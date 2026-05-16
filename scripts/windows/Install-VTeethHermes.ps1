$ErrorActionPreference = "Stop"

Write-Host "===== V-Teeth Hermes Agent Windows Installer ====="

$BaseDir = "D:\vteeth"
$HermesHome = Join-Path $BaseDir "hermes"
$InstallDir = Join-Path $HermesHome "hermes-agent"
$InstallerDir = Join-Path $BaseDir "_installers\hermes"
$InstallerPath = Join-Path $InstallerDir "install.ps1"
$InstallerUrl = "https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.ps1"

$HermesBin = Join-Path $HermesHome "bin"
$HermesExe = Join-Path $InstallDir "venv\Scripts\hermes.exe"
$HermesCmd = Join-Path $HermesBin "hermes.cmd"
$SkinDir = Join-Path $HermesHome "skins"
$SkinPath = Join-Path $SkinDir "vteeth.yaml"
$BannerFile = Join-Path $InstallDir "hermes_cli\banner.py"

function Repeat-Text {
    param(
        [string]$Text,
        [int]$Count
    )

    if ($Count -le 0) {
        return ""
    }

    return -join (1..$Count | ForEach-Object { $Text })
}

if ($env:OS -ne "Windows_NT") {
    throw "This script must run on Windows."
}

