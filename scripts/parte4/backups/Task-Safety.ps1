# Shared contracts. Dot-sourcing only defines functions; it performs no maintenance.
function Get-Uc13XmlDigest([string]$Xml,[switch]$IgnoreEnabled) {
 $reader=[Xml.XmlReader]::Create([IO.StringReader]::new($Xml),[Xml.XmlReaderSettings]@{DtdProcessing='Prohibit';XmlResolver=$null})
 try {$doc=[Xml.XmlDocument]::new();$doc.PreserveWhitespace=$false;$doc.XmlResolver=$null;$doc.Load($reader)} finally {$reader.Dispose()}
 if($IgnoreEnabled){$node=$doc.SelectSingleNode("/*[local-name()='Task']/*[local-name()='Settings']/*[local-name()='Enabled']");if($node){[void]$node.ParentNode.RemoveChild($node)}}
 $hash=[Security.Cryptography.SHA256]::Create()
 try {return ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($doc.OuterXml)))).Replace('-','')}finally{$hash.Dispose()}
}
function Resolve-Uc13Sid([string]$Identity) {
 if($Identity -match '^S-1-'){return ([Security.Principal.SecurityIdentifier]::new($Identity)).Value}
 return ([Security.Principal.NTAccount]::new($Identity)).Translate([Security.Principal.SecurityIdentifier]).Value
}
function Get-Uc13TaskSnapshot($Task) {
 $definition=$Task.Definition
 $sddl=$Task.GetSecurityDescriptor(7)
 $descriptor=[Security.AccessControl.RawSecurityDescriptor]::new($sddl)
 return [pscustomobject]@{Name=$Task.Name;Sid=(Resolve-Uc13Sid $definition.Principal.UserId);OwnerSid=$descriptor.Owner.Value;Security=$sddl;Xml=$Task.Xml;Enabled=[bool]$Task.Enabled;Definition=$definition}
}
function Assert-Uc13Task($Snapshot,[string]$Sid,[string[]]$TrustedOwners,[string]$Runtime,[string]$NodePath) {
 if($Snapshot.Name -ne 'SecureFinance-UC13' -or $Snapshot.Sid -ne $Sid -or $TrustedOwners -notcontains $Snapshot.OwnerSid){throw 'Unexpected task identity or owner; no task changes authorized.'}
 Assert-Uc13Dacl ([Security.AccessControl.RawSecurityDescriptor]::new($Snapshot.Security)) $TrustedOwners
 $d=$Snapshot.Definition
 if($d.Principal.LogonType -ne 2 -or $d.Principal.RunLevel -ne 0 -or $d.Settings.MultipleInstances -ne 2){throw 'Task must be S4U/Limited/IgnoreNew.'}
 if($d.Actions.Count -ne 1 -or $d.Triggers.Count -ne 1){throw 'Exactly one execution action and one time trigger required.'}
 $a=$d.Actions.Item(1);$t=$d.Triggers.Item(1)
 if($a.Type -ne 0 -or $t.Type -ne 1 -or $t.Repetition.Interval -ne 'PT1M'){throw 'Unexpected action or trigger type/interval.'}
 if([IO.Path]::GetFullPath($a.Path) -ne [IO.Path]::GetFullPath($NodePath) -or $a.Arguments -cne ('"'+(Join-Path $Runtime 'run.cjs')+'"') -or [IO.Path]::GetFullPath($a.WorkingDirectory) -ne [IO.Path]::GetFullPath($Runtime)){throw 'Task executable, arguments or working directory mismatch.'}
}
function Resolve-Uc13Worker($Snapshot,[string]$RequestedAccount='') {
 $worker=Get-LocalUser -SID ([Security.Principal.SecurityIdentifier]::new($Snapshot.Sid)) -ErrorAction Stop
 if(-not $worker.Enabled){throw 'Task worker account is disabled.'}
 if($RequestedAccount -and (Get-LocalUser -Name $RequestedAccount -ErrorAction Stop).SID.Value -ne $worker.SID.Value){throw 'Requested account differs from registered task SID.'}
 return $worker
}
function Assert-Uc13Credential($Credential,[string]$Sid) {
 if($Credential -isnot [PSCredential] -or (Resolve-Uc13Sid $Credential.UserName) -ne $Sid){throw 'Protected credential does not match task SID; never reset or replace an existing credential.'}
}
function New-Uc13Mutation($Snapshot,[switch]$EnabledOnly) {
 return [pscustomobject]@{Before=$Snapshot;Attempted=$false;ExpectedXml=$Snapshot.Xml;ExpectedEnabled=$Snapshot.Enabled;EnabledOnly=[bool]$EnabledOnly}
}
function Restore-Uc13Mutation($State,[scriptblock]$GetSnapshot,[scriptblock]$SetEnabled,[scriptblock]$SetXml) {
 if($null -eq $State -or -not $State.Attempted){return}
 $current=& $GetSnapshot
 if($current.Sid -ne $State.Before.Sid -or $current.OwnerSid -ne $State.Before.OwnerSid -or $current.Security -cne $State.Before.Security){throw 'Task ownership/security changed concurrently; restoration refused.'}
 if($current.Enabled -ne $State.Before.Enabled -and $current.Enabled -ne $State.ExpectedEnabled){throw 'Task enabled state changed concurrently; restoration refused.'}
 $original=Get-Uc13XmlDigest $State.Before.Xml -IgnoreEnabled:$State.EnabledOnly
 $actual=Get-Uc13XmlDigest $current.Xml -IgnoreEnabled:$State.EnabledOnly
 $expected=Get-Uc13XmlDigest $State.ExpectedXml -IgnoreEnabled:$State.EnabledOnly
 if($actual -ne $original -and $actual -ne $expected){throw 'Task definition changed concurrently; restoration refused.'}
 if($State.EnabledOnly){if($current.Enabled -ne $State.Before.Enabled){& $SetEnabled $State.Before.Enabled}}
 elseif($actual -ne $original -or $current.Enabled -ne $State.Before.Enabled){& $SetXml $State.Before.Xml $State.Before.Enabled}
 $after=& $GetSnapshot
 if($after.Sid -ne $State.Before.Sid -or $after.Security -cne $State.Before.Security -or $after.Enabled -ne $State.Before.Enabled -or (Get-Uc13XmlDigest $after.Xml -IgnoreEnabled:$State.EnabledOnly) -ne $original){throw 'Restoration not confirmed; inspect retained evidence.'}
 $State.Attempted=$false
}
function Assert-Uc13Access([uint32]$Mask,[ValidateSet('Read','Logs','Private')]$Mode) {
 # WRITE_DATA, APPEND_DATA, WRITE_EA, DELETE_CHILD, WRITE_ATTRIBUTES, DELETE, WRITE_DAC, WRITE_OWNER.
 if($Mode -eq 'Private'){if($Mask -ne 0){throw 'Worker can access registration credential.'};return}
 if(($Mask -band 0x120089) -ne 0x120089){throw 'Required effective read access missing.'}
 if($Mode -eq 'Read' -and ($Mask -band 0xD0156) -ne 0){throw 'Excessive effective write/delete/ownership access, including group grants.'}
 if($Mode -eq 'Logs' -and ($Mask -band 0xC0000) -ne 0){throw 'Worker must not control log ownership or ACL.'}
}
function Assert-Uc13AncestorAccess([uint32]$Mask) {
 if(($Mask -band 0xD0040) -ne 0){throw 'Ancestor permits replacing protected runtime/executable or changing its trust boundary.'}
}
function Assert-Uc13Dacl($Descriptor,[string[]]$TrustedWriters,[string[]]$OnlyReaders=@()) {
 if($null -eq $Descriptor.DiscretionaryAcl){throw 'Null DACL is not permitted.'}
 foreach($ace in $Descriptor.DiscretionaryAcl){
  if($ace.AceType -notin @([Security.AccessControl.AceType]::AccessAllowed,[Security.AccessControl.AceType]::AccessDenied)){throw 'Unsupported ACE; effective protection cannot be confirmed.'}
  if($ace.AceType -eq [Security.AccessControl.AceType]::AccessDenied){continue}
  $sid=$ace.SecurityIdentifier.Value
  $mask=[BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$ace.AccessMask),0)
  if($TrustedWriters -notcontains $sid -and ($mask -band 0x500D0156) -ne 0){throw 'Non-trusted principal/group can modify protected code, credentials or task.'}
  if($OnlyReaders.Count -and $TrustedWriters -notcontains $sid -and $OnlyReaders -notcontains $sid){throw 'Unexpected credential reader, including group grants.'}
 }
}
function Assert-Uc13FreshReport($Report,[string]$ResultField,[string]$Sid,[DateTime]$Now,[int]$MaxMinutes=30) {
 if($Report.SchemaVersion -ne 2 -or $Report.$ResultField -ne 'PASS' -or $Report.Server -ne '9U8ICS2VLMRUE' -or $Report.Database -ne 'SecureFinanceERP' -or -not $Report.DatabaseGuid){throw 'Untrusted report schema, result or database identity.'}
 $guid=[Guid]::Empty;if(-not [Guid]::TryParse([string]$Report.DatabaseGuid,[ref]$guid) -or $guid -eq [Guid]::Empty){throw 'Report database GUID invalid.'}
 $at=[DateTimeOffset]::Parse($Report.AtUTC).UtcDateTime
 if($at -gt $Now.ToUniversalTime().AddMinutes(1) -or $at -lt $Now.ToUniversalTime().AddMinutes(-$MaxMinutes)){throw 'Report is stale or future-dated.'}
 if($Sid -and $Report.SID -ne $Sid){throw 'Security evidence belongs to a different worker SID.'}
}
function Assert-Uc13TimerEvents([string[]]$Events,[DateTime]$Started,[DateTime]$Finished,[string]$ExpectedUser) {
 $triggers=@();$completions=@()
 foreach($text in $Events){
  $settings=[Xml.XmlReaderSettings]@{DtdProcessing='Prohibit';XmlResolver=$null};$reader=[Xml.XmlReader]::Create([IO.StringReader]::new($text),$settings)
  try{$xml=[Xml.XmlDocument]::new();$xml.XmlResolver=$null;$xml.Load($reader)}finally{$reader.Dispose()}
  $time=[DateTimeOffset]::Parse($xml.SelectSingleNode("//*[local-name()='TimeCreated']").GetAttribute('SystemTime')).UtcDateTime
  if($time -lt $Started.ToUniversalTime() -or $time -gt $Finished.ToUniversalTime().AddSeconds(2)){continue}
  $fields=@{};foreach($n in $xml.SelectNodes("//*[local-name()='EventData']/*[local-name()='Data']")){$fields[$n.GetAttribute('Name')]=$n.InnerText}
  if($fields.TaskName -ne '\SecureFinance-UC13'){continue}
  $id=[int]$xml.SelectSingleNode("//*[local-name()='EventID']").InnerText
  $instance=$fields.TaskInstanceId;if(-not $instance){$instance=$fields.InstanceId}
  if(-not $instance){continue}
  # Event 107 has no UserContext on supported Windows builds; identity comes from
  # the matching completion 102, not an invented field in the trigger event.
  if($id -eq 107 -and (-not $fields.UserContext -or $fields.UserContext -eq $ExpectedUser)){$triggers+=,[pscustomobject]@{Instance=$instance;Time=$time;Xml=$text}}
  if($id -eq 102 -and $fields.UserContext -eq $ExpectedUser){$completions+=,[pscustomobject]@{Instance=$instance;Time=$time}}
 }
 foreach($trigger in $triggers){if(@($completions | Where-Object {$_.Instance -eq $trigger.Instance -and $_.Time -ge $trigger.Time}).Count){return $trigger.Xml}}
 throw 'No fresh timer/completion pair for this task, identity and instance.'
}
function Get-Uc13Events([DateTime]$Started) {
 $stamp=$Started.ToUniversalTime().ToString('o')
 $query=[Diagnostics.Eventing.Reader.EventLogQuery]::new('Microsoft-Windows-TaskScheduler/Operational',[Diagnostics.Eventing.Reader.PathType]::LogName,"*[System[TimeCreated[@SystemTime >= '$stamp']] and EventData[Data[@Name='TaskName']='\SecureFinance-UC13']]")
 $reader=[Diagnostics.Eventing.Reader.EventLogReader]::new($query);$events=@()
 try{for($i=0;$i -lt 200;$i++){$event=$reader.ReadEvent([TimeSpan]::FromSeconds(1));if($null -eq $event){break};try{$events+=$event.ToXml()}finally{$event.Dispose()}}}finally{$reader.Dispose()}
 return $events
}
function Get-Uc13Owners {
 return @('S-1-5-18','S-1-5-32-544',(Resolve-Uc13Sid 'NT SERVICE\TrustedInstaller'))
}
function Get-Uc13SecurityProof($Token,[string]$Runtime,[string]$NodePath,[string[]]$TrustedOwners) {
 if($Token.IsAdministrator){throw 'Worker has effective administrator group membership.'}
 $private=Join-Path $Runtime 'task-registration.credential.clixml';$secret=Join-Path $Runtime 'backups.env'
 $trustedWriters=@('S-1-5-18','S-1-5-32-544',(Resolve-Uc13Sid 'NT SERVICE\TrustedInstaller'))
 $readers=@($Token.Sid)
 # Preserve the existing read-only runner grant without changing its SID or password.
 $legacy=Get-LocalUser -Name sf_backup_runner -ErrorAction SilentlyContinue;if($legacy){$readers+=$legacy.SID.Value}
 $paths=@((Get-Item -LiteralPath $Runtime),(Get-Item -LiteralPath $NodePath))
 $paths+=@(Get-ChildItem -LiteralPath $Runtime -Recurse -Force | Where-Object {$_.FullName -ne (Join-Path $Runtime 'logs') -and -not $_.FullName.StartsWith((Join-Path $Runtime 'logs')+'\',[StringComparison]::OrdinalIgnoreCase)})
 foreach($item in $paths){
  if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse point in executable/runtime trust boundary.'}
  $acl=Get-Acl -LiteralPath $item.FullName;$owner=Resolve-Uc13Sid $acl.Owner
  if($TrustedOwners -notcontains $owner){throw 'Untrusted runtime/executable owner.'}
  $mode=if($item.FullName -eq $private){'Private'}else{'Read'}
  $descriptor=[Security.AccessControl.RawSecurityDescriptor]::new($acl.GetSecurityDescriptorBinaryForm(),0)
  if($item.FullName -eq $private){Assert-Uc13Dacl $descriptor @('S-1-5-18','S-1-5-32-544') @('S-1-5-18','S-1-5-32-544')}
  elseif($item.FullName -eq $secret){Assert-Uc13Dacl $descriptor @('S-1-5-18','S-1-5-32-544') $readers}
  else {Assert-Uc13Dacl $descriptor $trustedWriters}
  Assert-Uc13Access ($Token.AccessMask($acl.GetSecurityDescriptorBinaryForm())) $mode
  if($mode -eq 'Private'){
   foreach($rule in $acl.Access){if($rule.AccessControlType -eq 'Allow' -and @('S-1-5-18','S-1-5-32-544') -notcontains (Resolve-Uc13Sid $rule.IdentityReference.Value)){throw 'Registration credential DACL is not administrator/SYSTEM-only.'}}
  }
  if($item.FullName -eq $secret -and $item.Attributes -band [IO.FileAttributes]::Encrypted){throw 'S4U configuration must not depend on EFS.'}
 }
 foreach($protected in @($Runtime,$NodePath)){
  $parent=[IO.Path]::GetDirectoryName($protected)
  while($parent){$acl=Get-Acl -LiteralPath $parent;Assert-Uc13AncestorAccess ($Token.AccessMask($acl.GetSecurityDescriptorBinaryForm()));$parent=[IO.Path]::GetDirectoryName($parent)}
 }
 $logs=Get-Item -LiteralPath (Join-Path $Runtime 'logs');if($logs.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Log directory is a reparse point.'}
 Assert-Uc13Access ($Token.AccessMask((Get-Acl -LiteralPath $logs.FullName).GetSecurityDescriptorBinaryForm())) Logs
 return [pscustomobject]@{Sid=$Token.Sid;GroupAware=$true;ProtectedPaths=$paths.Count;NodePath=[IO.Path]::GetFullPath($NodePath);Runtime=[IO.Path]::GetFullPath($Runtime)}
}
function Save-Uc13Credential([PSCredential]$Credential,[string]$Path) {
 if(Test-Path -LiteralPath $Path){throw 'Existing credential custody must not be overwritten.'}
 $security=[Security.AccessControl.FileSecurity]::new();$security.SetAccessRuleProtection($true,$false)
 foreach($sid in @('S-1-5-18','S-1-5-32-544')){$security.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),'FullControl','Allow'))}
 # Create with private DACL from the start. Export-Clixml uses Windows DPAPI for SecureString.
 $stream=[IO.FileStream]::new($Path,[IO.FileMode]::CreateNew,[Security.AccessControl.FileSystemRights]::FullControl,[IO.FileShare]::None,4096,[IO.FileOptions]::None,$security)
 $stream.Dispose();$Credential | Export-Clixml -LiteralPath $Path -Force
 & icacls.exe $Path /setowner '*S-1-5-18' | Out-Null
 if($LASTEXITCODE -ne 0){throw 'Credential saved privately, but SYSTEM ownership not confirmed; inspect before proceeding.'}
}
function Get-Uc13DatabaseIdentity {
 $sql="SET NOCOUNT ON;IF DB_NAME()<>'SecureFinanceERP' OR CONVERT(nvarchar(128),SERVERPROPERTY('ServerName'))<>'9U8ICS2VLMRUE' THROW 58010,'Wrong target',1;IF dbo.P3_INT_Destino()<>DB_NAME() OR NOT EXISTS(SELECT 1 FROM dbo.BackupsSchedule WHERE Id=1 AND Enabled=0) THROW 58010,'Policy guard failed',1;IF EXISTS(SELECT 1 FROM dbo.BackupsJob WHERE Estado IN('PENDIENTE','EJECUTANDO')) THROW 58010,'Queue must be idle',1;IF NOT EXISTS(SELECT 1 FROM dbo.P4_LDF_Configuracion c JOIN sys.database_recovery_status r ON r.database_id=DB_ID() AND c.DatabaseGuid=r.database_guid WHERE c.BaseDatos=DB_NAME() AND c.Servidor=CONVERT(nvarchar(128),SERVERPROPERTY('ServerName'))) THROW 58010,'LDF identity mismatch',1;SELECT CONVERT(varchar(36),database_guid) FROM sys.database_recovery_status WHERE database_id=DB_ID();"
 $output=@(& sqlcmd.exe -S localhost -E -N -C -b -h -1 -W -d SecureFinanceERP -Q $sql)
 if($LASTEXITCODE -ne 0){throw 'SQL identity/policy/idle queue guard failed.'}
 $guid=[Guid]::Empty
 if(-not [Guid]::TryParse(($output -join '').Trim(),[ref]$guid)){throw 'SQL database GUID missing.'}
 return $guid.ToString()
}
function Assert-Uc13WorkerLog($Line,[string]$Account,[DateTime]$Started,[DateTime]$Finished) {
 $at=[DateTimeOffset]::Parse($Line.atUTC).UtcDateTime
 if($Line.identity -ne $Account -or $null -eq $Line.result -or $at -lt $Started.ToUniversalTime() -or $at -gt $Finished.ToUniversalTime().AddSeconds(2)){throw 'Fresh completed result from expected worker missing.'}
}
function Get-Uc13AuthorizedRoots {
 # Hex transport keeps Unicode paths independent of the sqlcmd/console code page.
 $text=@(& sqlcmd.exe -S localhost -E -N -C -b -h -1 -W -w 65535 -d SecureFinanceERP -Q 'SET NOCOUNT ON;SELECT CONVERT(varchar(8000),CONVERT(varbinary(4000),Ruta),2) FROM (SELECT Ruta FROM dbo.BackupsConfig WHERE Id=1 UNION SELECT RutaBackup FROM dbo.P4_LDF_Configuracion WHERE Id=1) r ORDER BY Ruta;')
 if($LASTEXITCODE -ne 0){throw 'Cannot reconfirm authorized backup destinations.'}
 return @($text | ForEach-Object {
  $hex=$_.Trim();if($hex -notmatch '^(?:[A-Fa-f0-9]{4})+$'){throw 'Invalid destination path encoding.'}
  $bytes=New-Object byte[] ($hex.Length/2);for($i=0;$i -lt $bytes.Length;$i++){$bytes[$i]=[Convert]::ToByte($hex.Substring($i*2,2),16)}
  [Text.Encoding]::Unicode.GetString($bytes)
 })
}
function Assert-Uc13CurrentCapacity($Report,[string[]]$Roots,[scriptblock]$Probe) {
 if(-not $Roots.Count -or -not $Report.roots.Count){throw 'Authorized destination evidence missing.'}
 $normalize={param($p) if($p -notmatch '^[A-Za-z]:\\' -or $p -match '(^|[\\/])\.\.([\\/]|$)' -or $p -match '[\r\n\x00]'){throw 'Invalid authorized destination.'};[IO.Path]::GetFullPath($p).TrimEnd('\').ToLowerInvariant()}
 $actual=@($Roots | ForEach-Object {& $normalize $_} | Sort-Object -Unique)
 $recorded=@($Report.roots | ForEach-Object {& $normalize $_.Ruta} | Sort-Object -Unique)
 if(($actual -join '|') -cne ($recorded -join '|')){throw 'Authorized destinations changed since capacity assessment.'}
 $needed=[System.Numerics.BigInteger]::Parse($Report.estimatedAdditionalBytes)+[System.Numerics.BigInteger]::Parse($Report.assumptions.freeReserveBytes)
 if($needed -le 0){throw 'Invalid capacity budget.'}
 foreach($root in $Roots){
  $current=& $Probe $root
  $previous=@($Report.volumes | Where-Object {(& $normalize $_.Root) -eq (& $normalize $root)})
  if($previous.Count -ne 1 -or $current.VolumeId -ne $previous[0].VolumeId -or [System.Numerics.BigInteger]::Parse($current.FreeBytes) -le $needed){throw 'Destination volume identity or available space changed; activation refused.'}
 }
}
function Set-Uc13TaskXml($Folder,[string]$Xml,[PSCredential]$Credential,[string]$Security) {
 if(-not $Security){throw 'Existing task security descriptor must be preserved explicitly.'}
 $password=$null
 # UPDATE | DONT_ADD_PRINCIPAL_ACE; preserve the complete existing owner/DACL.
 try{$password=$Credential.GetNetworkCredential().Password;$definition=New-Object -ComObject 'Schedule.Service';$definition.Connect();$d=$definition.NewTask(0);$d.XmlText=$Xml;$registered=$Folder.RegisterTaskDefinition('SecureFinance-UC13',$d,20,$Credential.UserName,$password,2,$Security);return $registered}
 finally{$password=$null}
}
