[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$destination=Join-Path $env:ProgramData 'SecureFinanceERP/UC13'
$workerIdentity=$env:COMPUTERNAME+'\sf_backup_runner'
if(-not (Test-Path -LiteralPath (Join-Path $destination 'run.cjs'))){throw 'Protected runtime missing.'}
$scheduler=New-Object -ComObject 'Schedule.Service'
$scheduler.Connect()
$folder=$scheduler.GetFolder('\')
$existing=$null
try {$existing=$folder.GetTask('SecureFinance-UC13')} catch {if($_.Exception.HResult -ne -2147024894){throw}}
if($null -ne $existing){throw 'Task already exists; do not replace it.'}
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
$action=$definition.Actions.Create(0)
$action.Path=(Get-Command node.exe).Source
$action.Arguments='"'+(Join-Path $destination 'run.cjs')+'"'
$action.WorkingDirectory=$destination
$folder.RegisterTaskDefinition('SecureFinance-UC13',$definition,2,$workerIdentity,$null,2) | Out-Null
Write-Output 'SecureFinance-UC13 registered DISABLED through Windows Task Scheduler COM API (S4U, Limited, IgnoreNew).'
