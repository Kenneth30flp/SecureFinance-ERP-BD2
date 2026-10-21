SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET XACT_ABORT ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
IF DB_NAME() NOT LIKE 'SecureFinanceERP_Edward_Test[_]%' OR NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=0 AND name='Edward.TestRun') THROW 54900,'Isolated marked database required',1;
DECLARE @Actor INT=(SELECT TOP(1) UsuarioId FROM dbo.Usuario ORDER BY UsuarioId),
 @Cliente INT=(SELECT TOP(1) ClienteId FROM dbo.Cliente ORDER BY ClienteId),
 @Producto INT=(SELECT TOP(1) ProductoId FROM dbo.Producto ORDER BY ProductoId),
 @Rol INT=(SELECT RolId FROM dbo.Rol WHERE Nombre=N'Administrador');
IF @Actor IS NULL OR @Cliente IS NULL OR @Producto IS NULL THROW 54900,'Missing laboratory fixtures',1;
INSERT dbo.Rol_Permiso(RolId,PermisoId)
SELECT @Rol,p.PermisoId FROM dbo.Permiso p WHERE NOT EXISTS(SELECT 1 FROM dbo.Rol_Permiso rp WHERE rp.RolId=@Rol AND rp.PermisoId=p.PermisoId);
IF NOT EXISTS(SELECT 1 FROM dbo.Usuario_Rol WHERE UsuarioId=@Actor AND RolId=@Rol) INSERT dbo.Usuario_Rol(UsuarioId,RolId) VALUES(@Actor,@Rol);
DECLARE @Apertura UNIQUEIDENTIFIER=NEWID();
EXEC dbo.sp_AbrirKardexInventario @Apertura,@Actor,N'LAB-EDWARD',N'Apertura laboratorio aislado';
EXEC dbo.sp_HabilitarKardexInventario @Apertura,@Actor;
DECLARE @Compra UNIQUEIDENTIFIER=NEWID();
EXEC dbo.sp_RegistrarMovimientoKardex @Producto,'COMPRA',50,@Actor,N'LAB-STOCK',@Compra,1,N'Fixture',@DevolverResultado=0;
-- Future sales capture coverage, old sales remain unknown.
UPDATE dbo.Producto SET GarantiaMeses=12,Precio=10.01 WHERE ProductoId=@Producto;
DECLARE @Venta dbo.TipoDetalleVentaDescuento;
INSERT @Venta VALUES(@Producto,3,10);
DECLARE @Factura INT;
EXEC dbo.sp_ProcesarVentaTransaccional @Cliente,@Actor,@Venta,@Factura OUTPUT,N'Otro';
DECLARE @Detalle INT=(SELECT DetalleFacturaId FROM dbo.DetalleFactura WHERE FacturaId=@Factura);
IF NOT EXISTS(SELECT 1 FROM dbo.CoberturaGarantiaVenta WHERE DetalleFacturaId=@Detalle AND GarantiaMeses=12) THROW 54900,'Missing coverage snapshot',1;
DECLARE @Op UNIQUEIDENTIFIER=NEWID(),@Json NVARCHAR(MAX),@Error INT;
SET @Json=CONCAT(N'[{"DetalleFacturaId":',@Detalle,N',"Cantidad":1,"Reingresar":true}]');
-- Nonexistent invoice and foreign detail.
BEGIN TRY
 EXEC dbo.sp_ProcesarDevolucionCliente @Actor,2147483647,@Op,N'Invalid',@Json;
 THROW 54900,'Missing nonexistent invoice validation',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>54604 THROW; END CATCH;
DECLARE @Otra INT;
EXEC dbo.sp_ProcesarVentaTransaccional @Cliente,@Actor,@Venta,@Otra OUTPUT,N'Otro';
BEGIN TRY
 EXEC dbo.sp_ProcesarDevolucionCliente @Actor,@Otra,@Op,N'Invalid',@Json;
 THROW 54900,'Missing foreign product validation',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>54604 THROW; END CATCH;
SET @Json=CONCAT(N'[{"DetalleFacturaId":',@Detalle,N',"Cantidad":0,"Reingresar":true}]');
BEGIN TRY
 EXEC dbo.sp_ProcesarDevolucionCliente @Actor,@Factura,@Op,N'Invalid',@Json;
 THROW 54900,'Missing zero validation',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>54602 THROW; END CATCH;
