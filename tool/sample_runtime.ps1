[CmdletBinding()]
param(
  [string]$ProcessName = 'zishu_flutter',
  [int]$IntervalSeconds = 5,
  [int]$DurationSeconds = 60,
  [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
$process = Get-Process -Name $ProcessName -ErrorAction Stop | Select-Object -First 1
$samples = @()
$lastCpu = $process.CPU
$lastAt = Get-Date
$deadline = $lastAt.AddSeconds($DurationSeconds)

while ($true) {
  $process.Refresh()
  if ($process.HasExited) { break }

  $now = Get-Date
  $elapsedSeconds = [Math]::Max(($now - $lastAt).TotalSeconds, 0.001)
  $cpuPercent = 0
  if ($null -ne $lastCpu) {
    $cpuPercent = (($process.CPU - $lastCpu) / $elapsedSeconds) * 100
  }
  $lastCpu = $process.CPU
  $lastAt = $now

  $gpuDedicatedMb = 0
  $gpuSharedMb = 0
  try {
    $gpuCounters = Get-Counter @(
      '\GPU Process Memory(*)\Dedicated Usage',
      '\GPU Process Memory(*)\Shared Usage'
    ) -ErrorAction Stop
    $instancePattern = "pid_$($process.Id)_"
    foreach ($counter in $gpuCounters.CounterSamples) {
      if ($counter.InstanceName -notmatch $instancePattern) { continue }
      if ($counter.Path -match 'dedicated usage$') {
        $gpuDedicatedMb += $counter.CookedValue / 1MB
      } elseif ($counter.Path -match 'shared usage$') {
        $gpuSharedMb += $counter.CookedValue / 1MB
      }
    }
  } catch {
    # Older or localized Windows counter sets may not expose GPU process memory.
  }

  $samples += [pscustomobject]@{
    Timestamp = $now.ToString('o')
    CpuPercent = [Math]::Round($cpuPercent, 1)
    PrivateMb = [Math]::Round($process.PrivateMemorySize64 / 1MB, 1)
    WorkingSetMb = [Math]::Round($process.WorkingSet64 / 1MB, 1)
    GpuDedicatedMb = [Math]::Round($gpuDedicatedMb, 1)
    GpuSharedMb = [Math]::Round($gpuSharedMb, 1)
    Threads = $process.Threads.Count
    Handles = $process.HandleCount
  }

  if ($now -ge $deadline) { break }
  Start-Sleep -Seconds ([Math]::Max($IntervalSeconds, 1)) -ErrorAction SilentlyContinue
}

if ($OutputPath) {
  $parent = Split-Path -Parent $OutputPath
  if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
  $samples | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding utf8
  Write-Host "Wrote $($samples.Count) samples to $OutputPath"
} else {
  $samples | Format-Table -AutoSize
}
