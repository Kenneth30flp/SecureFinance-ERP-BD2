USE [SecureFinanceERP];
GO
SET XACT_ABORT ON;
GO
-- La autenticacion se registra exclusivamente en Bitacora_Acceso.
DROP TRIGGER IF EXISTS dbo.tr_Usuario_Auditar_Update;
GO

CREATE OR ALTER TRIGGER dbo.tr_Producto_Auditar_Update
ON dbo.Producto
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.Bitacora_Transacciones
        (TablaAfectada, Operacion, UsuarioSQL, HostName, AppName,
         IdentificadorRegistro, ValorAnterior, ValorNuevo)
    SELECT N'Producto', 'UPDATE', SUSER_SNAME(), HOST_NAME(), APP_NAME(),
           CONVERT(NVARCHAR(4000), i.ProductoId),
           (SELECT d.ProductoId, d.Codigo, d.Descripcion, d.Precio, d.Stock, d.Activo FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
           (SELECT i.ProductoId, i.Codigo, i.Descripcion, i.Precio, i.Stock, i.Activo FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM inserted AS i INNER JOIN deleted AS d ON d.ProductoId = i.ProductoId
    WHERE d.Precio <> i.Precio OR d.Stock <> i.Stock;
END;
GO

CREATE OR ALTER TRIGGER dbo.tr_Producto_Auditar_Delete
ON dbo.Producto
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.Bitacora_Transacciones
        (TablaAfectada, Operacion, UsuarioSQL, HostName, AppName,
         IdentificadorRegistro, ValorAnterior, ValorNuevo)
    SELECT N'Producto', 'DELETE', SUSER_SNAME(), HOST_NAME(), APP_NAME(),
           CONVERT(NVARCHAR(4000), d.ProductoId),
           (SELECT d.ProductoId, d.Codigo, d.Descripcion, d.Precio, d.Stock, d.Activo FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
           NULL
    FROM deleted AS d;
END;
GO

CREATE OR ALTER TRIGGER dbo.tr_Factura_Auditar_Insert
ON dbo.Factura
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.Bitacora_Transacciones
        (TablaAfectada, Operacion, UsuarioSQL, HostName, AppName,
         IdentificadorRegistro, ValorAnterior, ValorNuevo)
    SELECT N'Factura', 'INSERT', SUSER_SNAME(), HOST_NAME(), APP_NAME(),
           CONVERT(NVARCHAR(4000), i.FacturaId),
           NULL,
           (SELECT i.FacturaId, i.ClienteId, i.UsuarioId, i.FechaHora, i.Subtotal, i.IVA, i.Total, i.Estado FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM inserted AS i;
END;
GO
