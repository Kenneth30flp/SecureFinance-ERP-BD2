USE [SecureFinanceERP];
GO
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'dbo.Bitacora_Transacciones', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Bitacora_Transacciones (
        BitacoraTransaccionId BIGINT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_Bitacora_Transacciones PRIMARY KEY,
        FechaHora DATETIME2(3) NOT NULL
            CONSTRAINT DF_BitacoraTransacciones_Fecha DEFAULT SYSUTCDATETIME(),
        TablaAfectada NVARCHAR(128) NOT NULL
            CONSTRAINT CK_BitacoraTransacciones_Tabla CHECK (LEN(LTRIM(RTRIM(TablaAfectada)) ) > 0),
        Operacion VARCHAR(20) NOT NULL
            CONSTRAINT CK_BitacoraTransacciones_Operacion CHECK (Operacion IN ('INSERT', 'UPDATE', 'DELETE')),
        UsuarioSQL NVARCHAR(128) NOT NULL
            CONSTRAINT DF_BitacoraTransacciones_UsuarioSQL DEFAULT SUSER_SNAME(),
        HostName NVARCHAR(128) NOT NULL
            CONSTRAINT DF_BitacoraTransacciones_Host DEFAULT HOST_NAME(),
        AppName NVARCHAR(128) NOT NULL
            CONSTRAINT DF_BitacoraTransacciones_App DEFAULT APP_NAME(),
        IdentificadorRegistro NVARCHAR(4000) NOT NULL,
        ValorAnterior NVARCHAR(MAX) NULL,
        ValorNuevo NVARCHAR(MAX) NULL,
        CONSTRAINT CK_BitacoraTransacciones_Registro CHECK (LEN(LTRIM(RTRIM(IdentificadorRegistro))) > 0)
    );

    CREATE INDEX IX_BitacoraTransacciones_Fecha ON dbo.Bitacora_Transacciones(FechaHora);
    CREATE INDEX IX_BitacoraTransacciones_Tabla ON dbo.Bitacora_Transacciones(TablaAfectada, FechaHora);
END;
GO

CREATE OR ALTER FUNCTION dbo.fn_CalcularIVA
(
    @Monto DECIMAL(18, 2)
)
RETURNS DECIMAL(18, 2)
AS
BEGIN
    RETURN CAST(@Monto * 0.12 AS DECIMAL(18,2));
END;
GO

CREATE OR ALTER FUNCTION dbo.fn_CalcularSubtotal
(
    @Cantidad DECIMAL(18, 2),
    @PrecioUnitario DECIMAL(18, 2)
)
RETURNS DECIMAL(18, 2)
AS
BEGIN
    RETURN CAST(@Cantidad * @PrecioUnitario AS DECIMAL(18, 2));
END;
GO

CREATE OR ALTER FUNCTION dbo.fn_ConsultarAuditoria
(
    @FechaInicial DATETIME2(3) = NULL,
    @FechaFinal DATETIME2(3) = NULL,
    @Tabla NVARCHAR(128) = NULL,
    @Operacion VARCHAR(20) = NULL
)
RETURNS TABLE
AS
RETURN
    SELECT
        bt.BitacoraTransaccionId,
        bt.FechaHora,
        bt.TablaAfectada,
        bt.Operacion,
        bt.UsuarioSQL,
        bt.HostName,
        bt.AppName,
        bt.IdentificadorRegistro,
        bt.ValorAnterior,
        bt.ValorNuevo
    FROM dbo.Bitacora_Transacciones AS bt
    WHERE (@FechaInicial IS NULL OR bt.FechaHora >= @FechaInicial)
      AND (@FechaFinal IS NULL OR bt.FechaHora <= @FechaFinal)
      AND (@Tabla IS NULL OR bt.TablaAfectada = @Tabla)
      AND (@Operacion IS NULL OR bt.Operacion = @Operacion);
GO

CREATE OR ALTER FUNCTION dbo.fn_ObtenerHistoricoVentas
(
    @FechaInicial DATETIME2(3) = NULL,
    @FechaFinal DATETIME2(3) = NULL,
    @Cliente NVARCHAR(150) = NULL
)
RETURNS TABLE
AS
RETURN
    SELECT f.FacturaId AS Factura, f.FechaHora AS Fecha,
           c.Nombre AS Cliente, u.NombreUsuario AS Usuario,
           f.Subtotal, f.IVA, f.Total
    FROM dbo.Factura AS f
    INNER JOIN dbo.Cliente AS c ON c.ClienteId = f.ClienteId
    INNER JOIN dbo.Usuario AS u ON u.UsuarioId = f.UsuarioId
    WHERE (@FechaInicial IS NULL OR f.FechaHora >= @FechaInicial)
      AND (@FechaFinal IS NULL OR f.FechaHora <= @FechaFinal)
      AND (@Cliente IS NULL OR CHARINDEX(@Cliente, c.Nombre) > 0);
GO

CREATE OR ALTER PROCEDURE dbo.sp_ConsultarHistoricoVentas
    @FechaInicial DATETIME2(3) = NULL,
    @FechaFinal DATETIME2(3) = NULL,
    @Cliente NVARCHAR(150) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Factura, Fecha, Cliente, Usuario, Subtotal, IVA, Total
    FROM dbo.fn_ObtenerHistoricoVentas(@FechaInicial, @FechaFinal, @Cliente)
    ORDER BY Fecha DESC, Factura DESC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ConsultarBitacoraAcceso
    @FechaInicial DATETIME2(3) = NULL,
    @FechaFinal DATETIME2(3) = NULL,
    @NombreUsuarioIntentado NVARCHAR(50) = NULL,
    @Resultado VARCHAR(30) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        ba.FechaHora,
        ba.NombreUsuarioIntentado,
        ba.Resultado,
        ba.HostName,
        ba.AppName,
        ba.UsuarioSQL,
        ba.IpConexionSQL
    FROM dbo.Bitacora_Acceso AS ba
    WHERE (@FechaInicial IS NULL OR ba.FechaHora >= @FechaInicial)
      AND (@FechaFinal IS NULL OR ba.FechaHora <= @FechaFinal)
      AND (@NombreUsuarioIntentado IS NULL OR ba.NombreUsuarioIntentado = @NombreUsuarioIntentado)
      AND (@Resultado IS NULL OR ba.Resultado = @Resultado)
    ORDER BY ba.FechaHora DESC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ConsultarAuditoriaTransacciones
    @FechaInicial DATETIME2(3) = NULL,
    @FechaFinal DATETIME2(3) = NULL,
    @Tabla NVARCHAR(128) = NULL,
    @Operacion VARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT *
    FROM dbo.fn_ConsultarAuditoria(@FechaInicial, @FechaFinal, @Tabla, @Operacion)
    ORDER BY FechaHora DESC;
END;
GO
