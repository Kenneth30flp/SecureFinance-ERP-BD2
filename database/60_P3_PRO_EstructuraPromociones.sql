-- 60: Promociones (José). Estructura, catálogo de tipos, categorías comerciales,
-- historial inmutable, aplicaciones por factura y permisos separados.
-- Incremental, sin USE, repetible. No altera Producto, Factura, DetalleFactura,
-- TipoDetalleVentaDescuento ni SolicitudVentaERP. Ejecutar primero en laboratorio,
-- dentro de una transacción externa del instalador, después de 41-44.
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
IF OBJECT_ID('dbo.sp_ConvertirCotizacionAFactura','P') IS NULL
 OR NOT EXISTS(SELECT 1 FROM sys.parameters WHERE object_id=OBJECT_ID('dbo.sp_ERP_ProcesarVenta') AND name='@P3CotizacionId')
 THROW 57100,'Requiere Parte II hasta 40 y Cotizaciones 41-43.',1;
BEGIN TRY
 BEGIN TRANSACTION;
 IF OBJECT_ID('dbo.P3_PRO_TipoPromocion','U') IS NULL
 CREATE TABLE dbo.P3_PRO_TipoPromocion(
  TipoCodigo VARCHAR(20) NOT NULL CONSTRAINT PK_P3_PRO_TipoPromocion PRIMARY KEY,
  Nombre NVARCHAR(60) NOT NULL,
  Descripcion NVARCHAR(250) NOT NULL,
  Elegibilidad VARCHAR(10) NOT NULL CONSTRAINT CK_P3_PRO_Tipo_Elegibilidad CHECK(Elegibilidad IN('PRODUCTO','CATEGORIA'))
 );
 MERGE dbo.P3_PRO_TipoPromocion WITH(HOLDLOCK) t
 USING (VALUES
  ('PORCENTAJE',N'Descuento porcentual',N'Porcentaje sobre el subtotal de la línea de productos elegibles.','PRODUCTO'),
  ('CATEGORIA',N'Descuento por categoría',N'Porcentaje sobre productos asignados a una categoría comercial elegible.','CATEGORIA'),
  ('DOS_POR_UNO',N'Promoción 2x1',N'Por cada dos unidades de la misma línea se bonifica una: FLOOR(cantidad/2) × precio.','PRODUCTO'),
  ('VOLUMEN',N'Descuento por volumen',N'Porcentaje sobre la línea cuando la cantidad alcanza el mínimo configurado.','PRODUCTO')
 ) s(TipoCodigo,Nombre,Descripcion,Elegibilidad) ON t.TipoCodigo=s.TipoCodigo
 WHEN NOT MATCHED THEN INSERT(TipoCodigo,Nombre,Descripcion,Elegibilidad) VALUES(s.TipoCodigo,s.Nombre,s.Descripcion,s.Elegibilidad);

 -- Extensión incremental: el catálogo no tiene categorías. Una categoría por producto,
 -- en tabla propia, sin columnas nuevas en dbo.Producto.
 IF OBJECT_ID('dbo.P3_PRO_Categoria','U') IS NULL
 CREATE TABLE dbo.P3_PRO_Categoria(
  CategoriaId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_P3_PRO_Categoria PRIMARY KEY,
  Nombre NVARCHAR(80) NOT NULL CONSTRAINT UQ_P3_PRO_Categoria_Nombre UNIQUE,
  Activa BIT NOT NULL CONSTRAINT DF_P3_PRO_Categoria_Activa DEFAULT(1),
  CreadaPor INT NOT NULL CONSTRAINT FK_P3_PRO_Categoria_Usuario REFERENCES dbo.Usuario(UsuarioId),
  FechaCreacion DATETIME2(3) NOT NULL CONSTRAINT DF_P3_PRO_Categoria_Fecha DEFAULT SYSUTCDATETIME(),
  CONSTRAINT CK_P3_PRO_Categoria_Nombre CHECK(LEN(LTRIM(RTRIM(Nombre)))>0)
 );
 IF OBJECT_ID('dbo.P3_PRO_ProductoCategoria','U') IS NULL
 BEGIN
 CREATE TABLE dbo.P3_PRO_ProductoCategoria(
  ProductoId INT NOT NULL CONSTRAINT PK_P3_PRO_ProductoCategoria PRIMARY KEY
   CONSTRAINT FK_P3_PRO_ProductoCategoria_Producto REFERENCES dbo.Producto(ProductoId),
  CategoriaId INT NOT NULL CONSTRAINT FK_P3_PRO_ProductoCategoria_Categoria REFERENCES dbo.P3_PRO_Categoria(CategoriaId),
  AsignadaPor INT NOT NULL CONSTRAINT FK_P3_PRO_ProductoCategoria_Usuario REFERENCES dbo.Usuario(UsuarioId),
  FechaAsignacion DATETIME2(3) NOT NULL CONSTRAINT DF_P3_PRO_ProductoCategoria_Fecha DEFAULT SYSUTCDATETIME()
 );
 CREATE INDEX IX_P3_PRO_ProductoCategoria_Categoria ON dbo.P3_PRO_ProductoCategoria(CategoriaId);
 END;

 IF OBJECT_ID('dbo.P3_PRO_Promocion','U') IS NULL
 BEGIN
 CREATE TABLE dbo.P3_PRO_Promocion(
  PromocionId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_P3_PRO_Promocion PRIMARY KEY,
  Codigo NVARCHAR(30) NOT NULL CONSTRAINT UQ_P3_PRO_Promocion_Codigo UNIQUE,
  Nombre NVARCHAR(120) NOT NULL,
  Descripcion NVARCHAR(250) NULL,
  TipoCodigo VARCHAR(20) NOT NULL CONSTRAINT FK_P3_PRO_Promocion_Tipo REFERENCES dbo.P3_PRO_TipoPromocion(TipoCodigo),
  -- Condiciones tipadas: porcentaje, cantidad mínima por línea y tope monetario por línea.
  Porcentaje DECIMAL(5,2) NULL,
  CantidadMinima INT NULL,
  TopeDescuento DECIMAL(19,2) NULL,
  -- Vigencia UTC [VigenteDesde, VigenteHasta).
  VigenteDesde DATETIME2(3) NOT NULL,
  VigenteHasta DATETIME2(3) NOT NULL,
  Activa BIT NOT NULL CONSTRAINT DF_P3_PRO_Promocion_Activa DEFAULT(0),
  CreadaPor INT NOT NULL CONSTRAINT FK_P3_PRO_Promocion_Creador REFERENCES dbo.Usuario(UsuarioId),
  FechaCreacion DATETIME2(3) NOT NULL CONSTRAINT DF_P3_PRO_Promocion_Fecha DEFAULT SYSUTCDATETIME(),
  ModificadaPor INT NOT NULL CONSTRAINT FK_P3_PRO_Promocion_Modificador REFERENCES dbo.Usuario(UsuarioId),
  FechaModificacion DATETIME2(3) NOT NULL CONSTRAINT DF_P3_PRO_Promocion_FechaMod DEFAULT SYSUTCDATETIME(),
  Version ROWVERSION NOT NULL,
  CONSTRAINT CK_P3_PRO_Promocion_Codigo CHECK(LEN(LTRIM(RTRIM(Codigo)))>0),
  CONSTRAINT CK_P3_PRO_Promocion_Nombre CHECK(LEN(LTRIM(RTRIM(Nombre)))>0),
  CONSTRAINT CK_P3_PRO_Promocion_Vigencia CHECK(VigenteHasta>VigenteDesde AND VigenteHasta<=DATEADD(DAY,367,VigenteDesde)),
  CONSTRAINT CK_P3_PRO_Promocion_Tope CHECK(TopeDescuento IS NULL OR TopeDescuento>0),
  CONSTRAINT CK_P3_PRO_Promocion_Reglas CHECK(
   (TipoCodigo IN('PORCENTAJE','CATEGORIA') AND Porcentaje BETWEEN 0.01 AND 90.00 AND (CantidadMinima IS NULL OR CantidadMinima BETWEEN 1 AND 100000))
   OR (TipoCodigo='VOLUMEN' AND Porcentaje BETWEEN 0.01 AND 90.00 AND CantidadMinima BETWEEN 2 AND 100000)
   OR (TipoCodigo='DOS_POR_UNO' AND Porcentaje IS NULL AND CantidadMinima=2))
 );
 CREATE INDEX IX_P3_PRO_Promocion_Vigencia ON dbo.P3_PRO_Promocion(Activa,VigenteDesde,VigenteHasta) INCLUDE(TipoCodigo,Porcentaje,CantidadMinima,TopeDescuento);
 END;
 IF OBJECT_ID('dbo.P3_PRO_PromocionProducto','U') IS NULL
 BEGIN
 CREATE TABLE dbo.P3_PRO_PromocionProducto(
  PromocionId INT NOT NULL CONSTRAINT FK_P3_PRO_PromocionProducto_Promocion REFERENCES dbo.P3_PRO_Promocion(PromocionId),
  ProductoId INT NOT NULL CONSTRAINT FK_P3_PRO_PromocionProducto_Producto REFERENCES dbo.Producto(ProductoId),
  CONSTRAINT PK_P3_PRO_PromocionProducto PRIMARY KEY(PromocionId,ProductoId)
 );
 CREATE INDEX IX_P3_PRO_PromocionProducto_Producto ON dbo.P3_PRO_PromocionProducto(ProductoId,PromocionId);
 END;
 IF OBJECT_ID('dbo.P3_PRO_PromocionCategoria','U') IS NULL
 BEGIN
 CREATE TABLE dbo.P3_PRO_PromocionCategoria(
  PromocionId INT NOT NULL CONSTRAINT FK_P3_PRO_PromocionCategoria_Promocion REFERENCES dbo.P3_PRO_Promocion(PromocionId),
  CategoriaId INT NOT NULL CONSTRAINT FK_P3_PRO_PromocionCategoria_Categoria REFERENCES dbo.P3_PRO_Categoria(CategoriaId),
  CONSTRAINT PK_P3_PRO_PromocionCategoria PRIMARY KEY(PromocionId,CategoriaId)
 );
 CREATE INDEX IX_P3_PRO_PromocionCategoria_Categoria ON dbo.P3_PRO_PromocionCategoria(CategoriaId,PromocionId);
 END;

 IF OBJECT_ID('dbo.P3_PRO_HistorialPromocion','U') IS NULL
 BEGIN
 CREATE TABLE dbo.P3_PRO_HistorialPromocion(
  HistorialId BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_P3_PRO_HistorialPromocion PRIMARY KEY,
  PromocionId INT NOT NULL CONSTRAINT FK_P3_PRO_Historial_Promocion REFERENCES dbo.P3_PRO_Promocion(PromocionId),
  Accion VARCHAR(12) NOT NULL CONSTRAINT CK_P3_PRO_Historial_Accion CHECK(Accion IN('CREAR','EDITAR','ACTIVAR','DESACTIVAR')),
  ValorAnterior NVARCHAR(MAX) NULL,
  ValorNuevo NVARCHAR(MAX) NOT NULL,
  CamposModificados NVARCHAR(400) NULL,
  ActorUsuarioId INT NOT NULL CONSTRAINT FK_P3_PRO_Historial_Usuario REFERENCES dbo.Usuario(UsuarioId),
  FechaHora DATETIME2(3) NOT NULL CONSTRAINT DF_P3_PRO_Historial_Fecha DEFAULT SYSUTCDATETIME(),
  OperacionId UNIQUEIDENTIFIER NOT NULL CONSTRAINT UQ_P3_PRO_Historial_Operacion UNIQUE,
  SolicitudHash BINARY(32) NOT NULL,
  Motivo NVARCHAR(250) NOT NULL,
  CONSTRAINT CK_P3_PRO_Historial_Json CHECK((ValorAnterior IS NULL OR ISJSON(ValorAnterior)=1) AND ISJSON(ValorNuevo)=1),
  CONSTRAINT CK_P3_PRO_Historial_Motivo CHECK(LEN(LTRIM(RTRIM(Motivo)))>0)
 );
 CREATE INDEX IX_P3_PRO_Historial_Promocion ON dbo.P3_PRO_HistorialPromocion(PromocionId,HistorialId);
 END;
 IF OBJECT_ID('dbo.P3_PRO_HistorialCategoria','U') IS NULL
 CREATE TABLE dbo.P3_PRO_HistorialCategoria(
  HistorialId BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_P3_PRO_HistorialCategoria PRIMARY KEY,
  Accion VARCHAR(16) NOT NULL CONSTRAINT CK_P3_PRO_HistCat_Accion CHECK(Accion IN('CREAR_CATEGORIA','ASIGNAR','RETIRAR')),
  CategoriaId INT NULL CONSTRAINT FK_P3_PRO_HistCat_Categoria REFERENCES dbo.P3_PRO_Categoria(CategoriaId),
  ProductoId INT NULL CONSTRAINT FK_P3_PRO_HistCat_Producto REFERENCES dbo.Producto(ProductoId),
  CategoriaAnteriorId INT NULL CONSTRAINT FK_P3_PRO_HistCat_Anterior REFERENCES dbo.P3_PRO_Categoria(CategoriaId),
  ActorUsuarioId INT NOT NULL CONSTRAINT FK_P3_PRO_HistCat_Usuario REFERENCES dbo.Usuario(UsuarioId),
  FechaHora DATETIME2(3) NOT NULL CONSTRAINT DF_P3_PRO_HistCat_Fecha DEFAULT SYSUTCDATETIME(),
  OperacionId UNIQUEIDENTIFIER NOT NULL CONSTRAINT UQ_P3_PRO_HistCat_Operacion UNIQUE,
  SolicitudHash BINARY(32) NOT NULL,
  Motivo NVARCHAR(250) NOT NULL
 );

 -- Una aplicación como máximo por línea facturada: no hay acumulación de promociones.
 -- Conserva el beneficio teórico, el importe registrado y la regla vigente al facturar.
 IF OBJECT_ID('dbo.P3_PRO_AplicacionFactura','U') IS NULL
 BEGIN
 CREATE TABLE dbo.P3_PRO_AplicacionFactura(
  AplicacionId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_P3_PRO_AplicacionFactura PRIMARY KEY,
  FacturaId INT NOT NULL CONSTRAINT FK_P3_PRO_Aplicacion_Factura REFERENCES dbo.Factura(FacturaId),
  DetalleFacturaId INT NOT NULL CONSTRAINT UQ_P3_PRO_Aplicacion_Detalle UNIQUE
   CONSTRAINT FK_P3_PRO_Aplicacion_Detalle REFERENCES dbo.DetalleFactura(DetalleFacturaId),
  PromocionId INT NOT NULL CONSTRAINT FK_P3_PRO_Aplicacion_Promocion REFERENCES dbo.P3_PRO_Promocion(PromocionId),
  ProductoId INT NOT NULL CONSTRAINT FK_P3_PRO_Aplicacion_Producto REFERENCES dbo.Producto(ProductoId),
  TipoCodigo VARCHAR(20) NOT NULL CONSTRAINT FK_P3_PRO_Aplicacion_Tipo REFERENCES dbo.P3_PRO_TipoPromocion(TipoCodigo),
  Cantidad INT NOT NULL,
  PrecioUnitario DECIMAL(12,2) NOT NULL,
  Subtotal DECIMAL(19,2) NOT NULL,
  UnidadesBonificadas INT NOT NULL,
  BeneficioTeorico DECIMAL(19,2) NOT NULL,
  DescuentoPorcentaje DECIMAL(5,2) NOT NULL,
  DescuentoMonto DECIMAL(19,2) NOT NULL,
  DescuentoManualDescartado DECIMAL(5,2) NOT NULL,
  ReglaVersion BINARY(8) NOT NULL,
  Regla NVARCHAR(MAX) NOT NULL,
  FechaHora DATETIME2(3) NOT NULL,
  CONSTRAINT CK_P3_PRO_Aplicacion_Importes CHECK(Cantidad>0 AND PrecioUnitario>=0
   AND Subtotal=PrecioUnitario*CONVERT(DECIMAL(10,0),Cantidad) AND UnidadesBonificadas BETWEEN 0 AND Cantidad
   AND DescuentoMonto>0 AND DescuentoMonto<=BeneficioTeorico AND BeneficioTeorico<=Subtotal
   AND DescuentoMonto=ROUND(Subtotal*DescuentoPorcentaje/CONVERT(DECIMAL(5,2),100),2)
   AND DescuentoManualDescartado BETWEEN 0 AND 100),
  CONSTRAINT CK_P3_PRO_Aplicacion_Regla CHECK(ISJSON(Regla)=1)
 );
 CREATE INDEX IX_P3_PRO_Aplicacion_Factura ON dbo.P3_PRO_AplicacionFactura(FacturaId);
 CREATE INDEX IX_P3_PRO_Aplicacion_Promocion ON dbo.P3_PRO_AplicacionFactura(PromocionId,FechaHora);
 END;

 IF COL_LENGTH('dbo.P3_PRO_Promocion','Porcentaje')<>5 OR COL_LENGTH('dbo.P3_PRO_AplicacionFactura','DescuentoMonto')<>9
  THROW 57100,'Estructura de Promociones incompatible; no sobrescribir.',1;

 INSERT dbo.Permiso(Codigo,Descripcion)
 SELECT v.Codigo,v.Descripcion FROM (VALUES
  (N'PROMOCIONES_CONSULTAR',N'Consultar promociones, condiciones e historial'),
  (N'PROMOCIONES_CREAR',N'Crear reglas promocionales inactivas'),
  (N'PROMOCIONES_MODIFICAR',N'Modificar reglas promocionales y categorías comerciales'),
  (N'PROMOCIONES_ACTIVAR',N'Activar o desactivar promociones'))v(Codigo,Descripcion)
 WHERE NOT EXISTS(SELECT 1 FROM dbo.Permiso p WITH(UPDLOCK,HOLDLOCK) WHERE p.Codigo=v.Codigo);
 -- Asignación inicial limitada al Administrador. Cajero no administra reglas globales.
 DECLARE @Rol INT=(SELECT RolId FROM dbo.Rol WHERE Nombre=N'Administrador' AND Activo=1);
 IF @Rol IS NULL THROW 57100,'Falta Administrador activo.',1;
 INSERT dbo.Rol_Permiso(RolId,PermisoId)
 SELECT @Rol,p.PermisoId FROM dbo.Permiso p
 WHERE p.Codigo IN(N'PROMOCIONES_CONSULTAR',N'PROMOCIONES_CREAR',N'PROMOCIONES_MODIFICAR',N'PROMOCIONES_ACTIVAR')
 AND NOT EXISTS(SELECT 1 FROM dbo.Rol_Permiso r WHERE r.RolId=@Rol AND r.PermisoId=p.PermisoId);
 COMMIT;
