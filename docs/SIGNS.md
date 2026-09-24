# Signs

Owner commission: [Development Expo handoff](DEVELOPMENT_EXPO_HANDOFF.md) section 9. A sign is an ordinary reusable gameplay asset — craftable, placeable, dismantleable, saved — not a development-only prop. The Expo's Supply Depot and district signs use the same item and the same API.

## The three boards

A sign comes in three sizes. They are **three items and three entities**, not
one item with a placement option:

| | Sign | Wide Board | District Board |
| --- | --- | --- | --- |
| Item / entity id | `sign` | `sign_board` | `sign_board_large` |
| Category / stack | `building`, 16 | `building`, 16 | `building`, 16 |
| Workbench recipe | 2 Planks + 1 Stick → 1 Sign (`recipe_book_order` 218) | 4 Planks + 2 Sticks → 1 Wide Board (`recipe_book_order` 219) | 6 Planks + 3 Sticks → 1 District Board (`recipe_book_order` 225) |
| Footprint | one cell (`occupied_offsets` `[[0, 0, 0]]`) | two cells (`[[0, 0, 0], [0, 0, 1]]`) | three cells (`[[0, 0, 0], [0, 0, 1], [0, 0, 2]]`) |
| Support (ground mount) | the cell below | the cell below each of the two | the cell below each of the three |
| Board | 0.92 × 0.86 m, one post | 1.92 × 0.86 m, a post at each end | 2.92 × 1.50 m, a post under each cell |
| Integrity | 8, repaired with 2 Planks | 12, repaired with 2 Planks | 16, repaired with 2 Planks |
| Icon | `icon_sign` (derived atlas cell 31) | `icon_sign_board` (derived atlas cell 32) | `icon_sign_board_large` (derived atlas cell 35) |

The Expo's district entrance boards are the District Board and its exhibit
boards are the Wide Board (signs card 3): the campus is read walking past, from
four to six metres, and the owner asked for bigger boards. A district board
that finds no run of three supported cells still falls back to the Wide Board
rather than being lost — but for a **district** that is now a gate failure and
not a footnote (card D2, T233/T246), and a district may carry its own
`sign_anchor` / `sign_facing` in the Expo manifest to stand its board where
three cells do fit. The central plaza's board is a District Board on its own
pad, no longer the narrowest board on the campus. The narrow `sign`
stays for the player's own use, and none of this restricts placement - any of
the three places anywhere the mount rules allow.

Everything else is shared: the same stored `sign` block, the same editor panel,
the same `configure_sign` / `sign_data` API and the same board renderer.
`WorkstationService.is_sign(entity_id)` is the one predicate that decides
whether a record is a sign, and all three ids are in
`WorkstationService.SIGN_ENTITIES`.

**Why a second item and not a rotation option.** The build rotation (W / R) is
already the sign's facing, and which way a board reads is the whole point of a
board, so it cannot also cycle a width. More importantly, one entity = one
footprint is how the placement stack works: `occupied_offsets` comes from the
entity definition and is what `preview_placement`, `try_reserve`, the saved
record and `restore` all read. A per-placement width would have to be threaded
through every one of them, for a choice the player makes at the workbench
anyway. The second recipe costs two data rows and an icon and changes no
placement code.

Balance is tunable; nothing here copies an external game's asset.

## Placement

The sign uses the existing mount rules (`WorkstationService.try_place` / `_wall_side`, the same path as the Torch and the Wall Lantern), so `mount.allowed` is `["ground", "wall"]`:

- **ground** — the cell below is solid: the board rides at **head height** (its centre 1.65 m above the floor the sign stands on) on an oak post that reaches that floor, with a stone foot where it meets it, turned by the ordinary build rotation (W / R);
- **wall** — no ground below, a solid block on one side: the board hangs flat on that block on two iron brackets, with no post, **centred at eye height** (1.55 m above the floor of the cell it is placed against), rotated to face away from the wall.

**Why the board leaves its own cell upwards** (signs card 3). The owner's
complaint was a board standing knee-high on a stub post: the old board sat
0.06 m above its anchor cell's centre, so it was read looking down from two
metres away instead of straight ahead from five. A board at head height cannot
also fit inside one 1 m cell, so the rule is now horizontal: every part of the
sign stays inside its own **column** - its own cell or cells and the air above
them - and never reaches sideways into a cell another entity owns. The post
occupies the sign's own cell, not the cell in front of it, so the board is
still walked up to and read. `GameSession.sign_board_centre_y(mount)` and
`sign_board_world_height(mount)` are the one place those two heights live, and
T232 reads them back off the built board.

