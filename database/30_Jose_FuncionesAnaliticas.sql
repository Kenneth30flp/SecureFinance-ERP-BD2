-- José / Analítica Parte II. Incremental y repetible; no modifica migraciones 15–26.
-- Todas las fechas recibidas por estas funciones son UTC y el valor monetario es DECIMAL.
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
IF DB_NAME() IN ('master','model','msdb','tempdb') THROW 56000, 'Seleccione la base de aplicación.', 1;
IF OBJECT_ID('dbo.Factura','U') IS NULL OR OBJECT_ID('dbo.DetalleFactura','U') IS NULL
   OR OBJECT_ID('dbo.Producto','U') IS NULL OR OBJECT_ID('dbo.Cliente','U') IS NULL
   OR OBJECT_ID('dbo.Proveedor','U') IS NULL
  THROW 56000, 'Requiere el esquema base y las migraciones de catálogos.', 1;

EXEC sys.sp_executesql N'
CREATE OR ALTER VIEW dbo.vw_JoseVentasHistoricas
AS
SELECT f.FacturaId, f.ClienteId, f.FechaHora, f.Total AS TotalFactura,
       f.ClienteNombreEmision, d.DetalleFacturaId, d.ProductoId,
       d.Cantidad, d.PrecioUnitario, d.DescuentoMonto, d.SubtotalNeto,
       p.Codigo AS SKU, p.Descripcion AS Producto
FROM dbo.Factura AS f
JOIN dbo.DetalleFactura AS d ON d.FacturaId = f.FacturaId
JOIN dbo.Producto AS p ON p.ProductoId = d.ProductoId
WHERE f.Estado = ''EMITIDA'';';
GO

EXEC sys.sp_executesql N'
CREATE OR ALTER FUNCTION dbo.fn_ProductosMasVendidos
(
  @DesdeUtc DATETIME2(3) = NULL,
  @HastaUtc DATETIME2(3) = NULL
)
RETURNS TABLE
AS
RETURN
(
  WITH agregados AS
  (
    SELECT ProductoId, SKU, Producto,
           SUM(CONVERT(BIGINT, Cantidad)) AS UnidadesVendidas,
           CONVERT(DECIMAL(19,2), SUM(CONVERT(DECIMAL(19,2), SubtotalNeto))) AS ImporteVendido,
           COUNT_BIG(DISTINCT FacturaId) AS NumeroFacturas
    FROM dbo.vw_JoseVentasHistoricas
    WHERE (@DesdeUtc IS NULL OR FechaHora >= @DesdeUtc)
      AND (@HastaUtc IS NULL OR FechaHora < @HastaUtc)
    GROUP BY ProductoId, SKU, Producto
  )
  SELECT ProductoId, SKU, Producto, UnidadesVendidas, ImporteVendido,
         NumeroFacturas,
         CONVERT(INT, ROW_NUMBER() OVER (ORDER BY UnidadesVendidas DESC, ImporteVendido DESC, ProductoId)) AS Ranking
  FROM agregados
);';
GO

EXEC sys.sp_executesql N'
CREATE OR ALTER FUNCTION dbo.fn_ProductosPorComprar
(
  @IncluirInactivos BIT = 1
)
RETURNS TABLE
AS
RETURN
(
  SELECT p.ProductoId, p.Codigo AS SKU, p.Descripcion AS Producto,
         p.ProveedorId, v.Nombre AS Proveedor, p.Stock, p.StockMinimo,
         p.PuntoReorden,
         CASE WHEN p.Stock < p.StockMinimo THEN p.StockMinimo - p.Stock ELSE 0 END AS Deficit,
         CASE WHEN p.PuntoReorden > p.Stock THEN p.PuntoReorden - p.Stock ELSE 0 END AS CantidadSugerida,
         CONVERT(bit, CASE WHEN p.Stock <= p.StockMinimo THEN 1 ELSE 0 END) AS BajoMinimo,
         CONVERT(bit, CASE WHEN p.Stock <= p.PuntoReorden THEN 1 ELSE 0 END) AS EnReorden,
         CONVERT(bit, CASE WHEN p.Activo = 1 AND p.Stock <= p.PuntoReorden THEN 1 ELSE 0 END) AS NecesitaCompra,
         CONVERT(varchar(24), CASE
           WHEN p.Activo = 0 THEN ''INACTIVO''
           WHEN v.ProveedorId IS NULL THEN ''PROVEEDOR_PENDIENTE''
           WHEN p.Stock <= p.StockMinimo THEN ''BAJO_MINIMO''
           WHEN p.Stock <= p.PuntoReorden THEN ''REORDEN''
           ELSE ''OK'' END) AS EstadoAbastecimiento,
         p.Activo
  FROM dbo.Producto AS p
  LEFT JOIN dbo.Proveedor AS v ON v.ProveedorId = p.ProveedorId
  WHERE @IncluirInactivos = 1 OR p.Activo = 1
);';
GO

EXEC sys.sp_executesql N'
CREATE OR ALTER FUNCTION dbo.fn_AnalisisClientesFrecuentes
(
  @DesdeUtc DATETIME2(3) = NULL,
  @HastaUtc DATETIME2(3) = NULL
)
RETURNS TABLE
AS
RETURN
(
  WITH compras AS
  (
    SELECT f.ClienteId,
           COALESCE(NULLIF(MAX(f.ClienteNombreEmision), N''''), MAX(c.Nombre)) AS NombreCliente,
           COUNT_BIG(*) AS NumeroCompras,
           CONVERT(DECIMAL(19,2), SUM(CONVERT(DECIMAL(19,2), f.Total))) AS TotalHistoricoComprado,
           MAX(f.FechaHora) AS UltimaFechaCompra,
           CONVERT(DECIMAL(19,2), AVG(CONVERT(DECIMAL(19,4), f.Total))) AS TicketPromedio
    FROM dbo.Factura AS f
    JOIN dbo.Cliente AS c ON c.ClienteId = f.ClienteId
    WHERE f.Estado = ''EMITIDA''
      AND (@DesdeUtc IS NULL OR f.FechaHora >= @DesdeUtc)
      AND (@HastaUtc IS NULL OR f.FechaHora < @HastaUtc)
    GROUP BY f.ClienteId
  )
  SELECT c.ClienteId, COALESCE(x.NombreCliente, c.Nombre) AS NombreCliente,
         COALESCE(x.NumeroCompras, CONVERT(BIGINT, 0)) AS NumeroCompras,
         COALESCE(x.TotalHistoricoComprado, CONVERT(DECIMAL(19,2), 0)) AS TotalHistoricoComprado,
         x.UltimaFechaCompra,
         COALESCE(x.TicketPromedio, CONVERT(DECIMAL(19,2), 0)) AS TicketPromedio,
         CONVERT(varchar(12), CASE
           WHEN x.NumeroCompras IS NULL THEN ''SIN_COMPRAS''
           WHEN x.NumeroCompras >= 12 THEN ''VIP''
           WHEN x.NumeroCompras >= 4 THEN ''FRECUENTE''
           ELSE ''OCASIONAL'' END) AS Clasificacion,
         c.Activo
  FROM dbo.Cliente AS c
  LEFT JOIN compras AS x ON x.ClienteId = c.ClienteId
);';
GO
