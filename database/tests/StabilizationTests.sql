SET NOCOUNT ON; SET XACT_ABORT ON; SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON;
SET ANSI_WARNINGS ON; SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET NUMERIC_ROUNDABORT OFF;
IF DB_NAME()<>'SecureFinanceERP_Estabilizacion_20261021' THROW 54900,'Solo laboratorio restaurado autorizado.',1;
DECLARE @Actor INT=(SELECT TOP(1) u.UsuarioId FROM dbo.Usuario u JOIN dbo.Usuario_Rol ur ON ur.UsuarioId=u.UsuarioId JOIN dbo.Rol r ON r.RolId=ur.RolId WHERE r.Nombre=N'Administrador' AND u.Activo=1),
 @Rol INT=(SELECT RolId FROM dbo.Rol WHERE Nombre=N'Administrador'),
 @P INT=(SELECT ProductoId FROM dbo.Producto WHERE Codigo='DEMO-CABLE'),
 @A INT=(SELECT MIN(ProveedorId) FROM dbo.Proveedor WHERE Activo=1),
 @B INT=(SELECT MAX(ProveedorId) FROM dbo.Proveedor WHERE Activo=1),
 @C INT=(SELECT TOP(1) ClienteId FROM dbo.Cliente WHERE Activo=1);
IF @Actor IS NULL OR @P IS NULL OR @A=@B THROW 54900,'Precondiciones de laboratorio ausentes.',1;
INSERT dbo.Rol_Permiso(RolId,PermisoId) SELECT @Rol,p.PermisoId FROM dbo.Permiso p
WHERE NOT EXISTS(SELECT 1 FROM dbo.Rol_Permiso rp WHERE rp.RolId=@Rol AND rp.PermisoId=p.PermisoId);
IF (SELECT Stock FROM dbo.Producto WHERE ProductoId=@P)<>90 THROW 54900,'Requiere HDMI original con stock 90; no repetir escenarios destructivamente.',1;
DECLARE @Op UNIQUEIDENTIFIER=NEWID(),@Count INT=(SELECT COUNT(*) FROM dbo.Kardex_Inventario WHERE ProductoId=@P);
EXECUTE AS USER='securefinance_app';
EXEC dbo.sp_RegistrarRecepcionCompra @Actor,@P,@A,10,N'LAB-COMPRA-A',N'Prueba aislada 90 + 10',@Op;
EXEC dbo.sp_RegistrarRecepcionCompra @Actor,@P,@A,10,N'LAB-COMPRA-A',N'Prueba aislada 90 + 10',@Op;
REVERT;
IF (SELECT Stock FROM dbo.Producto WHERE ProductoId=@P)<>100 OR (SELECT COUNT(*) FROM dbo.Kardex_Inventario WHERE ProductoId=@P)<>@Count+1 THROW 54900,'A/B fallo stock o idempotencia.',1;
PRINT 'PASS A/B HDMI 90 + 10 = 100; reintento un solo Kardex';
SET @Op=NEWID();
EXEC dbo.sp_RegistrarRecepcionCompra @Actor,@P,@B,15,N'LAB-COMPRA-B',N'Mismo SKU proveedor alternativo',@Op;
IF (SELECT Stock FROM dbo.Producto WHERE ProductoId=@P)<>115 OR (SELECT COUNT(DISTINCT r.ProveedorId) FROM dbo.RecepcionCompra r JOIN dbo.DetalleRecepcionCompra d ON d.RecepcionId=r.RecepcionId WHERE d.ProductoId=@P)<>2 THROW 54900,'C fallo multiples proveedores.',1;
PRINT 'PASS C dos proveedores mismo ProductoId; stock 115';
-- Falla dentro del mecanismo central, despues de insertar cabecera de recepcion.
DECLARE @Huge INT=2147483647; SET @Op=NEWID();
BEGIN TRY
 EXEC dbo.sp_RegistrarRecepcionCompra @Actor,@P,@A,@Huge,N'LAB-ROLLBACK',N'Overflow comprobado',@Op;
 THROW 54900,'D esperaba rechazo.',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>54113 THROW; END CATCH;
IF EXISTS(SELECT 1 FROM dbo.RecepcionCompra WHERE OperacionId=@Op) OR EXISTS(SELECT 1 FROM dbo.Kardex_Inventario WHERE OperacionId=@Op) OR (SELECT Stock FROM dbo.Producto WHERE ProductoId=@P)<>115 THROW 54900,'D rollback incompleto.',1;
PRINT 'PASS D rollback cabecera detalle Kardex stock';
BEGIN TRY
 EXEC dbo.sp_RegistrarRecepcionCompra -1,@P,@A,1,N'LAB-SIN-PERMISO',N'Prueba denegada',@Op;
 THROW 54900,'E esperaba rechazo.',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>54101 THROW; END CATCH;
