# Keybind contract

Canonical fixture: [keybinds.json](../contracts/keybinds.json). Bind named actions through Godot InputMap, using physical QWERTY positions for movement. Runtime rebinding must persist, detect conflicts by active context and provide reset defaults.

F5 candidate status: every currently implemented action below except reserved `reload` has a grouped, searchable editor row with Change and per-action Reset. The centered scrollable panel keeps Reset All available and reports capture/conflict state clearly. Changes persist across a full process restart. Invalid/conflicting stored maps recover to the complete safe default map; live conflicts mutate neither action.

| Action ID | Default | Context |
|---|---|---|
| move_forward | E | gameplay |
| move_backward | D | gameplay |
| strafe_left | S | gameplay |
| strafe_right | F | gameplay |
| sprint | A | gameplay |
| crouch | Z | gameplay |
| jump | Space | gameplay |
| interact | Shift | gameplay |
| inventory | Tab | gameplay |
| build | B | gameplay |
| pause | Escape | system |
| hotbar_1 … hotbar_9 | 1 … 9 | gameplay |
| reload | G | gameplay, reserved until relevant |
| primary | MouseLeft | gameplay |
| secondary | MouseRight | gameplay |
| capture_screenshot | F2 | gameplay |

`Z` implements crouch; prone is deferred. Sprint is hold-to-run initially. `G` is reserved; do not invent a reload mechanic for a pickaxe. Left mouse breaks/dismantles. Right mouse first opens a targeted station and otherwise places the selected item. Shift remains a general future interact action but does not open crafting/processing stations; targeting one explains that right-click is required.

Tab toggles inventory only. B toggles the limited hand-build/crafting modal; a workbench or processing-station modal is entered only by right-clicking that world object. Escape closes the active modal before pausing. F2 captures the game viewport to the global `screenshots` folder without pausing gameplay; it can be rebound like every other implemented action and remains separate from Windows Print Screen focus handling. Preserve an Escape recovery/cancel path even if users rebind their preferred pause action. UI navigation may use conventional keys only while the UI owns input; ESDF gameplay input must not leak through it.

Tests: every required action responds; forward is E (not W); a changed movement key persists after full restart; conflicting assignment is rejected/explained; reset restores these defaults; escape from capture/modal/pause works; repeated UI open/close does not leave mouse capture stuck. Test keyboard layout behavior on Windows rather than assuming logical key codes equal physical positions.
