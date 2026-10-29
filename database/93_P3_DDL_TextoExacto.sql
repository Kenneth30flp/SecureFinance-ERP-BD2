/*
 SOLO laboratorio sin secretos reales. Nunca SecureFinanceERP principal.
 Requiere 90-92. No modifica filas historicas. El requisito academico exige
 el texto exacto de EVENTDATA, que PUEDE contener secretos en cuerpos/literales.
 El DBA confirma laboratorio y acepta ese riesgo antes de establecer ambos
 SESSION_CONTEXT al nombre exacto de la BD. Este script no los establece.
 Ejecutar todos los GO en la misma transaccion externa, XACT_ABORT ON,
 abortando al primer error. Usar InstallAuditoriaDdlLab.ps1, no un cliente
 que continue despues de errores. No reaplicar 90 despues de esta evolucion.
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
 OR OBJECT_ID(N'dbo.P3_DDL_ConsultarDetalle', N'P') IS NULL
 OR OBJECT_ID(N'dbo.P3_DDL_ConsultarBitacora', N'P') IS NULL
 OR NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.Bitacora_DDL')
  AND name = N'ComandoTSql' AND system_type_id = TYPE_ID(N'nvarchar') AND max_length = -1 AND is_nullable = 1)
 THROW 54990, 'Requiere estructura y consultas 90-92 compatibles y visibles.', 1;

DECLARE @Legacy bit = CASE WHEN OBJECT_ID(N'dbo.P3_DDL_CK_ComandoNulo', N'C') IS NOT NULL THEN 1 ELSE 0 END;
DECLARE @Esperados TABLE (Nombre sysname, Expresion nvarchar(max));
INSERT @Esperados VALUES
 (N'P3_DDL_CK_EstadoComando', CASE WHEN @Legacy = 1
  THEN N'EstadoComando=''PENDIENTE_RUBRICA'''
  ELSE N'EstadoComando=''PENDIENTE_RUBRICA''OREstadoComando=''EXACTO_EVENTDATA''' END);
IF @Legacy = 1
 INSERT @Esperados VALUES (N'P3_DDL_CK_ComandoNulo', N'ComandoTSqlISNULL');
ELSE
 INSERT @Esperados VALUES (N'P3_DDL_CK_ComandoEstado',
  N'EstadoComando=''PENDIENTE_RUBRICA''ANDComandoTSqlISNULL OREstadoComando=''EXACTO_EVENTDATA''ANDComandoTSqlISNOTNULLANDdatalengthComandoTSql>0');
IF EXISTS (
 SELECT 1 FROM @Esperados e LEFT JOIN sys.check_constraints c
 ON c.parent_object_id = OBJECT_ID(N'dbo.Bitacora_DDL') AND c.name = e.Nombre
 CROSS APPLY (SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
  c.definition, N'[', N''), N']', N''), N'(', N''), N')', N''), N' ', N''),
  NCHAR(9), N''), NCHAR(10), N''), NCHAR(13), N'') AS Definicion) n
 WHERE c.object_id IS NULL OR c.is_disabled = 1 OR c.is_not_trusted = 1
  OR c.is_not_for_replication = 1 OR n.Definicion IS NULL
  OR n.Definicion COLLATE Latin1_General_100_BIN2
   <> REPLACE(e.Expresion, N' ', N'') COLLATE Latin1_General_100_BIN2
)
 THROW 54990, 'Restricciones incompatibles: revisar sin sobrescribir historia.', 1;

IF @Legacy = 1
BEGIN
 IF OBJECT_ID(N'dbo.P3_DDL_CK_ComandoEstado', N'C') IS NOT NULL
  THROW 54990, 'Estado de migracion ambiguo.', 1;
 ALTER TABLE dbo.Bitacora_DDL DROP CONSTRAINT P3_DDL_CK_ComandoNulo;
 ALTER TABLE dbo.Bitacora_DDL DROP CONSTRAINT P3_DDL_CK_EstadoComando;
 ALTER TABLE dbo.Bitacora_DDL WITH CHECK ADD CONSTRAINT P3_DDL_CK_EstadoComando
  CHECK (EstadoComando = 'PENDIENTE_RUBRICA' OR EstadoComando = 'EXACTO_EVENTDATA');
 ALTER TABLE dbo.Bitacora_DDL WITH CHECK ADD CONSTRAINT P3_DDL_CK_ComandoEstado
  CHECK ((EstadoComando = 'PENDIENTE_RUBRICA' AND ComandoTSql IS NULL)
   OR (EstadoComando = 'EXACTO_EVENTDATA' AND ComandoTSql IS NOT NULL AND DATALENGTH(ComandoTSql) > 0));
END;
GO
