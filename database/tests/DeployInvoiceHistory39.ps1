param([ValidateSet('Inspect','Prepare','Laboratory','Deploy','Verify')][string]$Stage='Inspect')
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$statePath=Join-Path $root '.data/facturas39-deployment.json'
$migration=Join-Path $root 'database/39_ERP_HistorialFacturas.sql'
$content=Get-Content $migration -Raw -Encoding UTF8
if($content -match '(?im)^\s*USE\s'){throw 'La migracion no puede cambiar contexto'}
function Connect([string]$database){
 $c=New-Object System.Data.SqlClient.SqlConnection "Server=localhost;Database=$database;Integrated Security=True;Encrypt=True;TrustServerCertificate=True;Application Name=SecureFinance-Facturas39-Deployment;Pooling=False"
 $c.Open();return $c
}
function Run($c,[string]$sql){$cmd=$c.CreateCommand();$cmd.CommandTimeout=180;$cmd.CommandText=$sql;[void]$cmd.ExecuteNonQuery()}
function Read($c,[string]$sql){$cmd=$c.CreateCommand();$cmd.CommandTimeout=180;$cmd.CommandText=$sql;$dt=New-Object System.Data.DataTable;$r=$cmd.ExecuteReader();$dt.Load($r);$r.Close();return ,$dt}
function Normalize([string]$definition){return ([regex]::Replace(([regex]::Replace($definition.Trim(),'(?i)^CREATE(?:\s+OR\s+ALTER)?\s+','')),'\s+',''))}
function Installed($c){
 $names=@('sp_ERP_ConsultarFacturas','sp_ERP_ConsultarComprobante','tr_ERP_FacturaProductoEmision','tr_ERP_FacturaProductoInmutable')
 $present=0
 foreach($name in $names){$r=Read $c "SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.$name')) D";if(-not $r.Rows[0].IsNull('D')){$present++}}
 $table=Read $c "SELECT OBJECT_ID('dbo.FacturaProductoEmision','U') T"
 if($present -eq 0 -and $table.Rows[0].IsNull('T')){return $false}
 if($present -ne 4 -or $table.Rows[0].IsNull('T')){throw 'Instalacion 39 parcial: detener sin sobreescribir'}
 foreach($name in $names){
  $expected=[regex]::Match($content,'(?ims)^(CREATE OR ALTER (?:PROCEDURE|TRIGGER) dbo\.'+[regex]::Escape($name)+'\b.*?)^GO\s*$').Groups[1].Value
  $actual=(Read $c "SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.$name')) D").Rows[0].D
  if(-not $expected -or (Normalize $expected) -ne (Normalize $actual)){throw "Definicion 39 incompatible: $name"}
 }
 return $true
}
function Permissions($c){
 $r=Read $c "EXECUTE AS USER='securefinance_app'; SELECT HAS_PERMS_BY_NAME('dbo.sp_ERP_ConsultarFacturas','OBJECT','EXECUTE') L,HAS_PERMS_BY_NAME('dbo.sp_ERP_ConsultarComprobante','OBJECT','EXECUTE') D,HAS_PERMS_BY_NAME('dbo.Factura','OBJECT','SELECT') T,HAS_PERMS_BY_NAME('dbo.FacturaProductoEmision','OBJECT','SELECT') S; REVERT;"
 if($r.Rows[0].L -ne 1 -or $r.Rows[0].D -ne 1 -or $r.Rows[0].T -ne 0 -or $r.Rows[0].S -ne 0){throw 'Permisos SQL incompatibles'}
 $roles=Read $c "SELECT r.Nombre FROM dbo.Rol_Permiso rp JOIN dbo.Permiso p ON p.PermisoId=rp.PermisoId JOIN dbo.Rol r ON r.RolId=rp.RolId WHERE p.Codigo='FACTURAS_CONSULTAR'"
 if($roles.Rows.Count -ne 2 -or @($roles.Rows|Where-Object{$_.Nombre -notin @('Administrador','Cajero')}).Count){throw 'Asignacion de permiso inesperada'}
 Write-Output 'PASS EXECUTE, permiso de consulta Administrador/Cajero y ausencia de SELECT directo'
}
function Snapshot($c){
 $snapshot=@{}
 $tables=Read $c "SELECT t.name FROM sys.tables t JOIN sys.schemas s ON s.schema_id=t.schema_id WHERE s.name='dbo' AND t.name<>'FacturaProductoEmision' AND t.is_ms_shipped=0 ORDER BY t.name"
 foreach($table in $tables.Rows){
  $name=$table.name;$quoted='['+$name.Replace(']',']]')+']';$literal=$name.Replace("'","''")
  $pk=Read $c "SELECT c.name FROM sys.indexes i JOIN sys.index_columns k ON k.object_id=i.object_id AND k.index_id=i.index_id JOIN sys.columns c ON c.object_id=k.object_id AND c.column_id=k.column_id WHERE i.object_id=OBJECT_ID(N'dbo.$literal') AND i.is_primary_key=1 AND k.key_ordinal>0 ORDER BY k.key_ordinal"
  if(-not $pk.Rows.Count){throw "Tabla sin clave para conciliacion determinista: $name"}
  $order=($pk.Rows|ForEach-Object{'['+$_.name.Replace(']',']]')+']'}) -join ','
  $where=if($name -eq 'Permiso'){" WHERE Codigo<>N'FACTURAS_CONSULTAR'"}elseif($name -eq 'Rol_Permiso'){" WHERE PermisoId NOT IN(SELECT PermisoId FROM dbo.Permiso WHERE Codigo=N'FACTURAS_CONSULTAR')"}else{''}
  $r=Read $c "SELECT COUNT_BIG(*) N,CONVERT(varchar(64),HASHBYTES('SHA2_256',CONVERT(varbinary(max),(SELECT * FROM dbo.$quoted $where ORDER BY $order FOR JSON PATH,INCLUDE_NULL_VALUES))),2) H FROM dbo.$quoted $where"
  $snapshot[$name]="$($r.Rows[0].N):$($r.Rows[0].H)"
 }
 return $snapshot
}
function Compare($before,$after){
 if($before.Count -ne $after.Count){throw 'Cambio inesperado de tablas de datos'}
 foreach($name in $before.Keys){if($before[$name] -ne $after[$name]){throw "Datos cambiaron: $name"}}
}
function Integrity($c){Run $c 'DBCC CHECKDB WITH NO_INFOMSGS,ALL_ERRORMSGS;';$r=Read $c 'DBCC CHECKCONSTRAINTS WITH ALL_CONSTRAINTS';if($r.Rows.Count){throw 'Restricciones incumplidas'};Write-Output 'PASS CHECKDB y restricciones'}
function Apply($c){
 if(Installed $c){Write-Output 'SKIP 39: objetos ya instalados y correctos';return}
 foreach($batch in [regex]::Split($content,'(?im)^\s*GO\s*\r?$')){if($batch.Trim()){Run $c $batch}}
 if(-not (Installed $c)){throw 'Migracion 39 incompleta'}
 Write-Output 'PASS migracion incremental 39'
}
function Save($state){$state|ConvertTo-Json -Depth 8|Set-Content $statePath -Encoding UTF8}
if($Stage -eq 'Inspect'){
 $c=Connect 'SecureFinanceERP'
 try{if(Installed $c){Permissions $c;Write-Output 'INSTALLED_39'}else{Write-Output 'ABSENT_39'}}finally{$c.Close()}
 exit
}
if($Stage -eq 'Deploy'){
 $existing=Connect 'SecureFinanceERP'
 try{if(Installed $existing){Permissions $existing;Write-Output 'SKIP 39: principal ya instalada correctamente; sin mantenimiento ni reaplicar migracion';exit}}finally{$existing.Close()}
}
if($Stage -eq 'Prepare'){
 $c=Connect 'SecureFinanceERP'
 try{
  if(Installed $c){Permissions $c;Write-Output 'SKIP respaldo/migracion: 39 correcta';exit}
  $before=Snapshot $c
  $stamp=Get-Date -Format 'yyyyMMddHHmmss'
  $backupRoot=(Read $c "SELECT CONVERT(nvarchar(200),SERVERPROPERTY('InstanceDefaultBackupPath')) P").Rows[0].P
  $backup=Join-Path $backupRoot "SecureFinanceERP_Facturas39_Current_$stamp.bak"
  Run $c "BACKUP DATABASE [SecureFinanceERP] TO DISK=N'$backup' WITH COPY_ONLY,CHECKSUM; RESTORE VERIFYONLY FROM DISK=N'$backup' WITH CHECKSUM;"
  $files=Read $c "RESTORE FILELISTONLY FROM DISK=N'$backup'"
  $dataRoot=(Read $c "SELECT CONVERT(nvarchar(200),SERVERPROPERTY('InstanceDefaultDataPath')) P").Rows[0].P
  $lab="SecureFinanceERP_Facturas_$stamp";$moves=@();$i=0
  foreach($row in $files.Rows){$ext=if($row.Type -eq 'L'){'ldf'}else{'mdf'};$path=Join-Path $dataRoot "${lab}_${i}.$ext";$moves+="MOVE N'$($row.LogicalName)' TO N'$path'";$i++}
  Run $c "RESTORE DATABASE [$lab] FROM DISK=N'$backup' WITH CHECKSUM,RECOVERY,$($moves -join ',');"
  $copy=Connect $lab
  try{Integrity $copy;Compare $before (Snapshot $copy);Compare $before (Snapshot $c)}finally{$copy.Close()}
  Save @{lab=$lab;backup=$backup;baseline=$before;migrationHash=(Get-FileHash $migration -Algorithm SHA256).Hash;prepared=(Get-Date).ToString('o')}
  Write-Output "PASS respaldo actual recuperado y $($before.Count) tablas conciliadas: $lab"
 }finally{$c.Close()}
 exit
}
$state=Get-Content $statePath -Raw|ConvertFrom-Json
if($state.lab -notmatch '^SecureFinanceERP_Facturas_[0-9]+$'){throw 'Destino aislado invalido'}
if($state.migrationHash -ne (Get-FileHash $migration -Algorithm SHA256).Hash){throw 'La migracion cambio despues del respaldo'}
$before=@{};$state.baseline.psobject.Properties|ForEach-Object{$before[$_.Name]=$_.Value}
if($Stage -eq 'Verify'){
 $c=Connect 'SecureFinanceERP'
 try{if(-not (Installed $c)){throw '39 no instalada'};Permissions $c;Compare $before (Snapshot $c)
  if((Read $c 'SELECT COUNT_BIG(*) N FROM dbo.FacturaProductoEmision').Rows[0].N -ne 0){throw 'Se registraron lineas nuevas: revisar actividad antes de afirmar ausencia de escrituras'}
  Write-Output 'PASS consultas y reimpresion conservan todas las filas del respaldo actual'
 }finally{$c.Close()}
 exit
}
if($Stage -eq 'Laboratory'){
 $c=Connect $state.lab
 try{
  Compare $before (Snapshot $c);Apply $c;Integrity $c;Compare $before (Snapshot $c);Permissions $c
  $state|Add-Member -NotePropertyName laboratoryPassed -NotePropertyValue $true -Force;Save $state
  if((Read $c 'SELECT COUNT_BIG(*) N FROM dbo.FacturaProductoEmision').Rows[0].N -ne 0){throw 'No se permite inventar snapshots historicos'}
  Write-Output 'PASS laboratorio actual sin cambiar filas historicas; solo nuevo permiso y sus roles'
 }finally{$c.Close()}
 exit
}
if(-not $state.laboratoryPassed -or -not $state.invoiceChecksPassed){throw 'Falta laboratorio y comprobante validado'}
$master=Connect 'master'
try{
 $active=Read $master "SELECT session_id FROM sys.dm_exec_sessions WHERE is_user_process=1 AND (database_id=DB_ID('SecureFinanceERP') OR session_id IN(SELECT session_id FROM sys.dm_tran_locks WHERE resource_database_id=DB_ID('SecureFinanceERP'))) AND session_id<>@@SPID"
 if($active.Rows.Count){throw 'Hay sesiones activas; conservar servicio y no desplegar'}
 Run $master 'ALTER DATABASE [SecureFinanceERP] SET RESTRICTED_USER WITH NO_WAIT;'
 $main=Connect 'SecureFinanceERP'
 try{Compare $before (Snapshot $main);Apply $main;Integrity $main;Compare $before (Snapshot $main);if((Read $main 'SELECT COUNT_BIG(*) N FROM dbo.FacturaProductoEmision').Rows[0].N -ne 0){throw 'Snapshots historicos inesperados'}}finally{$main.Close()}
 Run $master 'ALTER DATABASE [SecureFinanceERP] SET MULTI_USER WITH NO_WAIT;'
 $verify=Connect 'SecureFinanceERP'
 try{Permissions $verify;if(-not (Installed $verify)){throw 'Verificacion final 39 incompleta'}}finally{$verify.Close()}
 $state|Add-Member -NotePropertyName deployed -NotePropertyValue (Get-Date).ToString('o') -Force;Save $state
 Write-Output 'PASS 39 principal; todas las filas preservadas; MULTI_USER'
}finally{$master.Close()}
