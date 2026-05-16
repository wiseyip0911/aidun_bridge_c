#Requires -Version 5.1
<#
.SYNOPSIS
  Hermes Windows Agent 安装目录侧必做初始化(编码补丁、PYTHONUTF8、terminal、审批、Tirith 等)。

.DESCRIPTION
  仅处理 Hermes 安装树(hermes-agent、.env、hermes.exe config),不修改 aidun_bridge_c 仓库内 Python/启动器/文档。
  依赖同目录 Ensure-HermesBridgeWebhook.ps1 中的 Get-HermesHomeFromLauncher、Ensure-HermesWindowsAgentEnv 等。
  补丁文件来自仓库 patches/hermes-windows/（含 ui-tui-src-banner.ts）与 patch_browser_tool_windows_capture.py。

.NOTES
  对应原清单中的 1、2、5–9。bridge 仓库内行为(启动器、Python、文档)以源码为准,不在此脚本修补。
#>

function Test-HermesAgentEncodingPatch {
  param([string]$HermesAgentRoot)
  $issues = [System.Collections.Generic.List[string]]::new()
  if (-not $HermesAgentRoot) {
    $issues.Add("Hermes hermes-agent 目录未知,跳过编码补丁检测")
    return $issues
  }
  $pp = Join-Path $HermesAgentRoot "hermes_platform_paths.py"
  $bt = Join-Path $HermesAgentRoot "tools\browser_tool.py"
  if (-not (Test-Path -LiteralPath $pp)) {
    $issues.Add("缺少 hermes_platform_paths.py: $pp")
  } else {
    $s = Get-Content -LiteralPath $pp -Raw -Encoding UTF8
    if ($s -notmatch "read_subprocess_capture_file") {
      $issues.Add("hermes_platform_paths.py 未包含 read_subprocess_capture_file")
    }
    if ($s -notmatch "gbk") {
      $issues.Add("hermes_platform_paths.py 未包含 gbk 解码回退")
    }
  }
  if (-not (Test-Path -LiteralPath $bt)) {
    $issues.Add("缺少 tools/browser_tool.py: $bt")
  } else {
    $s2 = Get-Content -LiteralPath $bt -Raw -Encoding UTF8
    if ($s2 -notmatch "from hermes_platform_paths import read_subprocess_capture_file") {
      $issues.Add("browser_tool.py 未导入 read_subprocess_capture_file")
    }
    if ($s2 -notmatch "read_subprocess_capture_file\(stdout_path\)") {
      $issues.Add("browser_tool.py 未使用 read_subprocess_capture_file 读取 stdout 捕获文件")
    }
  }
  $tuiBanner = Join-Path $HermesAgentRoot "ui-tui\src\banner.ts"
  if (Test-Path -LiteralPath $tuiBanner) {
    $bs = Get-Content -LiteralPath $tuiBanner -Raw -Encoding UTF8
    if ($bs -notmatch "full\.matchAll\(RICH_RE\)") {
      $issues.Add("ui-tui/src/banner.ts 未应用多行 Rich 着色补丁(开标签与[/]跨行时 logo 会变白)")
    }
  }
  return @($issues)
}

function Invoke-HermesAgentEncodingPatch {
  param(
    [string]$HermesAgentRoot,
    [string]$PatchDir,
    [hashtable]$Py
  )
  if (-not $HermesAgentRoot -or -not (Test-Path -LiteralPath $HermesAgentRoot)) { return $false }
  $changed = $false
  $srcPp = Join-Path $PatchDir "hermes_platform_paths.py"
  $dstPp = Join-Path $HermesAgentRoot "hermes_platform_paths.py"
  if ((Test-Path -LiteralPath $srcPp) -and (Test-Path -LiteralPath $dstPp)) {
    Copy-Item -LiteralPath $srcPp -Destination $dstPp -Force
    $changed = $true
  }
  $patchPy = Join-Path $PSScriptRoot "patch_browser_tool_windows_capture.py"
  $bt = Join-Path $HermesAgentRoot "tools\browser_tool.py"
  if ((Test-Path -LiteralPath $patchPy) -and (Test-Path -LiteralPath $bt)) {
    $args = @()
    if ($Py.Prefix.Count -gt 0) { $args += $Py.Prefix }
    $args += @($patchPy, $bt)
    & $Py.Exe @args
    if ($LASTEXITCODE -eq 0) { $changed = $true }
  }
  $srcBanner = Join-Path $PatchDir "ui-tui-src-banner.ts"
  $dstBanner = Join-Path $HermesAgentRoot "ui-tui\src\banner.ts"
  if ((Test-Path -LiteralPath $srcBanner) -and (Test-Path -LiteralPath (Split-Path $dstBanner -Parent))) {
    Copy-Item -LiteralPath $srcBanner -Destination $dstBanner -Force
    $changed = $true
  }
  return $changed
}

