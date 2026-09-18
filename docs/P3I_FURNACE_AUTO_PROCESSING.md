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

## Owner playtest corrections (2026-09-18, round 3)

- **Fuel timing.** "Fuel will not run out until the last bar processes": the burning Coal stays in the Fuel slot until the last job it funds **completes**, not when that job starts. `furnace_fuel_operations` is still the operations left on the lit Coal; a new persisted `furnace_fuel_burning: bool` marks that Coal as lit so a lit Coal with 0 operations left stays in the slot while its final job runs and funds nothing further (`_fuel_operations_for` / `_fuel_count_for_operations` / `_furnace_available_operations` take the flag). `advance()` calls `_release_exhausted_fuel()` on `JOB_COMPLETED`, before the next job chains; `try_start_furnace` never removes Coal. `furnace_fuel_status` reports `burning`. Snapshot/restore round-trips the flag; records without it are treated as lit exactly when operations remain (a round-2 record with 0 operations and Coal in the slot is an unlit Coal, which is what round 2 meant).
- **Panel height.** The crafting modal fits the 1280×720 canvas in furnace and workbench modes: the auto-load help moved into the slider/label tooltips, the grid help and auto-load labels wrap to at most two lines, the output label and message are capped at two lines (message reserves 40 px so it never pushes the buttons), and the Load/Clear buttons are 40/36 px. T98 asserts the clear button and message bottoms are ≤ viewport height in both modes.
- **Select-then-add.** Clicking an ore or Coal tile highlights it with the recipe-card gold border and the message reads "Iron Ore selected — click Raw Input to add 1, Shift+Click adds 5" (Coal names Fuel). The recipe is inferred without the recipe book (`_recognize_furnace_recipe`: running job → staged slots satisfy a recipe → `furnace_recipe_for_input` of the staged Raw Input → of the selected tile → the only furnace recipe), so the auto-load slider and the **Load ×1 · Shift+Click ×5** button are enabled as soon as ore can be loaded. The button is now additive: `WorkstationService.try_load_furnace_batches(instance_id, recipe_id, batches)` adds up to `batches` inputs from the inventory and tops Fuel up with the Coal owed to the staged input; it never returns items (`can_load_furnace_batch` drives the button state). The slider keeps the exact-target semantics.

## Acceptance

- T107 (P3G gate): input + fuel deposited, never started by hand → idle before the tick, active after one unpaused tick, not started under `paused = true`, two inputs become two retained ingots, one stored fuel operation per item, returns to idle when the input is spent; the burning Coal stays in the slot with one operation left; a 3-ore/1-Coal furnace still holds the Coal (0 left, burning, 0 available) while the third job runs and loses it only when that job completes; the lit Coal round-trips snapshot/restore (with and without the round-3 field); counted `+N` transfers move `min(N, carried)`.
- T95 expects the burning Coal to remain in the slot, marked burning, after the first item.
- T114 (P3G gate): select-then-add through the app handlers, recipe inferred without the book, additive Load ×1. T115 (P3G visual): the same gesture through real viewport mouse events. T98 (P3G visual) asserts the modal fits the canvas.
- T22, T84–T88, T93–T97, T100 unchanged and passing (T87 checks the persistence note in the help tooltip).

## Boundary

No hoppers or automation blocks, no chest runtime, no recipe changes. Fuel accounting is unchanged in quantity (one Coal = `furnace.operations_per_fuel` items); only the moment the spent Coal leaves the slot moved.
