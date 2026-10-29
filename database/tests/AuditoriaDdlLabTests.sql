/* SOLO ejecutar con InstallAuditoriaDdlLab.ps1 -Probar en laboratorio exclusivo.
 No ejecutado en esta entrega. Todos los objetos son nuevos y propios del test.
 El runner hace ROLLBACK al terminar, incluidos los eventos de estas pruebas.
 No usa passwords ni secretos reales. Nunca ejecutar sobre tablas de negocio.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_ID() <= 4 OR DB_NAME() COLLATE Latin1_General_100_CI_AS = N'SecureFinanceERP'
 OR @@TRANCOUNT <> 1 OR XACT_STATE() <> 1
 THROW 54995, 'Requiere laboratorio y transaccion exclusiva del runner.', 1;
IF ISNULL(TRY_CONVERT(nvarchar(128), SESSION_CONTEXT(N'P3_DDL.LaboratorioConfirmado')), N'')
 COLLATE Latin1_General_100_BIN2 <> DB_NAME() COLLATE Latin1_General_100_BIN2
 OR ISNULL(TRY_CONVERT(nvarchar(128), SESSION_CONTEXT(N'P3_DDL.TextoExactoAutorizado')), N'')
 COLLATE Latin1_General_100_BIN2 <> DB_NAME() COLLATE Latin1_General_100_BIN2
 THROW 54995, 'Falta confirmacion externa del laboratorio y del riesgo.', 1;
IF OBJECT_ID(N'dbo.P3_DDL_QA_Tabla') IS NOT NULL OR OBJECT_ID(N'dbo.P3_DDL_QA_Proc') IS NOT NULL
 THROW 54995, 'Colision con objeto existente: no se elimina ni modifica.', 1;
IF NOT EXISTS (SELECT 1 FROM sys.triggers WHERE name = N'P3_DDL_CapturarEstructura' AND is_disabled = 0 AND parent_class = 0)
 THROW 54995, 'La captura no esta instalada.', 1;

DECLARE @Inicio bigint = ISNULL((SELECT MAX(BitacoraDdlId) FROM dbo.Bitacora_DDL), 0);
DECLARE @InicioUtc datetime2(3) = SYSUTCDATETIME(), @UsuarioEsperado sysname = USER_NAME();
DECLARE @Expected TABLE (Evento nvarchar(40), Objeto nvarchar(128), Comando nvarchar(max));
DECLARE @Sql nvarchar(max);
-- SQL Server can omit a terminal semicolon from EVENTDATA. Use equivalent
-- fixtures without that optional delimiter; capture itself is never rewritten.
SET @Sql = N'CREATE TABLE dbo.P3_DDL_QA_Tabla (Id int NOT NULL)';
INSERT @Expected VALUES (N'CREATE_TABLE', N'P3_DDL_QA_Tabla', @Sql);
EXEC sys.sp_executesql @Sql;
SET @Sql = N'ALTER TABLE dbo.P3_DDL_QA_Tabla ADD Descripcion nvarchar(20) NULL';
INSERT @Expected VALUES (N'ALTER_TABLE', N'P3_DDL_QA_Tabla', @Sql);
EXEC sys.sp_executesql @Sql;
SET @Sql = N'DROP TABLE dbo.P3_DDL_QA_Tabla';
INSERT @Expected VALUES (N'DROP_TABLE', N'P3_DDL_QA_Tabla', @Sql);
EXEC sys.sp_executesql @Sql;
SET @Sql = N'CREATE PROCEDURE dbo.P3_DDL_QA_Proc AS ' + NCHAR(10)
 + REPLICATE(CONVERT(nvarchar(max), N'-- synthetic ' + NCHAR(241) + NCHAR(10)), 500)
 + N'SELECT 1 AS Valor';
INSERT @Expected VALUES (N'CREATE_PROCEDURE', N'P3_DDL_QA_Proc', @Sql);
EXEC sys.sp_executesql @Sql;
SET @Sql = N'ALTER PROCEDURE dbo.P3_DDL_QA_Proc AS SELECT 2 AS Valor';
INSERT @Expected VALUES (N'ALTER_PROCEDURE', N'P3_DDL_QA_Proc', @Sql);
EXEC sys.sp_executesql @Sql;
SET @Sql = N'DROP PROCEDURE dbo.P3_DDL_QA_Proc';
INSERT @Expected VALUES (N'DROP_PROCEDURE', N'P3_DDL_QA_Proc', @Sql);
EXEC sys.sp_executesql @Sql;

IF (SELECT COUNT(*) FROM dbo.Bitacora_DDL WHERE BitacoraDdlId > @Inicio
 AND NombreObjeto IN (N'P3_DDL_QA_Tabla', N'P3_DDL_QA_Proc')) <> 6
 THROW 54995, 'Se esperaban exactamente seis eventos de fixtures.', 1;
IF EXISTS (SELECT 1 FROM @Expected e WHERE (
 SELECT COUNT(*) FROM dbo.Bitacora_DDL b WHERE b.BitacoraDdlId > @Inicio
 AND b.TipoEvento = e.Evento AND b.NombreObjeto = e.Objeto AND b.Esquema = N'dbo'
 AND b.BaseDatos = DB_NAME() AND b.EstadoComando = 'EXACTO_EVENTDATA'
 AND CONVERT(varbinary(max), b.ComandoTSql) = CONVERT(varbinary(max), e.Comando)
 AND DATALENGTH(b.ComandoTSql) = DATALENGTH(e.Comando)
 AND b.LoginOriginal = ORIGINAL_LOGIN() AND b.UsuarioSQL = @UsuarioEsperado AND b.SesionId = @@SPID
 AND b.FechaHora >= @InicioUtc AND b.FechaHora <= SYSUTCDATETIME()) <> 1)
 THROW 54995, 'Evento ausente, duplicado o texto distinto/truncado.', 1;
-- Full equality checks include Unicode and a procedure longer than 4000 chars.
IF OBJECT_ID(N'dbo.P3_DDL_QA_Tabla') IS NOT NULL OR OBJECT_ID(N'dbo.P3_DDL_QA_Proc') IS NOT NULL
 THROW 54995, 'No se completo el ciclo de los objetos propios de prueba.', 1;
