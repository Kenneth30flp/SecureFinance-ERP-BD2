# Concurrencia real de creditos (P3_CRE): dos sesiones SqlClient contra SecureFinanceERP_Lab_Dylan.
# Fixture sintetico PERSISTENTE (sin rollback final): Cliente + Producto + AJUSTE_INGRESO por la
# API de Kardex + perfil via P3_CRE_AdministrarCredito + cotizacion via P3_COT_Crear + conversion
# al credito via P3_CRE_ConvertirCotizacionCredito (extension 76 instalada en lab).
# NUNCA se inserta Factura directamente: la cuenta por cobrar nace del motor compartido.
# C1: replay del mismo OperacionId con mismos datos -> mismo recibo, sin doble abono.
# C2: mismo OperacionId con otros datos -> 57003.
# C3: dos OperacionId distintos compiten por el mismo saldo -> exactamente uno succeede, el otro 57006.
# No toca bases protegidas ni credenciales. Salida: consola + %TEMP%\opencode\P3_CRE_Concurrencias.json.
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
Add-Type -AssemblyName System.Data

$LAB_DB = 'SecureFinanceERP_Lab_Dylan'
[int]$script:actor = 0
$int = [System.Data.SqlDbType]::Int
$big = [System.Data.SqlDbType]::BigInt
$uid = [System.Data.SqlDbType]::UniqueIdentifier
$vc = [System.Data.SqlDbType]::VarChar
$nv = [System.Data.SqlDbType]::NVarChar
$bin = [System.Data.SqlDbType]::Binary
$dec = [System.Data.SqlDbType]::Decimal
$dt2 = [System.Data.SqlDbType]::DateTime2
$bit = [System.Data.SqlDbType]::Bit

function New-Conn {
    param([string]$appName)
    $b = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $b.set_DataSource('localhost'); $b.set_InitialCatalog($LAB_DB)
    $b.set_IntegratedSecurity($true); $b.set_Encrypt($true); $b.set_TrustServerCertificate($true)
    $b.set_ApplicationName($appName); $b.set_ConnectTimeout(15); $b.set_Pooling($false)
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
    if ($null -ne $val) { $p.Value = $val } else { $p.Value = [DBNull]::Value }
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
        return @{ ok = $false; respuesta = $null; number = $_.Exception.Number; mensaje = $_.Exception.Message }
    } finally { $cmd.Dispose() }
}

