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

function Ensure-HermesBridgeTaskSubscription {
  param(
    [string]$HermesHome,
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
  if ($subs.ContainsKey($RouteName)) { return }
  $stamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  $prompt = 'Bridge C pool task notification. Parse the JSON body for record_id, read data/pending/{record_id}.json in the bridge_c repo, process per channel in docs/HERMES.md, then run hermes_worker.py reply with the record id and your answer text.'
  $subs[$RouteName] = [ordered]@{
    description = "Bridge C pool notify (KQ_POOL_NOTIFY_WEBHOOK_URL)"
    events      = @()
    secret      = "INSECURE_NO_AUTH"
    prompt      = $prompt
    skills      = @()
    deliver     = "log"
    created_at  = $stamp
  }
  $json = $subs | ConvertTo-Json -Depth 8
  $utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
  [System.IO.File]::WriteAllText($subsPath, $json, $utf8)
}

function Ensure-HermesBridgeWebhookSetup {
  param(
    [string]$LauncherPath,
    [int]$GatewayPort = 8644,
    [string]$WebhookRouteName = "bridge-task"
  )
  $hermesHome = Get-HermesHomeFromLauncher -LauncherPath $LauncherPath
  if (-not $hermesHome) {
    Write-Warning "Ensure-HermesBridgeWebhookSetup: could not resolve HERMES_HOME from launcher."
    return $null
  }
  $hermesExe = Get-HermesExeFromLauncher -LauncherPath $LauncherPath
  Ensure-HermesWebhookPlatform -HermesHome $hermesHome -HermesExe $hermesExe -Port $GatewayPort
  Ensure-HermesBridgeTaskSubscription -HermesHome $hermesHome -RouteName $WebhookRouteName
  return $hermesHome
}
