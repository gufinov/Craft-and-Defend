# P3H — Balance catalogue, counted fuel and directional controls

Status: CANDIDATE / OWNER PLAYTEST PENDING

## Outcome

Make current gameplay tuning visible and adjustable in the content registry, replace opaque Furnace percentages with an exact counted ratio, and split build-preview rotation into two deliberate directions without changing the ESDF movement layout.

## Runtime contract

- `contracts/content.json` is the canonical current balance fixture; `game/data/content.json` is its validated runtime mirror.
- The named `balance` catalogue owns the live Furnace ratio, connected-tree harvest cap, practice-defense values and core-defense values. Services read these values through `ContentRegistry` and retain guarded defaults only for invalid/missing legacy data.
- This catalogue contains only mechanics that are active now. Tool durability, per-material strike counts and future unit/siege statistics must be added when their owning mechanic is implemented, not as inert values that falsely imply functionality.
- Furnace fuel is counted as work: **1 Coal funds 3 smelting operations**. Starting a job consumes one ore and one operation. When needed, one Coal is consumed and converted into three operations; unused operations stay with that placed Furnace and survive save/reload.
- Existing saves without a residual-operation field load with zero stored operations. Invalid saved remainders are rejected.
- Auto-load counts required fuel with ceiling division. Fifteen Iron Ore therefore requires five Coal at the current ratio. Lowering the target returns excess physical input/fuel transactionally.
- The UI reports the exact ratio and stored operation count; it does not show a misleading fuel percentage.
- Build preview rotates clockwise with `W` and counterclockwise with `R`. Both are independent, persisted, rebindable actions. `Left Shift` remains the Interact action.
- Sword recovery is still the weapon's data-driven cooldown. Feedback now distinguishes the brief between-swing delay from a broken or depleted weapon.

The 1:3 ratio is a transparent prototype balance choice, not a claim of real-world efficiency. It is intentionally easy to count and can be tuned from one registry value after playtesting.

## Gates

| Test | Required evidence |
|---|---|
| T99 — balance catalogue | Active Furnace, harvesting and defense services resolve their named values from the canonical catalogue. |
| T100 — counted Furnace fuel | One Coal produces exactly three retained ingots, a mid-fuel save restores the remainder, and no fourth output is free. |
| T101 — directional controls | W advances one quarter-turn, R reverses it, and Shift remains Interact. |
| T102 — presentation | Rendered evidence visibly shows `1 Coal → 3 items`, stored work and separate W/R Keybind rows. |

Run `TEST_P3H_BALANCE_CONTROLS.cmd`; it prepares the provenance-matched Windows export and controls both the headless and rendered diagnostics.

## Boundaries

P3H does not implement durability, tool repair, per-material strike counts, tree species/leaf decay, siege reloading, ammunition types, firing animation, wave spawning, armies, cavalry or magic. Their ordered contracts are recorded in [Balance, ecology and siege systems](BALANCE_ECOLOGY_AND_SIEGE_SYSTEMS.md).
