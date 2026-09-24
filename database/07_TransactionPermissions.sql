USE [SecureFinanceERP];
GO
-- Kenneth ejecuta manualmente con su cuenta administradora, después de 05 y 06.
-- Requiere el usuario securefinance_app ya creado; no crea cuentas ni credenciales.
GRANT EXECUTE ON OBJECT::dbo.sp_ListarClientes TO securefinance_app;
GRANT EXECUTE ON OBJECT::dbo.sp_ListarProductosDisponibles TO securefinance_app;
GRANT EXECUTE ON OBJECT::dbo.sp_ProcesarVentaTransaccional TO securefinance_app;
GRANT EXECUTE, REFERENCES ON TYPE::dbo.TipoDetalleVenta TO securefinance_app;
GO
