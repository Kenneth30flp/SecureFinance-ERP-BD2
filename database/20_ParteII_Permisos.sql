SET NOCOUNT ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
SET XACT_ABORT ON;
BEGIN TRY
 BEGIN TRANSACTION;
 INSERT dbo.Permiso(Codigo,Descripcion)
 SELECT s.Codigo,N'Parte II Kenneth: '+s.Codigo FROM (VALUES (N'INVENTARIO_CONSULTAR'),(N'INVENTARIO_REGISTRAR'),(N'INVENTARIO_AJUSTAR'),(N'PRODUCTOS_CONSULTAR'),(N'PRODUCTOS_ADMINISTRAR'),(N'PROVEEDORES_CONSULTAR'),(N'PROVEEDORES_ADMINISTRAR'),(N'CLIENTES_CONSULTAR'),(N'CLIENTES_ACTUALIZAR_NIT'),(N'CLIENTES_INACTIVAR')) s(Codigo)
 WHERE NOT EXISTS(SELECT 1 FROM dbo.Permiso WITH(UPDLOCK,HOLDLOCK) WHERE Codigo=s.Codigo);
 -- No asigna roles ni reactiva permisos existentes. Asignacion explicita por administrador.
 IF DATABASE_PRINCIPAL_ID(N'securefinance_app') IS NULL THROW 54301, 'Configure el usuario SQL dedicado antes de otorgar permisos.', 1;
 IF IS_ROLEMEMBER('db_owner','securefinance_app')=1 OR IS_ROLEMEMBER('db_datareader','securefinance_app')=1 OR IS_ROLEMEMBER('db_datawriter','securefinance_app')=1 THROW 54301, 'La cuenta de aplicacion tiene roles amplios; revisar antes de continuar.', 1;
 DECLARE @LoginAplicacion SYSNAME=(SELECT SUSER_SNAME(sid) FROM sys.database_principals WHERE name=N'securefinance_app');
 IF @LoginAplicacion IS NOT NULL AND IS_SRVROLEMEMBER(N'sysadmin',@LoginAplicacion)=1 THROW 54301,'El login de aplicacion no puede ser sysadmin.',1;
 GRANT EXECUTE ON OBJECT::dbo.sp_RegistrarProveedor TO securefinance_app;
 GRANT EXECUTE ON OBJECT::dbo.sp_ActualizarProveedor TO securefinance_app;
 GRANT EXECUTE ON OBJECT::dbo.sp_RegistrarProducto TO securefinance_app;
 GRANT EXECUTE ON OBJECT::dbo.sp_ActualizarProducto TO securefinance_app;
 GRANT EXECUTE ON OBJECT::dbo.sp_ActualizarNitCliente TO securefinance_app;
 GRANT EXECUTE ON OBJECT::dbo.sp_InactivarCliente TO securefinance_app;
 GRANT EXECUTE ON OBJECT::dbo.sp_RegistrarMovimientoKardex TO securefinance_app;
 GRANT EXECUTE ON OBJECT::dbo.sp_ConsultarProveedores TO securefinance_app;
 GRANT EXECUTE ON OBJECT::dbo.sp_ConsultarProductos TO securefinance_app;
 GRANT EXECUTE ON OBJECT::dbo.sp_ConsultarClientesAdministracion TO securefinance_app;
 GRANT EXECUTE ON OBJECT::dbo.sp_ConsultarKardex TO securefinance_app;
 DENY SELECT,INSERT,UPDATE,DELETE ON OBJECT::dbo.Proveedor TO securefinance_app;
 DENY SELECT,INSERT,UPDATE,DELETE ON OBJECT::dbo.Producto TO securefinance_app;
 DENY SELECT,INSERT,UPDATE,DELETE ON OBJECT::dbo.Cliente TO securefinance_app;
 DENY SELECT,INSERT,UPDATE,DELETE ON OBJECT::dbo.Kardex_Inventario TO securefinance_app;
 DENY SELECT,INSERT,UPDATE,DELETE ON OBJECT::dbo.ConfiguracionInventario TO securefinance_app;
 DENY SELECT,INSERT,UPDATE,DELETE ON OBJECT::dbo.Bitacora_Transacciones TO securefinance_app;
 DENY EXECUTE ON OBJECT::dbo.sp_ParteII_ValidarPermiso TO securefinance_app;
 -- Las concesiones de columna pueden prevalecer sobre DENY de tabla.
 EXECUTE AS USER=N'securefinance_app';
 DECLARE @StockDirecto INT=HAS_PERMS_BY_NAME(N'dbo.Producto',N'OBJECT',N'UPDATE',N'Stock',N'COLUMN');
 REVERT;
 IF @StockDirecto=1 THROW 54301,'Existe una concesion directa o heredada sobre Stock; revocarla antes de aplicar.',1;
 COMMIT TRANSACTION;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 THROW;
END CATCH;
GO
