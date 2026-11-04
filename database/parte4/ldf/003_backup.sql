CREATE OR ALTER PROCEDURE dbo.P4_LDF_RespaldarLog
 @ActorUsuarioId int, @OperacionId uniqueidentifier
AS
BEGIN
 SET NOCOUNT ON;
 -- BACKUP must not run inside an application transaction.
 IF @@TRANCOUNT <> 0 THROW 59011, 'LDF: respaldo requiere conexion sin transaccion externa.', 1;
 EXEC dbo.P4_LDF_Validar @ActorUsuarioId, N'DBA_LDF_CONSULTAR';
 EXEC dbo.P4_LDF_Validar @ActorUsuarioId, N'DBA_LDF_RESPALDAR_LOG';
 IF @OperacionId IS NULL THROW 59012, 'LDF: referencia obligatoria.', 1;

 DECLARE @Lock int, @Db sysname = DB_NAME(), @File nvarchar(2000), @Root nvarchar(1500),
 @Guid uniqueidentifier, @Fork uniqueidentifier, @LSN numeric(25,0), @BackupId int,
 @Name nvarchar(128) = CONCAT(N'P4_LDF:',CONVERT(nvarchar(36),@OperacionId)), @Code int;
 -- Integration contract: Edward uses this SAME resource, DB and principal for FULL/DIFF/LOG.
 EXEC @Lock = sys.sp_getapplock @Resource=N'SecureFinanceERP:BACKUP', @LockMode='Exclusive',
 @LockOwner='Session', @LockTimeout=0, @DbPrincipal='public';
 IF @Lock < 0 THROW 59013, 'Ya hay una operacion de respaldo; actualiza antes de reintentar.', 1;
 BEGIN TRY
  SELECT @Guid=database_guid, @Fork=recovery_fork_guid, @LSN=last_log_backup_lsn
  FROM sys.database_recovery_status WHERE database_id=DB_ID();
  IF EXISTS (SELECT 1 FROM dbo.P4_LDF_Ejecucion WHERE OperacionId=@OperacionId)
  BEGIN
   IF EXISTS (SELECT 1 FROM dbo.P4_LDF_Ejecucion WHERE OperacionId=@OperacionId AND ActorUsuarioId<>@ActorUsuarioId)
    THROW 59014, 'Referencia perteneciente a otra solicitud.', 1;
   -- Reconcile an interrupted connection from engine history, NEVER issue another BACKUP.
   IF EXISTS (SELECT 1 FROM dbo.P4_LDF_Ejecucion WHERE OperacionId=@OperacionId AND Estado IN ('EN_CURSO','INCIERTO'))
   BEGIN
    SELECT @File=Archivo FROM dbo.P4_LDF_Ejecucion WHERE OperacionId=@OperacionId;
    SELECT @BackupId=MAX(b.backup_set_id) FROM msdb.dbo.backupset b
    JOIN msdb.dbo.backupmediafamily m ON m.media_set_id=b.media_set_id
    WHERE b.name=@Name AND b.database_guid=@Guid AND b.last_recovery_fork_guid=@Fork
    AND b.type='L' AND b.backup_finish_date IS NOT NULL AND b.is_damaged=0 AND m.physical_device_name=@File;
    UPDATE dbo.P4_LDF_Ejecucion SET Estado=CASE WHEN @BackupId IS NULL THEN 'INCIERTO' ELSE 'CONFIRMADO' END,
    BackupSetId=@BackupId, FinUTC=SYSUTCDATETIME(), Mensaje=CASE WHEN @BackupId IS NULL
    THEN N'Sin confirmacion del motor. El DBA debe revisar el archivo y msdb antes de otra solicitud.'
    ELSE N'Respaldo confirmado por historial del motor; no se repitio.' END WHERE OperacionId=@OperacionId;
   END;
  END
  ELSE
  BEGIN
   INSERT dbo.P4_LDF_Ejecucion (OperacionId,ActorUsuarioId,LoginSQL,InicioUTC,Estado,Mensaje)
   VALUES (@OperacionId,@ActorUsuarioId,ORIGINAL_LOGIN(),SYSUTCDATETIME(),'EN_CURSO',N'Comprobando requisitos.');
   BEGIN TRY
    IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE database_id=DB_ID() AND recovery_model_desc IN ('FULL','BULK_LOGGED')
     AND state_desc='ONLINE' AND is_read_only=0)
     THROW 59015, 'El estado o modelo de recuperacion no permite BACKUP LOG.', 1;
    IF @LSN IS NULL THROW 59016, 'Falta respaldo completo o diferencial vigente que inicie la cadena LOG.', 1;
    IF HAS_PERMS_BY_NAME(DB_NAME(), 'DATABASE', 'BACKUP LOG') <> 1
     THROW 59017, 'La identidad administrativa no tiene BACKUP LOG.', 1;
    SELECT @Root=RutaBackup FROM dbo.P4_LDF_Configuracion WHERE Id=1;
    IF @Root IS NULL OR LEN(@Root)<3 OR @Root LIKE N'%..%' OR RIGHT(@Root,1) NOT IN (N'\',N'/')
     THROW 59018, 'Ruta de respaldo no autorizada.', 1;
    IF NOT EXISTS (SELECT 1 FROM sys.dm_os_file_exists(@Root) WHERE file_is_a_directory=1)
     THROW 59018, 'El directorio autorizado no existe en el servidor SQL.', 1;
    SET @File=CONCAT(@Root,N'P4_LDF_',DB_ID(),N'_',CONVERT(nvarchar(36),@OperacionId),N'.trn');
    UPDATE dbo.P4_LDF_Ejecucion SET Archivo=@File,Mensaje=N'Ejecutando BACKUP LOG con CHECKSUM.' WHERE OperacionId=@OperacionId;
    -- Fixed database; only an installation-approved directory. No browser path or SQL input.
    -- NOINIT + UUID filename: never overwrite another backup. Normal log backup, not COPY_ONLY.
    BACKUP LOG @Db TO DISK=@File WITH CHECKSUM, NOINIT, NOFORMAT, NAME=@Name;
    SELECT @BackupId=MAX(b.backup_set_id) FROM msdb.dbo.backupset b
    JOIN msdb.dbo.backupmediafamily m ON m.media_set_id=b.media_set_id
    WHERE b.name=@Name AND b.database_guid=@Guid AND b.last_recovery_fork_guid=@Fork
    AND b.type='L' AND b.backup_finish_date IS NOT NULL AND b.is_damaged=0 AND m.physical_device_name=@File;
    UPDATE dbo.P4_LDF_Ejecucion SET Estado=CASE WHEN @BackupId IS NULL THEN 'INCIERTO' ELSE 'CONFIRMADO' END,
    BackupSetId=@BackupId, FinUTC=SYSUTCDATETIME(), Mensaje=CASE WHEN @BackupId IS NULL
    THEN N'El comando termino pero falta confirmacion en msdb. Consultar al DBA.'
    ELSE N'BACKUP LOG completado con CHECKSUM y confirmado en msdb.' END WHERE OperacionId=@OperacionId;
   END TRY
   BEGIN CATCH
    SET @Code=ERROR_NUMBER();
    UPDATE dbo.P4_LDF_Ejecucion SET Estado='FALLIDO',FinUTC=SYSUTCDATETIME(),CodigoSQL=@Code,
    Mensaje=CASE @Code WHEN 59015 THEN N'Modelo o estado incompatible con BACKUP LOG.'
    WHEN 59016 THEN N'Cadena LOG no iniciada: se requiere respaldo FULL o diferencial vigente.'
    WHEN 59017 THEN N'Permiso BACKUP LOG ausente; revisar firma del procedimiento.'
    WHEN 59018 THEN N'Ruta no autorizada. Revisar configuracion con el DBA.'
    WHEN 3201 THEN N'El servicio SQL no puede abrir el destino. Revisar directorio y permisos del servicio.'
    ELSE N'SQL Server rechazo el respaldo. El DBA debe revisar el codigo y el registro del motor.' END
    WHERE OperacionId=@OperacionId;
   END CATCH;
  END;
  EXEC sys.sp_releaseapplock @Resource=N'SecureFinanceERP:BACKUP',@LockOwner='Session',@DbPrincipal='public';
 END TRY
 BEGIN CATCH
  EXEC sys.sp_releaseapplock @Resource=N'SecureFinanceERP:BACKUP',@LockOwner='Session',@DbPrincipal='public';
  THROW;
 END CATCH;
 SELECT OperacionId,ActorUsuarioId,InicioUTC,FinUTC,Estado,Archivo,BackupSetId,CodigoSQL,Mensaje
 FROM dbo.P4_LDF_Ejecucion WHERE OperacionId=@OperacionId;
END;
GO
