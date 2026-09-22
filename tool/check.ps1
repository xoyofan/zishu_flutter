[CmdletBinding()]
param(
    # Full path to flutter.bat. Override with -Flutter or $env:ZISHU_FLUTTER.
    [string] $Flutter = 'D:\flutter-sdk\flutter-3.47.0\flutter\bin\flutter.bat',

    # Full path to dart.bat (guard / 子包 pub get 需要). 缺省取 flutter.bat 同目录下的 dart.bat;
    # 可用 -Dart 或 $env:ZISHU_DART 覆盖.
    [string] $Dart = ''
)

# One-shot gate: pub get(根 + 2 个子包) -> analyze -> guard -> test -> build legacy web.
# Any step failing stops the run immediately with that step's exit code.

$ErrorActionPreference = 'Stop'

if ($env:ZISHU_FLUTTER) { $Flutter = $env:ZISHU_FLUTTER }
if ($env:ZISHU_DART) { $Dart = $env:ZISHU_DART }

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot

# 刻意**不**在这里设置 PUB_HOSTED_URL / FLUTTER_STORAGE_BASE_URL:
# pub 会把实际使用的 hosted URL 写进 pubspec.lock。若门禁里固定用 CN 镜像,
# 每次跑门禁都会把 3 个 lock(根 + packages/live_parser + packages/speech2zh)
# 的 url 从 pub.dev 改写成镜像 URL,并顺带升传递依赖版本(实测 264 行噪音);
# 而 .github/workflows/release-windows.yml 在 GitHub runner(外网)上不设镜像,
# 两边必须一致。需要镜像/代理时请在调用方的 shell 或全局环境变量里设置。

if (-not (Test-Path -LiteralPath $Flutter)) {
    Write-Host "[check] flutter.bat not found: $Flutter" -ForegroundColor Red
    Write-Host '[check] pass -Flutter <path> or set ZISHU_FLUTTER.' -ForegroundColor Red
    Pop-Location
    exit 1
}

# dart.bat 与 flutter.bat 在同一目录; 不依赖 PATH, 也不靠调用方预先激活环境.
if (-not $Dart) { $Dart = Join-Path (Split-Path -Parent $Flutter) 'dart.bat' }
if (-not (Test-Path -LiteralPath $Dart)) {
    Write-Host "[check] dart.bat not found: $Dart" -ForegroundColor Red
    Write-Host '[check] pass -Dart <path> or set ZISHU_DART.' -ForegroundColor Red
    Pop-Location
    exit 1
}

$steps = @(
    @{ Title = 'flutter pub get';   Args = @('pub', 'get') },

    # packages/ 下是**独立 package**(本仓库不是 pub workspace, 也没有 melos)。
    # 根 pub get 只把两个子包当 path 依赖解析, 不会为它们自己生成 .dart_tool,
    # 也不会解析它们自己的 dev_dependencies(如 test)。缺了这两步时,
    # fresh clone 上跑 analyze 会在本仓库报出约 3000 个假 error
    # (packages/**/test 的 uri_does_not_exist / undefined_function),
    # 看起来像代码坏了, 实际只是子包没解析依赖。
    @{ Title = 'pub get (packages/live_parser)'; Command = $Dart; WorkingDirectory = 'packages/live_parser'; Args = @('pub', 'get') },
    @{ Title = 'pub get (packages/speech2zh)';   Command = $Dart; WorkingDirectory = 'packages/speech2zh';   Args = @('pub', 'get') },

    @{ Title = 'flutter analyze';   Args = @('analyze') },
    # 裸值守卫(裸色值/裸阴影/裸字号/裸圆角): 纯 Dart 脚本, 用 Command 覆盖可执行文件。
    @{ Title = 'design token guard'; Command = $Dart; Args = @('run', 'tool/check_design_tokens.dart') },
    @{ Title = 'flutter test';      Args = @('test') },
    @{ Title = 'flutter build web (legacy UI)'; Args = @('build', 'web', '--target', 'lib/legacy/main_web.dart') }
)

$failed = $false
foreach ($step in $steps) {
    Write-Host ''
    Write-Host "======== [$($step.Title)] ========" -ForegroundColor Cyan

    # 步骤可用可选的 Command 覆盖可执行文件; 缺省仍是 flutter.bat, 老步骤行为不变。
    $cmd = if ($step.Command) { $step.Command } else { $Flutter }

    # 步骤可指定子目录(子包各自的 pub get / test 必须在自己目录里跑)。
    $stepDir = if ($step.WorkingDirectory) { Join-Path $repoRoot $step.WorkingDirectory } else { $null }
    if ($stepDir) {
        if (-not (Test-Path -LiteralPath $stepDir)) {
            Write-Host "-------- [$($step.Title)] SKIPPED: 目录不存在 $stepDir --------" -ForegroundColor Red
            $failed = $true
            $exitCode = 1
            break
        }
        Push-Location $stepDir
    }

    $previousPreference = $ErrorActionPreference
    $nativePreferenceVariable = Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
    $previousNativePreference = if ($nativePreferenceVariable) { $PSNativeCommandUseErrorActionPreference } else { $null }
    try {
        # Windows PowerShell turns native stderr into ErrorRecords; flutter writes
        # progress output to stderr, so with 'Stop' a normal progress line would
        # abort the script. Use the process exit code as the single source of truth.
        $ErrorActionPreference = 'Continue'
        if ($nativePreferenceVariable) { $PSNativeCommandUseErrorActionPreference = $false }
        & $cmd @($step.Args)
        $exitCode = $LASTEXITCODE
    } finally {
        if ($stepDir) { Pop-Location }
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
Write-Host 'check: all gates passed (pub get x3 / analyze / design token guard / test / legacy web build)' -ForegroundColor Green
exit 0
