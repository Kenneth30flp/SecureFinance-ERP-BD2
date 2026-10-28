param([string]$Server='localhost')
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
function Connect([string]$db){
 $c=New-Object System.Data.SqlClient.SqlConnection "Server=$Server;Database=$db;Integrated Security=True;Encrypt=True;TrustServerCertificate=True;Application Name=SecureFinance-Cotizaciones-Lab;Pooling=False"
 $c.Open();return $c
}
function Read($c,[string]$query){$cmd=$c.CreateCommand();$cmd.CommandTimeout=180;$cmd.CommandText=$query;$t=New-Object System.Data.DataTable;$r=$cmd.ExecuteReader();$t.Load($r);$r.Close();return ,$t}
function Run($c,[string]$query){$cmd=$c.CreateCommand();$cmd.CommandTimeout=180;$cmd.CommandText=$query;[void]$cmd.ExecuteNonQuery()}
$master=Connect 'master'
try{
 $backup=(Read $master "SELECT TOP(1) m.physical_device_name P FROM msdb.dbo.backupset b JOIN msdb.dbo.backupmediafamily m ON m.media_set_id=b.media_set_id WHERE b.database_name='SecureFinanceERP' AND b.type='D' AND b.is_copy_only=1 ORDER BY b.backup_finish_date DESC").Rows[0].P
 if(-not $backup){throw 'Falta respaldo COPY_ONLY existente; no se crea uno automaticamente'}
 $literal=$backup.Replace("'","''")
 Run $master "RESTORE VERIFYONLY FROM DISK=N'$literal' WITH CHECKSUM;"
 $files=Read $master "RESTORE FILELISTONLY FROM DISK=N'$literal'"
 $dataRoot=(Read $master "SELECT CONVERT(nvarchar(4000),SERVERPROPERTY('InstanceDefaultDataPath')) P").Rows[0].P
 $lab='SecureFinanceERP_P3_COT_'+(Get-Date -Format 'yyyyMMddHHmmss')+'_'+[guid]::NewGuid().ToString('N').Substring(0,8)
 if($lab -notmatch '^SecureFinanceERP_P3_COT_[0-9]{14}_[a-f0-9]{8}$'){throw 'Destino de laboratorio invalido'}
 $moves=@();$i=0
 foreach($file in $files.Rows){$extension=if($file.Type -eq 'L'){'ldf'}else{'mdf'};$target=Join-Path $dataRoot "${lab}_${i}.$extension";$moves+="MOVE N'$($file.LogicalName.Replace("'","''"))' TO N'$($target.Replace("'","''"))'";$i++}
 # No REPLACE: nunca sobrescribe una base existente. No escribe en SecureFinanceERP.
 Run $master "RESTORE DATABASE [$lab] FROM DISK=N'$literal' WITH CHECKSUM,RECOVERY,$($moves -join ',');"
}finally{$master.Close()}
$copy=Connect $lab
try{
 if((Read $copy 'SELECT DB_NAME() N').Rows[0].N -ne $lab){throw 'Identidad SQL incorrecta'}
 $baseline=(Read $copy 'SELECT (SELECT COUNT_BIG(*) FROM dbo.Factura) Facturas,(SELECT COUNT_BIG(*) FROM dbo.DetalleFactura) Detalles,(SELECT COUNT_BIG(*) FROM dbo.MovimientoCaja) Caja,(SELECT COUNT_BIG(*) FROM dbo.Kardex_Inventario) Kardex').Rows[0]
 $baselineMap=@{Facturas=[long]$baseline.Facturas;Detalles=[long]$baseline.Detalles;Caja=[long]$baseline.Caja;Kardex=[long]$baseline.Kardex}
 $shared=@{}
 foreach($row in (Read $copy "SELECT o.name,CONVERT(varchar(64),HASHBYTES('SHA2_256',m.definition),2) H FROM sys.sql_modules m JOIN sys.objects o ON o.object_id=m.object_id WHERE o.name IN('sp_ERP_ProcesarVenta','sp_ProcesarVentaTransaccional','sp_RegistrarMovimientoKardex','tr_ERP_SolicitudVentaInmutable')").Rows){$shared[$row.name]=$row.H}
 # El ultimo respaldo publicado precede a 40: instalarla solo en esta copia si falta.
 $names=@()
 if([DBNull]::Value -eq (Read $copy "SELECT OBJECT_ID('dbo.sp_ReactivarCliente','P') O").Rows[0].O){$names+='40_ERP_ReactivarCliente.sql'}
 $names+=@('41_P3_COT_EstructuraCotizaciones.sql','42_P3_COT_Operaciones.sql')
 foreach($name in $names){
  $content=Get-Content (Join-Path $root "database/$name") -Raw -Encoding UTF8
  if($content -match '(?im)^\s*USE\s'){throw 'Migracion no puede cambiar de base'}
  Run $copy 'BEGIN TRANSACTION;'
  try{foreach($batch in [regex]::Split($content,'(?im)^\s*GO\s*\r?$')){if($batch.Trim()){Run $copy $batch}};Run $copy 'COMMIT;'}catch{try{Run $copy 'IF @@TRANCOUNT>0 ROLLBACK;'}catch{};throw}
  Write-Output "PASS $name en laboratorio"
 }
 Run $copy 'DBCC CHECKDB WITH NO_INFOMSGS,ALL_ERRORMSGS;'
 if((Read $copy 'DBCC CHECKCONSTRAINTS WITH ALL_CONSTRAINTS').Rows.Count){throw 'Restricciones incumplidas'}
 $actor=(Read $copy "SELECT TOP(1) u.UsuarioId FROM dbo.Usuario u JOIN dbo.Usuario_Rol ur ON ur.UsuarioId=u.UsuarioId JOIN dbo.Rol r ON r.RolId=ur.RolId WHERE u.Activo=1 AND r.Activo=1 AND r.Nombre=N'Administrador' ORDER BY u.UsuarioId").Rows[0].UsuarioId
 if(-not $actor){throw 'Falta actor administrador en copia'}
 New-Item -ItemType Directory -Force (Join-Path $root '.data')|Out-Null
 @{lab=$lab;actor=[int]$actor;server=$Server;baseline=$baselineMap;shared=$shared}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $root '.data/cotizaciones-lab.json') -Encoding UTF8
 Write-Output "PASS laboratorio aislado preparado: $lab (sin desplegar principal)"
}finally{$copy.Close()}
