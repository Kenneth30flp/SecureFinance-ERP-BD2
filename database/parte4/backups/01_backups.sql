-- Instalación explícita por DBA en la base ERP seleccionada. No cambia recovery model.
:ON ERROR EXIT
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID('dbo.BackupsJob') IS NULL
CREATE TABLE dbo.BackupsJob(
 Id uniqueidentifier NOT NULL PRIMARY KEY, Tipo varchar(10) NOT NULL,
 ActorUsuarioId int NULL, Creado datetime2 NOT NULL DEFAULT SYSUTCDATETIME(),
 Inicio datetime2 NULL, Fin datetime2 NULL, Estado varchar(20) NOT NULL DEFAULT 'PENDIENTE',
 Punto varchar(19) NULL, Destino nvarchar(128) NULL, PlanId uniqueidentifier NULL,
 PlanJson nvarchar(max) NULL, Resultado nvarchar(max) NULL, ErrorNumero int NULL,
 Slot varchar(40) NULL,
 CONSTRAINT CK_BackupsTipo CHECK(Tipo IN('FULL','DIFF','LOG','PLAN','RESTORE')));
-- Filtered index permits multiple manual jobs without a schedule slot.
GO
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.BackupsJob') AND name='UX_BackupsSlot') CREATE UNIQUE INDEX UX_BackupsSlot ON dbo.BackupsJob(Slot) WHERE Slot IS NOT NULL;
IF OBJECT_ID('dbo.BackupsSchedule') IS NULL
CREATE TABLE dbo.BackupsSchedule(Id int NOT NULL PRIMARY KEY CHECK(Id=1), Enabled bit NOT NULL DEFAULT 0, CursorUtc datetime2 NOT NULL DEFAULT SYSUTCDATETIME(), HeartbeatUtc datetime2 NULL);
IF NOT EXISTS(SELECT 1 FROM dbo.BackupsSchedule) INSERT dbo.BackupsSchedule(Id) VALUES(1);
IF OBJECT_ID('dbo.BackupsConfig') IS NULL
CREATE TABLE dbo.BackupsConfig(Id int NOT NULL PRIMARY KEY CHECK(Id=1), Ruta nvarchar(240) NOT NULL, Compresion bit NOT NULL DEFAULT 0);
IF OBJECT_ID('dbo.BackupsExecution') IS NULL
CREATE TABLE dbo.BackupsExecution(Id uniqueidentifier NOT NULL PRIMARY KEY, Tipo varchar(4) NOT NULL, Ruta nvarchar(400) NOT NULL, Inicio datetime2 NOT NULL DEFAULT SYSUTCDATETIME(), Fin datetime2 NULL, Estado varchar(20) NOT NULL, ErrorNumero int NULL);
IF OBJECT_ID('dbo.BackupsCatalog') IS NULL
CREATE TABLE dbo.BackupsCatalog(Id int NOT NULL PRIMARY KEY, JsonData nvarchar(max) NOT NULL, Actualizado datetime2 NOT NULL DEFAULT SYSUTCDATETIME());
IF OBJECT_ID('dbo.BackupsAudit') IS NULL
CREATE TABLE dbo.BackupsAudit(Id bigint IDENTITY PRIMARY KEY,JobId uniqueidentifier NOT NULL,Evento varchar(30) NOT NULL,ActorUsuarioId int NULL,FechaUtc datetime2 NOT NULL DEFAULT SYSUTCDATETIME(),LoginSql sysname NOT NULL DEFAULT ORIGINAL_LOGIN());
INSERT dbo.Permiso(Codigo,Descripcion)
SELECT Codigo,N'UC13: '+Codigo FROM (VALUES('DBA_BACKUPS_CONSULTAR'),('DBA_BACKUPS_EJECUTAR'),('DBA_BACKUPS_RESTAURAR')) p(Codigo)
WHERE NOT EXISTS(SELECT 1 FROM dbo.Permiso x WHERE x.Codigo=p.Codigo);
GO
CREATE OR ALTER PROCEDURE dbo.sp_BackupsConsultar @ActorUsuarioId int AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'DBA_BACKUPS_CONSULTAR';
 SELECT TOP(100) * FROM dbo.BackupsJob ORDER BY Creado DESC;
 SELECT *,SYSUTCDATETIME() AS AhoraUtc FROM dbo.BackupsSchedule;
 SELECT * FROM dbo.BackupsCatalog;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_BackupsSolicitar @ActorUsuarioId int,@Id uniqueidentifier,@Tipo varchar(10),@Punto varchar(19)=NULL,@Destino nvarchar(128)=NULL,@PlanId uniqueidentifier=NULL AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 SET ANSI_WARNINGS ON; SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET NUMERIC_ROUNDABORT OFF;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'DBA_BACKUPS_CONSULTAR';
 DECLARE @Permiso nvarchar(100)=CASE WHEN @Tipo IN('PLAN','RESTORE') THEN N'DBA_BACKUPS_RESTAURAR' ELSE N'DBA_BACKUPS_EJECUTAR' END;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,@Permiso;
 IF @Tipo IS NULL OR @Tipo NOT IN('FULL','DIFF','LOG','PLAN','RESTORE') OR @Id IS NULL THROW 58001,'Solicitud invalida.',1;
 IF @Tipo='PLAN' AND (@Punto IS NULL OR TRY_CONVERT(datetime,@Punto,126) IS NULL OR CONVERT(varchar(19),TRY_CONVERT(datetime,@Punto,126),126)<>@Punto OR @Destino IS NULL OR @Destino COLLATE Latin1_General_100_BIN2 NOT LIKE N'SF[_]Recovery[_]%' OR @Destino COLLATE Latin1_General_100_BIN2 LIKE '%[^a-zA-Z0-9_]%' OR LEN(@Destino) NOT BETWEEN 13 AND 92 OR @Destino=DB_NAME()) THROW 58001,'Punto o destino invalido.',1;
 BEGIN TRAN;
 IF EXISTS(SELECT 1 FROM dbo.BackupsJob WITH(UPDLOCK,HOLDLOCK) WHERE Id=@Id)
 BEGIN
  IF NOT EXISTS(SELECT 1 FROM dbo.BackupsJob WHERE Id=@Id AND ActorUsuarioId=@ActorUsuarioId AND Tipo=@Tipo AND ISNULL(Punto,'')=ISNULL(@Punto,'') AND ISNULL(Destino,'')=ISNULL(@Destino,'') AND ISNULL(CONVERT(varchar(36),PlanId),'')=ISNULL(CONVERT(varchar(36),@PlanId),'')) THROW 58001,'Referencia reutilizada.',1;
 END
 ELSE BEGIN
  IF @Tipo='RESTORE'
  BEGIN
   IF NOT EXISTS(SELECT 1 FROM dbo.BackupsJob WITH(UPDLOCK,HOLDLOCK) WHERE Id=@PlanId AND Tipo='PLAN' AND Estado='COMPLETADO' AND ActorUsuarioId=@ActorUsuarioId AND Fin>DATEADD(minute,-30,SYSUTCDATETIME())) THROW 58001,'Plan inexistente o vencido.',1;
   IF EXISTS(SELECT 1 FROM dbo.BackupsJob WHERE PlanId=@PlanId AND Tipo='RESTORE') THROW 58001,'Plan ya solicitado.',1;
  END;
  INSERT dbo.BackupsJob(Id,Tipo,ActorUsuarioId,Punto,Destino,PlanId) VALUES(@Id,@Tipo,@ActorUsuarioId,@Punto,@Destino,@PlanId);
  INSERT dbo.BackupsAudit(JobId,Evento,ActorUsuarioId) VALUES(@Id,'SOLICITADO',@ActorUsuarioId);
 END;
 COMMIT;
 SELECT Id,Estado FROM dbo.BackupsJob WHERE Id=@Id;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_EjecutarBackupEstrategico @TipoBackup varchar(4),@RutaDestino nvarchar(240) AS
