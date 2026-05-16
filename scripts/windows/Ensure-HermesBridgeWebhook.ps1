# bridge_c client: enable Hermes webhook (loopback) + default bridge-task route.
# Dot-source from start_bridge_and_dashboard.ps1 and enterprise Install-*Hermes.ps1.

function Get-HermesHomeFromLauncher {
  param([string]$LauncherPath)
  if ($env:HERMES_HOME -and (Test-Path -LiteralPath $env:HERMES_HOME)) {
    return $env:HERMES_HOME
  }
  if (-not $LauncherPath) { return $null }
  $bin = Split-Path -Parent $LauncherPath
  $hermesHome = Split-Path -Parent $bin
  if (Test-Path -LiteralPath (Join-Path $hermesHome "config.yaml")) { return $hermesHome }
  if (Test-Path -LiteralPath (Join-Path $hermesHome "hermes-agent")) { return $hermesHome }
  return $hermesHome
}

function Set-HermesEnvLine {
  param(
    [string]$EnvPath,
    [string]$Key,
    [string]$Value
  )
  $lines = @()
  if (Test-Path -LiteralPath $EnvPath) {
    $lines = @(Get-Content -LiteralPath $EnvPath -Encoding UTF8)
  }
  $pat = "^\s*$([regex]::Escape($Key))\s*="
  $found = $false
  $out = [System.Collections.Generic.List[string]]::new()
  foreach ($line in $lines) {
    if ($line -match $pat) {
      $found = $true
      $out.Add("$Key=$Value")
    } else {
      $out.Add($line)
    }
  }
  if (-not $found) {
    if ($out.Count -gt 0 -and $out[$out.Count - 1] -ne "") { $out.Add("") }
    $out.Add("# bridge-c-client (auto)")
    $out.Add("$Key=$Value")
  }
  $utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
  [System.IO.File]::WriteAllLines($EnvPath, $out.ToArray(), $utf8)
}

function Get-HermesExeFromLauncher {
  param([string]$LauncherPath)
  if (-not $LauncherPath) { return $null }
  $hermesHome = Get-HermesHomeFromLauncher -LauncherPath $LauncherPath
  if (-not $hermesHome) { return $null }
  $exe = Join-Path $hermesHome "hermes-agent\venv\Scripts\hermes.exe"
  if (Test-Path -LiteralPath $exe) { return $exe }
  return $null
}

function Get-BridgePoolNotifyWebhookActive {
  param([string]$BridgeRepoRoot)
  if (-not $BridgeRepoRoot) { return $false }
  $envPath = Join-Path $BridgeRepoRoot ".env"
  if (-not (Test-Path -LiteralPath $envPath)) { return $false }
  foreach ($line in @(Get-Content -LiteralPath $envPath -Encoding UTF8)) {
    $t = $line.Trim()
    if (-not $t -or $t.StartsWith("#")) { continue }
    if ($t -match '^\s*KQ_POOL_NOTIFY_WEBHOOK_URL\s*=\s*(.+)$') {
      $v = $Matches[1].Trim().Trim('"').Trim([char]39)
      return ($v.Length -gt 0)
    }
  }
  return $false
}

function Test-BridgePoolNotifyWebhookActive {
  param([string]$BridgeRepoRoot)
  return Get-BridgePoolNotifyWebhookActive -BridgeRepoRoot $BridgeRepoRoot
}

function Ensure-HermesWebhookPlatform {
  param(
    [string]$HermesHome,
    [string]$HermesExe,
    [int]$Port = 8644
  )
  if (-not $HermesHome) { return }
  $envPath = Join-Path $HermesHome ".env"
  if (-not (Test-Path -LiteralPath $envPath)) {
    New-Item -ItemType File -Path $envPath -Force | Out-Null
  }
  Set-HermesEnvLine -EnvPath $envPath -Key "WEBHOOK_ENABLED" -Value "true"
  Set-HermesEnvLine -EnvPath $envPath -Key "WEBHOOK_PORT" -Value "$Port"
  # INSECURE_NO_AUTH requires loopback bind; default 0.0.0.0 would refuse to start.
  if ($HermesExe -and (Test-Path -LiteralPath $HermesExe)) {
    $prevHome = $env:HERMES_HOME
    $env:HERMES_HOME = $HermesHome
    try {
      & $HermesExe config set platforms.webhook.enabled true 2>&1 | Out-Null
      & $HermesExe config set platforms.webhook.extra.host 127.0.0.1 2>&1 | Out-Null
      & $HermesExe config set platforms.webhook.extra.port $Port 2>&1 | Out-Null
    } finally {
      if ($null -ne $prevHome) { $env:HERMES_HOME = $prevHome } else { Remove-Item Env:\HERMES_HOME -ErrorAction SilentlyContinue }
    }
  }
}

