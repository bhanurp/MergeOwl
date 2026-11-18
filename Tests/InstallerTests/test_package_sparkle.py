import pathlib
import subprocess
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[2] / "scripts/package_sparkle.sh"

class SparklePackagingTests(unittest.TestCase):
    def test_repackaging_removes_files_from_previous_framework(self):
        with tempfile.TemporaryDirectory() as root:
            root = pathlib.Path(root)
            framework = root / "Sparkle.framework"
            framework.mkdir()
            (framework / "Sparkle").write_text("new")
            (framework / "Sparkle").chmod(0o755)
            app = root / "Test.app"
            old = app / "Contents/Frameworks/Sparkle.framework"
            old.mkdir(parents=True)
            (old / "ObsoleteHelper").write_text("stale")
            result = subprocess.run(["bash", str(SCRIPT), str(app), str(framework)], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            self.assertFalse((old / "ObsoleteHelper").exists())
            self.assertEqual((old / "Sparkle").read_text(), "new")

    def test_copies_framework_preserving_symlinks_and_permissions(self):
        with tempfile.TemporaryDirectory() as root:
            root = pathlib.Path(root)
            framework = root / "Sparkle.framework"
            binary = framework / "Versions/B/Sparkle"
            binary.parent.mkdir(parents=True)
            binary.write_text("test fixture")
            binary.chmod(0o755)
            (framework / "Versions/Current").symlink_to("B")
            (framework / "Sparkle").symlink_to("Versions/Current/Sparkle")
            app = root / "Test.app"
            (app / "Contents").mkdir(parents=True)
            result = subprocess.run(["bash", str(SCRIPT), str(app), str(framework)], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            installed = app / "Contents/Frameworks/Sparkle.framework"
            self.assertTrue((installed / "Sparkle").is_symlink())
            self.assertEqual((installed / "Sparkle").read_text(), "test fixture")
            self.assertTrue((installed / "Sparkle").stat().st_mode & 0o111)

    def test_missing_framework_is_rejected_before_creating_app_contents(self):
        with tempfile.TemporaryDirectory() as root:
            app = pathlib.Path(root) / "Test.app"
            result = subprocess.run(["bash", str(SCRIPT), str(app), str(pathlib.Path(root) / "missing")], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(app.exists())

if __name__ == "__main__":
    unittest.main()
