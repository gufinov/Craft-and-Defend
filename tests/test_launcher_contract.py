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


if __name__ == "__main__":
    unittest.main()
