[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Servidor,
    [Parameter(Mandatory = $true)][string]$InstanciaEsperada,
    [Parameter(Mandatory = $true)][ValidateSet('SecureFinanceERP_Lab_Dylan')][string]$BaseLaboratorio,
    [ValidateSet('Inicial', 'Completar')][string]$Modo = 'Completar',
    [switch]$ConfirmarLaboratorioSinDatosReales,
    [switch]$AceptarTextoSqlCompleto,
    [switch]$Probar,
    [switch]$ConfiarCertificadoLocal
)
$ErrorActionPreference = 'Stop'
if (-not $ConfirmarLaboratorioSinDatosReales -or -not $AceptarTextoSqlCompleto) {
    throw 'Se requiere confirmar externamente el laboratorio sin datos reales y aceptar el riesgo del SQL completo.'
}
$builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
if ($ConfiarCertificadoLocal -and $Servidor -ne 'localhost') { throw 'La excepcion TLS solo se autoriza en localhost.' }
$builder.set_DataSource($Servidor)
$builder.set_InitialCatalog($BaseLaboratorio)
$builder.set_IntegratedSecurity($true)
$builder.set_Encrypt($true)
$builder.set_TrustServerCertificate([bool]$ConfiarCertificadoLocal)
$builder.set_ApplicationName('SecureFinanceERP-P3-DDL-Lab')
$connection = [System.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
$transaction = $null
$currentFile = 'conexion'
$currentBatch = 0
function Invoke-SqlFile([string]$File) {
    $script:currentFile = [System.IO.Path]::GetFileName($File)
    $script:currentBatch = 0
    $text = [System.IO.File]::ReadAllText($File)
    foreach ($batch in [regex]::Split($text, '(?im)^\s*GO\s*$')) {
        if ([string]::IsNullOrWhiteSpace($batch)) { continue }
        $script:currentBatch++
        $cmd = $connection.CreateCommand()
        try {
            $cmd.Transaction = $transaction
            $cmd.CommandTimeout = 60
            $cmd.CommandText = $batch
            [void]$cmd.ExecuteNonQuery()
        } finally { $cmd.Dispose() }
    }
}
try {
    $connection.Open()
    $cmd = $connection.CreateCommand()
    $cmd.CommandText = 'SELECT CONVERT(nvarchar(128), SERVERPROPERTY(''ServerName'')), DB_NAME();'
    $reader = $cmd.ExecuteReader()
    try {
        if (-not $reader.Read() -or $reader.GetString(0) -ine $InstanciaEsperada -or $reader.GetString(1) -cne $BaseLaboratorio) {
            throw 'La instancia o base real no coincide con el destino autorizado.'
        }
    } finally { $reader.Dispose(); $cmd.Dispose() }
    $transaction = $connection.BeginTransaction()
    $cmd = $connection.CreateCommand()
    try {
        $cmd.Transaction = $transaction
        $cmd.CommandText = "SET XACT_ABORT ON; EXEC sys.sp_set_session_context @key=N'P3_DDL.LaboratorioConfirmado', @value=@db; EXEC sys.sp_set_session_context @key=N'P3_DDL.TextoExactoAutorizado', @value=@db;"
        [void]$cmd.Parameters.Add('@db', [System.Data.SqlDbType]::NVarChar, 128)
        $cmd.Parameters['@db'].Value = $BaseLaboratorio
        [void]$cmd.ExecuteNonQuery()
    } finally { $cmd.Dispose() }
    $files = @('93_P3_DDL_TextoExacto.sql', '94_P3_DDL_Captura.sql')
    if ($Modo -eq 'Inicial') {
        $files = @('90_P3_DDL_Estructura.sql', '91_P3_DDL_Consultas.sql', '92_P3_DDL_Permisos.sql') + $files
    }
    foreach ($file in $files) { Invoke-SqlFile (Join-Path (Split-Path $PSScriptRoot -Parent) $file) }
    $transaction.Commit()
    $transaction.Dispose()
    $transaction = $null
    'Migraciones DDL completadas solamente en el laboratorio confirmado.'
    if ($Probar) {
        $transaction = $connection.BeginTransaction()
        Invoke-SqlFile (Join-Path $PSScriptRoot 'AuditoriaDdlLabTests.sql')
        $transaction.Rollback()
        $transaction.Dispose()
        $transaction = $null
        'Pruebas SQL completadas: fixtures y eventos de prueba revertidos.'
    }
} catch {
    if ($null -ne $transaction) { try { $transaction.Rollback() } catch {} }
    # Do not print SQL batches or server exception text: they can contain commands.
    $failure = $_.Exception
    $number = 0; $line = 0; $diagnostic = ''
    while ($null -ne $failure) {
        if ($failure -is [System.Data.SqlClient.SqlException]) {
            $number = $failure.Number; $line = $failure.LineNumber
            if ($number -in @(54990,54993,54995)) { $diagnostic = $failure.Message }
            break
        }
        $failure = $failure.InnerException
    }
    throw "Fallo DDL: Archivo=$currentFile; Lote=$currentBatch; Codigo=$number; Linea=$line. $diagnostic Se intento rollback activo; instalaciones ya confirmadas permanecen."
} finally {
    if ($null -ne $transaction) { $transaction.Dispose() }
    $connection.Dispose()
}
