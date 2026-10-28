SET XACT_ABORT ON;
IF OBJECT_ID('dbo.sp_ConsultarAplicacionesNotaCredito','P') IS NULL OR OBJECT_ID('dbo.sp_RegistrarRecepcionCompra','P') IS NULL
 THROW 54800,'Requiere migraciones 33-35.',1;
IF DATABASE_PRINCIPAL_ID(N'securefinance_app') IS NULL OR IS_ROLEMEMBER('db_owner','securefinance_app')=1
 OR IS_ROLEMEMBER('db_datawriter','securefinance_app')=1 OR IS_ROLEMEMBER('db_datareader','securefinance_app')=1
 THROW 54800,'Requiere cuenta de aplicacion con privilegios minimos.',1;
BEGIN TRY
 BEGIN TRANSACTION;
 INSERT dbo.Permiso(Codigo,Descripcion)
 SELECT N'NOTAS_CREDITO_APLICAR',N'Registrar reembolsos externos documentados contra notas de credito'
 WHERE NOT EXISTS(SELECT 1 FROM dbo.Permiso WITH(UPDLOCK,HOLDLOCK) WHERE Codigo=N'NOTAS_CREDITO_APLICAR');
 -- No concede este permiso empresarial a roles automaticamente. Requiere asignacion explicita.
 GRANT EXECUTE ON dbo.sp_RegistrarRecepcionCompra TO securefinance_app;
 GRANT EXECUTE ON dbo.sp_ERP_RegistrarAjuste TO securefinance_app;
 -- La cadena de propiedad permite llamadas internas desde ventas/devoluciones/recepciones.
 -- La aplicacion ya no puede emitir COMPRA sin cabecera de recepcion.
 DENY EXECUTE ON dbo.sp_RegistrarMovimientoKardex TO securefinance_app;
 GRANT EXECUTE ON dbo.sp_ConsultarProductoProveedor TO securefinance_app;
 GRANT EXECUTE ON dbo.sp_AsociarProductoProveedor TO securefinance_app;
 GRANT EXECUTE ON dbo.sp_ERP_ConsultarKardex TO securefinance_app;
 GRANT EXECUTE ON dbo.sp_RegistrarAplicacionNotaCredito TO securefinance_app;
 GRANT EXECUTE ON dbo.sp_ConsultarAplicacionesNotaCredito TO securefinance_app;
 DENY SELECT,INSERT,UPDATE,DELETE ON dbo.ProductoProveedor TO securefinance_app;
 DENY SELECT,INSERT,UPDATE,DELETE ON dbo.RecepcionCompra TO securefinance_app;
 DENY SELECT,INSERT,UPDATE,DELETE ON dbo.DetalleRecepcionCompra TO securefinance_app;
 DENY SELECT,INSERT,UPDATE,DELETE ON dbo.AplicacionNotaCredito TO securefinance_app;
 COMMIT;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK;
 THROW;
END CATCH;
GO
