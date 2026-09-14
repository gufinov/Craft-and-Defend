# Evidence — P3G Furnace usability and placed siege identity — 2026-09-14

STATUS: SOURCE GATE PASS — matching Windows export and owner ultrawide playtest pending

DONE:

- Added maximum-legal-amount Shift+Click transfer in Furnace/inventory surfaces while retaining drag, split and one-item gestures.
- Added a reversible 0–64 Furnace auto-load target that fills each ingredient independently from available material.
- Added live per-item progress, retained Output, and automatic continuation through already-loaded complete batches.
- Allowed only the active Furnace appliance clock to advance while its modal keeps world simulation paused.
- Replaced the placed Catapult's generic boxes with an original detailed low-poly prototype.
- Added `TEST_P3G_FURNACE_USABILITY.cmd`.

EXPECT:

Shift+Click Ore or Coal to move it into the proper Furnace slot and Shift+Click a Furnace stack to return it. Choosing Iron Ingot enables Auto-load; setting 15 with 15 Ore/10 Coal stages 15/10. Start once and watch one progress bar reset for each retained ingot. The world remains paused behind the panel. A placed Catapult is visibly a wheeled siege engine.

TEST:

| Test ID | Result | Evidence |
|---|---|---|
| T93–T97 source runtime | PASS | `artifacts/p3g-source-gate-2/gate.log` and JSON |
| T98 exported render | PENDING | matching Windows export required |
| Static | PASS | 11 blocks, 26 items, 21 recipes; 38/38 Python tests |

LIMITATIONS/FAILURES:

- Matching Windows export and inspected T98 images are still required before candidate delivery.
- The engine emits a non-blocking certificate-store warning in restricted runs.

NEXT:

Build the provenance-matched Windows export, run T93–T98 from it, inspect both images, run affected P3E/P3F regressions, then give Tony the normal playable path and one-click diagnostic.

GIT/REPRODUCIBILITY:

- Active worktree: `D:\CODEX\Craft_and_Defend\worktrees\p3d-tools-world-feedback`; branch `feature/p3d-tools-world-feedback`.
- No merge, push or release authorized or performed.
