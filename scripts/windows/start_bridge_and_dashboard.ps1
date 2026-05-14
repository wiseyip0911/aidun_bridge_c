#Requires -Version 5.1
<#
.SYNOPSIS
  一键启动 Aidun 桥守护 + V-Teeth 消息看板(Windows),并打开浏览器。

.DESCRIPTION
  - 若本机已有桥进程( python/py -m aidun_bridge_c ,非 --once )在跑 → 不重复启动。
  - 若 127.0.0.1:WebPort 已有监听 → 不重复启动看板。
  - 缺谁启谁;最后打开 http://127.0.0.1:WebPort/
  依赖: 已 pip install aidun-bridge-c, 仓库根目录有 .env (含 KQ_POOL_API_KEY)。
#>
param(
  [int]$WebPort = 8645,
  [string]$ListenHost = "127.0.0.1"
)

$ErrorActionPreference = "Continue"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $RepoRoot

function Write-Log([string]$m) {
  $line = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $m
  Write-Host $line
  try {
    Add-Content -Path (Join-Path $env:TEMP "aidun-bridge-dashboard-launcher.log") -Value $line -Encoding UTF8
  } catch {}
}

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
    if ($c -match "pytest|unittest|aidun-chat-web|chat_webapp") { return $false }
    if ($c -notmatch "[\-/]m\s+aidun_bridge_c(\s|$)") { return $false }
    if ($c -match "\-\-once(\s|$)") { return $false }
    $true
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

$py = Get-PythonLauncher
if (-not $py) {
  Write-Log "ERROR: 未找到 py -3 或 python,请先安装 Python 3.10+ 并加入 PATH。"
  Read-Host "按 Enter 关闭"
  exit 1
}

Write-Log "仓库根: $RepoRoot"
Write-Log "Python: $($py.Exe) $($py.Prefix -join ' ')"

if (-not (Test-Path (Join-Path $RepoRoot ".env"))) {
  Write-Log "WARN: 未找到 $RepoRoot\.env ,桥与看板可能因缺少 KQ_POOL_API_KEY 启动失败。请复制 .env.example 为 .env 并填写。"
}

# --- 桥 ---
if (Test-BridgeDaemonRunning) {
  Write-Log "桥守护进程已在运行,跳过启动。"
} else {
  Write-Log "正在启动桥守护进程…"
  $args = @()
  if ($py.Prefix.Count -gt 0) { $args += $py.Prefix }
  $args += @("-m", "aidun_bridge_c", "--no-interactive")
  Start-Process -FilePath $py.Exe -ArgumentList $args -WorkingDirectory $RepoRoot `
    -WindowStyle Minimized
  Start-Sleep -Seconds 2
  if (Test-BridgeDaemonRunning) {
    Write-Log "桥已启动。"
  } else {
    Write-Log "WARN: 未检测到桥进程,可能启动失败。请查看任务管理器或手动运行: py -3 -m aidun_bridge_c --once"
  }
}

# --- 看板 ---
if (Test-WebDashboardListening) {
  Write-Log "看板已在端口 $WebPort 监听,跳过启动。"
} else {
  Write-Log "正在启动 aidun-chat-web (端口 $WebPort)…"
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
  Start-Sleep -Seconds 2
  if (Test-WebDashboardListening) {
    Write-Log "看板已监听 $ListenHost`:$WebPort"
  } else {
    Write-Log "WARN: 端口 $WebPort 仍未监听,可能端口占用或启动失败。"
  }
}

$url = "http://${ListenHost}:${WebPort}/"
Write-Log "打开浏览器: $url"
try {
  Start-Process $url
} catch {
  Write-Log "ERROR: 无法打开浏览器: $_"
  Read-Host "按 Enter 关闭"
  exit 1
}

Write-Log "完成。"
Start-Sleep -Milliseconds 800
