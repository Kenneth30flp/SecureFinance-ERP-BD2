[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$destination=Join-Path $env:ProgramData 'SecureFinanceERP/UC13'
$workerIdentity=$env:COMPUTERNAME+'\sf_backup_runner'
$report=[ordered]@{AtUTC=[DateTime]::UtcNow.ToString('o');AutomaticPolicy='DISABLED';Task='SecureFinance-UC13';WindowsIdentity=$workerIdentity;Checks=@()}
$effectiveIdentity=[Security.Principal.WindowsIdentity]::GetCurrent()
$report.Operator=$effectiveIdentity.Name
$report.Elevated=([Security.Principal.WindowsPrincipal]::new($effectiveIdentity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$reportFile=Join-Path $repo '.data/p4-task-results.json'
try {
 & sqlcmd.exe -S localhost -E -N -C -b -d SecureFinanceERP -Q "SET NOCOUNT ON;IF DB_NAME()<>'SecureFinanceERP' OR CONVERT(nvarchar(128),SERVERPROPERTY('ServerName'))<>'9U8ICS2VLMRUE' THROW 58010,'Wrong target',1;IF NOT EXISTS(SELECT 1 FROM dbo.BackupsSchedule WHERE Id=1 AND Enabled=0) THROW 58010,'Automatic policy must be disabled',1;"
 if($LASTEXITCODE -ne 0){throw 'Automatic policy/target guard failed.'}
 $identity=Get-LocalUser -Name sf_backup_runner
 if(-not $identity.Enabled){throw 'Worker Windows account disabled.'}
 $administrators=Get-LocalGroupMember -SID 'S-1-5-32-544'
 if($administrators.SID.Value -contains $identity.SID.Value){throw 'Worker must not be Windows administrator.'}
 & icacls.exe $destination /setowner '*S-1-5-18' /T /C | Out-Null
 if($LASTEXITCODE -ne 0){throw 'Failed to fix protected runtime ownership.'}
 $secretAcl=Get-Acl -LiteralPath (Join-Path $destination 'backups.env')
 $allowed=@('S-1-5-18','S-1-5-32-544',$identity.SID.Value)
 foreach($entry in $secretAcl.Access){if($entry.AccessControlType -eq 'Allow' -and $allowed -notcontains $entry.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value){throw 'Unexpected secret access principal.'}}
 $report.Checks+='Standard dedicated Windows identity; protected secret ACL and SYSTEM ownership'
 if(-not (Get-ScheduledTask -TaskName SecureFinance-UC13 -ErrorAction SilentlyContinue)){& (Join-Path $PSScriptRoot 'Register-IsolatedTask.ps1')}
 $task=Get-ScheduledTask -TaskName SecureFinance-UC13
 if($task.Principal.UserId -ne $workerIdentity -or $task.Principal.RunLevel -ne 'Limited' -or $task.Principal.LogonType -ne 'S4U'){throw 'Unexpected task identity or privileges.'}
 $last=(Get-ScheduledTaskInfo -TaskName SecureFinance-UC13).LastRunTime
 Enable-ScheduledTask -TaskName SecureFinance-UC13 | Out-Null
 Start-ScheduledTask -TaskName SecureFinance-UC13
 $finished=$false
 for($attempt=0;$attempt -lt 45;$attempt++){
  Start-Sleep -Seconds 1
  $info=Get-ScheduledTaskInfo -TaskName SecureFinance-UC13
  $current=Get-ScheduledTask -TaskName SecureFinance-UC13
  if($info.LastRunTime -gt $last -and $current.State -ne 'Running'){$finished=$true;break}
 }
 if(-not $finished -or $info.LastTaskResult -ne 0){throw ('Worker task failed; LastTaskResult='+$info.LastTaskResult)}
 $line=Get-Content -LiteralPath (Join-Path $destination 'logs/worker.jsonl') -Tail 1 | ConvertFrom-Json
 if($line.identity -ne 'sf_backup_runner' -or $null -eq $line.result){throw 'Effective worker identity or completion missing.'}
 $report.Checks+='Real Task Scheduler execution with S4U, Limited, independent runtime, effective sf_backup_runner and exit 0'
 $report.LastRunTime=$info.LastRunTime.ToString('o');$report.LastTaskResult=$info.LastTaskResult;$report.Worker=$line
 $report.QueueProcessing='ENABLED; automatic backup policy remains DISABLED'
 $report.Result='PASS'
} catch {
 Disable-ScheduledTask -TaskName SecureFinance-UC13 -ErrorAction SilentlyContinue | Out-Null
 $report.Result='FAIL';$report.Error=$_.Exception.Message;$report.ErrorStack=$_.ScriptStackTrace
 throw
} finally {$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFile -Encoding UTF8}
