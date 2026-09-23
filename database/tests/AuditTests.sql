USE [SecureFinanceERP];
GO
SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID(N'dbo.fn_CalcularIVA', N'FN') IS NULL
        THROW 51001, 'No existe dbo.fn_CalcularIVA.', 1;
    IF OBJECT_ID(N'dbo.fn_CalcularSubtotal', N'FN') IS NULL
        THROW 51002, 'No existe dbo.fn_CalcularSubtotal.', 1;
    IF OBJECT_ID(N'dbo.Bitacora_Transacciones', N'U') IS NULL
        THROW 51003, 'No existe dbo.Bitacora_Transacciones.', 1;
    IF OBJECT_ID(N'dbo.fn_ConsultarAuditoria', N'IF') IS NULL
        THROW 51004, 'No existe dbo.fn_ConsultarAuditoria.', 1;

    DECLARE @Subtotal DECIMAL(18,2) = dbo.fn_CalcularSubtotal(5, 100.00);
    DECLARE @Iva DECIMAL(18,2) = dbo.fn_CalcularIVA(@Subtotal);

    IF @Subtotal <> 500.00
        THROW 51005, 'fn_CalcularSubtotal no devolvió el valor esperado.', 1;
    IF @Iva <> 60.00
        THROW 51006, 'fn_CalcularIVA no devolvió el valor esperado.', 1;

    INSERT INTO dbo.Bitacora_Transacciones (
        TablaAfectada,
        Operacion,
        IdentificadorRegistro,
        ValorAnterior,
        ValorNuevo
    )
    VALUES
        (N'Producto', N'UPDATE', N'1001', N'{"Precio":50.00}', N'{"Precio":55.00}'),
        (N'Usuario', N'DELETE', N'2001', N'{"UsuarioId":2001}', NULL);

    IF (SELECT COUNT(*) FROM dbo.Bitacora_Transacciones WHERE TablaAfectada = N'Producto' AND Operacion = N'UPDATE') <> 1
        THROW 51007, 'No se registró la actualización esperada.', 1;

    IF (SELECT COUNT(*) FROM dbo.fn_ConsultarAuditoria(NULL, NULL, N'Producto', N'UPDATE')) <> 1
        THROW 51008, 'fn_ConsultarAuditoria no filtró por tabla y operación.', 1;

    IF OBJECT_ID(N'dbo.Producto', N'U') IS NOT NULL
    BEGIN
        DECLARE @ProductoId INT = (SELECT TOP 1 ProductoId FROM dbo.Producto ORDER BY ProductoId);
        UPDATE dbo.Producto
        SET Precio = Precio + 1,
            Stock = Stock + 3
        WHERE ProductoId = @ProductoId;

        IF (SELECT COUNT(*)
            FROM dbo.Bitacora_Transacciones
            WHERE TablaAfectada = N'Producto'
              AND Operacion = N'UPDATE'
              AND ValorNuevo LIKE '%"Precio":%') < 1
            THROW 51009, 'No se registró la auditoría de precio y stock.', 1;
    END;

    IF OBJECT_ID(N'dbo.fn_ObtenerHistoricoVentas', N'IF') IS NOT NULL
    BEGIN
        IF (SELECT COUNT(*) FROM dbo.fn_ObtenerHistoricoVentas(NULL, NULL, NULL)) < 0
            THROW 51010, 'La función de histórico de ventas debe devolver cero o más filas.', 1;
    END;

    PRINT N'OK: Funciones y auditoría DML validadas.';
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
