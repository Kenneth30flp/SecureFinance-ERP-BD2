:ON ERROR EXIT
SET NOCOUNT ON; SET XACT_ABORT ON; SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON;
SET ANSI_WARNINGS ON; SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET NUMERIC_ROUNDABORT OFF;
IF DB_NAME()<>'SecureFinanceERP_Estabilizacion_20261021' THROW 54900,'Solo laboratorio.',1;
DECLARE @Actor INT=(SELECT UsuarioId FROM dbo.Usuario WHERE NombreUsuario='admin'),@P INT=(SELECT ProductoId FROM dbo.Producto WHERE Codigo='DEMO-CABLE'),@V INT=(SELECT MIN(ProveedorId) FROM dbo.Proveedor WHERE Activo=1),@Op UNIQUEIDENTIFIER=NEWID();
EXECUTE AS USER='securefinance_app';
EXEC dbo.sp_RegistrarRecepcionCompra @Actor,@P,@V,1,N'LAB-SNAPSHOT-PROVEEDOR',N'QA identidad al emitir',@Op;
REVERT;
IF NOT EXISTS(SELECT 1 FROM dbo.RecepcionCompra r JOIN dbo.Proveedor v ON v.ProveedorId=r.ProveedorId WHERE r.OperacionId=@Op AND r.ProveedorNombreEmision=v.Nombre AND r.ProveedorNITEmision=v.NIT) THROW 54900,'Snapshot de proveedor ausente.',1;
BEGIN TRY
 UPDATE dbo.RecepcionCompra SET DocumentoRespaldo=N'ALTERADO' WHERE OperacionId=@Op;
 THROW 54900,'Recepcion modificable.',1;
END TRY BEGIN CATCH IF ERROR_NUMBER()<>54805 THROW; END CATCH;
PRINT 'PASS proveedor historico capturado y recepcion inmutable';
SELECT ProductoId,Stock,ProveedorId INTO #ProductosAntes FROM dbo.Producto;
SELECT NotaCreditoId,Total,Estado,EstadoCredito INTO #NotasAntes FROM dbo.NotaCredito;
SELECT COUNT_BIG(*) N INTO #KardexAntes FROM dbo.Kardex_Inventario;
SELECT COUNT_BIG(*) N INTO #AplicacionesAntes FROM dbo.AplicacionNotaCredito;
GO
:r database/33_ERP_ProductoProveedor.sql
:r database/34_ERP_RecepcionesCompra.sql
:r database/35_ERP_AplicacionesNotaCredito.sql
:r database/36_ERP_PermisosIntegracion.sql
:r database/37_ERP_VentaIdempotente.sql
IF EXISTS(SELECT ProductoId,Stock,ProveedorId FROM dbo.Producto EXCEPT SELECT * FROM #ProductosAntes)
 OR EXISTS(SELECT * FROM #ProductosAntes EXCEPT SELECT ProductoId,Stock,ProveedorId FROM dbo.Producto)
 THROW 54900,'Repeticion cambia productos.',1;
IF EXISTS(SELECT NotaCreditoId,Total,Estado,EstadoCredito FROM dbo.NotaCredito EXCEPT SELECT * FROM #NotasAntes)
 OR EXISTS(SELECT * FROM #NotasAntes EXCEPT SELECT NotaCreditoId,Total,Estado,EstadoCredito FROM dbo.NotaCredito)
 THROW 54900,'Repeticion cambia notas historicas.',1;
IF (SELECT COUNT_BIG(*) FROM dbo.Kardex_Inventario)<>(SELECT N FROM #KardexAntes)
 OR (SELECT COUNT_BIG(*) FROM dbo.AplicacionNotaCredito)<>(SELECT N FROM #AplicacionesAntes)
 THROW 54900,'Repeticion cambia libros.',1;
PRINT 'PASS migraciones 33-37 repetibles: productos notas Kardex y aplicaciones preservados';
DBCC CHECKCONSTRAINTS WITH ALL_CONSTRAINTS;
DBCC CHECKDB WITH NO_INFOMSGS;
PRINT 'PASS integridad final DBCC';