END TRY BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK; THROW; END CATCH;
GO
IF TYPE_ID('dbo.P3_PRO_TipoListaIds') IS NULL
 CREATE TYPE dbo.P3_PRO_TipoListaIds AS TABLE(Id INT NOT NULL PRIMARY KEY);
GO
CREATE OR ALTER TRIGGER dbo.P3_PRO_HistorialInmutable ON dbo.P3_PRO_HistorialPromocion AFTER UPDATE,DELETE AS
BEGIN
 IF EXISTS(SELECT 1 FROM deleted) THROW 57103,'Historial de promociones inmutable.',1;
END;
GO
CREATE OR ALTER TRIGGER dbo.P3_PRO_HistorialCategoriaInmutable ON dbo.P3_PRO_HistorialCategoria AFTER UPDATE,DELETE AS
BEGIN
 IF EXISTS(SELECT 1 FROM deleted) THROW 57103,'Historial de categorías inmutable.',1;
END;
GO
CREATE OR ALTER TRIGGER dbo.P3_PRO_AplicacionInmutable ON dbo.P3_PRO_AplicacionFactura AFTER UPDATE,DELETE AS
BEGIN
 IF EXISTS(SELECT 1 FROM deleted) THROW 57103,'Aplicación facturada inmutable.',1;
