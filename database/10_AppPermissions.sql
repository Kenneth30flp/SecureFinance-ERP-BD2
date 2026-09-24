-- Referencia final de permisos mínimos. Ejecutar después de instalar todos los módulos.
-- Usar una cuenta administradora con visibilidad del login y permisos para crear usuarios/conceder permisos.
-- No crea logins de servidor ni contraseñas. Puede volver a ejecutarse.
USE [SecureFinanceERP];
GO
IF SUSER_ID(N'securefinance_app') IS NULL
BEGIN
    PRINT N'ADVERTENCIA: la base SecureFinanceERP fue instalada; los permisos de aplicación quedan pendientes porque no existe el login de servidor securefinance_app.';
    PRINT N'El administrador debe crear/configurar manualmente el login y después ejecutar database/10_AppPermissions.sql.';
END
ELSE
BEGIN
    IF DATABASE_PRINCIPAL_ID(N'securefinance_app') IS NULL
    BEGIN
        CREATE USER [securefinance_app] FOR LOGIN [securefinance_app];
    END;

    -- Autenticación: los procedimientos internos se ejecutan por la cadena de propiedad dbo.
    GRANT EXECUTE ON OBJECT::dbo.sp_Login TO [securefinance_app];
    GRANT EXECUTE ON OBJECT::dbo.sp_ObtenerPermisosUsuario TO [securefinance_app];

    -- Ventas y parámetro de tabla (TVP).
    GRANT EXECUTE ON OBJECT::dbo.sp_ListarClientes TO [securefinance_app];
    GRANT EXECUTE ON OBJECT::dbo.sp_ListarProductosDisponibles TO [securefinance_app];
    GRANT EXECUTE ON OBJECT::dbo.sp_ProcesarVentaTransaccional TO [securefinance_app];
    GRANT EXECUTE, REFERENCES ON TYPE::dbo.TipoDetalleVenta TO [securefinance_app];

    -- Consultas de auditoría e histórico de ventas.
    GRANT EXECUTE ON OBJECT::dbo.sp_ConsultarBitacoraAcceso TO [securefinance_app];
    GRANT EXECUTE ON OBJECT::dbo.sp_ConsultarAuditoriaTransacciones TO [securefinance_app];
    GRANT EXECUTE ON OBJECT::dbo.sp_ConsultarHistoricoVentas TO [securefinance_app];

    PRINT N'OK: permisos mínimos de autenticación, ventas, TVP y auditoría aplicados a securefinance_app.';
END;
GO
