-- Etapa 1. Ejecutar 50 y 51 por batches GO dentro de una transaccion del instalador.
-- Sin USE, semillas operativas ni cambios a objetos compartidos.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
SET XACT_ABORT ON;
IF @@TRANCOUNT=0 THROW 55000,'El instalador debe abrir una transaccion.',1;
IF TRY_CONVERT(INT,SERVERPROPERTY('ProductMajorVersion'))<14 OR DB_NAME() IN('master','model','msdb','tempdb') OR
 (SELECT compatibility_level FROM sys.databases WHERE database_id=DB_ID())<130
 THROW 55000,'Base de aplicacion y compatibilidad OPENJSON requeridas.',1;
IF OBJECT_ID('dbo.ProductoProveedor','U') IS NULL
 OR OBJECT_ID('dbo.sp_ParteII_ValidarPermiso','P') IS NULL
 OR COL_LENGTH('dbo.Bitacora_Transacciones','Motivo') IS NULL
 OR DATABASE_PRINCIPAL_ID('securefinance_app') IS NULL
 THROW 55000,'Requiere catalogos, auditoria y permisos de Parte II.',1;
IF IS_ROLEMEMBER('db_owner','securefinance_app')=1
 OR IS_ROLEMEMBER('db_datawriter','securefinance_app')=1
 OR IS_ROLEMEMBER('db_datareader','securefinance_app')=1
 OR IS_ROLEMEMBER('db_ddladmin','securefinance_app')=1
 OR IS_ROLEMEMBER('db_securityadmin','securefinance_app')=1
 THROW 55000,'La cuenta de aplicacion requiere privilegios minimos.',1;
DECLARE @LoginAplicacion SYSNAME=(SELECT SUSER_SNAME(sid) FROM sys.database_principals WHERE name=N'securefinance_app');
IF @LoginAplicacion IS NOT NULL AND IS_SRVROLEMEMBER(N'sysadmin',@LoginAplicacion)=1
 THROW 55000,'El login de aplicacion no puede ser sysadmin.',1;