PRINT 'PASS E actor sin permiso rechazado';
DECLARE @Venta dbo.TipoDetalleVentaDescuento,@F INT; INSERT @Venta VALUES(@P,2,0);
EXEC dbo.sp_ProcesarVentaTransaccional @C,@Actor,@Venta,@F OUTPUT;
IF (SELECT Stock FROM dbo.Producto WHERE ProductoId=@P)<>113 OR NOT EXISTS(SELECT 1 FROM dbo.Kardex_Inventario k JOIN dbo.DetalleFactura d ON d.DetalleFacturaId=k.DetalleFacturaId WHERE d.FacturaId=@F AND k.TipoMovimiento='VENTA' AND k.Cantidad=2) THROW 54900,'M venta sin Kardex coherente.',1;
PRINT 'PASS M venta real dos unidades un egreso Kardex';
DECLARE @D INT=(SELECT DetalleFacturaId FROM dbo.DetalleFactura WHERE FacturaId=@F),@Json NVARCHAR(MAX);
SET @Op=NEWID(); SET @Json=CONCAT(N'[{"DetalleFacturaId":',@D,N',"Cantidad":1,"Reingresar":true}]');
EXEC dbo.sp_ProcesarDevolucionCliente @Actor,@F,@Op,N'Prueba devolucion parcial aislada',@Json;
EXEC dbo.sp_ProcesarDevolucionCliente @Actor,@F,@Op,N'Prueba devolucion parcial aislada',@Json;
DECLARE @NC INT=(SELECT n.NotaCreditoId FROM dbo.NotaCredito n JOIN dbo.DevolucionCliente d ON d.DevolucionId=n.DevolucionId WHERE d.OperacionId=@Op),@Total DECIMAL(19,2),@Half DECIMAL(19,2),@Final DECIMAL(19,2);
SELECT @Total=Total FROM dbo.NotaCredito WHERE NotaCreditoId=@NC;
IF (SELECT Stock FROM dbo.Producto WHERE ProductoId=@P)<>114 OR (SELECT COUNT(*) FROM dbo.NotaCredito WHERE NotaCreditoId=@NC)<>1 OR (SELECT COUNT(*) FROM dbo.Kardex_Inventario WHERE OperacionId=@Op)<>1 THROW 54900,'F/G devolucion duplicada.',1;
PRINT 'PASS F/G devolucion parcial; credito y reingreso unicos';
SET @Op=NEWID(); SET @Half=ROUND(@Total/2,2); SET @Final=@Total-@Half;
EXECUTE AS USER='securefinance_app';
EXEC dbo.sp_RegistrarAplicacionNotaCredito @Actor,@NC,@Half,N'LAB-COMPROBANTE-EXTERNO-PARCIAL',@Op;
EXEC dbo.sp_RegistrarAplicacionNotaCredito @Actor,@NC,@Half,N'LAB-COMPROBANTE-EXTERNO-PARCIAL',@Op;
REVERT;
IF (SELECT EstadoCredito FROM dbo.NotaCredito WHERE NotaCreditoId=@NC)<>'PARCIAL' OR (SELECT COUNT(*) FROM dbo.AplicacionNotaCredito WHERE NotaCreditoId=@NC)<>1 THROW 54900,'H fallo parcial o idempotencia.',1;
PRINT 'PASS H aplicacion parcial idempotente';
SET @Op=NEWID();
BEGIN TRY
 EXEC dbo.sp_RegistrarAplicacionNotaCredito @Actor,@NC,@Total,N'LAB-EXCESO',@Op;
 THROW 54900,'J esperaba rechazo.',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>54804 THROW; END CATCH;
PRINT 'PASS J saldo excedido rechazado';
EXEC dbo.sp_RegistrarAplicacionNotaCredito @Actor,@NC,@Final,N'LAB-COMPROBANTE-EXTERNO-FINAL',@Op;
IF (SELECT EstadoCredito FROM dbo.NotaCredito WHERE NotaCreditoId=@NC)<>'LIQUIDADA' OR @Total<>(SELECT SUM(Monto) FROM dbo.AplicacionNotaCredito WHERE NotaCreditoId=@NC) THROW 54900,'I liquidacion inconsistente.',1;
PRINT 'PASS I credito liquidado saldo cero';
SET @Op=NEWID();
EXEC dbo.sp_CrearTicketGarantia @Actor,@D,@Op,N'Escenario QA aislado vinculado a venta real del laboratorio';
DECLARE @T INT=(SELECT TicketId FROM dbo.Ticket_Garantia WHERE OperacionId=@Op),@V BINARY(8);
SELECT @V=Version FROM dbo.Ticket_Garantia WHERE TicketId=@T;
EXEC dbo.sp_ActualizarEstadoGarantia @Actor,@T,@V,'EN_REVISION',N'Diagnostico QA aislado';
IF (SELECT COUNT(*) FROM dbo.Historial_Garantia WHERE TicketId=@T)<>2 OR (SELECT Stock FROM dbo.Producto WHERE ProductoId=@P)<>114 THROW 54900,'K historial o stock incorrecto.',1;
PRINT 'PASS K garantia con historial, sin ingreso de stock';
SELECT @V=Version FROM dbo.Ticket_Garantia WHERE TicketId=@T;
BEGIN TRY
 EXEC dbo.sp_ActualizarEstadoGarantia @Actor,@T,@V,'ENTREGADO',N'Salto invalido';
 THROW 54900,'L esperaba rechazo.',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>54606 THROW; END CATCH;
PRINT 'PASS L transicion invalida rechazada';
-- Cliente de la venta conserva sus referencias e importes al inactivarse.
DECLARE @CV BINARY(8)=(SELECT Version FROM dbo.Cliente WHERE ClienteId=@C),@Ftotal DECIMAL(19,2)=(SELECT Total FROM dbo.Factura WHERE FacturaId=@F);
EXEC dbo.sp_InactivarCliente @C,@Actor,@CV,N'QA aislado preservacion historial';
IF NOT EXISTS(SELECT 1 FROM dbo.Factura WHERE FacturaId=@F AND ClienteId=@C AND Total=@Ftotal) THROW 54900,'N historial alterado.',1;
PRINT 'PASS N cliente inactivo factura intacta';
DBCC CHECKCONSTRAINTS WITH ALL_CONSTRAINTS;
DBCC CHECKDB WITH NO_INFOMSGS;
SELECT @P ProductoId,Stock FROM dbo.Producto WHERE ProductoId=@P;
