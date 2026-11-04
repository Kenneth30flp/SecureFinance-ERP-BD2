[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$operatorIdentity=[Security.Principal.WindowsIdentity]::GetCurrent()
if(-not ([Security.Principal.WindowsPrincipal]::new($operatorIdentity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Windows elevation is required to create a standard worker identity and protect its secrets.'}
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$destination=Join-Path $env:ProgramData 'SecureFinanceERP/UC13'
$account='sf_backup_runner'
if(Test-Path -LiteralPath $destination){throw 'Existing production runtime: inspect before retry; never replace secrets.'}
if(Get-LocalUser -Name $account -ErrorAction SilentlyContinue){throw 'Existing worker identity: inspect before reuse; never change its password.'}
if(Get-ScheduledTask -TaskName 'SecureFinance-UC13' -ErrorAction SilentlyContinue){throw 'Existing worker task: inspect before changing it.'}
$random=[Security.Cryptography.RandomNumberGenerator]::Create()
$bytes=New-Object byte[] 48
$random.GetBytes($bytes)
$newPassword=ConvertTo-SecureString ([Convert]::ToBase64String($bytes)+'aA1!') -AsPlainText -Force
New-LocalUser -Name $account -Password $newPassword -Description 'SecureFinance UC13 dedicated standard worker' -AccountNeverExpires | Out-Null
Add-LocalGroupMember -SID 'S-1-5-32-545' -Member $account
$newPassword=$null
$workerIdentity=$env:COMPUTERNAME+'\'+$account
New-Item -Path $destination -ItemType Directory | Out-Null
& icacls.exe $destination /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' ($workerIdentity+':(OI)(CI)RX') | Out-Null
if($LASTEXITCODE -ne 0){throw 'Failed to isolate runtime ACL.'}
Push-Location $repo
try {
 & node.exe scripts/parte4/backups/integration.cjs deploy
 if($LASTEXITCODE -ne 0){throw 'Deployment did not pass; inspect .data/p4-production-results.json. Automatic policy remains disabled.'}
 $logs=Join-Path $destination 'logs'
 & icacls.exe $logs /grant:r ($workerIdentity+':(OI)(CI)M') | Out-Null
 if($LASTEXITCODE -ne 0){throw 'Failed to grant worker log access.'}
 & icacls.exe $destination /setowner '*S-1-5-18' /T /C | Out-Null
 if($LASTEXITCODE -ne 0){throw 'Failed to fix protected runtime ownership.'}
 & (Join-Path $PSScriptRoot 'Register-IsolatedTask.ps1')
 Write-Output 'Production SQL installed; task registered DISABLED. Verify worker identity and task execution before enabling its queue processing. SQL automatic schedule remains DISABLED.'
} finally {Pop-Location}
