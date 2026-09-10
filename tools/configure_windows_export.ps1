[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TemplateExe
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$gameRoot = Join-Path $repositoryRoot 'game'
$sourcePreset = Join-Path $gameRoot 'export_presets.cfg.in'
$generatedPreset = Join-Path $gameRoot 'export_presets.cfg'
$resolvedTemplate = [System.IO.Path]::GetFullPath($TemplateExe)

if (-not (Test-Path -LiteralPath $resolvedTemplate -PathType Leaf)) {
    throw "Matching custom release template not found: $resolvedTemplate"
}
if ([System.IO.Path]::GetFileName($resolvedTemplate) -ne 'godot.windows.template_release.x86_64.exe') {
    throw "Refusing unexpected template filename: $resolvedTemplate"
}

$presetText = [System.IO.File]::ReadAllText($sourcePreset)
$portableTemplatePath = $resolvedTemplate.Replace('\', '/')
$presetText = $presetText.Replace('__CUSTOM_RELEASE_TEMPLATE__', $portableTemplatePath)
[System.IO.File]::WriteAllText($generatedPreset, $presetText, [System.Text.UTF8Encoding]::new($false))

Write-Output "Generated local export preset: $generatedPreset"
Write-Output "Custom release template: $resolvedTemplate"

