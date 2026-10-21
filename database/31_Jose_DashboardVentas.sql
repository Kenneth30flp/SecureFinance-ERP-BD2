-- Dashboard ejecutivo: requiere 15-26 y 30. Garantias reales de Edward.
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
IF DB_NAME() IN ('master','model','msdb','tempdb') THROW 56010, 'Seleccione la base de aplicación.', 1;
IF OBJECT_ID('dbo.Ticket_Garantia','U') IS NULL
   OR OBJECT_ID('dbo.fn_ProductosMasVendidos','IF') IS NULL
   OR OBJECT_ID('dbo.fn_ProductosPorComprar','IF') IS NULL
   OR OBJECT_ID('dbo.fn_AnalisisClientesFrecuentes','IF') IS NULL
  THROW 56010, 'Requiere las migraciones 24-26 y la migración 30.', 1;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Factura') AND name = 'IX_Factura_JoseAnalitica_Fecha')
  CREATE INDEX IX_Factura_JoseAnalitica_Fecha ON dbo.Factura(FechaHora, FacturaId)
    INCLUDE (ClienteId, Total, Estado, ClienteNombreEmision);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.DetalleFactura') AND name = 'IX_DetalleFactura_JoseAnalitica_Factura')
  CREATE INDEX IX_DetalleFactura_JoseAnalitica_Factura ON dbo.DetalleFactura(FacturaId, ProductoId)
    INCLUDE (Cantidad, SubtotalNeto, PrecioUnitario, DescuentoMonto);

EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.sp_ObtenerDashboardVentas
  @ActorUsuarioId INT,
  @Modo VARCHAR(15) = ''MENSUAL'',
  @FechaDesde DATE = NULL,
  @FechaHasta DATE = NULL,
  @Limite INT = 10,
  @Desplazamiento INT = 0
