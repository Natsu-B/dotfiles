# PowerShell wrapper smoke test. Runs on windows-latest, no real WSL required.
$ErrorActionPreference = 'Stop'
$launcher = Join-Path (Split-Path -Parent $PSScriptRoot) 'windows/MacDataSync.ps1'
$script:calls = @()
$script:opened = @()

function global:wsl.exe {
    $script:calls += ,@($args)
    $global:LASTEXITCODE = 0
    if (@($args) -contains '--windows-path') {
        '\\wsl.localhost\Ubuntu\home\demo\work'
    }
}

function global:Start-Process {
    param([string]$FilePath, [string[]]$ArgumentList)
    $script:opened += [pscustomobject]@{ FilePath = $FilePath; ArgumentList = $ArgumentList }
}

function Assert-Test {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

& $launcher -Distribution Ubuntu start 'notes/日本語 file.txt'
Assert-Test ($script:calls.Count -eq 1) 'Expected one WSL launch.'
$call = $script:calls[0]
Assert-Test ($call -contains '/usr/local/bin/mac-data-sync-wsl') 'Fixed entrypoint missing.'
Assert-Test ($call[-2] -eq 'start') 'Start command was not passed.'
Assert-Test ($call[-1] -eq 'notes/日本語 file.txt') 'Unicode filename lost or split.'

& $launcher -Distribution Ubuntu -Daemon
Assert-Test ($script:calls.Count -eq 2) 'Daemon not dispatched.'
Assert-Test ($script:calls[1][-1] -eq '--daemon') 'Daemon argument missing.'

& $launcher -Distribution Ubuntu -OpenWork
Assert-Test ($script:calls.Count -eq 3) 'OpenWork did not call WSL.'
Assert-Test ($script:calls[2][-1] -eq '--windows-path') 'OpenWork entrypoint missing.'
Assert-Test ($script:opened.Count -eq 1) 'Explorer was not requested.'
Assert-Test ($script:opened[0].FilePath -eq 'explorer.exe') 'Unexpected Explorer process.'

Write-Host 'Windows PowerShell wrapper mock tests PASS'
