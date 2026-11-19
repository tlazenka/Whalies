from argparse import Namespace
import base64
import gzip
import hashlib
import json
import os
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

from whaley_tools.assets import decode_layer, run, stage_assets
from whaley_tools.presentation import image_size, jpeg_size, painting_name, read_font, read_visual_level, read_scene_images, resource, make_presentation_source, make_gallery_source

# Exact Background payload in level2-568h.tmx at a14a144. It is deliberately
# decoded independently of the collision Meta layer for the regression.
LEVEL2_BACKGROUND = (
    "H4sIAAAAAAAAA+2Z4Q6FIAiFrfd/6Lv7o80xgUOIYuNsrLyhUHxZ3q7G6+osWtfAJN/Rvrc9ygGxHYqKveIazBgPYSQju7TfrHZE3e7OZqrYzccu3Uf6zWq/rVkUn4hm12clu1I8yxiPaA1WcOuRlh/CrseyCH0GaOfwlXn3C7Kc36nc9uJyu8nxjOxa/bPWgGpVnidzy4k+RzOx25o+xqy4q9/rLrKl+1Exv8Kuxu1udpH+aNwd642RKLMouxm4QtZu6PrOsw4c9ZHqz70PR7CL+p00h3DMcuyO5g1k/L7tqVWWe52KW29nmXcRnzdxLff6bTQp134r/W5h19KOqtVqadf5FHZpPqP8dopjVjqegd3d142T9v9mVnYj4/796BzqiaUxK/llYffpu/PbRC8kfgZ2kZykuVaLq9XcK8s9Q/2zsZtB6PekjOdgZbc1OfdodlFlZxepP/rO/1aWMU9jt6ysrKysrKzMaz+2407ZfC4AAA=="
)


def png_header(path, width, height):
    # The generator only reads IHDR; actual image decoding is renderer-tested.
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + b"\x00\x00\x00\rIHDR" + struct.pack(">II", width, height))


def jpeg_header(path, width, height, progressive=False):
    # Header-only fixtures, just like png_header. Include APP metadata and a
    # fill byte so dimensions are not accidentally read at a fixed offset.
    metadata = b"painting metadata"
    frame = struct.pack(">BHHB", 8, height, width, 3) + b"\x01\x11\x00\x02\x11\x01\x03\x11\x01"
    path.write_bytes(b"\xff\xd8\xff\xe1" + struct.pack(">H", len(metadata) + 2) + metadata
                     + bytes((0xFF, 0xFF, 0xC2 if progressive else 0xC0))
                     + struct.pack(">H", len(frame) + 2) + frame + b"\xff\xd9")


class PresentationAssetsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.resources = self.root / "Resources"
        self.legacy = self.root / "Apps" / "Whaley2010" / "Resources"
        self.resources.mkdir()
        self.legacy.mkdir(parents=True)
        png_header(self.resources / "tileset.png", 70, 36)
        png_header(self.resources / "other.png", 36, 36)
        png_header(self.legacy / "game_font.png", 512, 512)

    def level(self, values=(1, 0, 2, 0), extra=""):
        payload = base64.b64encode(gzip.compress(struct.pack(f"<{len(values)}I", *values))).decode()
        source = f'''<map orientation="orthogonal" width="2" height="2" tilewidth="32" tileheight="32">
        <tileset firstgid="1" tilewidth="32" tileheight="32" margin="2" spacing="2">
          <image source="tileset.png"/></tileset>{extra}
        <layer name="Background" width="2" height="2"><data encoding="base64" compression="gzip">{payload}</data></layer>
        <layer name="Meta" width="2" height="2"><data encoding="csv">0,0,0,0</data></layer></map>'''
        (self.resources / "level1-568h.tmx").write_text(source)

    def font(self):
        path = self.legacy / "game_font.fnt"
        path.write_text('''info face="PressStartK" size=16
common lineHeight=16 base=26 scaleW=512 scaleH=512 pages=1
page id=0 file="game_font.png"
char id=32 x=0 y=0 width=0 height=0 xoffset=0 yoffset=14 xadvance=16 page=0
char id=33 x=191 y=0 width=9 height=15 xoffset=4 yoffset=0 xadvance=16 page=0
char id=65 x=0 y=17 width=15 height=15 xoffset=0 yoffset=0 xadvance=16 page=0
kerning first=65 second=65 amount=-1
''')
        return path

    def painting(self, number, tall=True):
        name = painting_name(number, tall)
        size = (320, 568 if tall else 480)
        png_header(self.resources / name, *size)
        return name, size

    def test_jpeg_dimensions_preserve_baseline_progressive_and_odd_width_sources(self):
        for name, expected, progressive in (
                ("baseline.jpg", (500, 671), False),
                ("progressive.jpg", (1420, 2048), True),
                ("odd-width.jpg", (1163, 2048), False)):
            jpeg_header(self.resources / name, *expected, progressive=progressive)
            self.assertEqual(jpeg_size(self.resources / name), expected)
            self.assertEqual(image_size(self.resources / name), expected)

    def test_malformed_jpeg_headers_fail_instead_of_inventing_a_crop(self):
        path = self.resources / "broken.jpg"
        jpeg_header(path, 1163, 2048)
        valid = path.read_bytes()
        malformed = {
            "not JPEG": b"not an image",
            "missing frame": b"\xff\xd8\xff\xd9",
            "scan before frame": b"\xff\xd8\xff\xda",
            "truncated marker": b"\xff\xd8\xff",
            "missing segment length": b"\xff\xd8\xff\xe1\x00",
            "invalid segment length": b"\xff\xd8\xff\xe1\x00\x01",
            "truncated metadata": b"\xff\xd8\xff\xe1\x00\x10short",
            "truncated frame": valid[:-4],
            "stuffed byte before scan": b"\xff\xd8\xff\x00",
            "restart before scan": b"\xff\xd8\xff\xd0",
        }
        for reason, content in malformed.items():
            with self.subTest(reason=reason):
                path.write_bytes(content)
                with self.assertRaises(ValueError):
                    jpeg_size(path)
        for width, height in ((0, 100), (100, 0)):
            jpeg_header(path, width, height)
            with self.assertRaises(ValueError):
                jpeg_size(path)

    def test_actual_level_two_background_counts(self):
        layer = ET.fromstring(f'<layer><data encoding="base64" compression="gzip">{LEVEL2_BACKGROUND}</data></layer>')
        values = decode_layer(layer, 175 * 17, preserve_flags=True)
        self.assertEqual((values.count(0), values.count(1), values.count(2)), (1695, 1221, 59))
        self.assertEqual(sum(v != 0 for v in values), 1280)

    def test_visuals_are_background_not_collision_cells(self):
        self.level()
        data = read_visual_level(1, self.resources, self.legacy, decode_layer)
        self.assertEqual(data["cells"], [(0, 1, 1), (0, 0, 2)])
        self.assertEqual(data["definitions"][1], ("tileset.png", (2, 2, 32, 32)))
        self.assertEqual(data["definitions"][2], ("tileset.png", (36, 2, 32, 32)))

    def test_tileset_selected_by_gid_not_first_image(self):
        self.level((1, 3, 0, 0), '<tileset firstgid="3" tilewidth="32" tileheight="32" margin="2"><image source="other.png"/></tileset>')
        data = read_visual_level(1, self.resources, self.legacy, decode_layer)
        self.assertEqual(data["definitions"][3], ("other.png", (2, 2, 32, 32)))

    def test_missing_image_is_error_not_empty_level(self):
        self.level()
        (self.resources / "tileset.png").unlink()
        with self.assertRaises(FileNotFoundError):
            read_visual_level(1, self.resources, self.legacy, decode_layer)

    def test_invalid_gid_and_flags_are_not_silently_rendered(self):
        for invalid in (3, 0x80000001):
            with self.subTest(invalid=invalid):
                self.level((invalid, 0, 0, 0))
                with self.assertRaises(ValueError):
                    read_visual_level(1, self.resources, self.legacy, decode_layer)

    def test_decode_preserves_flags_for_visual_validation(self):
        layer = ET.fromstring('<layer><data encoding="csv">2147483649</data></layer>')
        self.assertEqual(decode_layer(layer, 1), [1])
        self.assertEqual(decode_layer(layer, 1, preserve_flags=True), [0x80000001])

    def test_original_font_metrics_and_space_are_retained(self):
        font = read_font(self.font(), self.resources, self.legacy)
        self.assertEqual(font["glyphs"][33], (191, 0, 9, 15, 4, 0, 16))
        self.assertEqual(font["glyphs"][32][-1], 16)
        self.assertEqual(font["kernings"][(65, 65)], -1)
        self.assertEqual(font["height"], 16)

    def test_font_png_dimensions_are_validated(self):
        font = self.font()
        png_header(self.legacy / "game_font.png", 256, 256)
        with self.assertRaises(ValueError):
            read_font(font, self.resources, self.legacy)

    def test_apps_fallback_and_source_priority(self):
        self.font()
        self.assertEqual(resource("game_font.fnt", self.resources, self.legacy).parent, self.legacy)
        (self.resources / "game_font.fnt").write_text("override")
        self.assertEqual(resource("game_font.fnt", self.resources, self.legacy).parent, self.resources)
        with self.assertRaises(ValueError):
            resource("../secret", self.resources, self.legacy)

    def test_complete_generation_is_deterministic_and_carries_frame_offsets(self):
        self.level()
        for number in range(2, 7):
            (self.resources / f"level{number}-568h.tmx").write_bytes((self.resources / "level1-568h.tmx").read_bytes())
        for number in range(1, 7):
            self.painting(number)
        png_header(self.resources / "scanlines-568h.png", 320, 568)
        self.font()
        png_header(self.resources / "spout.png", 1024, 1024)
        frames = {f"spout{i}.png": dict(x=1+(i-1)*33, y=1, width=32, height=12+i*5,
                   originalWidth=32, originalHeight=32, offsetX=0, offsetY=(12+i*5-32)/2)
                  for i in range(1, 5)}
        (self.resources / "spout.plist").write_bytes(plistlib.dumps({"frames": frames}))
        expressions = ("whaley-expressions.png", "whaley-win-expressions.png")
        for name in expressions:
            png_header(self.resources / name, 864, 352)
        first = make_presentation_source(self.resources, self.legacy, decode_layer)
        self.assertEqual(first, make_presentation_source(self.resources, self.legacy, decode_layer))
        source, images = first
        self.assertIn("val whalelandArt: Boolean = true", source)
        self.assertIn('BitmapGlyph(Rect(191.0, 0.0, 9.0, 15.0), 4.0, 0.0, 16.0)', source)
        self.assertIn('Vec2(32.0, 32.0), Vec2(0.0, -7.5)', source)
        self.assertIn("tileset.png", images)
        self.assertIn("game_font.png", images)
        self.assertNotIn("meta_tileset.png", images)
        self.assertIn('TileArt("level2-568h.png", Rect(0.0, 0.0, 320.0, 568.0))', source)
        self.assertIn('Some(TileArt("scanlines-568h.png", Rect(0.0, 0.0, 320.0, 568.0)))', source)
        self.assertIn("scanlines-568h.png", images)
        for number in range(1, 7):
            self.assertIn(painting_name(number, tall=True), images)
        self.assertNotIn("level2.jpg", images)

        self.assertEqual(first, make_presentation_source(
            self.resources, self.legacy, decode_layer, whaleland_art=True))
        original_source, original_images = make_presentation_source(
            self.resources, self.legacy, decode_layer, whaleland_art=False)
        self.assertIn("val whalelandArt: Boolean = false", original_source)
        self.assertEqual(original_images, images)
        self.assertNotIn("retired-expressions.png", images)
        for name in expressions:
            self.assertIn(name, images)
            self.assertIn(f'"{name}"', original_source)
            for study in (False, True):
                (self.resources / name).unlink()
                with self.assertRaises(FileNotFoundError):
                    make_presentation_source(self.resources, self.legacy, decode_layer, whaleland_art=study)
                for dimensions in ((288, 352), (864, 416)):
                    png_header(self.resources / name, *dimensions)
                    with self.assertRaisesRegex(ValueError, "Expression atlas"):
                        make_presentation_source(self.resources, self.legacy, decode_layer, whaleland_art=study)
                png_header(self.resources / name, 864, 352)

    def test_scene_art_is_full_height_and_scanlines_only_cover_original_dry_levels(self):
        png_header(self.resources / "scanlines-568h.png", 320, 568)
        for number in range(1, 7):
            name, size = self.painting(number)
            painting, scanlines, images = read_scene_images(number, self.resources, self.legacy)
            self.assertEqual(painting, name)
            self.assertEqual(images[name], (0, 0, *size))
            self.assertEqual(scanlines, "scanlines-568h.png" if number in (1, 2) else None)

    def test_scene_art_rejects_missing_painting_and_wrong_surface_variant(self):
        with self.assertRaises(FileNotFoundError):
            read_scene_images(4, self.resources, self.legacy)
        png_header(self.resources / "level4-568h.png", 320, 480)
        with self.assertRaises(ValueError):
            read_scene_images(4, self.resources, self.legacy)
        png_header(self.resources / "level4-568h.png", 320, 568)
        self.assertEqual(read_scene_images(4, self.resources, self.legacy)[1], None)

    def test_scene_art_never_falls_back_to_retired_jpeg_and_scanlines_stay_validated(self):
        jpeg_header(self.resources / "level2.jpg", 500, 671)
        png_header(self.resources / "scanlines-568h.png", 320, 568)
        with self.assertRaises(FileNotFoundError):
            read_scene_images(2, self.resources, self.legacy)
        self.painting(2)
        png_header(self.resources / "scanlines-568h.png", 320, 480)
        with self.assertRaises(ValueError):
            read_scene_images(2, self.resources, self.legacy)

    def gallery_resources(self):
        source = self.font().read_text().replace("lineHeight=16", "lineHeight=109")
        for suffix in ("", "2"):
            page = f"title_font{suffix}.png"
            (self.legacy / f"title_font{suffix}.fnt").write_text(source.replace("game_font.png", page))
            png_header(self.legacy / page, 512, 512)
        for name, width, height in (("Default-568h@2x.png", 320, 568), ("frame.png", 344, 514),
                                    ("bubble01.png", 128, 128), ("dust.png", 8, 8)):
            png_header(self.resources / name, width, height)
        for index in range(1, 7):
            self.painting(index, tall=False)
            self.painting(index, tall=True)

    def test_gallery_stages_both_title_fonts_and_standard_tall_painting_pairs(self):
        self.gallery_resources()
        source, images = make_gallery_source(self.resources, self.legacy)
        self.assertEqual((source, images), make_gallery_source(self.resources, self.legacy))
        self.assertIn('grayFont: BitmapFont = BitmapFont("title_font.png", 109.0', source)
        self.assertIn('gladFont: BitmapFont = BitmapFont("title_font2.png", 109.0', source)
        self.assertIn('"frame.png" -> Vec2(344.0, 514.0)', source)
        self.assertEqual(len(images), 18)
        self.assertIn('val paintings: Map[Int, String]', source)
        self.assertIn('val previews: Map[Int, String]', source)
        for index in range(1, 7):
            self.assertIn(painting_name(index), images)
            self.assertIn(painting_name(index, tall=True), images)
            self.assertIn(f'{index} -> "level{index}.png"', source)
            self.assertIn(f'{index} -> "level{index}-568h.png"', source)
            self.assertIn(f'"level{index}.png" -> Vec2(320.0, 480.0)', source)
            self.assertIn(f'"level{index}-568h.png" -> Vec2(320.0, 568.0)', source)
            self.assertNotIn(f"level{index}.jpg", images)

    def test_gallery_rejects_missing_previews_and_changed_reference_geometry(self):
        self.gallery_resources()
        (self.resources / "level6-568h.png").unlink()
        with self.assertRaises(FileNotFoundError):
            make_gallery_source(self.resources, self.legacy)
        png_header(self.resources / "level6-568h.png", 320, 568)
        png_header(self.resources / "level2.png", 500, 671)
        with self.assertRaises(ValueError):
            make_gallery_source(self.resources, self.legacy)
        self.painting(2, tall=False)
        png_header(self.resources / "level3-568h.png", 320, 480)
        with self.assertRaises(ValueError):
            make_gallery_source(self.resources, self.legacy)
        self.painting(3, tall=True)
        png_header(self.resources / "frame.png", 320, 480)
        with self.assertRaises(ValueError):
            make_gallery_source(self.resources, self.legacy)

    def test_staging_preserves_source_bytes_and_prunes_only_previously_owned_assets(self):
        from whaley_tools.audio import AUDIO_FILES

        for name in AUDIO_FILES:
            (self.resources / name).write_bytes(b"original sound fixture")
        for name in ("meta_tileset.png", "infinite_bubble.png"):
            png_header(self.resources / name, 320, 480)
        sprites = {"player.png": (1024, 1024), "player-win.png": (1024, 1024),
                   "flame01.png": (24, 24), "flame02.png": (24, 24), "spout.png": (1024, 1024),
                   "tileset.png": (70, 36), "tileset2.png": (70, 36), "tileset3.png": (70, 36)}
        for name, size in sprites.items():
            for prefix in ("", "whaleland-"):
                directory = self.legacy if name == "tileset3.png" and not prefix else self.resources
                path = directory / f"{prefix}{name}"
                png_header(path, *size)
                path.write_bytes(path.read_bytes() + f"{prefix}{name}".encode())
        jpeg_header(self.resources / "level2.jpg", 500, 671)
        self.painting(2, tall=False)
        self.painting(2, tall=True)
        output = self.root / "staged"
        png_header(self.resources / "retired-expressions.png", 288, 416)
        stage_assets(output, {"level2.jpg", "retired-expressions.png"}, root=self.root,
                     resources=self.resources, legacy=self.legacy)
        (output / "auxiliary.png").write_bytes(b"not generated by staging")
        # A failed replacement must not retire the previous working files.
        with self.assertRaises(FileNotFoundError):
            stage_assets(output, {"missing.png"}, root=self.root, resources=self.resources, legacy=self.legacy)
        self.assertTrue((output / "level2.jpg").is_file())
        required = {"level2.png", "level2-568h.png"} | sprites.keys()
        for name in ("whaley-expressions.png", "whaley-win-expressions.png"):
            png_header(self.resources / name, 864, 352)
            required.add(name)
        scenery = sprites.keys() - {"player.png", "player-win.png"}
        default_manifest = None
        for style in (None, "original", "whaleland", "original", None):
            with self.subTest(art_style=style):
                selection = {} if style is None else {"art_style": style}
                stage_assets(output, required, root=self.root, resources=self.resources,
                             legacy=self.legacy, **selection)
                self.assertFalse((output / "level2.jpg").exists())
                self.assertEqual((output / "auxiliary.png").read_bytes(), b"not generated by staging")
                manifest = json.loads((output / "provenance.json").read_text())
                for name in required:
                    source_name = f"whaleland-{name}" if style != "original" and name in scenery else name
                    directory = self.legacy if source_name == "tileset3.png" else self.resources
                    source = directory / source_name
                    content = source.read_bytes()
                    self.assertEqual((output / name).read_bytes(), content)
                    self.assertEqual(manifest[name], {
                        "source": source.relative_to(self.root).as_posix(),
                        "sha256": hashlib.sha256(content).hexdigest()})
                self.assertNotIn("level2.jpg", manifest)
                self.assertFalse(any(name.startswith("whaleland-") for name in manifest))
                self.assertFalse((output / "retired-expressions.png").exists())
                if style is None:
                    default_manifest = manifest
                elif style == "whaleland":
                    self.assertEqual(manifest, default_manifest)
        before = (output / "provenance.json").read_bytes()
        stage_assets(output, required, root=self.root, resources=self.resources, legacy=self.legacy)
        self.assertEqual((output / "provenance.json").read_bytes(), before)
        png_header(self.resources / "whaleland-flame02.png", 25, 24)
        with self.assertRaisesRegex(ValueError, "Alternate atlas dimensions differ"):
            stage_assets(output, required, root=self.root, resources=self.resources,
                         legacy=self.legacy, art_style="whaleland")

    def test_invalid_art_style_leaves_previous_staging_untouched(self):
        output = self.root / "staged"
        output.mkdir()
        previous = b'{"keep.png":{"sha256":"working"}}'
        (output / "provenance.json").write_bytes(previous)
        (output / "keep.png").write_bytes(b"working asset")
        for value in ("", "whalelannd"):
            with self.subTest(art_style=value):
                with self.assertRaisesRegex(ValueError, "original or whaleland"):
                    stage_assets(output, set(), root=self.root, art_style=value)
                with patch.dict(os.environ, {"WHALEY_ART_STYLE": value}):
                    with self.assertRaisesRegex(ValueError, "original or whaleland"):
                        run(Namespace(source_output=None, asset_output=output), self.root)
                self.assertEqual((output / "provenance.json").read_bytes(), previous)
                self.assertEqual((output / "keep.png").read_bytes(), b"working asset")
                self.assertEqual({path.name for path in output.iterdir()}, {"provenance.json", "keep.png"})

    def test_staging_rejects_corrupt_manifests_and_cleanup_names_outside_its_directory(self):
        output = self.root / "staged"
        output.mkdir()
        outside = self.root / "keep.png"
        outside.write_bytes(b"keep")
        invalid = ["{broken", "[]", "null"] + [json.dumps({name: {"sha256": "unused"}})
            for name in ("../keep.png", "..\\keep.png", "subdir/keep.png", "C:keep.png")]
        for content in invalid:
            (output / "provenance.json").write_text(content)
            with self.assertRaises(ValueError):
                stage_assets(output, set(), root=self.root, resources=self.resources, legacy=self.legacy)
            self.assertEqual(outside.read_bytes(), b"keep")
