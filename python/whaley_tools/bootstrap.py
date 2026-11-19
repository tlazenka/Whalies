"""Select a supported interpreter before importing the Python 3.10+ CLI."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from typing import Iterator, List, Optional

MINIMUM = (3, 10)
_REEXEC = "_WHALEY_PYTHON_REEXEC"
_PROBE = ("import sys; "
          "sys.stdout.write('whaley-python-ok' if sys.version_info >= (3, 10) else '')")


def candidates() -> Iterator[str]:
    explicit = os.environ.get("PYTHON")
    if explicit:
        yield explicit
        return
    directories = [Path(part) for part in os.get_exec_path() if part]
    if sys.platform == "darwin":
        directories += [Path("/opt/homebrew/bin"), Path("/usr/local/bin"),
                        Path("/Library/Frameworks/Python.framework/Versions/Current/bin")]
    seen = set()
    for directory in directories:
        directory = directory.absolute()
        if directory in seen:
            continue
        seen.add(directory)
        try:
            entries = list(directory.iterdir())
        except OSError:
            continue
        choices = []
        for entry in entries:
            match = re.fullmatch(r"python3(?:\.(\d+))?(?:\.exe)?", entry.name)
            if match and (match[1] is None or int(match[1]) >= MINIMUM[1]):
                choices.append((int(match[1]) if match[1] else 10000, entry))
        for _, entry in sorted(choices, key=lambda choice: (-choice[0], str(choice[1]))):
            yield str(entry)


def compatible_executable(candidate: str) -> Optional[str]:
    executable = shutil.which(os.path.expanduser(candidate))
    if not executable:
        return None
    executable = os.path.abspath(executable)
    try:
        result = subprocess.run(
            [executable, "-I", "-c", _PROBE], stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired, UnicodeError):
        return None
    return executable if result.returncode == 0 and result.stdout == "whaley-python-ok" else None


def main(argv: Optional[List[str]] = None) -> int:
    arguments = list(sys.argv[1:] if argv is None else argv)
    if sys.version_info >= MINIMUM:
        os.environ.pop(_REEXEC, None)
        # sbt and its asset-generation subprocesses must inherit this interpreter.
        os.environ["PYTHON"] = sys.executable
        from .cli import main as run
        return run(arguments)

    if not os.environ.get(_REEXEC):
        for candidate in candidates():
            executable = compatible_executable(candidate)
            if executable:
                environment = dict(os.environ, PYTHON=executable)
                environment[_REEXEC] = "1"
                launcher = str(Path(__file__).resolve().parent.parent / "whaley.py")
                print("whaley-tools: using " + executable + " (Python 3.10+)", file=sys.stderr)
                try:
                    os.execve(executable, [executable, launcher] + arguments, environment)
                except OSError as error:
                    print("error: whaley-tools: cannot start " + executable + ": " + str(error),
                          file=sys.stderr)
                    return 1

    version = ".".join(str(part) for part in sys.version_info[:3])
    explicit = os.environ.get("PYTHON")
    detail = (" PYTHON=" + repr(explicit) + " is not usable; no fallback was selected."
              if explicit else " No compatible interpreter was found.")
    print("error: whaley-tools requires Python 3.10 or newer; running " + version
          + " at " + sys.executable + "." + detail
          + " Install Python 3.10+ or set the Xcode PYTHON build setting"
          + " (PYTHON environment variable for terminal builds) to its executable.", file=sys.stderr)
    return 2
