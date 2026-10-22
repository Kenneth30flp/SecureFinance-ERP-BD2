-- Incremental after 38. Historical invoices and monetary values are never rewritten.
SET XACT_ABORT ON; SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON;
IF OBJECT_ID('dbo.sp_ERP_RegistrarProducto','P') IS NULL
 OR OBJECT_ID('dbo.SolicitudVentaERP','U') IS NULL
 THROW 54800,'Requiere integracion 33-38.',1;
BEGIN TRY
 BEGIN TRANSACTION;
 IF OBJECT_ID('dbo.FacturaProductoEmision','U') IS NULL
 CREATE TABLE dbo.FacturaProductoEmision(
  DetalleFacturaId int NOT NULL PRIMARY KEY REFERENCES dbo.DetalleFactura(DetalleFacturaId),
  Codigo nvarchar(40) NOT NULL,Descripcion nvarchar(200) NOT NULL
 );
 IF ISNULL(COL_LENGTH('dbo.FacturaProductoEmision','Codigo'),-1)<>80
 OR ISNULL(COL_LENGTH('dbo.FacturaProductoEmision','Descripcion'),-1)<>400
 THROW 54800,'Identidad de emision incompatible; revisar sin borrar.',1;
 INSERT dbo.Permiso(Codigo,Descripcion)
 SELECT N'FACTURAS_CONSULTAR',N'Consultar y reimprimir comprobantes internos de facturas emitidas'
 WHERE NOT EXISTS(SELECT 1 FROM dbo.Permiso WITH(UPDLOCK,HOLDLOCK) WHERE Codigo=N'FACTURAS_CONSULTAR');
 -- Deliberate scope: existing sales Administrator/Cashier roles, never Auditor implicitly.
 INSERT dbo.Rol_Permiso(RolId,PermisoId)
 SELECT r.RolId,p.PermisoId FROM dbo.Rol r CROSS JOIN dbo.Permiso p
 WHERE r.Nombre IN(N'Administrador',N'Cajero') AND r.Activo=1 AND p.Codigo=N'FACTURAS_CONSULTAR'
 AND EXISTS(SELECT 1 FROM dbo.Rol_Permiso rp JOIN dbo.Permiso v ON v.PermisoId=rp.PermisoId WHERE rp.RolId=r.RolId AND v.Codigo=N'VENTAS_REGISTRAR')
 AND NOT EXISTS(SELECT 1 FROM dbo.Rol_Permiso rp WHERE rp.RolId=r.RolId AND rp.PermisoId=p.PermisoId);
 COMMIT;
END TRY BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK; THROW; END CATCH;
GO
CREATE OR ALTER TRIGGER dbo.tr_ERP_FacturaProductoEmision ON dbo.DetalleFactura AFTER INSERT AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.FacturaProductoEmision(DetalleFacturaId,Codigo,Descripcion)
 SELECT i.DetalleFacturaId,p.Codigo,p.Descripcion FROM inserted i JOIN dbo.Producto p ON p.ProductoId=i.ProductoId;
END;
GO
CREATE OR ALTER TRIGGER dbo.tr_ERP_FacturaProductoInmutable ON dbo.FacturaProductoEmision INSTEAD OF UPDATE,DELETE AS
BEGIN
 THROW 54805,'La identidad de producto al emitir es inmutable.',1;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_ERP_ConsultarFacturas
 @ActorUsuarioId int,@FacturaId int=NULL,@Cliente nvarchar(150)=NULL,
 @Desde datetime2(3)=NULL,@Hasta datetime2(3)=NULL,@Desplazamiento int=0,@Limite int=20
AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'FACTURAS_CONSULTAR';
 IF @Desplazamiento IS NULL OR @Desplazamiento<0 OR @Limite IS NULL OR @Limite NOT BETWEEN 1 AND 50
 OR @FacturaId<1 OR @Desde>=@Hasta THROW 54102,'Filtros invalidos.',1;
 SELECT f.FacturaId,f.FechaHora,f.ClienteNombreEmision Cliente,f.ClienteNITEmision NIT,
 u.NombreUsuario Responsable,CONVERT(varchar(21),f.Subtotal) Subtotal,
 CONVERT(varchar(21),f.DescuentoTotal) Descuento,CONVERT(varchar(21),f.IVA) IVA,
 CONVERT(varchar(21),f.Total) Total,f.Estado,COUNT_BIG(*) OVER() TotalFilas
 FROM dbo.Factura f JOIN dbo.Usuario u ON u.UsuarioId=f.UsuarioId
 WHERE (@FacturaId IS NULL OR f.FacturaId=@FacturaId)
 AND (@Cliente IS NULL OR CHARINDEX(@Cliente,f.ClienteNombreEmision)>0 OR CHARINDEX(@Cliente,f.ClienteNITEmision)>0)
 AND (@Desde IS NULL OR f.FechaHora>=@Desde) AND (@Hasta IS NULL OR f.FechaHora<@Hasta)
 ORDER BY f.FechaHora DESC,f.FacturaId DESC OFFSET @Desplazamiento ROWS FETCH NEXT @Limite ROWS ONLY;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_ERP_ConsultarComprobante @ActorUsuarioId int,@FacturaId int AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'FACTURAS_CONSULTAR';
 IF @FacturaId IS NULL OR @FacturaId<1 THROW 54102,'Factura invalida.',1;
 SELECT f.FacturaId,f.FechaHora,f.ClienteNombreEmision Cliente,f.ClienteNITEmision NIT,
 u.NombreUsuario Responsable,CONVERT(varchar(21),f.Subtotal) Subtotal,
 CONVERT(varchar(21),f.DescuentoTotal) Descuento,
 CONVERT(varchar(21),f.Subtotal-f.DescuentoTotal) SubtotalNeto,
 CONVERT(varchar(21),f.IVA) IVA,CONVERT(varchar(21),f.Total) Total,f.Estado,f.MotivoDescuento
 FROM dbo.Factura f JOIN dbo.Usuario u ON u.UsuarioId=f.UsuarioId WHERE f.FacturaId=@FacturaId;
 SELECT d.DetalleFacturaId,d.ProductoId,COALESCE(e.Codigo,p.Codigo) Codigo,
 COALESCE(e.Descripcion,j.Descripcion,p.Descripcion) Descripcion,
 CONVERT(bit,CASE WHEN e.DetalleFacturaId IS NULL THEN 1 ELSE 0 END) ReferenciaCatalogo,
 d.Cantidad,CONVERT(varchar(21),d.PrecioUnitario) PrecioUnitario,
 CONVERT(varchar(21),d.Subtotal) Subtotal,CONVERT(varchar(6),d.DescuentoPorcentaje) DescuentoPorcentaje,
 CONVERT(varchar(21),d.DescuentoMonto) DescuentoMonto,CONVERT(varchar(21),d.SubtotalNeto) SubtotalNeto
 FROM dbo.DetalleFactura d JOIN dbo.Producto p ON p.ProductoId=d.ProductoId
 LEFT JOIN dbo.FacturaProductoEmision e ON e.DetalleFacturaId=d.DetalleFacturaId
 LEFT JOIN dbo.SolicitudVentaERP s ON s.FacturaId=d.FacturaId
 OUTER APPLY(SELECT x.Descripcion FROM OPENJSON(s.Detalle) WITH(ProductoId int,Descripcion nvarchar(200)) x WHERE x.ProductoId=d.ProductoId) j
 WHERE d.FacturaId=@FacturaId ORDER BY d.DetalleFacturaId;
END;
GO
GRANT EXECUTE ON dbo.sp_ERP_ConsultarFacturas TO securefinance_app;
GRANT EXECUTE ON dbo.sp_ERP_ConsultarComprobante TO securefinance_app;
DENY SELECT,INSERT,UPDATE,DELETE ON dbo.FacturaProductoEmision TO securefinance_app;
GO
