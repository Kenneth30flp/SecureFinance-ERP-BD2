-- Migration and new-install module. Read-only summary; repeatable and atomic.
USE [SecureFinanceERP];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
BEGIN TRY
    BEGIN TRANSACTION;
    EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.sp_ObtenerResumenDashboard @UsuarioId INT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE UsuarioId = @UsuarioId AND Activo = 1)
        THROW 52701, ''El usuario no existe o está inactivo.'', 1;
    -- Guatemala: UTC-6 sin cambio estacional. Las fechas persistidas siguen en UTC.
    DECLARE @Dia DATE = CONVERT(DATE, DATEADD(HOUR, -6, SYSUTCDATETIME()));
    DECLARE @Desde DATETIME2(3) = DATEADD(HOUR, 6, CONVERT(DATETIME2(3), @Dia)),
        @Hasta DATETIME2(3), @Ventas BIT = 0, @Auditoria BIT = 0;
    SET @Hasta = DATEADD(DAY, 1, @Desde);
    SELECT @Ventas = CONVERT(BIT, COALESCE(MAX(CASE WHEN p.Codigo IN
        (N''VENTAS_REGISTRAR'', N''AUDITORIA_CONSULTAR'') THEN 1 ELSE 0 END), 0)),
        @Auditoria = CONVERT(BIT, COALESCE(MAX(CASE WHEN p.Codigo = N''AUDITORIA_CONSULTAR'' THEN 1 ELSE 0 END), 0))
    FROM dbo.Usuario_Rol ur
    INNER JOIN dbo.Rol r ON r.RolId = ur.RolId AND r.Activo = 1
    INNER JOIN dbo.Rol_Permiso rp ON rp.RolId = r.RolId
    INNER JOIN dbo.Permiso p ON p.PermisoId = rp.PermisoId AND p.Activo = 1
    WHERE ur.UsuarioId = @UsuarioId;
    SELECT
        CASE WHEN @Ventas = 1 THEN CONVERT(VARCHAR(40),
            (SELECT COALESCE(SUM(Total), CONVERT(DECIMAL(38,2), 0)) FROM dbo.Factura
             WHERE FechaHora >= @Desde AND FechaHora < @Hasta)) END AS VentasDia,
        CASE WHEN @Ventas = 1 THEN CONVERT(VARCHAR(20),
            (SELECT COUNT_BIG(*) FROM dbo.Factura WHERE FechaHora >= @Desde AND FechaHora < @Hasta)) END AS FacturasDia,
        CASE WHEN @Ventas = 1 THEN CONVERT(VARCHAR(20),
            (SELECT COUNT_BIG(*) FROM dbo.Producto WHERE Activo = 1 AND Stock <= 5)) END AS ProductosStockBajo,
        CASE WHEN @Auditoria = 1 THEN CONVERT(VARCHAR(20),
            (SELECT COUNT_BIG(*) FROM dbo.Bitacora_Transacciones WHERE FechaHora >= @Desde AND FechaHora < @Hasta)) END AS EventosDMLDia,
        CONVERT(VARCHAR(10), @Dia, 23) AS FechaOperacion,
        (SELECT STRING_AGG(CONVERT(NVARCHAR(MAX), r.Nombre), N'', '') WITHIN GROUP (ORDER BY r.Nombre)
         FROM dbo.Usuario_Rol ur INNER JOIN dbo.Rol r ON r.RolId = ur.RolId AND r.Activo = 1
         WHERE ur.UsuarioId = @UsuarioId) AS RolesActuales;
END;';
    IF DATABASE_PRINCIPAL_ID(N'securefinance_app') IS NOT NULL
        GRANT EXECUTE ON OBJECT::dbo.sp_ObtenerResumenDashboard TO [securefinance_app];
    COMMIT TRANSACTION;
    PRINT N'OK: Dashboard summary installed.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