END;
GO
-- Una regla ya facturada conserva tipo y condiciones; solo admite nombre, descripción,
-- cierre anticipado de vigencia y cambio de estado. Las promociones no se eliminan.
CREATE OR ALTER TRIGGER dbo.P3_PRO_PromocionProtegida ON dbo.P3_PRO_Promocion AFTER UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM deleted d LEFT JOIN inserted i ON i.PromocionId=d.PromocionId WHERE i.PromocionId IS NULL)
  THROW 57103,'Las promociones no se eliminan; desactívelas.',1;
 IF UPDATE(Codigo) OR UPDATE(CreadaPor) OR UPDATE(FechaCreacion) THROW 57103,'Identidad de promoción inmutable.',1;
 IF EXISTS(SELECT 1 FROM deleted d JOIN inserted i ON i.PromocionId=d.PromocionId
  WHERE EXISTS(SELECT 1 FROM dbo.P3_PRO_AplicacionFactura a WHERE a.PromocionId=d.PromocionId)
  AND (i.TipoCodigo<>d.TipoCodigo OR ISNULL(i.Porcentaje,-1)<>ISNULL(d.Porcentaje,-1)
   OR ISNULL(i.CantidadMinima,-1)<>ISNULL(d.CantidadMinima,-1) OR ISNULL(i.TopeDescuento,-1)<>ISNULL(d.TopeDescuento,-1)
   OR i.VigenteDesde<>d.VigenteDesde OR i.VigenteHasta>d.VigenteHasta))
  THROW 57104,'La promoción ya fue aplicada en facturas: sus condiciones no cambian.',1;
