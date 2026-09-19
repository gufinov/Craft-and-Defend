# P3D — tools and world feedback

Status: CANDIDATE PASS / OWNER PLAYTEST PENDING

## Outcome

Make frequent crafting, gathering and block placement readable and efficient in first person while preserving the existing inventory, terrain, placement and save authorities.

## Player-visible contract

- Clicking an immediate recipe craft button requests one batch. Holding Shift while clicking requests exactly five full batches.
- Five-batch crafting is one atomic inventory transaction: all required inputs and output capacity are validated before anything changes. It does not mean “craft as many as possible.”
- Timed Furnace jobs remain one reserved job at a time; Shift does not silently create a processing queue.
- The active hotbar item is the sole authority for the held presentation. Sword, picks and axe render raised; placeable blocks render lower. Empty slots show no held model.
- Placeable blocks expose a green/red world ghost from `InteractionService.preview_place_item`; the committing placement path reuses that validation.

## Tool and resource contract

- `wood_axe` is a one-stack Workbench tool made from 3 Planks and 2 Sticks.
- Using the selected axe on a Log gathers only that targeted block. Capacity is checked before mutation and its one drop commits in one inventory revision.
- Ordinary hands and non-axe tools also retain one-block gathering. The slice does not recursively fell trunks, branches or arbitrary connected player buildings.
- The fixed `terrain_p1_1` iron vein remains at its existing authored cells. A visible marker above it says to dig two blocks; no terrain regeneration, save migration, free ore or global detector is introduced.
- Iron ore still requires Stone Pick tier 2 and Furnace processing with coal.

## Visual asset provenance

The P3D 1536×1024 atlas is a non-destructive successor to the P3C original atlas. OpenAI's built-in image generation editor replaced only the unused shield cell with a distinct medieval Wood Axe while preserving the exact 6×4 canvas, grid, background and every other icon. Prompt intent: “replace only row 4 column 4 with a warm-brown-handled, gray-iron-headed wood axe; preserve every other pixel-region concept; no text or watermark.” The committed PNG SHA-256 is `46f46eb49e3ad8be4477a1ffdbae333860d60f2281800dfdd5c31c028ded85cf`.

## Gates

| Test | Required evidence |
|---|---|
| T79 — Shift craft | Exact five-batch success is one revision; insufficient input leaves the snapshot unchanged. |
| T80 — held presentation | Tool models exist above the lower block model and track active hotbar identity. |
| T81 — axe | One targeted starter-trunk Log is gathered; the three upper Logs remain in place. |
| T82 — world feedback | Block preview returns shared validity; marker text exists above a real guaranteed iron cell. |
| T83 — rendered presentation | Two 1280×720 images visibly show the held axe/marker and held block/placement ghost. |

## Boundaries

No tool durability, speed balance, animation rig, audio, drops physics, recursive tree simulation, ore radar, procedural resource expansion, armor behavior, player health, waves or campaign systems are claimed here.
