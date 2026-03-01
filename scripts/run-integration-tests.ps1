#
# Run each integration test individually to avoid multiple simultaneous
# BLE connections to the same test peripheral.
#
# Each test_*.rs file under tests/ is its own binary with a single test,
# ensuring process isolation for BLE stack stability.
#
# Usage:
#   .\scripts\run-integration-tests.ps1                    # run all tests
#   .\scripts\run-integration-tests.ps1 test_read_*        # run tests matching a glob
#
# Environment:
#   BTLEPLUG_TEST_PERIPHERAL  - peripheral name (default: btleplug-test)
#   RUST_LOG                  - log level (e.g. debug, btleplug=trace)
#   DELAY                     - seconds to wait between tests (default: 2)
#   TIMEOUT                   - seconds before a test is killed (default: 20)

[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments)]
    [string[]]$Filter
)

$ErrorActionPreference = 'Stop'

$Delay   = if ($env:DELAY)   { [int]$env:DELAY }   else { 2 }
$Timeout = if ($env:TIMEOUT) { [int]$env:TIMEOUT } else { 20 }
$Passed  = 0
$Failed  = 0
$Failures = @()

# Discover test files.
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TestsDir  = Join-Path (Split-Path -Parent $ScriptDir) 'tests'

$TestNames = Get-ChildItem -Path $TestsDir -Filter 'test_*.rs' -Name |
    ForEach-Object { $_ -replace '\.rs$', '' } |
    Sort-Object

# Apply filter if provided.
if ($Filter) {
    $TestNames = $TestNames | Where-Object {
        $name = $_
        ($Filter | Where-Object { $name -like $_ }).Count -gt 0
    }
}

if ($TestNames.Count -eq 0) {
    Write-Host "No tests matched."
    if ($Filter) { Write-Host "Filter: $($Filter -join ', ')" }
    exit 1
}

$Total = $TestNames.Count
Write-Host "=== btleplug integration tests ==="
Write-Host "Running $Total tests sequentially (${Delay}s delay, ${Timeout}s timeout per test)"
Write-Host ""

$LogFile = Join-Path $env:TEMP 'btleplug-test-output.log'
$TestNum = 0

foreach ($testName in $TestNames) {
    $TestNum++
    Write-Host -NoNewline ("[{0,2}/{1,2}] {2,-55} " -f $TestNum, $Total, $testName)

    # Run cargo test with a timeout via Start-Process.
    $proc = Start-Process -FilePath 'cargo' `
        -ArgumentList "test --test $testName -- --ignored" `
        -NoNewWindow -PassThru `
        -RedirectStandardError $LogFile `
        -RedirectStandardOutput "$LogFile.stdout"

    $finished = $proc.WaitForExit($Timeout * 1000)

    if (-not $finished) {
        # Timed out — kill the process tree.
        try { $proc.Kill($true) } catch {}
        $proc.WaitForExit()
        Write-Host "TIMEOUT (${Timeout}s)"
        $Failed++
        $Failures += $testName
        Write-Host "  --- output ---"
        if (Test-Path $LogFile) {
            Get-Content $LogFile -Tail 20 | ForEach-Object { "  $_" }
        }
        if (Test-Path "$LogFile.stdout") {
            Get-Content "$LogFile.stdout" -Tail 20 | ForEach-Object { "  $_" }
        }
        Write-Host "  --- end ---"
    } elseif ($proc.ExitCode -ne 0) {
        Write-Host "FAIL"
        $Failed++
        $Failures += $testName
        Write-Host "  --- output ---"
        if (Test-Path $LogFile) {
            Get-Content $LogFile -Tail 20 | ForEach-Object { "  $_" }
        }
        if (Test-Path "$LogFile.stdout") {
            Get-Content "$LogFile.stdout" -Tail 20 | ForEach-Object { "  $_" }
        }
        Write-Host "  --- end ---"
    } else {
        Write-Host "PASS"
        $Passed++
    }

    # Brief delay to let the BLE stack settle between tests.
    if ($TestNum -lt $Total) {
        Start-Sleep -Seconds $Delay
    }
}

Remove-Item -Path $LogFile, "$LogFile.stdout" -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=== Results ==="
Write-Host "  Passed:  $Passed"
Write-Host "  Failed:  $Failed"
Write-Host "  Total:   $Total"

if ($Failures.Count -gt 0) {
    Write-Host ""
    Write-Host "Failed tests:"
    foreach ($f in $Failures) {
        Write-Host "  - $f"
    }
    exit 1
}

Write-Host ""
Write-Host "All tests passed."
