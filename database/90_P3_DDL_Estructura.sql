/*
 PROHIBIDO ejecutar en SecureFinanceERP principal o en bases del sistema.
 Solo laboratorio: el DBA debe confirmar externamente el destino REAL y despues
 establecer SESSION_CONTEXT(N'P3_DDL.LaboratorioConfirmado') = DB_NAME().
 Este archivo NO establece esa confirmacion ni identifica por si solo un clon.
 Instalacion 90 -> 91 -> 92: abortar al PRIMER error y ejecutar TODOS los lotes
 GO de cada archivo dentro de una transaccion EXTERNA, en la MISMA conexion,
 con SET XACT_ABORT ON. El instalador hace COMMIT solo si todo tuvo exito;
 ante cualquier error hace ROLLBACK. GO no aporta atomicidad.
 No ejecutar este archivo aisladamente sin ese protocolo. No contiene captura
 DDL, activacion de triggers, comandos auditados, XML ni datos de ejemplo.
 La politica de captura y de texto TSQL sigue PENDIENTE de aprobacion.
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
 THROW 54990, 'Sin visibilidad completa de metadatos no se puede validar la estructura.', 1;

IF OBJECT_ID(N'dbo.Bitacora_DDL') IS NOT NULL
 AND OBJECT_ID(N'dbo.Bitacora_DDL', N'U') IS NULL
 THROW 54990, 'dbo.Bitacora_DDL existe y no es una tabla compatible.', 1;

IF OBJECT_ID(N'dbo.Bitacora_DDL', N'U') IS NULL
BEGIN
 CREATE TABLE dbo.Bitacora_DDL (
  BitacoraDdlId bigint IDENTITY(1,1) NOT NULL
   CONSTRAINT P3_DDL_PK_Bitacora_DDL PRIMARY KEY,
  FechaHora datetime2(3) NOT NULL
   CONSTRAINT P3_DDL_DF_FechaHora DEFAULT SYSUTCDATETIME(),
  TipoEvento nvarchar(40) NOT NULL,
  NombreObjeto nvarchar(128) NULL,
  TipoObjeto nvarchar(60) NULL,
  Esquema nvarchar(128) NULL,
  UsuarioSQL nvarchar(128) NOT NULL,
  LoginOriginal nvarchar(128) NULL,
  EquipoOrigen nvarchar(128) NULL,
  AplicacionOrigen nvarchar(128) NULL,
  BaseDatos nvarchar(128) NOT NULL,
  SesionId int NULL,
  ComandoTSql nvarchar(max) NULL,
  EstadoComando varchar(30) NOT NULL
   CONSTRAINT P3_DDL_DF_EstadoComando DEFAULT 'PENDIENTE_RUBRICA',
  CONSTRAINT P3_DDL_CK_TipoEvento CHECK (
   TipoEvento = N'CREATE_TABLE' OR TipoEvento = N'ALTER_TABLE'
   OR TipoEvento = N'DROP_TABLE' OR TipoEvento = N'CREATE_PROCEDURE'
   OR TipoEvento = N'ALTER_PROCEDURE' OR TipoEvento = N'DROP_PROCEDURE'),
  CONSTRAINT P3_DDL_CK_ComandoNulo CHECK (ComandoTSql IS NULL),
  CONSTRAINT P3_DDL_CK_EstadoComando CHECK (EstadoComando = 'PENDIENTE_RUBRICA')
 );
 CREATE INDEX P3_DDL_IX_FechaHora_Id
  ON dbo.Bitacora_DDL (FechaHora DESC, BitacoraDdlId DESC);
END;

-- Comparacion conservadora: no se reparan tablas existentes ni su historia.
-- Las definiciones equivalentes no reconocidas requieren revision manual DBA.
DECLARE @TablaId int = OBJECT_ID(N'dbo.Bitacora_DDL', N'U');
DECLARE @Columnas TABLE (
 Nombre sysname NOT NULL, Tipo sysname NOT NULL, Longitud smallint NULL,
 Escala tinyint NOT NULL, Nulable bit NOT NULL, Identidad bit NOT NULL
);
INSERT @Columnas (Nombre, Tipo, Longitud, Escala, Nulable, Identidad) VALUES
 (N'BitacoraDdlId', N'bigint', 8, 0, 0, 1),
 (N'FechaHora', N'datetime2', NULL, 3, 0, 0),
 (N'TipoEvento', N'nvarchar', 80, 0, 0, 0),
 (N'NombreObjeto', N'nvarchar', 256, 0, 1, 0),
 (N'TipoObjeto', N'nvarchar', 120, 0, 1, 0),
 (N'Esquema', N'nvarchar', 256, 0, 1, 0),
 (N'UsuarioSQL', N'nvarchar', 256, 0, 0, 0),
 (N'LoginOriginal', N'nvarchar', 256, 0, 1, 0),
 (N'EquipoOrigen', N'nvarchar', 256, 0, 1, 0),
 (N'AplicacionOrigen', N'nvarchar', 256, 0, 1, 0),
 (N'BaseDatos', N'nvarchar', 256, 0, 0, 0),
 (N'SesionId', N'int', 4, 0, 1, 0),
 (N'ComandoTSql', N'nvarchar', -1, 0, 1, 0),
 (N'EstadoComando', N'varchar', 30, 0, 0, 0);

IF (SELECT COUNT(*) FROM sys.columns WHERE object_id = @TablaId) <> 14
 OR EXISTS (
  SELECT 1 FROM @Columnas e
  LEFT JOIN sys.columns c ON c.object_id = @TablaId AND c.name = e.Nombre
  WHERE c.column_id IS NULL OR c.system_type_id <> TYPE_ID(e.Tipo)
   OR c.user_type_id <> c.system_type_id
   OR (e.Longitud IS NOT NULL AND c.max_length <> e.Longitud)
   OR c.scale <> e.Escala OR c.is_nullable <> e.Nulable
   OR c.is_identity <> e.Identidad OR c.is_computed <> 0
   OR c.is_sparse <> 0 OR c.is_column_set <> 0
   OR c.generated_always_type <> 0 OR c.is_hidden <> 0
 )
 OR NOT EXISTS (
  SELECT 1 FROM sys.identity_columns WHERE object_id = @TablaId
   AND name = N'BitacoraDdlId' AND CONVERT(bigint, seed_value) = 1
   AND CONVERT(bigint, increment_value) = 1 AND is_not_for_replication = 0
 )
 OR NOT EXISTS (
  SELECT 1 FROM sys.tables t JOIN sys.objects o ON o.object_id = t.object_id
  WHERE t.object_id = @TablaId AND t.temporal_type = 0
   AND t.is_memory_optimized = 0 AND t.is_filetable = 0
   AND (o.principal_id IS NULL OR o.principal_id = DATABASE_PRINCIPAL_ID(N'dbo'))
 )
 THROW 54990, 'Bitacora_DDL incompatible: columnas, identidad o propietario. No modificar historia.', 1;

IF NOT EXISTS (
 SELECT 1 FROM sys.key_constraints k
 JOIN sys.indexes i ON i.object_id = k.parent_object_id AND i.index_id = k.unique_index_id
 WHERE k.parent_object_id = @TablaId AND k.type = N'PK'
  AND k.name = N'P3_DDL_PK_Bitacora_DDL' AND i.is_disabled = 0
  AND i.is_unique = 1 AND i.has_filter = 0
  AND (SELECT COUNT(*) FROM sys.index_columns c WHERE c.object_id = i.object_id
       AND c.index_id = i.index_id AND c.key_ordinal > 0) = 1
  AND EXISTS (SELECT 1 FROM sys.index_columns c JOIN sys.columns col
       ON col.object_id = c.object_id AND col.column_id = c.column_id
       WHERE c.object_id = i.object_id AND c.index_id = i.index_id
        AND c.key_ordinal = 1 AND col.name = N'BitacoraDdlId')
)
 THROW 54990, 'La clave primaria P3_DDL no coincide o esta deshabilitada.', 1;

DECLARE @Checks TABLE (Nombre sysname NOT NULL, Expresion nvarchar(max) NOT NULL);
INSERT @Checks (Nombre, Expresion) VALUES
 (N'P3_DDL_CK_ComandoNulo', N'ComandoTSqlISNULL'),
 (N'P3_DDL_CK_EstadoComando', N'EstadoComando=''PENDIENTE_RUBRICA'''),
 (N'P3_DDL_CK_TipoEvento', N'TipoEvento=N''CREATE_TABLE''ORTipoEvento=N''ALTER_TABLE''ORTipoEvento=N''DROP_TABLE''ORTipoEvento=N''CREATE_PROCEDURE''ORTipoEvento=N''ALTER_PROCEDURE''ORTipoEvento=N''DROP_PROCEDURE''');
IF (SELECT COUNT(*) FROM sys.check_constraints WHERE parent_object_id = @TablaId) <> 3
 OR EXISTS (
  SELECT 1 FROM @Checks e
  LEFT JOIN sys.check_constraints c ON c.parent_object_id = @TablaId AND c.name = e.Nombre
  CROSS APPLY (SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
   c.definition, N'[', N''), N']', N''), N'(', N''), N')', N''), N' ', N''),
   NCHAR(9), N''), NCHAR(10), N''), NCHAR(13), N'') AS Definicion) n
  WHERE c.object_id IS NULL OR c.is_disabled <> 0 OR c.is_not_trusted <> 0
   OR c.is_not_for_replication <> 0 OR n.Definicion IS NULL
   OR n.Definicion COLLATE Latin1_General_100_BIN2 <> e.Expresion COLLATE Latin1_General_100_BIN2
 )
 THROW 54990, 'CHECK incompatibles: se exige bloqueo confiable de comandos y eventos limitados.', 1;

IF (SELECT COUNT(*) FROM sys.default_constraints WHERE parent_object_id = @TablaId) <> 2
 OR NOT EXISTS (
  SELECT 1 FROM sys.default_constraints d JOIN sys.columns c
   ON c.object_id = d.parent_object_id AND c.column_id = d.parent_column_id
  WHERE d.parent_object_id = @TablaId AND c.name = N'FechaHora'
   AND d.name = N'P3_DDL_DF_FechaHora'
   AND LOWER(REPLACE(REPLACE(REPLACE(d.definition, N'(', N''), N')', N''), N' ', N'')) = N'sysutcdatetime'
 )
 OR NOT EXISTS (
  SELECT 1 FROM sys.default_constraints d JOIN sys.columns c
   ON c.object_id = d.parent_object_id AND c.column_id = d.parent_column_id
  WHERE d.parent_object_id = @TablaId AND c.name = N'EstadoComando'
   AND d.name = N'P3_DDL_DF_EstadoComando'
   AND REPLACE(REPLACE(REPLACE(d.definition, N'(', N''), N')', N''), N' ', N'')
       COLLATE Latin1_General_100_BIN2 = N'''PENDIENTE_RUBRICA'''
 )
 THROW 54990, 'Defaults incompatibles: se requieren UTC y PENDIENTE_RUBRICA.', 1;

IF NOT EXISTS (
 SELECT 1 FROM sys.indexes i WHERE i.object_id = @TablaId
  AND i.name = N'P3_DDL_IX_FechaHora_Id' AND i.type = 2
  AND i.is_disabled = 0 AND i.is_hypothetical = 0 AND i.has_filter = 0
  AND (SELECT COUNT(*) FROM sys.index_columns c WHERE c.object_id = i.object_id
       AND c.index_id = i.index_id AND c.key_ordinal > 0) = 2
  AND EXISTS (SELECT 1 FROM sys.index_columns c JOIN sys.columns col
       ON col.object_id = c.object_id AND col.column_id = c.column_id
       WHERE c.object_id = i.object_id AND c.index_id = i.index_id
        AND c.key_ordinal = 1 AND c.is_descending_key = 1 AND col.name = N'FechaHora')
  AND EXISTS (SELECT 1 FROM sys.index_columns c JOIN sys.columns col
       ON col.object_id = c.object_id AND col.column_id = c.column_id
       WHERE c.object_id = i.object_id AND c.index_id = i.index_id
        AND c.key_ordinal = 2 AND c.is_descending_key = 1 AND col.name = N'BitacoraDdlId')
)
 THROW 54990, 'Indice de consulta incompatible; no se reconstruye una tabla existente.', 1;
GO
