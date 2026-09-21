param(
  [switch]$Debug
)

$ErrorActionPreference = 'Stop'
$flutter = if (Get-Command flutter -ErrorAction SilentlyContinue) { 'flutter' } else { 'F:\flutter\bin\flutter.bat' }
$mode = if ($Debug) { 'debug' } else { 'release' }

& $flutter build windows --$mode -t lib/main.dart '--dart-define=ZISHU_REAL_PARSER=true'
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Windows $mode build with real parser generated."
