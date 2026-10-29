/*
 SOLO laboratorio confirmado sin secretos reales, con aceptacion explicita de
 captura literal. No ejecutar en SecureFinanceERP principal. Requiere 90-93.
 Todos los GO en transaccion externa, misma conexion, aborto al primer error.
 Una fila por evento del motor; no deduplicar ALTER repetidos legitimos.
 Un fallo del trigger puede impedir el DDL. Un rollback revierte tambien su
 fila de auditoria. No garantiza persistencia de intentos fallidos/revertidos.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
IF DB_ID() IS NULL OR DB_ID() <= 4
 OR DB_NAME() COLLATE Latin1_General_100_CI_AS = N'SecureFinanceERP'
 THROW 54990, 'Destino prohibido: requiere laboratorio aislado.', 1;
IF ISNULL(TRY_CONVERT(nvarchar(128), SESSION_CONTEXT(N'P3_DDL.LaboratorioConfirmado')), N'')
 COLLATE Latin1_General_100_BIN2 <> DB_NAME() COLLATE Latin1_General_100_BIN2
 OR ISNULL(TRY_CONVERT(nvarchar(128), SESSION_CONTEXT(N'P3_DDL.TextoExactoAutorizado')), N'')
 COLLATE Latin1_General_100_BIN2 <> DB_NAME() COLLATE Latin1_General_100_BIN2
 THROW 54990, 'Falta confirmacion del laboratorio o aceptacion del riesgo de texto exacto.', 1;
IF @@TRANCOUNT = 0 OR XACT_STATE() <> 1
 THROW 54990, 'Se requiere transaccion externa y aborto al primer error.', 1;
IF ISNULL(HAS_PERMS_BY_NAME(DB_NAME(), N'DATABASE', N'VIEW DEFINITION'), 0) <> 1
 OR DATABASE_PRINCIPAL_ID(N'securefinance_app') IS NULL
 OR NOT EXISTS (SELECT 1 FROM sys.check_constraints
  WHERE parent_object_id = OBJECT_ID(N'dbo.Bitacora_DDL') AND name = N'P3_DDL_CK_ComandoEstado'
   AND is_disabled = 0 AND is_not_trusted = 0)
 THROW 54990, 'Requiere permisos 92 y politica 93 verificados.', 1;

IF DATABASE_PRINCIPAL_ID(N'P3_DDL_Escritor') IS NULL
 CREATE USER P3_DDL_Escritor WITHOUT LOGIN;
DECLARE @Writer int = DATABASE_PRINCIPAL_ID(N'P3_DDL_Escritor');
IF NOT EXISTS (SELECT 1 FROM sys.database_principals
 WHERE principal_id = @Writer AND type = N'S' AND authentication_type = 0 AND principal_id > 4)
 OR EXISTS (SELECT 1 FROM sys.database_role_members WHERE member_principal_id = @Writer)
 OR EXISTS (SELECT 1 FROM sys.schemas WHERE principal_id = @Writer)
 OR EXISTS (SELECT 1 FROM sys.objects WHERE principal_id = @Writer)
 OR EXISTS (SELECT 1 FROM sys.database_permissions WHERE grantee_principal_id = @Writer
  AND NOT ((class = 0 AND major_id = 0 AND permission_name = N'CONNECT' AND state = N'G')
   OR (class = 1 AND major_id = OBJECT_ID(N'dbo.Bitacora_DDL') AND minor_id = 0
   AND ((permission_name = N'INSERT' AND state = N'G')
    OR (permission_name IN (N'SELECT', N'UPDATE', N'DELETE') AND state = N'D')))))
 THROW 54990, 'El escritor debe ser interno, sin roles, propiedad ni permisos adicionales.', 1;
IF EXISTS (SELECT 1 FROM sys.triggers WHERE name = N'P3_DDL_CapturarEstructura'
 AND (parent_class <> 0 OR type <> N'TR'))
 OR EXISTS (SELECT 1 FROM sys.triggers t JOIN sys.sql_modules m ON m.object_id = t.object_id
  WHERE t.name = N'P3_DDL_CapturarEstructura' AND ISNULL(m.execute_as_principal_id, -1) <> @Writer)
 THROW 54990, 'Hay un trigger incompatible con el nombre reservado.', 1;
GRANT INSERT ON OBJECT::dbo.Bitacora_DDL TO P3_DDL_Escritor;
DENY SELECT, UPDATE, DELETE ON OBJECT::dbo.Bitacora_DDL TO P3_DDL_Escritor;
DENY IMPERSONATE ON USER::P3_DDL_Escritor TO securefinance_app;
GO
CREATE OR ALTER TRIGGER P3_DDL_CapturarEstructura
ON DATABASE
WITH EXECUTE AS N'P3_DDL_Escritor'
FOR CREATE_TABLE, ALTER_TABLE, DROP_TABLE,
 CREATE_PROCEDURE, ALTER_PROCEDURE, DROP_PROCEDURE
AS
BEGIN
 SET NOCOUNT ON;
 IF DB_ID() <= 4 OR DB_NAME() COLLATE Latin1_General_100_CI_AS = N'SecureFinanceERP'
  THROW 54993, 'Captura autorizada solamente en laboratorio.', 1;
 DECLARE @Data xml = EVENTDATA();
 DECLARE @Command nvarchar(max) = @Data.value('(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]', 'nvarchar(max)');
 IF @Command IS NULL OR DATALENGTH(@Command) = 0
  THROW 54993, 'No se puede confirmar el comando del evento DDL.', 1;
 -- Preserve the decoded CommandText exactly: no trim, truncation or redaction.
 INSERT dbo.Bitacora_DDL (FechaHora, TipoEvento, NombreObjeto, TipoObjeto, Esquema,
  UsuarioSQL, LoginOriginal, EquipoOrigen, AplicacionOrigen, BaseDatos, SesionId,
  ComandoTSql, EstadoComando)
 VALUES (SYSUTCDATETIME(), @Data.value('(/EVENT_INSTANCE/EventType)[1]', 'nvarchar(40)'),
  NULLIF(@Data.value('(/EVENT_INSTANCE/ObjectName)[1]', 'nvarchar(128)'), N''),
  NULLIF(@Data.value('(/EVENT_INSTANCE/ObjectType)[1]', 'nvarchar(60)'), N''),
  NULLIF(@Data.value('(/EVENT_INSTANCE/SchemaName)[1]', 'nvarchar(128)'), N''),
  COALESCE(NULLIF(@Data.value('(/EVENT_INSTANCE/UserName)[1]', 'nvarchar(128)'), N''),
   NULLIF(@Data.value('(/EVENT_INSTANCE/LoginName)[1]', 'nvarchar(128)'), N''), N'No disponible'),
  ORIGINAL_LOGIN(), HOST_NAME(), APP_NAME(), DB_NAME(), @@SPID, @Command, 'EXACTO_EVENTDATA');
END;
GO
IF NOT EXISTS (SELECT 1 FROM sys.triggers WHERE name = N'P3_DDL_CapturarEstructura'
 AND parent_class = 0 AND is_disabled = 0)
 OR (SELECT COUNT(*) FROM sys.trigger_events e JOIN sys.triggers t ON t.object_id = e.object_id
  WHERE t.name = N'P3_DDL_CapturarEstructura') <> 6
 THROW 54990, 'La captura no quedo habilitada con sus seis eventos.', 1;
GO
