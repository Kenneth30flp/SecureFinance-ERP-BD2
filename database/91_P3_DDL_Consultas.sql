/*
 PROHIBIDO ejecutar en SecureFinanceERP principal o en bases del sistema.
 Solo laboratorio: DBA confirma externamente el destino REAL y solo despues
 establece SESSION_CONTEXT(N'P3_DDL.LaboratorioConfirmado') = DB_NAME().
 Instalador: 90 -> 91 -> 92, abortar al PRIMER error, SET XACT_ABORT ON,
 envolver TODOS los GO de cada archivo en una transaccion EXTERNA en la MISMA
 conexion. COMMIT solo con exito completo; ROLLBACK ante cualquier error.
 Las guardas anteriores al primer GO no protegen a un cliente que ignore errores.
 Sin captura DDL ni aprobacion de politica TSQL. No se almacenan comandos.
 CorteId es una cota de identidad, NO un snapshot transaccional: confirmaciones
 concurrentes de identidades reservadas <= corte pueden cambiar filas y conteo.
 No se agregan transacciones ni hints de bloqueo a las consultas; el helper
 conserva su propia politica de permisos. El actor debe proceder del backend
 autenticado, nunca de una identidad elegida libremente por el navegador.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

IF DB_ID() IS NULL OR DB_ID() <= 4
 OR DB_NAME() COLLATE Latin1_General_100_CI_AS = N'SecureFinanceERP'
 OR DB_NAME() IN (N'master', N'tempdb', N'model', N'msdb', N'mssqlsystemresource')
 THROW 54990, 'Destino prohibido: solo laboratorio confirmado, nunca la base principal.', 1;
IF ISNULL(TRY_CONVERT(nvarchar(128), SESSION_CONTEXT(N'P3_DDL.LaboratorioConfirmado')), N'')
 COLLATE Latin1_General_100_BIN2 <> DB_NAME() COLLATE Latin1_General_100_BIN2
 THROW 54990, 'Falta confirmacion externa del laboratorio por el DBA en esta conexion.', 1;
IF @@TRANCOUNT = 0 OR XACT_STATE() <> 1
 THROW 54990, 'El instalador debe abrir una transaccion externa y abortar al primer error.', 1;
IF ISNULL(HAS_PERMS_BY_NAME(DB_NAME(), N'DATABASE', N'VIEW DEFINITION'), 0) <> 1
 THROW 54990, 'No hay visibilidad suficiente para verificar las dependencias.', 1;
IF OBJECT_ID(N'dbo.Bitacora_DDL', N'U') IS NULL
 OR OBJECT_ID(N'dbo.sp_ParteII_ValidarPermiso', N'P') IS NULL
 THROW 54990, 'Requiere estructura 90 validada y helper de permisos Parte II.', 1;
GO
CREATE OR ALTER PROCEDURE dbo.P3_DDL_ConsultarBitacora
 @ActorUsuarioId INT,
 @Desde DATETIME2(3) = NULL,
 @Hasta DATETIME2(3) = NULL,
 @Usuario NVARCHAR(128) = NULL,
 @Objeto NVARCHAR(128) = NULL,
 @Evento NVARCHAR(40) = NULL,
 @CorteId BIGINT = NULL,
 @Desplazamiento INT = 0,
 @Limite INT = 20
AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId, N'AUDITORIA_DDL_CONSULTAR';

 IF (@Desde IS NOT NULL AND @Hasta IS NOT NULL AND @Desde >= @Hasta)
  OR @Desplazamiento IS NULL OR @Desplazamiento < 0 OR @Desplazamiento > 19999980
  OR @Limite IS NULL OR @Limite < 1 OR @Limite > 100
  OR (@CorteId IS NOT NULL AND @CorteId < 0)
  OR (@Evento IS NOT NULL AND @Evento NOT IN (
   N'CREATE_TABLE', N'ALTER_TABLE', N'DROP_TABLE',
   N'CREATE_PROCEDURE', N'ALTER_PROCEDURE', N'DROP_PROCEDURE'))
  THROW 54990, 'Filtros, corte o paginacion invalidos; Hasta es exclusivo.', 1;

 IF @CorteId IS NULL
  SELECT @CorteId = ISNULL(MAX(BitacoraDdlId), 0) FROM dbo.Bitacora_DDL;

 -- Cero es un corte vacio, no un alias de la ultima identidad disponible.
 DECLARE @TotalFilas bigint;
 SELECT @TotalFilas = COUNT_BIG(*)
 FROM dbo.Bitacora_DDL b
 WHERE @CorteId > 0 AND b.BitacoraDdlId <= @CorteId
  AND (@Desde IS NULL OR b.FechaHora >= @Desde)
  AND (@Hasta IS NULL OR b.FechaHora < @Hasta)
  AND (@Usuario IS NULL OR CHARINDEX(@Usuario, b.UsuarioSQL) > 0
       OR CHARINDEX(@Usuario, b.LoginOriginal) > 0)
  AND (@Objeto IS NULL OR CHARINDEX(@Objeto, b.NombreObjeto) > 0)
  AND (@Evento IS NULL OR b.TipoEvento = @Evento);

 SELECT CAST(b.BitacoraDdlId AS varchar(20)) AS BitacoraDdlId,
  b.FechaHora, b.TipoEvento, b.NombreObjeto, b.TipoObjeto, b.Esquema,
  b.UsuarioSQL, b.LoginOriginal, b.EquipoOrigen, b.AplicacionOrigen,
  b.BaseDatos, b.SesionId, b.EstadoComando
 FROM dbo.Bitacora_DDL b
 WHERE @CorteId > 0 AND b.BitacoraDdlId <= @CorteId
  AND (@Desde IS NULL OR b.FechaHora >= @Desde)
  AND (@Hasta IS NULL OR b.FechaHora < @Hasta)
  AND (@Usuario IS NULL OR CHARINDEX(@Usuario, b.UsuarioSQL) > 0
       OR CHARINDEX(@Usuario, b.LoginOriginal) > 0)
  AND (@Objeto IS NULL OR CHARINDEX(@Objeto, b.NombreObjeto) > 0)
  AND (@Evento IS NULL OR b.TipoEvento = @Evento)
 ORDER BY b.FechaHora DESC, b.BitacoraDdlId DESC
 OFFSET @Desplazamiento ROWS FETCH NEXT @Limite ROWS ONLY;

 SELECT CAST(@TotalFilas AS varchar(20)) AS TotalFilas,
  CAST(@CorteId AS varchar(20)) AS CorteId;
END;
GO
CREATE OR ALTER PROCEDURE dbo.P3_DDL_ConsultarDetalle
 @ActorUsuarioId INT,
 @BitacoraDdlId BIGINT
AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId, N'AUDITORIA_DDL_CONSULTAR';
 IF @BitacoraDdlId IS NULL OR @BitacoraDdlId <= 0
  THROW 54990, 'BitacoraDdlId debe ser mayor que cero.', 1;

 SELECT CAST(b.BitacoraDdlId AS varchar(20)) AS BitacoraDdlId,
  b.FechaHora, b.TipoEvento, b.NombreObjeto, b.TipoObjeto, b.Esquema,
  b.UsuarioSQL, b.LoginOriginal, b.EquipoOrigen, b.AplicacionOrigen,
  b.BaseDatos, b.SesionId, b.ComandoTSql, b.EstadoComando
 FROM dbo.Bitacora_DDL b
 WHERE b.BitacoraDdlId = @BitacoraDdlId;
END;
GO
