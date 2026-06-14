#requires -Version 5.1
<#
.SYNOPSIS
    One-shot developer environment installer for a fresh Windows VPS.
    Installs only the dev tools / frameworks you actually need - NOT any
    specific project. Uses winget (preferred), auto-falls back to Chocolatey.

.EXAMPLE
    # Run from an ADMIN PowerShell:
    Set-ExecutionPolicy Bypass -Scope Process -Force
    iwr -UseBasicParsing https://raw.githubusercontent.com/muhrifqie/solver/main/install.ps1 | iex

    # Pick categories:
    & .\install.ps1 -Core -Web -Tunnel -Utils
    & .\install.ps1 -All
    & .\install.ps1 -Tools go,rust,nginx
    & .\install.ps1 -OpenPorts 80,443,8080 -SetupProfile

.NOTES
    Categories:
      Core      : git, python, node            (default if nothing is given)
      Lang      : go, rust
      Container : docker
      Web       : nginx, caddy
      Tunnel    : cloudflared
      DB        : redis, postgres
      Editor    : vscode
      Utils     : jq, make, vim, openssl, 7zip, wget
      Shell     : pwsh (PowerShell 7), Windows Terminal
#>
[CmdletBinding()]
param(
    [switch]$Core,
    [switch]$Lang,
    [switch]$Container,
    [switch]$Web,
    [switch]$Tunnel,
    [switch]$DB,
    [switch]$Editor,
    [switch]$Utils,
    [switch]$Shell,
    [switch]$All,           # install everything
    [string[]]$Tools,       # explicit tool names from the catalog
    [int[]]$OpenPorts,      # e.g. -OpenPorts 80,443,8080
    [switch]$SetupProfile,  # add handy aliases/functions to $PROFILE
    [switch]$List,          # just list the catalog and exit
    [switch]$Force          # reinstall even if a tool is present
)

$InstallerUrl = 'https://raw.githubusercontent.com/muhrifqie/solver/main/install.ps1'

# ---------------------------------------------------------------- helpers ---- #
function Write-Step($m){ Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok($m)  { Write-Host "[OK]  $m" -ForegroundColor Green }
function Write-Wn($m)  { Write-Host "[!!]  $m" -ForegroundColor Yellow }
function Write-Err($m) { Write-Host "[X]   $m" -ForegroundColor Red }
function Test-Cmd($n)  { return [bool](Get-Command $n -ErrorAction SilentlyContinue) }

function Update-EnvPath {
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path','User')
}

# ---------------------------------------------------------------- elevate ---- #
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Wn "Not Administrator - re-launching elevated..."
    if ($PSCommandPath -and (Test-Path $PSCommandPath)) {
        $a = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
        foreach($k in 'Core','Lang','Container','Web','Tunnel','DB','Editor','Utils','Shell','All','SetupProfile','Force','List'){
            if($PSBoundParameters[$k]){ $a += "-$k" }
        }
        if($Tools)     { $a += '-Tools',($Tools -join ',') }
        if($OpenPorts) { $a += '-OpenPorts',($OpenPorts -join ',') }
        Start-Process powershell.exe -Verb RunAs -ArgumentList $a
    } else {
        $cmd = "Set-ExecutionPolicy Bypass -Scope Process -Force; iwr -UseBasicParsing '$InstallerUrl' | iex"
        Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-Command',$cmd
    }
    exit
}
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- catalog ---- #
# LogicalName -> WingetId, ChocoPkg, VerifyCmd, Category
$Catalog = [ordered]@{
    git         = @{ Winget='Git.Git';                       Choco='git';                        Verify='git';          Cat='core' }
    python      = @{ Winget='Python.Python.3.12';            Choco='python3';                    Verify='python';       Cat='core' }
    node        = @{ Winget='OpenJS.NodeJS.LTS';             Choco='nodejs-lts';                 Verify='node';         Cat='core' }
    go          = @{ Winget='GoLang.Go';                     Choco='golang';                     Verify='go';           Cat='lang' }
    rust        = @{ Winget='Rustlang.Rustup';               Choco='rustup.install';             Verify='rustc';        Cat='lang' }
    docker      = @{ Winget='Docker.DockerDesktop';          Choco='docker-desktop';             Verify='docker';       Cat='container' }
    nginx       = @{ Winget='';                              Choco='nginx';                      Verify='nginx';        Cat='web' }
    caddy       = @{ Winget='CaddyServer.Caddy';             Choco='caddy';                      Verify='caddy';        Cat='web' }
    cloudflared = @{ Winget='Cloudflare.cloudflared';        Choco='cloudflared';                Verify='cloudflared';  Cat='tunnel' }
    redis       = @{ Winget='Redis.Redis';                   Choco='redis-64';                   Verify='redis-cli';    Cat='db' }
    postgres    = @{ Winget='PostgreSQL.PostgreSQL.16';      Choco='postgresql';                 Verify='psql';         Cat='db' }
    vscode      = @{ Winget='Microsoft.VisualStudioCode';    Choco='vscode';                     Verify='code';         Cat='editor' }
    jq          = @{ Winget='jqlang.jq';                     Choco='jq';                         Verify='jq';           Cat='utils' }
    make        = @{ Winget='GnuWin32.Make';                 Choco='make';                       Verify='make';         Cat='utils' }
    vim         = @{ Winget='nvim.neovim';                   Choco='neovim';                     Verify='nvim';         Cat='utils' }
    openssl     = @{ Winget='';                              Choco='openssl.light';              Verify='openssl';      Cat='utils' }
    sevenzip    = @{ Winget='7zip.7zip';                     Choco='7zip';                       Verify='7z';           Cat='utils' }
    wget        = @{ Winget='JernejSimoncic.Wget';           Choco='wget';                       Verify='wget';         Cat='utils' }
    pwsh        = @{ Winget='Microsoft.PowerShell';          Choco='powershell-core';            Verify='pwsh';         Cat='shell' }
    terminal    = @{ Winget='Microsoft.WindowsTerminal';     Choco='microsoft-windows-terminal'; Verify='wt';           Cat='shell' }
}

