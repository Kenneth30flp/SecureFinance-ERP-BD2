param(
    [Parameter(Mandatory=$true)][string]$Server,
    [string]$Database = ('SecureFinanceERP_ParteII_Test_' + [guid]::NewGuid().ToString('N')),
    [switch]$Run,
    [switch]$AuditOnly,
    [switch]$TrustServerCertificate
)
$ErrorActionPreference = 'Stop'
if (-not $Run -and -not $AuditOnly) { throw 'Ejecucion deshabilitada. Usar -Run solo con autorizacion para crear una base aislada.' }
if ($Database -cnotmatch '^SecureFinanceERP_ParteII_Test_[A-Za-z0-9_]+$' -or $Database.Length -gt 128) {
    throw 'Nombre de base aislada invalido.'
}
$databaseRoot = Split-Path -Parent $PSScriptRoot
$runToken = [guid]::NewGuid().ToString('N')
$scriptParts = [System.Collections.Generic.List[string]]::new()
$scriptParts.Add(":ON ERROR EXIT`nUSE [master];`nGO`nIF DB_ID(N'$Database') IS NOT NULL THROW 54900,'La base aislada ya existe. No se sobrescribe.',1;`nCREATE DATABASE [$Database];`nGO`nUSE [$Database];`nGO`nEXEC sys.sp_addextendedproperty @name=N'ParteII.TestRun',@value=N'$runToken';`nGO")
function Add-IsolatedScript([string]$Text) {
    # Bloquear cambios de contexto y operaciones de servidor antes de conectar.
    foreach ($use in [regex]::Matches($Text,'(?im)\bUSE\s+\[?(\w+)\]?\s*;')) {
        if ($use.Groups[1].Value -cne $Database) { throw "Contexto SQL no permitido: $($use.Groups[1].Value)" }
    }
    $identifierText = $Text.Replace('[','').Replace(']','')
    if ($Text -match '(?im)^\s*(:|!!)' -or
        $Text -match '(?i)\b(CREATE|ALTER|DROP)\s+(DATABASE|LOGIN|SERVER)\b|\b(BACKUP|RESTORE|OPENROWSET|OPENDATASOURCE|OPENQUERY)\b' -or
        $identifierText -match '(?i)\b[A-Z_]\w*\s*\.\s*\w+\s*\.\s*\w+\b|\b[A-Z_]\w*\s*\.\s*\.\s*\w+\b') {
        throw 'Instruccion de servidor, SQLCMD o referencia cruzada no permitida.'
    }
    # Un guard separado permite que CREATE PROCEDURE/FUNCTION sea primero en su lote.
    foreach ($batch in [regex]::Split($Text,'(?im)^\s*GO\s*\r?$')) {
        if ([string]::IsNullOrWhiteSpace($batch)) { continue }
        $scriptParts.Add("USE [$Database];`nGO`nIF DB_NAME()<>N'$Database' OR NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=0 AND name=N'ParteII.TestRun' AND CONVERT(NVARCHAR(32),value)=N'$runToken') THROW 54900,'Contexto o propietario de ejecucion incorrecto.',1;`nGO")
        $scriptParts.Add($batch + "`nGO")
    }
}
# Solo transforma el instalador en memoria para una base NUEVA con nombre validado.
# No ejecuta el Full sobre SecureFinanceERP ni modifica archivos de instalacion.
$full = [IO.File]::ReadAllText((Join-Path $databaseRoot 'SecureFinanceERP_Full.sql'))
# La creacion ya fue exclusiva. Se elimina en memoria el preambulo master del Full.
$firstApplicationUse = $full.IndexOf('USE [SecureFinanceERP];')
if ($firstApplicationUse -lt 0) { throw 'Instalador base sin contexto esperado.' }
Add-IsolatedScript ($full.Substring($firstApplicationUse).Replace('SecureFinanceERP', $Database))
Add-IsolatedScript "IF DATABASE_PRINCIPAL_ID(N'securefinance_app') IS NULL CREATE USER securefinance_app WITHOUT LOGIN;"
Add-IsolatedScript @'
CREATE TABLE #ParteI (ObjetoId INT PRIMARY KEY, Definicion NVARCHAR(MAX));
-- Factura anterior a Parte II: fixture exclusivo de esta base nueva.
DECLARE @ClienteAnterior INT=(SELECT TOP(1) ClienteId FROM dbo.Cliente ORDER BY ClienteId),
 @ActorAnterior INT=(SELECT TOP(1) UsuarioId FROM dbo.Usuario ORDER BY UsuarioId);
INSERT dbo.Factura(ClienteId,UsuarioId,Subtotal,IVA,Total)
VALUES(@ClienteAnterior,@ActorAnterior,0,0,0);
INSERT #ParteI SELECT object_id,definition FROM sys.sql_modules
WHERE object_id IN (OBJECT_ID('dbo.sp_ProcesarVentaTransaccional'),OBJECT_ID('dbo.sp_ProcesarVentaSinDescuento'),
 OBJECT_ID('dbo.sp_Login'),OBJECT_ID('dbo.sp_RestablecerPassword'),OBJECT_ID('dbo.sp_ObtenerResumenDashboard'),
 OBJECT_ID('dbo.fn_ObtenerHistoricoVentas'));
SELECT ProductoId,Stock INTO #StockInicial FROM dbo.Producto;
SELECT FacturaId,ClienteId,UsuarioId,FechaHora,Subtotal,DescuentoTotal,IVA,Total INTO #FacturasInicial FROM dbo.Factura;
GO
'@
$migrations = @('15_ParteII_Preflight.sql','16_ParteII_Catalogos.sql','17_ParteII_Kardex.sql',
    '18_ParteII_Procedimientos.sql','19_ParteII_Auditoria.sql','20_ParteII_Permisos.sql')
