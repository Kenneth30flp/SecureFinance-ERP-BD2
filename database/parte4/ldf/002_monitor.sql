CREATE OR ALTER PROCEDURE dbo.P4_LDF_Consultar @ActorUsuarioId int
AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.P4_LDF_Validar @ActorUsuarioId, N'DBA_LDF_CONSULTAR';
 DECLARE @Guid uniqueidentifier, @Fork uniqueidentifier, @NextLSN numeric(25,0);
 SELECT @Guid = database_guid, @Fork = recovery_fork_guid, @NextLSN = last_log_backup_lsn
 FROM sys.database_recovery_status WHERE database_id = DB_ID();

 -- DMV combines ALL log files. Never assign its percentage to individual files.
 SELECT DB_NAME() DatabaseName, CONVERT(nvarchar(128), SERVERPROPERTY('ProductVersion')) ServerVersion,
 SYSUTCDATETIME() SampledAtUTC, d.recovery_model_desc RecoveryModel,
 d.state_desc DatabaseState, d.log_reuse_wait_desc ReuseWait, d.is_read_only IsReadOnly,
 CAST(CASE WHEN d.recovery_model_desc IN ('FULL','BULK_LOGGED') AND @NextLSN IS NOT NULL
  AND d.state_desc = 'ONLINE' AND d.is_read_only = 0 THEN 1 ELSE 0 END AS bit) ChainReady,
 CAST(s.total_log_size_in_bytes / 1048576.0 AS decimal(19,3)) LogicalMB,
 CAST(s.used_log_space_in_bytes / 1048576.0 AS decimal(19,3)) UsedMB,
 CAST((s.total_log_size_in_bytes - s.used_log_space_in_bytes) / 1048576.0 AS decimal(19,3)) FreeMB,
 CONVERT(decimal(7,3), s.used_log_space_in_percent) UsedPercent,
 CAST((SELECT SUM(CONVERT(bigint, size)) FROM sys.database_files WHERE type = 1) / 128.0 AS decimal(19,3)) PhysicalMB,
 c.Advertencia WarningPercent, c.Critico CriticalPercent, c.RutaBackup BackupDirectory
 FROM sys.dm_db_log_space_usage s JOIN sys.databases d ON d.database_id = s.database_id
 CROSS JOIN dbo.P4_LDF_Configuracion c WHERE d.database_id = DB_ID() AND c.Id = 1;

 SELECT file_id FileId, name LogicalName, physical_name PhysicalPath, state_desc FileState,
 CAST(CONVERT(bigint, size) / 128.0 AS decimal(19,3)) SizeMB,
 growth Growth, is_percent_growth PercentGrowth, max_size MaxSizePages
 FROM sys.database_files WHERE type = 1 ORDER BY file_id;

 DECLARE @Vlf TABLE (FileId int, OffsetBytes bigint, SizeMB float, Active bit, Status int, SequenceNumber bigint);
 INSERT @Vlf SELECT file_id, vlf_begin_offset, vlf_size_mb, vlf_active, vlf_status, vlf_sequence_number
 FROM sys.dm_db_log_info(DB_ID());
 SELECT COUNT(*) Total, COALESCE(SUM(CONVERT(int, Active)),0) Active,
 COUNT(*) - COALESCE(SUM(CONVERT(int, Active)),0) Inactive,
 MIN(SizeMB) MinMB, MAX(SizeMB) MaxMB, AVG(SizeMB) AverageMB,
 COALESCE(SUM(CASE WHEN Active = 0 THEN SizeMB ELSE 0 END),0) InactiveMB FROM @Vlf;
 SELECT TOP (200) FileId, CONVERT(varchar(20),OffsetBytes) OffsetBytes, SizeMB, Active, Status,
 CONVERT(varchar(20), SequenceNumber) SequenceNumber FROM @Vlf ORDER BY FileId, OffsetBytes;
 SELECT CASE WHEN SizeMB < 1 THEN '< 1 MB' WHEN SizeMB < 64 THEN '1-64 MB'
 WHEN SizeMB < 512 THEN '64-512 MB' ELSE '>= 512 MB' END SizeBand,
 COUNT(*) Total, SUM(CONVERT(int,Active)) Active, SUM(SizeMB) TotalMB
 FROM @Vlf GROUP BY CASE WHEN SizeMB < 1 THEN '< 1 MB' WHEN SizeMB < 64 THEN '1-64 MB'
 WHEN SizeMB < 512 THEN '64-512 MB' ELSE '>= 512 MB' END;

 -- msdb times are SQL Server local time, returned as text to avoid fictitious UTC conversion.
 SELECT TOP (20) b.backup_set_id BackupSetId,
 CONVERT(varchar(33),b.backup_start_date,126) StartServerTime,
 CONVERT(varchar(33),b.backup_finish_date,126) FinishServerTime,
 CONVERT(varchar(30),b.first_lsn) FirstLSN, CONVERT(varchar(30),b.last_lsn) LastLSN,
 CONVERT(varchar(30),b.database_backup_lsn) DatabaseBackupLSN,
 CAST(b.backup_size / 1048576.0 AS decimal(19,3)) SizeMB,
 b.has_backup_checksums HasChecksums, b.is_copy_only CopyOnly, b.is_damaged Damaged,
 b.user_name BackupUser, b.name BackupName,
 (SELECT STRING_AGG(CONVERT(nvarchar(max),m.physical_device_name),N' | ')
 FROM msdb.dbo.backupmediafamily m WHERE m.media_set_id=b.media_set_id) PhysicalPath
 FROM msdb.dbo.backupset b WHERE b.database_guid = @Guid AND b.last_recovery_fork_guid = @Fork
 AND b.type = 'L' AND b.backup_finish_date IS NOT NULL
 ORDER BY b.backup_finish_date DESC, b.backup_set_id DESC;

 SELECT TOP (30) OperacionId, ActorUsuarioId, InicioUTC, FinUTC, Estado, Archivo,
 BackupSetId, CodigoSQL, Mensaje FROM dbo.P4_LDF_Ejecucion ORDER BY InicioUTC DESC;
END;
GO