function Get-BridgeTaskWebhookPrompt {
  param([string]$BridgeRepoRoot)
  $root = "D:\aidun\aidun_bridge_c"
  if ($BridgeRepoRoot) {
    try { $root = [System.IO.Path]::GetFullPath($BridgeRepoRoot) } catch {}
  }
  return @"
Aidun bridge C pool task. Parse JSON for record_id.
Working directory is already TERMINAL_CWD ($root); use Windows paths in file tools.
Read data/pending/{record_id}.json, follow docs/HERMES.md, then run:
  aidun-hermes-worker reply <rid_prefix> "<answer>"
Do not use python hermes_worker.py or Unix-only /d/ paths. If task not found, it may already be replied.
"@
}

function Ensure-HermesBridgeTaskSubscription {
  param(
    [string]$HermesHome,
    [string]$BridgeRepoRoot = "",
    [string]$RouteName = "bridge-task"
  )
  if (-not $HermesHome) { return }
  $subsPath = Join-Path $HermesHome "webhook_subscriptions.json"
  $subs = @{}
  if (Test-Path -LiteralPath $subsPath) {
    try {
      $raw = Get-Content -LiteralPath $subsPath -Raw -Encoding UTF8
      $parsed = $raw | ConvertFrom-Json
      if ($parsed) {
        $parsed.PSObject.Properties | ForEach-Object { $subs[$_.Name] = $_.Value }
      }
    } catch {}
  }
  $stamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  $created = $stamp
  if ($subs.ContainsKey($RouteName) -and $subs[$RouteName].created_at) {
    $created = $subs[$RouteName].created_at
  }
  $prompt = Get-BridgeTaskWebhookPrompt -BridgeRepoRoot $BridgeRepoRoot
  $subs[$RouteName] = [ordered]@{
    description = "Bridge C pool notify (KQ_POOL_NOTIFY_WEBHOOK_URL)"
    events      = @()
    secret      = "INSECURE_NO_AUTH"
    prompt      = $prompt
    skills      = @()
    deliver     = "log"
    created_at  = $created
  }
  $json = $subs | ConvertTo-Json -Depth 8
  $utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
  [System.IO.File]::WriteAllText($subsPath, $json, $utf8)
}

function Enable-BridgePoolWebhookNotify {
  param(
    [string]$BridgeRepoRoot,
    [int]$GatewayPort = 8644
  )
  if (-not $BridgeRepoRoot) { return $false }
  $envPath = Join-Path $BridgeRepoRoot ".env"
  if (-not (Test-Path -LiteralPath $envPath)) {
    New-Item -ItemType File -Path $envPath -Force | Out-Null
  }
  $url = "http://127.0.0.1:$GatewayPort/webhooks/bridge-task"
  Set-HermesEnvLine -EnvPath $envPath -Key "KQ_POOL_NOTIFY_WEBHOOK_URL" -Value $url
  Set-HermesEnvLine -EnvPath $envPath -Key "KQ_POOL_NOTIFY_WEBHOOK_SECRET" -Value "INSECURE_NO_AUTH"
  return $true
}

function Disable-BridgePoolWebhookNotify {
  param([string]$BridgeRepoRoot)
  if (-not $BridgeRepoRoot) { return $false }
  $envPath = Join-Path $BridgeRepoRoot ".env"
  if (-not (Test-Path -LiteralPath $envPath)) { return $false }
  $keys = @(
    "KQ_POOL_NOTIFY_WEBHOOK_URL",
    "KQ_POOL_NOTIFY_WEBHOOK_SECRET",
    "KQ_POOL_NOTIFY_WEBHOOK_TIMEOUT_SEC"
  )
  $lines = @(Get-Content -LiteralPath $envPath -Encoding UTF8)
  $changed = $false
  $out = [System.Collections.Generic.List[string]]::new()
  foreach ($line in $lines) {
    $trim = $line.TrimStart()
    $active = $true
    if ($trim.StartsWith("#")) { $active = $false }
    $matched = $false
    foreach ($key in $keys) {
      $pat = "^\s*#?\s*$([regex]::Escape($key))\s*="
      if ($line -match $pat) {
        $matched = $true
        if ($active) {
          $out.Add("# $line")
          $changed = $true
        } else {
          $out.Add($line)
        }
        break
      }
    }
    if (-not $matched) { $out.Add($line) }
  }
  if ($changed) {
    $utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
    [System.IO.File]::WriteAllLines($envPath, $out.ToArray(), $utf8)
  }
  return $changed
}

