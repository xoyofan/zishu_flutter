[CmdletBinding()]
param(
    # Full path to flutter.bat. Override with -Flutter or $env:ZISHU_FLUTTER.
    [string] $Flutter = 'D:\flutter-sdk\flutter-3.47.0\flutter\bin\flutter.bat',

    # Optional backend base url, forwarded as --dart-define=STREAM_API_URL=<url>.
    [string] $StreamApiUrl = ''
)

# Build build/web (release by default, mirroring "flutter build web").

$ErrorActionPreference = 'Stop'

if ($env:ZISHU_FLUTTER) { $Flutter = $env:ZISHU_FLUTTER }

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot

$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'

if (-not (Test-Path -LiteralPath $Flutter)) {
    Write-Host "[build-web] flutter.bat not found: $Flutter" -ForegroundColor Red
    Write-Host '[build-web] pass -Flutter <path> or set ZISHU_FLUTTER.' -ForegroundColor Red
    Pop-Location
    exit 1
}

$buildArgs = @('build', 'web', '--release')
if ($StreamApiUrl) {
    $buildArgs += "--dart-define=STREAM_API_URL=$StreamApiUrl"
}

Write-Host "======== [flutter $($buildArgs -join ' ')] ========" -ForegroundColor Cyan

$previousPreference = $ErrorActionPreference
$nativePreferenceVariable = Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
$previousNativePreference = if ($nativePreferenceVariable) { $PSNativeCommandUseErrorActionPreference } else { $null }
try {
    # Same stderr rationale as check.ps1: trust the exit code only.
    $ErrorActionPreference = 'Continue'
    if ($nativePreferenceVariable) { $PSNativeCommandUseErrorActionPreference = $false }
    & $Flutter @buildArgs
    $exitCode = $LASTEXITCODE
} finally {
    if ($nativePreferenceVariable) { $PSNativeCommandUseErrorActionPreference = $previousNativePreference }
    $ErrorActionPreference = $previousPreference
}

Pop-Location

if ($exitCode -ne 0) {
    Write-Host "-------- [flutter build web] exit=$exitCode FAILED --------" -ForegroundColor Red
    exit $exitCode
}

Write-Host "-------- [flutter build web] exit=0 OK --------" -ForegroundColor Green
Write-Host "build/web is ready at $(Join-Path $repoRoot 'build\web')" -ForegroundColor Green
exit 0
