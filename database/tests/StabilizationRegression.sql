SET NOCOUNT ON; SET XACT_ABORT ON; SET QUOTED_IDENTIFIER ON; SET ANSI_NULLS ON;
SET ANSI_WARNINGS ON; SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET NUMERIC_ROUNDABORT OFF;
IF DB_NAME()<>'SecureFinanceERP_Estabilizacion_20261021' THROW 54900,'Solo laboratorio.',1;
DECLARE @Actor INT=(SELECT UsuarioId FROM dbo.Usuario WHERE NombreUsuario='admin'),@P INT=(SELECT ProductoId FROM dbo.Producto WHERE Codigo='DEMO-CABLE'),
 @C INT=(SELECT TOP(1) ClienteId FROM dbo.Cliente WHERE Activo=1),@V INT=(SELECT MIN(ProveedorId) FROM dbo.Proveedor WHERE Activo=1),@Stock INT,@F INT,@Op UNIQUEIDENTIFIER=NEWID();
SELECT @Stock=Stock FROM dbo.Producto WHERE ProductoId=@P;
DECLARE @Detalle dbo.TipoDetalleVentaDescuento; INSERT @Detalle VALUES(@P,1,0);
EXECUTE AS USER='securefinance_app';
EXEC dbo.sp_ERP_ProcesarVenta @C,@Actor,@Detalle,@Op;
EXEC dbo.sp_ERP_ProcesarVenta @C,@Actor,@Detalle,@Op;
REVERT;
SELECT @F=FacturaId FROM dbo.SolicitudVentaERP WHERE OperacionId=@Op;
IF @F IS NULL OR (SELECT Stock FROM dbo.Producto WHERE ProductoId=@P)<>@Stock-1
 OR (SELECT COUNT(*) FROM dbo.MovimientoCaja WHERE FacturaId=@F)<>1
 OR (SELECT COUNT(*) FROM dbo.Kardex_Inventario k JOIN dbo.DetalleFactura d ON d.DetalleFacturaId=k.DetalleFacturaId WHERE d.FacturaId=@F)<>1
 THROW 54900,'Venta idempotente inconsistente.',1;
PRINT 'PASS venta idempotente: una factura, caja y egreso';
DELETE @Detalle; INSERT @Detalle VALUES(@P,2,0);
BEGIN TRY
 EXEC dbo.sp_ERP_ProcesarVenta @C,@Actor,@Detalle,@Op;
 THROW 54900,'Acepto otra venta con la misma operacion.',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>54803 THROW; END CATCH;
PRINT 'PASS venta: clave reutilizada con otros datos rechazada';
-- Cadena de propiedad autoriza el ajuste, el procedimiento central permanece protegido.
DECLARE @Version BINARY(8)=(SELECT Version FROM dbo.Producto WHERE ProductoId=@P);
SET @Op=NEWID();
EXECUTE AS USER='securefinance_app';
EXEC dbo.sp_ERP_RegistrarAjuste @Actor,@P,'AJUSTE_INGRESO',1,N'LAB-AJUSTE',@Op,1,N'Ajuste documentado laboratorio',@Version;
BEGIN TRY
 EXEC dbo.sp_RegistrarMovimientoKardex @P,'COMPRA',1,@Actor,N'LAB-BYPASS',@Op,1,N'Bypass';
 THROW 54900,'Acceso directo central permitido.',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>229 THROW; END CATCH;
REVERT;
PRINT 'PASS ajuste por wrapper; acceso central directo denegado';
EXEC dbo.sp_AsociarProductoProveedor @Actor,@P,@V,1;
EXEC dbo.sp_ConsultarProductoProveedor @Actor,@P,NULL;
PRINT 'PASS mantenimiento y consulta de relacion comercial';
-- Conciliacion O: ventas facturadas brutas; las notas no reescriben importes originales.
DECLARE @Desde DATETIME2(3)='2026-01-01',@Hasta DATETIME2(3)='2027-01-01';
IF (SELECT COALESCE(SUM(ImporteVendido),0) FROM dbo.fn_ProductosMasVendidos(@Desde,@Hasta))<>
 (SELECT COALESCE(SUM(d.SubtotalNeto),0) FROM dbo.DetalleFactura d JOIN dbo.Factura f ON f.FacturaId=d.FacturaId WHERE f.Estado='EMITIDA' AND f.FechaHora>=@Desde AND f.FechaHora<@Hasta) THROW 54900,'O importe de productos duplicado.',1;
IF (SELECT SUM(TotalHistoricoComprado) FROM dbo.fn_AnalisisClientesFrecuentes(@Desde,@Hasta))<>
 (SELECT SUM(Total) FROM dbo.Factura WHERE Estado='EMITIDA' AND FechaHora>=@Desde AND FechaHora<@Hasta) THROW 54900,'O clientes duplica ventas.',1;
IF EXISTS(SELECT 1 FROM dbo.fn_ProductosPorComprar(0) r JOIN dbo.Producto p ON p.ProductoId=r.ProductoId WHERE r.Stock<>p.Stock OR r.PuntoReorden<>p.PuntoReorden) THROW 54900,'O stock analitico inconsistente.',1;
EXECUTE AS USER='securefinance_app';
EXEC dbo.sp_ObtenerResumenDashboard @Actor;
EXEC dbo.sp_ObtenerDashboardVentas @Actor,'RANGO','2026-01-01','2026-12-31';
REVERT;
PRINT 'PASS O TVF productos clientes abastecimiento; dashboards con permisos';
DBCC CHECKCONSTRAINTS WITH ALL_CONSTRAINTS;
DBCC CHECKDB WITH NO_INFOMSGS;
