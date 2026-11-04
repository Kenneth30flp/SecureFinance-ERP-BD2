[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$destination=Join-Path $env:ProgramData 'SecureFinanceERP/UC13'
$reportFile=Join-Path $repo '.data/p4-task-repair.json'
$stamp=[DateTime]::UtcNow.ToString('yyyyMMddHHmmss')
$report=[ordered]@{AtUTC=[DateTime]::UtcNow.ToString('o');Steps=@();Changes=@();AutomaticPolicy='DISABLED';Account='sf_backup_task';Task='SecureFinance-UC13'}
. (Join-Path $PSScriptRoot 'Windows-AccountRights.ps1')
. (Join-Path $PSScriptRoot 'Task-Safety.ps1')
function Save {$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFile -Encoding UTF8}
function Step([string]$Label){$report.Steps+=$Label;Save}
try {
 $operatorIdentity=[Security.Principal.WindowsIdentity]::GetCurrent()
 if(-not ([Security.Principal.WindowsPrincipal]::new($operatorIdentity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Elevation required.'}
 $report.Operator=$operatorIdentity.Name;$report.Elevated=$true;Save
 & sqlcmd.exe -S localhost -E -N -C -b -d SecureFinanceERP -Q "SET NOCOUNT ON;IF DB_NAME()<>'SecureFinanceERP' OR CONVERT(nvarchar(128),SERVERPROPERTY('ServerName'))<>'9U8ICS2VLMRUE' THROW 58010,'Wrong target',1;IF NOT EXISTS(SELECT 1 FROM dbo.BackupsSchedule WHERE Id=1 AND Enabled=0) THROW 58010,'Automatic policy must stay disabled',1;IF EXISTS(SELECT 1 FROM dbo.BackupsJob WHERE Estado IN('PENDIENTE','EJECUTANDO')) THROW 58010,'Queue must be idle for controlled verification',1;"
 if($LASTEXITCODE -ne 0){throw 'SQL target/policy/idle queue guard failed.'}
 Step 'Pinned original target, automatic policy disabled, idle queue; no migrations'
 $service=Get-Service Schedule
 $report.Service=[ordered]@{Name=$service.Name;Status=[string]$service.Status}
 if($service.Status -ne 'Running'){throw 'Task Scheduler service is not running; inspect before changing it.'}
 $scheduler=New-Object -ComObject 'Schedule.Service';$scheduler.Connect();$folder=$scheduler.GetFolder('\')
 $report.RootTaskSecurity=$folder.GetSecurityDescriptor(7)
 $report.ServiceSecurity=(& sc.exe sdshow Schedule | Out-String).Trim()
 $report.UacEnabled=(Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System').EnableLUA
 if($report.UacEnabled -ne 1){throw 'Unexpected UAC configuration.'}
 $existing=$null;try{$existing=$folder.GetTask('SecureFinance-UC13')}catch{if($_.Exception.HResult -ne -2147024894){throw}}
 if($existing){throw 'Existing task: do not replace it; inspect saved evidence.'}
 Step 'Running scheduler and readable root DACL; no service ACL, UAC or general policy changes'
 $report.BatchAssigneesBefore=@([SecureFinance.AccountRights]::Assignees('SeBatchLogonRight'))
 $report.DenyBatchAssignees=@([SecureFinance.AccountRights]::Assignees('SeDenyBatchLogonRight'))
 Step 'Read actual batch right assignments through LSA; no global policy import'
 $original=Get-LocalUser -Name sf_backup_runner
 $report.PreservedAccount=[ordered]@{Name=$original.Name;SID=$original.SID.Value;Enabled=$original.Enabled;PasswordLastSet=$original.PasswordLastSet}
 $report.OriginalAccountRights=@([SecureFinance.AccountRights]::Read($original.SID.Value))
 Step 'Recorded original account SID and unchanged password date'
 $channel=[Diagnostics.Eventing.Reader.EventLogConfiguration]::new('Microsoft-Windows-TaskScheduler/Operational')
 $report.OperationalChannelInitiallyEnabled=$channel.IsEnabled
 if(-not $channel.IsEnabled){$channel.IsEnabled=$true;$channel.SaveChanges();$report.Changes+='Enabled TaskScheduler/Operational diagnostic channel only'}
 $channel.Dispose()
 Step 'Local batch rights and original account recorded; scheduler event channel available'
 $account='sf_backup_task';$workerIdentity=[Environment]::MachineName+'\'+$account
 if(Get-LocalUser -Name $account -ErrorAction SilentlyContinue){throw 'New worker account already exists; inspect state instead of changing its password.'}
 $bytes=New-Object byte[] 48;$generator=[Security.Cryptography.RandomNumberGenerator]::Create();$generator.GetBytes($bytes)
 $password=ConvertTo-SecureString ([Convert]::ToBase64String($bytes)+'Aa1!') -AsPlainText -Force
 New-LocalUser -Name $account -Password $password -Description 'SecureFinance isolated S4U backup task' -AccountNeverExpires | Out-Null
 Add-LocalGroupMember -SID 'S-1-5-32-545' -Member $account
 $credential=[PSCredential]::new($workerIdentity,$password);$password=$null;[Array]::Clear($bytes,0,$bytes.Length);$generator.Dispose()
 $user=Get-LocalUser -Name $account
 if((Get-LocalGroupMember -SID 'S-1-5-32-544').SID.Value -contains $user.SID.Value){throw 'New identity must not be administrator.'}
 $report.WorkerIdentity=$workerIdentity;$report.WorkerSID=$user.SID.Value;$report.Changes+='Created standard local sf_backup_task; existing account/passwords preserved'
 $custody=Join-Path $destination 'task-registration.credential.clixml'
 if(Test-Path -LiteralPath $custody){throw 'Existing registration credential: never overwrite it.'}
 Save-Uc13Credential $credential $custody
 & icacls.exe $destination /grant:r ($workerIdentity+':(OI)(CI)RX') | Out-Null
 if($LASTEXITCODE -ne 0){throw 'Runtime read ACL failed.'}
 & icacls.exe (Join-Path $destination 'logs') /grant:r ($workerIdentity+':(OI)(CI)M') | Out-Null
 if($LASTEXITCODE -ne 0){throw 'Worker log ACL failed.'}
 $report.Changes+='Granted new SID runtime RX and logs M only; registration credential DPAPI-encrypted and restricted to SYSTEM/Administrators'
 Step 'New standard identity and isolated runtime access prepared without changing existing credentials'
 & (Join-Path $PSScriptRoot 'Register-IsolatedTask.ps1') -WorkerCredential $credential -WorkerAccount $account
 $credential=$null
 $task=$folder.GetTask('SecureFinance-UC13')
 if($task.Enabled -or $task.Definition.Triggers.Item(1).Enabled){throw 'Task and trigger must initially be disabled.'}
 if($task.Definition.Principal.LogonType -ne 2 -or $task.Definition.Principal.RunLevel -ne 0){throw 'Expected S4U and limited task.'}
 $principal=$task.Definition.Principal.UserId
 $principalSid=if($principal -match '^S-1-'){$principal}else{([Security.Principal.NTAccount]::new($principal)).Translate([Security.Principal.SecurityIdentifier]).Value}
 if($principalSid -ne $user.SID.Value){throw 'Task SID differs from dedicated identity.'}
 $report.TaskXml=$task.Xml
 Step 'Task registered S4U/Limited with one-time credential; task and repetition trigger disabled'
 & (Join-Path $PSScriptRoot 'Verify-Production.ps1') -WorkerAccount $account
 $report.OperationalResult=Join-Path $repo '.data/p4-task-operational.json'
 Step 'Existing batch rights and controlled execution verified; no right assignment by verification'
 $now=Get-LocalUser -Name sf_backup_runner
 if($now.SID.Value -ne $original.SID.Value -or $now.PasswordLastSet -ne $original.PasswordLastSet -or $now.Enabled -ne $original.Enabled){throw 'Original Windows account changed.'}
 $report.ExistingAccountUnchanged=$true
 $report.TaskEnabled=$task.Enabled;$report.TriggerEnabled=$task.Definition.Triggers.Item(1).Enabled
 $report.Result='PASS'
} catch {
 $report.Result='FAIL';$report.Error=$_.Exception.Message;$report.ErrorStack=$_.ScriptStackTrace
 # Registration creates disabled tasks; verification owns/restores its temporary enable.
 # This script never changes an existing task, including when preflight fails.
 throw
} finally {$credential=$null;Save}
