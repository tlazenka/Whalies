"""Compile the original TMX/plist/BMFont resources into portable Scala data.

Gameplay collision data and visual Background data have distinct contracts.
Neither frontend invents visual tiles from collision markers or system fonts.
"""
from argparse import Namespace
import base64
import gzip
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import struct
import xml.etree.ElementTree as ET
import zlib

from .presentation import make_gallery_source, make_presentation_source, png_size, resource


def write_changed(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists() or path.read_text(encoding="utf-8") != content:
        path.write_text(content, encoding="utf-8")


def number(value):
    return repr(float(value))


def vec(x, y):
    return f"Vec2({number(x)}, {number(y)})"


def properties(element):
    return {p.attrib["name"]: p.attrib.get("value", p.text or "") for p in element.findall("properties/property")}


def decode_layer(layer, count, preserve_flags=False):
    data = layer.find("data")
    if data is None:
        raise ValueError("Missing TMX layer data")
    encoding = data.attrib.get("encoding")
    if encoding == "base64":
        raw = base64.b64decode("".join((data.text or "").split()), validate=True)
        compression = data.attrib.get("compression")
        if compression == "gzip":
            raw = gzip.decompress(raw)
        elif compression == "zlib":
            raw = zlib.decompress(raw)
        elif compression is not None:
            raise ValueError(f"Unsupported TMX compression {compression}")
        if len(raw) != count * 4:
            raise ValueError("TMX layer dimensions and byte length disagree")
        values = struct.unpack(f"<{count}I", raw)
    elif encoding == "csv":
        values = [int(x) for x in (data.text or "").replace("\n", "").split(",") if x.strip()]
    else:
        raise ValueError(f"Unsupported TMX layer encoding {encoding}")
    if len(values) != count:
        raise ValueError("TMX layer dimensions and cell count disagree")
    if any(v < 0 or v > 0xFFFFFFFF for v in values):
        raise ValueError("TMX GID is outside UInt32")
    return list(values) if preserve_flags else [v & 0x0FFFFFFF for v in values]


def load_level(index, resources: Path):
    path = resources / f"level{index}-568h.tmx"
    root = ET.parse(path).getroot()
    if root.attrib.get("orientation") != "orthogonal":
        raise ValueError(f"{path.name}: only orthogonal levels are supported")
    width, height, tile = (int(root.attrib[k]) for k in ("width", "height", "tilewidth"))
    if tile != int(root.attrib["tileheight"]):
        raise ValueError(f"{path.name}: non-square tiles")
    gid_properties = {}
    for tileset in root.findall("tileset"):
        if "source" in tileset.attrib:
            raise ValueError("External TSX must be explicitly supported before use")
        first = int(tileset.attrib["firstgid"])
        for definition in tileset.findall("tile"):
            gid_properties[first + int(definition.attrib["id"])] = properties(definition)
    meta = root.find("layer[@name='Meta']")
    if meta is None:
        raise ValueError(f"{path.name}: missing Meta layer")
    walls, grounds = [], []
    for i, gid in enumerate(decode_layer(meta, width * height)):
        p = gid_properties.get(gid, {})
        cell = (i % width, height - 1 - i // width)
        if p.get("IsWall", "").lower() == "true":
            walls.append(cell)
        if p.get("IsGround", "").lower() == "true":
            grounds.append(cell)
    groups = {group.attrib["name"]: list(group) for group in root.findall("objectgroup")}
    objects = groups.get("Objects", [])

    def bottom_left(obj):
        return float(obj.attrib["x"]), height * tile - float(obj.attrib["y"]) - float(obj.attrib.get("height", 0))

    def center(obj, half_size):
        x, y = bottom_left(obj)
        return vec(x + half_size, y + half_size)

    def named(name):
        matches = [o for o in objects if o.attrib.get("name") == name]
        if len(matches) != 1:
            raise ValueError(f"{path.name}: expected exactly one {name}")
        return matches[0]

    bubbles = [center(o, 22) for o in objects if properties(o).get("IsBubble") == "1"]
    coins = [center(o, 16) for o in objects if properties(o).get("IsCoin") == "1"]
    hazards = [f"HazardSpawn({center(o, 12)}, {int(properties(o).get('Phase', '0'))})" for o in groups.get("Flames", [])]
    return dict(number=index, width=width, height=height, tile=tile, walls=walls, grounds=grounds,
                spawn=vec(*bottom_left(named("PlayerOrigin"))), bubbles=bubbles, coins=coins,
                hazards=hazards, goal=center(named("Goal"), 16), source=path)


def make_level_source(levels):
    def cells(values):
        return 'cells("' + " ".join(f"{x},{y}" for x, y in sorted(values)) + '")'

    def vector(values):
        return "Vector(" + ", ".join(values) + ")"

    parts = ["""// Generated from Sources/WhaleySpriteKit/Resources. Edit the TMX sources.
package whaley.core

object LevelData {
  private def cells(value: String): Set[(Int, Int)] =
    value.split(" ").iterator.filter(_.nonEmpty).map { item =>
      val pair = item.split(",")
      (pair(0).toInt, pair(1).toInt)
    }.toSet

  lazy val all: Vector[Level] = Vector(level1, level2, level3, level4, level5, level6)
"""]
    for level in levels:
        parts.append(f"""
  private def level{level['number']}: Level = Level(
    number = {level['number']}, width = {level['width']}, height = {level['height']}, tileSize = {level['tile']},
    walls = {cells(level['walls'])},
    grounds = {cells(level['grounds'])},
    spawn = {level['spawn']},
    bubbles = {vector(level['bubbles'])},
    coins = {vector(level['coins'])},
    hazards = {vector(level['hazards'])},
    goal = {level['goal']}
  )
""")
    return "".join(parts) + "}\n"


def make_sprite_source(resources: Path):
    parts = ["// Generated from the original plist sprite atlases.\npackage whaley.core\n\nobject SpriteData {\n"]
    # Retained for compatibility with existing tests. Renderers use the visual
    # GIDs/crops in PresentationData, never these collision-shaped shortcuts.
    tileset = ET.parse(resources / "level1-568h.tmx").getroot().find("tileset[@name='tileset']")
    margin, spacing, tile = (int(tileset.attrib.get(k, "0")) for k in ("margin", "spacing", "tilewidth"))
    for name, column in (("wallTile", 0), ("groundTile", 1)):
        parts.append(f"  val {name}: Rect = Rect({margin + column * (tile + spacing)}.0, {margin}.0, {tile}.0, {tile}.0)\n")
    for name, field in (("player", "player"), ("player-win", "playerWin"), ("coin", "coin"), ("spout", "spout")):
        data = plistlib.loads((resources / f"{name}.plist").read_bytes())["frames"]
        frames = []
        for key in sorted(data, key=lambda s: int(re.search(r"(\d+)\.png$", s).group(1))):
            f = data[key]
            frames.append("Rect(" + ", ".join(number(f[k]) for k in ("x", "y", "width", "height")) + ")")
        parts.append(f"  val {field}Frames: Vector[Rect] = Vector({', '.join(frames)})\n")
    return "".join(parts) + "}\n"


def stage_assets(output, required_images, *, root: Path, resources: Path | None = None,
                 legacy: Path | None = None, art_style: str = "whaleland"):
    from .audio import stage_audio

    if art_style not in ("original", "whaleland"):
        raise ValueError("WHALEY_ART_STYLE must be original or whaleland")
    resources = resources if resources is not None else root / "Sources" / "WhaleySpriteKit" / "Resources"
    legacy = legacy if legacy is not None else root / "Apps" / "Whaley2010" / "Resources"

    output.mkdir(parents=True, exist_ok=True)
    provenance = output / "provenance.json"
    previous = json.loads(provenance.read_text(encoding="utf-8")) if provenance.is_file() else {}
    if not isinstance(previous, dict) or any(
            not name or name in (".", "..") or Path(name).name != name or "\\" in name or ":" in name
            for name in previous):
        raise ValueError(f"Invalid staged asset manifest: {provenance}")
    # Preserve existing auxiliary assets while validating all actually used art.
    names = set(required_images) | {"player-win.png", "meta_tileset.png", "infinite_bubble.png"}
    manifest = {}
    for name in sorted(names):
        source = resource(name, resources, legacy)
        if art_style == "whaleland" and name in (
                "flame01.png", "flame02.png", "spout.png",
                "tileset.png", "tileset2.png", "tileset3.png"):
            alternate = resource(f"whaleland-{name}", resources, legacy)
            if png_size(alternate) != png_size(source):
                raise ValueError(f"Alternate atlas dimensions differ: {alternate.name}")
            source = alternate
        content = source.read_bytes()
        target = output / name
        if not target.is_file() or target.read_bytes() != content:
            shutil.copyfile(source, target)
        manifest[name] = {"source": source.relative_to(root).as_posix(), "sha256": hashlib.sha256(content).hexdigest()}
    manifest.update(stage_audio(output, resources, legacy, root))
    # Remove retired generated assets only after all current inputs succeeded.
    # Untracked auxiliary files are not ours to delete.
    for name in previous.keys() - manifest.keys():
        retired = output / name
        if retired.is_file():
            retired.unlink()
    write_changed(provenance, json.dumps(manifest, indent=2) + "\n")


def run(args: Namespace, root: Path) -> None:
    if not (args.source_output or args.asset_output):
        raise ValueError("Specify --source-output or --asset-output")
    resources = root / "Sources" / "WhaleySpriteKit" / "Resources"
    legacy = root / "Apps" / "Whaley2010" / "Resources"
    art_style = os.environ.get("WHALEY_ART_STYLE", "whaleland")
    if art_style not in ("original", "whaleland"):
        raise ValueError("WHALEY_ART_STYLE must be original or whaleland")
    presentation, images = make_presentation_source(resources, legacy, decode_layer,
                                                   whaleland_art=art_style == "whaleland")
    gallery, gallery_images = make_gallery_source(resources, legacy)
    if args.source_output:
        levels = [load_level(i, resources) for i in range(1, 7)]
        write_changed(args.source_output / "LevelData.scala", make_level_source(levels))
        write_changed(args.source_output / "SpriteData.scala", make_sprite_source(resources))
        write_changed(args.source_output / "PresentationData.scala", presentation)
        write_changed(args.source_output / "GalleryData.scala", gallery)
    if args.asset_output:
        stage_assets(args.asset_output, images | gallery_images, root=root,
                     resources=resources, legacy=legacy, art_style=art_style)
