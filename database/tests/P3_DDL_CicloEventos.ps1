# Ciclo real de eventos DDL (P3_DDL) contra SecureFinanceERP_Lab_Dylan unicamente.
# Verifica: seis eventos vivos (CREATE/ALTER/DROP tabla y procedimiento) con
# ComandoTSql exacto en Bitacora_DDL; metadatos de permisos (GRANT INSERT, DENY
# SELECT/UPDATE/DELETE, DENY IMPERSONATE securefinance_app); EXECUTE AS
# P3_DDL_Escritor bloqueado para leer la bitacora; auditoria DML
# (Bitacora_Transacciones) y auditoria de accesos (rechazo via sp_Login)
# siguen operativas; la interfaz (P3_DDL_ConsultarBitacora) muestra los eventos;
# y aplica la propuesta 95 (guarda suave solo-laboratorio) re-verificando la
# captura despues del cambio.
# No modifica credenciales ni las bases protegidas. Salida: consola +
# %TEMP%\opencode\P3_DDL_CicloEventos.json.
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
Add-Type -AssemblyName System.Data

$LAB_DB = 'SecureFinanceERP_Lab_Dylan'
$script:migFile = Join-Path $PSScriptRoot '..\95_P3_DDL_CapturaAplicable.sql'
[int]$script:actor = 0
$int = [System.Data.SqlDbType]::Int
$nv = [System.Data.SqlDbType]::NVarChar
$vc = [System.Data.SqlDbType]::VarChar