SET @Json=CONCAT(N'[{"DetalleFacturaId":',@Detalle,N',"Cantidad":4,"Reingresar":true}]');
BEGIN TRY
 EXEC dbo.sp_ProcesarDevolucionCliente @Actor,@Factura,@Op,N'Invalid',@Json;
 THROW 54900,'Missing excessive quantity validation',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>54605 THROW; END CATCH;
-- Original price and discounts survive catalog changes; historical invoice IVA allocation.
UPDATE dbo.Producto SET Precio=999,GarantiaMeses=0 WHERE ProductoId=@Producto;
DECLARE @Stock INT=(SELECT Stock FROM dbo.Producto WHERE ProductoId=@Producto);
SET @Json=CONCAT(N'[{"DetalleFacturaId":',@Detalle,N',"Cantidad":1,"Reingresar":true}]');
EXECUTE AS USER='securefinance_app';
EXEC dbo.sp_ProcesarDevolucionCliente @Actor,@Factura,@Op,N'Parcial',@Json;
REVERT;
IF (SELECT Stock FROM dbo.Producto WHERE ProductoId=@Producto)<>@Stock+1 THROW 54900,'Reentry failed',1;
IF NOT EXISTS(SELECT 1 FROM dbo.DetalleDevolucion d JOIN dbo.DevolucionCliente r ON r.DevolucionId=d.DevolucionId WHERE r.OperacionId=@Op AND d.Subtotal=10.01 AND d.Descuento=1.00 AND d.IVA=1.08) THROW 54900,'Historical values failed',1;
EXEC dbo.sp_ProcesarDevolucionCliente @Actor,@Factura,@Op,N'Parcial',@Json;
IF (SELECT COUNT(*) FROM dbo.Kardex_Inventario WHERE OperacionId=@Op)<>1 THROW 54900,'Duplicate Kardex',1;
IF (SELECT COUNT(*) FROM dbo.NotaCredito n JOIN dbo.DevolucionCliente d ON d.DevolucionId=n.DevolucionId WHERE d.OperacionId=@Op)<>1 THROW 54900,'Duplicate note',1;
BEGIN TRY
 EXEC dbo.sp_ProcesarDevolucionCliente @Actor,@Factura,@Op,N'Changed',@Json;
 THROW 54900,'Missing key reuse validation',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>54603 THROW; END CATCH;
SET @Op=NEWID();
SET @Json=CONCAT(N'[{"DetalleFacturaId":',@Detalle,N',"Cantidad":2,"Reingresar":false}]');
EXEC dbo.sp_ProcesarDevolucionCliente @Actor,@Factura,@Op,N'Defectuoso',@Json;
IF (SELECT Stock FROM dbo.Producto WHERE ProductoId=@Producto)<>@Stock+1 OR EXISTS(SELECT 1 FROM dbo.Kardex_Inventario WHERE OperacionId=@Op) THROW 54900,'Defective reentered stock',1;
IF (SELECT SUM(n.Total) FROM dbo.NotaCredito n JOIN dbo.DevolucionCliente d ON d.DevolucionId=n.DevolucionId WHERE d.FacturaId=@Factura)<>(SELECT Total FROM dbo.Factura WHERE FacturaId=@Factura) THROW 54900,'Partial rounding failed',1;
IF (SELECT COUNT(*) FROM dbo.MovimientoCaja WHERE FacturaId=@Factura)<>1 THROW 54900,'False cash entry',1;
SET @Op=NEWID();
BEGIN TRY
 EXEC dbo.sp_ProcesarDevolucionCliente @Actor,@Factura,@Op,N'Accumulated',@Json;
 THROW 54900,'Missing accumulated validation',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>54605 THROW; END CATCH;
-- Full rollback when central Kardex fails, including caller transaction.
DECLARE @DetalleOtra INT=(SELECT DetalleFacturaId FROM dbo.DetalleFactura WHERE FacturaId=@Otra);
SET @Json=CONCAT(N'[{"DetalleFacturaId":',@DetalleOtra,N',"Cantidad":1,"Reingresar":true}]');
UPDATE dbo.Producto SET Activo=0 WHERE ProductoId=@Producto;
BEGIN TRY
 BEGIN TRANSACTION;
 EXEC dbo.sp_ProcesarDevolucionCliente @Actor,@Otra,@Op,N'Rollback',@Json;
 THROW 54900,'Expected inactive product failure',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>54104 THROW; END CATCH;
