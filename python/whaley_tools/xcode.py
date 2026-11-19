"""Select an available iPhone from simctl's JSON output."""
import json
from pathlib import Path
import sys


def select_simulator(document: dict) -> str:
    if not isinstance(document, dict) or not isinstance(document.get("devices"), dict):
        raise ValueError("Expected simctl JSON containing a devices object")
    for runtime, entries in document["devices"].items():
        if "iOS" not in runtime:
            continue
        for device in entries:
            if device.get("isAvailable") and "iPhone" in device["name"]:
                return device["udid"]
    raise RuntimeError("No available iPhone simulator. Install an iOS Simulator runtime in Xcode.")


def run(args, root: Path) -> int:
    print(select_simulator(json.load(sys.stdin)))
    return 0