function New-Conn {
    $b = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $b.set_DataSource('localhost'); $b.set_InitialCatalog($LAB_DB)
    $b.set_IntegratedSecurity($true); $b.set_Encrypt($true); $b.set_TrustServerCertificate($true)
    $b.set_ApplicationName('Dylan-DdlCiclo-P3'); $b.set_ConnectTimeout(15); $b.set_Pooling($false)
    $c = New-Object System.Data.SqlClient.SqlConnection($b.ConnectionString)
    $c.Open()
    if ((Invoke-ScalarQuery $c "SELECT CASE WHEN DB_NAME() COLLATE Latin1_General_100_BIN2=N'$LAB_DB' AND @@TRANCOUNT=0 AND SESSION_CONTEXT(N'P3_BOD.BodegaId') IS NULL THEN 1 ELSE 0 END" @{}) -ne 1) {
        $c.Dispose(); throw "Destino no autorizado: debe ser $LAB_DB, sin transaccion ni contexto"
    }
    return $c
}
function Add-Param($cmd, $name, $type, $len, $val) {
    $p = $cmd.Parameters.Add("@$name", $type, $len)
    if ($null -ne $val) { $p.Value = $val } else { $p.Value = [DBNull]::Value }
    return $p
}
function Read-SingleRow([System.Data.SqlClient.SqlCommand]$cmd) {
    $dr = $cmd.ExecuteReader()
    try { if ($dr.Read()) { if ($dr.IsDBNull(0)) { return $null } return $dr.GetValue(0) } return $null }
    finally { $dr.Dispose() }
}
function Invoke-ScalarQuery($conn, $sql, $map, $tx = $null) {
    $c = $conn.CreateCommand(); $c.CommandText = $sql; $c.CommandTimeout = 60
    if ($null -ne $tx) { $c.Transaction = $tx }
    foreach ($p in $map.GetEnumerator()) { Add-Param $c $p.Key $p.Value.SqlType $p.Value.Length $p.Value.Value | Out-Null }
    try { return Read-SingleRow $c } finally { $c.Dispose() }
}
function Invoke-Raw($conn, $sql) {
    $cmd = $conn.CreateCommand(); $cmd.CommandText = $sql; $cmd.CommandTimeout = 60
    try { [void]$cmd.ExecuteNonQuery(); return @{ ok = $true; number = $null; mensaje = $null } }
    catch [System.Data.SqlClient.SqlException] { return @{ ok = $false; number = $_.Exception.Number; mensaje = $_.Exception.Message } }
    finally { $cmd.Dispose() }
}
function Invoke-Rpc($conn, $proc, $map) {
    $cmd = $conn.CreateCommand(); $cmd.CommandType = 'StoredProcedure'; $cmd.CommandText = $proc; $cmd.CommandTimeout = 60
    foreach ($p in $map.GetEnumerator()) { Add-Param $cmd $p.Key $p.Value.SqlType $p.Value.Length $p.Value.Value | Out-Null }
    try { return @{ ok = $true; respuesta = (Read-SingleRow $cmd); number = $null; mensaje = $null } }
    catch [System.Data.SqlClient.SqlException] { return @{ ok = $false; respuesta = $null; number = $_.Exception.Number; mensaje = $_.Exception.Message } }
    finally { $cmd.Dispose() }
}
function Read-FirstCols($conn, $proc, $map) {
    # Lee (BitacoraDdlId, TipoEvento, NombreObjeto) del primer rs del proc de interfaz.
    $cmd = $conn.CreateCommand(); $cmd.CommandType = 'StoredProcedure'; $cmd.CommandText = $proc; $cmd.CommandTimeout = 60
    foreach ($p in $map.GetEnumerator()) { Add-Param $cmd $p.Key $p.Value.SqlType $p.Value.Length $p.Value.Value | Out-Null }
    $dr = $cmd.ExecuteReader(); $rows = @()
    try { while ($dr.Read()) { $rows += ,@([string]$dr.GetValue(0), [string]$dr.GetValue(2), [string]$dr.GetValue(3)) } return $rows }
    finally { $dr.Dispose(); $cmd.Dispose() }
}
function Get-LastCapture($conn) {
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = 'SELECT TOP(1) BitacoraDdlId, TipoEvento, ComandoTSql, NombreObjeto FROM dbo.Bitacora_DDL ORDER BY BitacoraDdlId DESC'
    $dr = $cmd.ExecuteReader()
    try {
        if ($dr.Read()) { return @{ id = $dr.GetInt64(0); evento = [string]$dr.GetString(1); comando = [string]$dr.GetString(2); objeto = [string]$dr.GetString(3) } }
        return $null
    } finally { $dr.Dispose(); $cmd.Dispose() }
}
function Get-Plain([System.Data.SqlClient.SqlConnection]$conn, [string]$sql) {
    $cmd = $conn.CreateCommand(); $cmd.CommandText = $sql; $cmd.CommandTimeout = 60
    $dr = $cmd.ExecuteReader()
    try { if ($dr.Read()) { if ($dr.IsDBNull(0)) { return $null } return $dr.GetValue(0) } return $null }
    finally { $dr.Dispose(); $cmd.Dispose() }
}

