[CmdletBinding()]
param(
    # Full path to flutter.bat. Override with -Flutter or $env:ZISHU_FLUTTER.
    [string] $Flutter = 'D:\flutter-sdk\flutter-3.47.0\flutter\bin\flutter.bat'
)

# One-shot gate: pub get -> analyze -> test -> build legacy web.
# Any step failing stops the run immediately with that step's exit code.

$ErrorActionPreference = 'Stop'

if ($env:ZISHU_FLUTTER) { $Flutter = $env:ZISHU_FLUTTER }

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot

# Pub mirror (CN), same values used everywhere in this project.
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'

if (-not (Test-Path -LiteralPath $Flutter)) {
    Write-Host "[check] flutter.bat not found: $Flutter" -ForegroundColor Red
    Write-Host '[check] pass -Flutter <path> or set ZISHU_FLUTTER.' -ForegroundColor Red
    Pop-Location
    exit 1
}

$steps = @(
    @{ Title = 'flutter pub get';   Args = @('pub', 'get') },
    @{ Title = 'flutter analyze';   Args = @('analyze') },
    @{ Title = 'flutter test';      Args = @('test') },
    @{ Title = 'flutter build web (legacy UI)'; Args = @('build', 'web', '--target', 'lib/legacy/main_web.dart') }
)

$failed = $false
foreach ($step in $steps) {
    Write-Host ''
    Write-Host "======== [$($step.Title)] ========" -ForegroundColor Cyan

    $previousPreference = $ErrorActionPreference
    $nativePreferenceVariable = Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
    $previousNativePreference = if ($nativePreferenceVariable) { $PSNativeCommandUseErrorActionPreference } else { $null }
    try {
        # Windows PowerShell turns native stderr into ErrorRecords; flutter writes
        # progress output to stderr, so with 'Stop' a normal progress line would
        # abort the script. Use the process exit code as the single source of truth.
        $ErrorActionPreference = 'Continue'
        if ($nativePreferenceVariable) { $PSNativeCommandUseErrorActionPreference = $false }
        & $Flutter @($step.Args)
        $exitCode = $LASTEXITCODE
    } finally {
        if ($nativePreferenceVariable) { $PSNativeCommandUseErrorActionPreference = $previousNativePreference }
        $ErrorActionPreference = $previousPreference
    }

    if ($exitCode -eq 0) {
        Write-Host "-------- [$($step.Title)] exit=$exitCode OK --------" -ForegroundColor Green
    } else {
        Write-Host "-------- [$($step.Title)] exit=$exitCode FAILED --------" -ForegroundColor Red
        $failed = $true
        break
    }
}

Pop-Location

if ($failed) { exit $exitCode }

Write-Host ''
Write-Host 'check: all gates passed (pub get / analyze / test / legacy web build)' -ForegroundColor Green
exit 0