IF OBJECT_ID('dbo.P3_COM_OrdenCompra','U') IS NULL
BEGIN
 CREATE TABLE dbo.P3_COM_OrdenCompra(
  OrdenCompraId INT IDENTITY PRIMARY KEY,
  Numero AS ('OC-'+CONVERT(VARCHAR(10),OrdenCompraId)) PERSISTED,
  ProveedorId INT NOT NULL REFERENCES dbo.Proveedor(ProveedorId),
  ProveedorNombre NVARCHAR(150) NOT NULL,
  ProveedorNIT NVARCHAR(25) NOT NULL,
  CreadorUsuarioId INT NOT NULL REFERENCES dbo.Usuario(UsuarioId),
  FechaCreacion DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
  Observaciones NVARCHAR(1000) NULL,
  Total DECIMAL(32,4) NOT NULL CONSTRAINT CK_P3_COM_Total CHECK(Total>=0),
  Estado VARCHAR(25) NOT NULL DEFAULT 'BORRADOR',
  Version ROWVERSION,
  CONSTRAINT CK_P3_COM_Estado CHECK(Estado IN('BORRADOR','PENDIENTE_APROBACION','APROBADA','PARCIALMENTE_RECIBIDA','RECIBIDA','CANCELADA'))
 );
 CREATE UNIQUE INDEX UX_P3_COM_Numero ON dbo.P3_COM_OrdenCompra(Numero);
 CREATE INDEX IX_P3_COM_Consulta ON dbo.P3_COM_OrdenCompra(Estado,OrdenCompraId DESC);
 CREATE TABLE dbo.P3_COM_DetalleOrdenCompra(
  OrdenCompraId INT NOT NULL REFERENCES dbo.P3_COM_OrdenCompra(OrdenCompraId),
  ProductoId INT NOT NULL REFERENCES dbo.Producto(ProductoId),
  SKU NVARCHAR(40) NOT NULL,
  Descripcion NVARCHAR(200) NOT NULL,
  Cantidad INT NOT NULL CONSTRAINT CK_P3_COM_Cantidad CHECK(Cantidad>0),
  CostoUnitario DECIMAL(19,4) NOT NULL CONSTRAINT CK_P3_COM_Costo CHECK(CostoUnitario>=0),
  Subtotal AS CONVERT(DECIMAL(32,4),CONVERT(DECIMAL(10,0),Cantidad)*CostoUnitario) PERSISTED,
  PRIMARY KEY(OrdenCompraId,ProductoId)
 );
 CREATE TABLE dbo.P3_COM_HistorialEstado(
  HistorialId BIGINT IDENTITY PRIMARY KEY,
  OrdenCompraId INT NOT NULL REFERENCES dbo.P3_COM_OrdenCompra(OrdenCompraId),
  OperacionId UNIQUEIDENTIFIER NOT NULL UNIQUE,
  SolicitudHash BINARY(32) NOT NULL,
  Accion VARCHAR(10) NOT NULL,
  EstadoAnterior VARCHAR(25) NULL,
  EstadoNuevo VARCHAR(25) NOT NULL,
  ActorUsuarioId INT NOT NULL REFERENCES dbo.Usuario(UsuarioId),
  FechaHora DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
  Motivo NVARCHAR(250) NOT NULL CONSTRAINT CK_P3_COM_Motivo CHECK(LEN(LTRIM(RTRIM(Motivo)))>0),
  VersionResultado BINARY(8) NOT NULL,
  CONSTRAINT CK_P3_COM_Transicion CHECK(
   (Accion='CREAR' AND EstadoAnterior IS NULL AND EstadoNuevo='BORRADOR') OR
   (EstadoAnterior IS NOT NULL AND (
    (Accion='ENVIAR' AND EstadoAnterior='BORRADOR' AND EstadoNuevo='PENDIENTE_APROBACION') OR
    (Accion='APROBAR' AND EstadoAnterior='PENDIENTE_APROBACION' AND EstadoNuevo='APROBADA') OR
    (Accion='CANCELAR' AND EstadoAnterior IN('BORRADOR','PENDIENTE_APROBACION','APROBADA') AND EstadoNuevo='CANCELADA'))))
 );
 CREATE UNIQUE INDEX UX_P3_COM_Creacion ON dbo.P3_COM_HistorialEstado(OrdenCompraId) WHERE Accion='CREAR';
 CREATE INDEX IX_P3_COM_Historial ON dbo.P3_COM_HistorialEstado(OrdenCompraId,HistorialId);
END;
IF ISNULL(COL_LENGTH('dbo.P3_COM_OrdenCompra','Version'),0)<>8
 OR ISNULL(COL_LENGTH('dbo.P3_COM_HistorialEstado','SolicitudHash'),0)<>32
 OR OBJECT_ID('dbo.P3_COM_DetalleOrdenCompra','U') IS NULL
 THROW 55000,'Esquema Compras incompatible; no sobrescribir.',1;
-- No aceptar silenciosamente un esquema homonimo con precision o claves distintas.
IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.P3_COM_OrdenCompra') AND name='Total' AND TYPE_NAME(system_type_id)='decimal' AND precision=32 AND scale=4 AND is_nullable=0)
 OR NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.P3_COM_DetalleOrdenCompra') AND name='CostoUnitario' AND TYPE_NAME(system_type_id)='decimal' AND precision=19 AND scale=4 AND is_nullable=0)
 OR NOT EXISTS(SELECT 1 FROM sys.computed_columns WHERE object_id=OBJECT_ID('dbo.P3_COM_DetalleOrdenCompra') AND name='Subtotal' AND is_persisted=1 AND precision=32 AND scale=4)
 OR EXISTS(SELECT 1 FROM sys.check_constraints WHERE parent_object_id IN(OBJECT_ID('dbo.P3_COM_OrdenCompra'),OBJECT_ID('dbo.P3_COM_DetalleOrdenCompra'),OBJECT_ID('dbo.P3_COM_HistorialEstado')) AND (is_disabled=1 OR is_not_trusted=1))
 OR EXISTS(SELECT 1 FROM sys.foreign_keys WHERE parent_object_id IN(OBJECT_ID('dbo.P3_COM_OrdenCompra'),OBJECT_ID('dbo.P3_COM_DetalleOrdenCompra'),OBJECT_ID('dbo.P3_COM_HistorialEstado')) AND (is_disabled=1 OR is_not_trusted=1))
 THROW 55000,'Tipos o restricciones Compras incompatibles.',1;
