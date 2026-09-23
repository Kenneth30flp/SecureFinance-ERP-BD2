USE [SecureFinanceERP];
GO
SET XACT_ABORT ON;
-- Instalación inicial, una sola vez después de 01-04. No reemplaza objetos.
-- Fechas UTC; precios sin IVA. El ingreso de caja representa la venta cobrada.
BEGIN TRY
    BEGIN TRANSACTION;
    CREATE TABLE dbo.Cliente (
        ClienteId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Cliente PRIMARY KEY,
        NIT NVARCHAR(25) NOT NULL CONSTRAINT UQ_Cliente_NIT UNIQUE,
        Nombre NVARCHAR(150) NOT NULL,
        Correo NVARCHAR(254) NULL,
        Telefono NVARCHAR(25) NULL,
        Activo BIT NOT NULL CONSTRAINT DF_Cliente_Activo DEFAULT (1),
        FechaCreacion DATETIME2(3) NOT NULL CONSTRAINT DF_Cliente_Fecha DEFAULT SYSUTCDATETIME(),
        CONSTRAINT CK_Cliente_NIT CHECK (LEN(LTRIM(RTRIM(NIT))) > 0),
        CONSTRAINT CK_Cliente_Nombre CHECK (LEN(LTRIM(RTRIM(Nombre))) > 0)
    );
    CREATE TABLE dbo.Producto (
        ProductoId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Producto PRIMARY KEY,
        Codigo NVARCHAR(40) NOT NULL CONSTRAINT UQ_Producto_Codigo UNIQUE,
        Descripcion NVARCHAR(200) NOT NULL,
        Precio DECIMAL(12,2) NOT NULL,
        Stock INT NOT NULL CONSTRAINT DF_Producto_Stock DEFAULT (0),
        Activo BIT NOT NULL CONSTRAINT DF_Producto_Activo DEFAULT (1),
        FechaCreacion DATETIME2(3) NOT NULL CONSTRAINT DF_Producto_Fecha DEFAULT SYSUTCDATETIME(),
        CONSTRAINT CK_Producto_Codigo CHECK (LEN(LTRIM(RTRIM(Codigo))) > 0),
        CONSTRAINT CK_Producto_Descripcion CHECK (LEN(LTRIM(RTRIM(Descripcion))) > 0),
        CONSTRAINT CK_Producto_Precio CHECK (Precio >= 0),
        CONSTRAINT CK_Producto_Stock CHECK (Stock >= 0)
    );
    CREATE TABLE dbo.Factura (
        FacturaId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Factura PRIMARY KEY,
        ClienteId INT NOT NULL CONSTRAINT FK_Factura_Cliente REFERENCES dbo.Cliente(ClienteId),
        UsuarioId INT NOT NULL CONSTRAINT FK_Factura_Usuario REFERENCES dbo.Usuario(UsuarioId),
        FechaHora DATETIME2(3) NOT NULL CONSTRAINT DF_Factura_Fecha DEFAULT SYSUTCDATETIME(),
        Subtotal DECIMAL(19,2) NOT NULL,
        IVA DECIMAL(19,2) NOT NULL,
        Total DECIMAL(19,2) NOT NULL,
        Estado VARCHAR(15) NOT NULL CONSTRAINT DF_Factura_Estado DEFAULT ('EMITIDA'),
        CONSTRAINT CK_Factura_Importes CHECK (Subtotal >= 0 AND IVA >= 0 AND Total = Subtotal + IVA),
        CONSTRAINT CK_Factura_Estado CHECK (Estado = 'EMITIDA')
    );
    CREATE INDEX IX_Factura_Cliente ON dbo.Factura(ClienteId, FechaHora);
    CREATE INDEX IX_Factura_Usuario ON dbo.Factura(UsuarioId);
    CREATE TABLE dbo.DetalleFactura (
        DetalleFacturaId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DetalleFactura PRIMARY KEY,
        FacturaId INT NOT NULL CONSTRAINT FK_DetalleFactura_Factura REFERENCES dbo.Factura(FacturaId),
        ProductoId INT NOT NULL CONSTRAINT FK_DetalleFactura_Producto REFERENCES dbo.Producto(ProductoId),
        Cantidad INT NOT NULL,
        PrecioUnitario DECIMAL(12,2) NOT NULL,
        Subtotal DECIMAL(19,2) NOT NULL,
        CONSTRAINT UQ_DetalleFactura_Producto UNIQUE (FacturaId, ProductoId),
        CONSTRAINT CK_DetalleFactura_Cantidad CHECK (Cantidad > 0),
        CONSTRAINT CK_DetalleFactura_Precio CHECK (PrecioUnitario >= 0),
        CONSTRAINT CK_DetalleFactura_Subtotal CHECK (Subtotal >= 0 AND Subtotal = PrecioUnitario * CONVERT(DECIMAL(10,0), Cantidad))
    );
    CREATE INDEX IX_DetalleFactura_Producto ON dbo.DetalleFactura(ProductoId);
    CREATE TABLE dbo.MovimientoCaja (
        MovimientoCajaId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_MovimientoCaja PRIMARY KEY,
        FacturaId INT NOT NULL CONSTRAINT UQ_MovimientoCaja_Factura UNIQUE
            CONSTRAINT FK_MovimientoCaja_Factura REFERENCES dbo.Factura(FacturaId),
        TipoMovimiento VARCHAR(10) NOT NULL CONSTRAINT DF_MovimientoCaja_Tipo DEFAULT ('INGRESO'),
        Monto DECIMAL(19,2) NOT NULL,
        FechaHora DATETIME2(3) NOT NULL CONSTRAINT DF_MovimientoCaja_Fecha DEFAULT SYSUTCDATETIME(),
        CONSTRAINT CK_MovimientoCaja_Tipo CHECK (TipoMovimiento = 'INGRESO'),
        CONSTRAINT CK_MovimientoCaja_Monto CHECK (Monto >= 0)
    );
    -- Sin PK/CHECK aquí: el SP devuelve errores de negocio precisos para duplicados/cantidades.
    CREATE TYPE dbo.TipoDetalleVenta AS TABLE (ProductoId INT NOT NULL, Cantidad INT NOT NULL);
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
