[CmdletBinding()]
param(
    [switch]$PrepareOnly
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$buildRoot = Join-Path $repositoryRoot 'builds\CraftAndDefend'
$buildExe = Join-Path $buildRoot 'CraftAndDefend.exe'
$buildPck = Join-Path $buildRoot 'CraftAndDefend.pck'
$manifestPath = Join-Path $buildRoot 'build_manifest.json'
$gitMarker = Join-Path $repositoryRoot '.git'
$gitSafeDirectory = $repositoryRoot.Replace('\', '/')

function Get-GameTree {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        return $null
    }
    $value = (& git -c "safe.directory=$gitSafeDirectory" -C $repositoryRoot rev-parse HEAD:game 2>$null | Select-Object -First 1)
    if ($value -notmatch '^[0-9a-fA-F]{40}$') {
        return $null
    }
    return [string]$value
}

function Test-GameTreeClean {
    $changes = (& git -c "safe.directory=$gitSafeDirectory" -C $repositoryRoot status --porcelain -- game 2>$null)
    return -not $changes
}

function Test-BuildCurrent {
    if (-not (Test-Path -LiteralPath $buildExe -PathType Leaf) -or -not (Test-Path -LiteralPath $buildPck -PathType Leaf)) {
        return $false
    }
    if (-not (Test-Path -LiteralPath $gitMarker)) {
        return $true
    }
    $currentGameTree = Get-GameTree
    if ([string]::IsNullOrWhiteSpace($currentGameTree) -or -not (Test-GameTreeClean)) {
        return $false
    }
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        return $false
    }
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        return $manifest.schema_version -eq 1 -and $manifest.game_tree -eq $currentGameTree
    }
    catch {
        return $false
    }
}

$buildCurrent = Test-BuildCurrent
if (-not $buildCurrent) {
	Write-Output 'The packaged game is missing, unversioned, or older than the checked-out game source. Rebuilding it now...'
	& (Join-Path $PSScriptRoot 'build_windows_f0.ps1')
	if (-not (Test-BuildCurrent)) {
        throw 'The Windows build completed, but its provenance does not match the current clean game tree.'
    }
}
else {
    Write-Output 'Packaged game provenance matches the current game source.'
}

if ($PrepareOnly) {
    Write-Output "Prepared current game: $buildExe"
    return
}

Write-Output "Launching provenance-matched game: $buildExe"
Start-Process -FilePath $buildExe -WorkingDirectory $buildRoot