# Show catalog and exit
if ($List) {
    Write-Host "Available tools (name -> category):" -ForegroundColor Cyan
    $Catalog.GetEnumerator() | ForEach-Object {
        Write-Host ("  {0,-12} {1}" -f $_.Key, $_.Value.Cat)
    }
    Write-Host "`nUsage: -Core -Web -Tunnel  |  -All  |  -Tools go,rust,nginx`n"
    exit
}

# ---------------------------------------------------------------- resolve ---- #
if ($All) { $Core=$Lang=$Container=$Web=$Tunnel=$DB=$Editor=$Utils=$Shell=$true }
$wantedCats = @()
foreach($pair in @(
    @($Core,'core'),@($Lang,'lang'),@($Container,'container'),@($Web,'web'),
    @($Tunnel,'tunnel'),@($DB,'db'),@($Editor,'editor'),@($Utils,'utils'),@($Shell,'shell'))){
    if($pair[0]){ $wantedCats += $pair[1] }
}
if((-not $wantedCats) -and (-not $Tools)){ $wantedCats = @('core') }   # default = core

$want = New-Object System.Collections.Generic.List[string]
foreach($kv in $Catalog.GetEnumerator()){
    if($wantedCats -contains $kv.Value.Cat){ $want.Add($kv.Key) }
}
foreach($t in ($Tools | Where-Object { $_ })){
    $t = "$t".Trim().ToLower()
    if($Catalog.Contains($t)){ $want.Add($t) } else { Write-Wn "Unknown tool: $t (use -List to see catalog)" }
}
$want = $want | Sort-Object -Unique

Write-Step "Selected tools: $($want -join ', ')"

# --------------------------------------------------- ensure package mgr ---- #
Update-EnvPath
$hasWinget = Test-Cmd winget
$hasChoco  = Test-Cmd choco
if (-not $hasWinget -and -not $hasChoco) {
    Write-Step "Installing Chocolatey (no winget/choco found)"
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    $env:ChocolateyInstall = "$env:ProgramData\chocolatey"
    Update-EnvPath
    $hasChoco = Test-Cmd choco
    if (-not $hasChoco) { throw "Chocolatey install failed" }
    Write-Ok "Chocolatey installed"
}
Update-EnvPath
Write-Ok ("Package manager: winget={0} choco={1}" -f $hasWinget, $hasChoco)

# --------------------------------------------------------- install loop ---- #
function Install-One {
    param([string]$Name)
    $t   = $Catalog[$Name]
    $cmd = $t.Verify
    Update-EnvPath
    if ((Test-Cmd $cmd) -and -not $Force) { Write-Ok ("$Name already present ('$cmd') - skipped"); return $true }

    Write-Step "Installing $Name"
    $ok = $false
    if ($hasWinget -and $t.Winget) {
        winget install --id $t.Winget -e --source winget `
            --accept-package-agreements --accept-source-agreements `
            --disable-interactivity --silent 2>$null | Out-Null
        Update-EnvPath
        if (Test-Cmd $cmd) { $ok = $true }
    }
    if (-not $ok -and $hasChoco) {
        choco install $t.Choco -y --no-progress 2>$null | Out-Null
        Update-EnvPath
        if (Test-Cmd $cmd) { $ok = $true }
    }
    if ($ok) { Write-Ok "${Name} installed ('$cmd')" }
    else     { Write-Wn "${Name}: could not verify '$cmd' after install (may need a new shell / reboot for Docker)" }
    return $ok
}

