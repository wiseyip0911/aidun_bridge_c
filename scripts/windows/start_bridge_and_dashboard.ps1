#Requires -Version 5.1
<#
.SYNOPSIS
  One-click: Aidun bridge daemon + local chat web dashboard (Windows), open browser.

.DESCRIPTION
  - If bridge (py -m aidun_bridge_c, not --once) is running -> skip start.
  - If hermes_worker watch is running -> skip start; else start minimized.
  - If WebPort is listening -> skip web.
  - Else start missing pieces; open http://127.0.0.1:WebPort/
  Requires: pip install aidun-bridge-c, repo root .env with KQ_POOL_API_KEY.

  NOTE: Runtime log strings are ASCII-only so Windows PowerShell 5.1 -File
  works without UTF-8 BOM mis-parse on Chinese-locale systems.
#>
param(
  [int]$WebPort = 8645,
  [string]$ListenHost = "127.0.0.1",
  [int]$WebReadyTimeoutSec = 45,
  [int]$HermesWatchIntervalSec = 5,
  [switch]$NoHermesWorker
)

$ErrorActionPreference = "Continue"

# Log must work before Resolve-Path, or a path error leaves no log file on disk.
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

Write-Log "=== begin PSScriptRoot=$PSScriptRoot initialPWD=$((Get-Location).Path) ==="

# Explorer-launched processes may have a stale PATH; refresh Machine+User PATH from registry.
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

function Test-WebDashboardListening {
  try {
    $x = @(Get-NetTCPConnection -LocalPort $WebPort -State Listen -ErrorAction SilentlyContinue |
      Where-Object { $_.LocalAddress -eq "127.0.0.1" -or $_.LocalAddress -eq "::" -or $_.LocalAddress -eq "0.0.0.0" })
    return $x.Count -gt 0
  } catch {
    return $false
  }
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

# --- aidun-hermes-worker watch (reads data/pending, reply to pool) ---
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
