import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class LauncherContractTests(unittest.TestCase):
    def test_one_click_launcher_uses_provenance_guard(self):
        launcher = (ROOT / "START_GAME.cmd").read_text(encoding="utf-8")
        self.assertIn(r"tools\start_game.ps1", launcher)
        self.assertNotIn(r"if exist \"%APP%\"", launcher)

    def test_builder_and_launcher_share_game_tree_manifest(self):
        starter = (ROOT / "tools" / "start_game.ps1").read_text(encoding="utf-8")
        builder = (ROOT / "tools" / "build_windows_f0.ps1").read_text(encoding="utf-8")
        for token in ("build_manifest.json", "HEAD:game", "game_tree"):
            self.assertIn(token, starter)
            self.assertIn(token, builder)
        self.assertIn("Test-GameTreeClean", starter)
        self.assertIn("Rebuilding it now", starter)

    def test_git_ownership_exception_is_repository_scoped(self):
        starter = (ROOT / "tools" / "start_game.ps1").read_text(encoding="utf-8")
        builder = (ROOT / "tools" / "build_windows_f0.ps1").read_text(encoding="utf-8")
        for script in (starter, builder):
            self.assertIn('git -c "safe.directory=$gitSafeDirectory" -C $repositoryRoot', script)
            self.assertNotIn("config --global", script)

    def test_export_includes_standalone_portable_launcher_and_instructions(self):
        builder = (ROOT / "tools" / "build_windows_f0.ps1").read_text(encoding="utf-8")
        portable = (ROOT / "tools" / "portable" / "START_GAME.cmd").read_text(encoding="utf-8")
        instructions = (ROOT / "tools" / "portable" / "README.txt").read_text(encoding="utf-8")
        self.assertIn("portableLauncherSource", builder)
        self.assertIn("portableReadmeSource", builder)
        self.assertIn("CraftAndDefend.exe", portable)
        self.assertIn("CraftAndDefend.pck", portable)
        self.assertIn("%*", portable)
        self.assertNotIn("git ", portable.lower())
        self.assertIn("%APPDATA%\\CraftAndDefend\\", instructions)
        self.assertIn("default F2", instructions)


if __name__ == "__main__":
    unittest.main()
