SET NOCOUNT ON; SET XACT_ABORT ON; SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON;
SET ANSI_WARNINGS ON; SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET NUMERIC_ROUNDABORT OFF;
IF DB_NAME()<>'SecureFinanceERP_Estabilizacion_20261021' THROW 54900,'Solo laboratorio.',1;
DECLARE @Actor INT=(SELECT UsuarioId FROM dbo.Usuario WHERE NombreUsuario='admin'),@P INT=(SELECT ProductoId FROM dbo.Producto WHERE Codigo='DEMO-CABLE'),
 @C INT=(SELECT TOP(1) ClienteId FROM dbo.Cliente WHERE Activo=1),@V INT=(SELECT MIN(ProveedorId) FROM dbo.Proveedor WHERE Activo=1),@Op UNIQUEIDENTIFIER=NEWID();
-- Estado inactivo temporal en la copia. El rechazo revierte tambien esta preparacion.
BEGIN TRY
 BEGIN TRANSACTION;
 UPDATE dbo.Proveedor SET Activo=0 WHERE ProveedorId=@V;
 EXEC dbo.sp_RegistrarRecepcionCompra @Actor,@P,@V,1,N'LAB-INACTIVO',N'QA proveedor inactivo',@Op;
 THROW 54900,'Proveedor inactivo admitido.',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>54104 THROW; END CATCH;
IF EXISTS(SELECT 1 FROM dbo.RecepcionCompra WHERE OperacionId=@Op) THROW 54900,'Recepcion inactiva persistida.',1;
PRINT 'PASS proveedor inactivo rechazado, historicos preservados';
DECLARE @D dbo.TipoDetalleVentaDescuento,@F INT; INSERT @D VALUES(@P,1,100);
EXEC dbo.sp_ProcesarVentaTransaccional @C,@Actor,@D,@F OUTPUT,N'Otro';
DECLARE @Detalle INT=(SELECT DetalleFacturaId FROM dbo.DetalleFactura WHERE FacturaId=@F),@Json NVARCHAR(MAX);
SET @Op=NEWID();SET @Json=CONCAT(N'[{"DetalleFacturaId":',@Detalle,N',"Cantidad":1,"Reingresar":false}]');
EXEC dbo.sp_ProcesarDevolucionCliente @Actor,@F,@Op,N'QA devolucion de venta con descuento 100%',@Json;
IF NOT EXISTS(SELECT 1 FROM dbo.NotaCredito n JOIN dbo.DevolucionCliente d ON d.DevolucionId=n.DevolucionId WHERE d.OperacionId=@Op AND n.Total=0 AND n.EstadoCredito='LIQUIDADA') THROW 54900,'Nota cero bloqueada pendiente.',1;
PRINT 'PASS nota de importe cero emitida y liquidada sin inventar aplicaciones';
EXECUTE AS USER='securefinance_app';
BEGIN TRY
 UPDATE dbo.Producto SET Stock=Stock+1 WHERE ProductoId=@P;
 THROW 54900,'DML directo permitido.',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>229 THROW; END CATCH;
REVERT;
PRINT 'PASS aplicacion sin DML directo de stock';
DBCC CHECKCONSTRAINTS WITH ALL_CONSTRAINTS;