IF NOT EXISTS(SELECT 1 FROM sys.indexes i JOIN sys.index_columns ic ON ic.object_id=i.object_id AND ic.index_id=i.index_id AND ic.key_ordinal=1
 JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id
 WHERE i.object_id=OBJECT_ID('dbo.P3_COM_HistorialEstado') AND i.is_unique=1 AND i.is_disabled=0 AND i.has_filter=0 AND c.name='OperacionId'
 AND NOT EXISTS(SELECT 1 FROM sys.index_columns more WHERE more.object_id=i.object_id AND more.index_id=i.index_id AND more.key_ordinal>1))
 THROW 55000,'Falta unicidad global de operacion.',1;
IF (SELECT COUNT(*) FROM sys.check_constraints WHERE name IN('CK_P3_COM_Total','CK_P3_COM_Estado','CK_P3_COM_Cantidad','CK_P3_COM_Costo','CK_P3_COM_Motivo','CK_P3_COM_Transicion') AND is_disabled=0 AND is_not_trusted=0)<>6
 OR (SELECT COUNT(*) FROM sys.foreign_keys WHERE parent_object_id IN(OBJECT_ID('dbo.P3_COM_OrdenCompra'),OBJECT_ID('dbo.P3_COM_DetalleOrdenCompra'),OBJECT_ID('dbo.P3_COM_HistorialEstado')))<>6
 OR (SELECT COUNT(*) FROM sys.key_constraints WHERE parent_object_id IN(OBJECT_ID('dbo.P3_COM_OrdenCompra'),OBJECT_ID('dbo.P3_COM_DetalleOrdenCompra'),OBJECT_ID('dbo.P3_COM_HistorialEstado')) AND type='PK')<>3
 OR NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.P3_COM_OrdenCompra') AND name='UX_P3_COM_Numero' AND is_unique=1 AND is_disabled=0)
 OR NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.P3_COM_HistorialEstado') AND name='UX_P3_COM_Creacion' AND is_unique=1 AND is_disabled=0 AND has_filter=1)
 THROW 55000,'Faltan claves o restricciones Compras; revisar esquema.',1;
INSERT dbo.Permiso(Codigo,Descripcion)
SELECT v.Codigo,v.Descripcion FROM (VALUES
 (N'COMPRAS_CONSULTAR',N'Consultar ordenes de compra e historial'),
 (N'COMPRAS_CREAR',N'Crear y enviar ordenes a aprobacion'),
 (N'COMPRAS_APROBAR',N'Aprobar ordenes creadas por otro usuario'),
 (N'COMPRAS_CANCELAR',N'Cancelar ordenes sin recepciones'))v(Codigo,Descripcion)
WHERE NOT EXISTS(SELECT 1 FROM dbo.Permiso WITH(UPDLOCK,HOLDLOCK) WHERE Codigo=v.Codigo);
-- Ninguna asignacion automatica a roles, incluido Administrador.
DENY SELECT,INSERT,UPDATE,DELETE ON dbo.P3_COM_OrdenCompra TO securefinance_app;
DENY SELECT,INSERT,UPDATE,DELETE ON dbo.P3_COM_DetalleOrdenCompra TO securefinance_app;
DENY SELECT,INSERT,UPDATE,DELETE ON dbo.P3_COM_HistorialEstado TO securefinance_app;
-- SQL Server permite que GRANT de columna prevalezca sobre DENY de tabla.
-- Solo identificadores obtenidos del catalogo, delimitados con QUOTENAME.
DECLARE @Tabla SYSNAME,@Columnas NVARCHAR(MAX),@Deny NVARCHAR(MAX);
DECLARE ProteccionColumnas CURSOR LOCAL FAST_FORWARD FOR
 SELECT t.name,STRING_AGG(CONVERT(NVARCHAR(MAX),QUOTENAME(c.name)),N',')
 FROM sys.tables t JOIN sys.columns c ON c.object_id=t.object_id
 WHERE t.object_id IN(OBJECT_ID('dbo.P3_COM_OrdenCompra'),OBJECT_ID('dbo.P3_COM_DetalleOrdenCompra'),OBJECT_ID('dbo.P3_COM_HistorialEstado')) GROUP BY t.name;
