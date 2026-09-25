import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("prepare.sh").resolve()


class ReleasePreparationTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="nzovu-release-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git("init", "-q")
        self.git("config", "user.name", "Release fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("-c", "commit.gpgsign=false", "commit", "--allow-empty", "-qm", "initial")
        self.commit = self.git("rev-parse", "HEAD")
        self.git("update-ref", "refs/remotes/origin/main", self.commit)

    def git(self, *args):
        return subprocess.check_output(
            ["git", *args], cwd=self.root, text=True, stderr=subprocess.STDOUT
        ).strip()

    def prepare(self, tag="v0.0.1", event="push", **env):
        output = self.root / "output"
        output.unlink(missing_ok=True)
        result = subprocess.run(
            ["bash", str(SCRIPT)], cwd=self.root, text=True, capture_output=True,
            env={**os.environ, "GITHUB_EVENT_NAME": event,
                 "GITHUB_REF": f"refs/tags/{tag}", "REQUESTED_TAG": tag,
                 "GITHUB_SHA": self.commit, "GITHUB_REPOSITORY": "adrien19/nzovu",
                 "GITHUB_OUTPUT": str(output), **env},
        )
        values = dict(line.split("=", 1) for line in output.read_text().splitlines()) if output.exists() else {}
        return result, values

    def test_initial_release(self):
        self.git("tag", "v0.0.1")
        result, values = self.prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(values["version"], "0.0.1")
        self.assertEqual(values["commit"], self.commit)
        self.assertEqual(values["prerelease"], "false")
        self.assertEqual(values["image_tag"], "0.0.1")
        self.assertRegex(values["build_date"], r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
        self.assertEqual((self.root / "CHANGELOG.md").read_text(), "## Initial release v0.0.1\n")

    def test_annotated_dispatch(self):
        self.git("-c", "tag.gpgsign=false", "tag", "-am", "first", "v0.0.1")
        result, values = self.prepare(event="workflow_dispatch")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(values["commit"], self.commit)

    def test_semver_classification(self):
        for tag, prerelease in [("v0.0.1-rc.1+build.7", "true"), ("v0.0.1+build-test", "false")]:
            with self.subTest(tag=tag):
                self.git("tag", tag)
                result, values = self.prepare(tag)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(values["prerelease"], prerelease)
                self.assertEqual(values["version"], tag[1:])
                self.assertEqual(values["image_tag"], tag[1:].replace("+", "-"))

    def test_invalid_or_missing_tag(self):
        for tag in ["v0.0.1", "0.0.1", "v01.0.1", "v0.0.1-01", "v0.0.1+", "../main"]:
            with self.subTest(tag=tag):
                result, values = self.prepare(tag)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(values, {})

    def test_commit_outside_main(self):
        self.git("-c", "commit.gpgsign=false", "commit", "--allow-empty", "-qm", "unmerged")
        self.git("tag", "v0.0.1")
        result, _ = self.prepare(GITHUB_SHA=self.git("rev-parse", "HEAD"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not on main", result.stderr)

    def test_wrong_checkout(self):
        self.git("tag", "v0.0.1")
        self.git("-c", "commit.gpgsign=false", "commit", "--allow-empty", "-qm", "later")
        result, _ = self.prepare()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Checkout does not match", result.stderr)

    def test_wrong_event_commit(self):
        self.git("tag", "v0.0.1")
        result, _ = self.prepare(GITHUB_SHA="0" * 40)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("event commit", result.stderr)

    def test_missing_main(self):
        self.git("tag", "v0.0.1")
        self.git("update-ref", "-d", "refs/remotes/origin/main")
        result, _ = self.prepare()
        self.assertNotEqual(result.returncode, 0)

    def test_container_tag_too_long(self):
        tag = "v0.0.1+" + "a" * 128
        self.git("tag", tag)
        result, _ = self.prepare(tag)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("tag limit", result.stderr)

    def test_subsequent_release_notes(self):
        self.git("tag", "v0.0.1")
        self.git("-c", "commit.gpgsign=false", "commit", "--allow-empty", "-qm", "fix: next")
        self.git("update-ref", "refs/remotes/origin/main", "HEAD")
        self.git("tag", "v0.0.2")
        result, _ = self.prepare("v0.0.2", GITHUB_SHA=self.git("rev-parse", "HEAD"))
        self.assertEqual(result.returncode, 0, result.stderr)
        notes = (self.root / "CHANGELOG.md").read_text()
        self.assertIn("fix: next", notes)
        self.assertIn("compare/v0.0.1...v0.0.2", notes)


if __name__ == "__main__":
    unittest.main()
