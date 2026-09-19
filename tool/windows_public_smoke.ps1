[CmdletBinding()]
param(
    [string] $ExePath = 'build/windows/x64/runner/Release/zishu_flutter.exe',
    [string] $EvidenceDir,
    [switch] $DryRun,
    [switch] $Checklist,
    [switch] $Launch,
    [ValidateRange(0, 120)]
    [int] $LaunchWaitSeconds = 3,
    [string] $BuildVersion,
    [string] $TestId = 'WIN-PUBLIC-4.2',
    [string] $Platform = 'Windows',
    [ValidateSet('PASS', 'FAIL', 'BLOCKED', 'N/A', 'NOT_RUN')]
    [string] $Status = 'NOT_RUN',
    [string] $LogPath,
    [string] $ScreenshotPath
)

# This script records an operator-run smoke checklist. It does not perform clicks,
# network requests, sign-in, or infer PASS/FAIL from process startup.
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

function Resolve-RepoPath {
    param([Parameter(Mandatory = $true)][string] $Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
}

function Invoke-GitText {
    param([Parameter(Mandatory = $true)][string[]] $Arguments)

    Push-Location $repoRoot
    try {
        $value = & git @Arguments 2>$null
        if ($LASTEXITCODE -ne 0) {
            return 'UNKNOWN'
        }
        $text = ($value -join "`n").Trim()
        if ([string]::IsNullOrWhiteSpace($text)) {
            return 'UNKNOWN'
        }
        return $text
    } finally {
        Pop-Location
    }
}

if ([string]::IsNullOrWhiteSpace($EvidenceDir)) {
    $EvidenceDir = "tool/windows-public-smoke/$timestamp"
}
$evidenceRoot = Resolve-RepoPath $EvidenceDir
New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null

$resolvedExe = Resolve-RepoPath $ExePath
$exeExists = Test-Path -LiteralPath $resolvedExe -PathType Leaf
$fileVersion = $null
if ($exeExists) {
    $fileVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($resolvedExe).FileVersion
}
if ([string]::IsNullOrWhiteSpace($BuildVersion)) {
    if (-not [string]::IsNullOrWhiteSpace($fileVersion)) {
        $BuildVersion = $fileVersion
    } else {
        $BuildVersion = 'UNAVAILABLE (release exe not found)'
    }
}

$manifestPath = Join-Path $evidenceRoot 'evidence.json'
$checklistPath = Join-Path $evidenceRoot 'checklist.md'
if ([string]::IsNullOrWhiteSpace($LogPath)) {
    $LogPath = Join-Path $evidenceRoot 'manual-smoke.log'
} else {
    $LogPath = Resolve-RepoPath $LogPath
}
if ([string]::IsNullOrWhiteSpace($ScreenshotPath)) {
    $ScreenshotPath = Join-Path $evidenceRoot 'screenshots'
} else {
    $ScreenshotPath = Resolve-RepoPath $ScreenshotPath
}

$platforms = @(
    'douyu', 'huya', 'bilibili', 'douyin', 'kuaishou',
    'yy', 'twitch', 'soop', 'youtube', 'iptv'
)
$testCases = @(
    @{ id = 'VOL'; name = 'room volume isolation and restore' },
    @{ id = 'MUTE'; name = 'mute and unmute' },
    @{ id = 'QUALITY'; name = 'default quality and switching' },
    @{ id = 'LINE'; name = 'line format switching and fallback' },
    @{ id = 'DANMAKU'; name = 'danmaku connection room switch settings and dedupe' },
    @{ id = 'FULLSCREEN'; name = 'system and web fullscreen' },
    @{ id = 'PIP'; name = 'picture in picture enter exit and restore' },
    @{ id = 'FOLLOW'; name = 'follow unfollow status refresh and sync' },
    @{ id = 'THEME'; name = 'dark light theme and settings restore' },
    @{ id = 'RETURN'; name = 'back button Alt-left and mouse side button' }
)

$entries = @()
foreach ($site in $platforms) {
    foreach ($testCase in $testCases) {
        $entries += [ordered]@{
            platform = $site
            testId = $testCase.id
            name = $testCase.name
            status = 'NOT_RUN'
            logPath = $LogPath
            screenshotPath = $ScreenshotPath
            notes = ''
        }
    }
}

$launchRequested = [bool]$Launch
$launchSkippedReason = $null
$processId = $null
$launchError = $null
if ($DryRun -or $Checklist) {
    $launchSkippedReason = 'dry-run/checklist mode does not start the application'
} elseif (-not $Launch) {
    $launchSkippedReason = 'application launch was not requested; use -Launch for an optional manual session'
} elseif (-not $exeExists) {
    $launchSkippedReason = 'release executable was not found'
    $launchError = "Release executable not found: $resolvedExe"
} else {
    try {
        $process = Start-Process -FilePath $resolvedExe -WorkingDirectory (Split-Path -Parent $resolvedExe) -PassThru
        $processId = $process.Id
        if ($LaunchWaitSeconds -gt 0) {
            Start-Sleep -Seconds $LaunchWaitSeconds
        }
    } catch {
        $launchError = $_.Exception.Message
    }
}

$manifest = [ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    testId = $TestId
    platform = $Platform
    status = $Status
    build = [ordered]@{
        executable = $resolvedExe
        version = $BuildVersion
        gitCommit = (Invoke-GitText @('rev-parse', 'HEAD'))
    }
    execution = [ordered]@{
        dryRun = [bool]$DryRun
        checklistMode = [bool]$Checklist
        launchRequested = $launchRequested
        processId = $processId
        launchSkippedReason = $launchSkippedReason
        launchError = $launchError
    }
    evidence = [ordered]@{
        logPath = $LogPath
        screenshotPath = $ScreenshotPath
        screenshotMethod = 'PrintWindow(PW_RENDERFULLCONTENT) via tool/win_tool.py; desktop-composited capture is not sufficient as the sole evidence'
    }
    checklist = $entries
    operatorInstructions = @(
        'Build the release executable before a real run; this script does not build it.',
        'Run the application manually and execute the checklist for each platform and test ID.',
        'Record only PASS, FAIL, BLOCKED, N/A, or NOT_RUN in evidence.json; startup alone is not PASS.',
        'Use py tool/win_tool.py shot <path> for PrintWindow(PW_RENDERFULLCONTENT) window-surface evidence.',
        'Do not put credentials, tokens, playback.log, screenshots, or build outputs in the repository.'
    )
}

$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

$markdown = New-Object System.Collections.Generic.List[string]
$markdown.Add('# Windows public smoke checklist')
$markdown.Add('')
$markdown.Add(('- Test ID: `' + $TestId + '`'))
$markdown.Add(('- Generated (UTC): `' + $manifest.generatedAt + '`'))
$markdown.Add(('- Build version: `' + $BuildVersion + '`'))
$markdown.Add(('- Git commit: `' + $manifest.build.gitCommit + '`'))
$markdown.Add(('- Default status: `' + $Status + '` (change only after manual verification)'))
$markdown.Add('')
$markdown.Add('| Platform | Test ID | Status | Log path | Screenshot path | Notes |')
$markdown.Add('|---|---|---|---|---|---|')
foreach ($entry in $entries) {
    $markdown.Add("| $($entry.platform) | $($entry.testId) | $($entry.status) | $($entry.logPath) | $($entry.screenshotPath) |  |")
}
$markdown.Add('')
$markdown.Add('## Manual evidence steps')
$markdown.Add('')
$markdown.Add('1. Build and launch the Windows release executable; do not enter credentials into this script.')
$markdown.Add('2. For each applicable platform, execute the public-function checklist and update `evidence.json`/this table with a truthful status.')
$markdown.Add('3. Capture the window surface with `py tool/win_tool.py shot <path>` (`PrintWindow(PW_RENDERFULLCONTENT)`).')
$markdown.Add('4. A screen-composited screenshot (`shotdesktop`) may supplement evidence but must not be the sole evidence.')
$markdown.Add('5. Keep the evidence directory outside the product commit; the default `tool/windows-public-smoke/` path is ignored by Git.')
$markdown -join "`n" | Set-Content -LiteralPath $checklistPath -Encoding UTF8

Write-Host "evidence directory: $evidenceRoot"
Write-Host "metadata: $manifestPath"
Write-Host "checklist: $checklistPath"
Write-Host "status: $Status"
if ($launchError) {
    Write-Host "launch: NOT STARTED ($launchError)" -ForegroundColor Yellow
    exit 2
}
if ($processId) {
    Write-Host "launch: started process $processId; manual verification is still required" -ForegroundColor Yellow
} else {
    Write-Host "launch: not started ($launchSkippedReason)"
}
Write-Host 'no PASS/FAIL was inferred by the script; checklist entries remain NOT_RUN'
exit 0
