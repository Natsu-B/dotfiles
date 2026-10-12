#Requires -Version 5.1
<#
.SYNOPSIS
  Install the Mac Data Sync client into a WSL2 Ubuntu/Debian distribution.
.EXAMPLE
  .\Install-MacDataSync.ps1 -Distribution Ubuntu -MacHost 100.101.102.103 -MacUser alice
.EXAMPLE
  .\Install-MacDataSync.ps1 -Distribution Ubuntu -SkipStartup
#>
[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]*$')]
    [string]$Distribution = 'Ubuntu',

    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9.-]*$')]
    [string]$MacHost = '',

    [ValidatePattern('^[A-Za-z0-9_][A-Za-z0-9_.-]*$')]
    [string]$MacUser = '',

    [switch]$SkipStartup
)

$ErrorActionPreference = 'Stop'

if ([bool]$MacHost -ne [bool]$MacUser) {
    throw 'Supply both -MacHost and -MacUser, or neither (configure WSL ~/.ssh/config yourself).'
}
$wsl = Get-Command 'wsl.exe' -ErrorAction SilentlyContinue
if ($null -eq $wsl) {
    throw 'WSL is missing. Install it first with "wsl --install -d Ubuntu", then open Ubuntu once.'
}

# Check that this distro can execute shell commands as the intended user.
& $wsl.Source --distribution $Distribution --exec bash -c 'printf "WSL_READY"'
if ($LASTEXITCODE -ne 0) {
    throw "Could not launch '$Distribution'. Install or initialize it first with 'wsl --install -d $Distribution'."
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$repoWsl = & $wsl.Source --distribution $Distribution --exec wslpath -u $repoRoot
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($repoWsl | Out-String))) {
    throw "WSL could not translate the repository directory: $repoRoot"
}
$repoWsl = ($repoWsl | Select-Object -First 1).Trim()

Write-Host "Installing Mac Data Sync in WSL distribution $Distribution ..."
& $wsl.Source --distribution $Distribution --exec bash "$repoWsl/windows/setup-wsl.sh" $repoWsl $MacHost $MacUser
if ($LASTEXITCODE -ne 0) { throw "WSL setup failed with exit code $LASTEXITCODE." }

# Install the PowerShell launcher outside the git checkout, so shortcuts survive
# moving/replacing the dotfiles folder.
$installDir = Join-Path $env:LOCALAPPDATA 'MacDataSync'
New-Item -ItemType Directory -Path $installDir -Force | Out-Null
$launcher = Join-Path $installDir 'MacDataSync.ps1'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'MacDataSync.ps1') -Destination $launcher -Force

# Search "Mac Data Sync" in Start Menu, no terminal command required.
$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$wsh = New-Object -ComObject WScript.Shell
$programs = [Environment]::GetFolderPath('Programs')
$launchShortcut = $wsh.CreateShortcut((Join-Path $programs 'Mac Data Sync.lnk'))
$launchShortcut.TargetPath = $windowsPowerShell
$launchShortcut.Arguments = "-NoLogo -NoProfile -NoExit -ExecutionPolicy Bypass -File `"$launcher`" -Distribution `"$Distribution`""
$launchShortcut.WorkingDirectory = $installDir
$launchShortcut.Save()

$filesShortcut = $wsh.CreateShortcut((Join-Path $programs 'Mac Data Sync Files.lnk'))
$filesShortcut.TargetPath = $windowsPowerShell
$filesShortcut.Arguments = "-NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$launcher`" -Distribution `"$Distribution`" -OpenWork"
$filesShortcut.WorkingDirectory = $installDir
$filesShortcut.Save()

if (-not $SkipStartup) {
    # An ordinary current-user Startup shortcut. Does not need admin rights.
    # This launches a hidden, long-running WSL keeper on each Windows login.
    $startup = [Environment]::GetFolderPath('Startup')
    $shortcutPath = Join-Path $startup 'Mac Data Sync (WSL).lnk'
    $shortcut = $wsh.CreateShortcut($shortcutPath)
    $powershell = $windowsPowerShell
    $shortcut.TargetPath = $powershell
    $shortcut.Arguments = "-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$launcher`" -Distribution `"$Distribution`" -Daemon"
    $shortcut.WorkingDirectory = $installDir
    $shortcut.Save()

    # Start the keeper for this session as well, not only at the next login.
    Start-Process -FilePath $powershell -ArgumentList $shortcut.Arguments -WindowStyle Hidden
    Write-Host "Background synchronization at Windows login: enabled ($shortcutPath)"
} else {
    Write-Host 'Windows login startup was skipped. Synchronization runs while WSL is active.'
}

Write-Host ''
Write-Host 'Setup completed. Start Menu shortcuts: Mac Data Sync / Mac Data Sync Files.'
Write-Host 'Next steps:'
Write-Host "  1. In Windows WSL: wsl.exe --distribution $Distribution --exec bash -lc 'cat ~/.ssh/id_ed25519.pub'"
Write-Host '     Add that public key to the Mac account authorized_keys file.'
Write-Host '  2. Confirm the Mac has Remote Login enabled and that WSL can run: ssh mac "ls ~/data"'
Write-Host "  3. Run in PowerShell: & '$launcher'"
Write-Host "  4. Open the Windows working copies: & '$launcher' -OpenWork"
