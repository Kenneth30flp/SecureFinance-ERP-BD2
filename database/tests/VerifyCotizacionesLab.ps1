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
 foreach($name in @('41_P3_COT_EstructuraCotizaciones.sql','42_P3_COT_Operaciones.sql')){
  $s=Get-Content (Join-Path $root "database/$name") -Raw -Encoding UTF8
  if($s -match '(?im)^\s*USE\s'){throw 'USE prohibido'}
  Run 'BEGIN TRANSACTION;'
  try{foreach($batch in [regex]::Split($s,'(?im)^\s*GO\s*\r?$')){if($batch.Trim()){Run $batch}};Run 'COMMIT;'}catch{try{Run 'IF @@TRANCOUNT>0 ROLLBACK;'}catch{};throw}
 }
 $after=(Read 'SELECT (SELECT COUNT_BIG(*) FROM dbo.P3_COT_Cotizacion) C,(SELECT COUNT_BIG(*) FROM dbo.P3_COT_Detalle) D,(SELECT COUNT_BIG(*) FROM dbo.P3_COT_HistorialEstado) H').Rows[0]
 if(($beforeCounts -join ',') -ne (@([long]$after.C,[long]$after.D,[long]$after.H) -join ',')){throw 'Reaplicacion modifico documentos'}
 Write-Output 'PASS reaplicacion 41-42 preserva documentos y estados'
 $current=(Read 'SELECT (SELECT COUNT_BIG(*) FROM dbo.Factura) Facturas,(SELECT COUNT_BIG(*) FROM dbo.DetalleFactura) Detalles,(SELECT COUNT_BIG(*) FROM dbo.MovimientoCaja) Caja,(SELECT COUNT_BIG(*) FROM dbo.Kardex_Inventario) Kardex').Rows[0]
 foreach($field in @('Facturas','Detalles','Caja','Kardex')){if([long]$current[$field] -ne [long]$state.baseline.$field){throw "Efecto de venta inesperado: $field"}}
 Write-Output 'PASS emision/cancelacion no agregan Factura, DetalleFactura, MovimientoCaja ni Kardex'
 foreach($row in (Read "SELECT o.name,CONVERT(varchar(64),HASHBYTES('SHA2_256',m.definition),2) H FROM sys.sql_modules m JOIN sys.objects o ON o.object_id=m.object_id WHERE o.name IN('sp_ERP_ProcesarVenta','sp_ProcesarVentaTransaccional','sp_RegistrarMovimientoKardex','tr_ERP_SolicitudVentaInmutable')").Rows){if($row.H -ne $state.shared.($row.name)){throw "Contrato compartido modificado: $($row.name)"}}
 Write-Output 'PASS hashes de procedimientos compartidos intactos'
 $audit=(Read "SELECT COUNT_BIG(*) N FROM dbo.P3_COT_HistorialEstado h WHERE NOT EXISTS(SELECT 1 FROM dbo.Bitacora_Transacciones b WHERE b.TablaAfectada=N'P3_COT_Cotizacion' AND b.OperacionId=h.OperacionId AND b.ActorUsuarioId=h.ActorUsuarioId)").Rows[0].N
 if($audit -ne 0){throw 'Evento de cotizacion sin auditoria DML'}
 Write-Output 'PASS historial de cotizaciones conciliado con auditoria'
 Run 'DBCC CHECKDB WITH NO_INFOMSGS,ALL_ERRORMSGS;'
 if((Read 'DBCC CHECKCONSTRAINTS WITH ALL_CONSTRAINTS').Rows.Count){throw 'Restricciones incumplidas'}
 Write-Output 'PASS CHECKDB y CHECKCONSTRAINTS'
}finally{$c.Close()}
