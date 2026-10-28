-- Incremental, no USE, no cambios a Facturacion/Kardex. Ejecutar en laboratorio primero.
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
IF OBJECT_ID('dbo.sp_ReactivarCliente','P') IS NULL
 OR TYPE_ID('dbo.TipoDetalleVentaDescuento') IS NULL
 THROW 54900,'Requiere esquema Parte II hasta 40.',1;
BEGIN TRY
 BEGIN TRANSACTION;
 IF OBJECT_ID('dbo.P3_COT_Cotizacion','U') IS NULL
 BEGIN
 CREATE TABLE dbo.P3_COT_Cotizacion(
  CotizacionId INT IDENTITY PRIMARY KEY,
  Numero AS ('COT-'+CONVERT(VARCHAR(10),CotizacionId)) PERSISTED,
  ClienteId INT NOT NULL REFERENCES dbo.Cliente(ClienteId),
  ClienteNombre NVARCHAR(150) NOT NULL,ClienteNIT NVARCHAR(25) NOT NULL,
  UsuarioId INT NOT NULL REFERENCES dbo.Usuario(UsuarioId),
  FechaCreacion DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
  VenceEn DATETIME2(3) NOT NULL,
  Estado VARCHAR(15) NOT NULL DEFAULT 'ACTIVA',
  Subtotal DECIMAL(19,2) NOT NULL,Descuento DECIMAL(19,2) NOT NULL,
  SubtotalNeto AS (Subtotal-Descuento) PERSISTED,
  IVA DECIMAL(19,2) NOT NULL,Total DECIMAL(19,2) NOT NULL,
  Observaciones NVARCHAR(1000) NULL,
  OperacionId UNIQUEIDENTIFIER NOT NULL UNIQUE,
  SolicitudHash BINARY(32) NOT NULL,
  FacturaId INT NULL REFERENCES dbo.Factura(FacturaId),
  CONSTRAINT CK_P3_COT_Vigencia CHECK(VenceEn>FechaCreacion),
  CONSTRAINT CK_P3_COT_Estado CHECK(Estado IN('ACTIVA','PROCESADA','CANCELADA')),
  CONSTRAINT CK_P3_COT_Factura CHECK((Estado='PROCESADA' AND FacturaId IS NOT NULL) OR (Estado<>'PROCESADA' AND FacturaId IS NULL)),
  CONSTRAINT CK_P3_COT_Importes CHECK(Subtotal>=0 AND Descuento BETWEEN 0 AND Subtotal AND IVA=ROUND((Subtotal-Descuento)*CONVERT(DECIMAL(3,2),0.12),2) AND Total=Subtotal-Descuento+IVA)
 );
 CREATE UNIQUE INDEX UX_P3_COT_Numero ON dbo.P3_COT_Cotizacion(Numero);
 CREATE UNIQUE INDEX UX_P3_COT_Factura ON dbo.P3_COT_Cotizacion(FacturaId) WHERE FacturaId IS NOT NULL;
 CREATE INDEX IX_P3_COT_Historial ON dbo.P3_COT_Cotizacion(FechaCreacion DESC,CotizacionId DESC) INCLUDE(ClienteId,Estado,VenceEn,Total);
 CREATE INDEX IX_P3_COT_Cliente ON dbo.P3_COT_Cotizacion(ClienteId,FechaCreacion);
 END;
 IF OBJECT_ID('dbo.P3_COT_Detalle','U') IS NULL
 CREATE TABLE dbo.P3_COT_Detalle(
  DetalleId INT IDENTITY PRIMARY KEY,
  CotizacionId INT NOT NULL REFERENCES dbo.P3_COT_Cotizacion(CotizacionId),
  ProductoId INT NOT NULL REFERENCES dbo.Producto(ProductoId),
  SKU NVARCHAR(40) NOT NULL,Descripcion NVARCHAR(200) NOT NULL,
  Cantidad INT NOT NULL CHECK(Cantidad>0),
  PrecioUnitario DECIMAL(12,2) NOT NULL CHECK(PrecioUnitario>=0),
  DescuentoPorcentaje DECIMAL(5,2) NOT NULL CHECK(DescuentoPorcentaje BETWEEN 0 AND 100),
  Subtotal DECIMAL(19,2) NOT NULL,
  DescuentoMonto DECIMAL(19,2) NOT NULL,
  SubtotalNeto AS (Subtotal-DescuentoMonto) PERSISTED,
  UNIQUE(CotizacionId,ProductoId),
  CHECK(Subtotal=PrecioUnitario*CONVERT(DECIMAL(10,0),Cantidad)),
  CHECK(DescuentoMonto=ROUND(Subtotal*DescuentoPorcentaje/CONVERT(DECIMAL(5,2),100),2))
 );
 IF OBJECT_ID('dbo.P3_COT_HistorialEstado','U') IS NULL
 CREATE TABLE dbo.P3_COT_HistorialEstado(
  HistorialId BIGINT IDENTITY PRIMARY KEY,
  CotizacionId INT NOT NULL REFERENCES dbo.P3_COT_Cotizacion(CotizacionId),
  EstadoAnterior VARCHAR(15) NULL,EstadoNuevo VARCHAR(15) NOT NULL,
  ActorUsuarioId INT NOT NULL REFERENCES dbo.Usuario(UsuarioId),
  FechaHora DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
  OperacionId UNIQUEIDENTIFIER NOT NULL UNIQUE,
  Motivo NVARCHAR(250) NOT NULL,
  CHECK(EstadoNuevo IN('ACTIVA','CANCELADA','PROCESADA'))
 );
 IF COL_LENGTH('dbo.P3_COT_Cotizacion','SolicitudHash')<>32
 OR COL_LENGTH('dbo.P3_COT_Detalle','PrecioUnitario')<>9
 THROW 54900,'Estructura Cotizaciones incompatible; no sobrescribir.',1;
 INSERT dbo.Permiso(Codigo,Descripcion)
 SELECT v.Codigo,v.Descripcion FROM (VALUES
 (N'COTIZACIONES_CONSULTAR',N'Consultar documentos de cotizacion'),
 (N'COTIZACIONES_CREAR',N'Emitir cotizaciones con precios historicos'),
 (N'COTIZACIONES_CONVERTIR',N'Convertir cotizaciones autorizadas a factura'),
 (N'COTIZACIONES_CANCELAR',N'Cancelar cotizaciones vigentes con motivo'))v(Codigo,Descripcion)
 WHERE NOT EXISTS(SELECT 1 FROM dbo.Permiso p WITH(UPDLOCK,HOLDLOCK) WHERE p.Codigo=v.Codigo);
 -- Asignacion inicial limitada al Administrador, como migracion 40.
 DECLARE @Rol INT=(SELECT RolId FROM dbo.Rol WHERE Nombre=N'Administrador' AND Activo=1);
 IF @Rol IS NULL THROW 54900,'Falta Administrador activo.',1;
 INSERT dbo.Rol_Permiso(RolId,PermisoId)
 SELECT @Rol,PermisoId FROM dbo.Permiso p WHERE Codigo IN(N'COTIZACIONES_CONSULTAR',N'COTIZACIONES_CREAR',N'COTIZACIONES_CONVERTIR',N'COTIZACIONES_CANCELAR')
 AND NOT EXISTS(SELECT 1 FROM dbo.Rol_Permiso r WHERE r.RolId=@Rol AND r.PermisoId=p.PermisoId);
 COMMIT;
