# P4F — enemy units: orc melee and troll ranged

## Outcome

Owner direction (2026-09-19, two reference images in `docs/reference/owner_art/`): replace the capsule raiders with two recognisable enemy unit models and add a ranged behaviour. The basic raider becomes an **orc melee** with two cleavers, the brute the same orc scaled up with a purple tint, and a new **troll ranged** kind shoots a crossbow from up to nine cells. Everything stays on the P4D wave service (`CoreDefenseService`, `BasicRaider`); no new UI.

## Models (`BasicRaider`, box/cylinder/cone parts under a `Model` node whose origin is the feet, 0.9 below the body origin; front toward -z)

| Kind | `kind` | Model | Named parts (for diagnostics) |
|---|---|---|---|
| Orc melee | `raider` | green skin, bald head with pointed cone ears, red eyes and tusks; red left pauldron with an iron rim, iron diamond and rear spike; baldric with an iron disc; leather belt with an iron buckle; red loincloth front and back; brown boots with fur trim, iron shin plate and iron toe caps; red bracer with an iron plate on the right forearm; two grey cleavers with gold guards and pommels held blade-up and outward | `OrcSwordL`, `OrcSwordR`, `OrcPauldron`, `Torso`, `Head`, `BeltBuckle`, `Loincloth`, `LegL/R`, `ArmL/R` |
| Brute | `brute` | the orc model with purple skin (`8a4a9a`), `Model.scale = 1.25` (pauldron, iron and cleavers kept) | same as the orc |
| Troll ranged | `troll` | blue-grey skin (`7f93b3`), black topknot with a gold band and a ponytail hanging back, beard, amber eyes and white tusks; red shoulder pad over fur with an iron rim and spike on the right shoulder; leather bracers with iron plates and fur trim; red loincloth with a white sigil; quiver of three iron-tipped bolts on the left hip; a wooden crossbow in the right hand (iron-banded stock, gold nut block, grey iron limbs swept back with gold tips, rope string, loaded bolt with an iron tip) with the left hand on the stock | `TrollCrossbow`, `TrollMuzzle` (bolt origin), `TrollBoltLoaded`, `TrollQuiver`, `TrollTopknot`, `TrollShoulderPad` |

Collision stays a `CapsuleShape3D` (radius 0.34, height 1.8; brute 0.42) as a **direct child of the root** (`die()` / `revive()` toggle every `CollisionShape3D` child). `feet_cell()` keeps its 0.9 origin rule. The body still `look_at`s its move direction, so the model's front (-z) leads.

Animation (per-frame maths and Tweens, no AnimationPlayer resources):

- **Walk bob** — `_walk_distance` accumulates the horizontal distance travelled; phase = distance × 4.2 rad/m. Legs scissor ±0.55 rad, orc arms counter-swing ±0.42 rad around their rest pose; trolls keep the crossbow levelled (arms bob ±0.06) and the whole model bobs 5 cm. The swing blends out over ~0.17 s when the body stops.
- **Melee swing** — `play_attack()` on an orc/brute raises one arm (alternating) to 2.4 rad, chops to 0.55 rad and eases back to rest (~0.6 s). The service calls it on every core or structure hit (primary and extra raiders).
- **Shoot pose** — `play_attack()` on a troll kicks the crossbow back 12 cm and the right arm up 0.25 rad, then levels again (~0.36 s).
- **Death** — unchanged: the root topples about z and sinks, the body stays 6 s and frees itself.

## Stats and balance (`contracts/content.json → balance.core_defense`, mirrored in `game/data/content.json` by `tools/format_content.py`)

