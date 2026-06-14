#requires -Version 5.1
<# Run the multi-port CAPTCHA solver launcher using the local venv. #>
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Remaining)
Set-Location $PSScriptRoot
$py = "$PSScriptRoot\venv\Scripts\python.exe"
if (-not (Test-Path $py)) {
    Write-Host "venv not found. Run install.ps1 first." -ForegroundColor Red
    exit 1
}
Write-Host "Starting CAPTCHA solver launcher..." -ForegroundColor Cyan
& $py launcher.py @Remaining
