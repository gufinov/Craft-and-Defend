# Windows development setup

This is a local-agent procedure, not a claim that these commands ran on Tony's PC. No engine is installed by the groundwork tools.

## Inspect first

Inspect `D:\CODEX\Craft-and-Defend` (and any existing known project folder), Git status/remotes/worktrees, available tools, Windows hardware and free disk. Do not overwrite an existing checkout or install over another Godot version. Reuse a correct existing checkout even if its folder has a different name; record it.

For a new root, run the following PowerShell commands individually and stop on a nonzero Git result:

```powershell
$ProjectRoot = 'D:\CODEX\Craft-and-Defend'
New-Item -ItemType Directory -Force $ProjectRoot | Out-Null
git clone https://github.com/gufinov/Craft-and-Defend.git "$ProjectRoot\main"
Set-Location "$ProjectRoot\main"
git remote -v
git status --short
git worktree list
git fetch origin
```

The repo already has a bootstrap commit. Do not reinitialize it. Keep `main` clean. If the foundation PR is still open, base implementation on the explicit groundwork branch:

```powershell
New-Item -ItemType Directory -Force "$ProjectRoot\worktrees" | Out-Null
git worktree add "$ProjectRoot\worktrees\foundation" -b prototype/foundation origin/docs/foundation-groundwork
Set-Location "$ProjectRoot\worktrees\foundation"
python tools/validate_foundation.py
python -m unittest discover -s tests -v
```

If that branch/worktree already exists, inspect and reuse it rather than rerunning creation. If the groundwork is merged and the branch removed, fetch and confirm `origin/main` contains the handoff, then branch from `origin/main`. Do not change refs merely to make a setup snippet succeed. Python 3.11+ is required for repo checks; `py -3` may be used if that is the verified local interpreter.

## Candidate engine acquisition

1. Read [engine decision](ENGINE_DECISION.md) and [versions.json](../tools/versions.json). Check for a known material defect/security issue before installation; do not silently repin.
2. Download exactly the two recorded standard Windows archives from the recorded v1.6 release URLs. Avoid double/tracy/extension variants for this first setup.
3. Put them in a separate folder, for example `D:\CODEX\_tools\GodotVoxel\4.6-1.6\archives`.
4. Run `python tools/verify_toolchain.py --archive-dir '<that archive folder>'`. This compares full archive size and SHA-256 with recorded upstream metadata. It does not validate runtime behavior.
5. Extract editor and template separately. Inspect the actual archive contents; no extracted executable filename is assumed here. Set a **session-only** `$env:GODOT_VOXEL_EXE` to the real standard editor executable, then run `& $env:GODOT_VOXEL_EXE --version`.
6. The local agent creates a tiny Godot probe verifying `ClassDB.class_exists` for VoxelTerrain, VoxelMesherBlocky, VoxelBlockyLibrary, VoxelStreamSQLite and VoxelSaveCompletionTracker. Save probe results in F0 evidence.

## Project and export

After creating the project, launch using the verified executable:

```powershell
& $env:GODOT_VOXEL_EXE --path "$ProjectRoot\worktrees\foundation\game" --editor
```

Create a Windows Desktop export preset named `Windows Desktop`, x86-64, with its **custom release template** pointing to the extracted matching template. Do not hard-code one developer's D: path in committed config. Use a documented local preset overlay/generation step or relative setup path excluded from Git. The agent must implement and test that small step when the actual files/preset exist.

Use `--export-release 'Windows Desktop'` with a destination under the ignored `builds` directory. Do not use a vanilla template or assume a debug template exists. Document the exact tested export command once implemented; do not report an export preset as working merely because it parses.

Close the editor, run the exported executable from a portable folder, and perform F0. Record engine/template hashes, build hash, Windows version, renderer, resolution, actual save directory and results. An installer, code signing, Steam account and store submission are not prerequisites.

## Verified F0 setup — 2026-09-10

The candidate pair was downloaded from the recorded official v1.6 URLs and extracted without changing PATH:

```text
D:\CODEX\_tools\GodotVoxel\4.6-1.6\editor\godot.windows.editor.x86_64.exe
D:\CODEX\_tools\GodotVoxel\4.6-1.6\template\godot.windows.template_release.x86_64.exe
```

The archive verifier passed both publisher hashes. `--version` returned `4.6.stable.custom_build.89cea1439`; the runtime probe returned Voxel Tools `1.6.0 Module` at `595f52ee4e23203a865eeb981f115909f7aa92f4`. Official Godot 4.7.2 was deliberately tested only as the negative control and was rejected with `FATAL_TOOLCHAIN_MISMATCH`.

The tested export path is:

```powershell
& .\tools\build_windows_f0.ps1
```

This generates ignored `game\export_presets.cfg` from `game\export_presets.cfg.in`, inserts the verified local custom release-template path, and runs `--export-release "Windows Desktop"`. The portable output is `builds\CraftAndDefend\CraftAndDefend.exe` plus `CraftAndDefend.pck`. Exact hashes and runtime results are in [F0 evidence](evidence/F0_WINDOWS_INTEGRATION.md).
