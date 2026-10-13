#!/usr/bin/env python3
"""Exercise release identity and stable build ordering in an isolated Git checkout."""
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("bundle-metadata.py").resolve()


class ReleaseMetadataTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="premiumshot-metadata-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "VERSION").write_text("0.1.6\n")
        (self.root / "BUILD_NUMBER").write_text("2026101201\n")
        (self.root / "icon.plist").write_bytes(plistlib.dumps({}))
        (self.root / "App.app/Contents").mkdir(parents=True)
        self.git("init", "-q")
        self.git("config", "user.name", "Metadata test")
        self.git("config", "user.email", "metadata@example.invalid")
        self.git("add", "VERSION", "BUILD_NUMBER")
        self.git("commit", "-qm", "fixture")

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.root, check=True, capture_output=True)

    def generate(self, config="release"):
        env = {k: v for k, v in os.environ.items() if k not in {"VERSION", "SUPPORT_URL"}}
        return subprocess.run(["python3", str(SCRIPT), "App.app", config, "icon.plist"],
                              cwd=self.root, env=env, capture_output=True, text=True)

    def info(self):
        return plistlib.loads((self.root / "App.app/Contents/Info.plist").read_bytes())

    def testExtractedHistoryStillFollowsLegacyBuildSeven(self):
        self.assertEqual(self.generate().returncode, 0)
        self.assertEqual(self.info()["CFBundleVersion"], "2026101201")
        self.assertGreater(int(self.info()["CFBundleVersion"]), 7)
        self.assertEqual(self.info()["CFBundleIdentifier"], "app.premiumshot.mac")
        self.assertNotIn("PSFeedbackURL", self.info(),
                         "Feedback must stay disabled until receiving and replying are verified")
        self.assertNotIn("PSSupportURL", self.info())

    def testExtraCommitsDoNotChangeARecordedBuild(self):
        self.assertEqual(self.generate().returncode, 0)
        before = self.info()["CFBundleVersion"]
        self.git("commit", "--allow-empty", "-qm", "another fixture commit")
        self.assertEqual(self.generate().returncode, 0)
        self.assertEqual(self.info()["CFBundleVersion"], before)

    def testDevelopmentIdentityIsSeparate(self):
        self.assertEqual(self.generate("debug").returncode, 0)
        self.assertEqual(self.info()["CFBundleIdentifier"], "app.premiumshot.mac.dev")

    def testTaggedBuildCanBeRebuiltButNotReusedForNewSource(self):
        self.git("tag", "v0.1.6")
        self.assertEqual(self.generate().returncode, 0)
        self.git("commit", "--allow-empty", "-qm", "new source")
        self.assertNotEqual(self.generate().returncode, 0)
        (self.root / "BUILD_NUMBER").write_text("2026101202\n")
        self.assertEqual(self.generate().returncode, 0)

    def testEarlierDateThanAnExistingReleaseIsRejected(self):
        self.git("tag", "v0.1.6")
        (self.root / "BUILD_NUMBER").write_text("2026101101\n")
        self.assertNotEqual(self.generate().returncode, 0)

    def testInvalidOrAmbiguousNumbersAreRejected(self):
        for value in ["4", "2026023001", "2026101200", "20261012x1"]:
            with self.subTest(value=value):
                (self.root / "BUILD_NUMBER").write_text(value + "\n")
                self.assertNotEqual(self.generate().returncode, 0)


if __name__ == "__main__":
    unittest.main()