OPEN ProteccionColumnas;
FETCH NEXT FROM ProteccionColumnas INTO @Tabla,@Columnas;
WHILE @@FETCH_STATUS=0
BEGIN
 SET @Deny=N'DENY SELECT,UPDATE ON OBJECT::dbo.'+QUOTENAME(@Tabla)+N' ('+@Columnas+N') TO securefinance_app; DENY ALTER,TAKE OWNERSHIP ON OBJECT::dbo.'+QUOTENAME(@Tabla)+N' TO securefinance_app;';
 EXEC sys.sp_executesql @Deny;
 FETCH NEXT FROM ProteccionColumnas INTO @Tabla,@Columnas;
END;
CLOSE ProteccionColumnas; DEALLOCATE ProteccionColumnas;
GO
CREATE OR ALTER TRIGGER dbo.P3_COM_OrdenProtegida ON dbo.P3_COM_OrdenCompra AFTER UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM deleted d LEFT JOIN inserted i ON i.OrdenCompraId=d.OrdenCompraId
 WHERE i.OrdenCompraId IS NULL) THROW 55005,'No se eliminan ordenes.',1;
 IF UPDATE(ProveedorId) OR UPDATE(ProveedorNombre) OR UPDATE(ProveedorNIT)
 OR UPDATE(CreadorUsuarioId) OR UPDATE(FechaCreacion) OR UPDATE(Observaciones) OR UPDATE(Total)
 THROW 55005,'El contenido emitido es inmutable.',1;
 IF EXISTS(SELECT 1 FROM inserted i JOIN deleted d ON d.OrdenCompraId=i.OrdenCompraId
 WHERE NOT((d.Estado='BORRADOR' AND i.Estado='PENDIENTE_APROBACION')
 OR (d.Estado='PENDIENTE_APROBACION' AND i.Estado='APROBADA')
 OR (d.Estado IN('BORRADOR','PENDIENTE_APROBACION','APROBADA') AND i.Estado='CANCELADA')))
 THROW 55005,'Transicion no habilitada en esta etapa.',1;
END;
GO
CREATE OR ALTER TRIGGER dbo.P3_COM_DetalleInmutable ON dbo.P3_COM_DetalleOrdenCompra AFTER UPDATE,DELETE AS
BEGIN
 IF EXISTS(SELECT 1 FROM deleted) THROW 55005,'Detalle inmutable.',1;
END;
GO
CREATE OR ALTER TRIGGER dbo.P3_COM_HistorialInmutable ON dbo.P3_COM_HistorialEstado AFTER UPDATE,DELETE AS
BEGIN
 IF EXISTS(SELECT 1 FROM deleted) THROW 55005,'Historial inmutable.',1;
END;
GO
CREATE OR ALTER TRIGGER dbo.P3_COM_AuditarEstado ON dbo.P3_COM_HistorialEstado AFTER INSERT AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.Bitacora_Transacciones(TablaAfectada,Operacion,IdentificadorRegistro,ValorAnterior,ValorNuevo,ActorUsuarioId,OperacionId,Motivo)
 SELECT N'P3_COM_OrdenCompra',CASE WHEN i.Accion='CREAR' THEN 'INSERT' ELSE 'UPDATE' END,
 CONVERT(NVARCHAR(20),i.OrdenCompraId),
 (SELECT i.EstadoAnterior Estado FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER),
 (SELECT i.EstadoNuevo Estado,i.Accion,i.FechaHora,i.HistorialId FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),
 i.ActorUsuarioId,i.OperacionId,i.Motivo FROM inserted i;
END;
GO