function Ensure-HermesBridgeAgentEnvOnly {
  param(
    [string]$LauncherPath,
    [string]$BridgeRepoRoot
  )
  $hermesExe = Get-HermesExeFromLauncher -LauncherPath $LauncherPath
  $hermesHome = Get-HermesHomeFromLauncher -LauncherPath $LauncherPath
  Ensure-HermesWindowsAgentEnv -HermesExe $hermesExe -BridgeRepoRoot $BridgeRepoRoot -HermesHome $hermesHome
  return $hermesHome
}

function Ensure-HermesWindowsAgentEnv {
  param(
    [string]$HermesExe,
    [string]$BridgeRepoRoot,
    [string]$HermesHome = ""
  )
  if (-not $HermesExe -or -not (Test-Path -LiteralPath $HermesExe)) { return }
  if (-not $BridgeRepoRoot) { return }
  try {
    $root = [System.IO.Path]::GetFullPath($BridgeRepoRoot)
    if (-not (Test-Path -LiteralPath $root)) { return }
  } catch { return }
  # config.yaml terminal.cwd -> gateway exports TERMINAL_CWD (see hermes cli.py)
  $cwdWin = $root
  $cwdYaml = ($root -replace '\\', '/')
  & $HermesExe config set terminal.backend local 2>&1 | Out-Null
  & $HermesExe config set terminal.cwd $cwdYaml 2>&1 | Out-Null
  & $HermesExe config set security.tirith_enabled false 2>&1 | Out-Null
  # Unattended bridge webhook: auto-approve terminal tools (user handles policy at gateway).
  & $HermesExe config set approvals.mode off 2>&1 | Out-Null
  if (-not $HermesHome) {
    $HermesHome = (Split-Path -Parent (Split-Path -Parent $HermesExe))
  }
  if ($HermesHome -and (Test-Path -LiteralPath $HermesHome)) {
    $envPath = Join-Path $HermesHome ".env"
    if (-not (Test-Path -LiteralPath $envPath)) {
      New-Item -ItemType File -Path $envPath -Force | Out-Null
    }
    Set-HermesEnvLine -EnvPath $envPath -Key "GATEWAY_ALLOW_ALL_USERS" -Value "true"
    Set-HermesEnvLine -EnvPath $envPath -Key "HERMES_EXEC_ASK" -Value "0"
    Set-HermesEnvLine -EnvPath $envPath -Key "HERMES_HOST_OS" -Value "windows"
    Set-HermesEnvLine -EnvPath $envPath -Key "PYTHONUTF8" -Value "1"
    Set-HermesEnvLine -EnvPath $envPath -Key "TERMINAL_CWD" -Value $cwdWin
    $bash = Join-Path $HermesHome "git\usr\bin\bash.exe"
    if (-not (Test-Path -LiteralPath $bash)) {
      $bash = Join-Path $HermesHome "git\bin\bash.exe"
    }
    if (Test-Path -LiteralPath $bash) {
      Set-HermesEnvLine -EnvPath $envPath -Key "HERMES_GIT_BASH_PATH" -Value $bash
    }
  }
}

