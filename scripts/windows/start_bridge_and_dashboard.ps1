#Requires -Version 5.1
<#
.SYNOPSIS
  One-click: optional Hermes + Aidun bridge + hermes_worker watch + local chat web (Windows).

.DESCRIPTION
  Default (no -RecycleAll): start missing pieces only (skip if already running).
  -RecycleAll: stop matching bridge / hermes_worker / Hermes / our web on WebPort, then start in order.
  HermesLaunchMode auto: if hermes.cmd exists -> tui_then_gateway, else none (bat passes -HermesLaunchMode auto).
  If auto and Hermes is missing, runs scripts/windows/Install-VTeethHermes.ps1 in a new window and exits 0 (relaunch after install).
  TUI: cmd /k console; tui_then_gateway waits HermesTuiWarmupMinSec for TUI init only (--tui does not bind gateway port), then starts gateway run if needed.

  NOTE: Most log lines are ASCII-only for Windows PowerShell 5.1 -File; user-facing WARN lines may use Chinese.
#>
param(
  [int]$WebPort = 8645,
  [int]$HermesGatewayPort = 8644,
  [string]$ListenHost = "127.0.0.1",
  [int]$WebReadyTimeoutSec = 45,
  [int]$HermesWatchIntervalSec = 5,
  [int]$HermesTuiWarmupMinSec = 10,
  [int]$HermesTuiWarmupMaxSec = 10,
  [int]$HermesTuiPollIntervalSec = 2,
  [int]$HermesGatewayReadyTimeoutSec = 120,
  [int]$HermesGatewayGraceSec = 30,
  [string]$HermesCmdPath = "",
  [ValidateSet("auto", "none", "gateway", "tui", "tui_then_gateway")]
  [string]$HermesLaunchMode = "none",
  [switch]$RecycleAll,
  [switch]$NoHermes,
  [switch]$NoHermesWorker,
  [switch]$SkipHermesInstall
)

$ErrorActionPreference = "Continue"

$LauncherLog = Join-Path $env:TEMP "aidun-bridge-dashboard-launcher.log"
function Write-Log([string]$m) {
  $line = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $m
  Write-Host $line
  try {
    Add-Content -LiteralPath $LauncherLog -Value $line -Encoding UTF8
  } catch {
    try { [Console]::Error.WriteLine($line) } catch {}
  }
}

Write-Log "=== begin PSScriptRoot=$PSScriptRoot initialPWD=$((Get-Location).Path) RecycleAll=$RecycleAll ==="

try {
  $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  if ($machinePath -or $userPath) { $env:Path = "$machinePath;$userPath" }
} catch {}

