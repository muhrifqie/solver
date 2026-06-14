#requires -Version 5.1
<#
.SYNOPSIS
    One-shot installer for the CAPTCHA solver on a Windows VPS.
    Installs Git, Python and Node.js (only if missing), clones the repo,
    sets up a virtualenv, installs dependencies, downloads camoufox,
    configures .env and opens the firewall ports.

.EXAMPLE
    # Easiest (run from an ADMIN PowerShell):
    Set-ExecutionPolicy Bypass -Scope Process -Force
    iwr -UseBasicParsing https://raw.githubusercontent.com/muhrifqie/solver/main/install.ps1 | iex

    # Or with options:
    & .\install.ps1 -InstallDir D:\solver -AutoStart
#>
[CmdletBinding()]
param(
    [string]$InstallDir = "$env:USERPROFILE\solver",
    [string]$RepoUrl    = "https://github.com/muhrifqie/solver.git",
    [string]$Branch     = "main",
    [switch]$AutoStart,    # register a Scheduled Task to run at boot
    [switch]$NoFirewall,   # skip opening firewall ports
    [switch]$NoNode,       # skip Node.js
    [switch]$Force         # re-clone even if dir exists
)

# URL used to re-elevate when the script is piped via iex.
$InstallerUrl = "https://raw.githubusercontent.com/muhrifqie/solver/main/install.ps1"

# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #
function Write-Step($m){ Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok($m)  { Write-Host "[OK]  $m" -ForegroundColor Green }
function Write-Wn($m)  { Write-Host "[!!]  $m" -ForegroundColor Yellow }
function Write-Err($m) { Write-Host "[X]   $m" -ForegroundColor Red }
function Test-Cmd($n)  { return [bool](Get-Command $n -ErrorAction SilentlyContinue) }

function Update-EnvPath {
    $machine = [Environment]::GetEnvironmentVariable('Path','Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path','User')
    $env:Path = ($machine + ';' + $user)
}

# --------------------------------------------------------------------------- #
# Ensure elevated (auto re-launch as admin)
# --------------------------------------------------------------------------- #
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Wn "Not running as Administrator. Re-launching elevated..."
    if ($PSCommandPath -and (Test-Path $PSCommandPath)) {
        $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
        if ($PSBoundParameters.ContainsKey('InstallDir')) { $argList += '-InstallDir', $InstallDir }
        if ($PSBoundParameters.ContainsKey('RepoUrl'))    { $argList += '-RepoUrl', $RepoUrl }
        if ($PSBoundParameters.ContainsKey('Branch'))     { $argList += '-Branch', $Branch }
        if ($AutoStart)     { $argList += '-AutoStart' }
        if ($NoFirewall)    { $argList += '-NoFirewall' }
        if ($NoNode)        { $argList += '-NoNode' }
        if ($Force)         { $argList += '-Force' }
        Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
    } else {
        $cmd = "Set-ExecutionPolicy Bypass -Scope Process -Force; iwr -UseBasicParsing '$InstallerUrl' | iex"
        Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-Command',$cmd
    }
    exit
}

$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------------------- #
# 1) Detect / install package manager + tools
# --------------------------------------------------------------------------- #
Write-Step "Detecting existing tools"
Update-EnvPath
$hasWinget = Test-Cmd winget
$hasChoco  = Test-Cmd choco
Write-Ok ("winget={0}  choco={1}" -f $hasWinget, $hasChoco)

if (-not $hasWinget -and -not $hasChoco) {
    Write-Step "No winget/choco found -> installing Chocolatey"
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    $env:ChocolateyInstall = "$env:ProgramData\chocolatey"
    Update-EnvPath
    $hasChoco = Test-Cmd choco
    if (-not $hasChoco) { throw "Chocolatey install failed" }
    Write-Ok "Chocolatey installed"
}

function Install-Pkg {
    param([string]$WingetId,[string]$ChocoPkg,[string]$Label)
    Write-Step "Installing $Label"
    if ($hasWinget) {
        winget install --id $WingetId -e --source winget `
            --accept-package-agreements --accept-source-agreements `
            --disable-interactivity --silent | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Wn "winget returned $LASTEXITCODE for $Label" }
    } elseif ($hasChoco) {
        choco install $ChocoPkg -y --no-progress | Out-Null
    } else {
        throw "No package manager available to install $Label"
    }
    Write-Ok "$Label installed"
}

