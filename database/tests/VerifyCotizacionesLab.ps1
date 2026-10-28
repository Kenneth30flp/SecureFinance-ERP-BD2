$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$state=Get-Content (Join-Path $root '.data/cotizaciones-lab.json') -Raw|ConvertFrom-Json
if($state.lab -notmatch '^SecureFinanceERP_P3_COT_[0-9]{14}_[a-f0-9]{8}$'){throw 'Solo laboratorio de Cotizaciones'}
$c=New-Object System.Data.SqlClient.SqlConnection "Server=$($state.server);Database=$($state.lab);Integrated Security=True;Encrypt=True;TrustServerCertificate=True;Application Name=SecureFinance-Cotizaciones-Verify;Pooling=False"
function Run([string]$s){$cmd=$c.CreateCommand();$cmd.CommandTimeout=180;$cmd.CommandText=$s;[void]$cmd.ExecuteNonQuery()}
function Read([string]$s){$cmd=$c.CreateCommand();$cmd.CommandTimeout=180;$cmd.CommandText=$s;$t=New-Object System.Data.DataTable;$r=$cmd.ExecuteReader();$t.Load($r);$r.Close();return ,$t}
$c.Open()
try{
 if((Read 'SELECT DB_NAME() N').Rows[0].N -ne $state.lab){throw 'Destino incorrecto'}
 $before=(Read 'SELECT (SELECT COUNT_BIG(*) FROM dbo.P3_COT_Cotizacion) C,(SELECT COUNT_BIG(*) FROM dbo.P3_COT_Detalle) D,(SELECT COUNT_BIG(*) FROM dbo.P3_COT_HistorialEstado) H').Rows[0]
 $beforeCounts=@([long]$before.C,[long]$before.D,[long]$before.H)
 $conversion=(Read "SELECT COUNT(*) N FROM sys.procedures WHERE object_id=OBJECT_ID('dbo.sp_ConvertirCotizacionAFactura')").Rows[0].N -eq 1
 $names=@('41_P3_COT_EstructuraCotizaciones.sql','42_P3_COT_Operaciones.sql');if($conversion){$names+='43_P3_COT_ConversionFactura.sql'}
 foreach($name in $names){
  $s=Get-Content (Join-Path $root "database/$name") -Raw -Encoding UTF8
  if($s -match '(?im)^\s*USE\s'){throw 'USE prohibido'}
  Run 'BEGIN TRANSACTION;'
  try{foreach($batch in [regex]::Split($s,'(?im)^\s*GO\s*\r?$')){if($batch.Trim()){Run $batch}};Run 'COMMIT;'}catch{try{Run 'IF @@TRANCOUNT>0 ROLLBACK;'}catch{};throw}
 }
 $after=(Read 'SELECT (SELECT COUNT_BIG(*) FROM dbo.P3_COT_Cotizacion) C,(SELECT COUNT_BIG(*) FROM dbo.P3_COT_Detalle) D,(SELECT COUNT_BIG(*) FROM dbo.P3_COT_HistorialEstado) H').Rows[0]
 if(($beforeCounts -join ',') -ne (@([long]$after.C,[long]$after.D,[long]$after.H) -join ',')){throw 'Reaplicacion modifico documentos'}
 Write-Output 'PASS reaplicacion de migraciones instaladas preserva documentos y estados'
 $current=(Read 'SELECT (SELECT COUNT_BIG(*) FROM dbo.Factura) Facturas,(SELECT COUNT_BIG(*) FROM dbo.DetalleFactura) Detalles,(SELECT COUNT_BIG(*) FROM dbo.MovimientoCaja) Caja,(SELECT COUNT_BIG(*) FROM dbo.Kardex_Inventario) Kardex').Rows[0]
 if(-not $conversion){
  foreach($field in @('Facturas','Detalles','Caja','Kardex')){if([long]$current[$field] -ne [long]$state.baseline.$field){throw "Efecto de venta inesperado: $field"}}
  Write-Output 'PASS sin UC09: emision/cancelacion no agregan efectos de venta'
 }else{
  # Con UC09 las nuevas facturas son esperadas: conciliar todas las conversiones.
  $bad=(Read "SELECT COUNT(*) N FROM dbo.P3_COT_Cotizacion c WHERE Estado='PROCESADA' AND (NOT EXISTS(SELECT 1 FROM dbo.Factura f WHERE f.FacturaId=c.FacturaId AND f.ClienteId=c.ClienteId AND f.Total=c.Total AND f.Subtotal=c.Subtotal AND f.DescuentoTotal=c.Descuento AND f.IVA=c.IVA) OR (SELECT COUNT(*) FROM dbo.MovimientoCaja m WHERE m.FacturaId=c.FacturaId AND m.Monto=c.Total)<>1 OR EXISTS(SELECT 1 FROM dbo.DetalleFactura d WHERE d.FacturaId=c.FacturaId AND (SELECT COUNT(*) FROM dbo.Kardex_Inventario k WHERE k.DetalleFacturaId=d.DetalleFacturaId AND k.TipoMovimiento='VENTA' AND k.Cantidad=d.Cantidad)<>1))").Rows[0].N
  if($bad -ne 0){throw 'Conversion inconsistente con Factura/caja/Kardex'}
  Write-Output 'PASS todas las conversiones conciliadas con Factura, caja y Kardex'
  if((Read "SELECT COUNT(*) N FROM sys.triggers WHERE name='P3_COT_QA_FalloKardex'").Rows[0].N -ne 0){throw 'Quedo un trigger de inyeccion QA'}
 }
 $protected=if($conversion){"'sp_RegistrarMovimientoKardex','tr_ERP_SolicitudVentaInmutable'"}else{"'sp_ERP_ProcesarVenta','sp_ProcesarVentaTransaccional','sp_RegistrarMovimientoKardex','tr_ERP_SolicitudVentaInmutable'"}
 foreach($row in (Read "SELECT o.name,CONVERT(varchar(64),HASHBYTES('SHA2_256',m.definition),2) H FROM sys.sql_modules m JOIN sys.objects o ON o.object_id=m.object_id WHERE o.name IN($protected)").Rows){if($row.H -ne $state.shared.($row.name)){throw "Contrato fuera de alcance modificado: $($row.name)"}}
 Write-Output 'PASS Kardex y libro idempotente conservan definiciones originales'
 $audit=(Read "SELECT COUNT_BIG(*) N FROM dbo.P3_COT_HistorialEstado h WHERE NOT EXISTS(SELECT 1 FROM dbo.Bitacora_Transacciones b WHERE b.TablaAfectada=N'P3_COT_Cotizacion' AND b.OperacionId=h.OperacionId AND b.ActorUsuarioId=h.ActorUsuarioId)").Rows[0].N
 if($audit -ne 0){throw 'Evento de cotizacion sin auditoria DML'}
 Write-Output 'PASS historial de cotizaciones conciliado con auditoria'
 Run 'DBCC CHECKDB WITH NO_INFOMSGS,ALL_ERRORMSGS;'
 if((Read 'DBCC CHECKCONSTRAINTS WITH ALL_CONSTRAINTS').Rows.Count){throw 'Restricciones incumplidas'}
 Write-Output 'PASS CHECKDB y CHECKCONSTRAINTS'
}finally{$c.Close()}