The chosen mount is stored on the station record as `"mount": "wall"` (absent means ground) so a reload does not ask a wall sign for ground support. Every part of the board, posts and collision stays **inside the sign's own logical cells**: a thin panel can never reach into a cell another entity owns, and a sign cannot be placed into an occupied cell (`OCCUPIED`). To hang a sign above a chest, place it in the cell above — the Expo's authored fixtures do exactly that.

The board faces local +X, so a ground sign turns with the build rotation and a wall sign faces the room.

**The wide board's second cell** is the anchor's own local +z, so it turns with
the board exactly as `EntityFootprintService.rotate_offset` says: at rotation 0
(reading east) it is the neighbour at +z, at rotation 1 (reading south) the
neighbour at -x, and so on. **Both** cells are reserved, both want support under
them on the ground mount, and a placement whose second cell is taken is refused
`OCCUPIED` even when the anchor itself is free. The board runs from -0.5 to
+1.5 in local z, so it is centred over the pair and never overhangs it.

## Content model

The station record carries one `sign` block of stable ids and text — never a label, a scene path or an array index:

```
"sign": {
  "mode": "text" | "split" | "items" | "header_items" | "header_body",
  "text_a": String,   # the single text, the left text, or the header
  "text_b": String,   # the right text of a split sign, or the subheader
  "text_c": String,   # the body of a stacked sign
  "items": [item_id, ...]   # up to 8 item ids, in board order
}
```

It is saved by `workstations.snapshot()` with the rest of the record and normalised on `restore()`: an unknown mode falls back to `text`, text is trimmed to `SIGN_TEXT_LIMIT` (256) characters and unknown or surplus item ids are dropped. The SIGN editor's own text line stops at `SIGN_EDITOR_TEXT_LIMIT` (64) so a hand-typed board stays a heading; the longer stored limit exists for an authored board — the Development Expo's district and exhibit signs carry the manifest's whole body paragraph in `text_b`. A record written before this feature (or an authored one without the block) **migrates** to an empty single-text sign instead of failing the load.

## The five display modes

1. **Single Text** — `text_a` centred on the board.
2. **Split Text** — `text_a` and `text_b` side by side with a carved divider. It stays for genuinely two-column content; it is no longer what an authored board gets by default.
3. **Item Grid** — up to eight entries as icon + readable name, 4 rows × 2 columns, filled left column top-to-bottom then right column.
4. **Header + Item Grid** — `text_a` as a heading above the same grid.
5. **Header + Subheader + Body** (`header_body`, signs card 3) — `text_a`, `text_b` and `text_c` **stacked**, one under another, each in its own band of the board. This is what the Expo's district and exhibit boards use.

### The stacked board

The owner's words were "over under text, like header, subheader, content".
The three roles share the board's height in the proportion 0.26 / 0.18 / 0.56,
and a role with no text gives its band to the roles that have some, so a
header-only board still fills the panel. Each role is sized for its own band by
the same typographer every other field uses, and then capped under the role
above it (subheader ≤ 0.72 of the header, body ≤ 0.85 of the subheader), so the
rendered order is **header > subheader > body** even when a long header has had
to shrink. The floors are `SIGN_MIN_HEADER_HEIGHT` 0.10 m,
`SIGN_MIN_SUBHEADER_HEIGHT` 0.070 m and `SIGN_MIN_BODY_HEIGHT` 0.055 m of cap
height - all well above the 0.030 m floor the other modes use, because a
district board is read from five metres, not from arm's length.

**Centred, not left-aligned.** Every field on one of these boards is one to
three short lines read from four to six metres. A ragged left column under a
centred headline reads as a mistake at that distance, and a left-aligned header
over a centred body reads as two boards. Centred keeps the three roles on one
axis.

The labels are named `SignHeader` / `SignSubheader` / `SignBody` on the board's
`SignFace`, which is how T232 reads back the size each role rendered at.

The board renders with `Label3D` text and `Sprite3D` item icons (the same `ItemIconCatalog` art the inventory uses), the project's existing in-world text approach. Captions carry a pale outline so they read on the oak grain.

## Typography: lay out first, shrink last

`GameSession.fitted_sign_text(text, width, height, preferred, minimum)` is the
board's typographer, and every field on a board goes through it:

