# P3I — Furnace auto-processing

## Outcome

A Furnace works without a manual start (owner direction 2026-09-18). Deposit Raw Input and Fuel, walk away; it processes one item at a time until the input is spent or the Output is blocked, exactly as the P3E/P3G container contract already allowed for the *next* item after the first.

## Runtime contract

- `WorkstationService.advance()` first calls `_auto_start_idle_furnaces()`: every placed Furnace with no active job whose `input` stack matches a furnace recipe (`furnace_recipe_for_input`) attempts `try_start_furnace`. The same transaction as before runs, so input, counted fuel, single-job and output-capacity rules are unchanged; failure is silent and re-tried next tick.
- Nothing starts while the simulation is paused (`advance` returns early), so a paused game never advances a Furnace.
- The furnace panel's action button becomes **Load from Inventory** (`try_load_furnace_recipe`); the idle progress label says the Furnace runs automatically. `GameSession.try_craft` for a furnace still starts a job directly for existing diagnostics.
- Live processing while the menu is closed was already true (`GameSession._process` advances workstations); this slice removes the only manual step.

## Acceptance

- T107 (P3G gate): input + fuel deposited, never started by hand → idle before the tick, active after one unpaused tick, not started under `paused = true`, two inputs become two retained ingots, one stored fuel operation per item, returns to idle when the input is spent.
- T22, T84–T88, T93–T98 unchanged and passing.

## Boundary

No hoppers or automation blocks, no chest runtime, no recipe changes, no change to fuel accounting.
