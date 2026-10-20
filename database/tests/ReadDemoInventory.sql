-- Read-only inventory. No substitutions, updates, or deletion of historical data.
SET NOCOUNT ON;
SELECT
 JSON_QUERY((SELECT c.ClienteId,c.Nombre,c.NIT,c.Correo,c.Telefono,
   (SELECT COUNT(*) FROM dbo.Factura f WHERE f.ClienteId=c.ClienteId) Facturas
 FROM dbo.Cliente c WHERE c.NIT LIKE '%DEMO%' OR c.Nombre LIKE '%DEMO%' OR c.Correo LIKE '%.invalid' FOR JSON PATH)) Clientes,
 JSON_QUERY((SELECT p.ProductoId,p.Codigo,p.Descripcion,p.Stock,p.StockMinimo,p.PuntoReorden,
   (SELECT COUNT(*) FROM dbo.DetalleFactura d WHERE d.ProductoId=p.ProductoId) LineasFactura,
   (SELECT COUNT(*) FROM dbo.Kardex_Inventario k WHERE k.ProductoId=p.ProductoId) MovimientosKardex
 FROM dbo.Producto p WHERE p.Codigo LIKE '%DEMO%' OR p.Descripcion LIKE '%DEMO%' FOR JSON PATH)) Productos,
 JSON_QUERY((SELECT s.ProveedorId,s.Nombre,s.NIT,s.Correo,
   (SELECT COUNT(*) FROM dbo.Producto p WHERE p.ProveedorId=s.ProveedorId) ProductosAsociados
 FROM dbo.Proveedor s WHERE s.NIT LIKE '%DEMO%' OR s.Nombre LIKE '%DEMO%' OR s.Correo LIKE '%.invalid' FOR JSON PATH)) Proveedores,
 JSON_QUERY((SELECT u.UsuarioId,u.NombreUsuario,u.NombreCompleto,u.Correo FROM dbo.Usuario u
 WHERE u.NombreCompleto LIKE '%DEMO%' OR u.Correo LIKE '%DEMO%' OR u.Correo LIKE '%.invalid' FOR JSON PATH)) Usuarios
FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
