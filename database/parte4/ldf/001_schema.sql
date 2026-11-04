-- Run through scripts/parte4/ldf/install.cjs, in one external transaction.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF @@TRANCOUNT <> 1 OR DB_ID() <= 4
 OR CONVERT(nvarchar(256), SESSION_CONTEXT(N'P4_LDF.InstallTarget')) <> CONCAT(CONVERT(nvarchar(128), SERVERPROPERTY('ServerName')), N'|', DB_NAME())
 OR SESSION_CONTEXT(N'P4_LDF.InstallTarget') IS NULL
 THROW 59010, 'LDF: destino de instalacion no autorizado.', 1;
IF TRY_CONVERT(int, SERVERPROPERTY('ProductMajorVersion')) < 14
 OR OBJECT_ID(N'dbo.sp_ParteII_ValidarPermiso', N'P') IS NULL
 OR DATABASE_PRINCIPAL_ID(N'securefinance_app') IS NULL
 THROW 59010, 'LDF: requiere SQL Server 2017+ y seguridad de Parte II.', 1;
IF OBJECT_ID(N'dbo.P4_LDF_Configuracion') IS NOT NULL
 THROW 59010, 'LDF ya instalado. No sobrescribir configuracion ni firmas.', 1;

CREATE TABLE dbo.P4_LDF_Configuracion (
 Id tinyint NOT NULL CONSTRAINT P4_LDF_PK_Configuracion PRIMARY KEY CHECK (Id = 1),
 Servidor nvarchar(128) NOT NULL, BaseDatos sysname NOT NULL,
 DatabaseGuid uniqueidentifier NOT NULL, Habilitado bit NOT NULL,
 RutaBackup nvarchar(1500) NOT NULL,
 Advertencia decimal(5,2) NOT NULL, Critico decimal(5,2) NOT NULL,
 CONSTRAINT P4_LDF_CK_Umbrales CHECK (Advertencia > 0 AND Advertencia < Critico AND Critico <= 100)
);
CREATE TABLE dbo.P4_LDF_Ejecucion (
 OperacionId uniqueidentifier NOT NULL CONSTRAINT P4_LDF_PK_Ejecucion PRIMARY KEY,
 ActorUsuarioId int NOT NULL, LoginSQL sysname NOT NULL,
 InicioUTC datetime2(3) NOT NULL, FinUTC datetime2(3) NULL,
 Estado varchar(16) NOT NULL CHECK (Estado IN ('EN_CURSO','CONFIRMADO','FALLIDO','INCIERTO')),
 Archivo nvarchar(2000) NULL, BackupSetId int NULL, CodigoSQL int NULL,
 Mensaje nvarchar(300) NOT NULL
);
CREATE INDEX P4_LDF_IX_Ejecucion_Fecha ON dbo.P4_LDF_Ejecucion (InicioUTC DESC);
INSERT dbo.Permiso (Codigo, Descripcion)
 SELECT p.Codigo, p.Descripcion FROM (VALUES
 (N'DBA_LDF_CONSULTAR', N'Consultar metricas reales, archivos, VLF e historial LOG.'),
 (N'DBA_LDF_RESPALDAR_LOG', N'Ejecutar respaldo manual del LOG en destino autorizado.')
 ) p(Codigo, Descripcion)
 WHERE NOT EXISTS (SELECT 1 FROM dbo.Permiso x WHERE x.Codigo = p.Codigo);
-- Roles are assigned explicitly by the installer/operator, never implicitly here.
GO
CREATE OR ALTER PROCEDURE dbo.P4_LDF_Validar
 @ActorUsuarioId int, @Permiso nvarchar(100)
AS
BEGIN
 SET NOCOUNT ON;
 IF NOT EXISTS (SELECT 1 FROM dbo.P4_LDF_Configuracion c
 JOIN sys.database_recovery_status r ON r.database_id = DB_ID() AND r.database_guid = c.DatabaseGuid
 WHERE c.Id = 1 AND c.Habilitado = 1 AND DB_ID() > 4
 AND c.BaseDatos COLLATE Latin1_General_100_BIN2 = DB_NAME() COLLATE Latin1_General_100_BIN2
 AND c.Servidor = CONVERT(nvarchar(128), SERVERPROPERTY('ServerName')))
 THROW 59010, 'LDF: destino no autorizado o identidad de base modificada.', 1;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId, @Permiso;
END;
GO
