param([ValidateSet('Prepare','Laboratory','Deploy')][string]$Stage='Prepare',
 [ValidateSet('','Administrador')][string]$CreditRole='')
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$statePath=Join-Path $root '.data/erp-deployment.json'
function Connect([string]$db) {
 $c=New-Object System.Data.SqlClient.SqlConnection "Server=localhost;Database=$db;Integrated Security=True;Encrypt=True;TrustServerCertificate=True;Application Name=SecureFinance-Deployment"
 $c.Open(); return $c
}
function Query($c,[string]$text) {
 $cmd=$c.CreateCommand();$cmd.CommandText=$text;$cmd.CommandTimeout=180
 $dt=New-Object System.Data.DataTable
 $reader=$cmd.ExecuteReader();$dt.Load($reader);$reader.Close()
 return ,$dt
}
function Run($c,[string]$text) {$cmd=$c.CreateCommand();$cmd.CommandText=$text;$cmd.CommandTimeout=180;[void]$cmd.ExecuteNonQuery()}
function Snapshot($c) {
 $result=@{}
 foreach($table in @('Producto','Proveedor','Cliente','Factura','DetalleFactura','MovimientoCaja','Kardex_Inventario','Apertura_Inventario','DevolucionCliente','DetalleDevolucion','DevolucionKardex','Ticket_Garantia','Historial_Garantia','CoberturaGarantiaVenta','Usuario_Rol','Rol_Permiso')) {
  $pk=Query $c "SELECT c.name FROM sys.indexes i JOIN sys.index_columns ic ON ic.object_id=i.object_id AND ic.index_id=i.index_id JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id WHERE i.object_id=OBJECT_ID('dbo.$table') AND i.is_primary_key=1 ORDER BY ic.key_ordinal"
  if(-not $pk.Rows.Count){throw "Clave primaria ausente $table"}
  $order=($pk.Rows|ForEach-Object{"[$($_.name)]"}) -join ','
  $r=Query $c "SELECT COUNT_BIG(*) N,CONVERT(varchar(64),HASHBYTES('SHA2_256',CONVERT(varbinary(max),(SELECT * FROM dbo.[$table] ORDER BY $order FOR JSON PATH,INCLUDE_NULL_VALUES))),2) H FROM dbo.[$table]"
  $result[$table]="$( $r.Rows[0].N ):$( $r.Rows[0].H )"
 }
 # Migration 35 deliberately settles zero-value credits; preserve every other field.
 $r=Query $c "SELECT COUNT_BIG(*) N,CONVERT(varchar(64),HASHBYTES('SHA2_256',CONVERT(varbinary(max),(SELECT NotaCreditoId,DevolucionId,Total,Estado,CASE WHEN Total=0 AND EstadoCredito='PENDIENTE' THEN 'LIQUIDADA' ELSE EstadoCredito END EstadoCredito FROM dbo.NotaCredito ORDER BY NotaCreditoId FOR JSON PATH,INCLUDE_NULL_VALUES))),2) H FROM dbo.NotaCredito"
 $result.NotaCredito="$( $r.Rows[0].N ):$( $r.Rows[0].H )"
 return $result
}
function Compare($before,$after) {
 foreach($key in $before.Keys){if($before[$key] -ne $after[$key]){throw "Datos cambiaron: $key"}}
}
function Migrate($c) {
 foreach($n in 33..37){
  $files=@(Get-ChildItem (Join-Path $root "database/${n}_*.sql"));if($files.Count -ne 1){throw "Archivo ambiguo $n"}
  $content=Get-Content -LiteralPath $files[0].FullName -Raw -Encoding UTF8
  if($content -match '(?im)^\s*USE\s'){throw 'Cambio de contexto prohibido'}
  foreach($batch in [regex]::Split($content,'(?im)^\s*GO\s*\r?$')){if($batch.Trim()){Run $c $batch}}
  Write-Output "PASS migracion $n"
 }
}
function Integrity($c){Run $c 'DBCC CHECKDB WITH NO_INFOMSGS, ALL_ERRORMSGS;';$r=Query $c 'DBCC CHECKCONSTRAINTS WITH ALL_CONSTRAINTS';if($r.Rows.Count){throw 'Restricciones incumplidas'};Write-Output 'PASS CHECKDB y CHECKCONSTRAINTS'}
function Permissions($c) {
 $names=@('sp_ConsultarProductoProveedor','sp_ERP_ConsultarKardex','sp_RegistrarRecepcionCompra','sp_ERP_RegistrarAjuste','sp_ERP_ProcesarVenta','sp_RegistrarAplicacionNotaCredito','sp_ConsultarAplicacionesNotaCredito','sp_AsociarProductoProveedor')
 foreach($name in $names){$r=Query $c "EXECUTE AS USER='securefinance_app'; SELECT HAS_PERMS_BY_NAME('dbo.$name','OBJECT','EXECUTE') P; REVERT;";if($r.Rows[0].P -ne 1){throw "Permiso ausente: $name"}}
 $r=Query $c "EXECUTE AS USER='securefinance_app'; SELECT HAS_PERMS_BY_NAME('dbo.Producto','OBJECT','UPDATE') Dml,HAS_PERMS_BY_NAME('dbo.sp_ProcesarVentaTransaccional','OBJECT','EXECUTE') Venta,HAS_PERMS_BY_NAME('dbo.sp_RegistrarMovimientoKardex','OBJECT','EXECUTE') Kardex; REVERT;"
 if($r.Rows[0].Dml -ne 0 -or $r.Rows[0].Venta -ne 0 -or $r.Rows[0].Kardex -ne 0){throw 'Permisos directos excesivos'}
 Write-Output 'PASS permisos efectivos y denegaciones'
}
if($Stage -eq 'Prepare'){
 $c=Connect 'SecureFinanceERP'
 try {
  # Check installed declarations from incremental schema files, never seeds or Full.
  foreach($file in Get-ChildItem (Join-Path $root 'database/*.sql')){
   if($file.Name -match '^(\d+)_'){$n=[int]$Matches[1]}else{continue}
   if($n -gt 32 -or $file.Name -match 'Seed|CreateDatabase'){continue}
   $content=Get-Content $file.FullName -Raw -Encoding UTF8
   foreach($match in [regex]::Matches($content,'(?im)^\s*CREATE\s+(?:OR\s+ALTER\s+)?(?:PROCEDURE|FUNCTION|TRIGGER|TABLE)\s+(dbo\.\w+)')){
    $name=$match.Groups[1].Value;$r=Query $c "SELECT OBJECT_ID('$name') Id";if($r.Rows[0].IsNull('Id')){throw "Prerrequisito ausente $name ($($file.Name))"}
   }
  }
  Write-Output 'PASS objetos requeridos 01-32 presentes'
  $before=Snapshot $c
  $stamp=Get-Date -Format 'yyyyMMddHHmmss'
  $backupDir=(Query $c "SELECT CONVERT(nvarchar(200),SERVERPROPERTY('InstanceDefaultBackupPath')) P").Rows[0].P
  $backup=Join-Path $backupDir "SecureFinanceERP_Current_$stamp.bak"
  Run $c "BACKUP DATABASE [SecureFinanceERP] TO DISK=N'$backup' WITH COPY_ONLY,CHECKSUM,INIT; RESTORE VERIFYONLY FROM DISK=N'$backup' WITH CHECKSUM;"
  $files=Query $c "RESTORE FILELISTONLY FROM DISK=N'$backup'"
  $dataDir=(Query $c "SELECT CONVERT(nvarchar(200),SERVERPROPERTY('InstanceDefaultDataPath')) P").Rows[0].P
  $lab="SecureFinanceERP_Estabilizacion_$stamp"
  $moves=@();$i=0
  foreach($row in $files.Rows){$ext=if($row.Type -eq 'L'){'ldf'}else{'mdf'};$path=Join-Path $dataDir "${lab}_${i}.$ext";$moves+="MOVE N'$($row.LogicalName)' TO N'$path'";$i++}
  Run $c "RESTORE DATABASE [$lab] FROM DISK=N'$backup' WITH CHECKSUM,RECOVERY,$($moves -join ',');"
  $lc=Connect $lab
  try{Integrity $lc;Compare $before (Snapshot $lc)}finally{$lc.Close()}
  New-Item -ItemType Directory -Force (Split-Path $statePath) | Out-Null
  @{lab=$lab;backup=$backup;baseline=$before;prepared=(Get-Date).ToString('o')}|ConvertTo-Json -Depth 8|Set-Content $statePath -Encoding UTF8
  Write-Output "PASS respaldo actual recuperable y datos conciliados: $lab"
 }finally{$c.Close()}
}else{
 $state=Get-Content $statePath -Raw|ConvertFrom-Json
 $baseline=@{};$state.baseline.psobject.Properties|ForEach-Object{$baseline[$_.Name]=$_.Value}
 if($Stage -eq 'Laboratory'){
  $c=Connect $state.lab
  try{Compare $baseline (Snapshot $c);Migrate $c;Integrity $c;Compare $baseline (Snapshot $c);Permissions $c;$state|Add-Member -NotePropertyName labPassed -NotePropertyValue $true -Force;$state|ConvertTo-Json -Depth 8|Set-Content $statePath -Encoding UTF8;Write-Output 'PASS laboratorio migrado sin perdida de datos'}finally{$c.Close()}
 }else{
  if(-not $state.labPassed -or -not $state.readOnlyRoutesPassed -or -not $state.workflowsPassed){throw 'Falta validacion de laboratorio, rutas reales o transacciones'}
  $c=Connect 'master'
  try{
   $active=Query $c "SELECT session_id FROM sys.dm_exec_sessions WHERE is_user_process=1 AND database_id=DB_ID('SecureFinanceERP') AND session_id<>@@SPID"
   if($active.Rows.Count){throw 'Existen sesiones activas: no desplegar'}
   Run $c 'ALTER DATABASE [SecureFinanceERP] SET RESTRICTED_USER WITH NO_WAIT;'
   $main=Connect 'SecureFinanceERP'
   try{
    Compare $baseline (Snapshot $main)
    Migrate $main;Integrity $main;Compare $baseline (Snapshot $main)
    if($CreditRole -eq 'Administrador'){
     # Explicit deployment choice; migration 36 never grants business roles itself.
     # Extend the existing administrator that already authorizes financial returns.
     Run $main @"
SET XACT_ABORT ON;
BEGIN TRANSACTION;
DECLARE @Role int=(SELECT RolId FROM dbo.Rol WHERE Nombre=N'Administrador' AND Activo=1),
 @Permission int=(SELECT PermisoId FROM dbo.Permiso WHERE Codigo=N'NOTAS_CREDITO_APLICAR');
IF @Role IS NULL OR @Permission IS NULL OR NOT EXISTS(
 SELECT 1 FROM dbo.Rol_Permiso rp JOIN dbo.Permiso p ON p.PermisoId=rp.PermisoId
 WHERE rp.RolId=@Role AND p.Codigo=N'DEVOLUCIONES_AUTORIZAR')
 THROW 54800,'Rol financiero administrador no cumple precondiciones.',1;
IF NOT EXISTS(SELECT 1 FROM dbo.Rol_Permiso WHERE RolId=@Role AND PermisoId=@Permission)
BEGIN
 INSERT dbo.Rol_Permiso(RolId,PermisoId) VALUES(@Role,@Permission);
 INSERT dbo.Bitacora_Transacciones(TablaAfectada,Operacion,IdentificadorRegistro,ValorNuevo,OperacionId,Motivo)
 VALUES(N'Rol_Permiso','INSERT',CONVERT(nvarchar(20),@Role),N'NOTAS_CREDITO_APLICAR / Administrador',NEWID(),N'Despliegue coordinado 33-37: habilitacion financiera explicita del administrador');
END;
COMMIT;
"@
     Write-Output 'PASS permiso financiero asignado explicitamente solo a Administrador'
    }
   }finally{$main.Close()}
   # All schema/data updates are complete before reopening. No application
   # backend is started until this post-deployment effective-permission check.
   Run $c 'ALTER DATABASE [SecureFinanceERP] SET MULTI_USER WITH NO_WAIT;'
   $verify=Connect 'SecureFinanceERP'
   try{Permissions $verify}finally{$verify.Close()}
   $state|Add-Member -NotePropertyName deployed -NotePropertyValue (Get-Date).ToString('o') -Force
   $state|ConvertTo-Json -Depth 8|Set-Content $statePath -Encoding UTF8
   Write-Output 'PASS despliegue coordinado; escritura reabierta tras conciliacion'
  }finally{$c.Close()}
 }
}
