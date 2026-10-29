-- Integration policy: only the explicitly bound synthetic laboratory; never silently skip capture.
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
IF DB_NAME() COLLATE Latin1_General_100_BIN2 <> dbo.P3_INT_Destino()
 OR @@TRANCOUNT=0
 OR ISNULL(HAS_PERMS_BY_NAME(DB_NAME(), N'DATABASE', N'VIEW DEFINITION'), 0) <> 1
 OR SESSION_CONTEXT(N'P3_BOD.BodegaId') IS NOT NULL
 OR DATABASE_PRINCIPAL_ID(N'P3_DDL_Escritor') IS NULL
 OR EXISTS (SELECT 1 FROM sys.triggers WHERE name=N'P3_DDL_CapturarEstructura' AND parent_class<>0)
 THROW 54990, 'Requiere laboratorio autorizado, transaccion externa y captura 94 previa.', 1;
GO
DECLARE @Escritor int = DATABASE_PRINCIPAL_ID(N'P3_DDL_Escritor');
IF EXISTS (SELECT 1 FROM sys.database_role_members WHERE member_principal_id=@Escritor)
 OR EXISTS (SELECT 1 FROM sys.schemas WHERE principal_id=@Escritor)
 OR EXISTS (SELECT 1 FROM sys.objects WHERE principal_id=@Escritor)
 OR EXISTS (SELECT 1 FROM sys.database_permissions WHERE grantee_principal_id=@Escritor
  AND NOT ((class=0 AND major_id=0 AND permission_name=N'CONNECT' AND state=N'G')
   OR (class=1 AND major_id=OBJECT_ID(N'dbo.P3_INT_Destino') AND permission_name=N'EXECUTE' AND state=N'G')
   OR (class=1 AND major_id=OBJECT_ID(N'dbo.Bitacora_DDL') AND minor_id=0
   AND ((permission_name=N'INSERT' AND state=N'G')
    OR (permission_name IN (N'SELECT',N'UPDATE',N'DELETE') AND state=N'D')))))
 THROW 54990, 'El escritor no cumple el contrato de minimos privilegios 94.', 1;
ELSE
BEGIN
 EXEC(N'CREATE OR ALTER TRIGGER P3_DDL_CapturarEstructura
 ON DATABASE
 WITH EXECUTE AS N''P3_DDL_Escritor''
 FOR CREATE_TABLE, ALTER_TABLE, DROP_TABLE,
  CREATE_PROCEDURE, ALTER_PROCEDURE, DROP_PROCEDURE
 AS
 BEGIN
  SET NOCOUNT ON;
  -- Fail closed if the database/server binding no longer matches.
  IF DB_NAME() COLLATE Latin1_General_100_BIN2 <> dbo.P3_INT_Destino()
   THROW 54993, ''Captura DDL fuera del laboratorio autorizado.'',1;
  DECLARE @Data xml = EVENTDATA();
  DECLARE @Command nvarchar(max) = @Data.value(''(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]'', ''nvarchar(max)'');
  IF @Command IS NULL OR DATALENGTH(@Command) = 0
   THROW 54993, ''No se puede confirmar el comando del evento DDL.'', 1;
  -- Preserve the decoded CommandText exactly: no trim, truncation or redaction.
  INSERT dbo.Bitacora_DDL (FechaHora, TipoEvento, NombreObjeto, TipoObjeto, Esquema,
   UsuarioSQL, LoginOriginal, EquipoOrigen, AplicacionOrigen, BaseDatos, SesionId,
   ComandoTSql, EstadoComando)
  VALUES (SYSUTCDATETIME(), @Data.value(''(/EVENT_INSTANCE/EventType)[1]'', ''nvarchar(40)''),
   NULLIF(@Data.value(''(/EVENT_INSTANCE/ObjectName)[1]'', ''nvarchar(128)''), N''''),
   NULLIF(@Data.value(''(/EVENT_INSTANCE/ObjectType)[1]'', ''nvarchar(60)''), N''''),
   NULLIF(@Data.value(''(/EVENT_INSTANCE/SchemaName)[1]'', ''nvarchar(128)''), N''''),
   COALESCE(NULLIF(@Data.value(''(/EVENT_INSTANCE/UserName)[1]'', ''nvarchar(128)''), N''''),
    NULLIF(@Data.value(''(/EVENT_INSTANCE/LoginName)[1]'', ''nvarchar(128)''), N''''), N''No disponible''),
   ORIGINAL_LOGIN(), HOST_NAME(), APP_NAME(), DB_NAME(), @@SPID, @Command, ''EXACTO_EVENTDATA'');
 END;');
END;
GO
IF NOT EXISTS (SELECT 1 FROM sys.triggers WHERE name = N'P3_DDL_CapturarEstructura'
 AND parent_class = 0 AND is_disabled = 0)
 OR (SELECT COUNT(*) FROM sys.trigger_events e JOIN sys.triggers t ON t.object_id = e.object_id
  WHERE t.name = N'P3_DDL_CapturarEstructura') <> 6
 OR NOT EXISTS (SELECT 1 FROM sys.sql_modules m JOIN sys.triggers t ON t.object_id = m.object_id
  WHERE t.name = N'P3_DDL_CapturarEstructura'
   AND CHARINDEX(N'THROW 54993', m.definition) > 0
   AND CHARINDEX(N'P3_INT_Destino', m.definition) > 0)
 THROW 54990, 'La captura no quedo aplicable con guarda de laboratorio.', 1;
GO
