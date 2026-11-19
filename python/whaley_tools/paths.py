"""Locate checkout inputs without changing the caller's working directory."""
from pathlib import Path


def is_repository(path: Path) -> bool:
    return ((path / "Scala" / "build.sbt").is_file()
            and (path / "Sources" / "WhaleySpriteKit" / "Resources").is_dir())


def repository_root(explicit: Path | None = None) -> Path:
    if explicit is not None:
        root = explicit.expanduser().resolve()
        if not is_repository(root):
            raise ValueError(f"Not a WhaleKart checkout: {root}")
        return root

    # A source invocation belongs to its checkout; an installed command finds
    # the checkout containing the current directory. --root overrides either.
    project = Path(__file__).resolve().parent.parent
    source = project.parent
    if project.name == "python" and is_repository(source):
        return source
    working = Path.cwd().resolve()
    for candidate in (working, *working.parents):
        if is_repository(candidate):
            return candidate
    raise ValueError("Cannot find a WhaleKart checkout. Run inside one or pass --root PATH.")
