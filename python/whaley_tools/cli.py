"""Command-line entry point shared by source and installed invocations."""
import argparse
import importlib
from pathlib import Path
import subprocess
import sys
import unittest

from . import __version__
from .paths import repository_root


def positive_int(value: str) -> int:
    number = int(value)
    if number <= 0:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return number


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="whaley-tools",
        description="Build, package, publish and verify a WhaleKart checkout.",
        epilog="From the repository root: python3 python/whaley.py COMMAND. No installation is required.",
    )
    parser.add_argument("--version", action="version", version=f"%(prog)s {__version__}")
    parser.add_argument("--root", type=Path, help="Use another WhaleKart checkout")
    commands = parser.add_subparsers(dest="command", required=True)

    assets = commands.add_parser("assets", help="Generate Scala data and stage original assets")
    assets.add_argument("--source-output", type=Path, help="Generated Scala source directory")
    assets.add_argument("--asset-output", type=Path, help="Staged image/audio directory")
    assets.set_defaults(module="whaley_tools.assets", command_parser=assets)

    web = commands.add_parser("web", help="Package or publish the Canvas game")
    web_commands = web.add_subparsers(dest="web_command", required=True)
    package = web_commands.add_parser("package", help="Build and package Pages or offline WebKit")
    package.add_argument("--target", choices=("pages", "webkit"), default="pages",
                         help="Select default destination and Pages metadata (default: pages)")
    package.add_argument("--output", type=Path,
                         help="Override the destination; relative paths use the current directory")
    package.add_argument("--skip-build", action="store_true", help="Use an already staged Scala/target/web")
    package.set_defaults(module="whaley_tools.web")
    publish = web_commands.add_parser("publish", help="Publish a checked static bundle to gh-pages")
    publish.add_argument("--site", type=Path, help="Prepared site (default: Scala/target/pages)")
    publish.add_argument("--remote", default="origin", help="Git remote name or URL (default: origin)")
    publish.set_defaults(module="whaley_tools.publish")

    sbt = commands.add_parser("sbt", help="Run the checksum-verified sbt launcher",
                              epilog="Use -- before sbt options, for example: sbt -- -batch check")
    sbt.add_argument("arguments", nargs=argparse.REMAINDER, help="Arguments forwarded unchanged to sbt")
    sbt.set_defaults(module="whaley_tools.sbt")

    native_deps = commands.add_parser("native-deps", help="Find or fetch pinned stb headers for Scala Native")
    native_deps.add_argument("--offline", action="store_true", help="Never download missing headers")
    native_deps.add_argument("--print-includes", action="store_true", help="Print one include directory per line")
    native_deps.set_defaults(module="whaley_tools.native")

    stadium = commands.add_parser("stadium", help="Run deterministic references and generate fixtures")
    models = stadium.add_subparsers(dest="model_command", required=True)
    math = models.add_parser("math", help="Check fixed-point math or print its sine table")
    math.add_argument("--check", action="store_true", help="Run arithmetic self-checks (default)")
    math.add_argument("--table", action="store_true", help="Print the Swift sine-table literal")
    math.set_defaults(module="whaley_tools.stadium.math")
    ballgame = models.add_parser("ballgame", help="Generate the season table and baseball replay fixtures")
    ballgame.add_argument("--table", type=Path, help="Write the Swift season table to this file")
    ballgame.add_argument("--fixtures", type=Path, help="Write season and baseball fixtures to this directory")
    ballgame.add_argument("--report", action="store_true", help="Print a replay report (default without output options)")
    ballgame.set_defaults(module="whaley_tools.stadium.ballgame")
    crowd = models.add_parser("crowd", help="Generate crowd, camera and aiming fixtures")
    crowd.add_argument("--fixtures", type=Path, help="Write crowd.json to this directory")
    crowd.add_argument("--report", action="store_true", help="Print the reference report (default)")
    crowd.set_defaults(module="whaley_tools.stadium.crowd")
    kart = models.add_parser("kart", help="Generate kart/rope fixtures or render a reference run")
    kart.add_argument("--fixtures", type=Path, help="Write ring-3600.json to this directory")
    kart.add_argument("--report", action="store_true", help="Print reference results (default)")
    kart.add_argument("--ascii", action="store_true", help="Print text frames of a reference run")
    kart.add_argument("--model", choices=("a", "b"), default="b", help="Rope model for text frames (default: b)")
    kart.add_argument("--every", type=positive_int, default=60, help="Ticks between text frames (default: 60)")
    kart.set_defaults(module="whaley_tools.stadium.kart")
    feed = models.add_parser("feed", help="Build the season Explorer document from checked-in CSVs")
    feed.add_argument("--write", action="store_true", help="Write ExplorerFeed.json beside the source CSVs")
    feed.add_argument("--check", action="store_true", help="Compare the saved feed to a fresh build")
    feed.add_argument("--summary", action="store_true", help="Print a summary (default)")
    feed.set_defaults(module="whaley_tools.stadium.feed")

    tests = commands.add_parser("test", help="Run Python regression tests")
    tests.add_argument("suite", nargs="?", default="all",
                       choices=("all", "assets", "web", "publish", "stadium", "cli", "native"))
    tests.add_argument("-v", "--verbose", action="store_true")
    tests.set_defaults(module=None)

    xcode = commands.add_parser("xcode", help="Helpers for native build scripts")
    native = xcode.add_subparsers(dest="xcode_command", required=True)
    simulator = native.add_parser("simulator", help="Read simctl JSON from stdin and print an available iPhone UDID")
    simulator.set_defaults(module="whaley_tools.xcode")
    return parser


def run_tests(args, root: Path) -> int:
    patterns = {
        "all": ("test_*.py",),
        "assets": ("test_assets.py",),
        "web": ("test_web.py", "test_webkit.py"),
        "publish": ("test_publish.py",),
        "stadium": ("test_stadium.py",),
        "cli": ("test_cli.py",),
        "native": ("test_native.py",),
    }
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    project = root / "python"
    tests = project / "tests"
    for pattern in patterns[args.suite]:
        suite.addTests(loader.discover(str(tests), pattern=pattern, top_level_dir=str(project)))
    if not suite.countTestCases():
        raise ValueError(f"No Python tests found for {args.suite} in {tests}")
    result = unittest.TextTestRunner(verbosity=2 if args.verbose else 1).run(suite)
    return 0 if result.wasSuccessful() else 1


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.module == "whaley_tools.assets" and not (args.source_output or args.asset_output):
        args.command_parser.error("specify --source-output or --asset-output")
    try:
        root = repository_root(args.root)
        if args.module is None:
            return run_tests(args, root)
        result = importlib.import_module(args.module).run(args, root)
        return 0 if result is None else result
    except subprocess.CalledProcessError as error:
        print(f"whaley-tools: command failed with exit status {error.returncode}", file=sys.stderr)
        return error.returncode if error.returncode > 0 else 1
    except (OSError, RuntimeError, ValueError) as error:
        print(f"whaley-tools: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130
