# Runtime implementation boundary

The local agent creates the Godot project here. No `project.godot` is included yet: this delivery is supervisory groundwork and starter data/tooling.

Suggested folders: `scenes/app`, `scenes/player`, `scenes/world`, `scenes/ui`, `scripts/app`, `scripts/world`, `scripts/inventory`, `scripts/crafting`, `scripts/persistence`, `scripts/settings`, `data`, and `assets`.

Read/convert canonical `contracts/*.json` through one content loader. If the fixtures move into game resources, update the validator/docs in the same commit. Do not create independent registries in UI screens.

F0 boots to a menu, reports missing voxel classes clearly and starts a real test world. Unfinished functions stay visibly unavailable. A static mockup does not satisfy the integration gate.
