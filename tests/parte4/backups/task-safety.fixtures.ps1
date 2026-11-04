# In-memory fixtures ONLY. No production script is executed. No account/credential is exported.
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$scripts=Join-Path $repo 'scripts/parte4/backups'
. (Join-Path $scripts 'Task-Safety.ps1')
Add-Type -Path (Join-Path $scripts 'Windows-Inspection.cs')
$count=0
function Assert([bool]$Condition,[string]$Message='Assertion failed'){if(-not $Condition){throw $Message}}
function Reject([scriptblock]$Action){$failed=$false;try{& $Action}catch{$failed=$true};Assert $failed 'Expected rejection'}
function Check([string]$Name,[scriptblock]$Action){& $Action;$script:count++;Write-Output ('PASS '+$Name)}
$sid='S-1-5-21-111-222-333-1001';$owners=@('S-1-5-18','S-1-5-32-544')
$runtime='C:\ProgramData\SecureFinanceERP\UC13';$node='C:\Program Files\nodejs\node.exe'
function Collection($Element){$c=[pscustomobject]@{Count=1;Element=$Element};$c | Add-Member ScriptMethod Item {param($i) if($i -ne 1){throw 'Invalid index'};return $this.Element};return $c}
function Snapshot([bool]$Enabled=$false,[string]$Action='expected'){
 $word=if($Enabled){'true'}else{'false'}
 return [pscustomobject]@{Name='SecureFinance-UC13';Sid=$sid;OwnerSid='S-1-5-18';Security='O:SYG:SYD:(A;;FA;;;SY)(A;;FA;;;BA)(A;;FRFX;;;AU)';Enabled=$Enabled;Xml=('<Task><Settings><Enabled>'+ $word+'</Enabled></Settings><Actions><Exec>'+ $Action+'</Exec></Actions></Task>');Definition=[pscustomobject]@{Principal=[pscustomobject]@{LogonType=2;RunLevel=0};Settings=[pscustomobject]@{MultipleInstances=2};Actions=(Collection ([pscustomobject]@{Type=0;Path=$node;Arguments=('"'+$runtime+'\run.cjs"');WorkingDirectory=$runtime}));Triggers=(Collection ([pscustomobject]@{Type=1;Enabled=$false;Repetition=[pscustomobject]@{Interval='PT1M'}}))}}
}
Check 'unattempted cleanup never fetches or changes an existing task' {
 Restore-Uc13Mutation $null {throw 'Unexpected access'} {throw 'Unexpected write'} {throw 'Unexpected write'}
 Restore-Uc13Mutation (New-Uc13Mutation (Snapshot)) {throw 'Unexpected access'} {throw 'Unexpected write'} {throw 'Unexpected write'}
}
Check 'controlled verification restores both initially enabled and initially disabled states' {
 foreach($original in @($true,$false)){
  $state=New-Uc13Mutation (Snapshot $original) -EnabledOnly;$state.ExpectedEnabled=-not $original;$state.Attempted=$true;$script:current=Snapshot (-not $original);$script:writes=0
  Restore-Uc13Mutation $state {$script:current} {param($enabled) $script:writes++;$script:current=Snapshot $enabled} {throw 'No XML update permitted'}
  Assert ($script:writes -eq 1 -and $script:current.Enabled -eq $original -and -not $state.Attempted)
 }
}
Check 'cleanup refuses concurrent identity, owner, ACL or definition changes without writes' {
 foreach($field in @('Sid','OwnerSid','Security','Xml')){
  $state=New-Uc13Mutation (Snapshot) -EnabledOnly;$state.Attempted=$true;$script:current=Snapshot $true
  $script:current.$field=if($field -eq 'Xml'){(Snapshot $true 'foreign').Xml}else{'foreign'}
  Reject {Restore-Uc13Mutation $state {$script:current} {throw 'Forbidden write'} {throw 'Forbidden write'}}
 }
 $state=New-Uc13Mutation (Snapshot $true) -EnabledOnly;$state.Attempted=$true;$script:current=Snapshot $false
 Reject {Restore-Uc13Mutation $state {$script:current} {throw 'Concurrent disable must not be undone'} {throw 'No write'}}
}
Check 'definition update rollback restores the exact prior XML and state' {
 $before=Snapshot $true;$state=New-Uc13Mutation $before;$state.Attempted=$true;$script:current=Snapshot $true 'updated';$state.ExpectedXml=$script:current.Xml;$script:writes=0
 Restore-Uc13Mutation $state {$script:current} {throw 'No enable-only update'} {param($xml,$enabled) Assert ($xml -ceq $before.Xml);$script:writes++;$script:current=Snapshot $enabled}
 Assert ($script:writes -eq 1 -and $script:current.Xml -ceq $before.Xml)
}
Check 'task contract rejects wrong SID, owner, executable, arguments, working directory and privileges' {
 Assert-Uc13Task (Snapshot) $sid $owners $runtime $node
 foreach($change in @('sid','owner','path','arguments','directory','admin','instances','extraAction')){
  $s=Snapshot
  switch($change){sid{$s.Sid='foreign'} owner{$s.OwnerSid='foreign'} path{$s.Definition.Actions.Item(1).Path='C:\evil.exe'} arguments{$s.Definition.Actions.Item(1).Arguments='--eval evil'} directory{$s.Definition.Actions.Item(1).WorkingDirectory='C:\Temp'} admin{$s.Definition.Principal.RunLevel=1} instances{$s.Definition.Settings.MultipleInstances=0} extraAction{$s.Definition.Actions.Count=2}}
  Reject {Assert-Uc13Task $s $sid $owners $runtime $node}
 }
}
Check 'effective secret ACL rejects FullControl, write, append, delete and ACL/owner changes' {
 Assert-Uc13Access 0x120089 Read
 foreach($extra in @(0x2,0x4,0x10,0x40,0x100,0x10000,0x40000,0x80000)){Reject {Assert-Uc13Access ([uint32](0x120089 -bor $extra)) Read}}
 Reject {Assert-Uc13Access 0x1F01FF Read};Reject {Assert-Uc13Access 1 Private};Assert-Uc13Access 0 Private
}
Check 'group/inherited write grants and public secret readers are rejected' {
 $bad=[Security.AccessControl.RawSecurityDescriptor]::new('O:SYG:SYD:(A;;FA;;;SY)(A;;FA;;;BU)')
 Reject {Assert-Uc13Dacl $bad $owners}
 $readers=[Security.AccessControl.RawSecurityDescriptor]::new('O:SYG:SYD:(A;;FA;;;SY)(A;;FR;;;AU)')
 Reject {Assert-Uc13Dacl $readers $owners @($sid)}
 Reject {Assert-Uc13Dacl ([Security.AccessControl.RawSecurityDescriptor]::new('O:SYG:SY')) $owners}
 Assert-Uc13AncestorAccess 0x120089
 foreach($mask in @(0x40,0x10000,0x40000,0x80000)){Reject {Assert-Uc13AncestorAccess ([uint32]$mask)}}
}
Check 'both existing account names resolve through the task SID, without creating accounts' {
 $script:fixtureSid=$sid
 function Get-LocalUser {param($SID,$Name,$ErrorAction) if($Name -eq 'wrong'){return [pscustomobject]@{SID=[pscustomobject]@{Value='S-1-5-21-111-222-333-1002'}}};return [pscustomobject]@{Name=$script:fixtureName;Enabled=$true;SID=[pscustomobject]@{Value=$script:fixtureSid}}}
 foreach($name in @('sf_backup_runner','sf_backup_task')){$script:fixtureName=$name;Assert ((Resolve-Uc13Worker (Snapshot)).Name -eq $name);Assert ((Resolve-Uc13Worker (Snapshot) $name).SID.Value -eq $sid)}
 Reject {Resolve-Uc13Worker (Snapshot) 'wrong'}
}
Check 'credential SID binding accepts only synthetic matching credentials; no export occurs' {
 $fake=ConvertTo-SecureString 'TEST_ONLY_NOT_AN_ACCOUNT_PASSWORD' -AsPlainText -Force
 Assert-Uc13Credential ([PSCredential]::new($sid,$fake)) $sid
 Reject {Assert-Uc13Credential ([PSCredential]::new('S-1-5-21-111-222-333-1002',$fake)) $sid}
}
$now=[DateTime]::Parse('2026-11-04T18:00:00Z').ToUniversalTime()
function Report {return [pscustomobject]@{SchemaVersion=2;AtUTC=$now.ToString('o');Result='PASS';Server='9U8ICS2VLMRUE';Database='SecureFinanceERP';DatabaseGuid='12345678-1234-1234-1234-123456789012';SID=$sid}}
Check 'security/capacity evidence rejects old schema, stale/future time, other SID or database' {
 Assert-Uc13FreshReport (Report) Result $sid $now
 foreach($change in @('schema','old','future','sid','database','guid')){
  $r=Report;switch($change){schema{$r.SchemaVersion=1} old{$r.AtUTC=$now.AddMinutes(-31).ToString('o')} future{$r.AtUTC=$now.AddMinutes(2).ToString('o')} sid{$r.SID='foreign'} database{$r.Database='other'} guid{$r.DatabaseGuid='invalid'}}
  Reject {Assert-Uc13FreshReport $r Result $sid $now}
 }
 $r=Report;$r.AtUTC=$now.AddMinutes(-6).ToString('o');Reject {Assert-Uc13FreshReport $r Result $sid $now 5}
}
function Event([int]$Id,[DateTime]$Time,[string]$Instance,[string]$User='MACHINE\worker',[string]$Task='\SecureFinance-UC13'){
 $userField=if($Id -eq 107){''}else{'<Data Name="UserContext">'+$User+'</Data>'}
 return '<Event><System><EventID>'+ $Id+'</EventID><TimeCreated SystemTime="'+$Time.ToString('o')+'"/></System><EventData><Data Name="TaskName">'+$Task+'</Data><Data Name="InstanceId">'+$Instance+'</Data>'+$userField+'</EventData></Event>'
}
Check 'timer verification correlates fresh 107 and 102 by instance/user; 107 need not contain UserContext' {
 $good=@((Event 107 $now 'same'),(Event 102 ($now.AddSeconds(2)) 'same'))
 Assert ((Assert-Uc13TimerEvents $good $now ($now.AddSeconds(3)) 'MACHINE\worker') -eq $good[0])
 foreach($events in @(@((Event 107 $now.AddMinutes(-1) 'same'),$good[1]),@($good[0],(Event 102 $now.AddSeconds(2) 'other')),@($good[0],(Event 102 $now.AddSeconds(2) 'same' 'MACHINE\wrong')),@((Event 110 $now 'same'),$good[1]))){Reject {Assert-Uc13TimerEvents $events $now ($now.AddSeconds(3)) 'MACHINE\worker'}}
}
Check 'stale worker logs are rejected independently of task exit code' {
 $line=[pscustomobject]@{atUTC=$now.ToString('o');identity='worker';result=@{}}
 Assert-Uc13WorkerLog $line worker $now $now.AddSeconds(3)
 $line.atUTC=$now.AddMinutes(-1).ToString('o');Reject {Assert-Uc13WorkerLog $line worker $now $now.AddSeconds(3)}
}
Check 'activation rechecks destinations and actual volume space without trusting a stale path mapping' {
 $r=[pscustomobject]@{roots=@([pscustomobject]@{Ruta='C:\Backups\'});volumes=@([pscustomobject]@{Root='C:\Backups\';VolumeId='volume1'});estimatedAdditionalBytes='100';assumptions=[pscustomobject]@{freeReserveBytes='20'}}
 Assert-Uc13CurrentCapacity $r @('C:\Backups\') {param($root) [pscustomobject]@{VolumeId='volume1';FreeBytes='121'}}
 Reject {Assert-Uc13CurrentCapacity $r @('D:\Backups\') {throw 'Must not probe changed roots'}}
 Reject {Assert-Uc13CurrentCapacity $r @('C:\Backups\') {[pscustomobject]@{VolumeId='other';FreeBytes='10000'}}}
 Reject {Assert-Uc13CurrentCapacity $r @('C:\Backups\') {[pscustomobject]@{VolumeId='volume1';FreeBytes='120'}}}
}
Check 'authorized paths preserve Unicode and spaces through mocked sqlcmd hex output' {
 $script:expectedRoot='C:\Respaldo '+[char]0x00E1+'\SQL\'
 $script:encodedRoot=([BitConverter]::ToString([Text.Encoding]::Unicode.GetBytes($script:expectedRoot))).Replace('-','')
 function sqlcmd.exe {$global:LASTEXITCODE=0;return $script:encodedRoot}
 $roots=@(Get-Uc13AuthorizedRoots);Assert ($roots.Count -eq 1 -and $roots[0] -ceq $script:expectedRoot)
 $script:encodedRoot='not-hex';Reject {Get-Uc13AuthorizedRoots}
}
Check 'production wrappers wire guarded restoration and custody; no unconditional catch disable or right grant' {
 foreach($name in @('Verify-Production.ps1','Enable-QueueTask.ps1','Repair-Task.ps1')){
  $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $scripts $name),[ref]$tokens,[ref]$errors);Assert (@($errors).Count -eq 0)
  $top=@($ast.EndBlock.Statements | Where-Object {$_ -is [Management.Automation.Language.TryStatementAst]})[0]
  Assert (-not ($top.CatchClauses[0].Body.Extent.Text -match '\.Enabled\s*='))
  $text=Get-Content -LiteralPath (Join-Path $scripts $name) -Raw;Assert (-not $text.Contains('::GrantBatchOnly('))
  if($name -ne 'Repair-Task.ps1'){Assert $text.Contains('Restore-Uc13Mutation $mutation')}
 }
 foreach($name in @('Prepare-Production.ps1','Repair-Task.ps1')){$text=Get-Content -LiteralPath (Join-Path $scripts $name) -Raw;Assert ($text.IndexOf('Save-Uc13Credential ') -lt $text.IndexOf("'Register-IsolatedTask.ps1'"))}
}
Write-Output ('TASK_SAFETY_PASS '+$count+' groups; native code compiled only; no Windows maintenance/SQL/credential export executed.')
