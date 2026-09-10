# Third-party components and rights ledger

No third-party executable, source code, texture, model or sound is bundled in this groundwork. The original research report is retained as user-supplied planning material. References do not imply copied assets or included dependencies.

| Component | State | License/source | Required before shipping/copying |
|---|---|---|---|
| Godot Engine | Selected external runtime | [MIT and third-party information](https://godotengine.org/license/) | Include applicable engine and bundled-library notices with shipped build |
| Zylann Voxel Tools v1.6 | Selected external Module | [Pinned MIT license](https://github.com/Zylann/godot_voxel/blob/595f52ee4e23203a865eeb981f115909f7aa92f4/LICENSE.md) | Preserve Marc Gilleron notice; inventory module subdependencies in actual build |
| voxelgame | Reference inspected; nothing copied | [Repository](https://github.com/Zylann/voxelgame), inspected commit `4cf747a8456375e527c8c976c50fb24446f9d18f` | Re-audit and record paths if future code/assets are copied |
| solar_system_demo | Reference only | [Repository](https://github.com/Zylann/solar_system_demo) | Audit code and every copied asset separately |
| Luanti / Minecraft mods | Deferred research routes | Not bundled | Review exact packages and terms if activated |

Use original placeholder materials initially. A future asset entry records path, creator, source URL, immutable revision/download date, license, attribution text and modifications. An open-source engine license does not license all assets in its demos. Do not copy Minecraft or Orcs Must Die assets/code into this game.

F0 creates its plain cube models and colors in project-owned GDScript. The Godot/Voxel Tools binaries remain external tools/build inputs and are not committed. No voxelgame code, textures, models, sounds or other demo assets were copied into F0.

Tony has not selected a project source/content license. The public repository's visibility does not by itself grant a permissive license. Do not add MIT/CC0 to original game code/art without his choice. This is an implementation ledger, not a completed distribution audit; audit the actual engine build and final package before release.