$candRoot = Join-Path $PSScriptRoot "..\.."
if (-not $PSScriptRoot) {
  Write-Log "ERROR: PSScriptRoot empty. Run: powershell -ExecutionPolicy Bypass -File `"<repo>\scripts\windows\start_bridge_and_dashboard.ps1`""
  Read-Host "Press Enter to close"
  exit 1
}
if (-not (Test-Path -LiteralPath $candRoot)) {
  Write-Log "ERROR: repo root missing: $candRoot (run bat from cloned aidun_bridge_c; do not copy only the .bat away)"
  Read-Host "Press Enter to close"
  exit 1
}
try {
  $RepoRoot = (Resolve-Path -LiteralPath $candRoot).Path
} catch {
  Write-Log "ERROR: Resolve-Path failed: $_ candRoot=$candRoot"
  Read-Host "Press Enter to close"
  exit 1
}
Set-Location -LiteralPath $RepoRoot
Write-Log "REPO_ROOT (cd ok): $RepoRoot"

function Get-PythonLauncher {
  if (Get-Command py -ErrorAction SilentlyContinue) {
    & py -3 -c "pass" 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { return @{ Exe = "py"; Prefix = @("-3") } }
  }
  if (Get-Command python -ErrorAction SilentlyContinue) {
    & python -c "pass" 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { return @{ Exe = "python"; Prefix = @() } }
  }
  return $null
}

function Test-BridgeDaemonRunning {
  $hits = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $c = $_.CommandLine
    if (-not $c) { return $false }
    if ($c -match "pytest|unittest|aidun-chat-web|chat_webapp|hermes_worker") { return $false }
    if ($c -notmatch "[\-/]m\s+aidun_bridge_c(\s|$)") { return $false }
    if ($c -match "\-\-once(\s|$)") { return $false }
    $true
  })
  return $hits.Count -gt 0
}

function Get-BridgeDaemonProcesses {
  @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $c = $_.CommandLine
    if (-not $c) { return $false }
    if ($c -match "pytest|unittest|aidun-chat-web|chat_webapp|hermes_worker") { return $false }
    if ($c -notmatch "[\-/]m\s+aidun_bridge_c(\s|$)") { return $false }
    if ($c -match "\-\-once(\s|$)") { return $false }
    $true
  })
}

function Test-HermesWorkerWatchRunning {
  $hits = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $c = $_.CommandLine
    if (-not $c) { return $false }
    if ($c -match "pytest|unittest") { return $false }
    if ($c -match "[\-/]m\s+aidun_bridge_c\.hermes_worker" -and $c -match "\bwatch\b") { return $true }
    if ($c -match "aidun-hermes-worker(\.exe)?\s" -and $c -match "\bwatch\b") { return $true }
    $false
  })
  return $hits.Count -gt 0
}

function Get-HermesWorkerWatchProcesses {
  @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $c = $_.CommandLine
    if (-not $c) { return $false }
    if ($c -match "pytest|unittest") { return $false }
    if ($c -match "[\-/]m\s+aidun_bridge_c\.hermes_worker" -and $c -match "\bwatch\b") { return $true }
    if ($c -match "aidun-hermes-worker(\.exe)?\s" -and $c -match "\bwatch\b") { return $true }
    $false
  })
}

function Test-TcpPortListening {
  param([int]$Port)
  try {
    # Any LISTEN on LocalPort counts. Narrow filters (127.0.0.1 / :: only) miss ::1 and other local bind shapes on Windows.
    $x = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
    return $x.Count -gt 0
  } catch {
    return $false
  }
}

function Test-WebDashboardListening {
  return (Test-TcpPortListening -Port $WebPort)
}

function Test-HermesGatewayListening {
  return (Test-TcpPortListening -Port $HermesGatewayPort)
}

function Wait-WebDashboardReady {
  param([int]$TimeoutSec)
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  while ((Get-Date) -lt $deadline) {
    if (Test-WebDashboardListening) { return $true }
    Start-Sleep -Seconds 1
  }
  return (Test-WebDashboardListening)
}

function Wait-HermesGatewayReady {
  param(
    [int]$TimeoutSec,
    [int]$GraceSec = 0
  )
  $t0 = Get-Date
  $nextHb = $t0.AddSeconds(15)
  Write-Log "Hermes: waiting for gateway port $HermesGatewayPort (up to ${TimeoutSec}s, then grace ${GraceSec}s)."
  $deadline = $t0.AddSeconds($TimeoutSec)
  while ((Get-Date) -lt $deadline) {
    if (Test-HermesGatewayListening) {
      $elapsed = [int](((Get-Date) - $t0).TotalSeconds)
      Write-Log "Hermes: gateway port $HermesGatewayPort listening (${elapsed}s)."
      return $true
    }
    $now = Get-Date
    if ($now -ge $nextHb) {
      $elapsed = [int](($now - $t0).TotalSeconds)
      Write-Log "Hermes: gateway port $HermesGatewayPort not up yet (${elapsed}s / ${TimeoutSec}s)."
      $nextHb = $now.AddSeconds(15)
    }
    Start-Sleep -Seconds 1
  }
  if (Test-HermesGatewayListening) { return $true }
  if ($GraceSec -le 0) { return $false }
  Write-Log "Hermes: primary wait ended; grace probe ${GraceSec}s for port $HermesGatewayPort."
  $graceEnd = (Get-Date).AddSeconds($GraceSec)
  while ((Get-Date) -lt $graceEnd) {
    if (Test-HermesGatewayListening) {
      $elapsed = [int](((Get-Date) - $t0).TotalSeconds)
      Write-Log "Hermes: gateway port $HermesGatewayPort listening during grace (${elapsed}s total)."
      return $true
    }
    Start-Sleep -Seconds 2
  }
  return (Test-HermesGatewayListening)
}

function Start-HermesGatewayAndWait {
  param([string]$LauncherPath)
  Start-HermesGatewayMinimized -LauncherPath $LauncherPath
  return (Wait-HermesGatewayReady -TimeoutSec $HermesGatewayReadyTimeoutSec -GraceSec $HermesGatewayGraceSec)
}

function Invoke-HermesTuiInitWait {
  param([int]$InitSec)
  if ($InitSec -lt 1) { $InitSec = 1 }
  Write-Log "Hermes: TUI init wait ${InitSec}s (--tui does not listen on gateway port $HermesGatewayPort)."
  $msgZh = "Hermes: TUI 已启动，等待 ${InitSec} 秒做初始化（TUI 不会监听 ${HermesGatewayPort} 网关，随后将单独启动 gateway）。"
  Write-Host $msgZh
  Start-Sleep -Seconds $InitSec
}

function Resolve-HermesLauncher {
  param([string]$ExplicitPath)
  $cands = @()
  if ($ExplicitPath) { $cands += $ExplicitPath }
  if ($env:HERMES_CMD) { $cands += $env:HERMES_CMD }
  $cands += "D:\vteeth\hermes\bin\hermes.cmd"
  foreach ($p in $cands) {
    if (-not $p) { continue }
    try {
      if (Test-Path -LiteralPath $p) { return (Resolve-Path -LiteralPath $p).Path }
    } catch {}
  }
  return $null
}

function Resolve-HermesLaunchMode {
  param([string]$Mode, [bool]$LauncherExists)
  $m = $Mode.ToLowerInvariant().Trim()
  if ($m -eq "auto") {
    if ($LauncherExists) { return "tui_then_gateway" }
    return "none"
  }
  if (@("none", "gateway", "tui", "tui_then_gateway") -contains $m) { return $m }
  Write-Log "WARN: unknown HermesLaunchMode '$Mode'; using none"
  return "none"
}

function Get-HermesKillCandidates {
  param([string]$HermesBinDir)
  $norm = ""
  if ($HermesBinDir) {
    try {
      $norm = ([System.IO.Path]::GetFullPath($HermesBinDir)).ToLowerInvariant().Replace("/", "\")
    } catch {
      $norm = $HermesBinDir.ToLowerInvariant().Replace("/", "\")
    }
  }
  @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $c = $_.CommandLine
    if (-not $c) { return $false }
    if ($c -match "pytest|unittest") { return $false }
    $lc = $c.ToLowerInvariant().Replace("/", "\")
    if ($norm -and $lc.Contains($norm)) { return $true }
    if ($_.Name -ieq "hermes.exe") { return $true }
    if ($lc -match "hermes\.cmd" -and ($lc -match "\bgateway\b" -or $lc -match "--tui")) { return $true }
    if ($lc -match "\\hermes\\bin\\" -or $lc -match "\\hermes-agent\\") { return $true }
    if ($_.Name -ieq "node.exe" -and $lc -match "hermes" -and ($lc -match "gateway" -or $lc -match "tui")) { return $true }
    $false
  })
}

function Get-OurWebListenerProcesses {
  $arr = @()
  try {
    $conns = @(Get-NetTCPConnection -LocalPort $WebPort -State Listen -ErrorAction SilentlyContinue)
    $pids = @($conns | Select-Object -ExpandProperty OwningProcess -Unique)
    foreach ($owningPid in $pids) {
      $p = Get-CimInstance Win32_Process -Filter "ProcessId=$owningPid" -ErrorAction SilentlyContinue
      if (-not $p) { continue }
      $c = $p.CommandLine
      if (-not $c) { continue }
      if ($c -match "chat_webapp|aidun-chat-web") { $arr += $p }
    }
  } catch {}
  return $arr
}

function Stop-ProcessListLogged {
  param([array]$Procs, [string]$Label)
  $ids = @($Procs | ForEach-Object { [int]$_.ProcessId } | Where-Object { $_ -gt 0 } | Sort-Object -Unique)
  foreach ($id in $ids) {
    $one = @($Procs | Where-Object { $_.ProcessId -eq $id })[0]
    $snip = ""
    if ($one.CommandLine) {
      $mx = [Math]::Min(140, $one.CommandLine.Length)
      $snip = $one.CommandLine.Substring(0, $mx)
      if ($one.CommandLine.Length -gt $mx) { $snip += "..." }
    }
    Write-Log "RecycleAll: stop $Label PID=$id $snip"
    Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
  }
  if ($ids.Count -gt 0) { Start-Sleep -Seconds 1 }
}

function Invoke-RecycleAidunStack {
  param(
    [bool]$KillHermes,
    [string]$HermesLauncherPath
  )
  Write-Log "RecycleAll: scanning processes..."
  Stop-ProcessListLogged -Procs (Get-HermesWorkerWatchProcesses) -Label "hermes_worker"
  Stop-ProcessListLogged -Procs (Get-BridgeDaemonProcesses) -Label "bridge"
  Stop-ProcessListLogged -Procs (Get-OurWebListenerProcesses) -Label "web"
  if ($KillHermes -and $HermesLauncherPath) {
    $bin = Split-Path -Parent $HermesLauncherPath
    Stop-ProcessListLogged -Procs (Get-HermesKillCandidates -HermesBinDir $bin) -Label "hermes"
  } elseif ($KillHermes) {
    Stop-ProcessListLogged -Procs (Get-HermesKillCandidates -HermesBinDir "") -Label "hermes"
  }
  Start-Sleep -Seconds 1
  Write-Log "RecycleAll: stop pass done."
}

function Write-HermesStartFailedHint {
  $msgZh = "启动 Hermes 失败，请检查 Hermes 是否正确安装和正确启动。"
  Write-Host $msgZh
  Write-Log "WARN: $msgZh"
}

function Start-HermesTuiConsole {
  param([string]$LauncherPath)
  $bin = Split-Path -Parent $LauncherPath
  Write-Log "Hermes: open TUI console (leave window open): $LauncherPath --tui"
  Start-Process -FilePath "cmd.exe" -ArgumentList @(
    "/k",
    "cd /d `"$bin`" && `"$LauncherPath`" --tui"
  ) -WorkingDirectory $bin
}