Update-EnvPath
if (-not (Test-Cmd git))   { Install-Pkg 'Git.Git'              'git'          'Git' }
if (-not (Test-Cmd python)){ Install-Pkg 'Python.Python.3.12'   'python'       'Python 3.12' }
if (-not $NoNode -and -not (Test-Cmd node)){
                          Install-Pkg 'OpenJS.NodeJS.LTS'      'nodejs-lts'   'Node.js LTS'
}
Update-EnvPath

# Resolve python executable (prefer python, fallback to py launcher)
$pyExe = $null
foreach($c in @('python','py')){ if (Test-Cmd $c) { $pyExe = (Get-Command $c).Source; break } }
if (-not $pyExe) { throw "Python still not on PATH after install. Open a new shell and re-run." }
Write-Ok "Using Python: $pyExe ($(& $pyExe --version 2>&1))"

# --------------------------------------------------------------------------- #
# 2) Clone / update the repo
# --------------------------------------------------------------------------- #
if (Test-Path "$InstallDir\.git") {
    if ($Force) {
        Write-Step "-Force: removing existing $InstallDir"
        Remove-Item -Recurse -Force $InstallDir
    } else {
        Write-Step "Repo exists -> pulling latest ($Branch)"
        Push-Location $InstallDir
        git fetch --all --quiet
        git checkout $Branch --quiet 2>$null
        git pull --quiet
        Pop-Location
    }
}
if (-not (Test-Path "$InstallDir\.git")) {
    Write-Step "Cloning $RepoUrl ($Branch) -> $InstallDir"
    New-Item -ItemType Directory -Force -Path (Split-Path $InstallDir) | Out-Null
    git clone -b $Branch --quiet $RepoUrl $InstallDir
}

# --------------------------------------------------------------------------- #
# 3) Virtualenv + Python deps
# --------------------------------------------------------------------------- #
Push-Location $InstallDir
try {
    if (-not (Test-Path "$InstallDir\venv\Scripts\python.exe")) {
        Write-Step "Creating virtualenv"
        & $pyExe -m venv venv
    }
    $venvPy  = "$InstallDir\venv\Scripts\python.exe"
    $venvPip = "$InstallDir\venv\Scripts\pip.exe"

    Write-Step "Upgrading pip"
    & $venvPip install --upgrade pip --quiet
    Write-Step "Installing Python dependencies"
    & $venvPip install -r requirements.txt --quiet
    Write-Ok "Python dependencies installed"

    # 4) camoufox browser binary (try fetch, fallback to download)
    $camo = "$InstallDir\venv\Scripts\camoufox.exe"
    Write-Step "Downloading camoufox browser"
    if (Test-Path $camo) {
        & $camo fetch 2>$null
        if ($LASTEXITCODE -ne 0) { & $camo download }
    } else {
        & $venvPy -m camoufox fetch 2>$null
        if ($LASTEXITCODE -ne 0) { & $venvPy -m camoufox download }
    }
    Write-Ok "camoufox ready"
} finally {
    Pop-Location
}

# --------------------------------------------------------------------------- #
# 5) .env from template
# --------------------------------------------------------------------------- #
if (-not (Test-Path "$InstallDir\.env")) {
    if (Test-Path "$InstallDir\.env.example") {
        Write-Step "Creating .env from template"
        Copy-Item "$InstallDir\.env.example" "$InstallDir\.env"
        Write-Ok ".env created (edit it to tune THREAD/PAGE_COUNT/PORTS)"
    }
} else {
    Write-Ok ".env already exists, kept as-is"
}

