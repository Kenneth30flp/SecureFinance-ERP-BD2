[CmdletBinding()]
param([switch]$ConfiarCertificadoLocal, [switch]$EjecutarPruebas)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not ($ConfiarCertificadoLocal -and $EjecutarPruebas)) {
    'PLAN ONLY: localhost / SecureFinanceERP_Lab_Dylan. Requires -ConfiarCertificadoLocal -EjecutarPruebas. No SQL connection opened.'
    return
}
$evidenceRoot = Join-Path $PSScriptRoot '..\..\docs\parte3\auditoria-ddl'
if (-not (Test-Path -LiteralPath $evidenceRoot -PathType Container)) { throw 'Evidence parent missing.' }
Add-Type -AssemblyName System.Data
$run = [guid]::NewGuid().ToString('N')
$results = New-Object 'System.Collections.Generic.List[object]'
$connections = New-Object 'System.Collections.Generic.List[object]'
$guard = @"
SET NOCOUNT ON; SET XACT_ABORT ON;
SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON; SET ANSI_PADDING ON; SET ANSI_WARNINGS ON;
SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET NUMERIC_ROUNDABORT OFF;
IF CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')) COLLATE Latin1_General_100_BIN2 <> N'DESKTOP-HBNSH7J'
 OR DB_NAME() COLLATE Latin1_General_100_BIN2 <> N'SecureFinanceERP_Lab_Dylan'
 OR DATALENGTH(DB_NAME()) <> DATALENGTH(N'SecureFinanceERP_Lab_Dylan')
 THROW 54980,'Verification target rejected.',1;
