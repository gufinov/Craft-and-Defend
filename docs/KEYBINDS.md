# Keybind contract

Canonical fixture: [keybinds.json](../contracts/keybinds.json). Bind named actions through Godot InputMap, using physical QWERTY positions for movement. Runtime rebinding must persist, detect conflicts by active context and provide reset defaults.

F1 implementation status: every currently implemented action below except reserved `reload` has a visible scrollable editor row and accepts keyboard or mouse input. Changes persist across a full process restart. Invalid/conflicting stored maps recover to the complete safe default map; the UI explains live conflicts without mutating either action.

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
| pause | Escape | system |
| hotbar_1 … hotbar_9 | 1 … 9 | gameplay |
| reload | G | gameplay, reserved until relevant |
| primary | MouseLeft | gameplay |
| secondary | MouseRight | gameplay |

`Z` implements crouch; prone is deferred. Sprint is hold-to-run initially. `G` is reserved; do not invent a reload mechanic for a pickaxe. Left mouse breaks/uses; right mouse places/uses secondary; Shift interacts with a targeted workstation. Workstation interaction wins only when it is a valid target and the overlay owns input after opening.

Tab inventory and Escape system pause reconcile earlier menu wording. Preserve an Escape recovery/cancel path even if users rebind their preferred pause action. UI navigation may use conventional keys only while the UI owns input; ESDF gameplay input must not leak through it. Modifier-only Shift requires deliberate capture handling and clear display.

Tests: every required action responds; forward is E (not W); a changed movement key persists after full restart; conflicting assignment is rejected/explained; reset restores these defaults; escape from capture/modal/pause works; repeated UI open/close does not leave mouse capture stuck. Test keyboard layout behavior on Windows rather than assuming logical key codes equal physical positions.