# Dos pasadas verifican repetibilidad, sin apertura ni reposicion de existencias.
foreach ($pass in 1..2) {
    foreach ($migration in $migrations) {
        Add-IsolatedScript "PRINT 'MIGRATION PASS $pass : $migration';"
        Add-IsolatedScript ([IO.File]::ReadAllText((Join-Path $databaseRoot $migration)))
    }
    if ($pass -eq 1) {
        Add-IsolatedScript @'
SELECT type,name,parent_object_id INTO #ObjetosPrimeraPasada FROM sys.objects WHERE is_ms_shipped=0;
SELECT object_id,name,index_id,is_unique,filter_definition INTO #IndicesPrimeraPasada FROM sys.indexes WHERE object_id IN(SELECT object_id FROM sys.objects WHERE is_ms_shipped=0);
GO
'@
    }
}
Add-IsolatedScript @'
IF EXISTS(SELECT type,name,parent_object_id FROM sys.objects WHERE is_ms_shipped=0 EXCEPT SELECT * FROM #ObjetosPrimeraPasada)
 OR EXISTS(SELECT * FROM #ObjetosPrimeraPasada EXCEPT SELECT type,name,parent_object_id FROM sys.objects WHERE is_ms_shipped=0)
 THROW 54900,'Segunda pasada cambio el inventario de objetos.',1;
IF EXISTS(SELECT object_id,name,index_id,is_unique,filter_definition FROM sys.indexes WHERE object_id IN(SELECT object_id FROM sys.objects WHERE is_ms_shipped=0) EXCEPT SELECT * FROM #IndicesPrimeraPasada)
 THROW 54900,'Segunda pasada cambio indices.',1;
DECLARE @Modulo SYSNAME;
DECLARE Modulos CURSOR LOCAL FAST_FORWARD FOR
 SELECT QUOTENAME(SCHEMA_NAME(o.schema_id))+N'.'+QUOTENAME(o.name)
 FROM sys.objects o JOIN sys.sql_modules m ON m.object_id=o.object_id WHERE o.is_ms_shipped=0;
OPEN Modulos;
FETCH NEXT FROM Modulos INTO @Modulo;
WHILE @@FETCH_STATUS=0
BEGIN
 EXEC sys.sp_refreshsqlmodule @name=@Modulo;
 FETCH NEXT FROM Modulos INTO @Modulo;
END;
CLOSE Modulos;
DEALLOCATE Modulos;
PRINT 'PASS: segunda pasada sin duplicados; modulos recompilados.';
IF EXISTS(SELECT 1 FROM #ParteI b JOIN sys.sql_modules m ON m.object_id=b.ObjetoId
 WHERE CONVERT(VARBINARY(MAX),b.Definicion)<>CONVERT(VARBINARY(MAX),m.definition))
 THROW 54900,'Se alteraron procedimientos de Parte I.',1;
IF EXISTS(SELECT ProductoId,Stock FROM #StockInicial EXCEPT SELECT ProductoId,Stock FROM dbo.Producto)
 THROW 54900,'Las migraciones alteraron existencias.',1;
IF EXISTS(SELECT * FROM #FacturasInicial EXCEPT SELECT FacturaId,ClienteId,UsuarioId,FechaHora,Subtotal,DescuentoTotal,IVA,Total FROM dbo.Factura)
 THROW 54900,'Las migraciones alteraron facturas.',1;
IF EXISTS(SELECT 1 FROM dbo.Factura f JOIN #FacturasInicial b ON b.FacturaId=f.FacturaId
 WHERE f.ClienteNITEmision IS NOT NULL OR f.ClienteNombreEmision IS NOT NULL)
 THROW 54900,'Las migraciones inventaron identidad historica.',1;
IF EXISTS(SELECT 1 FROM dbo.Kardex_Inventario) OR EXISTS(SELECT 1 FROM dbo.ConfiguracionInventario WHERE Habilitado=1)
 THROW 54900,'Apertura prematura.',1;
GO
'@
Add-IsolatedScript ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'ParteIIKennethTests.sql')))
Add-IsolatedScript ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'ParteIIKennethSupplementalTests.sql')))
# Regresion del contrato de auditoria heredado, en esta misma base AISLADA.
$legacyAudit = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'AuditTests.sql'))
Add-IsolatedScript ($legacyAudit.Replace('[SecureFinanceERP]', "[$Database]"))
if ($AuditOnly) {
    Write-Output "AUDIT PASS: $Database; bootstrap master exclusivo CREATE DATABASE; resto con contexto y token de ejecucion verificados; sin DROP DATABASE ni referencias cruzadas. $($scriptParts.Count) bloques preparados, cero consultas ejecutadas."
    return
}
$tempSql = [IO.Path]::GetTempFileName()
try {
    [IO.File]::WriteAllText($tempSql, ($scriptParts -join "`n"), [Text.UTF8Encoding]::new($false))
    $arguments = @('-S',$Server,'-E','-b','-r','0','-f','65001','-i',$tempSql)
    if ($TrustServerCertificate) { $arguments += '-C' }
    & sqlcmd @arguments
    if ($LASTEXITCODE -ne 0) { throw "Pruebas SQL fallidas. Base aislada conservada: $Database" }
    Write-Output "PASS SQL: $Database. Base conservada para inspeccion; no se elimina automaticamente."
} finally {
    Remove-Item -LiteralPath $tempSql -ErrorAction SilentlyContinue
}
