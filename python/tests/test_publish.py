"""Exercise manual publication against a local bare Git repository."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock


from whaley_tools import publish as publisher
from whaley_tools.web import MARKER, package as package_web


class PublishPagesTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.repository = self.root / "source"
        self.repository.mkdir()
        self.git(self.repository, "init", "--quiet", "--initial-branch=develop")
        self.git(self.repository, "config", "user.name", "Whaley test")
        self.git(self.repository, "config", "user.email", "whaley-test@example.invalid")
        self.git(self.repository, "config", "commit.gpgsign", "false")
        (self.repository / "README.md").write_text("Source checkout\n")
        self.git(self.repository, "add", "README.md")
        self.git(self.repository, "commit", "--quiet", "-m", "Source")
        # Publishing must leave staged, unstaged, and untracked work intact.
        (self.repository / "README.md").write_text("Locally modified source\n")
        (self.repository / "staged.txt").write_text("Keep this staged\n")
        self.git(self.repository, "add", "staged.txt")
        (self.repository / "untracked.txt").write_text("Keep this untracked\n")
        self.remote = self.root / "remote.git"
        self.git(self.root, "init", "--quiet", "--bare", str(self.remote))
        self.git(self.repository, "remote", "add", "origin", str(self.remote))
        self.site = self.root / "site"
        (self.site / "assets").mkdir(parents=True)
        (self.site / "index.html").write_text('<script type="module" src="./assets/main.js"></script>')
        (self.site / ".nojekyll").touch()
        (self.site / "assets/main.js").write_text("console.log('Whaley fixture');\n")
        (self.site / "assets/styles.css").write_text("canvas { display: block; }\n")
        (self.site / "assets/old.png").write_bytes(b"old artifact fixture")

    @staticmethod
    def git(repository, *arguments):
        return subprocess.run(
            ["git", "-C", str(repository), *arguments], check=True,
            text=True, capture_output=True,
        ).stdout.strip()

    def source_state(self):
        return (
            self.git(self.repository, "status", "--porcelain=v1"),
            self.git(self.repository, "rev-parse", "HEAD"),
            self.git(self.repository, "branch", "--show-current"),
            (self.repository / "README.md").read_bytes(),
            (self.repository / "staged.txt").read_bytes(),
            (self.repository / "untracked.txt").read_bytes(),
        )

    def test_initial_publish_update_and_noop_preserve_checkout_and_domain(self):
        before = self.source_state()
        (self.site / "CNAME").write_text("whaley.example.invalid\n")
        first = publisher.publish(self.site, self.repository)
        self.assertTrue(first.changed)
        self.assertEqual(self.git(self.remote, "rev-parse", "gh-pages"), first.commit)
        self.assertEqual(self.git(self.remote, "rev-list", "--count", "gh-pages"), "1")
        self.assertEqual(set(self.git(self.remote, "ls-tree", "--name-only", "gh-pages").splitlines()),
                         {".nojekyll", "CNAME", "assets", "index.html"})

        (self.site / "CNAME").unlink()
        (self.site / "assets/old.png").unlink()
        (self.site / "assets/new.jpg").write_bytes(b"new artifact fixture")
        (self.site / "assets/main.js").write_text("console.log('updated Whaley fixture');\n")
        second = publisher.publish(self.site, self.repository)
        self.assertTrue(second.changed)
        self.assertEqual(self.git(self.remote, "rev-parse", "gh-pages^"), first.commit)
        self.assertEqual(self.git(self.remote, "show", "gh-pages:CNAME"), "whaley.example.invalid")
        files = self.git(self.remote, "ls-tree", "-r", "--name-only", "gh-pages").splitlines()
        self.assertIn("assets/new.jpg", files)
        self.assertNotIn("assets/old.png", files)

        unchanged = publisher.publish(self.site, self.repository)
        self.assertFalse(unchanged.changed)
        self.assertEqual(unchanged.commit, second.commit)
        self.assertEqual(self.git(self.remote, "rev-list", "--count", "gh-pages"), "2")
        self.assertEqual(self.source_state(), before)

    def test_explicit_local_remote_is_supported(self):
        before = self.source_state()
        result = publisher.publish(self.site, self.repository, str(self.remote))
        self.assertEqual(self.git(self.remote, "rev-parse", "gh-pages"), result.commit)
        self.assertEqual(self.source_state(), before)

    def test_shared_packager_output_can_be_published(self):
        staged = self.root / "staged"
        shutil.copytree(self.site / "assets", staged / "assets")
        for name in ("main.js", "styles.css"):
            (staged / "assets" / name).rename(staged / name)
        image = staged / "assets/old.png"
        (staged / "assets/provenance.json").write_text(json.dumps({
            "old.png": {"sha256": hashlib.sha256(image.read_bytes()).hexdigest()}
        }))
        template = Path(__file__).resolve().parents[2] / "Scala/server/app/views/index.scala.html"
        generated = self.root / "pages"
        package_web(staged, generated, template, root=self.root, pages=True)

        result = publisher.publish(generated, self.repository)
        self.assertTrue(result.changed)
        self.assertEqual(self.git(self.remote, "show", f"gh-pages:{MARKER}"),
                         (generated / MARKER).read_text().strip())
        self.assertEqual(self.git(self.remote, "show", "gh-pages:index.html"),
                         (generated / "index.html").read_text().strip())
        self.assertIn(".nojekyll", self.git(self.remote, "ls-tree", "--name-only", "gh-pages").splitlines())

    def test_invalid_or_linked_site_never_creates_a_publishing_branch(self):
        for case in ("missing-marker", "empty-js", "git-entry", "symlink"):
            with self.subTest(case=case):
                invalid = self.root / case
                shutil.copytree(self.site, invalid)
                if case == "missing-marker":
                    (invalid / ".nojekyll").unlink()
                elif case == "empty-js":
                    (invalid / "assets/main.js").write_text("")
                elif case == "git-entry":
                    (invalid / "assets/.git").mkdir()
                else:
                    (invalid / "assets/source-link").symlink_to(self.repository, target_is_directory=True)
                with self.assertRaises(publisher.PublicationError):
                    publisher.publish(invalid, self.repository)
                self.assertEqual(self.git(self.remote, "for-each-ref", "--format=%(refname)"), "")

    def test_conflicting_cname_cannot_change_existing_site(self):
        (self.site / "CNAME").write_text("whaley.example.invalid\n")
        original = publisher.publish(self.site, self.repository)
        (self.site / "CNAME").write_text("different.example.invalid\n")
        with self.assertRaisesRegex(publisher.PublicationError, "CNAME differs"):
            publisher.publish(self.site, self.repository)
        self.assertEqual(self.git(self.remote, "rev-parse", "gh-pages"), original.commit)
        self.assertEqual(self.git(self.remote, "show", "gh-pages:CNAME"), "whaley.example.invalid")

    def test_a_concurrent_publication_is_not_overwritten(self):
        publisher.publish(self.site, self.repository)
        before = self.source_state()
        (self.site / "assets/main.js").write_text("console.log('my next build');\n")
        original_git = publisher.git
        competing_commit = None

        def race_before_push(repository, *arguments, **options):
            nonlocal competing_commit
            if arguments[0] == "push":
                competitor = self.root / "competing-publisher"
                self.git(self.root, "clone", "--quiet", "--branch", "gh-pages",
                         str(self.remote), str(competitor))
                self.git(competitor, "config", "user.name", "Concurrent test")
                self.git(competitor, "config", "user.email", "concurrent@example.invalid")
                self.git(competitor, "config", "commit.gpgsign", "false")
                (competitor / "concurrent.txt").write_text("Keep the concurrent publication\n")
                self.git(competitor, "add", "concurrent.txt")
                self.git(competitor, "commit", "--quiet", "-m", "Concurrent publication")
                self.git(competitor, "push", "origin", "gh-pages")
                competing_commit = self.git(competitor, "rev-parse", "HEAD")
            return original_git(repository, *arguments, **options)

        with mock.patch.object(publisher, "git", side_effect=race_before_push):
            with self.assertRaisesRegex(publisher.PublicationError, "Git push failed"):
                publisher.publish(self.site, self.repository)
        self.assertEqual(self.git(self.remote, "rev-parse", "gh-pages"), competing_commit)
        self.assertEqual(self.git(self.remote, "show", "gh-pages:concurrent.txt"),
                         "Keep the concurrent publication")
        self.assertEqual(self.source_state(), before)
