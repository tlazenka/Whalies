"""Fast, platform-independent packaging checks for the offline WebKit test app."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from whaley_tools.web import package, render_template


class BundleTests(unittest.TestCase):
    def test_twirl_page_remains_one_source_of_truth(self):
        with tempfile.TemporaryDirectory() as directory:
            template = Path(directory) / "index.scala.html"
            template.write_text(
                '@(gameName: String)\n<title>@gameName</title>\n'
                '<canvas id="game"></canvas>\n'
                '<script type="module">import("./assets/main.js")</script>\n',
                encoding="utf-8",
            )
            result = render_template(template)
            self.assertIn("Gray Whale", result)
            self.assertIn('import("./assets/main.js")', result)
            self.assertNotIn("@gameName", result)

    def test_stage_uses_exact_js_css_and_validates_original_assets(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            staged, destination = base / "staged", base / "app" / "WhaleyWebBundle"
            assets = staged / "assets"
            assets.mkdir(parents=True)
            (staged / "main.js").write_text("console.log('same Scala.js');")
            (staged / "styles.css").write_text("canvas { display:block }")
            image = b"original-image-fixture"
            (assets / "level1.png").write_bytes(image)
            (assets / "provenance.json").write_text(json.dumps({
                "level1.png": {"sha256": hashlib.sha256(image).hexdigest()}
            }))
            template = base / "index.scala.html"
            template.write_text("@(gameName: String)\n<title>@gameName</title>")
            # A checkout already has this tracked Xcode folder placeholder.
            destination.mkdir(parents=True)
            (destination / ".keep").write_bytes(b"")
            package(staged, destination, template, root=base)
            self.assertEqual((destination / ".keep").read_bytes(), b"")
            self.assertEqual((destination / "assets/main.js").read_text(),
                             "console.log('same Scala.js');")
            self.assertEqual((destination / "assets/level1.png").read_bytes(), image)
            self.assertEqual((destination / "index.html").read_text(), "<title>Gray Whale</title>")
            image_file = assets / "level1.png"
            image_file.write_bytes(b"tampered")
            with self.assertRaisesRegex(RuntimeError, "hash mismatch"):
                package(staged, destination, template, root=base)
            # A failure must never overwrite the previously good payload.
            self.assertEqual((destination / "assets/level1.png").read_bytes(), image)
            self.assertEqual((destination / ".keep").read_bytes(), b"")

    def test_missing_javascript_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            staged = Path(directory) / "staged"
            staged.mkdir()
            with self.assertRaisesRegex(RuntimeError, "Missing staged"):
                package(staged, Path(directory) / "output", Path(directory) / "template", root=Path(directory))
