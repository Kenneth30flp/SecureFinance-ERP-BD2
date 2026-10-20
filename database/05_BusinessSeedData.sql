USE [SecureFinanceERP];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
-- No sample business records unless explicitly enabled in this SQL session.
IF COALESCE(TRY_CONVERT(BIT, SESSION_CONTEXT(N'SecureFinance.AllowAcademicSeed')),0) <> 1
BEGIN
    PRINT N'SKIP: academic business seed not enabled.';
    RETURN;
END;
-- Never seed a database with issued invoices, even with an opt-in flag.
IF EXISTS (SELECT 1 FROM dbo.Factura)
    THROW 54950, 'Academic seed is blocked on databases with invoices.', 1;
IF OBJECT_ID(N'dbo.Kardex_Inventario',N'U') IS NOT NULL
    EXEC sys.sp_executesql N'IF EXISTS(SELECT 1 FROM dbo.Kardex_Inventario) THROW 54950, ''Academic seed is blocked on databases with Kardex.'', 1;';
-- Ficticios. Reejecutar no repone stock ni cambia precios/estados existentes.
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT dbo.Cliente (NIT, Nombre, Correo, Telefono)
    SELECT s.NIT, s.Nombre, s.Correo, s.Telefono
    FROM (VALUES
        (N'DEMO-001', N'Comercial Aurora DEMO', N'aurora@example.invalid', N'5550-0101'),
        (N'DEMO-002', N'Librería Horizonte DEMO', N'horizonte@example.invalid', N'5550-0102'),
        (N'CF-DEMO', N'Consumidor final DEMO', NULL, NULL)
    ) s(NIT, Nombre, Correo, Telefono)
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Cliente WITH (UPDLOCK, HOLDLOCK) WHERE NIT = s.NIT);
    INSERT dbo.Producto (Codigo, Descripcion, Precio, Stock)
    SELECT s.Codigo, s.Descripcion, s.Precio, s.Stock
    FROM (VALUES
        (N'DEMO-TECLADO', N'Teclado USB', CONVERT(DECIMAL(12,2), 125.50), 50),
        (N'DEMO-MOUSE', N'Mouse óptico', CONVERT(DECIMAL(12,2), 75.25), 80),
        (N'DEMO-MONITOR', N'Monitor 24 pulgadas', CONVERT(DECIMAL(12,2), 1450.00), 20),
        (N'DEMO-CABLE', N'Cable HDMI', CONVERT(DECIMAL(12,2), 35.90), 100)
    ) s(Codigo, Descripcion, Precio, Stock)
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Producto WITH (UPDLOCK, HOLDLOCK) WHERE Codigo = s.Codigo);
    COMMIT TRANSACTION;
    PRINT N'OK: semillas de negocio disponibles; datos existentes conservados.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