IF @@TRANCOUNT<>0 OR EXISTS(SELECT 1 FROM dbo.DevolucionCliente WHERE OperacionId=@Op) OR EXISTS(SELECT 1 FROM dbo.Kardex_Inventario WHERE OperacionId=@Op) THROW 54900,'Partial rollback',1;
UPDATE dbo.Producto SET Activo=1 WHERE ProductoId=@Producto;
-- Successful caller transaction remains open and can roll back every side effect.
BEGIN TRANSACTION;
EXEC dbo.sp_ProcesarDevolucionCliente @Actor,@Otra,@Op,N'Caller rollback',@Json;
IF @@TRANCOUNT<>1 THROW 54900,'Committed caller transaction',1;
ROLLBACK;
IF EXISTS(SELECT 1 FROM dbo.DevolucionCliente WHERE OperacionId=@Op) THROW 54900,'Caller rollback failed',1;
-- RBAC in SQL and no direct application DML.
BEGIN TRY
 EXEC dbo.sp_ProcesarDevolucionCliente -1,@Otra,@Op,N'Unauthorized',@Json;
 THROW 54900,'Missing SQL RBAC',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>54101 THROW; END CATCH;
EXECUTE AS USER='securefinance_app';
IF HAS_PERMS_BY_NAME('dbo.NotaCredito','OBJECT','INSERT')<>0 OR HAS_PERMS_BY_NAME('dbo.Producto','OBJECT','UPDATE')<>0 THROW 54900,'Excess SQL grants',1;
REVERT;
-- Warranty transitions, optimistic concurrency and append-only diagnosis.
SET @Op=NEWID();
EXEC dbo.sp_CrearTicketGarantia @Actor,@Detalle,@Op,N'Falla tecnica';
DECLARE @Ticket INT=(SELECT TicketId FROM dbo.Ticket_Garantia WHERE OperacionId=@Op),@Version BINARY(8);
IF (SELECT Cobertura FROM dbo.Ticket_Garantia WHERE TicketId=@Ticket)<>'VIGENTE' THROW 54900,'Used current coverage',1;
EXEC dbo.sp_CrearTicketGarantia @Actor,@Detalle,@Op,N'Falla tecnica';
IF (SELECT COUNT(*) FROM dbo.Historial_Garantia WHERE TicketId=@Ticket)<>1 THROW 54900,'Duplicate ticket',1;
SELECT @Version=Version FROM dbo.Ticket_Garantia WHERE TicketId=@Ticket;
BEGIN TRY
 EXEC dbo.sp_ActualizarEstadoGarantia @Actor,@Ticket,@Version,'ENTREGADO',N'Invalid';
 THROW 54900,'Arbitrary transition accepted',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>54606 THROW; END CATCH;
EXEC dbo.sp_ActualizarEstadoGarantia @Actor,@Ticket,@Version,'EN_REVISION',N'Revision';
BEGIN TRY
 EXEC dbo.sp_ActualizarEstadoGarantia @Actor,@Ticket,@Version,'APROBADO',N'Stale';
 THROW 54900,'Lost update',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>54603 THROW; END CATCH;
SELECT @Version=Version FROM dbo.Ticket_Garantia WHERE TicketId=@Ticket;
EXEC dbo.sp_ActualizarEstadoGarantia @Actor,@Ticket,@Version,'EN_REVISION',N'Diagnostico adicional';
SELECT @Version=Version FROM dbo.Ticket_Garantia WHERE TicketId=@Ticket;
EXEC dbo.sp_ActualizarEstadoGarantia @Actor,@Ticket,@Version,'APROBADO',N'Falla de fabrica';
SELECT @Version=Version FROM dbo.Ticket_Garantia WHERE TicketId=@Ticket;
EXEC dbo.sp_ActualizarEstadoGarantia @Actor,@Ticket,@Version,'ENTREGADO',N'Entrega documentada';
IF (SELECT COUNT(*) FROM dbo.Historial_Garantia WHERE TicketId=@Ticket)<>5 OR (SELECT FechaResolucion FROM dbo.Ticket_Garantia WHERE TicketId=@Ticket) IS NULL THROW 54900,'History missing',1;
BEGIN TRY
 UPDATE dbo.Historial_Garantia SET Diagnostico=N'Overwrite' WHERE TicketId=@Ticket;
 THROW 54900,'Mutable history',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>54606 THROW; END CATCH;
