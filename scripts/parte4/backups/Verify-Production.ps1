[CmdletBinding()]
param([string]$WorkerAccount='',[switch]$GrantBatchRight,[string]$NodePath=(Join-Path $env:ProgramFiles 'nodejs/node.exe'))
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$destination=Join-Path $env:ProgramData 'SecureFinanceERP/UC13'
$reportFile=Join-Path $repo '.data/p4-task-operational.json'
$report=[ordered]@{SchemaVersion=2;AtUTC=[DateTime]::UtcNow.ToString('o');Server='9U8ICS2VLMRUE';Database='SecureFinanceERP';Task='SecureFinance-UC13';AutomaticPolicy='DISABLED';Checks=@();Changes=@()}
. (Join-Path $PSScriptRoot 'Windows-AccountRights.ps1')
. (Join-Path $PSScriptRoot 'Task-Safety.ps1')
if(-not ('SecureFinance.WorkerAccess' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'Windows-Inspection.cs')}
$mutation=$null;$token=$null;$credential=$null
function Save {$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFile -Encoding UTF8}
function Check([string]$Label){$report.Checks+=$Label;Save}
try {
 $operatorIdentity=[Security.Principal.WindowsIdentity]::GetCurrent()
 if(-not ([Security.Principal.WindowsPrincipal]::new($operatorIdentity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Elevation required for task management and protected evidence.'}
 $report.DatabaseGuid=Get-Uc13DatabaseIdentity
 Check 'Original SQL target, automatic policy disabled and idle queue; no migrations'
 $scheduler=New-Object -ComObject 'Schedule.Service';$scheduler.Connect();$folder=$scheduler.GetFolder('\');$task=$folder.GetTask('SecureFinance-UC13')
 $snapshot=Get-Uc13TaskSnapshot $task;$identity=Resolve-Uc13Worker $snapshot $WorkerAccount;$owners=Get-Uc13Owners
 Assert-Uc13Task $snapshot $identity.SID.Value $owners $destination $NodePath
 if($snapshot.Definition.Triggers.Item(1).Enabled){throw 'Controlled verification requires a disabled trigger; existing task preserved. Arrange authorized maintenance first.'}
 $report.SID=$identity.SID.Value;$report.WindowsIdentity=[Environment]::MachineName+'\'+$identity.Name
 $report.BatchAssigneesBefore=@([SecureFinance.AccountRights]::Assignees('SeBatchLogonRight'))
 $report.DenyBatchAssignees=@([SecureFinance.AccountRights]::Assignees('SeDenyBatchLogonRight'))
 $report.RightsBefore=@([SecureFinance.AccountRights]::Read($identity.SID.Value))
 # Group-assigned batch rights are valid too; the actual batch logon below is decisive.
 # GrantBatchRight is retained for CLI compatibility, but never mutates policy here.
 $report.RightsAfter=@([SecureFinance.AccountRights]::Read($identity.SID.Value))
 $report.BatchAssigneesAfter=@([SecureFinance.AccountRights]::Assignees('SeBatchLogonRight'))
 if((@($report.RightsBefore | Sort-Object) -join '|') -cne (@($report.RightsAfter | Sort-Object) -join '|')){throw 'Account rights changed concurrently.'}
 if(@($report.BatchAssigneesBefore | Where-Object {$report.BatchAssigneesAfter -notcontains $_}).Count){throw 'Existing batch assignee was removed.'}
 if(@($report.BatchAssigneesAfter | Where-Object {$report.BatchAssigneesBefore -notcontains $_ -and $_ -ne $identity.SID.Value}).Count){throw 'Unexpected additional batch assignee.'}
 # Before importing DPAPI custody, require its owner and DACL to exclude non-administrators.
 $custody=Join-Path $destination 'task-registration.credential.clixml';$acl=Get-Acl -LiteralPath $custody
 if($owners -notcontains (Resolve-Uc13Sid $acl.Owner)){throw 'Untrusted credential owner.'}
 foreach($rule in $acl.Access){if($rule.AccessControlType -eq 'Allow' -and @('S-1-5-18','S-1-5-32-544') -notcontains (Resolve-Uc13Sid $rule.IdentityReference.Value)){throw 'Credential custody is not administrator/SYSTEM-only.'}}
 $credential=Import-Clixml -LiteralPath $custody;Assert-Uc13Credential $credential $identity.SID.Value
 $token=[SecureFinance.WorkerAccess]::new($credential.UserName,$credential.Password)
 if($token.Sid -ne $identity.SID.Value){throw 'Batch token SID differs from registered worker.'}
 if(@($report.DenyBatchAssignees | Where-Object {$token.GroupSids -contains $_}).Count){throw 'Applicable batch deny; no policy changes authorized.'}
 $report.Security=Get-Uc13SecurityProof $token $destination $NodePath $owners
 Check 'Actual batch token, group-aware effective ACL, trusted executable/runtime and unchanged rights'
 $current=Get-Uc13TaskSnapshot ($folder.GetTask('SecureFinance-UC13'))
 if($current.Security -cne $snapshot.Security -or (Get-Uc13XmlDigest $current.Xml) -ne (Get-Uc13XmlDigest $snapshot.Xml)){throw 'Task changed during preflight; existing task preserved.'}
 $mutation=New-Uc13Mutation $snapshot -EnabledOnly
 $report.TaskXmlBefore=$snapshot.Xml;$previous=$task.LastRunTime;$started=[DateTime]::UtcNow
 try {
  $mutation.ExpectedEnabled=$true;$mutation.Attempted=$true;$task.Enabled=$true;$running=$task.Run($null);$finished=$false
  for($attempt=0;$attempt -lt 50;$attempt++){Start-Sleep -Seconds 1;$task=$folder.GetTask('SecureFinance-UC13');if($task.LastRunTime -gt $previous -and $task.State -ne 4){$finished=$true;break}}
  $report.LastTaskResult=$task.LastTaskResult
  if(-not $finished -or $task.LastTaskResult -ne 0){throw ('Controlled task did not succeed; LastTaskResult='+$task.LastTaskResult)}
  $line=Get-Content -LiteralPath (Join-Path $destination 'logs/worker.jsonl') -Tail 1 -Encoding UTF8 | ConvertFrom-Json
  Assert-Uc13WorkerLog $line $identity.Name $started ([DateTime]::UtcNow)
  $report.Worker=$line;$report.LastRunTime=$task.LastRunTime.ToString('o')
 } finally {Restore-Uc13Mutation $mutation {Get-Uc13TaskSnapshot ($folder.GetTask('SecureFinance-UC13'))} {param($enabled) $folder.GetTask('SecureFinance-UC13').Enabled=$enabled} {throw 'Definition restoration not permitted in enable-only verification.'}}
 Check 'Controlled worker completed; original task state restored and confirmed'
 $report.TaskDigest=Get-Uc13XmlDigest $snapshot.Xml -IgnoreEnabled
 $report.TaskSecurity=$snapshot.Security
 $report.SchedulerEventsXml=@(Get-Uc13Events $started);$report.AtUTC=[DateTime]::UtcNow.ToString('o');$report.Result='PASS'
} catch {
 $report.Result='FAIL';$report.Error=$_.Exception.Message;$report.ErrorStack=$_.ScriptStackTrace
 throw
} finally {if($token){$token.Dispose()};$credential=$null;Save}