if (-not (Test-Path "D:\")) {
    throw "Drive D: was not found."
}

Write-Host ""
Write-Host "[1/10] Creating base directories..."
New-Item -ItemType Directory -Force -Path $BaseDir | Out-Null
New-Item -ItemType Directory -Force -Path $InstallerDir | Out-Null

Write-Host "HermesHome: $HermesHome"
Write-Host "InstallDir : $InstallDir"

Write-Host ""
Write-Host "[2/10] Downloading official Hermes Agent installer..."

try {
    Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallerPath -UseBasicParsing
    Write-Host "Downloaded: $InstallerPath"
} catch {
    throw "Failed to download installer. Check VPN and raw.githubusercontent.com access. Error: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "[3/10] Rewriting official installer as UTF-8 with BOM..."

try {
    $InstallerText = [System.IO.File]::ReadAllText($InstallerPath, [System.Text.Encoding]::UTF8)
    $Utf8Bom = New-Object System.Text.UTF8Encoding -ArgumentList $true
    [System.IO.File]::WriteAllText($InstallerPath, $InstallerText, $Utf8Bom)
    Write-Host "Encoding fixed: $InstallerPath"
} catch {
    throw "Failed to rewrite installer encoding. Error: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "[4/10] Running official installer..."
Write-Host "Important: if the installer asks whether to start Hermes now, choose No."
Write-Host ""

powershell -NoProfile -ExecutionPolicy Bypass `
    -File $InstallerPath `
    -HermesHome $HermesHome `
    -InstallDir $InstallDir

if (-not (Test-Path $HermesExe)) {
    throw "Hermes executable was not found: $HermesExe"
}

Write-Host ""
Write-Host "[5/10] Creating global hermes command..."

New-Item -ItemType Directory -Force -Path $HermesBin | Out-Null

@"
@echo off
set "HERMES_HOME=$HermesHome"
"$HermesExe" %*
exit /b %ERRORLEVEL%
"@ | Set-Content -Path $HermesCmd -Encoding ASCII

Write-Host "Created: $HermesCmd"

Write-Host ""
Write-Host "[6/10] Setting user environment variables..."

[Environment]::SetEnvironmentVariable("HERMES_HOME", $HermesHome, "User")
$env:HERMES_HOME = $HermesHome

$VenvScripts = Join-Path $InstallDir "venv\Scripts"
$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")

$RemoveFromPath = @(
    $HermesBin,
    $VenvScripts,
    "$env:LOCALAPPDATA\hermes\bin",
    "$env:LOCALAPPDATA\hermes\hermes-agent\venv\Scripts"
) | ForEach-Object { $_.Trim().TrimEnd("\") }

$CleanPathItems = @()

if ($UserPath) {
    $CleanPathItems = $UserPath -split ";" | Where-Object {
        $p = $_.Trim().TrimEnd("\")
        $p -and ($RemoveFromPath -notcontains $p)
    }
}

$NewUserPath = @($HermesBin) + $CleanPathItems
$NewUserPath = ($NewUserPath | Where-Object { $_ -and $_.Trim() }) -join ";"

[Environment]::SetEnvironmentVariable("Path", $NewUserPath, "User")

$MachinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$env:Path = "$HermesBin;$NewUserPath;$MachinePath"

Write-Host "HERMES_HOME set to: $HermesHome"
Write-Host "User PATH includes: $HermesBin"

Write-Host ""
Write-Host "[7/10] Writing V-Teeth skin..."

New-Item -ItemType Directory -Force -Path $SkinDir | Out-Null

$B  = [string][char]0x2588
$R  = [string][char]0x2557
$V  = [string][char]0x2551
$LC = [string][char]0x255A
$UL = [string][char]0x2554
$LR = [string][char]0x255D
$H  = [string][char]0x2550
$TP = [string][char]0x250A

$B2 = Repeat-Text $B 2
$B4 = Repeat-Text $B 4
$B5 = Repeat-Text $B 5
$B7 = Repeat-Text $B 7
$B8 = Repeat-Text $B 8

$H1 = Repeat-Text $H 1
$H2 = Repeat-Text $H 2
$H3 = Repeat-Text $H 3
$H4 = Repeat-Text $H 4
$H6 = Repeat-Text $H 6

$SkinLines = @(
    "name: vteeth",
    "description: V-Teeth custom skin",
    "",
    "colors:",
    '  banner_border: "#FF6600"',
    '  banner_title: "#FF6600"',
    '  banner_accent: "#FF6600"',
    '  banner_dim: "#B85A00"',
    '  banner_text: "#FFFFFF"',
    "",
    "branding:",
    '  agent_name: "V-Teeth"',
    '  welcome: "Welcome to V-Teeth."',
    '  goodbye: "Goodbye from V-Teeth."',
    '  response_label: " V-Teeth "',
    '  prompt_symbol: ">"',
    '  help_header: "V-Teeth Commands"',
    "",
    "banner_logo: |",
    "  [bold #FF6600]",
    "  $B2$R   $B2$R      $B8$R$B7$R$B7$R$B8$R$B2$R  $B2$R",
    "  $B2$V   $B2$V      $LC$H2$B2$UL$H2$LR$B2$UL$H4$LR$B2$UL$H4$LR$LC$H2$B2$UL$H2$LR$B2$V  $B2$V",
    "  $B2$V   $B2$V$B5$R   $B2$V   $B5$R  $B5$R     $B2$V   $B7$V",
    "  $LC$B2$R $B2$UL$LR$LC$H4$LR   $B2$V   $B2$UL$H2$LR  $B2$UL$H2$LR     $B2$V   $B2$UL$H2$B2$V",
    "   $LC$B4$UL$LR          $B2$V   $B7$R$B7$R   $B2$V   $B2$V  $B2$V",
    "    $LC$H3$LR           $LC$H1$LR   $LC$H6$LR$LC$H6$LR   $LC$H1$LR   $LC$H1$LR  $LC$H1$LR",
    "  [/]",
    "",
    "banner_hero: |",
    "  [bold #FF6600]",
    "",
    "",
    "",
    "      $B2$R   $B2$R      $B8$R",
    "      $B2$V   $B2$V      $LC$H2$B2$UL$H2$LR",
    "      $B2$V   $B2$V$B5$R   $B2$V",
    "      $LC$B2$R $B2$UL$LR$LC$H4$LR   $B2$V",
    "       $LC$B4$UL$LR          $B2$V",
    "        $LC$H3$LR           $LC$H1$LR",
    "",
    "",
    "",
    "  [/]",
    "",
    "tool_prefix: `"$TP`""
)

$SkinText = ($SkinLines -join "`r`n") + "`r`n"
$Utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
[System.IO.File]::WriteAllText($SkinPath, $SkinText, $Utf8NoBom)

Write-Host "Skin written: $SkinPath"

Write-Host ""
Write-Host "[7.5] Patching ui-tui banner (multiline [#hex]...[/] skin logo colors)..."

$BridgeRepoRootForTui = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$PatchBannerTs = Join-Path $BridgeRepoRootForTui "patches\hermes-windows\ui-tui-src-banner.ts"
$TuiBannerTs = Join-Path $InstallDir "ui-tui\src\banner.ts"
if ((Test-Path -LiteralPath $PatchBannerTs) -and (Test-Path -LiteralPath (Split-Path $TuiBannerTs -Parent))) {
  Copy-Item -LiteralPath $PatchBannerTs -Destination $TuiBannerTs -Force
  Write-Host "Applied: ui-tui/src/banner.ts"
} else {
  Write-Host "Warning: ui-tui banner patch skipped (missing patch file or ui-tui/src)."
}

Write-Host ""
Write-Host "[8/10] Patching Hermes banner title and hero alignment..."

if (-not (Test-Path $BannerFile)) {
    throw "banner.py not found: $BannerFile"
}

Copy-Item $BannerFile "$BannerFile.bak.vteeth" -Force

$BannerText = [System.IO.File]::ReadAllText($BannerFile, [System.Text.Encoding]::UTF8)

$TitlePattern = '(?m)^(\s*)base\s*=\s*f".*?v\{VERSION\} \(\{RELEASE_DATE\}\)"'
$TitleRegex = New-Object System.Text.RegularExpressions.Regex($TitlePattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)

if ($TitleRegex.IsMatch($BannerText)) {
    $BannerText = $TitleRegex.Replace(
        $BannerText,
        '$1base = f"V-Teeth: Hermes Agent v{VERSION} ({RELEASE_DATE})"',
        1
    )
    Write-Host "Title patched: V-Teeth: Hermes Agent ..."
} else {
    Write-Host "Warning: title target line not found."
}

if ($BannerText -like '*layout_table.add_column("left", justify="center")*') {
    $BannerText = $BannerText.Replace(
        'layout_table.add_column("left", justify="center")',
        'layout_table.add_column("left", justify="left")'
    )
    Write-Host "Hero alignment patched: center -> left."
} elseif ($BannerText -like '*layout_table.add_column("left", justify="left")*') {
    Write-Host "Hero alignment already patched."
} else {
    Write-Host "Warning: hero alignment target line not found."
}

[System.IO.File]::WriteAllText($BannerFile, $BannerText, $Utf8NoBom)

Write-Host ""
Write-Host "[9/10] Applying V-Teeth skin..."

& $HermesExe config set display.skin vteeth

Write-Host ""
Write-Host "[10/11] Hermes agent cwd (bridge repo; webhook off by default)..."

$webhookHelper = Join-Path $PSScriptRoot "Ensure-HermesBridgeWebhook.ps1"
if (Test-Path -LiteralPath $webhookHelper) {
    . $webhookHelper
    $bridgeRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
    $null = Invoke-HermesWindowsAgentSetup -LauncherPath $HermesCmd -GatewayPort 8644 -BridgeRepoRoot $bridgeRoot -EnableWebhook $true
    Enable-BridgePoolWebhookNotify -BridgeRepoRoot $bridgeRoot -GatewayPort 8644 | Out-Null
    Write-Host "terminal.cwd + gateway 8644 + bridge-task webhook enabled for $bridgeRoot"
} else {
    Write-Host "Warning: $webhookHelper not found; run start script once."
}

Write-Host ""
Write-Host "[11/11] Testing Hermes..."

& $HermesExe --version
& $HermesExe doctor

Write-Host ""
Write-Host "===== Done ====="
Write-Host "Hermes Agent installed at: $HermesHome"
Write-Host "Global command created: $HermesCmd"
Write-Host ""
Write-Host "Close this CMD/PowerShell window and open a new one."
Write-Host "Then test:"
Write-Host "  where.exe hermes"
Write-Host "  hermes --version"
Write-Host "  hermes doctor"
Write-Host "  hermes"