# --------------------------------------------------------------------------- #
# 6) Convenience launcher run.ps1
# --------------------------------------------------------------------------- #
$runPs1 = @"
# Auto-generated: run the multi-port CAPTCHA solver launcher via venv.
Set-Location `$PSScriptRoot
`$py = "`$PSScriptRoot\venv\Scripts\python.exe"
if (-not (Test-Path `$py)) { Write-Host 'venv missing - run install.ps1 first' -ForegroundColor Red; exit 1 }
& `$py launcher.py @args
"@
Set-Content -Path "$InstallDir\run.ps1" -Value $runPs1 -Encoding UTF8
Write-Ok "Created run.ps1"

# --------------------------------------------------------------------------- #
# 7) Windows firewall
# --------------------------------------------------------------------------- #
function Get-SolverPorts {
    param([string]$EnvFile)
    $vals = @{}
    foreach($l in Get-Content $EnvFile -ErrorAction SilentlyContinue){
        if($l -match '^\s*([A-Z_]+)\s*=\s*(.+?)\s*$'){ $vals[$Matches[1]] = $Matches[2] }
    }
    $nums = [System.Collections.Generic.List[int]]::new()
    if($vals.ContainsKey('PORTS')){
        foreach($p in ($vals['PORTS'] -split ',')){
            $p = $p.Trim()
            if($p -match '^(\d+)-(\d+)$'){ for($i=[int]$Matches[1];$i -le [int]$Matches[2];$i++){ $nums.Add($i) } }
            elseif($p -match '^\d+$'){ $nums.Add([int]$p) }
        }
    }
    if($nums.Count -eq 0 -and $vals.ContainsKey('PORT_START') -and $vals.ContainsKey('PORT_COUNT')){
        $s=[int]$vals['PORT_START']; $c=[int]$vals['PORT_COUNT']
        for($i=$s;$i -lt $s+$c;$i++){ $nums.Add($i) }
    }
    if($nums.Count -eq 0 -and $vals.ContainsKey('PORT')){ $nums.Add([int]$vals['PORT']) }
    if($nums.Count -eq 0){ $nums.Add(5032) }
    return $nums.ToArray()
}

if (-not $NoFirewall) {
    try {
        $ports = Get-SolverPorts "$InstallDir\.env"
        $lo = ($ports | Measure-Object -Minimum).Minimum
        $hi = ($ports | Measure-Object -Maximum).Maximum
        $spec = if($lo -eq $hi){ "$lo" } else { "$lo-$hi" }
        Write-Step "Opening firewall ports $spec (inbound TCP)"
        Get-NetFirewallRule -DisplayName 'CaptchaSolver Ports' -ErrorAction SilentlyContinue |
            Remove-NetFirewallRule -ErrorAction SilentlyContinue
        New-NetFirewallRule -DisplayName 'CaptchaSolver Ports' `
            -Direction Inbound -Protocol TCP -LocalPort $spec `
            -Action Allow -Profile Any -Group 'CaptchaSolver' | Out-Null
        Write-Ok "Firewall ports $spec open"
    } catch {
        Write-Wn "Firewall step skipped: $($_.Exception.Message)"
    }
}

# --------------------------------------------------------------------------- #
# 8) Optional auto-start at boot (Scheduled Task)
# --------------------------------------------------------------------------- #
if ($AutoStart) {
    Write-Step "Registering Scheduled Task 'CaptchaSolver' (AtStartup)"
    $action   = New-ScheduledTaskAction -Execute 'powershell.exe' `
                -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$InstallDir\run.ps1`""
    $trigger  = New-ScheduledTaskTrigger -AtStartup
    $principal= New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest -LogonType ServiceAccount
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
                -ExecutionTimeLimit ([TimeSpan]::Zero)
    Unregister-ScheduledTask -TaskName 'CaptchaSolver' -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName 'CaptchaSolver' -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Force | Out-Null
    Write-Ok "Auto-start enabled at boot"
}

# --------------------------------------------------------------------------- #
# Done
# --------------------------------------------------------------------------- #
$bar = '=' * 64
Write-Host ""
Write-Host $bar -ForegroundColor Green
Write-Host "  CAPTCHA solver installed at: $InstallDir" -ForegroundColor Green
Write-Host $bar -ForegroundColor Green
Write-Host "  Start now:        $InstallDir\run.ps1"
Write-Host "  Start (admin):    Start-Process powershell -Verb RunAs -ArgumentList '-File','$InstallDir\run.ps1'"
if ($AutoStart) {
    Write-Host "  Auto-start:       enabled (Scheduled Task 'CaptchaSolver')"
    Write-Host "  Manage task:      Get-ScheduledTask -TaskName 'CaptchaSolver'"
}
Write-Host "  Health check:     http://localhost:5032/health"
Write-Host "  Edit config:      notepad $InstallDir\.env"
Write-Host $bar -ForegroundColor Green
Write-Host ""
