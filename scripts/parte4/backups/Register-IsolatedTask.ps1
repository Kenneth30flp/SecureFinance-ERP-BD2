[CmdletBinding()]
param(
 [PSCredential]$WorkerCredential,
 [string]$WorkerAccount='sf_backup_runner',
 [string]$NodePath=(Join-Path $env:ProgramFiles 'nodejs/node.exe')
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Task-Safety.ps1')
$destination=Join-Path $env:ProgramData 'SecureFinanceERP/UC13'
$workerIdentity=$env:COMPUTERNAME+'\'+$WorkerAccount
if(-not (Test-Path -LiteralPath (Join-Path $destination 'run.cjs'))){throw 'Protected runtime missing.'}
$scheduler=New-Object -ComObject 'Schedule.Service'
$scheduler.Connect()
$folder=$scheduler.GetFolder('\')
$existing=$null
try {$existing=$folder.GetTask('SecureFinance-UC13')} catch {if($_.Exception.HResult -ne -2147024894){throw}}
if($null -ne $existing){throw 'Task already exists; do not replace it.'}
if($null -eq $WorkerCredential){throw 'S4U registration for another account requires its credential ONCE. Supply WorkerCredential securely in memory; do not reset an existing password or pass it on the command line.'}
$worker=Get-LocalUser -Name $WorkerAccount
if(-not $worker.Enabled){throw 'Worker account is disabled.'}
$credentialSid=([Security.Principal.NTAccount]::new($WorkerCredential.UserName)).Translate([Security.Principal.SecurityIdentifier]).Value
if($credentialSid -ne $worker.SID.Value){throw 'Credential and local worker SID differ.'}
if((Get-LocalGroupMember -SID 'S-1-5-32-544').SID.Value -contains $worker.SID.Value){throw 'Worker must be a standard account.'}
$definition=$scheduler.NewTask(0)
$definition.RegistrationInfo.Description='SecureFinance UC13 isolated queue worker. Automatic backup policy is independently controlled in SQL.'
$definition.Principal.UserId=$workerIdentity
$definition.Principal.LogonType=2
$definition.Principal.RunLevel=0
$definition.Settings.Enabled=$false
$definition.Settings.MultipleInstances=2
$definition.Settings.StartWhenAvailable=$true
$definition.Settings.ExecutionTimeLimit='PT12H'
$trigger=$definition.Triggers.Create(1)
$trigger.StartBoundary=(Get-Date).AddMinutes(2).ToString('s')
$trigger.Repetition.Interval='PT1M'
$trigger.Enabled=$false
$action=$definition.Actions.Create(0)
$node=Get-Item -LiteralPath $NodePath -ErrorAction Stop
if($node.PSIsContainer -or $node.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Pinned Node executable must be an ordinary file.'}
$action.Path=[IO.Path]::GetFullPath($NodePath)
$action.Arguments='"'+(Join-Path $destination 'run.cjs')+'"'
$action.WorkingDirectory=$destination
$registrationPassword=$null
try {
 $registrationPassword=$WorkerCredential.GetNetworkCredential().Password
 # A NEW task only: Administrators owner; worker gets read/execute, never definition write.
 # CREATE | DONT_ADD_PRINCIPAL_ACE. Existing tasks are rejected above, never resecured.
 $security='O:BAG:BAD:P(A;;FA;;;SY)(A;;FA;;;BA)(A;;GRGX;;;'+$worker.SID.Value+')'
 $folder.RegisterTaskDefinition('SecureFinance-UC13',$definition,18,$workerIdentity,$registrationPassword,2,$security) | Out-Null
} finally {$registrationPassword=$null}
Write-Output 'SecureFinance-UC13 registered DISABLED through Windows Task Scheduler COM API (S4U, Limited, IgnoreNew).'
