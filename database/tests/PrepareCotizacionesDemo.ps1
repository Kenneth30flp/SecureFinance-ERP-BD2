param([string]$Server='localhost')
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
function Connect([string]$db){$c=New-Object System.Data.SqlClient.SqlConnection "Server=$Server;Database=$db;Integrated Security=True;Encrypt=True;TrustServerCertificate=True;Application Name=SecureFinance-Cotizaciones-Demo;Pooling=False";$c.Open();return $c}
function Read($c,[string]$s){$cmd=$c.CreateCommand();$cmd.CommandTimeout=180;$cmd.CommandText=$s;$dt=New-Object System.Data.DataTable;$r=$cmd.ExecuteReader();$dt.Load($r);$r.Close();return ,$dt}
function Run($c,[string]$s){$cmd=$c.CreateCommand();$cmd.CommandTimeout=180;$cmd.CommandText=$s;[void]$cmd.ExecuteNonQuery()}
$master=Connect 'master'
try{
 $backup=(Read $master "SELECT TOP(1) m.physical_device_name P FROM msdb.dbo.backupset b JOIN msdb.dbo.backupmediafamily m ON m.media_set_id=b.media_set_id WHERE b.database_name='SecureFinanceERP' AND b.type='D' AND b.is_copy_only=1 ORDER BY b.backup_finish_date DESC").Rows[0].P
 if(-not $backup){throw 'Falta respaldo COPY_ONLY existente'}
 $literal=$backup.Replace("'","''");Run $master "RESTORE VERIFYONLY FROM DISK=N'$literal' WITH CHECKSUM;"
 $files=Read $master "RESTORE FILELISTONLY FROM DISK=N'$literal'"
 $dataRoot=(Read $master "SELECT CONVERT(nvarchar(4000),SERVERPROPERTY('InstanceDefaultDataPath')) P").Rows[0].P
 $stamp=(Get-Date -Format 'yyyyMMddHHmmss')+'_'+[guid]::NewGuid().ToString('N').Substring(0,8)
 $demo='SecureFinanceERP_P3_COT_DEMO_'+$stamp
 if($demo -notmatch '^SecureFinanceERP_P3_COT_DEMO_[0-9]{14}_[a-f0-9]{8}$'){throw 'Nombre de demostracion invalido'}
 $moves=@();$i=0;foreach($f in $files.Rows){$extension=if($f.Type -eq 'L'){'ldf'}else{'mdf'};$target=Join-Path $dataRoot "${demo}_${i}.$extension";$moves+="MOVE N'$($f.LogicalName.Replace("'","''"))' TO N'$($target.Replace("'","''"))'";$i++}
 Run $master "RESTORE DATABASE [$demo] FROM DISK=N'$literal' WITH CHECKSUM,RECOVERY,$($moves -join ',');"
}finally{$master.Close()}
$c=Connect $demo
try{
 if((Read $c 'SELECT DB_NAME() N').Rows[0].N -ne $demo){throw 'Identidad SQL incorrecta'}
 # No se borran ni ocultan registros. El respaldo debe preceder los ejecutores QA.
 if((Read $c "SELECT (SELECT COUNT(*) FROM dbo.Producto WHERE Descripcion LIKE N'QA %')+(SELECT COUNT(*) FROM dbo.Cliente WHERE Nombre LIKE N'Cliente QA%' OR Nombre LIKE N'QA UC09%') N").Rows[0].N -ne 0){throw 'El respaldo contiene QA: conservar copia y elegir un respaldo anterior; no eliminar datos'}
 $maxFactura=(Read $c 'SELECT ISNULL(MAX(FacturaId),0) N FROM dbo.Factura').Rows[0].N
 $before=(Read $c "SELECT CONVERT(varchar(64),HASHBYTES('SHA2_256',CONVERT(varbinary(max),(SELECT * FROM dbo.Factura WHERE FacturaId<=$maxFactura ORDER BY FacturaId FOR JSON PATH,INCLUDE_NULL_VALUES))),2) H").Rows[0].H
 $names=@();if([DBNull]::Value -eq (Read $c "SELECT OBJECT_ID('dbo.sp_ReactivarCliente','P') O").Rows[0].O){$names+='40_ERP_ReactivarCliente.sql'}
 $names+=@('41_P3_COT_EstructuraCotizaciones.sql','42_P3_COT_Operaciones.sql','43_P3_COT_ConversionFactura.sql','44_P3_COT_BusquedaComercial.sql')
 foreach($name in $names){$content=Get-Content (Join-Path $root "database/$name") -Raw -Encoding UTF8;if($content -match '(?im)^\s*USE\s'){throw 'USE prohibido'};Run $c 'BEGIN TRANSACTION;';try{foreach($batch in [regex]::Split($content,'(?im)^\s*GO\s*\r?$')){if($batch.Trim()){Run $c $batch}};Run $c 'COMMIT;'}catch{try{Run $c 'IF @@TRANCOUNT>0 ROLLBACK;'}catch{};throw}}
 $actor=(Read $c "SELECT TOP(1) u.UsuarioId FROM dbo.Usuario u JOIN dbo.Usuario_Rol ur ON ur.UsuarioId=u.UsuarioId JOIN dbo.Rol r ON r.RolId=ur.RolId WHERE u.Activo=1 AND r.Activo=1 AND r.Nombre=N'Administrador' ORDER BY u.UsuarioId").Rows[0].UsuarioId
 if(-not $actor){throw 'Falta Administrador activo en copia'}
 $clients=@();$clientNames=@('Papeleria Horizonte - Demostracion','Oficinas del Norte - Demostracion','Comercial Aurora - Demostracion')
 for($i=0;$i -lt $clientNames.Count;$i++){
  $nit='DEMOCOT'+($i+1).ToString('000');$existing=Read $c "SELECT ClienteId FROM dbo.Cliente WHERE NIT=N'$nit'"
  if($existing.Rows.Count){$clients+=[int]$existing.Rows[0].ClienteId}else{$clients+=[int](Read $c "EXEC dbo.sp_RegistrarCliente @ActorUsuarioId=$actor,@NIT=N'$nit',@Nombre=N'$($clientNames[$i])';").Rows[0].ClienteId}
 }
 $catalog=Read $c "SELECT ProductoId,Codigo,Descripcion,Stock FROM dbo.Producto WHERE Codigo IN(N'DEMO-TECLADO',N'DEMO-MOUSE',N'DEMO-MONITOR',N'CABLE') AND Activo=1 ORDER BY Codigo"
 if($catalog.Rows.Count -lt 3){throw 'Faltan productos comerciales del respaldo; conservar copia sin crear duplicados'}
 foreach($p in $catalog.Rows){if($p.Stock -lt 10){
  $supplier=(Read $c "SELECT TOP(1) ProveedorId FROM dbo.Proveedor WHERE Activo=1 ORDER BY ProveedorId").Rows[0].ProveedorId
  if(-not $supplier){throw 'Falta proveedor activo para recepcion de demostracion'}
  $op=[guid]::NewGuid();Run $c "EXEC dbo.sp_RegistrarRecepcionCompra @ActorUsuarioId=$actor,@ProductoId=$($p.ProductoId),@ProveedorId=$supplier,@Cantidad=20,@DocumentoRespaldo=N'DEMO-COT-INGRESO',@Motivo=N'Existencias de demostracion en copia aislada',@OperacionId='$op';"
 }}
 $p1=[int]$catalog.Rows[0].ProductoId;$p2=[int]$catalog.Rows[1].ProductoId
 $quoteIds=@()
 for($i=0;$i -lt 5;$i++){
  $expiry=if($i -eq 4){'DATEADD(SECOND,2,SYSUTCDATETIME())'}else{'DATEADD(DAY,14,SYSUTCDATETIME())'}
  $customer=$clients[$i%$clients.Count];$op=[guid]::NewGuid()
  $sql="DECLARE @D dbo.TipoDetalleVentaDescuento,@V datetime2(3)=$expiry; INSERT @D VALUES($p1,2,5),($p2,1,0); EXEC dbo.P3_COT_Crear @ActorUsuarioId=$actor,@ClienteId=$customer,@VenceEn=@V,@Detalle=@D,@OperacionId='$op',@Observaciones=N'DEMOSTRACION: propuesta comercial ficticia para presentacion academica. Vigencia y precios sujetos al documento.';"
  $id=[int](Read $c $sql).Rows[0].CotizacionId;$quoteIds+=$id
  if($i -eq 1){$conversion=[guid]::NewGuid();Run $c "EXEC dbo.sp_ConvertirCotizacionAFactura @CotizacionId=$id,@ActorUsuarioId=$actor,@OperacionId='$conversion';"}
  if($i -eq 3){$cancellation=[guid]::NewGuid();Run $c "EXEC dbo.P3_COT_Cancelar @CotizacionId=$id,@ActorUsuarioId=$actor,@OperacionId='$cancellation',@Motivo=N'DEMOSTRACION: cliente solicita revisar condiciones';"}
 }
 Run $c "WAITFOR DELAY '00:00:03'; DBCC CHECKDB WITH NO_INFOMSGS,ALL_ERRORMSGS;"
 if((Read $c 'DBCC CHECKCONSTRAINTS WITH ALL_CONSTRAINTS').Rows.Count){throw 'Restricciones incumplidas'}
 $after=(Read $c "SELECT CONVERT(varchar(64),HASHBYTES('SHA2_256',CONVERT(varbinary(max),(SELECT * FROM dbo.Factura WHERE FacturaId<=$maxFactura ORDER BY FacturaId FOR JSON PATH,INCLUDE_NULL_VALUES))),2) H").Rows[0].H
 if($after -ne $before){throw 'Las facturas del respaldo cambiaron'}
 $backupRoot=(Read $c "SELECT CONVERT(nvarchar(4000),SERVERPROPERTY('InstanceDefaultBackupPath')) P").Rows[0].P
 $demoBackup=Join-Path $backupRoot ($demo+'.bak');$demoBackupLiteral=$demoBackup.Replace("'","''")
 Run $c "BACKUP DATABASE [$demo] TO DISK=N'$demoBackupLiteral' WITH COPY_ONLY,CHECKSUM; RESTORE VERIFYONLY FROM DISK=N'$demoBackupLiteral' WITH CHECKSUM;"
 $state=@{lab=$demo;actor=[int]$actor;server=$Server;demo=$true;clients=$clients;products=@($catalog.Rows|ForEach-Object{[int]$_.ProductoId});quotes=$quoteIds;backup=$demoBackup;originalInvoiceHash=$before}
 New-Item -ItemType Directory -Force (Join-Path $root '.data')|Out-Null
 $state|ConvertTo-Json -Depth 5|Set-Content (Join-Path $root '.data/cotizaciones-demo.json') -Encoding UTF8
 Write-Output "PASS demostracion restaurada y respaldada: $demo; 3 clientes ficticios y productos comerciales reutilizados; 5 documentos de demostracion; historicos conservados"
}finally{$c.Close()}
