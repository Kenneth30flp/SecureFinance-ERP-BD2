$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$state=Get-Content (Join-Path $root '.data/cotizaciones-demo.json') -Raw|ConvertFrom-Json
if($state.lab -notmatch '^SecureFinanceERP_P3_COT_DEMO_[0-9]{14}_[a-f0-9]{8}$'){throw 'Solo demostracion aislada'}
$c=New-Object System.Data.SqlClient.SqlConnection "Server=$($state.server);Database=$($state.lab);Integrated Security=True;Encrypt=True;TrustServerCertificate=True;Application Name=SecureFinance-Demo-Verify;Pooling=False"
function Read([string]$s){$cmd=$c.CreateCommand();$cmd.CommandTimeout=180;$cmd.CommandText=$s;$t=New-Object System.Data.DataTable;$r=$cmd.ExecuteReader();$t.Load($r);$r.Close();return ,$t}
function Run([string]$s){$cmd=$c.CreateCommand();$cmd.CommandTimeout=180;$cmd.CommandText=$s;[void]$cmd.ExecuteNonQuery()}
$c.Open();try{
 if((Read 'SELECT DB_NAME() N').Rows[0].N -ne $state.lab){throw 'Base incorrecta'}
 $qa=(Read "SELECT (SELECT COUNT(*) FROM dbo.Producto WHERE Descripcion LIKE N'QA %')+(SELECT COUNT(*) FROM dbo.Cliente WHERE Nombre LIKE N'Cliente QA%' OR Nombre LIKE N'QA UC09%') N").Rows[0].N
 if($qa -ne 0){throw 'La demostracion contiene registros de automatizacion'}
 $count=(Read 'SELECT COUNT(*) N FROM dbo.P3_COT_Cotizacion').Rows[0].N
 if($count -ne 5){throw 'Los ejecutores escribieron en demostracion o existe actividad manual; revisar sin borrar'}
 $states=@{};foreach($row in (Read 'SELECT EstadoVigente,COUNT(*) N FROM dbo.P3_COT_Vigencias() GROUP BY EstadoVigente').Rows){$states[$row.EstadoVigente]=[int]$row.N}
 if($states.ACTIVA -ne 2 -or $states.PROCESADA -ne 1 -or $states.CANCELADA -ne 1 -or $states.VENCIDA -ne 1){throw 'Estados de demostracion inesperados'}
 $original=(Read "SELECT CONVERT(varchar(64),HASHBYTES('SHA2_256',CONVERT(varbinary(max),(SELECT * FROM dbo.Factura WHERE FacturaId<(SELECT MIN(FacturaId) FROM dbo.P3_COT_Cotizacion WHERE FacturaId IS NOT NULL) ORDER BY FacturaId FOR JSON PATH,INCLUDE_NULL_VALUES))),2) H").Rows[0].H
 if($original -ne $state.originalInvoiceHash){throw 'Cambio inesperado en facturas originales del respaldo'}
 Run "EXECUTE AS USER='securefinance_app'; EXEC dbo.P3_COT_PrepararFormulario @ActorUsuarioId=$($state.actor); EXEC dbo.P3_COT_BuscarCatalogo @ActorUsuarioId=$($state.actor),@Clase='productos'; EXEC dbo.P3_COT_EstadoConversion @ActorUsuarioId=$($state.actor),@CotizacionId=1; REVERT;"
 Run 'DBCC CHECKDB WITH NO_INFOMSGS,ALL_ERRORMSGS;';if((Read 'DBCC CHECKCONSTRAINTS WITH ALL_CONSTRAINTS').Rows.Count){throw 'Restricciones incumplidas'}
 $report=@{database=$state.lab;qaRecords=[int]$qa;quotes=[int]$count;states=$states;invoiceHashPreserved=$true;applicationExecuteVerified=$true;integrity='PASS';automationWritesToDemo='NONE'}
 $folder=Join-Path $root 'docs/parte3/cotizaciones/redisenio';New-Item -ItemType Directory -Force $folder|Out-Null
 $report|ConvertTo-Json -Depth 5|Set-Content (Join-Path $folder 'demostracion-verificada.json') -Encoding UTF8
 Write-Output "PASS DB_NAME=$($state.lab); cero QA; cinco propuestas originales; historicos y permisos verificados; CHECKDB/CHECKCONSTRAINTS"
}finally{$c.Close()}
