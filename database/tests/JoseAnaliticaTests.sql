-- Ensayo de José. Ejecutar SOLO en una base aislada con nombre
-- SecureFinanceERP_JoseTest* o SecureFinanceERP_ParteII_Test*.
-- El ensayo es transaccional y revierte sus fixtures; nunca apunta a la base principal.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() NOT LIKE 'SecureFinanceERP_JoseTest%'
   AND DB_NAME() NOT LIKE 'SecureFinanceERP_ParteII_Test%'
  THROW 56100, 'Base no aislada: se cancela el ensayo de analítica.', 1;
IF OBJECT_ID('dbo.fn_ProductosMasVendidos','IF') IS NULL
   OR OBJECT_ID('dbo.fn_ProductosPorComprar','IF') IS NULL
   OR OBJECT_ID('dbo.fn_AnalisisClientesFrecuentes','IF') IS NULL
   OR OBJECT_ID('dbo.sp_ObtenerDashboardVentas','P') IS NULL
  THROW 56101, 'Faltan las migraciones 30–32.', 1;

BEGIN TRY
  BEGIN TRANSACTION;
  DECLARE @Actor INT = (
    SELECT TOP (1) u.UsuarioId
    FROM dbo.Usuario u
    JOIN dbo.Usuario_Rol ur ON ur.UsuarioId = u.UsuarioId
    JOIN dbo.Rol_Permiso rp ON rp.RolId = ur.RolId
    JOIN dbo.Permiso p ON p.PermisoId = rp.PermisoId
    WHERE u.Activo = 1 AND p.Codigo = N'ANALITICA_CONSULTAR'
  );
  IF @Actor IS NULL THROW 56102, 'No existe un usuario de laboratorio con ANALITICA_CONSULTAR.', 1;

  DECLARE @Sufijo VARCHAR(36) = REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', '');
  DECLARE @Proveedor INT, @ClienteA INT, @ClienteB INT, @P1 INT, @P2 INT, @P3 INT, @P4 INT, @P5 INT, @P6 INT;
  INSERT dbo.Proveedor(NIT,Nombre) VALUES (CONCAT('J', LEFT(@Sufijo, 24)), CONCAT('Proveedor ensayo ', @Sufijo));
  SET @Proveedor = SCOPE_IDENTITY();
  INSERT dbo.Cliente(NIT,Nombre) VALUES (CONCAT('C', LEFT(@Sufijo, 24)), CONCAT('Cliente frecuente ', @Sufijo));
  SET @ClienteA = SCOPE_IDENTITY();
  INSERT dbo.Cliente(NIT,Nombre,Activo) VALUES (CONCAT('I', LEFT(@Sufijo, 24)), CONCAT('Cliente inactivo ', @Sufijo), 0);
  SET @ClienteB = SCOPE_IDENTITY();
  INSERT dbo.Producto(Codigo,Descripcion,Precio,ProveedorId,Stock,StockMinimo,PuntoReorden) VALUES
    (CONCAT('J1-', LEFT(@Sufijo, 12)), 'Producto ranking con descuento', 100, @Proveedor, 20, 5, 8),
    (CONCAT('J2-', LEFT(@Sufijo, 12)), 'Producto precio historico', 100, @Proveedor, 20, 5, 8),
    (CONCAT('J3-', LEFT(@Sufijo, 12)), 'Producto stock cero sin proveedor', 10, NULL, 0, 5, 8),
    (CONCAT('J4-', LEFT(@Sufijo, 12)), 'Producto bajo minimo', 10, @Proveedor, 4, 5, 6),
    (CONCAT('J5-', LEFT(@Sufijo, 12)), 'Producto igual reorden', 10, @Proveedor, 7, 5, 7),
    (CONCAT('J6-', LEFT(@Sufijo, 12)), 'Producto inactivo', 10, NULL, 0, 5, 8);
  SELECT @P1 = ProductoId FROM dbo.Producto WHERE Codigo = CONCAT('J1-', LEFT(@Sufijo, 12));
  SELECT @P2 = ProductoId FROM dbo.Producto WHERE Codigo = CONCAT('J2-', LEFT(@Sufijo, 12));
  SELECT @P3 = ProductoId FROM dbo.Producto WHERE Codigo = CONCAT('J3-', LEFT(@Sufijo, 12));
  SELECT @P4 = ProductoId FROM dbo.Producto WHERE Codigo = CONCAT('J4-', LEFT(@Sufijo, 12));
  SELECT @P5 = ProductoId FROM dbo.Producto WHERE Codigo = CONCAT('J5-', LEFT(@Sufijo, 12));
  SELECT @P6 = ProductoId FROM dbo.Producto WHERE Codigo = CONCAT('J6-', LEFT(@Sufijo, 12));
  UPDATE dbo.Producto SET Activo = 0 WHERE ProductoId = @P6;

  DECLARE @HoyUtc DATETIME2(3) = DATEADD(hour, -1, SYSUTCDATETIME()), @F1 INT, @F2 INT;
  INSERT dbo.Factura(ClienteId,UsuarioId,FechaHora,Subtotal,DescuentoTotal,IVA,Total,ClienteNITEmision,ClienteNombreEmision)
  VALUES (@ClienteA,@Actor,@HoyUtc,20,2,2.16,20.16,CONCAT('C', LEFT(@Sufijo, 24)),CONCAT('Cliente frecuente ', @Sufijo));
  SET @F1 = SCOPE_IDENTITY();
  INSERT dbo.DetalleFactura(FacturaId,ProductoId,Cantidad,PrecioUnitario,Subtotal,DescuentoPorcentaje,DescuentoMonto) VALUES (@F1,@P1,2,10,20,10,2);
  INSERT dbo.Factura(ClienteId,UsuarioId,FechaHora,Subtotal,DescuentoTotal,IVA,Total,ClienteNITEmision,ClienteNombreEmision)
  VALUES (@ClienteA,@Actor,@HoyUtc,15,0,1.80,16.80,CONCAT('C', LEFT(@Sufijo, 24)),CONCAT('Cliente frecuente ', @Sufijo));
  SET @F2 = SCOPE_IDENTITY();
  INSERT dbo.DetalleFactura(FacturaId,ProductoId,Cantidad,PrecioUnitario,Subtotal,DescuentoPorcentaje,DescuentoMonto) VALUES (@F2,@P1,3,5,15,0,0);
  INSERT dbo.Factura(ClienteId,UsuarioId,FechaHora,Subtotal,DescuentoTotal,IVA,Total,ClienteNITEmision,ClienteNombreEmision)
  VALUES (@ClienteB,@Actor,@HoyUtc,7,0,.84,7.84,CONCAT('I', LEFT(@Sufijo, 24)),CONCAT('Cliente inactivo ', @Sufijo));
  INSERT dbo.DetalleFactura(FacturaId,ProductoId,Cantidad,PrecioUnitario,Subtotal,DescuentoPorcentaje,DescuentoMonto) VALUES (SCOPE_IDENTITY(),@P2,1,7,7,0,0);

  DECLARE @Vendidas TABLE(ProductoId INT, SKU NVARCHAR(40), Producto NVARCHAR(200), UnidadesVendidas BIGINT, ImporteVendido DECIMAL(19,2), NumeroFacturas BIGINT, Ranking INT);
  INSERT @Vendidas SELECT * FROM dbo.fn_ProductosMasVendidos(DATEADD(day,-1,@HoyUtc), DATEADD(day,1,@HoyUtc));
  IF NOT EXISTS (SELECT 1 FROM @Vendidas WHERE ProductoId=@P1 AND UnidadesVendidas=5 AND ImporteVendido=33.00 AND NumeroFacturas=2) THROW 56103, 'Fallo en venta histórica, descuento o conteo de facturas.', 1;
  IF EXISTS (SELECT 1 FROM @Vendidas WHERE ProductoId=@P2 AND ImporteVendido=100) THROW 56104, 'Se usó el precio actual del catálogo.', 1;

  IF NOT EXISTS (SELECT 1 FROM dbo.fn_ProductosPorComprar(1) WHERE ProductoId=@P3 AND EstadoAbastecimiento='PROVEEDOR_PENDIENTE' AND CantidadSugerida=8)
    THROW 56105, 'Fallo en stock cero/proveedor pendiente.', 1;
  IF NOT EXISTS (SELECT 1 FROM dbo.fn_ProductosPorComprar(1) WHERE ProductoId=@P4 AND BajoMinimo=1 AND EnReorden=1 AND CantidadSugerida=2)
    THROW 56106, 'Fallo en diferencia entre mínimo y reorden.', 1;
  IF NOT EXISTS (SELECT 1 FROM dbo.fn_ProductosPorComprar(1) WHERE ProductoId=@P5 AND BajoMinimo=0 AND EnReorden=1)
    THROW 56107, 'Fallo en igualdad con el punto de reorden.', 1;
  IF NOT EXISTS (SELECT 1 FROM dbo.fn_ProductosPorComprar(1) WHERE ProductoId=@P6 AND EstadoAbastecimiento='INACTIVO')
    THROW 56108, 'Fallo en conservación analítica del producto inactivo.', 1;
  IF EXISTS (SELECT 1 FROM dbo.fn_ProductosPorComprar(0) WHERE ProductoId=@P6)
    THROW 56109, 'El filtro de activos no excluyó el producto inactivo.', 1;

  IF NOT EXISTS (SELECT 1 FROM dbo.fn_AnalisisClientesFrecuentes(DATEADD(day,-1,@HoyUtc), DATEADD(day,1,@HoyUtc)) WHERE ClienteId=@ClienteA AND NumeroCompras=2 AND TotalHistoricoComprado=36.96)
    THROW 56110, 'Fallo en compras por factura o total histórico.', 1;
  IF NOT EXISTS (SELECT 1 FROM dbo.fn_AnalisisClientesFrecuentes(DATEADD(day,-1,@HoyUtc), DATEADD(day,1,@HoyUtc)) WHERE ClienteId=@ClienteB AND Activo=0 AND NumeroCompras=1)
    THROW 56111, 'Se perdió el historial del cliente inactivo.', 1;
  IF EXISTS (SELECT 1 FROM dbo.fn_AnalisisClientesFrecuentes(DATEADD(day,-1,@HoyUtc), DATEADD(day,1,@HoyUtc)) WHERE ClienteId=@ClienteA AND NumeroCompras=3)
    THROW 56112, 'Se contaron líneas como facturas.', 1;

  SELECT 'PASS' AS Resultado, 'Fixtures sintéticos validados; la transacción será revertida.' AS Detalle;
  ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
  IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
  THROW;
END CATCH;
GO
