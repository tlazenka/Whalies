"""Publish a prepared Whaley static bundle to gh-pages using normal Git authentication.

Build and test the site first. This command only publishes generated files; it
does not change the source checkout or configure the repository's Pages settings.
"""
from __future__ import annotations

from argparse import Namespace
from dataclasses import dataclass
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


from .web import MARKER

BRANCH = "gh-pages"
REF = f"refs/heads/{BRANCH}"


class PublicationError(RuntimeError):
    pass


@dataclass(frozen=True)
class Publication:
    commit: str
    changed: bool


def git(repository: Path, *arguments: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    # These variables could otherwise redirect an isolated checkout's writes
    # into the caller's repository or index. Authentication/identity stay intact.
    environment = os.environ.copy()
    for name in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR",
                 "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES"):
        environment.pop(name, None)
    result = subprocess.run(
        ["git", "-C", str(repository), *arguments],
        text=True, capture_output=True, env=environment,
    )
    if check and result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        raise PublicationError(f"Git {arguments[0]} failed: {detail}")
    return result


def validate_site(site: Path) -> None:
    if site.is_symlink() or not site.is_dir():
        raise PublicationError("The site must be a regular directory produced by make whaley-pages.")
    allowed = {"index.html", "assets", ".nojekyll", "CNAME", MARKER}
    unexpected = sorted(path.name for path in site.iterdir() if path.name not in allowed)
    if unexpected:
        raise PublicationError("Unexpected files at the site root: " + ", ".join(unexpected))
    for path in site.rglob("*"):
        if path.is_symlink():
            raise PublicationError(f"Symbolic links cannot be published: {path.relative_to(site)}")
        if any(part.lower() == ".git" for part in path.relative_to(site).parts):
            raise PublicationError("A generated site must not contain a .git entry.")
        if not path.is_file() and not path.is_dir():
            raise PublicationError(f"Unsupported file type: {path.relative_to(site)}")
    for name in ("index.html", "assets/main.js", "assets/styles.css", ".nojekyll"):
        path = site / name
        if not path.is_file() or (name != ".nojekyll" and path.stat().st_size == 0):
            raise PublicationError(f"Missing or empty static-site file: {name}")
    if (site / "CNAME").exists() and not (site / "CNAME").is_file():
        raise PublicationError("CNAME must be a regular file.")


def remote_url(repository: Path, remote: str) -> str:
    if not remote or remote.startswith("-") or any(character in remote for character in "\r\n\0"):
        raise PublicationError("Invalid remote name or URL.")
    configured = git(repository, "remote", "get-url", "--push", remote, check=False)
    if configured.returncode == 0:
        value = configured.stdout.strip()
        relative_to = repository
    else:
        # Explicit local paths are also useful for rehearsing a deployment to
        # a bare repository. A misspelled remote name must not become a URL.
        candidate = Path(remote).expanduser()
        if candidate.exists():
            return str(candidate.resolve())
        if not re.match(r"^[A-Za-z][A-Za-z0-9+.-]*://", remote) and not re.match(r"^[^/]+@[^/]+:", remote):
            raise PublicationError(f"Git remote {remote!r} is not configured.")
        value = remote
        relative_to = Path.cwd()
    if re.match(r"^[A-Za-z][A-Za-z0-9+.-]*://", value) or re.match(r"^[^/]+@[^/]+:", value):
        return value
    path = Path(value).expanduser()
    return str((relative_to / path).resolve() if not path.is_absolute() else path)


def publish(site: Path, repository: Path, remote: str = "origin") -> Publication:
    validate_site(site)
    site = site.resolve()
    repository = repository.resolve()
    destination = remote_url(repository, remote)

    with tempfile.TemporaryDirectory(prefix="whaley-pages-publish-") as directory:
        temporary = Path(directory)
        snapshot = temporary / "site"
        # Preserve links while copying so validation rejects them instead of
        # following a newly introduced link outside the generated directory.
        shutil.copytree(site, snapshot, symlinks=True)
        validate_site(snapshot)
        checkout = temporary / "checkout"
        checkout.mkdir()
        git(checkout, "init", "--quiet", f"--initial-branch={BRANCH}")
        git(checkout, "remote", "add", "origin", destination)
        for key in ("user.name", "user.email"):
            value = git(repository, "config", "--get", key, check=False)
            if value.returncode == 0:
                git(checkout, "config", key, value.stdout.strip())

        existing = git(checkout, "ls-remote", "--exit-code", "--heads", "origin", REF, check=False)
        if existing.returncode not in (0, 2):
            raise PublicationError("Could not inspect gh-pages: " + existing.stderr.strip())
        if existing.returncode == 0:
            git(checkout, "fetch", "--quiet", "--no-tags", "--depth=1", "origin", REF)
            git(checkout, "checkout", "--quiet", "-B", BRANCH, "FETCH_HEAD")

        cname = checkout / "CNAME"
        preserved_cname = None
        if cname.exists() or cname.is_symlink():
            if cname.is_symlink() or not cname.is_file():
                raise PublicationError("Existing gh-pages CNAME is not a regular file.")
            preserved_cname = cname.read_bytes()
            supplied = snapshot / "CNAME"
            if supplied.exists() and supplied.read_bytes() != preserved_cname:
                raise PublicationError(
                    "The generated CNAME differs from gh-pages. Update the custom domain "
                    "deliberately before publishing; this command preserves the existing CNAME."
                )

        for path in checkout.iterdir():
            if path.name == ".git":
                continue
            if path.is_dir() and not path.is_symlink():
                shutil.rmtree(path)
            else:
                path.unlink()
        for path in snapshot.iterdir():
            target = checkout / path.name
            if path.is_dir():
                shutil.copytree(path, target)
            else:
                shutil.copy2(path, target)
        if preserved_cname is not None:
            (checkout / "CNAME").write_bytes(preserved_cname)

        git(checkout, "add", "--all", "--force")
        difference = git(checkout, "diff", "--cached", "--quiet", check=False)
        if difference.returncode not in (0, 1):
            raise PublicationError("Could not compare the prepared site: " + difference.stderr.strip())
        changed = difference.returncode == 1
        if changed:
            git(checkout, "commit", "--quiet", "-m", "Publish Whaley web build")
        commit = git(checkout, "rev-parse", "HEAD").stdout.strip()
        # A regular push rejects concurrent updates. Never replace another
        # publisher's branch history or change the user's source branch.
        git(checkout, "push", "origin", f"HEAD:{REF}")
        return Publication(commit, changed)


def run(args: Namespace, root: Path) -> int:
    site = args.site if args.site is not None else root / "Scala" / "target" / "pages"
    try:
        publication = publish(site, root, args.remote)
    except (PublicationError, OSError) as error:
        print(f"Publication failed: {error}", file=sys.stderr)
        return 1
    prefix = "Published" if publication.changed else "Already published"
    print(f"{prefix} {publication.commit} on {BRANCH}.")
    print("Pages source: Settings > Pages > Deploy from a branch > gh-pages > / (root).")
    return 0
