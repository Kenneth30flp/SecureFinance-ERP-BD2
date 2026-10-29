[CmdletBinding()]
param(
    [ValidateSet('localhost')][string]$Servidor = 'localhost',
    [string]$InstanciaEsperada,
    [switch]$Ejecutar,
    [switch]$CrearBase,
    [switch]$ConfirmarLaboratorioSinDatosReales,
    [switch]$AceptarTextoSqlCompleto,
    [switch]$IncluirAuditoriaDdl,
    [ValidateSet('securefinance_app', 'SecureFinanceAppRuntime')][string]$LoginAplicacionExistente = 'securefinance_app',
    [switch]$ConfiarCertificadoLocal
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Set-Variable -Name BaseLaboratorio -Value 'SecureFinanceERP_Lab_Dylan' -Option Constant
$databaseDirectory = Split-Path $PSScriptRoot -Parent

# The first group alone may have one leading USE, removed only in memory.
$baseFiles = @(
    '02_SecurityTables.sql',
    '03_SecurityStoredProcedures.sql',
    'tests/LabDylanSecurityCatalog.sql',
    '05_BusinessTables.sql',
    '06_TransactionProcedures.sql',
    '07_AuditCore.sql',
    '08_AuditTriggers.sql',
    '11_UserAdministration.sql',
    '12_PasswordRecovery.sql',
    '14_DashboardSummary.sql',
    '10_AppPermissions.sql'
)
$moduleFiles = @(
    '15_ParteII_Preflight.sql',
    '16_ParteII_Catalogos.sql',
    '17_ParteII_Kardex.sql',
    '18_ParteII_Procedimientos.sql',
    '19_ParteII_Auditoria.sql',
    '20_ParteII_Permisos.sql',
    '21_ParteII_IntegracionFacturacionKardex.sql',
    '22_ParteII_ConsultasWeb.sql',
    '23_ParteII_MantenimientoClientes.sql',
    '24_Edward_Devoluciones.sql',
    '25_Edward_Garantias.sql',
    '26_Edward_ConsultasPermisos.sql',
    '30_Jose_FuncionesAnaliticas.sql',
    '31_Jose_DashboardVentas.sql',
    '32_Jose_PermisosConsultas.sql',
    '33_ERP_ProductoProveedor.sql',
    '34_ERP_RecepcionesCompra.sql',
    '35_ERP_AplicacionesNotaCredito.sql',
    '36_ERP_PermisosIntegracion.sql',
    '37_ERP_VentaIdempotente.sql',
    '38_ERP_ProductoSKUAutomatico.sql',
    '39_ERP_HistorialFacturas.sql',
    '40_ERP_ReactivarCliente.sql',
    '41_P3_COT_EstructuraCotizaciones.sql',
    '42_P3_COT_Operaciones.sql',
    '43_P3_COT_ConversionFactura.sql',
    '44_P3_COT_BusquedaComercial.sql'
)
$ddlFiles = @(
    '90_P3_DDL_Estructura.sql',
    '91_P3_DDL_Consultas.sql',
    '92_P3_DDL_Permisos.sql',
    '93_P3_DDL_TextoExacto.sql',
    '94_P3_DDL_Captura.sql'
)

function Get-SqlLayout([string]$Text) {
    # Preserve offsets/newlines for GO; comments and literals are not separators.
    # Nested block comments are recognized with .NET balancing groups.
    $pattern = '(?<comment>--[^\r\n]*|/\*(?>/\*(?<depth>)|\*/(?<-depth>)|(?!/\*|\*/)[\s\S])*(?(depth)(?!))\*/)|(?<literal>N?''(?:''''|[^''])*'')|(?<identifier>\[(?:\]\]|[^\]])*\]|"(?:""|[^"])*")|(?<code>[^\["''/\-]+|/(?!\*)|-(?!-))'
    $mask = [System.Text.StringBuilder]::new()
    $literals = [System.Collections.Generic.List[string]]::new()
    $offset = 0
    foreach ($token in [regex]::Matches($Text, $pattern, 'IgnoreCase')) {
        if ($token.Index -ne $offset) { throw 'SQL lexico no admitido.' }
        if ($token.Groups['comment'].Success -or $token.Groups['literal'].Success) {
            [void]$mask.Append([regex]::Replace($token.Value, '[^\r\n]', ' '))
            if ($token.Groups['literal'].Success) {
                $value = $token.Value -replace '^N?''|''$', ''
                $literals.Add($value.Replace("''", "'"))
            }
        } else {
            if ($token.Groups['identifier'].Success -and $token.Value -match '[\r\n]') {
                throw 'Identificador SQL multilinea no admitido.'
            }
            [void]$mask.Append($token.Value)
        }
        $offset += $token.Length
    }
    if ($offset -ne $Text.Length) { throw 'SQL lexico incompleto.' }
    [pscustomobject]@{ Code = $mask.ToString(); Literals = $literals }
}

function Assert-SqlScope([string]$Code, [string[]]$Literals, [int]$Depth = 0) {
    if ($Depth -gt 16) { throw 'Anidamiento SQL no admitido.' }
    $identifier = '(?:\[(?:\]\]|[^\]])+\]|"(?:""|[^"])+"|[A-Za-z_#][A-Za-z0-9_@$#]*)'
    $forbidden = '(?i)\bUSE(?:\s+[A-Za-z_]|\s*(?:\[|"))|\b(?:CREATE|ALTER|DROP)\s+DATABASE\b|\bDROP\s+TABLE\b|\b(?:BACKUP|RESTORE)\b|\b(?:CREATE|ALTER|DROP)\s+LOGIN\b|\bALTER\s+SERVER\b|\b(?:sp_configure|RECONFIGURE|OPENROWSET|OPENDATASOURCE|OPENQUERY|CHANGE_DATABASE)\b|\bEXEC(?:UTE)?\s+AS\s+LOGIN\b|\b(?:sp_addsrvrolemember|sp_addlinkedserver|xp_cmdshell)\b|(?m)^\s*[:!]|\$\('
    $threePart = $identifier + '\s*\.\s*(?:' + $identifier + ')?\s*\.\s*' + $identifier
    if ($Code -match $forbidden -or $Code -match $threePart) {
        throw 'SQL fuera del alcance permitido.'
    }
    # Inspect complete literal SQL recursively, not dotted resource names or prose.
    # This is a reviewed-manifest guard, not a sandbox for arbitrary dynamic SQL.
    foreach ($literal in $Literals) {
        if ($literal -match '(?is)^\s*(?:USE|SELECT|IF|BEGIN|CREATE|ALTER|DROP|EXEC(?:UTE)?|DECLARE|SET|BACKUP|RESTORE|WITH|GRANT|DENY|REVOKE)\b') {
            $nested = Get-SqlLayout $literal
            Assert-SqlScope $nested.Code $nested.Literals.ToArray() ($Depth + 1)
        }
    }
}

$preparedFiles = [System.Collections.Generic.List[object]]::new()
$manifest = @($baseFiles) + @($moduleFiles)
if ($IncluirAuditoriaDdl) { $manifest += $ddlFiles }
$stage = 0
try {
    foreach ($file in $manifest) {
        $stage++
        $text = [System.IO.File]::ReadAllText((Join-Path $databaseDirectory $file))
        if ($file -eq '10_AppPermissions.sql' -and $LoginAplicacionExistente -ne 'securefinance_app') {
            # Database USER stays securefinance_app; map an existing limited LOGIN, never create/change credentials.
            if (-not $text.Contains("SUSER_ID(N'securefinance_app')") -or -not $text.Contains('FOR LOGIN [securefinance_app]')) {
                throw 'Contrato de mapeo del usuario de aplicacion inesperado.'
            }
            $text = $text.Replace("SUSER_ID(N'securefinance_app')", "SUSER_ID(N'$LoginAplicacionExistente')")
            $text = $text.Replace('FOR LOGIN [securefinance_app]', "FOR LOGIN [$LoginAplicacionExistente]")
        }
        $layout = Get-SqlLayout $text
        if ($baseFiles -contains $file -and $file -ne 'tests/LabDylanSecurityCatalog.sql') {
            $leading = [regex]::Match($layout.Code, '\A\s*USE \[SecureFinanceERP\];', 'CultureInvariant')
            if (-not $leading.Success) { throw 'Se esperaba un unico USE inicial exacto.' }
            $useStart = $layout.Code.IndexOf('USE ', [System.StringComparison]::Ordinal)
            $text = $text.Remove($useStart, 'USE [SecureFinanceERP];'.Length)
            $layout = Get-SqlLayout $text
        }
        Assert-SqlScope $layout.Code $layout.Literals.ToArray()
        $batches = [System.Collections.Generic.List[string]]::new()
        $start = 0
        foreach ($separator in [regex]::Matches($layout.Code, '(?im)^[\t ]*GO[\t ]*\r?$')) {
            $batches.Add($text.Substring($start, $separator.Index - $start))
            $start = $separator.Index + $separator.Length
        }
        $batches.Add($text.Substring($start))
        if ([regex]::Replace($layout.Code, '(?im)^[\t ]*GO[\t ]*\r?$', '') -match '(?im)^\s*GO\b') {
            throw 'Solo se admite GO solo, sin contador ni terminador.'
        }
        $preparedFiles.Add([pscustomobject]@{ Name = $file; Batches = $batches })
    }
} catch {
    throw "Validacion local rechazada. Etapa=$stage. No se abrio conexion ni se creo una base. Revisar el archivo del manifiesto en privado."
}

# PLAN must return before constructing/opening any connection or doing preflight.
if (-not $Ejecutar) {
    "PLAN sin conexion SQL. Destino=$BaseLaboratorio; Servidor=localhost."
    $stage = 0
    foreach ($file in $preparedFiles) {
        $stage++
        '{0:D2} {1} (lotes={2})' -f $stage, $file.Name, $file.Batches.Count
    }
    "Archivos=$($preparedFiles.Count); modulos15a44=$($moduleFiles.Count); AuditoriaDdl=$([bool]$IncluirAuditoriaDdl)."
    'PLAN no verifica TLS, instancia, login, ausencia de base ni compilacion SQL. No autoriza ejecutar.'
    return
}
if (-not $CrearBase -or -not $ConfirmarLaboratorioSinDatosReales -or -not $AceptarTextoSqlCompleto -or
    [string]::IsNullOrWhiteSpace($InstanciaEsperada) -or $InstanciaEsperada.Length -gt 128) {
    throw 'Ejecutar requiere CrearBase, ambas confirmaciones e InstanciaEsperada obtenida privadamente por el DBA.'
}

$connection = $null
$transaction = $null
$stage = 0
$preflight = -1
try {
    $builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
    # Explicit setters avoid PowerShell 5.1 treating this IDictionary as keyword keys.
    $builder.set_DataSource('localhost')
    $builder.set_InitialCatalog('master')
    $builder.set_IntegratedSecurity($true)
    $builder.set_Encrypt($true)
    # Explicit per-connection exception authorized by Dylan; server is restricted to localhost.
    $builder.set_TrustServerCertificate([bool]$ConfiarCertificadoLocal)
    $builder.set_PersistSecurityInfo($false)
    $builder.set_Pooling($false)
    $builder.set_ConnectTimeout(15)
    $builder.set_ApplicationName('SecureFinanceERP-Lab-Dylan')
    $connection = [System.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
    $connection.Open()
    $stage = 1
    $cmd = $connection.CreateCommand()
    try {
        # Read-only preflight. Return only a numeric result, never server/login details.
        $cmd.CommandText = @'
SELECT CASE
 WHEN ISNULL(CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')),N'') COLLATE Latin1_General_100_BIN2
      <> @expected COLLATE Latin1_General_100_BIN2 THEN 1
 WHEN ISNULL(TRY_CONVERT(int,SERVERPROPERTY('ProductMajorVersion')),0)<14 THEN 2
 WHEN ISNULL((SELECT CONVERT(int,value_in_use) FROM sys.configurations WHERE name=N'nested triggers'),0)<>1 THEN 3
  WHEN ISNULL(HAS_PERMS_BY_NAME(NULL,NULL,N'VIEW ANY DEFINITION'),0)<>1
    OR ISNULL(HAS_PERMS_BY_NAME(NULL,NULL,N'VIEW ANY DATABASE'),0)<>1
    OR ISNULL(HAS_PERMS_BY_NAME(NULL,NULL,N'CREATE ANY DATABASE'),0)<>1 THEN 4
 WHEN EXISTS(SELECT 1 FROM sys.databases WHERE name COLLATE Latin1_General_100_CI_AS=N'SecureFinanceERP_Lab_Dylan') THEN 5
  WHEN NOT EXISTS(SELECT 1 FROM sys.server_principals WHERE name=@appLogin AND type=N'S' AND is_disabled=0) THEN 6
  WHEN EXISTS(SELECT 1 FROM sys.server_role_members WHERE member_principal_id=SUSER_ID(@appLogin))
   OR EXISTS(SELECT 1 FROM sys.server_principals WHERE type=N'R' AND is_fixed_role=1
              AND name<>N'public' AND ISNULL(IS_SRVROLEMEMBER(name,@appLogin),1)<>0)
    OR EXISTS(SELECT 1 FROM sys.server_permissions WHERE grantee_principal_id IN
               (SELECT principal_id FROM sys.server_principals WHERE name IN(@appLogin,N'public'))
             AND state IN(N'G',N'W') AND NOT (state=N'G' AND
               ((class=100 AND permission_name IN(N'CONNECT SQL',N'VIEW ANY DATABASE'))
                OR (class=105 AND permission_name=N'CONNECT'))))
    OR EXISTS(SELECT 1 FROM sys.databases WHERE owner_sid=SUSER_SID(@appLogin)) THEN 7
 ELSE 0 END;
'@
        [void]$cmd.Parameters.Add('@expected', [System.Data.SqlDbType]::NVarChar, 128)
        $cmd.Parameters['@expected'].Value = $InstanciaEsperada
        [void]$cmd.Parameters.Add('@appLogin', [System.Data.SqlDbType]::NVarChar, 128)
        $cmd.Parameters['@appLogin'].Value = $LoginAplicacionExistente
        $preflight = [int]$cmd.ExecuteScalar()
        if ($preflight -ne 0) { throw "Preflight=$preflight" }
    } finally { $cmd.Dispose() }
    'Etapa=1; preflight de solo lectura aprobado.'
    $stage = 2
    $cmd = $connection.CreateCommand()
    try {
        $cmd.CommandTimeout = 120
        # Deliberately outside the schema transaction. A concurrent creator causes failure.
        $cmd.CommandText = @'
IF @@TRANCOUNT<>0 OR DB_NAME()<>N'master' OR DB_ID(N'SecureFinanceERP_Lab_Dylan') IS NOT NULL
 THROW 54980, 'Destino de creacion no autorizado o ya existente.', 1;
CREATE DATABASE [SecureFinanceERP_Lab_Dylan];
'@
        [void]$cmd.ExecuteNonQuery()
    } finally { $cmd.Dispose() }
    $connection.ChangeDatabase($BaseLaboratorio)
    $stage = 3
    $cmd = $connection.CreateCommand()
    try {
        $cmd.CommandText = @'
IF DB_NAME() COLLATE Latin1_General_100_BIN2 <> N'SecureFinanceERP_Lab_Dylan'
 OR ISNULL(HAS_PERMS_BY_NAME(DB_NAME(),N'DATABASE',N'VIEW DEFINITION'),0)<>1
 OR EXISTS(SELECT 1 FROM sys.objects WHERE is_ms_shipped=0)
 OR EXISTS(SELECT 1 FROM sys.triggers WHERE is_ms_shipped=0)
 OR EXISTS(SELECT 1 FROM sys.types WHERE is_user_defined=1)
 OR EXISTS(SELECT 1 FROM sys.assemblies WHERE is_user_defined=1)
 OR EXISTS(SELECT 1 FROM sys.synonyms)
 OR EXISTS(SELECT 1 FROM sys.database_principals WHERE principal_id>4 AND is_fixed_role=0)
 OR EXISTS(SELECT 1 FROM sys.schemas WHERE schema_id BETWEEN 5 AND 16383)
 THROW 54980, 'La base nueva no esta vacia o no tiene visibilidad completa.', 1;
'@
        [void]$cmd.ExecuteNonQuery()
    } finally { $cmd.Dispose() }
    $transaction = $connection.BeginTransaction()
    $cmd = $connection.CreateCommand()
    try {
        $cmd.Transaction = $transaction
        $cmd.CommandText = 'SET XACT_ABORT ON; SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON;'
        [void]$cmd.ExecuteNonQuery()
    } finally { $cmd.Dispose() }
    $stage = 3
    foreach ($file in $preparedFiles) {
        $stage++
        "Etapa=$stage; Destino=$BaseLaboratorio; Archivo=$($file.Name)."
        if ($file.Name -eq $ddlFiles[0]) {
            $cmd = $connection.CreateCommand()
            try {
                $cmd.Transaction = $transaction
                $cmd.CommandText = "EXEC sys.sp_set_session_context @key=N'P3_DDL.LaboratorioConfirmado', @value=@db; EXEC sys.sp_set_session_context @key=N'P3_DDL.TextoExactoAutorizado', @value=@db;"
                [void]$cmd.Parameters.Add('@db', [System.Data.SqlDbType]::NVarChar, 128)
                $cmd.Parameters['@db'].Value = $BaseLaboratorio
                [void]$cmd.ExecuteNonQuery()
            } finally { $cmd.Dispose() }
        }
        foreach ($batch in $file.Batches) {
            if ([string]::IsNullOrWhiteSpace($batch)) { continue }
            $cmd = $connection.CreateCommand()
            try {
                $cmd.Transaction = $transaction
                $cmd.CommandText = "IF DB_NAME() COLLATE Latin1_General_100_BIN2 <> N'SecureFinanceERP_Lab_Dylan' OR @@TRANCOUNT<>1 OR XACT_STATE()<>1 THROW 54980, 'Contexto de laboratorio no autorizado.', 1;"
                [void]$cmd.ExecuteNonQuery()
                if ($connection.Database -cne $BaseLaboratorio) { throw 'Contexto de conexion incorrecto.' }
                $cmd.CommandText = $batch
                $cmd.CommandTimeout = 120
                [void]$cmd.ExecuteNonQuery()
            } finally { $cmd.Dispose() }
        }
    }
    $cmd = $connection.CreateCommand()
    try {
        $cmd.Transaction = $transaction
        $cmd.CommandText = @'
IF DB_NAME() COLLATE Latin1_General_100_BIN2 <> N'SecureFinanceERP_Lab_Dylan' OR @@TRANCOUNT<>1 OR XACT_STATE()<>1
 THROW 54980, 'Contexto final no autorizado.', 1;
IF NOT EXISTS(SELECT 1 FROM sys.database_principals WHERE name=N'securefinance_app' AND sid=SUSER_SID(@appLogin))
 OR IS_ROLEMEMBER(N'db_owner',N'securefinance_app')<>0
 OR IS_ROLEMEMBER(N'db_securityadmin',N'securefinance_app')<>0
 OR EXISTS(SELECT 1 FROM sys.database_role_members WHERE member_principal_id=DATABASE_PRINCIPAL_ID(N'securefinance_app'))
 OR EXISTS(SELECT 1 FROM sys.schemas WHERE principal_id=DATABASE_PRINCIPAL_ID(N'securefinance_app'))
 OR EXISTS(SELECT 1 FROM sys.objects WHERE principal_id=DATABASE_PRINCIPAL_ID(N'securefinance_app'))
 OR EXISTS(SELECT 1 FROM sys.database_permissions WHERE grantee_principal_id=DATABASE_PRINCIPAL_ID(N'securefinance_app')
           AND state IN(N'G',N'W') AND NOT (state=N'G' AND
             ((class IN(1,6) AND permission_name IN(N'EXECUTE',N'REFERENCES')) OR (class=0 AND permission_name=N'CONNECT'))))
 THROW 54980, 'El mapeo de aplicacion no es limitado.', 1;
DECLARE @Riesgo bit=0;
EXECUTE AS USER=N'securefinance_app';
BEGIN TRY
 IF EXISTS(SELECT 1 FROM sys.fn_my_permissions(NULL,N'DATABASE')
           WHERE permission_name NOT IN(N'CONNECT',N'VIEW ANY COLUMN MASTER KEY DEFINITION',N'VIEW ANY COLUMN ENCRYPTION KEY DEFINITION'))
  OR EXISTS(SELECT 1 FROM sys.fn_my_permissions(N'dbo',N'SCHEMA')) SET @Riesgo=1;
 REVERT;
END TRY
BEGIN CATCH
 REVERT;
 THROW;
END CATCH;
IF @Riesgo<>0 THROW 54980, 'El usuario de aplicacion hereda permisos amplios.', 1;
IF EXISTS(SELECT 1 FROM dbo.Usuario) OR EXISTS(SELECT 1 FROM dbo.Cliente) OR EXISTS(SELECT 1 FROM dbo.Producto)
 OR EXISTS(SELECT 1 FROM dbo.Factura) OR EXISTS(SELECT 1 FROM dbo.Kardex_Inventario)
 OR EXISTS(SELECT 1 FROM dbo.Apertura_Inventario) OR EXISTS(SELECT 1 FROM dbo.ConfiguracionInventario WHERE Habilitado<>0 OR AperturaId IS NOT NULL)
 THROW 54980, 'No se permiten identidades, negocio ni apertura automatica.', 1;
'@
        [void]$cmd.Parameters.Add('@appLogin', [System.Data.SqlDbType]::NVarChar, 128)
        $cmd.Parameters['@appLogin'].Value = $LoginAplicacionExistente
        [void]$cmd.ExecuteNonQuery()
    } finally { $cmd.Dispose() }
    $transaction.Commit()
    "Instalacion confirmada. Destino=$BaseLaboratorio; Archivos=$($preparedFiles.Count)."
} catch {
    if ($null -ne $transaction) { try { $transaction.Rollback() } catch {} }
    $number = 0
    $failure = $_.Exception
    while ($null -ne $failure) {
        if ($failure -is [System.Data.SqlClient.SqlException]) { $number = $failure.Number; break }
        $failure = $failure.InnerException
    }
    # Never emit Exception.Message, SQL text, connection strings or server identity.
    $errorLine = $_.InvocationInfo.ScriptLineNumber
    $errorType = $_.Exception.GetType().Name
    throw "Instalacion detenida. Etapa=$stage; CodigoSql=$number; Preflight=$preflight; Linea=$errorLine; Tipo=$errorType. Se intento rollback si habia transaccion. No se elimina ninguna base; puede quedar el laboratorio vacio. Revisar privadamente con el DBA, incluido TLS."
} finally {
    if ($null -ne $transaction) { $transaction.Dispose() }
    if ($null -ne $connection) { $connection.Dispose() }
}
