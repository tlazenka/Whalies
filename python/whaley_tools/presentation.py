"""Generate presentation data from the original assets, not collision approximations.

Paths are supplied by the asset command so tests can use
small fixtures. All geometry uses atlas pixels; only the renderers scale to a view.
"""
import json
from pathlib import Path
import plistlib
import re
import struct
import xml.etree.ElementTree as ET


FLAGS = 0xF0000000


def painting_name(index, tall=False):
    if index not in range(1, 7):
        raise ValueError(f"Unknown painting level: {index}")
    return f"level{index}{'-568h' if tall else ''}.png"


def resource(name, resources, legacy):
    # Build inputs are repository-owned; never resolve an absolute/path-traversal name.
    if Path(name).name != name or not name:
        raise ValueError(f"Expected a resource filename, got {name!r}")
    for directory in (resources, legacy):
        candidate = directory / name
        if candidate.is_file():
            return candidate
    raise FileNotFoundError(f"Missing Whaley resource: {name}")


def png_size(path):
    header = path.read_bytes()[:24]
    if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise ValueError(f"Invalid PNG header: {path}")
    width, height = struct.unpack(">II", header[16:24])
    if width < 1 or height < 1:
        raise ValueError(f"Empty PNG: {path}")
    return width, height


def jpeg_size(path):
    """Read baseline/progressive JPEG frame dimensions without rewriting art.

    Like png_size, this validates the size header, not the compressed pixels;
    image decoding remains the renderers' responsibility. No Pillow dependency
    is required for the existing Python-only build step.
    """
    data = path.read_bytes()
    if not data.startswith(b"\xff\xd8"):
        raise ValueError(f"Invalid JPEG header: {path}")
    offset = 2
    while offset < len(data):
        if data[offset] != 0xFF:
            raise ValueError(f"Invalid JPEG marker: {path}")
        while offset < len(data) and data[offset] == 0xFF:
            offset += 1
        if offset >= len(data):
            break
        marker = data[offset]
        offset += 1
        if marker in (0xD9, 0xDA):  # End or scan data before a size-bearing frame.
            break
        if marker == 0x01:  # Standalone TEM marker.
            continue
        if marker == 0 or 0xD0 <= marker <= 0xD8 or offset + 2 > len(data):
            raise ValueError(f"Invalid JPEG marker: {path}")
        length = struct.unpack_from(">H", data, offset)[0]
        if length < 2 or offset + length > len(data):
            raise ValueError(f"Truncated JPEG segment: {path}")
        if marker in (0xC0, 0xC1, 0xC2):
            if length < 8:
                raise ValueError(f"Truncated JPEG frame: {path}")
            precision, height, width, channels = struct.unpack_from(">BHHB", data, offset + 2)
            if precision != 8 or min(width, height) < 1 or channels not in (1, 3, 4) or length != 8 + 3 * channels:
                raise ValueError(f"Invalid JPEG frame: {path}")
            return width, height
        offset += length
    raise ValueError(f"Missing supported JPEG frame: {path}")


def image_size(path):
    return jpeg_size(path) if path.suffix.lower() in (".jpg", ".jpeg") else png_size(path)


def attributes(line):
    return {key: quoted if quoted else plain for key, quoted, plain in
            re.findall(r'(\w+)=(?:"([^"]*)"|([^\s]+))', line)}


def read_font(path, resources, legacy):
    common = None
    page = None
    glyphs = {}
    kernings = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        values = attributes(line)
        if line.startswith("common "):
            common = {k: int(values[k]) for k in ("lineHeight", "scaleW", "scaleH", "pages")}
        elif line.startswith("page "):
            if page is not None or int(values["id"]) != 0:
                raise ValueError(f"Only single-page fonts are supported: {path}")
            page = values["file"]
        elif line.startswith("char "):
            code = int(values["id"])
            if code in glyphs or int(values.get("page", "0")) != 0:
                raise ValueError(f"Invalid/duplicate font character: {code}")
            glyphs[code] = tuple(int(values[k]) for k in
                                ("x", "y", "width", "height", "xoffset", "yoffset", "xadvance"))
        elif line.startswith("kerning "):
            kernings[(int(values["first"]), int(values["second"]))] = int(values["amount"])
    if not common or not page or not glyphs or common["pages"] != 1 or common["lineHeight"] <= 0:
        raise ValueError(f"Incomplete bitmap font: {path}")
    width, height = png_size(resource(page, resources, legacy))
    if (width, height) != (common["scaleW"], common["scaleH"]):
        raise ValueError(f"Font descriptor and PNG dimensions differ: {path}")
    for code, (x, y, w, h, dx, dy, advance) in glyphs.items():
        if min(x, y, w, h, advance) < 0 or x + w > width or y + h > height:
            raise ValueError(f"Font crop outside atlas: {path}, character {code}")
    return dict(page=page, height=common["lineHeight"], glyphs=glyphs, kernings=kernings)