AS
BEGIN
  SET NOCOUNT ON;
  SET XACT_ABORT ON;
  EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId, N''ANALITICA_CONSULTAR'';
  IF @Modo NOT IN (''DIARIO'', ''SEMANAL'', ''MENSUAL'', ''RANGO'', ''PERSONALIZADO'')
    THROW 56011, ''Modo temporal inválido.'', 1;
  IF @Limite IS NULL OR @Limite < 1 OR @Limite > 100 OR @Desplazamiento IS NULL OR @Desplazamiento < 0
    THROW 56012, ''Paginación inválida.'', 1;

  DECLARE @HoyLocal DATE = CONVERT(date, SYSUTCDATETIME() AT TIME ZONE ''UTC'' AT TIME ZONE ''Central America Standard Time'');
  DECLARE @InicioLocal DATE, @FinLocalExclusivo DATE;
  IF @Modo = ''DIARIO''
  BEGIN SET @InicioLocal = COALESCE(@FechaDesde, @HoyLocal); SET @FinLocalExclusivo = DATEADD(day, 1, @InicioLocal); END;
  ELSE IF @Modo = ''SEMANAL''
  BEGIN
    SET @InicioLocal = DATEADD(day, -(DATEDIFF(day, CONVERT(date, ''19000101''), COALESCE(@FechaDesde, @HoyLocal)) % 7), COALESCE(@FechaDesde, @HoyLocal));
    SET @FinLocalExclusivo = DATEADD(day, 7, @InicioLocal);
  END;
  ELSE IF @Modo = ''MENSUAL''
  BEGIN SET @InicioLocal = DATEFROMPARTS(YEAR(COALESCE(@FechaDesde, @HoyLocal)), MONTH(COALESCE(@FechaDesde, @HoyLocal)), 1); SET @FinLocalExclusivo = DATEADD(month, 1, @InicioLocal); END;
  ELSE
  BEGIN
    IF @FechaDesde IS NULL OR @FechaHasta IS NULL OR @FechaDesde > @FechaHasta THROW 56013, ''El rango de fechas es obligatorio y no puede estar invertido.'', 1;
    SET @InicioLocal = @FechaDesde; SET @FinLocalExclusivo = DATEADD(day, 1, @FechaHasta);
  END;

  DECLARE @DesdeUtc DATETIME2(3) = CONVERT(datetime2(3), (CAST(@InicioLocal AS datetime2) AT TIME ZONE ''Central America Standard Time'') AT TIME ZONE ''UTC'');
  DECLARE @HastaUtc DATETIME2(3) = CONVERT(datetime2(3), (CAST(@FinLocalExclusivo AS datetime2) AT TIME ZONE ''Central America Standard Time'') AT TIME ZONE ''UTC'');
  DECLARE @HoyDesdeUtc DATETIME2(3) = CONVERT(datetime2(3), (CAST(@HoyLocal AS datetime2) AT TIME ZONE ''Central America Standard Time'') AT TIME ZONE ''UTC'');
  DECLARE @HoyHastaUtc DATETIME2(3) = CONVERT(datetime2(3), (CAST(DATEADD(day, 1, @HoyLocal) AS datetime2) AT TIME ZONE ''Central America Standard Time'') AT TIME ZONE ''UTC'');
  DECLARE @MesDesdeLocal DATE = DATEFROMPARTS(YEAR(@HoyLocal), MONTH(@HoyLocal), 1);
  DECLARE @MesDesdeUtc DATETIME2(3) = CONVERT(datetime2(3), (CAST(@MesDesdeLocal AS datetime2) AT TIME ZONE ''Central America Standard Time'') AT TIME ZONE ''UTC'');
  DECLARE @MesHastaUtc DATETIME2(3) = CONVERT(datetime2(3), (CAST(DATEADD(month, 1, @MesDesdeLocal) AS datetime2) AT TIME ZONE ''Central America Standard Time'') AT TIME ZONE ''UTC'');

  SELECT CONVERT(varchar(10), @InicioLocal, 23) AS PeriodoDesdeLocal,
         CONVERT(varchar(10), DATEADD(day, -1, @FinLocalExclusivo), 23) AS PeriodoHastaLocal,
         CONVERT(varchar(30), CONVERT(DECIMAL(19,2), COALESCE((SELECT SUM(Total) FROM dbo.Factura WHERE Estado = ''EMITIDA'' AND FechaHora >= @HoyDesdeUtc AND FechaHora < @HoyHastaUtc), 0))) AS VentasDia,
         CONVERT(varchar(30), CONVERT(DECIMAL(19,2), COALESCE((SELECT SUM(Total) FROM dbo.Factura WHERE Estado = ''EMITIDA'' AND FechaHora >= @MesDesdeUtc AND FechaHora < @MesHastaUtc), 0))) AS VentasMes,
         CONVERT(varchar(30), CONVERT(DECIMAL(19,2), COALESCE((SELECT SUM(Total) FROM dbo.Factura WHERE Estado = ''EMITIDA'' AND FechaHora >= @DesdeUtc AND FechaHora < @HastaUtc), 0))) AS VentasRango,
         CONVERT(varchar(30), COALESCE((SELECT COUNT_BIG(*) FROM dbo.Factura WHERE Estado = ''EMITIDA'' AND FechaHora >= @DesdeUtc AND FechaHora < @HastaUtc), 0)) AS FacturasRango,
         CONVERT(varchar(30), CONVERT(DECIMAL(19,2), COALESCE((SELECT AVG(CONVERT(DECIMAL(19,4), Total)) FROM dbo.Factura WHERE Estado = ''EMITIDA'' AND FechaHora >= @DesdeUtc AND FechaHora < @HastaUtc), 0))) AS TicketPromedio,
         CONVERT(varchar(30), COALESCE((SELECT SUM(CONVERT(BIGINT, d.Cantidad)) FROM dbo.Factura f JOIN dbo.DetalleFactura d ON d.FacturaId = f.FacturaId WHERE f.Estado = ''EMITIDA'' AND f.FechaHora >= @DesdeUtc AND f.FechaHora < @HastaUtc), 0)) AS UnidadesVendidas,
         ''UTC-6 / America Guatemala'' AS ZonaHoraria,
         ''[inicio local, fin local exclusivo)'' AS LimiteTemporal;

  SELECT ProductoId, SKU, Producto, UnidadesVendidas, ImporteVendido, NumeroFacturas, Ranking
  FROM dbo.fn_ProductosMasVendidos(@DesdeUtc, @HastaUtc)
  ORDER BY Ranking, ProductoId OFFSET @Desplazamiento ROWS FETCH NEXT @Limite ROWS ONLY;

  SELECT ClienteId, NombreCliente, NumeroCompras, TotalHistoricoComprado, UltimaFechaCompra, TicketPromedio, Clasificacion, Activo
  FROM dbo.fn_AnalisisClientesFrecuentes(@DesdeUtc, @HastaUtc)
  WHERE NumeroCompras > 0
  ORDER BY NumeroCompras DESC, TotalHistoricoComprado DESC, ClienteId OFFSET @Desplazamiento ROWS FETCH NEXT @Limite ROWS ONLY;

  SELECT ProductoId, SKU, Producto, ProveedorId, Proveedor, Stock, StockMinimo, PuntoReorden, Deficit, CantidadSugerida, BajoMinimo, EnReorden, NecesitaCompra, EstadoAbastecimiento, Activo
  FROM dbo.fn_ProductosPorComprar(0)
  WHERE NecesitaCompra = 1
  ORDER BY CASE WHEN EstadoAbastecimiento = ''PROVEEDOR_PENDIENTE'' THEN 0 ELSE 1 END, Deficit DESC, ProductoId
  OFFSET @Desplazamiento ROWS FETCH NEXT @Limite ROWS ONLY;

  -- Una falta de permiso no debe ocultar las métricas comerciales autorizadas.
  IF EXISTS(SELECT 1 FROM dbo.Usuario u
    JOIN dbo.Usuario_Rol ur ON ur.UsuarioId=u.UsuarioId
    JOIN dbo.Rol r ON r.RolId=ur.RolId AND r.Activo=1
    JOIN dbo.Rol_Permiso rp ON rp.RolId=r.RolId
    JOIN dbo.Permiso p ON p.PermisoId=rp.PermisoId AND p.Activo=1
    WHERE u.UsuarioId=@ActorUsuarioId AND u.Activo=1 AND p.Codigo=N''GARANTIAS_CONSULTAR'')
  BEGIN
    EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId, N''GARANTIAS_CONSULTAR'';
    SELECT CONVERT(bit,1) Integrado, estados.Estado,
      CONVERT(varchar(30),COUNT_BIG(t.TicketId)) Cantidad
    FROM (VALUES(''RECIBIDO''),(''EN_REVISION''),(''APROBADO''),(''RECHAZADO''),(''ENTREGADO'')) estados(Estado)
    LEFT JOIN dbo.Ticket_Garantia t ON t.Estado=estados.Estado
      AND t.FechaApertura>=@DesdeUtc AND t.FechaApertura<@HastaUtc
    GROUP BY estados.Estado;
  END
  ELSE
    SELECT CONVERT(bit,0) Integrado, N''Se requiere GARANTIAS_CONSULTAR para ver las métricas.'' Mensaje;
END;';
GO
