-- SQLCMD: -v ErpDatabase="..." WebUser="..." WorkerLogin="..." WorkerUser="..."
-- Existing dedicated logins/users only. Does not create credentials or assign ERP roles.
:ON ERROR EXIT
USE [$(ErpDatabase)];
GO
BEGIN TRANSACTION;
IF DATABASE_PRINCIPAL_ID(N'$(WebUser)') IS NULL OR DATABASE_PRINCIPAL_ID(N'$(WorkerUser)') IS NULL THROW 58003,'Cree previamente los usuarios dedicados.',1;
DECLARE @WebSid varbinary(85)=(SELECT sid FROM sys.database_principals WHERE name=N'$(WebUser)'),@WorkerSid varbinary(85)=(SELECT sid FROM sys.database_principals WHERE name=N'$(WorkerUser)');
IF SUSER_ID(N'$(WorkerLogin)') IS NULL OR @WorkerSid<>SUSER_SID(N'$(WorkerLogin)') OR @WebSid=@WorkerSid OR ISNULL(IS_SRVROLEMEMBER('sysadmin',N'$(WorkerLogin)'),1)<>0 THROW 58003,'Separacion de logins requerida.',1;
IF IS_ROLEMEMBER('db_owner',N'$(WorkerUser)')=1 OR @WorkerSid=(SELECT owner_sid FROM sys.databases WHERE database_id=DB_ID()) THROW 58003,'El ejecutor no debe ser propietario del ERP.',1;
IF IS_ROLEMEMBER('db_owner',N'$(WebUser)')=1 OR IS_SRVROLEMEMBER('sysadmin',SUSER_SNAME((SELECT sid FROM sys.database_principals WHERE name=N'$(WebUser)')))=1 THROW 58003,'Cuenta web privilegiada no permitida.',1;
GRANT EXECUTE ON dbo.sp_BackupsConsultar TO [$(WebUser)];
GRANT EXECUTE ON dbo.sp_BackupsSolicitar TO [$(WebUser)];
DENY EXECUTE ON dbo.sp_EjecutarBackupEstrategico TO [$(WebUser)];
DENY SELECT,INSERT,UPDATE,DELETE ON dbo.BackupsJob TO [$(WebUser)];
DENY SELECT,INSERT,UPDATE,DELETE ON dbo.BackupsSchedule TO [$(WebUser)];
DENY SELECT,INSERT,UPDATE,DELETE ON dbo.BackupsConfig TO [$(WebUser)];
DENY SELECT,INSERT,UPDATE,DELETE ON dbo.BackupsCatalog TO [$(WebUser)];
DENY SELECT,INSERT,UPDATE,DELETE ON dbo.BackupsExecution TO [$(WebUser)];
DENY SELECT,INSERT,UPDATE,DELETE ON dbo.BackupsAudit TO [$(WebUser)];
GRANT EXECUTE ON dbo.sp_EjecutarBackupEstrategico TO [$(WorkerUser)];
GRANT EXECUTE ON dbo.sp_BackupsRutas TO [$(WorkerUser)];
GRANT EXECUTE ON dbo.sp_ParteII_ValidarPermiso TO [$(WorkerUser)];
GRANT BACKUP DATABASE,BACKUP LOG TO [$(WorkerUser)];
GRANT SELECT,INSERT,UPDATE ON dbo.BackupsJob TO [$(WorkerUser)];
GRANT SELECT,UPDATE ON dbo.BackupsSchedule TO [$(WorkerUser)];
GRANT SELECT ON dbo.BackupsConfig TO [$(WorkerUser)];
GRANT SELECT,INSERT,UPDATE ON dbo.BackupsCatalog TO [$(WorkerUser)];
GRANT INSERT,SELECT ON dbo.BackupsAudit TO [$(WorkerUser)];
GO
USE master;
GO
-- Needed to restore a NEW database and to reliably reject existing targets.
GRANT CREATE ANY DATABASE TO [$(WorkerLogin)];
GRANT VIEW ANY DATABASE TO [$(WorkerLogin)];
GO
USE msdb;
GO
IF DATABASE_PRINCIPAL_ID(N'$(WorkerUser)') IS NULL CREATE USER [$(WorkerUser)] FOR LOGIN [$(WorkerLogin)];
IF (SELECT sid FROM sys.database_principals WHERE name=N'$(WorkerUser)')<>SUSER_SID(N'$(WorkerLogin)') THROW 58003,'Usuario msdb asociado a otro login.',1;
GRANT SELECT ON dbo.backupset TO [$(WorkerUser)];
GRANT SELECT ON dbo.backupmediafamily TO [$(WorkerUser)];
COMMIT TRANSACTION;
GO
