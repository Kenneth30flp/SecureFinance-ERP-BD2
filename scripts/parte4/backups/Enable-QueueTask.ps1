[CmdletBinding()]
param([string]$WorkerAccount='',[string]$NodePath=(Join-Path $env:ProgramFiles 'nodejs/node.exe'))
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$destination=Join-Path $env:ProgramData 'SecureFinanceERP/UC13'
$reportFile=Join-Path $repo '.data/p4-task-timer.json'
$report=[ordered]@{SchemaVersion=2;AtUTC=[DateTime]::UtcNow.ToString('o');Server='9U8ICS2VLMRUE';Database='SecureFinanceERP';AutomaticBackupPolicy='DISABLED';QueueProcessing='PENDING';Task='SecureFinance-UC13';Checks=@()}
. (Join-Path $PSScriptRoot 'Task-Safety.ps1')
if(-not ('SecureFinance.WorkerAccess' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'Windows-Inspection.cs')}
$mutation=$null;$credential=$null;$token=$null;$success=$false
try {
 $operator=[Security.Principal.WindowsIdentity]::GetCurrent()
 if(-not ([Security.Principal.WindowsPrincipal]::new($operator)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Elevation required.'}
 $proof=Get-Content -LiteralPath (Join-Path $repo '.data/p4-task-operational.json') -Raw -Encoding UTF8 | ConvertFrom-Json
 $capacity=Get-Content -LiteralPath (Join-Path $repo '.data/p4-capacity-review.json') -Raw -Encoding UTF8 | ConvertFrom-Json
 Assert-Uc13FreshReport $proof Result '' ([DateTime]::UtcNow) 30
 Assert-Uc13FreshReport $capacity Result '' ([DateTime]::UtcNow) 5
 if($proof.LastTaskResult -ne 0 -or -not $capacity.observedCapacityFitsEstimate -or $capacity.status -ne 'SUFFICIENT' -or $capacity.policy.Enabled -ne $false){throw 'Fresh operational and sufficient capacity reports required; SQL automatic policy must stay disabled.'}
 $report.DatabaseGuid=Get-Uc13DatabaseIdentity
 if($report.DatabaseGuid -ne $proof.DatabaseGuid -or $report.DatabaseGuid -ne $capacity.DatabaseGuid){throw 'Evidence database GUID differs from current database.'}
 $service=New-Object -ComObject 'Schedule.Service';$service.Connect();$folder=$service.GetFolder('\');$task=$folder.GetTask('SecureFinance-UC13');$definition=$task.Definition
 $snapshot=Get-Uc13TaskSnapshot $task;$worker=Resolve-Uc13Worker $snapshot $WorkerAccount;$owners=Get-Uc13Owners
 Assert-Uc13Task $snapshot $worker.SID.Value $owners $destination $NodePath
 Assert-Uc13FreshReport $proof Result $worker.SID.Value ([DateTime]::UtcNow) 30
 if((Get-Uc13XmlDigest $snapshot.Xml -IgnoreEnabled) -ne $proof.TaskDigest -or $snapshot.Security -cne $proof.TaskSecurity){throw 'Task definition or security changed since security verification.'}
 $custody=Join-Path $destination 'task-registration.credential.clixml';$acl=Get-Acl -LiteralPath $custody
 if($owners -notcontains (Resolve-Uc13Sid $acl.Owner)){throw 'Untrusted credential owner.'}
 foreach($rule in $acl.Access){if($rule.AccessControlType -eq 'Allow' -and @('S-1-5-18','S-1-5-32-544') -notcontains (Resolve-Uc13Sid $rule.IdentityReference.Value)){throw 'Credential is not private to administrators/SYSTEM.'}}
 $credential=Import-Clixml -LiteralPath $custody;Assert-Uc13Credential $credential $worker.SID.Value
 $token=[SecureFinance.WorkerAccess]::new($credential.UserName,$credential.Password)
 if($token.Sid -ne $worker.SID.Value){throw 'Actual token SID mismatch.'}
 $report.Security=Get-Uc13SecurityProof $token $destination $NodePath $owners
 Assert-Uc13CurrentCapacity $capacity @(Get-Uc13AuthorizedRoots) {param($root) [SecureFinance.VolumeInspection]::Read($root)}
 $report.SID=$worker.SID.Value
 $current=Get-Uc13TaskSnapshot ($folder.GetTask('SecureFinance-UC13'))
 if($current.Security -cne $snapshot.Security -or (Get-Uc13XmlDigest $current.Xml) -ne (Get-Uc13XmlDigest $snapshot.Xml)){throw 'Task changed during preflight; no update authorized.'}
 $mutation=New-Uc13Mutation $snapshot
 $previous=$task.LastRunTime;$started=[DateTime]::UtcNow
 $definition.Settings.Enabled=$true
 $definition.Triggers.Item(1).Enabled=$true
 $definition.Triggers.Item(1).StartBoundary=(Get-Date).AddSeconds(20).ToString('s')
 $mutation.ExpectedXml=$definition.XmlText;$mutation.ExpectedEnabled=$true;$mutation.Attempted=$true
 $registered=Set-Uc13TaskXml $folder $definition.XmlText $credential $snapshot.Security
 $mutation.ExpectedXml=$registered.Xml
 $report.Checks+='Existing task updated with same S4U/Limited principal; one-minute queue trigger enabled; SQL automatic backups remain disabled'
 $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportFile -Encoding UTF8
 $finished=$false
 for($attempt=0;$attempt -lt 70;$attempt++){Start-Sleep -Seconds 1;$task=$folder.GetTask('SecureFinance-UC13');if($task.LastRunTime -gt $previous -and $task.State -ne 4){$finished=$true;break}}
 if(-not $finished -or $task.LastTaskResult -ne 0){throw ('Timed execution failed: '+$task.LastTaskResult)}
 $line=Get-Content -LiteralPath (Join-Path $destination 'logs/worker.jsonl') -Tail 1 -Encoding UTF8 | ConvertFrom-Json
 Assert-Uc13WorkerLog $line $worker.Name $started ([DateTime]::UtcNow)
 $report.TimerEventXml=Assert-Uc13TimerEvents @(Get-Uc13Events $started) $started ([DateTime]::UtcNow) $credential.UserName
 # Recheck identity/definition and SQL policy after the execution, before claiming success.
 $after=Get-Uc13TaskSnapshot ($folder.GetTask('SecureFinance-UC13'));Assert-Uc13Task $after $worker.SID.Value $owners $destination $NodePath
 if($after.Security -cne $snapshot.Security -or (Get-Uc13XmlDigest $after.Xml) -ne (Get-Uc13XmlDigest $mutation.ExpectedXml)){throw 'Concurrent task changes detected.'}
 if((Get-Uc13DatabaseIdentity) -ne $report.DatabaseGuid){throw 'SQL identity changed during verification.'}
 Assert-Uc13CurrentCapacity $capacity @(Get-Uc13AuthorizedRoots) {param($root) [SecureFinance.VolumeInspection]::Read($root)}
 $report.Checks+='Fresh timer/completion events share instance, time interval and expected user; worker log is fresh'
 $report.LastTaskResult=$task.LastTaskResult;$report.Worker=$line;$report.TaskXml=$task.Xml;$report.QueueProcessing='ENABLED';$report.Result='PASS'
 $report.AtUTC=[DateTime]::UtcNow.ToString('o');$success=$true
} catch {
 $report.Result='FAIL';$report.Error=$_.Exception.Message;$report.ErrorStack=$_.ScriptStackTrace
 throw
} finally {
 try{if(-not $success){Restore-Uc13Mutation $mutation {Get-Uc13TaskSnapshot ($folder.GetTask('SecureFinance-UC13'))} {param($enabled) $folder.GetTask('SecureFinance-UC13').Enabled=$enabled} {param($xml,$enabled) Set-Uc13TaskXml $folder $xml $credential $mutation.Before.Security | Out-Null}}}
 catch{$report.RestorationError=$_.Exception.Message;$report.Result='FAIL';throw}
 finally{if($token){$token.Dispose()};$credential=$null;$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFile -Encoding UTF8}
}
