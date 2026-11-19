"""Discover stb headers or cache the port's pinned upstream files."""
import hashlib
import os
from pathlib import Path
import sys
import tempfile
import urllib.request

STB_REVISION = "2c980bb59875b0d32144a71867fbdebb2f77cd20"
# Git blob IDs from that revision; verify the entire downloaded file, not just its name.
STB_FILES = {
    "stb_image.h": "9eedabedc45b3e6fd88fae6f14a160b4d53272ec",
    "stb_truetype.h": "90a5c2e2b3fe563c98585294ca7a949876aec94c",
    "LICENSE": "a77ae91f3ec0abb0028c9d9bd8d34d880b454d38",
}
HEADERS = ("stb_image.h", "stb_truetype.h")
SYSTEM_INCLUDES = tuple(map(Path, (
    "/usr/include/stb", "/usr/local/include/stb", "/opt/homebrew/include/stb",
    "/usr/include", "/usr/local/include", "/opt/homebrew/include",
)))
MAX_DOWNLOAD_BYTES = 2 * 1024 * 1024


def blob_id(content: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(content)).encode("ascii") + b"\0" + content).hexdigest()


def has_headers(paths: list[Path]) -> bool:
    return all(any((path / name).is_file() for path in paths) for name in HEADERS)


def valid_file(path: Path, expected: str) -> bool:
    return path.is_file() and blob_id(path.read_bytes()) == expected


def prepare(root: Path, *, offline: bool = False) -> list[Path]:
    scala = root.resolve() / "Scala"
    configured = []
    for entry in os.environ.get("WHALEY_NATIVE_INCLUDE", "").split(os.pathsep):
        if entry:
            path = Path(entry).expanduser()
            # sbt and Clang run from Scala/, including when invoked by root Make targets.
            path = (path if path.is_absolute() else scala / path).resolve()
            if path not in configured:
                configured.append(path)
    if has_headers(configured):
        return configured

    cache = scala / "target" / "stb"
    missing = [name for name, expected in STB_FILES.items()
               if not valid_file(cache / name, expected)]
    if not missing:
        return list(dict.fromkeys([*configured, cache]))

    system = [path for path in SYSTEM_INCLUDES if path.is_dir()]
    if has_headers([*configured, *system]):
        return list(dict.fromkeys([*configured, *system]))
    if offline:
        raise RuntimeError(
            "stb headers are unavailable offline. Run `python3 python/whaley.py native-deps` "
            "once online, or set WHALEY_NATIVE_INCLUDE to directories containing "
            "stb_image.h and stb_truetype.h."
        )

    cache.parent.mkdir(parents=True, exist_ok=True)
    try:
        # Verify every replacement before touching any existing cached file.
        with tempfile.TemporaryDirectory(prefix="stb-", dir=cache.parent) as staging:
            for name in missing:
                url = f"https://raw.githubusercontent.com/nothings/stb/{STB_REVISION}/{name}"
                print(f"Fetching pinned stb {name}", file=sys.stderr)
                with urllib.request.urlopen(url, timeout=60) as response:
                    content = response.read(MAX_DOWNLOAD_BYTES + 1)
                if len(content) > MAX_DOWNLOAD_BYTES or blob_id(content) != STB_FILES[name]:
                    raise RuntimeError(f"stb {name} does not match the pinned Git blob")
                (Path(staging) / name).write_bytes(content)
            cache.mkdir(parents=True, exist_ok=True)
            for name in missing:
                os.replace(Path(staging) / name, cache / name)
    except OSError as error:
        raise RuntimeError(
            "Could not prepare stb headers. Retry when online or set WHALEY_NATIVE_INCLUDE "
            "to an existing installation containing both headers. " + str(error)
        ) from error
    return list(dict.fromkeys([*configured, cache]))


def run(args, root: Path) -> int:
    paths = prepare(root, offline=args.offline)
    if args.print_includes:
        for path in paths:
            print(path)
    else:
        print("stb headers ready: " + os.pathsep.join(map(str, paths)))
    return 0
