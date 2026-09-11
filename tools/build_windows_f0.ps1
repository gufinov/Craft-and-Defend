[CmdletBinding()]
param(
    [string]$GodotExe = $env:GODOT_VOXEL_EXE,
    [string]$TemplateExe = $env:GODOT_VOXEL_TEMPLATE
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$gitSafeDirectory = $repositoryRoot.Replace('\', '/')

function Find-PinnedToolRoot {
    $cursor = [System.IO.DirectoryInfo]::new($repositoryRoot)
    while ($null -ne $cursor) {
        $candidate = Join-Path $cursor.FullName '_tools\GodotVoxel\4.6-1.6'
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            return $candidate
        }
        $cursor = $cursor.Parent
    }
    return $null
}

$pinnedToolRoot = $null
if ([string]::IsNullOrWhiteSpace($GodotExe) -or [string]::IsNullOrWhiteSpace($TemplateExe)) {
    $pinnedToolRoot = Find-PinnedToolRoot
    if ([string]::IsNullOrWhiteSpace($pinnedToolRoot)) {
        throw 'Pinned Godot/Voxel Tools folder was not found in any repository ancestor. Set GODOT_VOXEL_EXE and GODOT_VOXEL_TEMPLATE for a custom location.'
    }
}

if ([string]::IsNullOrWhiteSpace($GodotExe)) {
    $GodotExe = Join-Path $pinnedToolRoot 'editor\godot.windows.editor.x86_64.exe'
}
if ([string]::IsNullOrWhiteSpace($TemplateExe)) {
    $TemplateExe = Join-Path $pinnedToolRoot 'template\godot.windows.template_release.x86_64.exe'
}

$GodotExe = [System.IO.Path]::GetFullPath($GodotExe)
$TemplateExe = [System.IO.Path]::GetFullPath($TemplateExe)
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
    throw "Pinned Godot/Voxel Tools editor not found: $GodotExe"
}

& (Join-Path $PSScriptRoot 'configure_windows_export.ps1') -TemplateExe $TemplateExe

$gameRoot = Join-Path $repositoryRoot 'game'
$buildRoot = Join-Path $repositoryRoot 'builds\CraftAndDefend'
$buildExe = Join-Path $buildRoot 'CraftAndDefend.exe'
$buildPck = Join-Path $buildRoot 'CraftAndDefend.pck'
$manifestPath = Join-Path $buildRoot 'build_manifest.json'
$logPath = Join-Path $repositoryRoot 'artifacts\windows_export.log'
New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $logPath) -Force | Out-Null

$arguments = @(
    '--headless',
    '--path', $gameRoot,
    '--log-file', $logPath,
    '--export-release', '"Windows Desktop"',
    $buildExe
)
$process = Start-Process -FilePath $GodotExe -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
if ($process.ExitCode -ne 0) {
    throw "Godot export failed with exit code $($process.ExitCode). See $logPath"
}
if (-not (Test-Path -LiteralPath $buildExe -PathType Leaf)) {
    throw "Godot reported success but did not create $buildExe"
}
if (-not (Test-Path -LiteralPath $buildPck -PathType Leaf)) {
    throw "Godot reported success but did not create $buildPck"
}

$exeHash = (Get-FileHash -LiteralPath $buildExe -Algorithm SHA256).Hash.ToLowerInvariant()
$pckHash = (Get-FileHash -LiteralPath $buildPck -Algorithm SHA256).Hash.ToLowerInvariant()
$sourceCommit = $null
$gameTree = $null
if ((Test-Path -LiteralPath (Join-Path $repositoryRoot '.git')) -and (Get-Command git -ErrorAction SilentlyContinue)) {
	$sourceOutput = @(& git -c "safe.directory=$gitSafeDirectory" -C $repositoryRoot rev-parse HEAD 2>&1)
	$sourceExitCode = $LASTEXITCODE
	$sourceCommit = ($sourceOutput | Select-Object -First 1)
	if ($sourceExitCode -ne 0 -or $sourceCommit -notmatch '^[0-9a-fA-F]{40}$') {
		throw "Windows export completed, but source-commit provenance could not be resolved: $sourceCommit"
	}
	$gameTreeOutput = @(& git -c "safe.directory=$gitSafeDirectory" -C $repositoryRoot rev-parse HEAD:game 2>&1)
	$gameTreeExitCode = $LASTEXITCODE
	$gameTree = ($gameTreeOutput | Select-Object -First 1)
	if ($gameTreeExitCode -ne 0 -or $gameTree -notmatch '^[0-9a-fA-F]{40}$') {
		throw "Windows export completed, but game-tree provenance could not be resolved: $gameTree"
	}
}
$engineVersion = (& $GodotExe --version | Select-Object -First 1)
$manifest = [ordered]@{
    schema_version = 1
    source_commit = $sourceCommit
    game_tree = $gameTree
    engine_version = $engineVersion
    executable_sha256 = $exeHash
    package_sha256 = $pckHash
    built_utc = [DateTime]::UtcNow.ToString('o')
}
$temporaryManifest = "$manifestPath.tmp"
[System.IO.File]::WriteAllText($temporaryManifest, ($manifest | ConvertTo-Json) + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporaryManifest -Destination $manifestPath -Force
Write-Output "Windows export PASS: $buildExe"
Write-Output "Executable SHA-256: $exeHash"
Write-Output "PCK SHA-256: $pckHash"
Write-Output "Build manifest: $manifestPath"