$report = [ordered]@{}
$script:stage = 'inicio'
$conn = New-Conn
try {
    $script:actor = [int](Invoke-ScalarQuery $conn "SELECT UsuarioId FROM dbo.Usuario WHERE NombreUsuario=N'P3_DYLAN_QA_ADMIN'" @{})
    if (-not $script:actor) { throw 'Falta actor sintetico P3_DYLAN_QA_ADMIN' }

    # ---- G0: baseline
    $script:stage = 'G0'
    # Limpieza idempotente de orphanos de corrida previa (objetos de prueba, no datos historicos).
    # Corre ANTES del baseline porque los DROPs disparan capturas del trigger.
    [void](Invoke-Raw $conn "IF OBJECT_ID(N'dbo.P3_DDL_EvProc', N'P') IS NOT NULL DROP PROCEDURE dbo.P3_DDL_EvProc")
    [void](Invoke-Raw $conn "IF OBJECT_ID(N'dbo.P3_DDL_EvTabla', N'U') IS NOT NULL DROP TABLE dbo.P3_DDL_EvTabla")
    $baseDdl = [int64](Invoke-ScalarQuery $conn 'SELECT COUNT(*) FROM dbo.Bitacora_DDL' @{})
    $baseDml = [int64](Invoke-ScalarQuery $conn 'SELECT COUNT(*) FROM dbo.Bitacora_Transacciones' @{})
    $baseAcc = [int64](Invoke-ScalarQuery $conn 'SELECT COUNT(*) FROM dbo.Bitacora_Acceso' @{})
    $evPrevios = [int](Invoke-ScalarQuery $conn "SELECT COUNT(*) FROM sys.trigger_events e JOIN sys.triggers t ON t.object_id = e.object_id WHERE t.name = N'P3_DDL_CapturarEstructura'" @{})
    $report['G0_baseline'] = [ordered]@{ rowsBitacoraDdl = $baseDdl; rowsBitacoraDml = $baseDml; rowsBitacoraAcceso = $baseAcc; triggerEventos = $evPrevios }
    if ($evPrevios -ne 6) { throw ('El trigger 94 no tiene los seis eventos (=' + $evPrevios + ')') }

    # ---- G1: ciclo de los SEIS eventos con captura exacta del comando
    $script:stage = 'G1'
    $stmts = @(
        @{ evento = 'CREATE_TABLE'; text = 'CREATE TABLE dbo.P3_DDL_EvTabla (Col1 INT NULL);' },
        @{ evento = 'ALTER_TABLE'; text = 'ALTER TABLE dbo.P3_DDL_EvTabla ADD Col2 NVARCHAR(20) NULL;' },
        @{ evento = 'CREATE_PROCEDURE'; text = 'CREATE PROCEDURE dbo.P3_DDL_EvProc AS SELECT 1 AS PruebaDylan;' },
        @{ evento = 'ALTER_PROCEDURE'; text = 'ALTER PROCEDURE dbo.P3_DDL_EvProc AS SELECT 2 AS PruebaDylanV2;' },
        @{ evento = 'DROP_PROCEDURE'; text = 'DROP PROCEDURE dbo.P3_DDL_EvProc;' },
        @{ evento = 'DROP_TABLE'; text = 'DROP TABLE dbo.P3_DDL_EvTabla;' }
    )
    $capturas = @()
    foreach ($s in $stmts) {
        $r = Invoke-Raw $conn $s.text
        if (-not $r.ok) { throw ('Evento ' + $s.evento + ' no ejecuto: ' + $r.number + ' ' + $r.mensaje) }
        $cap = Get-LastCapture $conn
        if ($null -eq $cap) { throw ('Sin captura para ' + $s.evento) }
        # El motor reporta el texto sin el terminador ';' en eventos TABLE/DROP y
        # con ';' en CREATE/ALTER PROCEDURE: comparacion verbatim salvo terminador.
        $esperado = ($s.text.TrimEnd() -replace ';+\s*$', '')
        $capturado = ($cap.comando.TrimEnd() -replace ';+\s*$', '')
        $capturas += [ordered]@{ evento = $s.evento; objeto = $cap.objeto; filaBitacora = $cap.id; comandoExacto = ($capturado -ceq $esperado) }
        $report[('G1_captura_' + $s.evento)] = $cap.id
    }
    $todasExactas = (@($capturas | ForEach-Object { $_.comandoExacto }) -notcontains $false)
    $secuencia = (@($capturas | ForEach-Object { $_.evento }) -join ',') -eq (($stmts | ForEach-Object { $_.evento }) -join ',')
    $deltaDdl = [int64](Invoke-ScalarQuery $conn 'SELECT COUNT(*) FROM dbo.Bitacora_DDL' @{}) - $baseDdl
    $report['G1_ciclo_seis'] = [ordered]@{ filasDelta = $deltaDdl; comandosExactos = $todasExactas; secuencia = $secuencia; detalle = $capturas }
    $report['G1_PASS'] = [bool]($deltaDdl -eq 6 -and $todasExactas -and $secuencia)

    # ---- G2: metadatos de permisos del escritor
    $script:stage = 'G2'
    $esc = (Invoke-ScalarQuery $conn "SELECT DATABASE_PRINCIPAL_ID(N'P3_DDL_Escritor')" @{})
    if (-not $esc) { throw 'No existe P3_DDL_Escritor' }
    $permChk = [ordered]@{
        conectGrant = ($null -ne (Invoke-ScalarQuery $conn "SELECT 1 FROM sys.database_permissions WHERE grantee_principal_id=@e AND class=0 AND permission_name=N'CONNECT' AND state=N'G'" @{ e = @{ SqlType = $int; Length = 0; Value = $esc } }))
        insertGrant = ($null -ne (Invoke-ScalarQuery $conn "SELECT 1 FROM sys.database_permissions WHERE grantee_principal_id=@e AND major_id=OBJECT_ID(N'dbo.Bitacora_DDL') AND permission_name=N'INSERT' AND state=N'G'" @{ e = @{ SqlType = $int; Length = 0; Value = $esc } }))
        count3Deny = ([int](Invoke-ScalarQuery $conn "SELECT COUNT(*) FROM sys.database_permissions WHERE grantee_principal_id=@e AND major_id=OBJECT_ID(N'dbo.Bitacora_DDL') AND permission_name IN (N'SELECT',N'UPDATE',N'DELETE') AND state=N'D'" @{ e = @{ SqlType = $int; Length = 0; Value = $esc } }) -eq 3)
        sinRoles = ([int](Invoke-ScalarQuery $conn 'SELECT COUNT(*) FROM sys.database_role_members WHERE member_principal_id=@e' @{ e = @{ SqlType = $int; Length = 0; Value = $esc } }) -eq 0)
        impersonateDeny = ($null -ne (Invoke-ScalarQuery $conn "SELECT 1 FROM sys.database_permissions WHERE grantee_principal_id=DATABASE_PRINCIPAL_ID(N'securefinance_app') AND class=4 AND major_id=@e AND permission_name=N'IMPERSONATE' AND state=N'D'" @{ e = @{ SqlType = $int; Length = 0; Value = $esc } }))
    }
    $report['G2_permisos'] = $permChk
    $report['G2_PASS'] = [bool]($permChk.conectGrant -and $permChk.insertGrant -and $permChk.count3Deny -and $permChk.sinRoles -and $permChk.impersonateDeny)

    # ---- G3: EXECUTE AS escritor NO puede leer la bitacora (DENY SELECT efectivo)
    $script:stage = 'G3'
    $probe = Invoke-Raw $conn (@'
BEGIN TRY
    EXECUTE AS USER = N'P3_DDL_Escritor';
    SELECT TOP(1) 1 FROM dbo.Bitacora_DDL;
    REVERT;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    REVERT;
    THROW;
END CATCH;
'@)
    $report['G3_execute_as'] = [ordered]@{ bloqueado = (-not $probe.ok); numero = $probe.number; mensaje = $probe.mensaje }
    $report['G3_PASS'] = [bool]((-not $probe.ok) -and $probe.number -in @(229, 230, 297))

    # ---- G4: auditoria DML sigue operativa: cambio real y reversion (2 eventos)
    $script:stage = 'G4'
    $prodSyn = [int](Get-Plain $conn "SELECT TOP(1) ProductoId FROM dbo.Producto WHERE Codigo LIKE 'P3-CRE-QA-%' ORDER BY ProductoId DESC")
    if (-not $prodSyn) { throw 'Sin producto sintetico para la prueba DML' }
    $precio0 = [decimal](Get-Plain $conn ("SELECT Precio FROM dbo.Producto WHERE ProductoId=" + $prodSyn))
    [void](Invoke-Raw $conn ("UPDATE dbo.Producto SET Precio = Precio + 1000 WHERE ProductoId = " + $prodSyn))
    $delta1 = [int64](Invoke-ScalarQuery $conn 'SELECT COUNT(*) FROM dbo.Bitacora_Transacciones' @{}) - $baseDml
    [void](Invoke-Raw $conn ("UPDATE dbo.Producto SET Precio = Precio - 1000 WHERE ProductoId = " + $prodSyn))
    $deltaDml = [int64](Invoke-ScalarQuery $conn 'SELECT COUNT(*) FROM dbo.Bitacora_Transacciones' @{}) - $baseDml
    $precioF = [decimal](Get-Plain $conn ("SELECT Precio FROM dbo.Producto WHERE ProductoId=" + $prodSyn))
    $report['G4_dml'] = [ordered]@{ deltaTrasCambio = $delta1; deltaTotal = $deltaDml; precioRestaurado = ($precioF -eq $precio0) }
    $report['G4_PASS'] = [bool]($deltaDml -ge 2 -and ($precioF -eq $precio0))

    # ---- G5: auditoria de accesos sigue operativa (via rechazo sp_Login)
    $script:stage = 'G5'
    $login = Invoke-Rpc $conn 'dbo.sp_Login' @{
        NombreUsuario = @{ SqlType = $nv; Length = -1; Value = 'P3_DYLAN_QA_ADMIN' }
        Password = @{ SqlType = $nv; Length = -1; Value = ('norel-' + [System.Guid]::NewGuid().ToString('N').Substring(0, 20)) }
    }
    $deltaAcc = [int64](Invoke-ScalarQuery $conn 'SELECT COUNT(*) FROM dbo.Bitacora_Acceso' @{}) - $baseAcc
    $report['G5_accesos'] = [ordered]@{ codigo = [string]$login.respuesta; deltaFilas = $deltaAcc; numeroErrorSi = $login.number }
    # La respuesta del proc empieza con Codigo=3 (PASSWORD_INCORRECTA); respuesta escalar numerica 3.
    $report['G5_PASS'] = [bool]((-not $login.ok -or ([int]$login.respuesta -eq 3)) -and $deltaAcc -ge 1)

    # ---- G6: interfaz: P3_DDL_ConsultarBitacora muestra los seis eventos
    $script:stage = 'G6'
    $rows = Read-FirstCols $conn 'dbo.P3_DDL_ConsultarBitacora' @{
        ActorUsuarioId = @{ SqlType = $int; Length = 0; Value = $script:actor }
        Objeto = @{ SqlType = $nv; Length = 128; Value = 'P3_DDL_Ev' }
        Limite = @{ SqlType = $int; Length = 0; Value = 100 }
    }
    $idsVistos = @($rows | ForEach-Object { $_[0] })
    $evVistos = @($rows | ForEach-Object { $_[1] })
    $objsVistos = @($rows | ForEach-Object { $_[2] })
    $idsEsperadas = @($capturas | ForEach-Object { [string]$_.filaBitacora })
    $report['G6_interfaz'] = [ordered]@{ filasDevueltas = $rows.Count; historicasIncluidas = $rows.Count -gt 6; idsEstaCorridaVisibles = (@($idsEsperadas | ForEach-Object { $idsVistos -contains $_ }) -notcontains $false) }
    # La interfaz devuelve TODA la bitacora historica del objeto (inmutable): los seis
    # eventos de ESTA corrida (ids exactos) deben estar presentes entre las filas.
    $report['G6_PASS'] = [bool]($rows.Count -ge 6 -and (@($idsEsperadas | ForEach-Object { $idsVistos -contains $_ }) -notcontains $false))

    # ---- G7: aplicar propuesta 95 (guarda suave solo-laboratorio) y re-verificar
    $script:stage = 'G7'
    $mig = Get-Content $script:migFile -Raw -ErrorAction Stop
    $batches = ($mig -split '(\r?\nGO\r?\n)') | Where-Object { $_ -notmatch '^\r?\nGO\r?\n$' -and $_.Trim().Length -gt 0 }
    # Conservar solo los bloques SQL (descartar los separadores GO)
    $batches = @($batches | Where-Object { -not ($_ -match '^\s*\r?\n\s*$') })
    $tx = $conn.BeginTransaction()
    try {
        foreach ($b in $batches) {
            $b2 = ($b -replace '\r?\nGO\s*$', '')
            if ([string]::IsNullOrWhiteSpace($b2)) { continue }
            $cmd = $conn.CreateCommand(); $cmd.Transaction = $tx; $cmd.CommandText = $b2; $cmd.CommandTimeout = 60
            [void]$cmd.ExecuteNonQuery(); $cmd.Dispose()
        }
        $tx.Commit()
    } catch { $tx.Rollback(); throw ('Migracion 95 fallo: ' + $_.Exception.Message) }
    $triggerOk = [int](Invoke-ScalarQuery $conn "SELECT COUNT(*) FROM sys.sql_modules m JOIN sys.triggers t ON t.object_id=m.object_id WHERE t.name=N'P3_DDL_CapturarEstructura' AND m.definition LIKE '%SecureFinanceERP_Lab_Dylan%' AND m.definition LIKE '%Return%'" @{})
    $evPost = [int](Invoke-ScalarQuery $conn "SELECT COUNT(*) FROM sys.trigger_events e JOIN sys.triggers t ON t.object_id=e.object_id WHERE t.name=N'P3_DDL_CapturarEstructura'" @{})
    $report['G7_migracion_95'] = [ordered]@{ batches = $batches.Count; guardaSuave = ($triggerOk -ge 1); triggerEventos = $evPost }
    if ($triggerOk -lt 1 -or $evPost -ne 6) { throw 'La migracion 95 no quedo aplicada con guarda suave' }

    # ---- G8: la captura sigue funcionando despues de 95 (dos eventos de control)
    $script:stage = 'G8'
    $preG8 = [int64](Invoke-ScalarQuery $conn 'SELECT COUNT(*) FROM dbo.Bitacora_DDL' @{})
    $r8a = Invoke-Raw $conn 'CREATE TABLE dbo.P3_DDL_EvTabla (Col3 INT NULL);'
    $r8b = Invoke-Raw $conn 'DROP TABLE dbo.P3_DDL_EvTabla;'
    if (-not $r8a.ok -or -not $r8b.ok) { throw ('G8 no ejecuto: ' + $r8a.mensaje + ' / ' + $r8b.mensaje) }
    $delta8 = [int64](Invoke-ScalarQuery $conn 'SELECT COUNT(*) FROM dbo.Bitacora_DDL' @{}) - $preG8
    $last = Get-LastCapture $conn
    $report['G8_post_95'] = [ordered]@{ deltaFilas = $delta8; ultimoEvento = $last.evento; ultimoObjeto = $last.objeto }
    $report['G8_PASS'] = [bool]($delta8 -eq 2 -and $last.evento -eq 'DROP_TABLE' -and $last.objeto -eq 'P3_DDL_EvTabla')

    $report['timestamp_local'] = (Get-Date).ToString('o')
    $resumenJson = $report | ConvertTo-Json -Depth 6
    $resumenJson | Set-Content -Path (Join-Path $env:TEMP 'opencode\P3_DDL_CicloEventos.json') -Encoding UTF8
    Write-Host '---- RESULTADO ----'
    foreach ($k in @('G1_PASS', 'G2_PASS', 'G3_PASS', 'G4_PASS', 'G5_PASS', 'G6_PASS', 'G8_PASS')) { Write-Host ("{0}={1}" -f $k, $report[$k]) }
    Write-Host $resumenJson
    if (-not ($report['G1_PASS'] -and $report['G2_PASS'] -and $report['G3_PASS'] -and $report['G4_PASS'] -and $report['G5_PASS'] -and $report['G6_PASS'] -and $report['G8_PASS'])) { exit 1 }
} catch {
    Write-Host ('MAIN_ERR [etapa ' + $script:stage + '] ' + $_.Exception.Message)
    try { $report | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $env:TEMP 'opencode\P3_DDL_CicloEventos_diag.json') -Encoding UTF8 } catch { }
    exit 2
} finally { $conn.Dispose() }
