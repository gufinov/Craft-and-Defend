# Engine decision — ADR 001

Date: 2026-09-10. Status: **selected for prototype; runtime validation pending**.

Use Godot + Zylann Voxel Tools Module edition for Windows x86-64. Foundation uses GDScript, blocky `VoxelTerrain`, `VoxelMesherBlocky`, `VoxelBlockyLibrary`, and `VoxelStreamSQLite`. Start with a simple `CharacterBody3D` and collision-enabled `VoxelViewer`.

| Part | Candidate |
|---|---|
| Release | [Voxel Tools v1.6](https://github.com/Zylann/godot_voxel/releases/tag/v1.6) |
| Editor | Godot 4.6 stable custom build, Godot revision `89cea1439` |
| Voxel source | `595f52ee4e23203a865eeb981f115909f7aa92f4` |
| Precision | Standard single precision |
| Editor archive | `godot.windows.editor.x86_64.exe.zip` |
| Template archive | `godot.windows.template_release.x86_64.exe.zip` |
| Integrity | [versions.json](../tools/versions.json): publisher-reported size/SHA-256 |

Metadata and matching Windows assets were verified. Binaries were not downloaded, locally hashed or run. The release supplies a **release template**; do not invent a debug-template filename or use an assumed `--export-debug` setup. First export uses the matching release template with diagnostic logging. Keep tools outside Git.

A newer Godot 4.7.2 / Voxel Tools 1.7 Module release appears on [the release list](https://github.com/Zylann/godot_voxel/releases). This corrects the report's freshness implication. Retain the researched 4.6/1.6 pairing as a controlled starting point; no claim is made that it is more reliable than 1.7. Reconsider for a relevant defect, security issue, missing API or failed F0. Record new artifacts and rerun the gate.

## Rationale

Voxel Tools handles editable chunk terrain; Godot supplies app/UI/input/native export. This suits a custom first-person game without a Minecraft installation dependency. See [verified sources](TECHNICAL_RESEARCH.md). Capabilities justify prototyping, not performance guarantees.

The Module edition provides a paired editor/template; [upstream guidance](https://voxel-tools.readthedocs.io/en/latest/getting_the_module/) also notes less testing for the extension edition. Never mix official Godot, a Module project and vanilla templates. GDScript avoids an unnecessary C# custom-build toolchain.

No browser wrapper, backend, multiplayer stack or custom mesher is required. Compatibility rendering is an initial **hypothesis** to reduce rendering demands; prove the blocky path in F0 and record a switch to Forward+ if needed. Finite block terrain needs no smooth-terrain LOD system yet.

## Gate and fallback

F0 proves collision, bounded editing, coupled inventory updates, pause/rebind, full restart persistence and Windows export without the editor. Save completion and clean teardown need direct tests.

If it fails, preserve a minimal reproduction, timebox one targeted correction, then evaluate a newer matching Module build if relevant. If still unsuitable, compare Luanti against the same gate and discuss the engine change with Tony. Luanti is not installed or pinned here; refresh its release/license evidence if activated.

Change record: adopted research direction; corrected latest-release wording; separated metadata verification from runtime proof; restored basic day/night to full Foundation; no gameplay implemented.