$report = [ordered]@{}
$script:stage = 'inicio'
$connA = New-Conn -appName 'Dylan-CreConc-A'
$connB = New-Conn -appName 'Dylan-CreConc-B'
try {
    $script:actor = [int](Invoke-ScalarQuery $connA "SELECT UsuarioId FROM dbo.Usuario WHERE NombreUsuario=N'P3_DYLAN_QA_ADMIN'" @{})
    if (-not $script:actor) { throw 'Falta actor sintetico P3_DYLAN_QA_ADMIN' }

    # ---- F1: fixture persistente (perfiles + cotizacion + conversion al credito por el motor compartido)
    $script:stage = 'fixture'
    $marca = [System.Guid]::NewGuid().ToString('N').Substring(0, 10)
    $nit = 'CRE' + $marca
    $codigo = 'P3-CRE-QA-' + $marca
    $cmd = $connA.CreateCommand(); $cmd.CommandText = "INSERT dbo.Cliente(NIT,Nombre) VALUES(@n,N'P3 DYLAN QA concurrencia credito'); SELECT SCOPE_IDENTITY();"
    Add-Param $cmd 'n' $nv 25 $nit | Out-Null
    $Cliente = [int](Read-SingleRow $cmd); $cmd.Dispose()
    if (-not $Cliente) { throw 'No se creo el cliente sintetico' }

    $cmd = $connA.CreateCommand(); $cmd.CommandText = "INSERT dbo.Producto(Codigo,Descripcion,Precio,Stock) VALUES(@c,N'Sintetico P3 CRE concurrencia',1785.71,0); SELECT SCOPE_IDENTITY();"
    Add-Param $cmd 'c' $vc 40 $codigo | Out-Null
    $Producto = [int](Read-SingleRow $cmd); $cmd.Dispose()
    if (-not $Producto) { throw 'No se creo el producto sintetico' }

    # El stock entra SOLO por la API del Kardex central (mitad persona del core).
    $verObj = Invoke-ScalarQuery $connA "SELECT Version FROM dbo.Producto WHERE ProductoId=@p" @{ p = @{ SqlType = $int; Length = 0; Value = $Producto } }
    $verBytes = [byte[]]$verObj
    $ajOp = [System.Guid]::NewGuid()
    $aj = Invoke-Rpc $connA 'dbo.sp_RegistrarMovimientoKardex' @{
        ProductoId = @{ SqlType = $int; Length = 0; Value = $Producto }
        TipoMovimiento = @{ SqlType = $vc; Length = 20; Value = 'AJUSTE_INGRESO' }
        Cantidad = @{ SqlType = $int; Length = 0; Value = 1 }
        ActorUsuarioId = @{ SqlType = $int; Length = 0; Value = $script:actor }
        DocumentoRespaldo = @{ SqlType = $nv; Length = 100; Value = 'P3_CRE_QA_CONC' }
        OperacionId = @{ SqlType = $uid; Length = 0; Value = $ajOp }
        LineaOperacion = @{ SqlType = $int; Length = 0; Value = 1 }
        Motivo = @{ SqlType = $nv; Length = 250; Value = 'Fixture sintetico de concurrencia Dylan' }
        VersionEsperada = @{ SqlType = $bin; Length = 8; Value = $verBytes }
        DevolverResultado = @{ SqlType = $bit; Length = 0; Value = $false }
    }
    if (-not $aj.ok) { throw ('AJUSTE_INGRESO fallo: ' + $aj.number + ' ' + $aj.mensaje) }

    # Perfil de credito para el cliente (persistente).
    $perfilOp = [System.Guid]::NewGuid()
    $perf = Invoke-Rpc $connA 'dbo.P3_CRE_AdministrarCredito' @{
        ActorUsuarioId = @{ SqlType = $int; Length = 0; Value = $script:actor }
        ClienteId = @{ SqlType = $int; Length = 0; Value = $Cliente }
        Activo = @{ SqlType = $bit; Length = 0; Value = $true }
        Limite = @{ SqlType = $dec; Length = 0; Value = [decimal]5000.00 }
        PlazoDias = @{ SqlType = $int; Length = 0; Value = 30 }
        VersionEsperada = @{ SqlType = $bin; Length = 8; Value = $null }
        Motivo = @{ SqlType = $nv; Length = 500; Value = 'Perfil sintetico QA concurrencia Dylan' }
        OperacionId = @{ SqlType = $uid; Length = 0; Value = $perfilOp }
    }
    if (-not $perf.ok) { throw ('Perfil fallo: ' + $perf.number + ' ' + $perf.mensaje) }
    if (([int](Invoke-ScalarQuery $connA "SELECT COUNT(*) FROM dbo.Credito_Cliente WHERE ClienteId=@c AND Limite=5000 AND Activo=1" @{ c = @{ SqlType = $int; Length = 0; Value = $Cliente } })) -ne 1) { throw 'Perfil de credito no coincide' }

    # Cotizacion de exactamente 1785.71 + IVA 214.29 = 2000.00.
    $cmd = $connA.CreateCommand(); $cmd.CommandType = 'StoredProcedure'; $cmd.CommandText = 'dbo.P3_COT_Crear'; $cmd.CommandTimeout = 60
    Add-Param $cmd 'ActorUsuarioId' $int 0 $script:actor | Out-Null
    Add-Param $cmd 'ClienteId' $int 0 $Cliente | Out-Null
    $vence = Invoke-ScalarQuery $connA "SELECT DATEADD(DAY,2,SYSUTCDATETIME())" @{}
    Add-Param $cmd 'VenceEn' $dt2 0 $vence | Out-Null
    $tvp = New-Object System.Data.DataTable
    [void]$tvp.Columns.Add('ProductoId', [int])
    [void]$tvp.Columns.Add('Cantidad', [int])
    [void]$tvp.Columns.Add('DescuentoPorcentaje', [decimal])
    [void]$tvp.Rows.Add(@($Producto, 1, [decimal]0.00))
    $ptv = $cmd.Parameters.Add('@Detalle', [System.Data.SqlDbType]::Structured)
    $ptv.TypeName = 'dbo.TipoDetalleVentaDescuento'; $ptv.Value = $tvp
    $cotOp = [System.Guid]::NewGuid()
    Add-Param $cmd 'OperacionId' $uid 0 $cotOp | Out-Null
    Add-Param $cmd 'Observaciones' $nv 2000 'Conversion al credito QA Dylan' | Out-Null
    $cotRaw = Read-SingleRow $cmd; $cmd.Dispose()
    $CotId = [int]$cotRaw
    if (-not $CotId) { throw 'P3_COT_Crear no devolvio CotizacionId' }
    $totalCot = [decimal](Invoke-ScalarQuery $connA "SELECT Total FROM dbo.P3_COT_Cotizacion WHERE CotizacionId=@c" @{ c = @{ SqlType = $int; Length = 0; Value = $CotId } })
    $report['fixture'] = [ordered]@{ cliente = $Cliente; producto = $Producto; cotizacion = $CotId; total = "$totalCot" }
    if ($totalCot -ne [decimal]2000.00) { throw "El total de la cotizacion no es 2000.00: $totalCot" }

    # Conversion AL CREDITO (extension 76 instalada; sin contexto de bodega).
    $venOp = [System.Guid]::NewGuid()
    $conv = Invoke-Rpc $connA 'dbo.P3_CRE_ConvertirCotizacionCredito' @{
        ActorUsuarioId = @{ SqlType = $int; Length = 0; Value = $script:actor }
        CotizacionId = @{ SqlType = $int; Length = 0; Value = $CotId }
        OperacionId = @{ SqlType = $uid; Length = 0; Value = $venOp }
        PlazoDias = @{ SqlType = $int; Length = 0; Value = 30 }
        NumeroCuotas = @{ SqlType = $int; Length = 0; Value = 2 }
        BodegaId = @{ SqlType = $int; Length = 0; Value = $null }
    }
    if (-not $conv.ok) { throw ('Conversion credito fallo: ' + $conv.number + ' ' + $conv.mensaje) }
    $Factura = [int](Invoke-ScalarQuery $connA "SELECT FacturaId FROM dbo.P3_COT_Cotizacion WHERE CotizacionId=@c AND Estado='PROCESADA'" @{ c = @{ SqlType = $int; Length = 0; Value = $CotId } })
    $saldo0 = [decimal](Invoke-ScalarQuery $connA "SELECT Saldo FROM dbo.P3_CRE_Cuenta WHERE FacturaId=@f AND ClienteId=@c" @{ f = @{ SqlType = $int; Length = 0; Value = $Factura }; c = @{ SqlType = $int; Length = 0; Value = $Cliente } })
    $cuotas = [int](Invoke-ScalarQuery $connA "SELECT COUNT(*) FROM dbo.P3_CRE_Cuota WHERE FacturaId=@f" @{ f = @{ SqlType = $int; Length = 0; Value = $Factura } })
    $conc0 = [decimal](Invoke-ScalarQuery $connA "SELECT COALESCE(SUM(Importe-Abonado),0) FROM dbo.P3_CRE_Cuota WHERE FacturaId=@f" @{ f = @{ SqlType = $int; Length = 0; Value = $Factura } })
    $report['conversion'] = [ordered]@{ factura = $Factura; saldoInicial = "$saldo0"; cuotas = $cuotas; conciliacion = "$conc0" }
    if (-not $Factura) { throw 'La conversion no produjo FacturaId' }
    if ($saldo0 -ne [decimal]2000.00 -or $cuotas -ne 2) { throw 'La cuenta por cobrar no concilia con el credito esperado' }

    # ---- C1: replay del mismo OperacionId con mismos datos (dos sesiones)
    $script:stage = 'C1'
    $u1 = [System.Guid]::NewGuid()
    $r1a = Invoke-Rpc $connA 'dbo.sp_RegistrarAbonoCliente' @{
        ActorUsuarioId = @{ SqlType = $int; Length = 0; Value = $script:actor }
        ClienteId = @{ SqlType = $int; Length = 0; Value = $Cliente }
        FacturaId = @{ SqlType = $int; Length = 0; Value = $Factura }
        Monto = @{ SqlType = $dec; Length = 0; Value = [decimal]300.00 }
        Referencia = @{ SqlType = $nv; Length = 200; Value = 'QA C1 abono original' }
        OperacionId = @{ SqlType = $uid; Length = 0; Value = $u1 }
    }
    $r1b = Invoke-Rpc $connB 'dbo.sp_RegistrarAbonoCliente' @{
        ActorUsuarioId = @{ SqlType = $int; Length = 0; Value = $script:actor }
        ClienteId = @{ SqlType = $int; Length = 0; Value = $Cliente }
        FacturaId = @{ SqlType = $int; Length = 0; Value = $Factura }
        Monto = @{ SqlType = $dec; Length = 0; Value = [decimal]300.00 }
        Referencia = @{ SqlType = $nv; Length = 200; Value = 'QA C1 abono original' }
        OperacionId = @{ SqlType = $uid; Length = 0; Value = $u1 }
    }
    $abonosC1 = [int](Invoke-ScalarQuery $connA "SELECT COUNT(*) FROM dbo.Abono_Factura WHERE OperacionId=@o" @{ o = @{ SqlType = $uid; Length = 0; Value = $u1 } })
    $saldoC1 = [decimal](Invoke-ScalarQuery $connA "SELECT Saldo FROM dbo.P3_CRE_Cuenta WHERE FacturaId=@f" @{ f = @{ SqlType = $int; Length = 0; Value = $Factura } })
    $recibosC1 = [int](Invoke-ScalarQuery $connA "SELECT COUNT(*) FROM dbo.P3_CRE_ReciboCaja r JOIN dbo.Abono_Factura a ON a.AbonoId=r.AbonoId WHERE a.OperacionId=@o" @{ o = @{ SqlType = $uid; Length = 0; Value = $u1 } })
    $report['C1_replay_mismo_uuid'] = [ordered]@{ sesionA = $r1a.ok; sesionB = $r1b.ok; filasAbono = $abonosC1; recibos = $recibosC1; saldoPosterior = "$saldoC1" }
    $report['C1_PASS'] = [bool]($r1a.ok -and $r1b.ok -and $abonosC1 -eq 1 -and $recibosC1 -eq 1 -and $saldoC1 -eq ($saldo0 - [decimal]300.00))

    # ---- C2: mismo OperacionId con OTROS datos -> 57003
    $script:stage = 'C2'
    $r2 = Invoke-Rpc $connB 'dbo.sp_RegistrarAbonoCliente' @{
        ActorUsuarioId = @{ SqlType = $int; Length = 0; Value = $script:actor }
        ClienteId = @{ SqlType = $int; Length = 0; Value = $Cliente }
        FacturaId = @{ SqlType = $int; Length = 0; Value = $Factura }
        Monto = @{ SqlType = $dec; Length = 0; Value = [decimal]300.01 }
        Referencia = @{ SqlType = $nv; Length = 200; Value = 'QA C2 carga distinta' }
        OperacionId = @{ SqlType = $uid; Length = 0; Value = $u1 }
    }
    $saldoC2 = [decimal](Invoke-ScalarQuery $connA "SELECT Saldo FROM dbo.P3_CRE_Cuenta WHERE FacturaId=@f" @{ f = @{ SqlType = $int; Length = 0; Value = $Factura } })
    $report['C2_mismo_uuid_otra_carga'] = [ordered]@{ ok = $r2.ok; numero = $r2.number; mensaje = $r2.mensaje; saldoPosterior = "$saldoC2" }
    $report['C2_PASS'] = [bool]((-not $r2.ok) -and $r2.number -eq 57003 -and $saldoC2 -eq $saldoC1)

    # ---- C3: dos OperacionId distintos compiten por el mismo saldo (1000 + 1000 sobre 1700)
    $script:stage = 'C3'
    $u3a = [System.Guid]::NewGuid(); $u3b = [System.Guid]::NewGuid()
    function New-AbonoCmd($conn, $u, $monto) {
        $cmd = $conn.CreateCommand(); $cmd.CommandType = 'StoredProcedure'
        $cmd.CommandText = 'dbo.sp_RegistrarAbonoCliente'; $cmd.CommandTimeout = 60
        Add-Param $cmd 'ActorUsuarioId' $int 0 $script:actor | Out-Null
        Add-Param $cmd 'ClienteId' $int 0 $Cliente | Out-Null
        Add-Param $cmd 'FacturaId' $int 0 $Factura | Out-Null
        Add-Param $cmd 'Monto' $dec 0 $monto | Out-Null
        Add-Param $cmd 'Referencia' $nv 200 'QA C3 carrera por saldo' | Out-Null
        Add-Param $cmd 'OperacionId' $uid 0 $u | Out-Null
        return $cmd
    }
    $cmdA = New-AbonoCmd $connA $u3a ([decimal]1000.00)
    $cmdB = New-AbonoCmd $connB $u3b ([decimal]1000.00)
    try {
        $arA = $cmdA.BeginExecuteNonQuery()
        Start-Sleep -Milliseconds 50
        $arB = $cmdB.BeginExecuteNonQuery()
    } catch {
        $dump = @()
        foreach ($pp in $cmdA.Parameters) { $dump += ('{0}={1}[{2}]' -f $pp.ParameterName, $pp.Value, $pp.Value.GetType().FullName) }
        throw ('C3 prep fallo: ' + $_.Exception.Message + ' PARAMS ' + ($dump -join '; '))
    }
    $finA = $false; $numA = $null; $finB = $false; $numB = $null
    try { [void]$cmdA.EndExecuteNonQuery($arA); $finA = $true } catch [System.Data.SqlClient.SqlException] { $numA = $_.Exception.Number } finally { $cmdA.Dispose() }
    try { [void]$cmdB.EndExecuteNonQuery($arB); $finB = $true } catch [System.Data.SqlClient.SqlException] { $numB = $_.Exception.Number } finally { $cmdB.Dispose() }
    $saldoC3 = [decimal](Invoke-ScalarQuery $connA "SELECT Saldo FROM dbo.P3_CRE_Cuenta WHERE FacturaId=@f" @{ f = @{ SqlType = $int; Length = 0; Value = $Factura } })
    $concC3 = [decimal](Invoke-ScalarQuery $connA "SELECT COALESCE(SUM(Importe-Abonado),0) FROM dbo.P3_CRE_Cuota WHERE FacturaId=@f" @{ f = @{ SqlType = $int; Length = 0; Value = $Factura } })
    $abonosTot = [int](Invoke-ScalarQuery $connA "SELECT COUNT(*) FROM dbo.Abono_Factura WHERE FacturaId=@f" @{ f = @{ SqlType = $int; Length = 0; Value = $Factura } })
    $es57006 = ($numA -eq 57006) -or ($numB -eq 57006)
    $unoSolo = (($finA -and -not $finB) -or ($finB -and -not $finA))
    $report['C3_carrera_saldo'] = [ordered]@{ A_ok = $finA; A_error = $numA; B_ok = $finB; B_error = $numB; saldoFinal = "$saldoC3"; conciliacionCuotas = "$concC3"; abonosTotalFactura = $abonosTot }
    $report['C3_PASS'] = [bool]($es57006 -and $unoSolo -and $abonosTot -eq 2 -and $saldoC3 -eq ($saldo0 - [decimal]1300.00) -and $saldoC3 -eq $concC3)

    $report['timestamp_local'] = (Get-Date).ToString('o')
    $resumenJson = $report | ConvertTo-Json -Depth 6
    $resumenJson | Set-Content -Path (Join-Path $env:TEMP 'opencode\P3_CRE_Concurrencias.json') -Encoding UTF8
    Write-Host "---- RESULTADO ----"
    foreach ($k in @('C1_PASS', 'C2_PASS', 'C3_PASS')) { Write-Host ("{0}={1}" -f $k, $report[$k]) }
    Write-Host $resumenJson
    if (-not ($report['C1_PASS'] -and $report['C2_PASS'] -and $report['C3_PASS'])) { exit 1 }
} catch {
    Write-Host ('MAIN_ERR [etapa ' + $script:stage + '] ' + $_.Exception.Message)
    try { $report | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $env:TEMP 'opencode\P3_CRE_Concurrencias_diag.json') -Encoding UTF8 } catch { }
    exit 2
} finally {
    $connA.Dispose(); $connB.Dispose()
}
