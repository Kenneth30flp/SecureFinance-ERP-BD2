# Integraciones reales de multibodega (P3_BOD) contra SecureFinanceERP_Lab_Dylan unicamente.
# Cubre: prueba 19 (venta con ubicacion), prueba 20 (devolucion apta con reingreso local),
# prueba 21 (devolucion defectuosa sin reingreso), verificacion de Kardex y regresion
# de conciliacion + auditoria DML cruzada (Kenneth/COT, Edward/devolucion, Dylan/Kardex).
# Requiere actor sintetico P3_DYLAN_QA_ADMIN. No toca bases protegidas ni credenciales.
# Salida: consola + %TEMP%\opencode\P3_BOD_Integraciones.json.
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
Add-Type -AssemblyName System.Data

$LAB_DB = 'SecureFinanceERP_Lab_Dylan'
[int]$script:actor = 0
$int = [System.Data.SqlDbType]::Int
$uid = [System.Data.SqlDbType]::UniqueIdentifier
$vc = [System.Data.SqlDbType]::VarChar
$nv = [System.Data.SqlDbType]::NVarChar
$bin = [System.Data.SqlDbType]::Binary
$dec = [System.Data.SqlDbType]::Decimal
$dt2 = [System.Data.SqlDbType]::DateTime2

function New-Conn {
    $b = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $b.set_DataSource('localhost'); $b.set_InitialCatalog($LAB_DB)
    $b.set_IntegratedSecurity($true); $b.set_Encrypt($true); $b.set_TrustServerCertificate($true)
    $b.set_ApplicationName('Dylan-Integraciones-P3BOD'); $b.set_ConnectTimeout(15); $b.set_Pooling($false)
    $c = New-Object System.Data.SqlClient.SqlConnection($b.ConnectionString)
    $c.Open()
    if ((Invoke-ScalarQuery $c "SELECT CASE WHEN DB_NAME() COLLATE Latin1_General_100_BIN2=N'$LAB_DB' AND @@TRANCOUNT=0 AND SESSION_CONTEXT(N'P3_BOD.BodegaId') IS NULL THEN 1 ELSE 0 END" @{}) -ne 1) {
        $c.Dispose(); throw "Destino no autorizado: debe ser $LAB_DB, sin transaccion ni contexto de bodega"
    }
    return $c
}
function Add-Param($cmd, $name, $type, $len, $val) {
    $p = $cmd.Parameters.Add("@$name", $type, $len)
    if ($type -eq $dec) { $p.Precision = 19; $p.Scale = 2 }
    if ($null -ne $val) { $p.Value = $val }
    return $p
}
function Read-SingleRow([System.Data.SqlClient.SqlCommand]$cmd) {
    $dr = $cmd.ExecuteReader()
    try { if ($dr.Read()) { if ($dr.IsDBNull(0)) { return $null } return $dr.GetValue(0) } return $null }
    finally { $dr.Dispose() }
}
function Invoke-ScalarQuery($conn, $sql, $map) {
    $c = $conn.CreateCommand(); $c.CommandText = $sql; $c.CommandTimeout = 60
    foreach ($p in $map.GetEnumerator()) { Add-Param $c $p.Key $p.Value.SqlType $p.Value.Length $p.Value.Value | Out-Null }
    try { return Read-SingleRow $c } finally { $c.Dispose() }
}
function Invoke-Rpc($conn, $proc, $map) {
    $cmd = $conn.CreateCommand(); $cmd.CommandType = 'StoredProcedure'; $cmd.CommandText = $proc; $cmd.CommandTimeout = 60
    foreach ($p in $map.GetEnumerator()) { Add-Param $cmd $p.Key $p.Value.SqlType $p.Value.Length $p.Value.Value | Out-Null }
    try {
        $v = Read-SingleRow $cmd
        return @{ ok = $true; respuesta = $v; number = $null; mensaje = $null }
    } catch [System.Data.SqlClient.SqlException] {
        return @{ ok = $false; respuesta = $null; number = $_.Exception.Number; mensaje = $_.Exception.Message; proc = $_.Exception.Procedure.ToString() }
    } finally { $cmd.Dispose() }
}
function Set-ContextBodega($conn, $bodega) {
    $cmd = $conn.CreateCommand(); $cmd.CommandText = 'EXEC sys.sp_set_session_context @key=N''P3_BOD.BodegaId'', @value=@b, @read_only=0'
    Add-Param $cmd 'b' $int 0 $bodega | Out-Null
    [void]$cmd.ExecuteNonQuery(); $cmd.Dispose()
}
function Clear-ContextBodega($conn) {
    $cmd = $conn.CreateCommand(); $cmd.CommandText = 'EXEC sys.sp_set_session_context @key=N''P3_BOD.BodegaId'', @value=NULL, @read_only=0'
    [void]$cmd.ExecuteNonQuery(); $cmd.Dispose()
}
function Get-Json([System.Data.SqlClient.SqlConnection]$conn, [string]$sql, $map) {
    $v = Invoke-ScalarQuery $conn $sql $map
    if ($null -eq $v) { return $null } else { return ($v | ConvertFrom-Json) }
}
function To-J([object]$text, [string]$name) {
    if ($null -eq $text -or "$text".Trim().Length -eq 0) { throw ("{0}: respuesta vacia del procedimiento" -f $name) }
    return ($text | ConvertFrom-Json)
}