1. **Wrap on words.** `wrap_sign_text` packs whole words into lines that fit the
   column; a word is never split. The `Label3D` behind it uses
   `AUTOWRAP_WORD` rather than `AUTOWRAP_WORD_SMART`, so the renderer cannot
   split one either. This is what ended `DEVELO / PMENT / EXPO`.
2. **Size for the board, then step down.** The fitter starts at the field's
   preferred cap height — a heading is sized for the board's own width — and
   steps down only while the wrapped block does not fit the panel, or while a
   single word is still wider than the column.
3. **Stop at a readable size.** `SIGN_MIN_LINE_HEIGHT` (0.030 m) for text and
   `SIGN_MIN_CAPTION_HEIGHT` (0.032 m, which still reads at about 4 m) for grid
   captions are floors, not suggestions.
4. **Fewer lines, not smaller glyphs.** Content that still will not fit at the
   floor loses whole lines, and the last kept line ends in an ellipsis.

The item grid lays each entry out as **its icon at the head of the row with its
name beside it**, so a row that is much wider than it is tall spends that width
on size instead of on empty board. On the wide board the Supply Depot's eight
entries read at about four metres.

A one-cell board carrying a six-line route list is still a one-cell board: it
now wraps on words and keeps a readable size, and the cure for a long list is
the wide board.

## The editor panel

Right-click a placed sign (the ordinary station interaction) and the SIGN panel opens in the app's existing modal language — `AppState.SIGN`, the world still running under it (the live-menu contract; only the pause menu pauses). Escape or **Close** leaves without writing; **Save** writes the record.

The panel holds the four mode buttons, the text field(s) of the active mode, the eight item slots (each a tile showing icon + name) and the item picker. It is **not** a dropdown: a category strip comes first, then an icon + readable-name grid, exactly like the inventory and recipe book. Click a slot, then an item, and the selection walks to the next slot; **Clear Selected Slot** and **Clear All Slots** empty them. Clearing a slot in the middle closes the gap when the record is written — the board shows the remaining entries in order.

## Categories

`game/scripts/ui/item_categories.gd` (`ItemCategories`) owns the single mapping from item id to Expo category (handoff section 8): an explicit per-item table, a fallback from the content `category` field, and `unassigned` for anything neither places, so a new visible item is surfaced rather than lost. `ItemCategories.category_of(item_id, content_category)`, `label_of(category_id)` and `grouped(registry)` are the API. The Supply Depot card owns the depot's own use of this mapping and may extend it; existing ids and their order stay.

## API for other systems

```
GameSession.configure_sign(instance_id, data) -> Dictionary   # {"ok", "reason", "details": {"sign": …}}
GameSession.sign_data(instance_id) -> Dictionary              # the normalised block, {} when not a sign
```

`data` may carry any subset of `mode` / `text_a` / `text_b` / `items`; what it omits keeps its current value. An unknown mode (`INVALID_SIGN_MODE`), an unknown item id (`UNKNOWN_SIGN_ITEM`) or a ninth item (`INVALID_SIGN_ITEMS`) is rejected without changing the record. `WorkstationService.configure_sign` / `sign_data` / `sign_mount` are the service-level calls underneath; configuring through the session also rebuilds the board's face.

## Tests

`T232_SIGN_STACKED` (`--p3d-usability-automation=phase1`) for the stacked mode,
the rendered size order and the two mounting heights, with the rendered
evidence `T232_SIGN_STACKED_PRESENTATION` (`p3d-sign-stacked-board.png`, read
from five metres at standing eye height); `T233_EXPO_BOARDS`
(`--development-expo-automation=gate`) and its `T233V_DISTRICT_BOARD_VIEW` for
the Expo's district boards;
`T212_SIGN_PLACEMENT_AND_EDITOR` (`--p3d-usability-automation=phase1`), which
also places the wide board on the ground and on a wall, checks that it reserves
both of its cells, refuses a pair whose second cell is taken and round-trips its
content through a real save; the rendered evidence `T212_SIGN_PRESENTATION` and
`T212_SIGN_WIDE_PRESENTATION` (`--p3d-usability-automation=visual`,
`p3d-sign-item-grid.png` and `p3d-sign-wide-board.png`); and
`T225_SIGN_ANCHORS` (`--development-expo-automation=gate`) for the Expo's use of
both boards; and `T246_PLAZA_BOARD` (`--development-expo-automation=gate`) for
the plaza's three-cell board at its district anchor, with no district board
anywhere falling back to a narrower width. See [the test plan](TEST_PLAN.md).