BEGIN
 SET NOCOUNT ON;
 IF @@TRANCOUNT>0 THROW 58002,'BACKUP no admite transaccion externa.',1;
 IF @TipoBackup IS NULL OR @TipoBackup NOT IN('FULL','DIFF','LOG') THROW 58002,'Tipo invalido.',1;
 IF @RutaDestino IS NULL OR NOT EXISTS(SELECT 1 FROM dbo.BackupsConfig WHERE Id=1 AND Ruta=@RutaDestino) OR @RutaDestino LIKE '%..%' OR RIGHT(@RutaDestino,1)<>N'\' THROW 58002,'Ruta no autorizada.',1;
 IF DATABASEPROPERTYEX(DB_NAME(),'Recovery')<>'FULL' THROW 58002,'Se requiere recovery FULL y cadena inicializada por DBA.',1;
 DECLARE @lock int;
 EXEC @lock=sys.sp_getapplock @Resource='UC13_BACKUP',@LockMode='Exclusive',@LockOwner='Session',@LockTimeout=0;
 IF @lock<0 THROW 58002,'Otro respaldo esta activo.',1;
 DECLARE @id uniqueidentifier=NEWID(),@file nvarchar(400),@cmd nvarchar(max),@compression bit;
 SET @file=@RutaDestino+CONVERT(nvarchar(36),@id)+CASE WHEN @TipoBackup='LOG' THEN '.trn' ELSE '.bak' END;
 BEGIN TRY
  INSERT dbo.BackupsExecution(Id,Tipo,Ruta,Estado) VALUES(@id,@TipoBackup,@file,'EJECUTANDO');
  IF @TipoBackup IN('DIFF','LOG') AND NOT EXISTS(SELECT 1 FROM msdb.dbo.backupset WHERE database_name=DB_NAME() AND type='D' AND is_copy_only=0 AND recovery_model='FULL' AND database_guid=(SELECT database_guid FROM sys.database_recovery_status WHERE database_id=DB_ID())) THROW 58002,'Falta FULL base.',1;
  SELECT @compression=Compresion FROM dbo.BackupsConfig WHERE Id=1;
  IF @compression=1 AND CONVERT(int,SERVERPROPERTY('EngineEdition')) NOT IN(2,3) THROW 58002,'Compresion no compatible con esta edicion.',1;
  SET @cmd=N'BACKUP '+CASE WHEN @TipoBackup='LOG' THEN N'LOG ' ELSE N'DATABASE ' END+QUOTENAME(DB_NAME())+N' TO DISK=@file WITH CHECKSUM, NOINIT, '+CASE WHEN @TipoBackup='DIFF' THEN N'DIFFERENTIAL, ' ELSE N'' END+CASE WHEN @compression=1 THEN N'COMPRESSION' ELSE N'NO_COMPRESSION' END+N'; RESTORE VERIFYONLY FROM DISK=@file WITH CHECKSUM;';
  EXEC sys.sp_executesql @cmd,N'@file nvarchar(400)',@file;
  UPDATE dbo.BackupsExecution SET Estado='VERIFICADO',Fin=SYSUTCDATETIME() WHERE Id=@id;
  EXEC sys.sp_releaseapplock @Resource='UC13_BACKUP',@LockOwner='Session';
  SELECT Id,Tipo,Ruta,Estado FROM dbo.BackupsExecution WHERE Id=@id;
 END TRY
 BEGIN CATCH
  UPDATE dbo.BackupsExecution SET Estado='FALLIDO',Fin=SYSUTCDATETIME(),ErrorNumero=ERROR_NUMBER() WHERE Id=@id;
  EXEC sys.sp_releaseapplock @Resource='UC13_BACKUP',@LockOwner='Session'; THROW;
 END CATCH;
END;
GO