def read_visual_level(index, resources, legacy, decode_layer):
    root = ET.parse(resources / f"level{index}-568h.tmx").getroot()
    width, height, tile = (int(root.attrib[k]) for k in ("width", "height", "tilewidth"))
    if root.attrib.get("orientation") != "orthogonal" or tile != int(root.attrib["tileheight"]):
        raise ValueError("Only square, orthogonal Whaley maps are supported")
    sets = []
    for entry in root.findall("tileset"):
        if "source" in entry.attrib:
            raise ValueError("External TSX is not supported")
        image = entry.find("image")
        if image is None:
            raise ValueError("Missing tileset image")
        name = image.attrib["source"]
        sheet_w, sheet_h = png_size(resource(name, resources, legacy))
        margin, spacing = (int(entry.attrib.get(k, "0")) for k in ("margin", "spacing"))
        tw, th = (int(entry.attrib[k]) for k in ("tilewidth", "tileheight"))
        if (tw, th) != (tile, tile) or min(margin, spacing) < 0:
            raise ValueError("Unsupported tileset geometry")
        columns = (sheet_w - 2 * margin + spacing) // (tile + spacing)
        rows = (sheet_h - 2 * margin + spacing) // (tile + spacing)
        if columns <= 0 or rows <= 0:
            raise ValueError(f"Tileset too small: {name}")
        sets.append(dict(first=int(entry.attrib["firstgid"]), page=name, columns=columns,
                         count=columns * rows, margin=margin, spacing=spacing,
                         width=sheet_w, height=sheet_h))
    sets.sort(key=lambda s: s["first"])
    layer = root.find("layer[@name='Background']")
    if layer is None:
        raise ValueError(f"Level {index}: missing Background layer")
    if (int(layer.attrib["width"]), int(layer.attrib["height"])) != (width, height):
        raise ValueError(f"Level {index}: Background dimensions differ from map")
    # Existing maps have no flip flags. Reject, rather than silently render, a
    # future transformed tile until both backends implement the same transform.
    gids = decode_layer(layer, width * height, preserve_flags=True)
    definitions = {}
    for encoded in set(gids) - {0}:
        if encoded & FLAGS:
            raise ValueError(f"Level {index}: unsupported tile flip/rotation {encoded:#x}")
        candidates = [s for s in sets if s["first"] <= encoded]
        if not candidates:
            raise ValueError(f"Level {index}: unbound visual GID {encoded}")
        sheet = candidates[-1]
        local = encoded - sheet["first"]
        if local >= sheet["count"]:
            raise ValueError(f"Level {index}: GID {encoded} exceeds {sheet['page']}")
        x = sheet["margin"] + local % sheet["columns"] * (tile + sheet["spacing"])
        y = sheet["margin"] + local // sheet["columns"] * (tile + sheet["spacing"])
        if x + tile > sheet["width"] or y + tile > sheet["height"]:
            raise ValueError(f"Level {index}: invalid tile crop {encoded}")
        definitions[encoded] = (sheet["page"], (x, y, tile, tile))
    return dict(number=index, width=width, height=height, tile=tile,
                cells=[(i % width, height - 1 - i // width, gid)
                       for i, gid in enumerate(gids) if gid], definitions=definitions)


def rect(values):
    return "Rect(" + ", ".join(str(float(v)) for v in values) + ")"


def font_source(name, font):
    glyphs = []
    for code, values in sorted(font["glyphs"].items()):
        glyphs.append(f"    {code} -> BitmapGlyph({rect(values[:4])}, {float(values[4])}, "
                      f"{float(values[5])}, {float(values[6])})")
    kerns = ", ".join(f"({a}, {b}) -> {float(value)}" for (a, b), value in sorted(font["kernings"].items()))
    return (f"  val {name}: BitmapFont = BitmapFont({json.dumps(font['page'])}, {float(font['height'])}, Map(\n"
            + ",\n".join(glyphs) + f"\n  ), Map({kerns}))\n")


def read_scene_images(index, resources, legacy):
    """Screen-fixed artwork from WhaleyScene.m, separate from TMX tiles.

    The Scala surface follows the original 568h variant even when a map is
    only 544 pixels tall. The scene adds its black bottom strip separately.
    """
    painting = painting_name(index, tall=True)
    scanlines = "scanlines-568h.png" if index in (1, 2) else None
    images = {}
    for name in (painting, scanlines):
        if name is not None:
            size = image_size(resource(name, resources, legacy))
            if size != (320, 568):
                raise ValueError(f"Original 568h scene requires {name} to be (320, 568), got {size}")
            images[name] = (0, 0, *size)
    return painting, scanlines, images


def make_gallery_source(resources, legacy):
    """Shared title metrics, standard cards and tall previews for both renderers."""
    gray = read_font(resource("title_font.fnt", resources, legacy), resources, legacy)
    glad = read_font(resource("title_font2.fnt", resources, legacy), resources, legacy)
    names = {"Default-568h@2x.png", "frame.png", "bubble01.png", "dust.png", gray["page"], glad["page"]}
    paintings = {i: painting_name(i) for i in range(1, 7)}
    previews = {i: painting_name(i, tall=True) for i in range(1, 7)}
    names.update(paintings.values())
    names.update(previews.values())
    dimensions = {name: image_size(resource(name, resources, legacy)) for name in sorted(names)}
    expected_sizes = {"Default-568h@2x.png": (320, 568), "frame.png": (344, 514), "bubble01.png": (128, 128)}
    expected_sizes.update({name: (320, 480) for name in paintings.values()})
    expected_sizes.update({name: (320, 568) for name in previews.values()})
    for name, size in expected_sizes.items():
        if dimensions[name] != size:
            raise ValueError(f"Original gallery geometry requires {name} to be {size}, got {dimensions[name]}")
    if gray["height"] != 109 or glad["height"] != 109:
        raise ValueError("Original gallery title fonts require a 109-pixel line height")
    pieces = ["// Generated from shared painting resources and original BMFont metrics.\npackage whaley.core\n\nobject GalleryData {\n",
              font_source("grayFont", gray), font_source("gladFont", glad)]
    for field, pages in (("paintings", paintings), ("previews", previews)):
        entries = ", ".join(f"{index} -> {json.dumps(name)}" for index, name in pages.items())
        pieces.append(f"  val {field}: Map[Int, String] = Map({entries})\n")
    pieces.append("  val images: Map[String, Vec2] = Map(\n")
    pieces.append(",\n".join(f"    {json.dumps(name)} -> Vec2({float(w)}, {float(h)})"
                              for name, (w, h) in dimensions.items()))
    pieces.append("\n  )\n  val requiredImages: Vector[String] = images.keys.toVector.sorted\n}\n")
    return "".join(pieces), names


def make_presentation_source(resources, legacy, decode_layer, *, whaleland_art=True):
    font = read_font(resource("game_font.fnt", resources, legacy), resources, legacy)
    levels = [read_visual_level(i, resources, legacy, decode_layer) for i in range(1, 7)]
    pieces = ["// Generated from original BMFont, TMX Background, shared paintings and spout plist data.\n",
              "package whaley.core\n\nobject PresentationData {\n"]
    pieces.append(f"  val whalelandArt: Boolean = {str(whaleland_art).lower()}\n")
    pieces.append(font_source("gameFont", font))
    pieces.append("  private def cells(value: String): Vector[(Int, Int, Int)] =\n"
                  "    value.split(\" \").iterator.filter(_.nonEmpty).map { item =>\n"
                  "      val p = item.split(\",\"); (p(0).toInt, p(1).toInt, p(2).toInt)\n"
                  "    }.toVector\n")
    pieces.append("  lazy val levels: Map[Int, VisualLevel] = Map(\n")
    blocks = []
    scene_images = set()
    for level in levels:
        # Compact triples avoid constructing thousands of AST nodes per map.
        data = " ".join(f"{x},{y},{gid}" for x, y, gid in level["cells"])
        defs = ", ".join(f"{gid} -> TileArt({json.dumps(page)}, {rect(crop)})"
                         for gid, (page, crop) in sorted(level["definitions"].items()))
        painting, scanlines, images = read_scene_images(level["number"], resources, legacy)
        scene_images.update(images)
        painting_source = f"TileArt({json.dumps(painting)}, {rect(images[painting])})"
        scanline_source = (f"Some(TileArt({json.dumps(scanlines)}, {rect(images[scanlines])}))"
                           if scanlines else "None")
        blocks.append(f"    {level['number']} -> VisualLevel({level['tile']}, cells({json.dumps(data)}), Map({defs}), "
                      f"{painting_source}, {scanline_source})")
    pieces.append(",\n".join(blocks) + "\n  )\n")
    plist = plistlib.loads((resources / "spout.plist").read_bytes())["frames"]
    frames = []
    sw, sh = png_size(resource("spout.png", resources, legacy))
    for index in range(1, 5):
        f = plist[f"spout{index}.png"]
        if f.get("rotated"):
            raise ValueError("Rotated spout frames are not supported")
        crop = tuple(float(f[k]) for k in ("x", "y", "width", "height"))
        if min(crop) < 0 or crop[0] + crop[2] > sw or crop[1] + crop[3] > sh:
            raise ValueError(f"Invalid spout frame {index}")
        frames.append(f"AtlasFrame({rect(crop)}, Vec2({float(f['originalWidth'])}, {float(f['originalHeight'])}), "
                      f"Vec2({float(f['offsetX'])}, {float(f['offsetY'])}))")
    pieces.append("  val spout: Vector[AtlasFrame] = Vector(" + ", ".join(frames) + ")\n")
    names = {font["page"], "player.png", "player-win.png", "bubble01.png", "infinite_bubble.png", "coin.png", "flame01.png", "flame02.png", "goal01.png", "spout.png"}
    names.update(page for level in levels for page, _ in level["definitions"].values())
    names.update(scene_images)
    for expressions in ("whaley-expressions.png", "whaley-win-expressions.png"):
        if png_size(resource(expressions, resources, legacy)) != (864, 352):
            raise ValueError("Expression atlas must contain eleven rows and three banks of nine 32-pixel frames")
        names.add(expressions)
    pieces.append("  val requiredImages: Vector[String] = (Vector(" + ", ".join(json.dumps(n) for n in sorted(names)) + ") ++ GalleryData.requiredImages).distinct\n}\n")
    return "".join(pieces), names