END TRY BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK; THROW; END CATCH;
GO
CREATE OR ALTER FUNCTION dbo.P3_COT_Vigencias()
RETURNS TABLE AS RETURN
 SELECT c.*,CASE WHEN Estado='ACTIVA' AND VenceEn<=SYSUTCDATETIME() THEN 'VENCIDA' ELSE Estado END AS EstadoVigente
 FROM dbo.P3_COT_Cotizacion c;
GO
CREATE OR ALTER TRIGGER dbo.P3_COT_DetalleInmutable ON dbo.P3_COT_Detalle AFTER UPDATE,DELETE AS
BEGIN
 IF EXISTS(SELECT 1 FROM deleted) THROW 54903,'Detalle emitido inmutable.',1;
END;
GO
CREATE OR ALTER TRIGGER dbo.P3_COT_HistorialInmutable ON dbo.P3_COT_HistorialEstado AFTER UPDATE,DELETE AS
BEGIN
 IF EXISTS(SELECT 1 FROM deleted) THROW 54903,'Historial inmutable.',1;
END;
GO
CREATE OR ALTER TRIGGER dbo.P3_COT_DocumentoInmutable ON dbo.P3_COT_Cotizacion AFTER UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM deleted d LEFT JOIN inserted i ON i.CotizacionId=d.CotizacionId WHERE i.CotizacionId IS NULL)
 THROW 54903,'No eliminar documentos emitidos.',1;
 IF UPDATE(ClienteId) OR UPDATE(ClienteNombre) OR UPDATE(ClienteNIT) OR UPDATE(UsuarioId)
 OR UPDATE(FechaCreacion) OR UPDATE(VenceEn) OR UPDATE(Subtotal) OR UPDATE(Descuento)
 OR UPDATE(IVA) OR UPDATE(Total) OR UPDATE(Observaciones) OR UPDATE(OperacionId) OR UPDATE(SolicitudHash)
 THROW 54903,'Condiciones emitidas inmutables.',1;
 IF EXISTS(SELECT 1 FROM deleted d JOIN inserted i ON i.CotizacionId=d.CotizacionId
 WHERE d.Estado<>'ACTIVA' OR i.Estado NOT IN('CANCELADA','PROCESADA'))
 THROW 54903,'Transicion de estado invalida.',1;
END;
GO
DENY SELECT,INSERT,UPDATE,DELETE ON dbo.P3_COT_Cotizacion TO securefinance_app;
DENY SELECT,INSERT,UPDATE,DELETE ON dbo.P3_COT_Detalle TO securefinance_app;
DENY SELECT,INSERT,UPDATE,DELETE ON dbo.P3_COT_HistorialEstado TO securefinance_app;
DENY SELECT ON dbo.P3_COT_Vigencias TO securefinance_app;
GO