"@
function Open-Lab {
    $b = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $b.set_DataSource('localhost'); $b.set_InitialCatalog('SecureFinanceERP_Lab_Dylan')
    $b.set_IntegratedSecurity($true); $b.set_Encrypt($true); $b.set_TrustServerCertificate($true)
    $b.set_AsynchronousProcessing($true); $b.set_Pooling($false); $b.set_ApplicationName('LabDylanSqlVerification')
    $c = New-Object System.Data.SqlClient.SqlConnection($b.ConnectionString)
    try {
        $c.Open()
        $cmd = $c.CreateCommand(); $cmd.CommandText = "SELECT CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')), DB_NAME();"
        $r = $cmd.ExecuteReader()
        try {
            if (-not $r.Read() -or $r.GetString(0) -cne 'DESKTOP-HBNSH7J' -or $r.GetString(1) -cne 'SecureFinanceERP_Lab_Dylan') { throw 'Target rejected.' }
        } finally { $r.Dispose(); $cmd.Dispose() }
        $cmd = $c.CreateCommand(); $cmd.CommandText = $guard; [void]$cmd.ExecuteNonQuery(); $cmd.Dispose()
        $connections.Add($c)
        return $c
    } catch { $c.Dispose(); throw 'Connection or exact-target verification failed (details suppressed).' }
}
function Invoke-QA($Connection, [string]$Sql) {
    $cmd = $Connection.CreateCommand(); $cmd.CommandTimeout = 30; $cmd.CommandText = $guard + "`n" + $Sql
    try {
        $r = $cmd.ExecuteReader()
        try {
            do {
                $capture = $r.FieldCount -gt 0 -and $r.GetName(0) -ceq 'QA'
                while ($r.Read()) {
                    if ($capture) {
                        $row = [ordered]@{}
                        for ($i=0; $i -lt $r.FieldCount; $i++) {
                            $value = $r.GetValue($i)
                            if ($value -is [DBNull]) { $value = $null }
                            $row[$r.GetName($i)] = $value
                        }
                        [pscustomobject]$row
                    }
                }
            } while ($r.NextResult())
        } finally { $r.Dispose() }
    } finally { $cmd.Dispose() }
}
function Record([string]$Case, $Metrics) {
    $results.Add([pscustomobject]@{ case=$Case; code=0; metrics=$Metrics })
    "PASS $Case"
}
function Assert-QA([bool]$Condition, [string]$Code) { if (-not $Condition) { throw $Code } }
function Permission-Case([string]$Name, [string]$Sql, [int]$Expected) {
    $q = Invoke-QA $observer @"
DECLARE @Code int=0;
EXECUTE AS USER=N'securefinance_app';
BEGIN TRY
$Sql
END TRY BEGIN CATCH SET @Code=ERROR_NUMBER(); IF XACT_STATE()<>0 ROLLBACK; END CATCH;
REVERT;
SELECT 1 QA,@Code ResultCode,@@TRANCOUNT TranCount,CASE WHEN SESSION_CONTEXT(N'P3_BOD.BodegaId') IS NULL THEN 1 ELSE 0 END ContextClean;
"@
    $results.Add([pscustomobject]@{case=$Name; code=[int]$q.ResultCode; expected=$Expected; metrics=@{tranCount=$q.TranCount;contextClean=$q.ContextClean}})
    Assert-QA ($q.ResultCode -eq $Expected -and $q.TranCount -eq 0 -and $q.ContextClean -eq 1) "Permission assertion failed: $Name"
    "PASS $Name code=$($q.ResultCode)"
}
function Start-Worker($Connection, [string]$Body, [bool]$Hold) {
    $cmd = $Connection.CreateCommand(); $cmd.CommandTimeout=25
    $holdSql = if ($Hold) { "WAITFOR DELAY '00:00:04';" } else { '' }
    $cmd.CommandText = $guard + @"

SET @ResultCode=0;
BEGIN TRY
BEGIN TRANSACTION;
$Body
$holdSql
COMMIT;
END TRY BEGIN CATCH
 SET @ResultCode=ERROR_NUMBER(); IF XACT_STATE()<>0 ROLLBACK;
END CATCH;
SET @Clean=CASE WHEN @@TRANCOUNT=0 AND SESSION_CONTEXT(N'P3_BOD.BodegaId') IS NULL THEN 1 ELSE 0 END;
"@
    [void]$cmd.Parameters.Add('@ResultCode',[System.Data.SqlDbType]::Int)
    $cmd.Parameters['@ResultCode'].Direction=[System.Data.ParameterDirection]::Output
    [void]$cmd.Parameters.Add('@Clean',[System.Data.SqlDbType]::Int)
    $cmd.Parameters['@Clean'].Direction=[System.Data.ParameterDirection]::Output
    $timer=[System.Diagnostics.Stopwatch]::StartNew()
    $async=$cmd.BeginExecuteNonQuery()
    return [pscustomobject]@{cmd=$cmd;async=$async;timer=$timer}
}
function End-Worker($Worker) {
    try {
        [void]$Worker.cmd.EndExecuteNonQuery($Worker.async); $Worker.timer.Stop()
        return [pscustomobject]@{code=[int]$Worker.cmd.Parameters['@ResultCode'].Value;clean=[int]$Worker.cmd.Parameters['@Clean'].Value;ms=$Worker.timer.ElapsedMilliseconds}
    } finally { $Worker.cmd.Dispose() }
}
function Concurrent-Case([string]$Name,[string]$BodyA,[string]$BodyB,[int]$ExpectedB) {
    $a=Open-Lab; $b=Open-Lab
    $aid=(Invoke-QA $a 'SELECT 1 QA,@@SPID SessionId;').SessionId
    $bid=(Invoke-QA $b 'SELECT 1 QA,@@SPID SessionId;').SessionId
    $wa=$null; $wb=$null; $waitA=0; $waitB=0
    try {
        $wa=Start-Worker $a $BodyA $true
        $deadline=[Diagnostics.Stopwatch]::StartNew()
        while ($deadline.ElapsedMilliseconds -lt 3000 -and -not $wa.async.IsCompleted) {
            $q=Invoke-QA $observer "SELECT 1 QA,COUNT(*) Hits FROM sys.dm_exec_requests WHERE database_id=DB_ID() AND session_id=$aid AND command='WAITFOR' AND open_transaction_count>0;"
            if ($q.Hits -eq 1) { $waitA=1; break }; Start-Sleep -Milliseconds 25
        }
        Assert-QA ($waitA -eq 1) "$Name A_WAITFOR_NOT_OBSERVED"
        $wb=Start-Worker $b $BodyB $false
        $deadline.Restart()
        while ($deadline.ElapsedMilliseconds -lt 3000 -and -not $wb.async.IsCompleted) {
            $q=Invoke-QA $observer "SELECT 1 QA,COUNT(*) Hits FROM sys.dm_exec_requests WHERE database_id=DB_ID() AND session_id=$bid AND blocking_session_id=$aid AND wait_type LIKE 'LCK[_]M[_]%' AND start_time>=DATEADD(SECOND,-10,GETDATE());"
            if ($q.Hits -eq 1) { $waitB=1; break }; Start-Sleep -Milliseconds 25
        }
        $ra=End-Worker $wa; $wa=$null; $rb=End-Worker $wb; $wb=$null
        $metrics=@{sessionA=$aid;sessionB=$bid;aWaitforObserved=$waitA;bBlockedByAObserved=$waitB;codeA=$ra.code;codeB=$rb.code;cleanA=$ra.clean;cleanB=$rb.clean;msA=$ra.ms;msB=$rb.ms}
        $results.Add([pscustomobject]@{case=$Name;code=$rb.code;expected=$ExpectedB;metrics=$metrics})
        Assert-QA ($waitB -eq 1 -and $ra.code -eq 0 -and $rb.code -eq $ExpectedB -and $ra.clean -eq 1 -and $rb.clean -eq 1) "$Name concurrency assertion failed"
        "PASS $Name A=$($ra.code) B=$($rb.code) observedOverlap=1"
    } finally {
        if ($null -ne $wa) { try { [void](End-Worker $wa) } catch {} }
        if ($null -ne $wb) { try { [void](End-Worker $wb) } catch {} }
        $a.Dispose(); $b.Dispose()
    }
}
$status='FAIL'; $safeFailure=$null
try {
    $observer=Open-Lab
    $actors=Invoke-QA $observer @"
SELECT 1 QA,
 (SELECT UsuarioId FROM dbo.Usuario WHERE NombreUsuario=N'P3_DYLAN_QA_ADMIN' AND Activo=1) AdminId,
 (SELECT UsuarioId FROM dbo.Usuario WHERE NombreUsuario=N'P3_DYLAN_QA_AUDITOR' AND Activo=1) AuditorId,
 (SELECT UsuarioId FROM dbo.Usuario WHERE NombreUsuario=N'P3_DYLAN_QA_DENEGADO' AND Activo=1) DeniedId,
 (SELECT COUNT(*) FROM sys.database_principals WHERE name=N'securefinance_app' AND sid=SUSER_SID(N'SecureFinanceAppRuntime')) MappingCount;
"@
    Assert-QA ($actors.AdminId -gt 0 -and $actors.AuditorId -gt 0 -and $actors.DeniedId -gt 0 -and $actors.MappingCount -eq 1) 'ACTOR_OR_MAPPING_INVALID'
    $admin=[int]$actors.AdminId; $auditor=[int]$actors.AuditorId; $denied=[int]$actors.DeniedId
    Record 'ExistingRuntimeMapping' @{count=$actors.MappingCount}
    Permission-Case 'DDL_SelectDenied' 'SELECT TOP(0) * FROM dbo.Bitacora_DDL;' 229
    Permission-Case 'DDL_UpdateDenied' 'UPDATE dbo.Bitacora_DDL SET NombreObjeto=NombreObjeto WHERE 1=0;' 229
    Permission-Case 'DDL_DeleteDenied' 'DELETE dbo.Bitacora_DDL WHERE 1=0;' 229
    Permission-Case 'DDL_NoInsertOrAlter' @"
IF ISNULL(HAS_PERMS_BY_NAME(N'dbo.Bitacora_DDL',N'OBJECT',N'INSERT'),0)<>0
 OR ISNULL(HAS_PERMS_BY_NAME(N'dbo.Bitacora_DDL',N'OBJECT',N'ALTER'),0)<>0
 OR ISNULL(HAS_PERMS_BY_NAME(DB_NAME(),N'DATABASE',N'ALTER ANY DATABASE DDL TRIGGER'),0)<>0
 THROW 54981,'Unexpected permission.',1;
"@ 0
    foreach ($actor in @($admin,$auditor)) {
        Permission-Case "DDL_ListAuthorized_$actor" "EXEC dbo.P3_DDL_ConsultarBitacora @ActorUsuarioId=$actor,@Limite=1;" 0
        Permission-Case "DDL_DetailAuthorized_$actor" "EXEC dbo.P3_DDL_ConsultarDetalle @ActorUsuarioId=$actor,@BitacoraDdlId=1;" 0
    }
    Permission-Case 'DDL_ListActorDenied' "EXEC dbo.P3_DDL_ConsultarBitacora @ActorUsuarioId=$denied;" 54101
    Permission-Case 'DDL_DetailActorDenied' "EXEC dbo.P3_DDL_ConsultarDetalle @ActorUsuarioId=$denied,@BitacoraDdlId=1;" 54101
    Permission-Case 'Credit_QueryActorDenied' "EXEC dbo.P3_CRE_Consultar @ActorUsuarioId=$denied;" 54101
    Permission-Case 'Credit_PaymentActorDenied' "DECLARE @op uniqueidentifier=NEWID(); EXEC dbo.sp_RegistrarAbonoCliente $denied,1,1,1,N'QA denied',@op;" 54101
    Permission-Case 'BOD_QueryActorDenied' "EXEC dbo.P3_BOD_Consultar $denied,'bodegas';" 54101
    Permission-Case 'BOD_MutatorActorDenied' "DECLARE @op uniqueidentifier=NEWID(); EXEC dbo.sp_TransferirStockBodegas $denied,@op,1,1,2,1,N'QA denied';" 54101

    $fixture=Invoke-QA $observer @"
BEGIN TRY
BEGIN TRANSACTION;
DECLARE @Client int,@Product int,@Quote int,@Invoice int,@v binary(8),@op uniqueidentifier=NEWID(),@profile uniqueidentifier=NEWID(),@quoteOp uniqueidentifier=NEWID(),@sale uniqueidentifier=NEWID(),@expires datetime2(3)=DATEADD(DAY,1,SYSUTCDATETIME());
INSERT dbo.Cliente(NIT,Nombre) VALUES(N'Q'+LEFT(N'$run',24),N'Synthetic concurrent credit'); SET @Client=CONVERT(int,SCOPE_IDENTITY());
INSERT dbo.Producto(Codigo,Descripcion,Precio,Stock) VALUES(N'QC-$run',N'Synthetic concurrent credit',1785.71,0); SET @Product=CONVERT(int,SCOPE_IDENTITY());
SELECT @v=Version FROM dbo.Producto WHERE ProductoId=@Product;
EXEC dbo.sp_RegistrarMovimientoKardex @ProductoId=@Product,@TipoMovimiento='AJUSTE_INGRESO',@Cantidad=1,@ActorUsuarioId=$admin,@DocumentoRespaldo=N'QA_CONCURRENT',@OperacionId=@op,@LineaOperacion=1,@Motivo=N'Synthetic isolated fixture',@VersionEsperada=@v,@DevolverResultado=0;
EXEC dbo.P3_CRE_AdministrarCredito $admin,@Client,1,5000,30,NULL,N'Synthetic concurrent profile',@profile;
DECLARE @details dbo.TipoDetalleVentaDescuento; INSERT @details VALUES(@Product,1,0);
EXEC dbo.P3_COT_Crear $admin,@Client,@expires,@details,@quoteOp,N'Synthetic concurrent quote';
SELECT @Quote=CotizacionId FROM dbo.P3_COT_Cotizacion WHERE OperacionId=@quoteOp;
EXEC dbo.P3_CRE_ConvertirCotizacionCredito $admin,@Quote,@sale,30,1,NULL;
SELECT @Invoice=FacturaId FROM dbo.P3_COT_Cotizacion WHERE CotizacionId=@Quote;
IF NOT EXISTS(SELECT 1 FROM dbo.P3_CRE_Cuenta WHERE FacturaId=@Invoice AND Total=2000 AND Saldo=2000 AND NumeroCuotas=1)
 OR EXISTS(SELECT 1 FROM dbo.MovimientoCaja WHERE FacturaId=@Invoice) THROW 54981,'Credit setup assertion.',1;
COMMIT;
SELECT 1 QA,@Client ClientId,@Product ProductId,@Quote QuoteId,@Invoice InvoiceId;
END TRY BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK; THROW; END CATCH;
"@
    $client=[int]$fixture.ClientId; $invoice=[int]$fixture.InvoiceId
    Record 'Credit_Setup' $fixture
    $rollbackOp=[guid]::NewGuid().ToString()
    $q=Invoke-QA $observer @"
BEGIN TRANSACTION;
EXEC dbo.sp_RegistrarAbonoCliente $admin,$client,$invoice,100,N'QA outer rollback','$rollbackOp';
IF NOT EXISTS(SELECT 1 FROM dbo.Abono_Factura WHERE OperacionId='$rollbackOp') THROW 54981,'Rollback success not exercised.',1;
ROLLBACK;
IF EXISTS(SELECT 1 FROM dbo.Abono_Factura WHERE OperacionId='$rollbackOp')
 OR (SELECT Saldo FROM dbo.P3_CRE_Cuenta WHERE FacturaId=$invoice)<>2000
 OR EXISTS(SELECT 1 FROM dbo.MovimientoCaja WHERE FacturaId=$invoice)
 OR EXISTS(SELECT 1 FROM dbo.P3_CRE_ReciboCaja r JOIN dbo.Abono_Factura a ON a.AbonoId=r.AbonoId WHERE a.FacturaId=$invoice)
 OR (SELECT SUM(Abonado) FROM dbo.P3_CRE_Cuota WHERE FacturaId=$invoice)<>0
 THROW 54981,'Credit rollback leaked effects.',1;
SELECT 1 QA,@@TRANCOUNT TranCount,CASE WHEN SESSION_CONTEXT(N'P3_BOD.BodegaId') IS NULL THEN 1 ELSE 0 END ContextClean;
"@
    Assert-QA ($q.TranCount -eq 0 -and $q.ContextClean -eq 1) 'CREDIT_ROLLBACK_CLEANUP'
    Record 'Credit_OuterRollback' $q
    $paymentOp=[guid]::NewGuid().ToString()
    $pay="EXEC dbo.sp_RegistrarAbonoCliente $admin,$client,$invoice,500,N'QA concurrent replay','$paymentOp';"
    Concurrent-Case 'Credit_SameUUID' $pay $pay 0
    $q=Invoke-QA $observer @"
IF (SELECT COUNT(*) FROM dbo.Abono_Factura WHERE FacturaId=$invoice)<>1
 OR (SELECT COUNT(*) FROM dbo.P3_CRE_ReciboCaja r JOIN dbo.Abono_Factura a ON a.AbonoId=r.AbonoId WHERE a.FacturaId=$invoice)<>1
 OR (SELECT Saldo FROM dbo.P3_CRE_Cuenta WHERE FacturaId=$invoice)<>1500
 OR NOT EXISTS(SELECT 1 FROM dbo.Abono_Factura WHERE OperacionId='$paymentOp' AND SaldoPosterior=1500 AND Monto=500)
 OR EXISTS(SELECT 1 FROM dbo.MovimientoCaja WHERE FacturaId=$invoice) THROW 54981,'Replay assertion.',1;
SELECT 1 QA,a.AbonoId,r.ReciboId,a.SaldoPosterior FROM dbo.Abono_Factura a JOIN dbo.P3_CRE_ReciboCaja r ON r.AbonoId=a.AbonoId WHERE a.OperacionId='$paymentOp';
"@
    Record 'Credit_SameUUID_ImmutableSingleReceipt' $q
    $opA=[guid]::NewGuid().ToString(); $opB=[guid]::NewGuid().ToString()
    Concurrent-Case 'Credit_DistinctUUID_Overpayment' "EXEC dbo.sp_RegistrarAbonoCliente $admin,$client,$invoice,1500,N'QA concurrent settle','$opA';" "EXEC dbo.sp_RegistrarAbonoCliente $admin,$client,$invoice,1500,N'QA concurrent settle','$opB';" 57006
    $q=Invoke-QA $observer @"
DECLARE @payments int=(SELECT COUNT(*) FROM dbo.Abono_Factura WHERE FacturaId=$invoice),@receipts int=(SELECT COUNT(*) FROM dbo.P3_CRE_ReciboCaja r JOIN dbo.Abono_Factura a ON a.AbonoId=r.AbonoId WHERE a.FacturaId=$invoice),@sum decimal(19,2)=(SELECT SUM(Monto) FROM dbo.Abono_Factura WHERE FacturaId=$invoice),@available decimal(19,2)=(SELECT Limite FROM dbo.Credito_Cliente WHERE ClienteId=$client)-(SELECT SUM(Saldo) FROM dbo.P3_CRE_Cuenta WHERE ClienteId=$client);
IF @payments<>2 OR @receipts<>2 OR @sum<>2000 OR @available<>5000 OR (SELECT Saldo FROM dbo.P3_CRE_Cuenta WHERE FacturaId=$invoice)<>0 OR EXISTS(SELECT 1 FROM dbo.MovimientoCaja WHERE FacturaId=$invoice) THROW 54981,'Settlement assertion.',1;
SELECT 1 QA,@payments Payments,@receipts Receipts,@sum AmountSum,@available Available,(SELECT Saldo FROM dbo.P3_CRE_Cuenta WHERE FacturaId=$invoice) Balance;
"@
    Record 'Credit_FinalReconciliation' $q

    $bod=Invoke-QA $observer @"
BEGIN TRY
BEGIN TRANSACTION;
DECLARE @p int,@o int=(SELECT BodegaId FROM dbo.P3_BOD_Bodega WHERE IsCentral=1 AND Activo=1),@d int=(SELECT MIN(BodegaId) FROM dbo.P3_BOD_Bodega WHERE IsCentral=0 AND Activo=1),@v binary(8),@stockOp uniqueidentifier=NEWID(),@a uniqueidentifier=NEWID(),@b uniqueidentifier=NEWID();
IF @o IS NULL OR @d IS NULL THROW 54981,'Missing active warehouses.',1;
INSERT dbo.Producto(Codigo,Descripcion,Precio,Stock) VALUES(N'QB-$run',N'Synthetic concurrent warehouse',25,0); SET @p=CONVERT(int,SCOPE_IDENTITY());
SELECT @v=Version FROM dbo.Producto WHERE ProductoId=@p;
EXEC dbo.sp_RegistrarMovimientoKardex @ProductoId=@p,@TipoMovimiento='AJUSTE_INGRESO',@Cantidad=100,@ActorUsuarioId=$admin,@DocumentoRespaldo=N'QA_CONCURRENT',@OperacionId=@stockOp,@LineaOperacion=1,@Motivo=N'Synthetic isolated fixture',@VersionEsperada=@v,@DevolverResultado=0;
EXEC dbo.sp_TransferirStockBodegas $admin,@a,@p,@o,@d,80,N'Synthetic concurrent A';
EXEC dbo.sp_TransferirStockBodegas $admin,@b,@p,@o,@d,80,N'Synthetic concurrent B';
IF NOT EXISTS(SELECT 1 FROM dbo.P3_BOD_Conciliacion WHERE ProductoId=@p AND Stock=100 AND StockLocal=100 AND Transito=0 AND Diferencia=0) THROW 54981,'Warehouse setup assertion.',1;
COMMIT;
SELECT 1 QA,@p ProductId,@o OriginId,@d DestinationId,
 (SELECT MIN(TransferenciaId) FROM dbo.P3_BOD_Transferencia WHERE ProductoId=@p) TransferA,
 (SELECT MAX(TransferenciaId) FROM dbo.P3_BOD_Transferencia WHERE ProductoId=@p) TransferB,
 (SELECT CONVERT(varchar(16),CONVERT(binary(8),Version),2) FROM dbo.P3_BOD_Transferencia WHERE TransferenciaId=(SELECT MIN(TransferenciaId) FROM dbo.P3_BOD_Transferencia WHERE ProductoId=@p)) VersionA,
 (SELECT CONVERT(varchar(16),CONVERT(binary(8),Version),2) FROM dbo.P3_BOD_Transferencia WHERE TransferenciaId=(SELECT MAX(TransferenciaId) FROM dbo.P3_BOD_Transferencia WHERE ProductoId=@p)) VersionB;
END TRY BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK; THROW; END CATCH;
"@
    $product=[int]$bod.ProductId; $ta=[int]$bod.TransferA; $tb=[int]$bod.TransferB
    $va=$bod.VersionA; $vb=$bod.VersionB
    Assert-QA ($va -cmatch '^[0-9A-F]{16}$' -and $vb -cmatch '^[0-9A-F]{16}$') 'BOD_VERSION_FORMAT'
    Record 'BOD_Setup' @{productId=$product;originId=$bod.OriginId;destinationId=$bod.DestinationId;transferA=$ta;transferB=$tb}
    $rollbackOp=[guid]::NewGuid().ToString()
    $q=Invoke-QA $observer @"
DECLARE @before int=(SELECT COUNT(*) FROM dbo.P3_BOD_Ledger WHERE ProductoId=$product);
BEGIN TRANSACTION;
EXEC dbo.P3_BOD_AvanzarTransferencia $admin,'$rollbackOp',$ta,'DESPACHAR',0x$va,N'QA outer rollback';
IF NOT EXISTS(SELECT 1 FROM dbo.P3_BOD_Ledger WHERE OperacionId='$rollbackOp') THROW 54981,'Warehouse rollback not exercised.',1;
ROLLBACK;
IF EXISTS(SELECT 1 FROM dbo.P3_BOD_Ledger WHERE OperacionId='$rollbackOp') OR EXISTS(SELECT 1 FROM dbo.P3_BOD_Operacion WHERE OperacionId='$rollbackOp')
 OR (SELECT COUNT(*) FROM dbo.P3_BOD_Ledger WHERE ProductoId=$product)<>@before
 OR NOT EXISTS(SELECT 1 FROM dbo.P3_BOD_Transferencia WHERE TransferenciaId=$ta AND Estado='PREPARADA' AND Version=0x$va)
 OR NOT EXISTS(SELECT 1 FROM dbo.P3_BOD_Conciliacion WHERE ProductoId=$product AND Stock=100 AND StockLocal=100 AND Transito=0 AND Diferencia=0) THROW 54981,'Warehouse rollback leaked effects.',1;
SELECT 1 QA,@@TRANCOUNT TranCount,CASE WHEN SESSION_CONTEXT(N'P3_BOD.BodegaId') IS NULL THEN 1 ELSE 0 END ContextClean;
"@
    Assert-QA ($q.TranCount -eq 0 -and $q.ContextClean -eq 1) 'BOD_ROLLBACK_CLEANUP'
    Record 'BOD_OuterRollback' $q
    $opA=[guid]::NewGuid().ToString(); $opB=[guid]::NewGuid().ToString()
    Concurrent-Case 'BOD_ConcurrentDispatch80' "EXEC dbo.P3_BOD_AvanzarTransferencia $admin,'$opA',$ta,'DESPACHAR',0x$va,N'QA concurrent dispatch';" "EXEC dbo.P3_BOD_AvanzarTransferencia $admin,'$opB',$tb,'DESPACHAR',0x$vb,N'QA concurrent dispatch';" 58005
    $q=Invoke-QA $observer @"
IF NOT EXISTS(SELECT 1 FROM dbo.P3_BOD_Conciliacion WHERE ProductoId=$product AND Stock=100 AND StockLocal=20 AND Transito=80 AND Diferencia=0)
 OR (SELECT COUNT(*) FROM dbo.P3_BOD_Ledger WHERE TransferenciaId IN($ta,$tb) AND Tipo='TRANSFERENCIA_SALIDA')<>1
 OR NOT EXISTS(SELECT 1 FROM dbo.P3_BOD_Transferencia WHERE TransferenciaId=$tb AND Estado='PREPARADA') THROW 54981,'Warehouse concurrency reconciliation.',1;
SELECT 1 QA,ProductoId,Stock,StockLocal,Transito,Diferencia,(SELECT COUNT(*) FROM dbo.P3_BOD_Ledger WHERE TransferenciaId IN($ta,$tb) AND Tipo='TRANSFERENCIA_SALIDA') ExitLedgerCount FROM dbo.P3_BOD_Conciliacion WHERE ProductoId=$product;
"@
    Record 'BOD_FinalReconciliation' $q
    $status='PASS'
} catch {
    $ex=$_.Exception
    while ($null -ne $ex.InnerException) { $ex=$ex.InnerException }
    if ($ex -is [System.Data.SqlClient.SqlException]) {
        $safeFailure=@{sqlCode=$ex.Number;line=$ex.LineNumber;procedure=$ex.Procedure}
        if ($ex.Number -eq 102 -and $ex.Message -match "near '([0-9A-Fa-fx,;]+)'" ) { $safeFailure['syntaxToken']=$Matches[1] }
    } else {
        # Harness messages are controlled; SQL exception text is never emitted.
        $safeFailure=@{harnessCode='ASSERTION_OR_HARNESS_FAILURE';line=$_.InvocationInfo.ScriptLineNumber}
    }
    'FAIL verification (sanitized details in evidence)'
} finally {
    foreach ($c in $connections) { $c.Dispose() }
    $evidence=[ordered]@{runId=$run;utc=[datetime]::UtcNow.ToString('o');status=$status;cases=$results.ToArray();failure=$safeFailure}
    $path=Join-Path $evidenceRoot "LabDylanSqlVerification-$run.json"
    if (-not (Test-Path -LiteralPath $evidenceRoot -PathType Container)) { throw 'Evidence parent missing.' }
    [IO.File]::WriteAllText($path,($evidence | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false)))
    "RESULT $status cases=$($results.Count) evidence=$path"
}
if ($status -ne 'PASS') { throw 'Lab verification failed; see sanitized evidence.' }