function Start-HermesGatewayMinimized {
  param([string]$LauncherPath)
  $bin = Split-Path -Parent $LauncherPath
  Write-Log "Hermes: start gateway minimized: gateway run"
  Start-Process -FilePath $LauncherPath -ArgumentList @("gateway", "run") -WorkingDirectory $bin `
    -WindowStyle Minimized
}

$py = Get-PythonLauncher
if (-not $py) {
  Write-Log "ERROR: py -3 or python not found. Install Python 3.10+ and add to PATH."
  Read-Host "Press Enter to close"
  exit 1
}

Write-Log "Python: $($py.Exe) $($py.Prefix -join ' ')"

if (-not (Test-Path (Join-Path $RepoRoot ".env"))) {
  Write-Log "WARN: .env missing under repo root; bridge/web may exit (need KQ_POOL_API_KEY). Copy .env.example to .env"
}

$hermesInstallScript = Join-Path $PSScriptRoot "Install-VTeethHermes.ps1"

$hermesLauncher = $null
if (-not $NoHermes) {
  $hp = $HermesCmdPath
  if (-not $hp) { $hp = "" }
  $hermesLauncher = Resolve-HermesLauncher -ExplicitPath $hp
}

if (-not $NoHermes -and -not $SkipHermesInstall -and ($HermesLaunchMode -eq "auto") -and -not $hermesLauncher) {
  if (-not (Test-Path -LiteralPath $hermesInstallScript)) {
    Write-Log "ERROR: Hermes not installed and repo installer missing: $hermesInstallScript"
    Read-Host "Press Enter to close"
    exit 1
  }
  Write-Log "Hermes launcher not found; starting V-Teeth Hermes installer in a new window. This launcher exits now (exit 0). After install finishes, run this launcher again."
  Start-Process -FilePath "powershell.exe" -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $hermesInstallScript
  ) -WorkingDirectory $PSScriptRoot
  exit 0
}

$hermesResolvedMode = Resolve-HermesLaunchMode -Mode $HermesLaunchMode -LauncherExists ([bool]$hermesLauncher)
if (-not $hermesLauncher -and $hermesResolvedMode -ne "none") {
  Write-Log "WARN: Hermes launcher not found (set -HermesCmdPath or HERMES_CMD); HermesLaunchMode effective=none"
  $hermesResolvedMode = "none"
}

if ($RecycleAll) {
  Invoke-RecycleAidunStack -KillHermes:(-not $NoHermes) -HermesLauncherPath $hermesLauncher
}

# --- Hermes (before bridge; webhook consumer expects gateway up) ---
if (-not $NoHermes -and $hermesResolvedMode -ne "none" -and $hermesLauncher) {
  $skipHermesStart = $false
  if (-not $RecycleAll -and (Test-HermesGatewayListening)) {
    Write-Log "Hermes: gateway already listening on port $HermesGatewayPort ; skip Hermes start."
    $skipHermesStart = $true
  }
  if (-not $skipHermesStart) {
    if ($hermesResolvedMode -eq "gateway") {
      $null = Start-HermesGatewayAndWait -LauncherPath $hermesLauncher
    }
    elseif ($hermesResolvedMode -eq "tui") {
      Start-HermesTuiConsole -LauncherPath $hermesLauncher
      Write-Log "Hermes: TUI-only mode; start gateway from TUI if needed."
    }
    elseif ($hermesResolvedMode -eq "tui_then_gateway") {
      Start-HermesTuiConsole -LauncherPath $hermesLauncher
      $tuiInitSec = $HermesTuiWarmupMinSec
      if ($HermesTuiWarmupMaxSec -gt $tuiInitSec) { $tuiInitSec = $HermesTuiWarmupMaxSec }
      Invoke-HermesTuiInitWait -InitSec $tuiInitSec
      if (-not (Test-HermesGatewayListening)) {
        Write-Log "Hermes: starting gateway run (webhook port $HermesGatewayPort)."
        $null = Start-HermesGatewayAndWait -LauncherPath $hermesLauncher
      } else {
        Write-Log "Hermes: gateway already listening after TUI init; skip gateway start."
      }
    }
    if ($hermesResolvedMode -eq "gateway" -or $hermesResolvedMode -eq "tui_then_gateway") {
      if (-not (Test-HermesGatewayListening)) {
        Write-HermesStartFailedHint
      }
    }
  }
} elseif ($NoHermes) {
  Write-Log "Skip Hermes (-NoHermes)."
} else {
  Write-Log "Hermes: skip (mode=$hermesResolvedMode or no launcher)."
}

# --- bridge ---
if (Test-BridgeDaemonRunning) {
  Write-Log "Bridge daemon already running; skip start."
} else {
  Write-Log "Starting bridge daemon..."
  $args = @()
  if ($py.Prefix.Count -gt 0) { $args += $py.Prefix }
  $args += @("-m", "aidun_bridge_c", "--no-interactive")
  Start-Process -FilePath $py.Exe -ArgumentList $args -WorkingDirectory $RepoRoot `
    -WindowStyle Minimized
  Start-Sleep -Seconds 2
  if (Test-BridgeDaemonRunning) {
    Write-Log "Bridge started."
  } else {
    Write-Log "WARN: bridge process not detected; try manually: py -3 -m aidun_bridge_c --once"
  }
}