-- Exercise every query under EXECUTE-only account.
EXECUTE AS USER='securefinance_app';
EXEC dbo.sp_Edward_ConsultarFactura @Actor,@Factura;
EXEC dbo.sp_Edward_ConsultarDevoluciones @Actor;
EXEC dbo.sp_Edward_ConsultarGarantias @Actor,@Ticket;
REVERT;
-- Historical VAT is taken from the invoice, not today's 12% function.
DECLARE @Historica INT,@HistoricoDetalle INT;
INSERT dbo.Factura(ClienteId,UsuarioId,Subtotal,DescuentoTotal,IVA,Total) VALUES(@Cliente,@Actor,30.03,3.00,1.89,28.92);
SET @Historica=CONVERT(INT,SCOPE_IDENTITY());
INSERT dbo.DetalleFactura(FacturaId,ProductoId,Cantidad,PrecioUnitario,Subtotal,DescuentoPorcentaje,DescuentoMonto)
VALUES(@Historica,@Producto,3,10.01,30.03,10,3.00);
SET @HistoricoDetalle=CONVERT(INT,SCOPE_IDENTITY());
-- Laboratory-only removal simulates a sale made before coverage snapshots existed.
DELETE dbo.CoberturaGarantiaVenta WHERE DetalleFacturaId=@HistoricoDetalle;
SET @Json=CONCAT(N'[{"DetalleFacturaId":',@HistoricoDetalle,N',"Cantidad":3,"Reingresar":false}]');
SET @Op=NEWID();
EXEC dbo.sp_ProcesarDevolucionCliente @Actor,@Historica,@Op,N'Historical tax',@Json;
IF NOT EXISTS(SELECT 1 FROM dbo.NotaCredito n JOIN dbo.DevolucionCliente d ON d.DevolucionId=n.DevolucionId WHERE d.OperacionId=@Op AND n.IVA=1.89 AND n.Total=28.92) THROW 54900,'Used current VAT',1;
SET @Op=NEWID();
EXEC dbo.sp_CrearTicketGarantia @Actor,@HistoricoDetalle,@Op,N'Unknown historical coverage';
SELECT @Ticket=TicketId,@Version=Version FROM dbo.Ticket_Garantia WHERE OperacionId=@Op;
IF (SELECT Cobertura FROM dbo.Ticket_Garantia WHERE TicketId=@Ticket)<>'NO_VERIFICADA' THROW 54900,'Invented historical coverage',1;
EXEC dbo.sp_ActualizarEstadoGarantia @Actor,@Ticket,@Version,'EN_REVISION',N'Review';
SELECT @Version=Version FROM dbo.Ticket_Garantia WHERE TicketId=@Ticket;
BEGIN TRY
 EXEC dbo.sp_ActualizarEstadoGarantia @Actor,@Ticket,@Version,'APROBADO',N'No evidence';
 THROW 54900,'Approved unknown coverage without evidence',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>54606 THROW; END CATCH;
EXEC dbo.sp_ActualizarEstadoGarantia @Actor,@Ticket,@Version,'RECHAZADO',N'No coverage evidence';
SELECT @Version=Version FROM dbo.Ticket_Garantia WHERE TicketId=@Ticket;
EXEC dbo.sp_ActualizarEstadoGarantia @Actor,@Ticket,@Version,'ENTREGADO',N'Returned to customer';
-- Multiple products in one document: one credit and exactly one ingress per apt line.
DECLARE @Producto2 INT=(SELECT TOP(1) ProductoId FROM dbo.Producto WHERE ProductoId<>@Producto AND Stock>=1 AND Activo=1 ORDER BY ProductoId);
IF @Producto2 IS NULL THROW 54900,'Missing second product fixture',1;
DECLARE @Multi dbo.TipoDetalleVentaDescuento,@FacturaMulti INT;
INSERT @Multi VALUES(@Producto,1,10),(@Producto2,1,0);
EXEC dbo.sp_ProcesarVentaTransaccional @Cliente,@Actor,@Multi,@FacturaMulti OUTPUT,N'Otro';
SET @Json=(SELECT DetalleFacturaId,Cantidad,CONVERT(BIT,1) Reingresar FROM dbo.DetalleFactura WHERE FacturaId=@FacturaMulti FOR JSON PATH);
SET @Op=NEWID();
EXEC dbo.sp_ProcesarDevolucionCliente @Actor,@FacturaMulti,@Op,N'Multiple lines',@Json;
IF (SELECT COUNT(*) FROM dbo.Kardex_Inventario WHERE OperacionId=@Op)<>2 THROW 54900,'Multi-line ingress failed',1;
IF (SELECT n.Total FROM dbo.NotaCredito n JOIN dbo.DevolucionCliente d ON d.DevolucionId=n.DevolucionId WHERE d.OperacionId=@Op)<>(SELECT Total FROM dbo.Factura WHERE FacturaId=@FacturaMulti) THROW 54900,'Multi-line VAT allocation failed',1;
PRINT 'PASS Edward SQL business tests';
