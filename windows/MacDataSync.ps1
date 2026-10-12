#Requires -Version 5.1
<#
.SYNOPSIS
  Run the Mac Data Sync English TUI from Windows using WSL2.
.DESCRIPTION
  The Mac remains the archive at ~/data; working copies live in WSL ~/work.
  -OpenWork opens the working directory in Windows File Explorer.
  -Daemon runs a foreground keeper for Windows login autostart.
.EXAMPLE
  .\MacDataSync.ps1
.EXAMPLE
  .\MacDataSync.ps1 -Distribution Ubuntu start project-a
.EXAMPLE
  .\MacDataSync.ps1 -OpenWork
#>
[CmdletBinding(DefaultParameterSetName = 'Cli')]
param(
    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]*$')]
    [string]$Distribution = 'Ubuntu',

    [Parameter(ParameterSetName = 'Open')]
    [switch]$OpenWork,

    [Parameter(ParameterSetName = 'Daemon')]
    [switch]$Daemon,

    [Parameter(ParameterSetName = 'Cli', ValueFromRemainingArguments = $true)]
    [string[]]$CliArgs
)

$ErrorActionPreference = 'Stop'

$wsl = Get-Command 'wsl.exe' -ErrorAction SilentlyContinue
if ($null -eq $wsl) {
    throw 'WSL is not installed. Run "wsl --install -d Ubuntu" in an elevated PowerShell terminal.'
}

if ($OpenWork) {
    $path = & $wsl.Source --distribution $Distribution --exec /usr/local/bin/mac-data-sync-wsl --windows-path
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($path | Out-String))) {
        throw "Could not open WSL directory for distribution '$Distribution'."
    }
    $uncPath = ($path | Select-Object -First 1).Trim()
    Start-Process -FilePath 'explorer.exe' -ArgumentList @($uncPath)
    exit 0
}

if ($Daemon) {
    # Foreground on purpose: the Windows Startup shortcut keeps WSL alive.
    & $wsl.Source --distribution $Distribution --exec /usr/local/bin/mac-data-sync-wsl --daemon
    exit $LASTEXITCODE
}

# Run the installed WSL entrypoint directly. PowerShell never interpolates
# file names into shell source; each argument keeps its own boundary.
& $wsl.Source --distribution $Distribution --exec /usr/local/bin/mac-data-sync-wsl @CliArgs
exit $LASTEXITCODE
