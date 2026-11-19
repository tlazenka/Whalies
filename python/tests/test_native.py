import contextlib
import io
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from whaley_tools import cli, native


class NativeHeadersTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name) / "checkout with spaces"
        self.cache = self.root / "Scala" / "target" / "stb"
        self.contents = {name: (name + "\nfixture\n").encode() for name in native.STB_FILES}
        self.files = {name: native.blob_id(content) for name, content in self.contents.items()}
        for target, value in (("STB_FILES", self.files), ("SYSTEM_INCLUDES", ())):
            guard = patch.object(native, target, value)
            guard.start()
            self.addCleanup(guard.stop)
        guard = patch.dict(os.environ, {"WHALEY_NATIVE_INCLUDE": ""})
        guard.start()
        self.addCleanup(guard.stop)
        self.requests = []
        guard = patch.object(native.urllib.request, "urlopen", side_effect=self.download)
        self.opener = guard.start()
        self.addCleanup(guard.stop)

    def download(self, url, *, timeout):
        self.requests.append(url)
        self.assertIn(native.STB_REVISION, url)
        self.assertEqual(timeout, 60)
        return io.BytesIO(self.contents[url.rsplit("/", 1)[-1]])

    def populate(self, directory, names=None):
        directory.mkdir(parents=True, exist_ok=True)
        for name in (names if names is not None else self.contents):
            (directory / name).write_bytes(self.contents[name])

    def test_downloads_both_headers_and_license_then_reuses_cache_offline(self):
        self.assertEqual(native.prepare(self.root), [self.cache])
        self.assertEqual(len(self.requests), 3)
        self.opener.reset_mock()
        self.assertEqual(native.prepare(self.root, offline=True), [self.cache])
        self.opener.assert_not_called()

    def test_custom_include_paths_keep_order_spaces_and_precedence(self):
        first, second = self.root / "one path", self.root / "two path"
        self.populate(first, ["stb_image.h"])
        self.populate(second, ["stb_truetype.h"])
        os.environ["WHALEY_NATIVE_INCLUDE"] = os.pathsep.join(map(str, [first, second, first]))
        self.assertEqual(native.prepare(self.root, offline=True), [first, second])
        self.opener.assert_not_called()

    def test_relative_override_is_relative_to_scala_not_working_directory(self):
        custom = self.root / "Scala" / "custom"
        self.populate(custom)
        os.environ["WHALEY_NATIVE_INCLUDE"] = "custom"
        self.assertEqual(native.prepare(self.root, offline=True), [custom])
        self.opener.assert_not_called()

    def test_system_installation_needs_no_download(self):
        system = self.root / "system" / "stb"
        self.populate(system, native.HEADERS)
        with patch.object(native, "SYSTEM_INCLUDES", (system,)):
            self.assertEqual(native.prepare(self.root), [system])
        self.opener.assert_not_called()

    def test_partial_custom_installation_is_preserved_with_cache_fallback(self):
        custom = self.root / "custom"
        self.populate(custom, ["stb_image.h"])
        os.environ["WHALEY_NATIVE_INCLUDE"] = str(custom)
        self.assertEqual(native.prepare(self.root), [custom, self.cache])
        self.assertEqual((custom / "stb_image.h").read_bytes(), self.contents["stb_image.h"])

    def test_downloads_only_missing_or_invalid_files(self):
        self.populate(self.cache)
        (self.cache / "stb_image.h").write_bytes(b"incomplete")
        native.prepare(self.root)
        self.assertEqual(len(self.requests), 1)
        self.assertTrue(self.requests[0].endswith("/stb_image.h"))
        self.assertEqual((self.cache / "stb_image.h").read_bytes(), self.contents["stb_image.h"])

    def test_failed_download_does_not_replace_existing_files(self):
        self.populate(self.cache, ["stb_image.h"])
        original = (self.cache / "stb_image.h").read_bytes()
        self.opener.side_effect = [io.BytesIO(self.contents["stb_truetype.h"]), OSError("offline")]
        with self.assertRaisesRegex(RuntimeError, "WHALEY_NATIVE_INCLUDE"):
            native.prepare(self.root)
        self.assertEqual((self.cache / "stb_image.h").read_bytes(), original)
        self.assertFalse((self.cache / "stb_truetype.h").exists())
        self.assertEqual(list(self.cache.parent.iterdir()), [self.cache])

    def test_checksum_failure_leaves_no_partial_cache(self):
        self.opener.side_effect = lambda *args, **kwargs: io.BytesIO(b"wrong revision")
        with self.assertRaisesRegex(RuntimeError, "pinned Git blob"):
            native.prepare(self.root)
        self.assertFalse(self.cache.exists())
        self.assertEqual(list(self.cache.parent.iterdir()), [])

    def test_oversized_download_is_rejected(self):
        self.opener.side_effect = lambda *args, **kwargs: io.BytesIO(b"x" * 17)
        with patch.object(native, "MAX_DOWNLOAD_BYTES", 16):
            with self.assertRaisesRegex(RuntimeError, "pinned Git blob"):
                native.prepare(self.root)
        self.assertFalse(self.cache.exists())

    def test_offline_missing_headers_fails_without_network(self):
        with self.assertRaisesRegex(RuntimeError, "unavailable offline"):
            native.prepare(self.root, offline=True)
        self.opener.assert_not_called()
        self.assertFalse(self.cache.parent.exists())

    def test_deleted_cache_is_recreated_on_next_prepare(self):
        native.prepare(self.root)
        for path in self.cache.iterdir():
            path.unlink()
        self.cache.rmdir()
        self.requests.clear()
        self.assertEqual(native.prepare(self.root), [self.cache])
        self.assertEqual(len(self.requests), 3)

    def test_machine_output_has_only_complete_paths(self):
        args = cli.build_parser().parse_args(["native-deps", "--print-includes"])
        self.assertEqual(args.module, "whaley_tools.native")
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            self.assertEqual(native.run(args, self.root), 0)
        self.assertEqual(stdout.getvalue().splitlines(), [str(self.cache)])
        self.assertIn("Fetching pinned stb", stderr.getvalue())

    def test_cli_dispatches_the_command(self):
        (self.root / "Scala").mkdir(parents=True)
        (self.root / "Scala" / "build.sbt").touch()
        (self.root / "Sources" / "WhaleySpriteKit" / "Resources").mkdir(parents=True)
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(cli.main(["--root", str(self.root), "native-deps"]), 0)
            self.assertEqual(cli.main(["--root", str(self.root), "native-deps", "--offline"]), 0)
        self.assertEqual(len(self.requests), 3)

    def test_cli_exits_unsuccessfully_when_offline_and_unprepared(self):
        with patch.object(cli, "repository_root", return_value=self.root):
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(cli.main(["native-deps", "--offline"]), 1)
        self.opener.assert_not_called()


if __name__ == "__main__":
    unittest.main()