$results = [ordered]@{}
foreach($name in $want){ $results[$name] = Install-One $name }

# ------------------------------------------------------- special hints ---- #
if ($want -contains 'docker' -and -not (Test-Cmd docker)) {
    Write-Wn "Docker Desktop needs a sign-out/reboot to finish. Start 'Docker Desktop' afterwards."
}
if ($want -contains 'pwsh' -and (Test-Cmd pwsh)) {
    Write-Ok "PowerShell 7 available - run 'pwsh' for the modern shell."
}
if ($want -contains 'cloudflared' -and (Test-Cmd cloudflared)) {
    Write-Ok "Expose any local port to the internet:  cloudflared tunnel --url http://localhost:8080"
}

# ----------------------------------------------------------- firewall ---- #
if ($OpenPorts -and $OpenPorts.Count -gt 0) {
    $ports = $OpenPorts | Sort-Object -Unique
    Write-Step "Opening firewall ports: $($ports -join ',')"
    Get-NetFirewallRule -DisplayName 'DevTools Custom Ports' -ErrorAction SilentlyContinue |
        Remove-NetFirewallRule -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName 'DevTools Custom Ports' `
        -Direction Inbound -Protocol TCP -LocalPort $ports `
        -Action Allow -Profile Any -Group 'DevTools' | Out-Null
    Write-Ok "Firewall ports opened"
}

# -------------------------------------------------------- profile setup ---- #
if ($SetupProfile) {
    Write-Step "Enhancing PowerShell profile"
    if (-not (Test-Path $PROFILE)) { New-Item -ItemType File -Path $PROFILE -Force | Out-Null }
    $marker = '# >>> devtools profile >>>'
    $content = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
    if ($content -and $content.Contains($marker)) {
        Write-Ok "Profile already enhanced"
    } else {
        $snip = @"
$marker
function ll { Get-ChildItem @args -Force | Format-Table Mode,Length,LastWriteTime,Name -AutoSize }
function which(`$n){ (Get-Command `$n -ErrorAction SilentlyContinue).Source }
function touch(`$p){ if(Test-Path `$p){ (Get-Item `$p).LastWriteTime=Get-Date }else{ New-Item -Type File `$p } }
function grep(`$p,`$f=`$input){ `$input | Select-String `$p @args }
function Get-PublicIP { (Invoke-RestMethod 'https://api.ipify.org?format=json').ip }
function Open-Port([int[]]`$Ports){
  New-NetFirewallRule -DisplayName 'DevTools Custom Ports' -Direction Inbound `
    -Protocol TCP -LocalPort `$Ports -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null
  Write-Host "Opened: `$(`$Ports -join ',')"
}
Set-Alias -Name open -Value Invoke-Item -ErrorAction SilentlyContinue
# <<< devtools profile <<<
"@
        Add-Content -Path $PROFILE -Value "`n$snip" -Encoding UTF8
        Write-Ok "Profile enhanced (ll, which, touch, grep, Get-PublicIP, Open-Port)"
    }
}

# --------------------------------------------------------------- summary ---- #
Write-Host ""
Write-Host ('=' * 64) -ForegroundColor Green
Write-Host "  Developer environment setup complete" -ForegroundColor Green
Write-Host ('=' * 64) -ForegroundColor Green
$installed = $results.GetEnumerator() | Where-Object { $_.Value } | Select-Object -ExpandProperty Key
$failed    = $results.GetEnumerator() | Where-Object { -not $_.Value } | Select-Object -ExpandProperty Key
Write-Host ("  Installed/OK : {0}" -f ($(if($installed){$installed -join ', '}else{'-'})))
Write-Host ("  Verify-fail : {0}" -f ($(if($failed){$failed -join ', '}else{'-'})))
if ($OpenPorts) { Write-Host ("  Ports opened: {0}" -f ($OpenPorts -join ',')) }
Write-Host ""
Write-Host "  Open a NEW terminal (so PATH refreshes), then try e.g.:"
Write-Host "    git --version ; python --version ; node --version ; nginx -v ; cloudflared --version"
Write-Host ('=' * 64) -ForegroundColor Green
Write-Host ""