END;
GO
CREATE OR ALTER TRIGGER dbo.P3_PRO_ElegibilidadProtegida ON dbo.P3_PRO_PromocionProducto AFTER INSERT,UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM (SELECT PromocionId FROM inserted UNION SELECT PromocionId FROM deleted) x
  WHERE EXISTS(SELECT 1 FROM dbo.P3_PRO_AplicacionFactura a WHERE a.PromocionId=x.PromocionId))
  THROW 57104,'La promoción ya fue aplicada en facturas: sus productos no cambian.',1;
END;
GO
CREATE OR ALTER TRIGGER dbo.P3_PRO_ElegibilidadCategoriaProtegida ON dbo.P3_PRO_PromocionCategoria AFTER INSERT,UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM (SELECT PromocionId FROM inserted UNION SELECT PromocionId FROM deleted) x
  WHERE EXISTS(SELECT 1 FROM dbo.P3_PRO_AplicacionFactura a WHERE a.PromocionId=x.PromocionId))
  THROW 57104,'La promoción ya fue aplicada en facturas: sus categorías no cambian.',1;
END;
GO
DENY SELECT,INSERT,UPDATE,DELETE ON dbo.P3_PRO_TipoPromocion TO securefinance_app;
DENY SELECT,INSERT,UPDATE,DELETE ON dbo.P3_PRO_Categoria TO securefinance_app;
DENY SELECT,INSERT,UPDATE,DELETE ON dbo.P3_PRO_ProductoCategoria TO securefinance_app;
DENY SELECT,INSERT,UPDATE,DELETE ON dbo.P3_PRO_Promocion TO securefinance_app;
DENY SELECT,INSERT,UPDATE,DELETE ON dbo.P3_PRO_PromocionProducto TO securefinance_app;
DENY SELECT,INSERT,UPDATE,DELETE ON dbo.P3_PRO_PromocionCategoria TO securefinance_app;
DENY SELECT,INSERT,UPDATE,DELETE ON dbo.P3_PRO_HistorialPromocion TO securefinance_app;
DENY SELECT,INSERT,UPDATE,DELETE ON dbo.P3_PRO_HistorialCategoria TO securefinance_app;
DENY SELECT,INSERT,UPDATE,DELETE ON dbo.P3_PRO_AplicacionFactura TO securefinance_app;
GRANT EXECUTE,REFERENCES ON TYPE::dbo.P3_PRO_TipoListaIds TO securefinance_app;
GO
