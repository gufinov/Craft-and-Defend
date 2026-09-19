# Evidence — P4b-1 resource distribution and gold — 2026-09-19

STATUS: PASS (candidate, editor-headless only) — static validation, unit tests and the new `--p4-resources-automation=gate` (T137–T140) pass on the pinned editor build; P1, F2, F3, P3F and P3G regression gates pass. No provenance-matched export and no `TEST_P4_RESOURCES.cmd` run yet (integrator exports). No owner playtest.

DONE: Implemented [the P4b contract](../P4B_RESOURCE_DISTRIBUTION.md) on branch `feature/p4-resources` (worktree `D:\CODEX\Craft_and_Defend\worktrees\p4-resources`): `terrain.ores` table in `world.json` replacing the two P1 magic numbers; table-driven, thread-safe `P1TerrainGenerator._ore_at` (`compile_ores`, cumulative roll bands, per-row depth band and cluster size) that reproduces the P1 coal/iron layout exactly and adds gold from depth 12; `gold_ore` block 11 with placeholder SVG and Godot import; `gold_ore`/`gold_ingot` items, `gold_ingot` furnace recipe and progression goal; derived gold icon atlas (`tools/make_gold_atlas_p4.py`, `gold` atlas key in `measure_item_atlas.py` and `ItemIconCatalog`); `validate_ores` rule plus 11 unit tests; `P4ResourcesAutomation` and `TEST_P4_RESOURCES.cmd`; docs.

EXPECT: Below the surface, coal clusters begin three cells down, iron six, gold twelve; gold is much rarer than iron, which is rarer than coal. A Gold Ore block refuses the Stone Pick and drops one Gold Ore to the Iron Pick. Gold Ore plus Coal in a Furnace auto-start the 8 s Gold Ingot recipe. Existing `terrain_p1_1` saves keep every coal, iron, tree and hill; untouched deep stone may now show gold.

TEST:

| Test ID | Expected | Actual | Result | Evidence |
|---|---|---|---|---|
| Static | `python tools/validate_foundation.py` | PASS: 12 blocks, 28 items, 22 recipes, 148 links | PASS | terminal |
| Unit | `python -m unittest discover -s tests` | 60 tests OK (11 new ore/gold tests) | PASS | terminal |
| Parse | `--check-only` on generator, adapter, icon catalog, diagnostic, app | no errors | PASS | terminal |
| T137 | depth bands, rarity order, determinism | 10,519 cells sampled: coal 397 (shallowest depth 3), iron 121 (6), gold 11 (12); 0 band violations; same-seed identical, other seed differs | PASS | `artifacts/dev-res-p4-gate/run.log` |
| T138 | P1 coal/iron layout preserved, gold additive | 24,439 cells vs P1 reference formula: 0 mismatches; 26 gold cells, 0 over former ore or above depth 12 | PASS | same |
| T139 | gold mining with the right pick | 4 generated gold cells loaded near the clearing; `(-6, -15, 38)`: Stone Pick `WRONG_TOOL`, Iron Pick `OK` drops `gold_ore` ×1, cell now air; content, texture and icons registered | PASS | same |
| T140 | gold smelting | 2 Gold Ore + 1 Coal auto-start `gold_ingot` (8.0 s); after 2 durations Output = Gold Ingot ×2, input 0, idle; collected 2 | PASS | same |
| T37–T39 | P1 phase1 regression | PASS (T38: coal 702, iron 237 samples unchanged from the P1 formula) | PASS | `artifacts/dev-res-p1-phase1/run.log` |
| T40 | P1 phase2 (restart continue) | PASS | PASS | `artifacts/dev-res-p1-phase1/run-phase2.log` |
| T19–T22 | F2 gate (starter coal/iron route) | PASS | PASS | `artifacts/dev-res-f2-gate/run.log` |
| T23–T26 | F3 phase1 persistence | PASS | PASS | `artifacts/dev-res-f3-phase1/run.log` |
| P3F gate | icon regions measured/non-overlapping incl. gold | PASS | PASS | `artifacts/dev-res-p3f-gate/run.log` |
| P3G gate | furnace usability regression | PASS | PASS | `artifacts/dev-res-p3g-gate/run.log` |
| F0 phase1 | shell regression | **T08_REBIND_SAVE FAIL** — pre-existing: the test rebinds Forward to R, which P3H assigned to Rotate Counterclockwise; unrelated to this card | FAIL (pre-existing) | `artifacts/dev-res-f0-phase1/run.log` |
| Exported | `TEST_P4_RESOURCES.cmd` on a provenance-matched build | NOT RUN | NOT RUN | — |
| Owner playtest | dig to depth ≥ 12 with an Iron Pick, smelt gold | NOT RUN | NOT RUN | — |

Command shape (from the worktree root; `<exe>` = `D:\CODEX\_tools\GodotVoxel\4.6-1.6\editor\godot.windows.editor.x86_64.exe`, `4.6.stable.custom_build.89cea1439`):

```
<exe> --headless --path game --import
<exe> --headless --path game --log-file artifacts\dev-res-p4-gate\run.log -- --f0-data-root=artifacts\dev-res-p4-gate --p4-resources-automation=gate
```

LIMITATIONS/FAILURES: Editor-headless only; not exported. Gold art is a re-hued copy of the iron art (documented placeholder). Gold has no consumer yet (no Foundry/market). F0 T08 was already failing before this branch (keybind R reassigned in P3H) and is left as is. The P1 T39 assertion was stale since P3D changed the arrival cue to `HOME CLEARING · IRON MARKER n m`; it now accepts the prefix. Gold is rare near the clearing (surface −1 leaves only y −13…−15 in band); reaching it in play needs digging to bedrock or exploring lower ground.

NEXT: integrator export + `TEST_P4_RESOURCES.cmd`; owner playtest; P4b-2 gold consumers (Foundry commission / market purchase per design direction §5); original gold art.

GIT/REPRODUCIBILITY: branch `feature/p4-resources` from `0be5f75`; one commit (hash in the handoff); engine `4.6.stable.custom_build.89cea1439`; Pillow 12.2.0 for the atlas tools.
