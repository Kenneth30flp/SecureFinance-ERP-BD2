# Concurrencia real de multibodega (P3_BOD): dos sesiones SqlClient contra SecureFinanceERP_Lab_Dylan.
# Requiere actor sintetico P3_DYLAN_QA_ADMIN y transferencias sinteticas creadas por este propio runner.
# No toca bases protegidas; no cambia TLS; no modifica credenciales; prueba SOLO el laboratorio Dylan.
# Cada sesion replica el patron del servicio: BEGIN TRAN -> EXEC -> COMMIT / rechazo con rollback.
# Salida: console log + JSON final (tambien queda en %TEMP%\opencode\P3_BOD_Concurrencias.json).
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
Add-Type -AssemblyName System.Data

$LAB_DB = 'SecureFinanceERP_Lab_Dylan'
$int = [System.Data.SqlDbType]::Int
$uid = [System.Data.SqlDbType]::UniqueIdentifier
$vc = [System.Data.SqlDbType]::VarChar
$nv = [System.Data.SqlDbType]::NVarChar
$bin = [System.Data.SqlDbType]::Binary

function New-Conn {
    $b = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $b.set_DataSource('localhost'); $b.set_InitialCatalog($LAB_DB)
    $b.set_IntegratedSecurity($true); $b.set_Encrypt($true); $b.set_TrustServerCertificate($true)
    $b.set_ApplicationName('Dylan-Concurrencias-P3BOD'); $b.set_ConnectTimeout(15); $b.set_Pooling($false)
    $c = New-Object System.Data.SqlClient.SqlConnection($b.ConnectionString)
    $c.Open()
    $g = $c.CreateCommand()
    $g.CommandText = "SELECT CASE WHEN DB_NAME() COLLATE Latin1_General_100_BIN2=N'$LAB_DB' AND @@TRANCOUNT=0 THEN 1 ELSE 0 END"
    if ($g.ExecuteScalar() -ne 1) { $c.Dispose(); throw "Destino no autorizado: no es el laboratorio $LAB_DB" }
    return $c
}
function Add-Param($cmd, $name, $type, $len, $val) {
    $p = $cmd.Parameters.Add("@$name", $type, $len)
    if ($null -ne $val) { $p.Value = $val }
}
function Read-SingleRow([System.Data.SqlClient.SqlCommand]$cmd) {
    $dr = $cmd.ExecuteReader()
    try { if ($dr.Read()) { if ($dr.IsDBNull(0)) { return $null } return $dr.GetValue(0) } return $null }
    finally { $dr.Dispose() }
}
function Get-VersionBytes($conn, $tid) {
    # Version es rowversion(binary 8): capturar como bytes, nunca hex de texto.
    return Invoke-ScalarQuery $conn "SELECT Version FROM dbo.P3_BOD_Transferencia WHERE TransferenciaId=@t" @{ t = @{ SqlType = $int; Length = 0; Value = $tid } }
}
# Ejecuta una llamada de una sesion; captura fila o numero de error.
function Invoke-Session {
    param([System.Data.SqlClient.SqlConnection]$conn, [string]$Sql, [hashtable]$Params, [ref]$Watch)
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $Sql; $cmd.CommandTimeout = 45
    foreach ($p in $Params.GetEnumerator()) { Add-Param $cmd $p.Key $p.Value.SqlType $p.Value.Length $p.Value.Value }
    $Watch.Value = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $dr = $cmd.ExecuteReader()
        try {
            $v = $null
            if ($dr.Read() -and (-not $dr.IsDBNull(0))) { $v = $dr[0] }
            return @{ ok = $true; respuesta = $v; number = $null }
        } finally { $dr.Dispose() }
    } catch [System.Data.SqlClient.SqlException] {
        return @{ ok = $false; respuesta = $null; number = $_.Exception.Number }
    } catch {
        Write-Host ('SESSION_ERR ' + $_.Exception.Message)
        return @{ ok = $false; respuesta = $null; number = $null }
    } finally { $Watch.Value.Stop(); $cmd.Dispose() }
}
function Invoke-ScalarQuery($conn, $sql, $map) {
    $c = $conn.CreateCommand(); $c.CommandText = $sql; $c.CommandTimeout = 30
    foreach ($p in $map.GetEnumerator()) { Add-Param $c $p.Key $p.Value.SqlType $p.Value.Length $p.Value.Value }
    try { return Read-SingleRow $c } finally { $c.Dispose() }
}
function Invoke-RowQuery($conn, $sql) {
    $c = $conn.CreateCommand(); $c.CommandText = $sql; $c.CommandTimeout = 30
    try {
        $dr = $c.ExecuteReader()
        try { if ($dr.Read()) { $o = @{}; for ($i = 0; $i -lt $dr.FieldCount; $i++) { $o[$dr.GetName($i)] = if ($dr.IsDBNull($i)) { $null } else { $dr.GetValue($i) } }; return $o } return $null }
        finally { $dr.Dispose() }
    } finally { $c.Dispose() }
}
function Count-Ledger($conn, $guidText) {
    [int](Invoke-ScalarQuery $conn "SELECT COUNT(*) FROM dbo.P3_BOD_Ledger WHERE OperacionId=@u" @{ u = @{ SqlType = $uid; Length = 0; Value = $([System.Guid]::Parse($guidText)) } })
}
function Count-Operacion($conn, $guidText) {
    [int](Invoke-ScalarQuery $conn "SELECT COUNT(*) FROM dbo.P3_BOD_Operacion WHERE OperacionId=@u" @{ u = @{ SqlType = $uid; Length = 0; Value = $([System.Guid]::Parse($guidText)) } })
}
function Get-Estado($conn, $tid) {
    Invoke-ScalarQuery $conn "SELECT Estado FROM dbo.P3_BOD_Transferencia WHERE TransferenciaId=@t" @{ t = @{ SqlType = $int; Length = 0; Value = $tid } }
}
# Dos sesiones sobre la misma FASE. A retiene locks 5s; B entra 1.5s despues.
# Llamada identical de B: applock(shared uuid) lo sincroniza; mismo Producto UPDLOCK serializa fases cruzadas.
function Invoke-Competencia {
    param([System.Data.SqlClient.SqlConnection]$connA, [System.Data.SqlClient.SqlConnection]$connB,
        [string]$UuidA, [int]$TidA, [byte[]]$VerA, [string]$MotivoA,
        [string]$UuidB, [int]$TidB, [byte[]]$VerB, [string]$MotivoB,
        [string]$AccionA, [string]$AccionB)
    # El pipeline emite el array como object[]: coercion explicita antes del binding.
    $VerA = [byte[]]$VerA; $VerB = [byte[]]$VerB
    if ($VerA.Length -ne 8 -or $VerB.Length -ne 8) { throw 'Version no son 8 bytes' }
    $cmdA = $connA.CreateCommand()
    $cmdA.CommandText = "BEGIN TRANSACTION; EXEC dbo.P3_BOD_AvanzarTransferencia @ActorUsuarioId=@Actor,@OperacionId=@UuidA,@TransferenciaId=@TidA,@Accion=@AccionA,@VersionEsperada=@VerA,@Motivo=@MotivoA; WAITFOR DELAY '00:00:05'; COMMIT;"
    $cmdA.CommandTimeout = 45
    Add-Param $cmdA 'Actor' $int 0 $script:actor
    Add-Param $cmdA 'UuidA' $uid 0 $([System.Guid]::Parse($UuidA))
    Add-Param $cmdA 'TidA' $int 0 $TidA
    Add-Param $cmdA 'AccionA' $vc 10 $AccionA
    Add-Param $cmdA 'VerA' $bin 8 $VerA
    Add-Param $cmdA 'MotivoA' $nv 250 $MotivoA
    $ar = $cmdA.BeginExecuteNonQuery()
    Start-Sleep -Milliseconds 1500 # A ya retiene su applock y su UPDLOCK/HOLDLOCK del Producto antes de abrir B.
    $bParams = @{ Actor = @{ SqlType = $int; Length = 0; Value = $script:actor }
        OpB = @{ SqlType = $uid; Length = 0; Value = $([System.Guid]::Parse($UuidB)) }
        TidB = @{ SqlType = $int; Length = 0; Value = $TidB }
        AccionB = @{ SqlType = $vc; Length = 10; Value = $AccionB }
        VerB = @{ SqlType = $bin; Length = 8; Value = $VerB }
        MotivoB = @{ SqlType = $nv; Length = 250; Value = $MotivoB }
    }
    $textoB = "BEGIN TRANSACTION; EXEC dbo.P3_BOD_AvanzarTransferencia @ActorUsuarioId=@Actor,@OperacionId=@OpB,@TransferenciaId=@TidB,@Accion=@AccionB,@VersionEsperada=@VerB,@Motivo=@MotivoB; COMMIT;"
    $sw = New-Object System.Diagnostics.Stopwatch
    $resB = Invoke-Session $connB $textoB $bParams ([ref]$sw)
    $bloqueoMs = $sw.ElapsedMilliseconds
    try { $cmdA.EndExecuteNonQuery($ar) | Out-Null } finally { $cmdA.Dispose() }
    return [ordered]@{ sesionB_ok = $resB.ok; number = $resB.number; respuesta = $resB.respuesta; bloqueoMs = $bloqueoMs }
}
function New-Transferencia {
    param([System.Data.SqlClient.SqlConnection]$conn, [int]$ProductoId, [int]$OrigenId, [int]$DestinoId, [int]$Cantidad, [string]$Motivo)
    $guid = [System.Guid]::NewGuid().ToString()
    $cmd = $conn.CreateCommand(); $cmd.CommandType = 'StoredProcedure'; $cmd.CommandTimeout = 30
    $cmd.CommandText = 'dbo.sp_TransferirStockBodegas'
    Add-Param $cmd 'ActorUsuarioId' $int 0 $script:actor
    Add-Param $cmd 'OperacionId' $uid 0 $([System.Guid]::Parse($guid))
    Add-Param $cmd 'ProductoId' $int 0 $ProductoId
    Add-Param $cmd 'OrigenId' $int 0 $OrigenId
    Add-Param $cmd 'DestinoId' $int 0 $DestinoId
    Add-Param $cmd 'Cantidad' $int 0 $Cantidad
    Add-Param $cmd 'Motivo' $nv 250 $Motivo
    try {
        $r = Read-SingleRow $cmd
        if ($null -eq $r) { throw "Propuesta fallida" }
        $o = $r | ConvertFrom-Json
        return [ordered]@{ uuid = $guid; id = [int]$o.TransferenciaId; respuesta = $r }
    } finally { $cmd.Dispose() }
}
# ------------------------------------------------------------------ main
$script:actor = 0
$connMain = New-Conn
$report = [ordered]@{}
try {
    $script:actor = [int](Invoke-ScalarQuery $connMain "SELECT UsuarioId FROM dbo.Usuario WHERE NombreUsuario=N'P3_DYLAN_QA_ADMIN'" @{})
    if (-not $script:actor) { throw 'Falta actor sintetico P3_DYLAN_QA_ADMIN' }
    $row = Invoke-RowQuery $connMain @"
SELECT s.ProductoId, s.BodegaId OrigenId, s.Cantidad,
 (SELECT TOP(1) d.BodegaId FROM dbo.P3_BOD_Bodega d WHERE d.Activo=1 AND d.BodegaId<>s.BodegaId ORDER BY d.BodegaId) DestinoId
FROM dbo.P3_BOD_Stock s
JOIN dbo.P3_BOD_Bodega b ON b.BodegaId=s.BodegaId AND b.Activo=1
JOIN dbo.Producto p ON p.ProductoId=s.ProductoId AND p.Activo=1
WHERE s.Cantidad>=10 AND EXISTS(SELECT 1 FROM dbo.P3_BOD_Bodega dd WHERE dd.Activo=1 AND dd.BodegaId<>s.BodegaId)
ORDER BY s.Cantidad DESC
"@
    if ($null -eq $row) { throw 'No hay bodega activa con stock suficiente' }
    $ProductoId = [int]$row.ProductoId; $OrigenId = [int]$row.OrigenId; $DestinoId = [int]$row.DestinoId
    $S = [int]$row.Cantidad
    Write-Host ("producto={0} origen={1} destino={2} stock={3}" -f $ProductoId, $OrigenId, $DestinoId, $S)
    $report['contexto'] = [ordered]@{ producto = $ProductoId; origen = $OrigenId; destino = $DestinoId; stock = $S }
    $motivoBase = 'QA concurrencia P3 BOD'
    # ---- C1 mismo despacho / mismo UUID y carga en la FASE (el GUID de la propuesta es otro)
    $t1 = New-Transferencia $connMain $ProductoId $OrigenId $DestinoId 2 $motivoBase
    $v1 = Get-VersionBytes $connMain $t1.id
    $uD1 = [System.Guid]::NewGuid().ToString()
    $cB1 = New-Conn
    try {
        $rC1 = Invoke-Competencia $connMain $cB1 $uD1 $t1.id $v1 $motivoBase $uD1 $t1.id $v1 $motivoBase 'DESPACHAR' 'DESPACHAR'
        $oper1 = Count-Operacion $connMain $uD1
        $ledger1 = Count-Ledger $connMain $uD1
        $estado1 = Get-Estado $connMain $t1.id
        $report['C1_mismo_uuid'] = [ordered]@{ t = $t1.id; sesionB = $rC1; operacion = $oper1; ledger = $ledger1; estado = $estado1 }
        $report['C1_PASS'] = [bool]($rC1.sesionB_ok -and $rC1.respuesta -and ($rC1.respuesta -like '*DESPACHADA*') -and $oper1 -eq 1 -and $ledger1 -eq 1 -and $estado1 -eq 'DESPACHADA')
    } finally { $cB1.Dispose() }
    # ---- C2 mismo UUID de fase con carga distinta
    $t2 = New-Transferencia $connMain $ProductoId $OrigenId $DestinoId 2 $motivoBase
    $v2 = Get-VersionBytes $connMain $t2.id
    $uD2 = [System.Guid]::NewGuid().ToString()
    $cB2 = New-Conn
    try {
        $rC2 = Invoke-Competencia $connMain $cB2 $uD2 $t2.id $v2 $motivoBase $uD2 $t2.id $v2 'Motivo alterno de la sesion B' 'DESPACHAR' 'DESPACHAR'
        $oper2 = Count-Operacion $connMain $uD2
        $report['C2_uuid_otra_carga'] = [ordered]@{ t = $t2.id; sesionB = $rC2; operacion = $oper2 }
        $report['C2_PASS'] = [bool]((-not $rC2.ok) -and $rC2.number -eq 58003 -and $oper2 -eq 1)
    } finally { $cB2.Dispose() }
    # ---- C3 recepcion duplicada con la version original
    $verDespacho = [byte[]](Get-VersionBytes $connMain $t1.id)
    $u3a = [System.Guid]::NewGuid().ToString()
    $u3b = [System.Guid]::NewGuid().ToString()
    $cB3 = New-Conn
    try {
        $bParams = @{ Actor = @{ SqlType = $int; Length = 0; Value = $script:actor }
            OpB = @{ SqlType = $uid; Length = 0; Value = $([System.Guid]::Parse($u3b)) }
            TidB = @{ SqlType = $int; Length = 0; Value = $t1.id }
            AccionB = @{ SqlType = $vc; Length = 10; Value = 'RECIBIR' }
            VerB = @{ SqlType = $bin; Length = 8; Value = $verDespacho }
            MotivoB = @{ SqlType = $nv; Length = 250; Value = $motivoBase }
        }
        $textoB = "BEGIN TRANSACTION; EXEC dbo.P3_BOD_AvanzarTransferencia @ActorUsuarioId=@Actor,@OperacionId=@OpB,@TransferenciaId=@TidB,@Accion=@AccionB,@VersionEsperada=@VerB,@Motivo=@MotivoB; COMMIT;"
        $cmdA = $connMain.CreateCommand()
        $cmdA.CommandText = "BEGIN TRANSACTION; EXEC dbo.P3_BOD_AvanzarTransferencia @ActorUsuarioId=@Actor,@OperacionId=@UuidA,@TransferenciaId=@TidB,@Accion=@AccionB,@VersionEsperada=@VerB,@Motivo=@MotivoB2; WAITFOR DELAY '00:00:05'; COMMIT;"
        $cmdA.CommandTimeout = 45
        Add-Param $cmdA 'Actor' $int 0 $script:actor
        Add-Param $cmdA 'UuidA' $uid 0 $([System.Guid]::Parse($u3a))
        Add-Param $cmdA 'TidB' $int 0 $t1.id
        Add-Param $cmdA 'AccionB' $vc 10 'RECIBIR'
        Add-Param $cmdA 'VerB' $bin 8 $verDespacho
        Add-Param $cmdA 'MotivoB2' $nv 250 $motivoBase
        $ar = $cmdA.BeginExecuteNonQuery()
        Start-Sleep -Milliseconds 1500
        $sw = New-Object System.Diagnostics.Stopwatch
        $resB = Invoke-Session $cB3 $textoB $bParams ([ref]$sw)
        try { $cmdA.EndExecuteNonQuery($ar) | Out-Null } finally { $cmdA.Dispose() }
        $ledgerB = Count-Ledger $connMain $u3b
        $estado3 = Get-Estado $connMain $t1.id
        $report['C3_doble_recepcion'] = [ordered]@{ t = $t1.id; sesionB = $resB; ledgerB = $ledgerB; estado = $estado3 }
        $report['C3_PASS'] = [bool]((-not $resB.ok) -and $resB.number -eq 58003 -and $ledgerB -eq 0 -and $estado3 -eq 'RECIBIDA')
    } finally { $cB3.Dispose() }
    # ---- C4 dos despachos compiten por origen (A toma T3; B intenta T4)
    $qtyC4 = [Math]::Floor($S / 2) + 1
    $t3 = New-Transferencia $connMain $ProductoId $OrigenId $DestinoId $qtyC4 $motivoBase
    $t4 = New-Transferencia $connMain $ProductoId $OrigenId $DestinoId $qtyC4 $motivoBase
    $v3 = Get-VersionBytes $connMain $t3.id
    $v4 = Get-VersionBytes $connMain $t4.id
    $uD4a = [System.Guid]::NewGuid().ToString()
    $uD4b = [System.Guid]::NewGuid().ToString()
    $cB4 = New-Conn
    try {
        $rC4 = Invoke-Competencia $connMain $cB4 $uD4a $t3.id $v3 $motivoBase $uD4b $t4.id $v4 $motivoBase 'DESPACHAR' 'DESPACHAR'
        $ledger4 = Count-Ledger $connMain $uD4b
        $estado4 = Get-Estado $connMain $t4.id
        $report['C4_dos_despachos'] = [ordered]@{ t3 = $t3.id; t4 = $t4.id; sesionB = $rC4; ledgerT4 = $ledger4; estadoT4 = $estado4; cantidad = $qtyC4 }
        $report['C4_PASS'] = [bool]($rC4.number -eq 58005 -and $ledger4 -eq 0 -and $estado4 -eq 'PREPARADA')
    } finally { $cB4.Dispose() }
    # ---- conciliacion final
    $dif = [int](Invoke-ScalarQuery $connMain "SELECT COUNT(*) FROM dbo.P3_BOD_Conciliacion WHERE Diferencia<>0" @{})
    $total = [int](Invoke-ScalarQuery $connMain "SELECT COUNT(*) FROM dbo.P3_BOD_Conciliacion" @{})
    $report['conciliacion'] = [ordered]@{ filasConDiferencia = $dif; filasTotal = $total }
    $report['CONCILIACION_PASS'] = ($dif -eq 0)
    $report['timestamp_local'] = (Get-Date).ToString('o')
    $resumenJson = $report | ConvertTo-Json -Depth 6
    $resumenJson | Set-Content -Path (Join-Path $env:TEMP 'opencode\P3_BOD_Concurrencias.json') -Encoding UTF8
    Write-Host "---- RESULTADO ----"
    foreach ($k in @('C1_PASS', 'C2_PASS', 'C3_PASS', 'C4_PASS', 'CONCILIACION_PASS')) { Write-Host ("{0}={1}" -f $k, $report[$k]) }
    Write-Host $resumenJson
    if (-not ($report['C1_PASS'] -and $report['C2_PASS'] -and $report['C3_PASS'] -and $report['C4_PASS'] -and $report['CONCILIACION_PASS'])) { exit 1 }
} catch {
    Write-Host ('MAIN_ERR ' + $_.Exception.Message)
    exit 2
} finally { $connMain.Dispose() }
