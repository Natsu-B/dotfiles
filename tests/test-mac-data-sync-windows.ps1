# PowerShell wrapper smoke test. Runs on windows-latest, no real WSL required.
$ErrorActionPreference = 'Stop'
$launcher = Join-Path (Split-Path -Parent $PSScriptRoot) 'windows/MacDataSync.ps1'
$global:WSLCalls = @()
$global:Opened = @()

function global:wsl.exe {
    $global:WSLCalls += ,@($args)
    $global:LASTEXITCODE = 0
    if (@($args) -contains '--windows-path') {
        '\\wsl.localhost\Ubuntu\home\demo\work'
    }
}

function global:Start-Process {
    param([string]$FilePath, [string[]]$ArgumentList)
    $global:Opened += [pscustomobject]@{ FilePath = $FilePath; ArgumentList = $ArgumentList }
}

function Assert-Test {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

& $launcher -Distribution Ubuntu start 'notes/日本語 file.txt'
Assert-Test ($global:WSLCalls.Count -eq 1) 'Expected one WSL launch.'
$call = $global:WSLCalls[0]
Assert-Test ($call -contains '/usr/local/bin/mac-data-sync-wsl') 'Fixed entrypoint missing.'
Assert-Test ($call[-2] -eq 'start') 'Start command was not passed.'
Assert-Test ($call[-1] -eq 'notes/日本語 file.txt') 'Unicode filename lost or split.'

& $launcher -Distribution Ubuntu -Daemon
Assert-Test ($global:WSLCalls.Count -eq 2) 'Daemon not dispatched.'
Assert-Test ($global:WSLCalls[1][-1] -eq '--daemon') 'Daemon argument missing.'

& $launcher -Distribution Ubuntu -OpenWork
Assert-Test ($global:WSLCalls.Count -eq 3) 'OpenWork did not call WSL.'
Assert-Test ($global:WSLCalls[2][-1] -eq '--windows-path') 'OpenWork entrypoint missing.'
Assert-Test ($global:Opened.Count -eq 1) 'Explorer was not requested.'
Assert-Test ($global:Opened[0].FilePath -eq 'explorer.exe') 'Unexpected Explorer process.'

Write-Host 'Windows PowerShell wrapper mock tests PASS'
