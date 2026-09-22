[CmdletBinding()]
param(
    # Runner file names to run (default: every TEST_*.cmd beside this script, sorted by name).
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Only
)

# Runs every exported-game runner in tools\runners in order, headless-friendly (no evidence
# images are opened, no pause prompts block), and prints one summary table. Each runner's
# output goes to artifacts\run_all-<stamp>\<runner>.log; the table is also written beside them.
$ErrorActionPreference = 'Continue'
$runnerRoot = $PSScriptRoot
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $runnerRoot '..\..'))
$stamp = [DateTime]::Now.ToString('yyyyMMdd-HHmmss')
$logRoot = Join-Path $repositoryRoot "artifacts\run_all-$stamp"
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null

foreach ($prefix in 'EXPO', 'P2', 'P3C', 'P3D', 'P3E', 'P3F', 'P3G', 'P3H', 'P3K', 'P4') {
    Set-Item -Path "env:${prefix}_DIAGNOSTIC_NO_OPEN" -Value '1'
    Set-Item -Path "env:${prefix}_DIAGNOSTIC_NO_PAUSE" -Value '1'
}

$runners = Get-ChildItem -LiteralPath $runnerRoot -Filter 'TEST_*.cmd' | Sort-Object Name
if ($Only) {
    $runners = $runners | Where-Object { $Only -contains $_.Name -or $Only -contains $_.BaseName }
}
if (-not $runners) {
    Write-Output 'No runners found.'
    exit 1
}

$results = @()
$sweep = [System.Diagnostics.Stopwatch]::StartNew()
foreach ($runner in $runners) {
    Write-Output "== $($runner.Name)"
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $logPath = Join-Path $logRoot ($runner.BaseName + '.log')
    # <nul keeps a failing runner's `pause` from blocking the sweep.
    $output = & cmd.exe /d /c "call `"$($runner.FullName)`" <nul" 2>&1 | ForEach-Object { [string]$_ }
    $exitCode = $LASTEXITCODE
    $clock.Stop()
    $output | Set-Content -LiteralPath $logPath -Encoding UTF8
    $verdictLine = $output | Where-Object { $_ -match 'TEST: (PASS|FAIL)' } | Select-Object -Last 1
    $verdict = if ($verdictLine -match 'TEST: PASS' -and $exitCode -eq 0) { 'PASS' } else { 'FAIL' }
    $failures = $output | Where-Object { $_ -match '^T\d+.* FAIL ' } | ForEach-Object { $_.Substring(0, [Math]::Min(120, $_.Length)) }
    $evidence = ($output | Where-Object { $_ -match '^Evidence folder: ' } | Select-Object -Last 1) -replace '^Evidence folder: ', ''
    $results += [pscustomobject]@{
        Runner   = $runner.Name
        Result   = $verdict
        Seconds  = [int][Math]::Round($clock.Elapsed.TotalSeconds)
        ExitCode = $exitCode
        Evidence = $evidence
    }
    Write-Output "   $verdict ($([int]$clock.Elapsed.TotalSeconds) s)"
    foreach ($line in $failures) { Write-Output "   $line" }
}
$sweep.Stop()

$table = $results | Format-Table -AutoSize Runner, Result, Seconds, ExitCode, Evidence | Out-String -Width 200
$passCount = @($results | Where-Object { $_.Result -eq 'PASS' }).Count
$summary = "RUN ALL: $passCount / $($results.Count) PASS in $([int]$sweep.Elapsed.TotalMinutes) min. Logs: $logRoot"
Write-Output ''
Write-Output $table.TrimEnd()
Write-Output $summary
($table.TrimEnd() + [Environment]::NewLine + $summary) | Set-Content -LiteralPath (Join-Path $logRoot 'summary.txt') -Encoding UTF8
if ($passCount -ne $results.Count) { exit 1 }
exit 0
