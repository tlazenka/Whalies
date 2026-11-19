"""Exercise the shared CLI at process, checkout and build boundaries."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from whaley_tools import __version__, cli, paths, sbt

ROOT = Path(__file__).resolve().parents[2]
ENTRY = ROOT / "python/whaley.py"


class CommandLineTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="whaley cli ")
        self.addCleanup(self.temporary.cleanup)
        self.work = Path(self.temporary.name)

    def invoke(self, *arguments, input=None):
        return subprocess.run(
            [sys.executable, str(ENTRY), *(str(value) for value in arguments)],
            cwd=self.work, input=input, text=True, capture_output=True,
        )

    def staged_checkout(self):
        root = self.work / "another checkout"
        (root / "Sources/WhaleySpriteKit/Resources").mkdir(parents=True)
        (root / "Scala").mkdir()
        (root / "Scala/build.sbt").write_text("// fixture\n", encoding="utf-8")
        template = root / "Scala/server/app/views/index.scala.html"
        template.parent.mkdir(parents=True)
        template.write_text('@(gameName: String)\n<title>@gameName</title>\n', encoding="utf-8")
        staged = root / "Scala/target/web"
        assets = staged / "assets"
        assets.mkdir(parents=True)
        data = b"unchanged original bytes"
        (assets / "painting.png").write_bytes(data)
        (assets / "provenance.json").write_text(json.dumps({
            "painting.png": {"source": "Sources/WhaleySpriteKit/Resources/painting.png",
                             "sha256": hashlib.sha256(data).hexdigest()},
        }), encoding="utf-8")
        (staged / "main.js").write_text("export const game = true;\n", encoding="utf-8")
        (staged / "styles.css").write_text("canvas {}\n", encoding="utf-8")
        return root

    def test_help_and_version_from_an_unrelated_directory(self):
        for command in ((), ("assets",), ("web", "package"), ("web", "publish"),
                        ("sbt",), ("stadium", "ballgame"), ("test",), ("xcode", "simulator")):
            with self.subTest(command=command):
                result = self.invoke(*command, "--help")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("usage:", result.stdout)
        self.assertEqual(self.invoke("--version").stdout.strip(), f"whaley-tools {__version__}")
        self.assertEqual(list(self.work.iterdir()), [])

    def test_assets_use_source_checkout_and_caller_relative_outputs(self):
        result = self.invoke("assets", "--source-output", "generated", "--asset-output", "staged")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual({file.name for file in (self.work / "generated").iterdir()},
                         {"LevelData.scala", "SpriteData.scala", "PresentationData.scala", "GalleryData.scala"})
        manifest = json.loads((self.work / "staged/provenance.json").read_text(encoding="utf-8"))
        self.assertIn("level5-568h.png", manifest)
        for name, metadata in manifest.items():
            original = (ROOT / metadata["source"]).read_bytes()
            self.assertEqual((self.work / "staged" / name).read_bytes(), original)
            self.assertEqual(metadata["sha256"], hashlib.sha256(original).hexdigest())

    def test_web_targets_use_selected_checkout_and_preserve_placeholders(self):
        root = self.staged_checkout()
        webkit = root / "Apps/WhaleyWebBundle"
        webkit.mkdir(parents=True)
        (webkit / ".keep").touch()
        for target, destination in (("pages", root / "Scala/target/pages"), ("webkit", webkit)):
            with self.subTest(target=target):
                result = self.invoke("--root", root, "web", "package", "--target", target, "--skip-build")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual((destination / "assets/painting.png").read_bytes(), b"unchanged original bytes")
                self.assertEqual((destination / ".nojekyll").exists(), target == "pages")
        self.assertTrue((webkit / ".keep").is_file())
        result = self.invoke("--root", root, "web", "package", "--skip-build", "--output", "custom output")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.work / "custom output/index.html").is_file())

    def test_invalid_arguments_and_checkouts_fail_without_writing(self):
        for arguments in (("assets",), ("web", "package", "--target", "unknown"),
                          ("stadium", "kart", "--ascii", "--every", "0"),
                          ("stadium", "feed", "--unknown")):
            with self.subTest(arguments=arguments):
                result = self.invoke(*arguments)
                self.assertEqual(result.returncode, 2, result.stderr)
        result = self.invoke("--root", self.work, "assets", "--asset-output", "missing")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Not a WhaleKart checkout", result.stderr)
        self.assertEqual(list(self.work.iterdir()), [])

    def test_installed_layout_uses_working_checkout_instead_of_venv_ancestor(self):
        working = self.staged_checkout()
        installed = self.work / "checkout owning venv"
        (installed / "Scala").mkdir(parents=True)
        (installed / "Scala/build.sbt").touch()
        (installed / "Sources/WhaleySpriteKit/Resources").mkdir(parents=True)
        module = installed / ".venv/lib/python3.12/site-packages/whaley_tools/paths.py"
        with patch.object(paths, "__file__", str(module)), patch.object(Path, "cwd", return_value=working / "Scala"):
            self.assertEqual(paths.repository_root(), working)
            self.assertEqual(paths.repository_root(installed), installed)

    def test_simulator_selection_reads_stdin_and_reports_missing_runtime(self):
        devices = {"devices": {
            "com.apple.CoreSimulator.SimRuntime.tvOS": [
                {"name": "iPhone fixture", "udid": "wrong-runtime", "isAvailable": True}],
            "com.apple.CoreSimulator.SimRuntime.iOS": [
                {"name": "iPhone unavailable", "udid": "unavailable", "isAvailable": False},
                {"name": "iPad", "udid": "tablet", "isAvailable": True},
                {"name": "iPhone", "udid": "selected", "isAvailable": True}],
        }}
        result = self.invoke("xcode", "simulator", input=json.dumps(devices))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "selected\n")
        for document in ('{"devices": {}}', '{invalid', '[]'):
            with self.subTest(document=document):
                result = self.invoke("xcode", "simulator", input=document)
                self.assertEqual(result.returncode, 1)
                self.assertTrue(result.stderr)
                self.assertNotIn("Traceback", result.stderr)

    def test_sbt_forwarding_and_web_build_failure_preserve_exit_status(self):
        arguments = ["-batch", "set Compile / scalacOptions += \"-feature\"", "web/stage"]
        with patch.object(sbt, "launch", return_value=23) as launch:
            self.assertEqual(cli.main(["--root", str(ROOT), "sbt", "--", *arguments]), 23)
            launch.assert_called_once_with(ROOT, arguments)
        root = self.staged_checkout()
        with patch.object(sbt, "launch", return_value=17) as launch:
            self.assertEqual(cli.main(["--root", str(root), "web", "package"]), 17)
            launch.assert_called_once_with(root, ["web/stage"])
        self.assertFalse((root / "Scala/target/pages").exists())

    def test_launcher_verifies_cached_bytes_before_starting_java(self):
        jar = self.work / "Scala/target/tools" / f"sbt-launch-{sbt.VERSION}.jar"
        jar.parent.mkdir(parents=True)
        jar.write_bytes(b"untrusted cached jar")
        with patch.object(sbt.subprocess, "call") as child:
            with self.assertRaisesRegex(RuntimeError, "checksum"):
                sbt.launch(self.work, ["check"])
            child.assert_not_called()

    def test_launcher_preserves_java_option_and_path_boundaries(self):
        jar = self.work / "Scala/target/tools" / f"sbt-launch-{sbt.VERSION}.jar"
        jar.parent.mkdir(parents=True)
        content = b"verified launcher fixture"
        jar.write_bytes(content)
        java_home = self.work / "Java Home"
        environment = {"JAVA_HOME": str(java_home), "WHALEY_JAVA_OPTS": '-Xmx1G "-Dlabel=two words"'}
        with patch.dict(os.environ, environment), patch.object(sbt, "SHA256", hashlib.sha256(content).hexdigest()):
            with patch.object(sbt.subprocess, "call", return_value=19) as child:
                self.assertEqual(sbt.launch(self.work, ["testOnly example.Suite"]), 19)
        child.assert_called_once_with([
            str(java_home / "bin/java"), "-Xmx1G", "-Dlabel=two words", "-Dsbt.supershell=false",
            "-Dsbt.server.autostart=false", "-jar", str(jar), "testOnly example.Suite",
        ], cwd=self.work / "Scala")
