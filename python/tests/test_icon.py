"""The source-sprite icon must keep the existing catalog contract and opaque PNGs."""
import json
from pathlib import Path
import struct
import unittest

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "Apps/Whaley/AppIcons.xcassets/AppIcon.appiconset"


class WhaleyIconTests(unittest.TestCase):
    def test_existing_icon_slots_are_complete(self):
        metadata = json.loads((CATALOG / "Contents.json").read_text())
        sizes = set()
        for entry in metadata["images"]:
            width, height = map(float, entry["size"].split("x"))
            scale = int(entry["scale"].rstrip("x"))
            expected = int(width * scale), int(height * scale)
            data = (CATALOG / entry["filename"]).read_bytes()
            self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
            self.assertEqual(data[12:16], b"IHDR")
            actual = struct.unpack(">II", data[16:24])
            self.assertEqual(actual, expected)
            self.assertEqual(entry["filename"], f"AppIcon-{actual[0]}.png")
            sizes.add(actual[0])
        self.assertEqual(sizes, {76, 120, 152, 167, 180, 1024})

    def test_icons_are_rgb_without_transparency(self):
        for path in CATALOG.glob("*.png"):
            with self.subTest(icon=path.name):
                data = path.read_bytes()
                self.assertEqual(data[24:26], bytes([8, 2]))
                offset = 8
                while offset < len(data):
                    length = struct.unpack(">I", data[offset:offset + 4])[0]
                    self.assertNotEqual(data[offset + 4:offset + 8], b"tRNS")
                    offset += length + 12