function Test-AidunHermesWindowsAgentMandatoryFixes {
  param(
    [string]$BridgeRepoRoot,
    [string]$HermesLauncherPath,
    [int]$GatewayPort = 8644,
    [hashtable]$Py
  )
  $all = [System.Collections.Generic.List[string]]::new()
  $scriptRoot = $PSScriptRoot
  $ensurePath = Join-Path $scriptRoot "Ensure-HermesBridgeWebhook.ps1"
  if (Test-Path -LiteralPath $ensurePath) { . $ensurePath }

  $hermesHome = $null
  $hermesExe = $null
  $hermesAgent = $null
  if ($HermesLauncherPath) {
    $hermesHome = Get-HermesHomeFromLauncher -LauncherPath $HermesLauncherPath
    $hermesExe = Get-HermesExeFromLauncher -LauncherPath $HermesLauncherPath
    if ($hermesHome) {
      $hermesAgent = Join-Path $hermesHome "hermes-agent"
    }
  }

  if ($hermesAgent) {
    foreach ($x in @(Test-HermesAgentEncodingPatch -HermesAgentRoot $hermesAgent)) { $all.Add("1 $x") }
  }
  if ($hermesHome) {
    $hEnv = Join-Path $hermesHome ".env"
    if (-not (Test-Path $hEnv)) { $all.Add("2 Hermes .env 不存在: $hEnv") }
    else {
      $ev = Get-Content -LiteralPath $hEnv -Raw -Encoding UTF8
      if ($ev -notmatch "(?m)^\s*PYTHONUTF8\s*=\s*1\s*$") { $all.Add("2 Hermes .env 缺少 PYTHONUTF8=1") }
    }
  }

  if ($hermesExe -and (Test-Path $hermesExe) -and $BridgeRepoRoot) {
    $null = & $hermesExe config get terminal.backend 2>$null
    foreach ($issue in @(Test-HermesWindowsAgentConfig -HermesHome $hermesHome -BridgeRepoRoot $BridgeRepoRoot)) {
      if ($issue -match "terminal\.backend") { $all.Add("6 $issue") }
      elseif ($issue -match "terminal\.cwd|TERMINAL_CWD") { $all.Add("5 $issue") }
      elseif ($issue -match "GIT_BASH|bash") { $all.Add("7 $issue") }
      elseif ($issue -match "approvals") { $all.Add("8 $issue") }
      elseif ($issue -match "tirith") { $all.Add("9 $issue") }
      else { $all.Add("5-9 $issue") }
    }
  }

  return [pscustomobject]@{
    AllPassed = ($all.Count -eq 0)
    Issues    = @($all)
  }
}

function Invoke-AidunHermesWindowsAgentMandatoryFixes {
  param(
    [string]$BridgeRepoRoot,
    [string]$HermesLauncherPath,
    [int]$GatewayPort = 8644,
    [hashtable]$Py,
    [switch]$WhatIf
  )
  $scriptRoot = $PSScriptRoot
  $ensurePath = Join-Path $scriptRoot "Ensure-HermesBridgeWebhook.ps1"
  if (Test-Path -LiteralPath $ensurePath) { . $ensurePath }

  $hermesHome = $null
  $hermesExe = $null
  $hermesAgent = $null
  if ($HermesLauncherPath) {
    $hermesHome = Get-HermesHomeFromLauncher -LauncherPath $HermesLauncherPath
    $hermesExe = Get-HermesExeFromLauncher -LauncherPath $HermesLauncherPath
    if ($hermesHome) { $hermesAgent = Join-Path $hermesHome "hermes-agent" }
  }

  $log = [System.Collections.Generic.List[string]]::new()
  if ($WhatIf) {
    $log.Add("[WhatIf] 不写入任何文件")
    return [pscustomobject]@{ Log = @($log); Applied = $false; StillIssues = @(); AllPassed = $false }
  }

  $preflight = Test-AidunHermesWindowsAgentMandatoryFixes -BridgeRepoRoot $BridgeRepoRoot -HermesLauncherPath $HermesLauncherPath -GatewayPort $GatewayPort -Py $Py
  if ($preflight.AllPassed) {
    return [pscustomobject]@{
      Log         = @()
      Applied     = $false
      StillIssues = @()
      AllPassed   = $true
    }
  }

  $patchDir = Join-Path $BridgeRepoRoot "patches\hermes-windows"
  if ($hermesAgent -and (Test-Path $patchDir)) {
    if (Invoke-HermesAgentEncodingPatch -HermesAgentRoot $hermesAgent -PatchDir $patchDir -Py $Py) {
      $log.Add("已应用: Hermes hermes_platform_paths / browser_tool / ui-tui banner(多行 Rich) 补丁")
    }
  }

  if ($hermesExe -and $BridgeRepoRoot -and (Get-Command Ensure-HermesWindowsAgentEnv -ErrorAction SilentlyContinue)) {
    Ensure-HermesWindowsAgentEnv -HermesExe $hermesExe -BridgeRepoRoot $BridgeRepoRoot -HermesHome $hermesHome
    $hEnv = Join-Path $hermesHome ".env"
    if (Get-Command Set-HermesEnvLine -ErrorAction SilentlyContinue) {
      Set-HermesEnvLine -EnvPath $hEnv -Key "PYTHONUTF8" -Value "1"
    }
    $log.Add("已应用: Hermes Windows agent .env + terminal + approvals + tirith(Ensure 脚本逻辑)")
  }

  $after = Test-AidunHermesWindowsAgentMandatoryFixes -BridgeRepoRoot $BridgeRepoRoot -HermesLauncherPath $HermesLauncherPath -GatewayPort $GatewayPort -Py $Py
  return [pscustomobject]@{
    Log         = @($log)
    Applied     = ($log.Count -gt 0)
    StillIssues = $after.Issues
    AllPassed   = $after.AllPassed
  }
}
