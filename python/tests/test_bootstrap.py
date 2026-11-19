"""Keep interpreter discovery outside the Python 3.10+ CLI import boundary."""
import ast
import contextlib
import importlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

from whaley_tools import bootstrap

PROJECT = Path(__file__).resolve().parents[1]


class Reexecuted(Exception):
    pass


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="whaley python ")
        self.addCleanup(temporary.cleanup)
        self.work = Path(temporary.name)
        self.environment = patch.dict(os.environ, {"PATH": str(self.work)}, clear=True)
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def legacy_main(self, arguments=None):
        output, error = io.StringIO(), io.StringIO()
        with patch.object(sys, "version_info", (3, 9, 6)):
            with contextlib.redirect_stdout(output), contextlib.redirect_stderr(error):
                status = bootstrap.main(arguments)
        return status, output.getvalue(), error.getvalue()

    def test_startup_sources_parse_with_python_39_grammar(self):
        for name in ("whaley.py", "whaley_tools/__init__.py", "whaley_tools/__main__.py",
                     "whaley_tools/bootstrap.py"):
            with self.subTest(name=name):
                ast.parse((PROJECT / name).read_text(), filename=name, feature_version=(3, 9))

    def test_import_does_not_import_cli(self):
        with patch.dict(sys.modules, {"whaley_tools.cli": None}):
            importlib.reload(bootstrap)

    def test_all_entry_points_use_bootstrap(self):
        self.assertIn("whaley_tools.bootstrap import main", (PROJECT / "whaley.py").read_text())
        self.assertIn(".bootstrap import main", (PROJECT / "whaley_tools/__main__.py").read_text())
        metadata = (PROJECT / "pyproject.toml").read_text()
        self.assertIn('whaley-tools = "whaley_tools.bootstrap:main"', metadata)
        self.assertIn('requires-python = ">=3.10"', metadata)

    def test_candidates_preserve_path_order_and_include_versioned_names(self):
        first, second = self.work / "first bin", self.work / "second bin"
        for directory in (first, second):
            directory.mkdir()
        for name in ("python3", "python3.9", "python3.10", "python3.12", "python3.12-config", "python2"):
            (first / name).touch()
        (second / "python3.14").touch()
        with patch.object(sys, "platform", "linux"), patch.object(os, "get_exec_path", return_value=[
                str(first), str(second), str(first), str(self.work / "missing")]):
            self.assertEqual(list(bootstrap.candidates()), [str(first / name) for name in
                             ("python3", "python3.12", "python3.10")] + [str(second / "python3.14")])

    def test_explicit_override_is_the_only_candidate(self):
        os.environ["PYTHON"] = "/custom python/bin/python3"
        with patch.object(os, "get_exec_path") as paths:
            self.assertEqual(list(bootstrap.candidates()), [os.environ["PYTHON"]])
            paths.assert_not_called()

    def test_mac_discovery_includes_homebrew_outside_xcode_path(self):
        expected = Path("/opt/homebrew/bin/python3.12")
        def entries(directory):
            return [expected] if directory == expected.parent else []
        with patch.object(sys, "platform", "darwin"), patch.object(os, "get_exec_path", return_value=[]):
            with patch.object(Path, "iterdir", entries):
                self.assertEqual(list(bootstrap.candidates()), [str(expected)])

    def test_inaccessible_directory_is_ignored(self):
        with patch.object(sys, "platform", "linux"), patch.object(Path, "iterdir", side_effect=PermissionError):
            self.assertEqual(list(bootstrap.candidates()), [])

    def test_probe_accepts_real_supported_interpreter(self):
        self.assertEqual(bootstrap.compatible_executable(sys.executable), os.path.abspath(sys.executable))

    def test_probe_does_not_consume_stdin_or_pollute_stdout(self):
        result = SimpleNamespace(returncode=0, stdout="whaley-python-ok")
        with patch.object(shutil, "which", return_value="/Python with spaces/bin/python3"):
            with patch.object(subprocess, "run", return_value=result) as run:
                self.assertEqual(bootstrap.compatible_executable("custom"), "/Python with spaces/bin/python3")
        args, kwargs = run.call_args
        self.assertEqual(args[0][:3], ["/Python with spaces/bin/python3", "-I", "-c"])
        self.assertEqual(kwargs["stdin"], subprocess.DEVNULL)
        self.assertEqual(kwargs["stdout"], subprocess.PIPE)
        self.assertEqual(kwargs["stderr"], subprocess.DEVNULL)
        self.assertEqual(kwargs["timeout"], 5)

    def test_probe_rejects_missing_old_or_unrelated_executables(self):
        with patch.object(shutil, "which", return_value=None), patch.object(subprocess, "run") as run:
            self.assertIsNone(bootstrap.compatible_executable("missing"))
            run.assert_not_called()
        for code, output in ((0, ""), (1, "whaley-python-ok"), (0, "unrelated")):
            with self.subTest(code=code, output=output):
                with patch.object(shutil, "which", return_value=sys.executable):
                    with patch.object(subprocess, "run", return_value=SimpleNamespace(returncode=code, stdout=output)):
                        self.assertIsNone(bootstrap.compatible_executable("candidate"))

    def test_probe_handles_broken_executables_and_timeouts(self):
        for failure in (OSError("broken"), subprocess.TimeoutExpired("python", 5), UnicodeError("bad output")):
            with self.subTest(failure=failure), patch.object(shutil, "which", return_value=sys.executable):
                with patch.object(subprocess, "run", side_effect=failure):
                    self.assertIsNone(bootstrap.compatible_executable("candidate"))

    def test_supported_runtime_stays_and_exports_python_for_nested_builds(self):
        run = Mock(return_value=23)
        os.environ[bootstrap._REEXEC] = "1"
        with patch.dict(sys.modules, {"whaley_tools.cli": SimpleNamespace(main=run)}):
            with patch.object(bootstrap, "candidates") as candidates:
                self.assertEqual(bootstrap.main(["web", "package", "--target", "webkit"]), 23)
        run.assert_called_once_with(["web", "package", "--target", "webkit"])
        candidates.assert_not_called()
        self.assertEqual(os.environ["PYTHON"], sys.executable)
        self.assertNotIn(bootstrap._REEXEC, os.environ)

    def test_default_arguments_are_forwarded_without_mutation(self):
        argv = ["whaley", "--root", "checkout with spaces", "--help"]
        run = Mock(return_value=0)
        with patch.object(sys, "argv", argv), patch.dict(sys.modules, {"whaley_tools.cli": SimpleNamespace(main=run)}):
            self.assertEqual(bootstrap.main(), 0)
        run.assert_called_once_with(argv[1:])
        self.assertEqual(argv[0], "whaley")

    def test_unsupported_runtime_fails_before_cli_import_with_actionable_error(self):
        with patch.object(bootstrap, "candidates", return_value=iter([])):
            with patch.dict(sys.modules, {"whaley_tools.cli": None}):
                status, output, error = self.legacy_main(["--help"])
        self.assertEqual(status, 2)
        self.assertEqual(output, "")
        for message in ("requires Python 3.10", "3.9.6", sys.executable, "Xcode PYTHON build setting"):
            self.assertIn(message, error)
        self.assertNotIn("Traceback", error)

    def test_incompatible_explicit_override_does_not_fall_back(self):
        os.environ["PYTHON"] = "/old python"
        with patch.object(bootstrap, "compatible_executable", return_value=None) as probe:
            status, output, error = self.legacy_main([])
        self.assertEqual(status, 2)
        probe.assert_called_once_with("/old python")
        self.assertEqual(output, "")
        self.assertIn("no fallback was selected", error)

    def test_reexecution_preserves_arguments_and_environment(self):
        os.environ.update(PYTHON="/new python", JAVA_HOME="/Java Home", CUSTOM_SETTING="preserved")
        arguments = ["--root", "/checkout with spaces", "sbt", "--", 'set x := "two words"']
        with patch.object(bootstrap, "compatible_executable", return_value="/new python"):
            with patch.object(os, "execve", side_effect=Reexecuted) as execute:
                with self.assertRaises(Reexecuted):
                    self.legacy_main(arguments)
        executable, argv, environment = execute.call_args.args
        self.assertEqual(executable, "/new python")
        self.assertEqual(argv, [executable, str(PROJECT / "whaley.py")] + arguments)
        self.assertEqual(environment["PYTHON"], executable)
        self.assertEqual(environment[bootstrap._REEXEC], "1")
        self.assertEqual(environment["JAVA_HOME"], "/Java Home")
        self.assertEqual(environment["CUSTOM_SETTING"], "preserved")

    def test_failed_reexecution_reports_error_without_traceback(self):
        os.environ["PYTHON"] = "/new python"
        with patch.object(bootstrap, "compatible_executable", return_value="/new python"):
            with patch.object(os, "execve", side_effect=PermissionError("denied")):
                status, output, error = self.legacy_main([])
        self.assertEqual(status, 1)
        self.assertEqual(output, "")
        self.assertIn("cannot start /new python", error)
        self.assertNotIn("Traceback", error)

    def test_reexecution_guard_prevents_loops(self):
        os.environ[bootstrap._REEXEC] = "1"
        with patch.object(bootstrap, "candidates") as candidates:
            status, output, error = self.legacy_main([])
        self.assertEqual(status, 2)
        candidates.assert_not_called()
        self.assertEqual(output, "")
        self.assertIn("requires Python 3.10", error)

    def test_real_reexecution_preserves_stdin_cwd_exit_code_and_argument_boundaries(self):
        project = self.work / "checkout with spaces" / "python"
        package = project / "whaley_tools"
        package.mkdir(parents=True)
        for name in ("whaley.py", "whaley_tools/__init__.py", "whaley_tools/__main__.py",
                     "whaley_tools/bootstrap.py"):
            shutil.copyfile(PROJECT / name, project / name)
        (package / "cli.py").write_text('''import json, os, sys
if sys.version_info < (3, 10):
    raise AssertionError("CLI imported before selecting a supported interpreter")
def main(argv):
    print(json.dumps(dict(argv=argv, cwd=os.getcwd(), stdin=sys.stdin.read(),
                         python=os.environ["PYTHON"], executable=sys.executable,
                         loop_guard="_WHALEY_PYTHON_REEXEC" in os.environ)))
    return 37
''')
        environment = dict(os.environ, PYTHON=sys.executable)
        arguments = ["--root", "a checkout", "sbt", "--", 'set x := "two words"']
        for module in (False, True):
            with self.subTest(module=module):
                code = ("import sys, runpy; sys.version_info=(3,9,6); "
                        + "sys.path.insert(0, " + repr(str(project)) + "); "
                        + "sys.argv=" + repr([str(project / "whaley.py")] + arguments) + "; "
                        + ("runpy.run_module('whaley_tools', run_name='__main__')" if module else
                           "runpy.run_path(" + repr(str(project / "whaley.py")) + ", run_name='__main__')"))
                result = subprocess.run([sys.executable, "-c", code], env=environment, cwd=self.work,
                                        input="piped simulator data", text=True, capture_output=True, timeout=15)
                self.assertEqual(result.returncode, 37, result.stderr)
                payload = json.loads(result.stdout)
                self.assertEqual(payload["argv"], arguments)
                self.assertEqual(payload["cwd"], str(self.work))
                self.assertEqual(payload["stdin"], "piped simulator data")
                self.assertEqual(payload["python"], payload["executable"])
                self.assertFalse(payload["loop_guard"])
                self.assertIn("whaley-tools: using", result.stderr)
                self.assertNotIn("Traceback", result.stderr)


if __name__ == "__main__":
    unittest.main()
