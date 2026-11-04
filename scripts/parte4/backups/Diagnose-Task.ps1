[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$report=[ordered]@{AtUTC=[DateTime]::UtcNow.ToString('o');Changes=@()}
. (Join-Path $PSScriptRoot 'Windows-AccountRights.ps1')
function Capture([string]$Label,[scriptblock]$Action){try{$report[$Label]=& $Action}catch{$report[$Label]=@{Error=$_.Exception.Message}}}
Capture 'Token' {$i=[Security.Principal.WindowsIdentity]::GetCurrent();[ordered]@{Name=$i.Name;SID=$i.User.Value;Elevated=([Security.Principal.WindowsPrincipal]::new($i)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator);Machine=[Environment]::MachineName}}
Capture 'Accounts' {
 foreach($name in @('sf_backup_runner','sf_backup_task')){
  $u=Get-LocalUser -Name $name -ErrorAction SilentlyContinue
  if($u){[ordered]@{Name=$u.Name;SID=$u.SID.Value;Enabled=$u.Enabled;PasswordLastSet=$u.PasswordLastSet;Rights=@([SecureFinance.AccountRights]::Read($u.SID.Value));Administrator=((Get-LocalGroupMember -SID 'S-1-5-32-544').SID.Value -contains $u.SID.Value)}}
 }
}
Capture 'BatchPolicy' {[ordered]@{Allow=@([SecureFinance.AccountRights]::Assignees('SeBatchLogonRight'));Deny=@([SecureFinance.AccountRights]::Assignees('SeDenyBatchLogonRight'))}}
Capture 'Service' {$s=Get-Service Schedule;[ordered]@{Name=$s.Name;Status=[string]$s.Status;Security=(& sc.exe sdshow Schedule | Out-String).Trim()}}
Capture 'Policies' {
 $keys=@('HKLM:\SOFTWARE\Policies\Microsoft\Windows\Task Scheduler5.0','HKLM:\SOFTWARE\Policies\Microsoft\Windows\TaskScheduler')
 [ordered]@{UacEnabled=(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System').EnableLUA;TaskPolicyKeys=@($keys | ForEach-Object {[ordered]@{Path=$_;Exists=(Test-Path -LiteralPath $_)}})}
}
Capture 'Task' {
 $service=New-Object -ComObject 'Schedule.Service';$service.Connect();$folder=$service.GetFolder('\');$task=$folder.GetTask('SecureFinance-UC13')
 [ordered]@{RootSecurity=$folder.GetSecurityDescriptor(7);Enabled=$task.Enabled;State=$task.State;LastTaskResult=$task.LastTaskResult;Principal=$task.Definition.Principal.UserId;LogonType=$task.Definition.Principal.LogonType;RunLevel=$task.Definition.Principal.RunLevel;TriggerEnabled=$task.Definition.Triggers.Item(1).Enabled;Xml=$task.Xml}
}
Capture 'SchedulerChannel' {$channel=[Diagnostics.Eventing.Reader.EventLogConfiguration]::new('Microsoft-Windows-TaskScheduler/Operational');try{[ordered]@{Enabled=$channel.IsEnabled;Name=$channel.LogName}}finally{$channel.Dispose()}}
Capture 'SecurityEvents' {
 $query=[Diagnostics.Eventing.Reader.EventLogQuery]::new('Security',[Diagnostics.Eventing.Reader.PathType]::LogName,"*[System[(EventID=4624 or EventID=4625 or EventID=4698 or EventID=4704)] and EventData[Data='sf_backup_task' or Data='sf_backup_runner']]")
 $query.ReverseDirection=$true;$reader=[Diagnostics.Eventing.Reader.EventLogReader]::new($query)
 try {for($i=0;$i -lt 20;$i++){$entry=$reader.ReadEvent([TimeSpan]::FromSeconds(2));if($null -eq $entry){break};try{$entry.ToXml()}finally{$entry.Dispose()}}}finally{$reader.Dispose()}
}
$initialFile=Join-Path $repo '.data/p4-task-repair.json'
if(Test-Path -LiteralPath $initialFile){
 $initial=Get-Content -LiteralPath $initialFile -Raw | ConvertFrom-Json;$u=Get-LocalUser sf_backup_runner
 $savedDate=$initial.PreservedAccount.PasswordLastSet
 if($savedDate -is [DateTime]){$savedMilliseconds=([DateTimeOffset]$savedDate).ToUnixTimeMilliseconds()}
 elseif([string]$savedDate -match '^/Date\((-?\d+)\)/$'){$savedMilliseconds=[long]$Matches[1]}
 else {throw 'Unknown password metadata timestamp format; do not assume preservation.'}
 $currentMilliseconds=([DateTimeOffset]$u.PasswordLastSet).ToUnixTimeMilliseconds()
 $report.OriginalAccountUnchanged=($u.SID.Value -eq $initial.PreservedAccount.SID -and $currentMilliseconds -eq $savedMilliseconds -and $u.Enabled -eq $initial.PreservedAccount.Enabled)
 $report.OriginalPasswordTimestampMilliseconds=[ordered]@{Before=$savedMilliseconds;After=$currentMilliseconds}
}
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $repo '.data/p4-task-diagnostic-final.json') -Encoding UTF8
