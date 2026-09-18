# P3I — Furnace auto-processing

## Outcome

A Furnace works without a manual start (owner direction 2026-09-18). Deposit Raw Input and Fuel, walk away; it processes one item at a time until the input is spent or the Output is blocked, exactly as the P3E/P3G container contract already allowed for the *next* item after the first.

## Runtime contract

- `WorkstationService.advance()` first calls `_auto_start_idle_furnaces()`: every placed Furnace with no active job whose `input` stack matches a furnace recipe (`furnace_recipe_for_input`) attempts `try_start_furnace`. The same transaction as before runs, so input, counted fuel, single-job and output-capacity rules are unchanged; failure is silent and re-tried next tick.
- Nothing starts while the simulation is paused (`advance` returns early), so a paused game never advances a Furnace.
- The furnace panel's action button becomes **Load from Inventory** (`try_load_furnace_recipe`); the idle progress label says the Furnace runs automatically. `GameSession.try_craft` for a furnace still starts a job directly for existing diagnostics.
- Live processing while the menu is closed was already true (`GameSession._process` advances workstations); this slice removes the only manual step.

## Owner playtest corrections (2026-09-18, round 2)

- **Fuel model 2.** The burning Coal stays in the Fuel slot until its last operation is spent; `furnace_fuel_operations` is the operations left on the Coal at the top of the stack and the stack count includes it (`_fuel_operations_for`, `_fuel_count_for_operations`). Legacy saves (records without `fuel_model: 2`) get the burning Coal put back on restore so no operations are lost.
- **Chained time.** `advance()` carries leftover time into the job it chains, so a large step finishes as many items as the elapsed time funds (bounded to 256 per call).
- **Gestures.** Drag and drop, the auto-load slider, right-click half pick/one-deposit and double-click move-all remain. New: click an ore or Coal to select it, then click Raw Input / Fuel to add **+1** (Shift+click **+5**); Shift+click on an inventory ore/Coal adds **+5** to its role slot; the panel button is **Load ×1 · Shift+Click ×5** batches through the auto-load target. `WorkstationService.try_transfer_inventory_item_to_furnace(instance_id, item_id, amount)` backs the counted moves.

## Acceptance

- T107 (P3G gate): input + fuel deposited, never started by hand → idle before the tick, active after one unpaused tick, not started under `paused = true`, two inputs become two retained ingots, one stored fuel operation per item, returns to idle when the input is spent; the burning Coal stays in the slot with one operation left; a 3-ore/1-Coal furnace finishes three ingots and only then loses the Coal; counted `+N` transfers move `min(N, carried)`.
- T95 now expects the burning Coal to remain in the slot after the first item.
- T22, T84–T88, T93–T98 unchanged and passing.

## Boundary

No hoppers or automation blocks, no chest runtime, no recipe changes, no change to fuel accounting.