# --- aidun-hermes-worker watch ---
if (-not $NoHermesWorker) {
  if (Test-HermesWorkerWatchRunning) {
    Write-Log "aidun-hermes-worker watch already running; skip start."
  } else {
    Write-Log "Starting aidun_bridge_c.hermes_worker watch (interval ${HermesWatchIntervalSec}s)..."
    $hwArgs = @()
    if ($py.Prefix.Count -gt 0) { $hwArgs += $py.Prefix }
    $hwArgs += @("-m", "aidun_bridge_c.hermes_worker", "watch", "--interval", "$HermesWatchIntervalSec")
    Start-Process -FilePath $py.Exe -ArgumentList $hwArgs -WorkingDirectory $RepoRoot `
      -WindowStyle Minimized
    Start-Sleep -Seconds 1
    if (Test-HermesWorkerWatchRunning) {
      Write-Log "Hermes worker watch started."
    } else {
      Write-Log "WARN: hermes_worker watch not detected; run manually: py -3 -m aidun_bridge_c.hermes_worker watch --interval $HermesWatchIntervalSec"
    }
  }
} else {
  Write-Log "Skip hermes_worker watch (-NoHermesWorker)."
}

# --- web dashboard ---
if (Test-WebDashboardListening) {
  Write-Log "Web already listening on port $WebPort ; skip start."
} else {
  Write-Log "Starting aidun-chat-web on port $WebPort ..."
  $chatCmd = Get-Command "aidun-chat-web" -ErrorAction SilentlyContinue
  if ($chatCmd) {
    Start-Process -FilePath $chatCmd.Source -ArgumentList @("--host", $ListenHost, "--port", "$WebPort") `
      -WorkingDirectory $RepoRoot -WindowStyle Minimized
  } else {
    $args = @()
    if ($py.Prefix.Count -gt 0) { $args += $py.Prefix }
    $args += @("-m", "aidun_bridge_c.chat_webapp", "--host", $ListenHost, "--port", "$WebPort")
    Start-Process -FilePath $py.Exe -ArgumentList $args -WorkingDirectory $RepoRoot `
      -WindowStyle Minimized
  }
  if (Wait-WebDashboardReady -TimeoutSec $WebReadyTimeoutSec) {
    Write-Log "Web listening on ${ListenHost}:${WebPort}"
  } else {
    Write-Log "ERROR: port $WebPort not listening after ${WebReadyTimeoutSec}s. Check .env (KQ_POOL_API_KEY), manual: py -3 -m aidun_bridge_c.chat_webapp , port conflict."
  }
}

$url = "http://${ListenHost}:${WebPort}/"
if (Test-WebDashboardListening) {
  Write-Log "Open browser: $url"
  try {
    Start-Process $url
  } catch {
    Write-Log "ERROR: Start-Process browser failed: $_"
    Read-Host "Press Enter to close"
    exit 1
  }
  Write-Log "Done."
  Start-Sleep -Milliseconds 800
  exit 0
}

Write-Log "ERROR: web not ready; browser not opened. See log: $LauncherLog"
Read-Host "Press Enter to close"
exit 1