function Test-HermesWindowsAgentConfig {
  param(
    [string]$HermesHome,
    [string]$BridgeRepoRoot
  )
  $issues = [System.Collections.Generic.List[string]]::new()
  if (-not $HermesHome) { return @() }
  $text = ""
  $cfgPath = Join-Path $HermesHome "config.yaml"
  if (Test-Path -LiteralPath $cfgPath) {
    $text = Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8
    if ($text -notmatch '(?ms)terminal:\s*[\s\S]*?backend:\s*local\b') {
      $issues.Add("config.yaml: terminal.backend should be local on Windows")
    }
    if ($text -match '(?ms)terminal:\s*[\s\S]*?cwd:\s*([^\r\n#]+)') {
      $cwdCfg = $Matches[1].Trim()
      if ($cwdCfg -match '^/[a-zA-Z]/') {
        $issues.Add("config.yaml: terminal.cwd is MSYS path ($cwdCfg); run launcher to fix")
      }
    }
  } else {
    $issues.Add("config.yaml missing under HERMES_HOME")
  }
  $envPath = Join-Path $HermesHome ".env"
  if (Test-Path -LiteralPath $envPath) {
    $tcwdLine = @(Get-Content -LiteralPath $envPath -Encoding UTF8 | Where-Object { $_ -match '^\s*TERMINAL_CWD\s*=' })[0]
    if (-not $tcwdLine) {
      $issues.Add(".env: TERMINAL_CWD not set (gateway tools use wrong cwd)")
    } elseif ($tcwdLine -match 'TERMINAL_CWD\s*=\s*/[a-zA-Z]/') {
      $issues.Add(".env: TERMINAL_CWD is MSYS path; run launcher to fix")
    }
    $hostOs = @(Get-Content -LiteralPath $envPath -Encoding UTF8 | Where-Object { $_ -match '^\s*HERMES_HOST_OS\s*=' })[0]
    if (-not $hostOs) {
      $issues.Add(".env: HERMES_HOST_OS not set")
    }
    $execAsk = @(Get-Content -LiteralPath $envPath -Encoding UTF8 | Where-Object { $_ -match '^\s*HERMES_EXEC_ASK\s*=' })[0]
    if ($execAsk -and $execAsk -notmatch 'HERMES_EXEC_ASK\s*=\s*0\b') {
      $issues.Add(".env: HERMES_EXEC_ASK should be 0 for unattended bridge tasks")
    }
  }
  if ($text -match '(?ms)approvals:\s*[\s\S]*?mode:\s*(\S+)') {
    $mode = $Matches[1].Trim().ToLower()
    if ($mode -notin @('off', 'false', '0', 'no')) {
      $issues.Add("config.yaml: approvals.mode is '$mode'; should be off/false for bridge auto-exec")
    }
  }
  if ($BridgeRepoRoot) {
    try {
      $want = [System.IO.Path]::GetFullPath($BridgeRepoRoot)
      if ($text -match '(?ms)terminal:\s*[\s\S]*?cwd:\s*([^\r\n#]+)') {
        $cwdCfg = $Matches[1].Trim() -replace '/', '\'
        if ($cwdCfg -and ($cwdCfg -ne $want) -and ($cwdCfg -ne ($want -replace '\\', '/'))) {
          $issues.Add("terminal.cwd ($cwdCfg) != bridge root ($want)")
        }
      }
    } catch {}
  }
  return @($issues)
}

function Invoke-HermesWindowsAgentSetup {
  param(
    [string]$LauncherPath,
    [string]$BridgeRepoRoot,
    [int]$GatewayPort = 8644,
    [bool]$EnableWebhook = $true,
    [string]$WebhookRouteName = "bridge-task"
  )
  $hermesHome = Get-HermesHomeFromLauncher -LauncherPath $LauncherPath
  if (-not $hermesHome) {
    Write-Warning "Invoke-HermesWindowsAgentSetup: could not resolve HERMES_HOME."
    return @{ Home = $null; Issues = @("HERMES_HOME not found") }
  }
  $hermesExe = Get-HermesExeFromLauncher -LauncherPath $LauncherPath
  Ensure-HermesWindowsAgentEnv -HermesExe $hermesExe -BridgeRepoRoot $BridgeRepoRoot -HermesHome $hermesHome
  if ($EnableWebhook) {
    Ensure-HermesWebhookPlatform -HermesHome $hermesHome -HermesExe $hermesExe -Port $GatewayPort
    Ensure-HermesBridgeTaskSubscription -HermesHome $hermesHome -BridgeRepoRoot $BridgeRepoRoot -RouteName $WebhookRouteName
  }
  $issues = @(Test-HermesWindowsAgentConfig -HermesHome $hermesHome -BridgeRepoRoot $BridgeRepoRoot)
  return @{ Home = $hermesHome; Issues = $issues }
}

function Ensure-HermesBridgeWebhookSetup {
  param(
    [string]$LauncherPath,
    [int]$GatewayPort = 8644,
    [string]$WebhookRouteName = "bridge-task",
    [string]$BridgeRepoRoot = ""
  )
  $hermesHome = Get-HermesHomeFromLauncher -LauncherPath $LauncherPath
  if (-not $hermesHome) {
    Write-Warning "Ensure-HermesBridgeWebhookSetup: could not resolve HERMES_HOME from launcher."
    return $null
  }
  $hermesExe = Get-HermesExeFromLauncher -LauncherPath $LauncherPath
  Ensure-HermesWebhookPlatform -HermesHome $hermesHome -HermesExe $hermesExe -Port $GatewayPort
  Ensure-HermesBridgeTaskSubscription -HermesHome $hermesHome -BridgeRepoRoot $BridgeRepoRoot -RouteName $WebhookRouteName
  Ensure-HermesWindowsAgentEnv -HermesExe $hermesExe -BridgeRepoRoot $BridgeRepoRoot -HermesHome $hermesHome
  return $hermesHome
}
