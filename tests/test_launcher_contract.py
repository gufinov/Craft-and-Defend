import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class LauncherContractTests(unittest.TestCase):
    def test_one_click_launcher_uses_provenance_guard(self):
        launcher = (ROOT / "START.cmd").read_text(encoding="utf-8")
        self.assertIn(r"tools\start_game.ps1", launcher)
        self.assertNotIn(r"if exist \"%APP%\"", launcher)
        for option in ("sandbox", "coastercraft", "build", "stop", "help"):
            self.assertIn('if /i "%MODE%"=="' + option + '" goto :' + option, launcher)
        self.assertIn("--coaster-sandbox", launcher)
        self.assertIn("--coastercraft", launcher)
        self.assertIn("taskkill /IM CraftAndDefend.exe", launcher)
        self.assertIn(r"tools\build_windows_f0.ps1", launcher)
        for legacy in ("START_GAME.cmd", "START_COASTER_SANDBOX.cmd", "START_COASTERCRAFT.cmd", "START_F0.cmd", "STOP_GAME.cmd", "BUILD_WINDOWS.cmd", "BUILD_WINDOWS_F0.cmd", "VIEW_NAVIGATION_SPIKE.cmd"):
            self.assertFalse((ROOT / legacy).exists(), legacy)
        self.assertEqual(sorted(path.name for path in ROOT.glob("*.cmd")), ["START.cmd"])

    def test_runners_live_in_tools_runners_and_resolve_the_repository_root(self):
        runners = sorted((ROOT / "tools" / "runners").glob("TEST_*.cmd"))
        self.assertGreaterEqual(len(runners), 14)
        for runner in runners:
            text = runner.read_text(encoding="utf-8")
            self.assertIn(r'for %%I in ("%~dp0..\..") do set "ROOT=%%~fI\"', text, runner.name)
            self.assertIn(r'"%ROOT%tools\start_game.ps1" -PrepareOnly', text, runner.name)
            self.assertNotIn("%~dp0tools", text, runner.name)
            self.assertNotIn("%~dp0artifacts", text, runner.name)
            self.assertNotIn("%~dp0builds", text, runner.name)
            self.assertRegex(text, r"echo [A-Z0-9 ]+ TEST: PASS", runner.name)
        run_all = (ROOT / "tools" / "runners" / "RUN_ALL.cmd").read_text(encoding="utf-8")
        self.assertIn("run_all.ps1", run_all)
        sweep = (ROOT / "tools" / "runners" / "run_all.ps1").read_text(encoding="utf-8")
        self.assertIn("TEST_*.cmd", sweep)
        self.assertIn("_DIAGNOSTIC_NO_OPEN", sweep)
        self.assertIn("_DIAGNOSTIC_NO_PAUSE", sweep)
        self.assertIn("RUN ALL:", sweep)

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
        portable = (ROOT / "tools" / "portable" / "START.cmd").read_text(encoding="utf-8")
        instructions = (ROOT / "tools" / "portable" / "README.txt").read_text(encoding="utf-8")
        self.assertIn("portableLauncherSource", builder)
        self.assertIn("portableReadmeSource", builder)
        self.assertIn("CraftAndDefend.exe", portable)
        self.assertIn("CraftAndDefend.pck", portable)
        self.assertIn("%*", portable)
        self.assertIn("taskkill /IM CraftAndDefend.exe", portable)
        self.assertNotIn(r"tools\portable\STOP_GAME.cmd", builder)
        self.assertIn("'START.cmd'", builder)
        self.assertNotIn("git ", portable.lower())
        self.assertIn("%APPDATA%\\CraftAndDefend\\", instructions)
        self.assertIn("default F2", instructions)


if __name__ == "__main__":
    unittest.main()