$report = [ordered]@{}
$script:stage = 'inicio'
$connMain = New-Conn
try {
    $script:actor = [int](Invoke-ScalarQuery $connMain "SELECT UsuarioId FROM dbo.Usuario WHERE NombreUsuario=N'P3_DYLAN_QA_ADMIN'" @{})
    if (-not $script:actor) { throw 'Falta actor sintetico P3_DYLAN_QA_ADMIN' }

    # ---- F0: contexto: producto conciliado con stock local en central y bodegas activas
    if (([int](Invoke-ScalarQuery $connMain "SELECT COUNT(*) FROM dbo.P3_BOD_Bodega WHERE BodegaId IN (1,2,3) AND Activo=1" @{})) -ne 3) { throw 'Bodegas 1/2/3 no estan activas' }
    $ProductoId = [int](Invoke-ScalarQuery $connMain @"
SELECT TOP(1) p2.ProductoId FROM dbo.Producto p2
JOIN dbo.P3_BOD_Stock s ON s.ProductoId=p2.ProductoId AND s.BodegaId=1 AND s.Cantidad>=10
WHERE p2.Activo=1 AND p2.Stock>=10
ORDER BY p2.ProductoId DESC
"@ @{})
    if (-not $ProductoId) { throw 'No hay producto conciliado con stock suficiente en Central' }
    $PStock = [int](Invoke-ScalarQuery $connMain "SELECT Stock FROM dbo.Producto WHERE ProductoId=@p" @{ p = @{ SqlType = $int; Length = 0; Value = $ProductoId } })
    $CENTRAL = 1; $Z1 = 2; $Z10 = 3
    $report['contexto'] = [ordered]@{ producto = $ProductoId; stock = $PStock }
    $motivo = 'QA integraciones P3 BOD'

    # ---- F1: transferencia central -> Z10 (8 unidades), completa y conciliada
    $uT = [System.Guid]::NewGuid().ToString()
    $script:stage = 'F1'
    $z10A = [int](Invoke-ScalarQuery $connMain "SELECT COALESCE((SELECT Cantidad FROM dbo.P3_BOD_Stock WHERE ProductoId=@p AND BodegaId=@b),0)" @{ p = @{ SqlType = $int; Length = 0; Value = $ProductoId }; b = @{ SqlType = $int; Length = 0; Value = $Z10 } })
    $stockA = $PStock
    $tres = Invoke-Rpc $connMain 'dbo.sp_TransferirStockBodegas' @{
        ActorUsuarioId = @{ SqlType = $int; Length = 0; Value = $script:actor }
        OperacionId = @{ SqlType = $uid; Length = 0; Value = $([System.Guid]::Parse($uT)) }
        ProductoId = @{ SqlType = $int; Length = 0; Value = $ProductoId }
        OrigenId = @{ SqlType = $int; Length = 0; Value = $CENTRAL }
        DestinoId = @{ SqlType = $int; Length = 0; Value = $Z10 }
        Cantidad = @{ SqlType = $int; Length = 0; Value = 8 }
        Motivo = @{ SqlType = $nv; Length = 250; Value = $motivo }
    }
    $tjson = To-J $tres.respuesta 'sp_TransferirStockBodegas'
    $Tid = [int]$tjson.TransferenciaId
    $ver1 = Invoke-ScalarQuery $connMain "SELECT Version FROM dbo.P3_BOD_Transferencia WHERE TransferenciaId=@t" @{ t = @{ SqlType = $int; Length = 0; Value = $Tid } }
    $v1bytes = [byte[]]$ver1
    $dres = Invoke-Rpc $connMain 'dbo.P3_BOD_AvanzarTransferencia' @{
        ActorUsuarioId = @{ SqlType = $int; Length = 0; Value = $script:actor }
        OperacionId = @{ SqlType = $uid; Length = 0; Value = $([System.Guid]::NewGuid()) }
        TransferenciaId = @{ SqlType = $int; Length = 0; Value = $Tid }
        Accion = @{ SqlType = $vc; Length = 10; Value = 'DESPACHAR' }
        VersionEsperada = @{ SqlType = $bin; Length = 8; Value = $v1bytes }
        Motivo = @{ SqlType = $nv; Length = 250; Value = $motivo }
    }
    $ver2 = Invoke-ScalarQuery $connMain "SELECT Version FROM dbo.P3_BOD_Transferencia WHERE TransferenciaId=@t" @{ t = @{ SqlType = $int; Length = 0; Value = $Tid } }
    $rres = Invoke-Rpc $connMain 'dbo.P3_BOD_AvanzarTransferencia' @{
        ActorUsuarioId = @{ SqlType = $int; Length = 0; Value = $script:actor }
        OperacionId = @{ SqlType = $uid; Length = 0; Value = $([System.Guid]::NewGuid()) }
        TransferenciaId = @{ SqlType = $int; Length = 0; Value = $Tid }
        Accion = @{ SqlType = $vc; Length = 10; Value = 'RECIBIR' }
        VersionEsperada = @{ SqlType = $bin; Length = 8; Value = [byte[]]$ver2 }
        Motivo = @{ SqlType = $nv; Length = 250; Value = $motivo }
    }
    $est1 = [string](Invoke-ScalarQuery $connMain "SELECT Estado FROM dbo.P3_BOD_Transferencia WHERE TransferenciaId=@t" @{ t = @{ SqlType = $int; Length = 0; Value = $Tid } })
    $z10local = [int](Invoke-ScalarQuery $connMain "SELECT Cantidad FROM dbo.P3_BOD_Stock WHERE ProductoId=@p AND BodegaId=@b" @{ p = @{ SqlType = $int; Length = 0; Value = $ProductoId }; b = @{ SqlType = $int; Length = 0; Value = $Z10 } })
    $report['F1_transferencia'] = [ordered]@{ t = $Tid; estado = $est1; z10Local = $z10local; preparar = $tres.ok; despachar = $dres.ok; recibir = $rres.ok }
    $report['F1_PASS'] = [bool]($tres.ok -and $dres.ok -and $rres.ok -and $est1 -eq 'RECIBIDA' -and $z10local -eq ($z10A + 8) -and $PStock -eq $stockA)

    $script:stage = 'F2'
    if (-not $tres.ok) { throw ('F1 preparar fallo: ' + $tres.number + ' ' + $tres.mensaje) }
    if (-not $dres.ok) { throw ('F1 despachar fallo: ' + $dres.number + ' ' + $dres.mensaje) }
    if (-not $rres.ok) { throw ('F1 recibir fallo: ' + $rres.number + ' ' + $rres.mensaje) }

    # ---- F2: PRUEBA 19 - venta con ubicacion: cotizacion -> conversion con salida en Z10
    $uCot = [System.Guid]::NewGuid().ToString()
    $uVen = [System.Guid]::NewGuid().ToString()
    $cliente = [int](Invoke-ScalarQuery $connMain "SELECT TOP(1) ClienteId FROM dbo.Cliente WHERE Activo=1 ORDER BY ClienteId" @{})
    if (-not $cliente) { throw 'Sin cliente activo para cotizacion' }
    $cmd = $connMain.CreateCommand(); $cmd.CommandType = 'StoredProcedure'; $cmd.CommandText = 'dbo.P3_COT_Crear'; $cmd.CommandTimeout = 60
    Add-Param $cmd 'ActorUsuarioId' $int 0 $script:actor | Out-Null
    Add-Param $cmd 'ClienteId' $int 0 $cliente | Out-Null
    $vence = Invoke-ScalarQuery $connMain "SELECT DATEADD(DAY,2,SYSUTCDATETIME())" @{}
    Add-Param $cmd 'VenceEn' $dt2 0 $vence | Out-Null
    $tvp = New-Object System.Data.DataTable
    [void]$tvp.Columns.Add('ProductoId', [int])
    [void]$tvp.Columns.Add('Cantidad', [int])
    [void]$tvp.Columns.Add('DescuentoPorcentaje', [decimal])
    [void]$tvp.Rows.Add(@($ProductoId, 2, [decimal]0.00))
    $ptv = $cmd.Parameters.Add('@Detalle', [System.Data.SqlDbType]::Structured)
    $ptv.TypeName = 'dbo.TipoDetalleVentaDescuento'; $ptv.Value = $tvp
    Add-Param $cmd 'OperacionId' $uid 0 $([System.Guid]::Parse($uCot)) | Out-Null
    Add-Param $cmd 'Observaciones' $nv 2000 $motivo | Out-Null
    $cotjson = Read-SingleRow $cmd; $cmd.Dispose()
    $report['f2_cotjson'] = [string]$cotjson
    $uch = [string]$cotjson
    if ($uch -match '^\s*\{') {
        $cot = To-J $cotjson 'P3_COT_Crear'
        $CotId = [int]$cot.CotizacionId
    } else {
        $CotId = [int]$cotjson
    }
    $report['f2_cotid'] = $CotId
    if (-not $CotId -or $CotId -lt 1) { throw 'P3_COT_Crear no devolvio un CotizacionId valido' }
    $z10B = [int](Invoke-ScalarQuery $connMain "SELECT Cantidad FROM dbo.P3_BOD_Stock WHERE ProductoId=@p AND BodegaId=@b" @{ p = @{ SqlType = $int; Length = 0; Value = $ProductoId }; b = @{ SqlType = $int; Length = 0; Value = $Z10 } })
    $stockB = [int](Invoke-ScalarQuery $connMain "SELECT Stock FROM dbo.Producto WHERE ProductoId=@p" @{ p = @{ SqlType = $int; Length = 0; Value = $ProductoId } })
    $vres = Invoke-Rpc $connMain 'dbo.P3_BOD_ConvertirCotizacion' @{
        ActorUsuarioId = @{ SqlType = $int; Length = 0; Value = $script:actor }
        CotizacionId = @{ SqlType = $int; Length = 0; Value = $CotId }
        OperacionId = @{ SqlType = $uid; Length = 0; Value = $([System.Guid]::Parse($uVen)) }
        BodegaId = @{ SqlType = $int; Length = 0; Value = $Z10 }
        Credito = @{ SqlType = [System.Data.SqlDbType]::Bit; Length = 0; Value = $false }
        PlazoDias = @{ SqlType = $int; Length = 0; Value = $null }
        NumeroCuotas = @{ SqlType = $int; Length = 0; Value = 1 }
    }
    if (-not $vres.ok) { throw ('F2 conversion fallo: ' + $vres.number + ' ' + $vres.mensaje + ' PROC=' + $vres.proc) }
    $FacturaId = [int](Invoke-ScalarQuery $connMain "SELECT FacturaId FROM dbo.P3_COT_Cotizacion WHERE CotizacionId=@c" @{ c = @{ SqlType = $int; Length = 0; Value = $CotId } })
    if (-not $FacturaId) { throw ('La conversion no produjo factura para cotizacion ' + $CotId) }
    $detalleId = [int](Invoke-ScalarQuery $connMain "SELECT TOP(1) DetalleFacturaId FROM dbo.DetalleFactura WHERE FacturaId=@f ORDER BY DetalleFacturaId" @{ f = @{ SqlType = $int; Length = 0; Value = $FacturaId } })
    # El motor de Kenneth asigna su propio OperacionId al Kardex de venta; se deriva desde el Ledger local Z10.
    $kVenta = [int](Invoke-ScalarQuery $connMain "SELECT TOP(1) COALESCE(KardexId,0) FROM dbo.P3_BOD_Ledger WHERE ProductoId=@p AND BodegaId=@b AND Tipo='VENTA' AND FechaHora>DATEADD(MINUTE,-2,SYSUTCDATETIME()) ORDER BY MovimientoId DESC" @{ p = @{ SqlType = $int; Length = 0; Value = $ProductoId }; b = @{ SqlType = $int; Length = 0; Value = $Z10 } })
    $ledgerVenta = [int](Invoke-ScalarQuery $connMain "SELECT COUNT(*) FROM dbo.P3_BOD_Ledger WHERE KardexId=@k" @{ k = @{ SqlType = [System.Data.SqlDbType]::BigInt; Length = 0; Value = $kVenta } })
    $vz10 = [int](Invoke-ScalarQuery $connMain "SELECT Cantidad FROM dbo.P3_BOD_Stock WHERE ProductoId=@p AND BodegaId=@b" @{ p = @{ SqlType = $int; Length = 0; Value = $ProductoId }; b = @{ SqlType = $int; Length = 0; Value = $Z10 } })
    $vstock = [int](Invoke-ScalarQuery $connMain "SELECT Stock FROM dbo.Producto WHERE ProductoId=@p" @{ p = @{ SqlType = $int; Length = 0; Value = $ProductoId } })
    $impl = Get-Json $connMain "SELECT ValorNuevo FROM dbo.Bitacora_Transacciones WHERE OperacionId=@o AND TablaAfectada=N'P3_COT_Cotizacion'" @{ o = @{ SqlType = $uid; Length = 0; Value = $([System.Guid]::Parse($uCot)) } }
    $report['F2_venta_ubicacion'] = [ordered]@{ cotizacion = $CotId; factura = $FacturaId; kardexId = $kVenta; ledgerVenta = $ledgerVenta; z10Antes = $z10B; z10Convertir = $vz10; stockAntes = $stockB; stockGlobal = $vstock }
    $report['F2_PASS'] = [bool]($vres.ok -and $FacturaId -gt 0 -and $kVenta -gt 0 -and $ledgerVenta -ge 1 -and $vz10 -eq ($z10B - 2) -and $vstock -eq ($stockB - 2) -and $impl)

    # ---- F3: PRUEBA 20 - devolucion APTA con reingreso en Z10 (contexto de bodega)
    $script:stage = 'F3'
    $z10C = $vz10
    $stockC = $vstock
    $uDev = [System.Guid]::NewGuid().ToString()
    Set-ContextBodega $connMain $Z10
    $dres = Invoke-Rpc $connMain 'dbo.sp_ProcesarDevolucionCliente' @{
        ActorUsuarioId = @{ SqlType = $int; Length = 0; Value = $script:actor }
        FacturaId = @{ SqlType = $int; Length = 0; Value = $FacturaId }
        OperacionId = @{ SqlType = $uid; Length = 0; Value = $([System.Guid]::Parse($uDev)) }
        Motivo = @{ SqlType = $nv; Length = 500; Value = 'Devolucion apta reintegra a ubicacion' }
        Detalles = @{ SqlType = $nv; Length = 4000; Value = ('[{"DetalleFacturaId":' + $detalleId + ',"Cantidad":1,"Reingresar":true}]') }
    }
    Clear-ContextBodega $connMain
    $resultDir = [ordered]@{}
    if (-not $dres.ok) { $resultDir['error'] = ('' + $dres.number + ': ' + $dres.mensaje) }
    $kDev = [int](Invoke-ScalarQuery $connMain "SELECT KardexId FROM dbo.Kardex_Inventario WHERE TipoMovimiento='DEVOLUCION' AND OperacionId=@o" @{ o = @{ SqlType = $uid; Length = 0; Value = $([System.Guid]::Parse($uDev)) } })
    $ledgerDev = [int](Invoke-ScalarQuery $connMain "SELECT COUNT(*) FROM dbo.P3_BOD_Ledger WHERE OperacionId=@o AND Tipo='DEVOLUCION'" @{ o = @{ SqlType = $uid; Length = 0; Value = $([System.Guid]::Parse($uDev)) } })
    $z10PostDev = [int](Invoke-ScalarQuery $connMain "SELECT Cantidad FROM dbo.P3_BOD_Stock WHERE ProductoId=@p AND BodegaId=@b" @{ p = @{ SqlType = $int; Length = 0; Value = $ProductoId }; b = @{ SqlType = $int; Length = 0; Value = $Z10 } })
    $stockPostDev = [int](Invoke-ScalarQuery $connMain "SELECT Stock FROM dbo.Producto WHERE ProductoId=@p" @{ p = @{ SqlType = $int; Length = 0; Value = $ProductoId } })
    $notaDev = [int](Invoke-ScalarQuery $connMain "SELECT COUNT(*) FROM dbo.NotaCredito n JOIN dbo.DevolucionCliente d ON d.DevolucionId=n.DevolucionId WHERE d.OperacionId=@o" @{ o = @{ SqlType = $uid; Length = 0; Value = $([System.Guid]::Parse($uDev)) } })
    $bitDev = [int](Invoke-ScalarQuery $connMain "SELECT COUNT(*) FROM dbo.Bitacora_Transacciones WHERE OperacionId=@o" @{ o = @{ SqlType = $uid; Length = 0; Value = $([System.Guid]::Parse($uDev)) } })
    $linkDev = [int](Invoke-ScalarQuery $connMain "SELECT COUNT(*) FROM dbo.DevolucionKardex k JOIN dbo.Kardex_Inventario i ON i.KardexId=k.KardexId JOIN dbo.P3_BOD_Ledger l ON l.KardexId=k.KardexId WHERE i.OperacionId=@o" @{ o = @{ SqlType = $uid; Length = 0; Value = $([System.Guid]::Parse($uDev)) } })
    $report['F3_devolucion_apta'] = [ordered]@{ operacion = $uDev; ok = $dres.ok; error = $resultDir.error; kardexId = $kDev; ledgerDev = $ledgerDev; z10 = $z10PostDev; stockGlobal = $stockPostDev; notaCredito = $notaDev; bitacoraDML = $bitDev; linkLedgerKardex = $linkDev }
    $report['F3_PASS'] = [bool]($dres.ok -and $kDev -gt 0 -and $ledgerDev -eq 1 -and $z10PostDev -eq ($z10C + 1) -and $stockPostDev -eq ($stockC + 1) -and $notaDev -eq 1 -and $bitDev -ge 1 -and $linkDev -eq 1)

    # ---- F4: PRUEBA 21 - devolucion DEFECTUOSA sin reingreso (no Kardex, sin stock local)
    $script:stage = 'F4'
    $z10D = [int](Invoke-ScalarQuery $connMain "SELECT Cantidad FROM dbo.P3_BOD_Stock WHERE ProductoId=@p AND BodegaId=@b" @{ p = @{ SqlType = $int; Length = 0; Value = $ProductoId }; b = @{ SqlType = $int; Length = 0; Value = $Z10 } })
    $stockD = [int](Invoke-ScalarQuery $connMain "SELECT Stock FROM dbo.Producto WHERE ProductoId=@p" @{ p = @{ SqlType = $int; Length = 0; Value = $ProductoId } })
    $uDev2 = [System.Guid]::NewGuid().ToString()
    $uDev2 = [System.Guid]::NewGuid().ToString()
    Set-ContextBodega $connMain $Z10
    $dres2 = Invoke-Rpc $connMain 'dbo.sp_ProcesarDevolucionCliente' @{
        ActorUsuarioId = @{ SqlType = $int; Length = 0; Value = $script:actor }
        FacturaId = @{ SqlType = $int; Length = 0; Value = $FacturaId }
        OperacionId = @{ SqlType = $uid; Length = 0; Value = $([System.Guid]::Parse($uDev2)) }
        Motivo = @{ SqlType = $nv; Length = 500; Value = 'Devolucion defectuosa sin reingreso vendible' }
        Detalles = @{ SqlType = $nv; Length = 4000; Value = ('[{"DetalleFacturaId":' + $detalleId + ',"Cantidad":1,"Reingresar":false}]') }
    }
    Clear-ContextBodega $connMain
    $resultDir = [ordered]@{}
    if (-not $dres2.ok) { $resultDir['error'] = ('' + $dres2.number + ': ' + $dres2.mensaje) }
    $kDev2 = [int](Invoke-ScalarQuery $connMain "SELECT COUNT(*) FROM dbo.Kardex_Inventario WHERE OperacionId=@o" @{ o = @{ SqlType = $uid; Length = 0; Value = $([System.Guid]::Parse($uDev2)) } })
    $ledgerDev2 = [int](Invoke-ScalarQuery $connMain "SELECT COUNT(*) FROM dbo.P3_BOD_Ledger WHERE OperacionId=@o" @{ o = @{ SqlType = $uid; Length = 0; Value = $([System.Guid]::Parse($uDev2)) } })
    $z10PostDev2 = [int](Invoke-ScalarQuery $connMain "SELECT Cantidad FROM dbo.P3_BOD_Stock WHERE ProductoId=@p AND BodegaId=@b" @{ p = @{ SqlType = $int; Length = 0; Value = $ProductoId }; b = @{ SqlType = $int; Length = 0; Value = $Z10 } })
    $stockPostDev2 = [int](Invoke-ScalarQuery $connMain "SELECT Stock FROM dbo.Producto WHERE ProductoId=@p" @{ p = @{ SqlType = $int; Length = 0; Value = $ProductoId } })
    $notaDev2 = [int](Invoke-ScalarQuery $connMain "SELECT COUNT(*) FROM dbo.NotaCredito n JOIN dbo.DevolucionCliente d ON d.DevolucionId=n.DevolucionId WHERE d.OperacionId=@o" @{ o = @{ SqlType = $uid; Length = 0; Value = $([System.Guid]::Parse($uDev2)) } })
    $bitDev2 = [int](Invoke-ScalarQuery $connMain "SELECT COUNT(*) FROM dbo.Bitacora_Transacciones WHERE OperacionId=@o" @{ o = @{ SqlType = $uid; Length = 0; Value = $([System.Guid]::Parse($uDev2)) } })
    $report['F4_devolucion_defectuosa'] = [ordered]@{ operacion = $uDev2; ok = $dres2.ok; error = $resultDir.error; kardexFilas = $kDev2; ledgerFilas = $ledgerDev2; z10 = $z10PostDev2; stockGlobal = $stockPostDev2; notaCredito = $notaDev2; bitacoraDML = $bitDev2 }
    # defectuosa: nota generada, sin Kardex ni ledger, sin movimientos de stock, con auditoria DML
    $report['F4_PASS'] = [bool]($dres2.ok -and $kDev2 -eq 0 -and $ledgerDev2 -eq 0 -and $z10PostDev2 -eq $z10D -and $stockPostDev2 -eq $stockD -and $notaDev2 -eq 1 -and $bitDev2 -ge 1)

    # ---- F5: verificacion de Kardex: ledger <-> Kardex, sin duplicados globales
    $mismatch = [int](Invoke-ScalarQuery $connMain @"
SELECT COUNT(*) FROM dbo.P3_BOD_Ledger l
JOIN dbo.Kardex_Inventario k ON k.KardexId=l.KardexId
WHERE l.OperacionId IN (@o,@o2) AND (k.OperacionId<>l.OperacionId OR k.UsuarioId<>l.ActorUsuarioId OR k.Cantidad<>l.Cantidad)
"@ @{
        o = @{ SqlType = $uid; Length = 0; Value = $([System.Guid]::Parse($uVen)) }
        o2 = @{ SqlType = $uid; Length = 0; Value = $([System.Guid]::Parse($uDev)) }
    })
    $dupKardex = [int](Invoke-ScalarQuery $connMain "SELECT COUNT(*) FROM (SELECT OperacionId, COUNT(*) c FROM dbo.Kardex_Inventario WHERE OperacionId IN (@o,@o2) GROUP BY OperacionId, TipoMovimiento, LineaOperacion HAVING COUNT(*)>1) x" @{
        o = @{ SqlType = $uid; Length = 0; Value = $([System.Guid]::Parse($uVen)) }
        o2 = @{ SqlType = $uid; Length = 0; Value = $([System.Guid]::Parse($uDev)) }
    })
    $report['F5_kardex'] = [ordered]@{ mismatchLedgerKardex = $mismatch; kardexDuplicados = $dupKardex }
    $report['F5_PASS'] = [bool]($mismatch -eq 0 -and $dupKardex -eq 0)

    # ---- F6: regresion: conciliacion integral + auditoria DML cruzada vigente
    $saldoOk = [int](Invoke-ScalarQuery $connMain "SELECT COUNT(*) FROM dbo.P3_BOD_Conciliacion WHERE Diferencia<>0" @{})
    $totalFilas = [int](Invoke-ScalarQuery $connMain "SELECT COUNT(*) FROM dbo.P3_BOD_Conciliacion" @{})
    $historia = [int](Invoke-ScalarQuery $connMain "SELECT COUNT(*) FROM dbo.Bitacora_Transacciones WHERE OperacionId IN (@oT,@oC,@oD1,@oD2)" @{
        oT = @{ SqlType = $uid; Length = 0; Value = $([System.Guid]::Parse($uT)) }
        oC = @{ SqlType = $uid; Length = 0; Value = $([System.Guid]::Parse($uCot)) }
        oD1 = @{ SqlType = $uid; Length = 0; Value = $([System.Guid]::Parse($uDev)) }
        oD2 = @{ SqlType = $uid; Length = 0; Value = $([System.Guid]::Parse($uDev2)) }
    })
    $evT = [int](Invoke-ScalarQuery $connMain "SELECT COUNT(*) FROM dbo.Bitacora_Transacciones WHERE OperacionId=@o" @{ o = @{ SqlType = $uid; Length = 0; Value = $([System.Guid]::Parse($uT)) } })
    $evC = [int](Invoke-ScalarQuery $connMain "SELECT COUNT(*) FROM dbo.Bitacora_Transacciones WHERE OperacionId=@o" @{ o = @{ SqlType = $uid; Length = 0; Value = $([System.Guid]::Parse($uCot)) } })
    $evD1 = [int](Invoke-ScalarQuery $connMain "SELECT COUNT(*) FROM dbo.Bitacora_Transacciones WHERE OperacionId=@o" @{ o = @{ SqlType = $uid; Length = 0; Value = $([System.Guid]::Parse($uDev)) } })
    $evD2 = [int](Invoke-ScalarQuery $connMain "SELECT COUNT(*) FROM dbo.Bitacora_Transacciones WHERE OperacionId=@o" @{ o = @{ SqlType = $uid; Length = 0; Value = $([System.Guid]::Parse($uDev2)) } })
    $validarSaldo = [string](Invoke-ScalarQuery $connMain "SELECT CONVERT(VARCHAR(30), (SELECT COALESCE(SUM(Diferencia),0) FROM dbo.P3_BOD_Conciliacion))" @{})
    $report['F6_regresion'] = [ordered]@{ filasConDiferencia = $saldoOk; filasTotal = $totalFilas; eventosTransferencia = $evT; eventosCotizacion = $evC; eventosDevolucionApta = $evD1; eventosDevolucionDefectuosa = $evD2; eventosDMLCruzados = $historia; saldoGlobalTexto = $validarSaldo }
    # auditoria DML cruzada: cada operacion del ciclo deja registro >=1 y la conciliacion integral sigue en 0
    $report['F6_PASS'] = [bool]($saldoOk -eq 0 -and $evT -ge 1 -and $evC -ge 1 -and $evD1 -ge 1 -and $evD2 -ge 1 -and $historia -ge 4)

    $report['timestamp_local'] = (Get-Date).ToString('o')
    $resumenJson = $report | ConvertTo-Json -Depth 6
    $resumenJson | Set-Content -Path (Join-Path $env:TEMP 'opencode\P3_BOD_Integraciones.json') -Encoding UTF8
    Write-Host "---- RESULTADO ----"
    foreach ($k in @('F1_PASS', 'F2_PASS', 'F3_PASS', 'F4_PASS', 'F5_PASS', 'F6_PASS')) { Write-Host ("{0}={1}" -f $k, $report[$k]) }
    Write-Host $resumenJson
    if (-not ($report['F1_PASS'] -and $report['F2_PASS'] -and $report['F3_PASS'] -and $report['F4_PASS'] -and $report['F5_PASS'] -and $report['F6_PASS'])) { exit 1 }
} catch {
    Write-Host ('MAIN_ERR [etapa ' + $script:stage + '] ' + $_.Exception.Message)
    try { $report | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $env:TEMP 'opencode\P3_BOD_Integraciones_diag.json') -Encoding UTF8; Write-Host 'DIAG guardado en P3_BOD_Integraciones_diag.json' } catch { }
    if ($_.Exception.Message -match 'otro flujo|utlizada') { Write-Host 'NOTA: referencia ya consumida en corrida previa; use una corrida nueva.' }
    exit 2
} finally { $connMain.Dispose() }
