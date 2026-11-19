"""Static-host packaging contracts shared by Pages and the WebKit app."""
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import tempfile
import unittest
from unittest.mock import patch
from urllib.parse import urljoin

from whaley_tools import web as package_web


class AssetLinks(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "link" and attrs.get("rel") == "stylesheet":
            self.links.append(attrs["href"])


def files(directory):
    return {str(path.relative_to(directory)): path.read_bytes()
            for path in directory.rglob("*") if path.is_file()}


class StaticPackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.staged = self.base / "staged"
        self.output = self.base / "pages"
        self.assets = self.staged / "assets"
        self.assets.mkdir(parents=True)
        (self.staged / "chunks").mkdir()
        (self.staged / "main.js").write_text("import './chunks/game.js';\n")
        (self.staged / "styles.css").write_text("canvas { display:block }\n")
        (self.staged / "chunks/game.js").write_text("export const ready = true;\n")
        (self.staged / "chunks/game.js.map").write_text('{"version":3}\n')
        for name in ("level5.png", "level5-568h.png"):
            (self.assets / name).write_bytes(b"painting-fixture")
        (self.assets / "theme.mp3").write_bytes(b"audio-fixture")
        self.manifest = {
            name: {"sha256": hashlib.sha256((self.assets / name).read_bytes()).hexdigest()}
            for name in ("level5.png", "level5-568h.png", "theme.mp3")
        }
        self.write_manifest(self.manifest)
        self.template = self.base / "index.scala.html"
        self.template.write_text('@(gameName: String)\n<title>@gameName</title>\n')

    def write_manifest(self, value):
        (self.assets / "provenance.json").write_text(json.dumps(value))

    def package(self, *, pages=True):
        package_web.package(self.staged, self.output, self.template, root=self.base, pages=pages)

    def test_real_template_resolves_entry_assets_under_repository_path(self):
        html = package_web.render_template(Path(__file__).resolve().parents[2] / "Scala/server/app/views/index.scala.html")
        parser = AssetLinks()
        parser.feed(html)
        imports = re.findall(r"import\(['\"]([^'\"]+)['\"]\)", html)
        base = "https://example.test/chatgpt-WhaleKart/"
        self.assertEqual([urljoin(base, url) for url in parser.links + imports], [
            base + "assets/styles.css", base + "assets/main.js"
        ])
        self.assertNotIn("@gameName", html)

    def test_pages_and_webkit_keep_identical_asset_and_nested_module_bytes(self):
        self.package()
        webkit = self.base / "webkit"
        package_web.package(self.staged, webkit, self.template, root=self.base)
        self.assertEqual(files(self.output / "assets"), files(webkit / "assets"))
        for relative in ("main.js", "styles.css", "chunks/game.js", "chunks/game.js.map"):
            self.assertEqual((self.output / "assets" / relative).read_bytes(),
                             (self.staged / relative).read_bytes())
        for relative in ("level5.png", "level5-568h.png", "theme.mp3", "provenance.json"):
            self.assertEqual((self.output / "assets" / relative).read_bytes(),
                             (self.assets / relative).read_bytes())
        self.assertEqual((self.output / ".nojekyll").read_bytes(), b"")
        self.assertFalse((webkit / ".nojekyll").exists())

    def test_restage_removes_stale_modules_and_accepts_previous_webkit_layout(self):
        self.package()
        (self.output / package_web.MARKER).unlink()  # The previous WebKit layout.
        (self.staged / "chunks/game.js.map").unlink()
        self.package(pages=False)
        self.assertFalse((self.output / "assets/chunks/game.js.map").exists())
        self.assertFalse((self.output / ".nojekyll").exists())
        self.assertEqual((self.output / "assets/level5.png").read_bytes(), b"painting-fixture")

    def test_checkout_placeholder_survives_first_build_and_rebuild(self):
        for finder_metadata in (False, True):
            with self.subTest(finder_metadata=finder_metadata):
                destination = self.base / f"webkit-{finder_metadata}"
                destination.mkdir()
                (destination / ".keep").write_bytes(b"")
                if finder_metadata:
                    (destination / ".DS_Store").write_bytes(b"Finder metadata")
                package_web.package(self.staged, destination, self.template, root=self.base)
                self.assertEqual((destination / ".keep").read_bytes(), b"")
                (self.staged / "main.js").write_text("console.log('rebuilt');\n")
                package_web.package(self.staged, destination, self.template, root=self.base)
                self.assertEqual((destination / ".keep").read_bytes(), b"")
                self.assertEqual((destination / "assets/main.js").read_bytes(),
                                 (self.staged / "main.js").read_bytes())

    def test_legacy_bundle_accepts_checkout_placeholder_and_finder_metadata(self):
        self.package()
        (self.output / package_web.MARKER).unlink()
        (self.output / ".keep").write_bytes(b"")
        (self.output / ".DS_Store").write_bytes(b"Finder metadata")
        self.package(pages=False)
        self.assertEqual((self.output / ".keep").read_bytes(), b"")
        self.assertEqual((self.output / package_web.MARKER).read_text(), package_web.MARKER_CONTENT)

    def test_placeholder_does_not_authorize_unrelated_files(self):
        self.output.mkdir()
        (self.output / ".keep").write_bytes(b"")
        (self.output / ".DS_Store").write_bytes(b"Finder metadata")
        (self.output / "notes.txt").write_text("keep these notes")
        before = files(self.output)
        with self.assertRaisesRegex(RuntimeError, "Refusing to replace"):
            self.package()
        self.assertEqual(files(self.output), before)

    def test_placeholder_must_be_an_empty_regular_file(self):
        outside = self.base / "outside.txt"
        outside.write_bytes(b"")
        for kind in ("nonempty", "directory", "symlink"):
            with self.subTest(kind=kind):
                destination = self.base / kind
                destination.mkdir()
                placeholder = destination / ".keep"
                if kind == "nonempty":
                    placeholder.write_text("keep this content")
                elif kind == "directory":
                    placeholder.mkdir()
                else:
                    placeholder.symlink_to(outside)
                with self.assertRaisesRegex(RuntimeError, "Refusing to replace"):
                    package_web.package(self.staged, destination, self.template, root=self.base)
                self.assertEqual({path.name for path in destination.iterdir()}, {".keep"})
                if kind == "nonempty":
                    self.assertEqual(placeholder.read_text(), "keep this content")
                elif kind == "directory":
                    self.assertTrue(placeholder.is_dir())
                else:
                    self.assertTrue(placeholder.is_symlink())
        self.assertEqual(outside.read_bytes(), b"")

    def test_invalid_inputs_preserve_the_complete_previous_package(self):
        self.package()
        before = files(self.output)
        invalid = [[], {}, {"../outside": {"sha256": "0" * 64}},
                   {"level5.png": None}, {"level5.png": {"sha256": "0" * 64}}]
        for manifest in invalid:
            with self.subTest(manifest=manifest):
                self.write_manifest(manifest)
                with self.assertRaises(RuntimeError):
                    self.package()
                self.assertEqual(files(self.output), before)
        self.write_manifest(self.manifest)
        (self.staged / "main.js").write_bytes(b"")
        with self.assertRaisesRegex(RuntimeError, "main.js is empty"):
            self.package()
        self.assertEqual(files(self.output), before)

    def test_copy_and_install_failures_preserve_previous_output(self):
        self.package()
        before = files(self.output)
        with patch.object(package_web.shutil, "copy2", side_effect=OSError("copy interrupted")):
            with self.assertRaisesRegex(OSError, "copy interrupted"):
                self.package()
        self.assertEqual(files(self.output), before)
        rename = Path.rename

        def interrupt_install(source, target):
            if source.name == "bundle" and target == self.output:
                raise OSError("install interrupted")
            return rename(source, target)

        with patch.object(Path, "rename", interrupt_install):
            with self.assertRaisesRegex(OSError, "install interrupted"):
                self.package()
        self.assertEqual(files(self.output), before)

    def test_source_overlap_and_unrelated_destinations_are_rejected(self):
        source_before = files(self.staged)
        unrelated = self.base / "unrelated"
        unrelated.mkdir()
        (unrelated / "notes.txt").write_text("keep this")
        for destination in (self.staged, self.staged / "nested", self.base, unrelated):
            with self.subTest(destination=destination):
                with self.assertRaises(RuntimeError):
                    package_web.package(self.staged, destination, self.template, root=self.base)
        self.assertEqual(files(self.staged), source_before)
        self.assertEqual((unrelated / "notes.txt").read_text(), "keep this")

    def test_module_asset_collision_never_overwrites_original_art(self):
        self.package()
        before = files(self.output)
        (self.assets / "main.js").write_text("original asset")
        with self.assertRaisesRegex(RuntimeError, "paths overlap"):
            self.package()
        self.assertEqual(files(self.output), before)
