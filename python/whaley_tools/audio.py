"""Stage the original audio unchanged; both transports support WAV and MP3.

No generated copies are committed. The asset manifest retains exact source
paths and hashes just as it does for the original artwork.
"""
import hashlib
from pathlib import Path
import shutil


AUDIO_FILES = (
    "A.mp3", "B.mp3", "bg01.mp3", "knock.mp3", "bounce01.wav",
    "coin01.wav", "flame01.wav", "goal01.wav", "jump01.wav", "pause01.wav",
)


def stage_audio(output: Path, resources: Path, legacy: Path, repo: Path) -> dict:
    output.mkdir(parents=True, exist_ok=True)
    manifest = {}
    for name in AUDIO_FILES:
        source = next((root / name for root in (resources, legacy) if (root / name).is_file()), None)
        if source is None:
            raise FileNotFoundError(f"Missing original Whaley audio: {name}")
        content = source.read_bytes()
        if not content:
            raise ValueError(f"Empty Whaley audio: {source}")
        target = output / name
        if not target.is_file() or target.read_bytes() != content:
            shutil.copyfile(source, target)
        manifest[name] = {"source": source.relative_to(repo).as_posix(),
                          "sha256": hashlib.sha256(content).hexdigest()}
    return manifest