| Kind | Health | Damage | Speed | Attack | Balance keys (fallback constants in `CoreDefenseService`) |
|---|---|---|---|---|---|
| Orc melee (`raider`) | 20 | 6 | 2.8 | melee, every 1.4 s at the target | `raider_health`, `raider_damage`, `raider_attack_interval_seconds` |
| Brute | 40 | 10 | 0.7× (1.96) | melee, every 1.4 s | `brute_health`, `brute_damage` (constants only; unchanged) |
| Troll ranged | 28 | 5 | 2.4 | ranged, every 2.0 s from ≤ 9 cells | `troll_health`, `troll_damage`, `troll_range`, `troll_attack_interval_seconds` |

`tools/validate_foundation.py` requires the four troll keys (integers ≥ 1 / positive numbers).

## Ranged rule (`CoreDefenseService`)

- `start_prototype(options)` accepts `"trolls": n` next to `"raiders"`, `"brutes"` and `"spawn_distance"`. The primary raider is always a melee orc; extras are assigned brutes first, then trolls, then orcs. Each extra entry carries `ranged`, `range` and `attack_interval` with its `kind`, `health`, `damage` and targeting fields.
- Trolls route like everyone else (`_plan_extra`: open route to the core, or a permitted breach, or stall and retry every 2 s). While a troll is `routing`, `_advance_extras` checks every frame whether its current target (the core cell or the structure it was sent to breach) lies within `range` of its body; if so `_engage_ranged` stops it (`active = false`), turns it toward the target and moves it to `attacking_core` / `attacking_structure` with a 0.3 s first-shot delay. **Line of sight is not required in this slice.**
- Every `attack_interval` seconds `_fire_ranged` turns the troll, plays the shoot pose, spawns a `TrollBolt` (wooden cylinder with an iron cone tip, tweened from `TrollMuzzle` to the target over 0.3 s, freed on arrival) and counts `ranged_shots`; the damage lands with the timer through the existing paths (`_extra_attacks_core` for the core, `workstations.try_damage(target_id, damage)` for a structure). A troll that reaches melee distance keeps shooting. When its structure is destroyed (or gone) it re-plans like the others; the stall → retry loop is unchanged for all kinds.
- Snapshot/restore stores each extra's `kind`; `_spawn_extra_raider` derives troll health, damage, range and interval from the kind, so a restored troll gets troll stats.
- `nearest_raider_position(from, filter)` accepts `"troll"`; the siege weapon panel (`SiegeWeaponPanel.TARGET_FILTERS`) and `WorkstationService.siege_set_target_filter` accept `troll` too.
- Pause menu: **Start Wave Drill** → `{"raiders": 6, "brutes": 1, "trolls": 1, "spawn_distance": 22}`; **Start Siege Drill** → `{"raiders": 12, "brutes": 3, "trolls": 3, "spawn_distance": 28}`.

## Acceptance

- `--p4-enemy-units-automation=gate` (headless): **T144** enemy unit models (a 3-unit wave builds the orc with two cleavers and a pauldron, the brute scaled 1.25 with cleavers, the troll with crossbow/quiver/topknot and no swords; ≥ 40 mesh parts each; one direct collision shape per body; entries 40/10, 28/5 ranged 9 cells 2 s, lead orc 20/6), **T145** troll ranged attack (a troll 14 cells from the core keeps routing and fires nothing; at 6 cells it stops, engages the core, fires a visible bolt and costs the core 5 per shot every 2 s).
- `--p4-enemy-units-automation=visual` (windowed): **T146** renders `p4-enemy-units.png` (1280×720) with an orc, a brute and a troll side by side about four metres in front of the camera.
- `tools\runners\TEST_P4_ENEMY_UNITS.cmd` runs gate then visual on the export.
- Regression: P4 siege units gate/save/restore, P3C phase1, P3B phase1 stay PASS.

## Boundary and next

No line-of-sight or projectile collision (the bolt is presentation; damage lands with the timer). Trolls do not kite or retreat and do not pick a different target than the route planner gives them. The practice `DefenseService` raider still uses the default orc model. Held-item icons for the enemy kinds do not exist (not needed). Next: line of sight and cover, troll targeting of siege machines, more kinds (shaman, ram), owner proportion notes on the two models.
