-- Read-only evidence for a human-approved transition to authentic master records.
-- Never updates master identities, emitted invoices, audit events or Kardex balances.
SET NOCOUNT ON;
DECLARE @Resultado nvarchar(max);
SET @Resultado=(
SELECT DB_NAME() BaseDatos, SYSUTCDATETIME() CapturadoUTC,
 JSON_QUERY((SELECT c.ClienteId,c.Nombre,c.NIT,c.Correo,c.Telefono,c.Activo,
   JSON_QUERY((SELECT f.FacturaId,f.FechaHora,f.Total,f.ClienteNITEmision,f.ClienteNombreEmision FROM dbo.Factura f WHERE f.ClienteId=c.ClienteId ORDER BY f.FacturaId FOR JSON PATH, INCLUDE_NULL_VALUES)) Facturas,
   (SELECT COUNT_BIG(*) FROM dbo.Bitacora_Transacciones a WHERE a.TablaAfectada=N'Cliente' AND a.IdentificadorRegistro=CONVERT(nvarchar(4000),c.ClienteId)) EventosAuditoria
 FROM dbo.Cliente c WHERE c.NIT LIKE '%DEMO%' OR c.Nombre LIKE '%DEMO%' OR c.Correo LIKE '%.invalid' FOR JSON PATH, INCLUDE_NULL_VALUES)) Clientes,
 JSON_QUERY((SELECT p.ProductoId,p.Codigo,p.Descripcion,p.ProveedorId,p.Precio,p.PrecioCosto,p.Stock,p.StockMinimo,p.PuntoReorden,p.GarantiaMeses,p.Activo,
   JSON_QUERY((SELECT d.DetalleFacturaId,d.FacturaId,d.Cantidad,d.PrecioUnitario FROM dbo.DetalleFactura d WHERE d.ProductoId=p.ProductoId ORDER BY d.DetalleFacturaId FOR JSON PATH)) LineasFactura,
   JSON_QUERY((SELECT k.KardexId,k.TipoMovimiento,k.FechaHora,k.DocumentoRespaldo,k.StockAnterior,k.StockResultante FROM dbo.Kardex_Inventario k WHERE k.ProductoId=p.ProductoId ORDER BY k.KardexId FOR JSON PATH)) Kardex,
   (SELECT COUNT_BIG(*) FROM dbo.Bitacora_Transacciones a WHERE a.TablaAfectada=N'Producto' AND a.IdentificadorRegistro=CONVERT(nvarchar(4000),p.ProductoId)) EventosAuditoria
 FROM dbo.Producto p WHERE p.Codigo LIKE '%DEMO%' OR p.Descripcion LIKE '%DEMO%' FOR JSON PATH, INCLUDE_NULL_VALUES)) Productos,
 JSON_QUERY((SELECT s.ProveedorId,s.Nombre,s.NIT,s.Correo,s.Telefono,s.Direccion,s.Activo,
   JSON_QUERY((SELECT p.ProductoId,p.Codigo FROM dbo.Producto p WHERE p.ProveedorId=s.ProveedorId ORDER BY p.ProductoId FOR JSON PATH)) Productos,
   (SELECT COUNT_BIG(*) FROM dbo.Bitacora_Transacciones a WHERE a.TablaAfectada=N'Proveedor' AND a.IdentificadorRegistro=CONVERT(nvarchar(4000),s.ProveedorId)) EventosAuditoria
 FROM dbo.Proveedor s WHERE s.NIT LIKE '%DEMO%' OR s.Nombre LIKE '%DEMO%' OR s.Correo LIKE '%.invalid' FOR JSON PATH, INCLUDE_NULL_VALUES)) Proveedores,
 JSON_QUERY((SELECT u.UsuarioId,u.NombreUsuario,u.NombreCompleto,u.Correo,u.Activo,
   JSON_QUERY((SELECT r.RolId,r.Nombre FROM dbo.Usuario_Rol ur JOIN dbo.Rol r ON r.RolId=ur.RolId WHERE ur.UsuarioId=u.UsuarioId FOR JSON PATH)) Roles,
   (SELECT COUNT_BIG(*) FROM dbo.Factura f WHERE f.UsuarioId=u.UsuarioId) FacturasEmitidas,
   (SELECT COUNT_BIG(*) FROM dbo.Kardex_Inventario k WHERE k.UsuarioId=u.UsuarioId) MovimientosKardex,
   (SELECT COUNT_BIG(*) FROM dbo.Bitacora_Acceso a WHERE a.UsuarioId=u.UsuarioId) EventosAcceso,
   (SELECT COUNT_BIG(*) FROM dbo.Bitacora_Transacciones a WHERE a.ActorUsuarioId=u.UsuarioId) EventosComoActor
 FROM dbo.Usuario u WHERE u.NombreCompleto LIKE '%DEMO%' OR u.Correo LIKE '%DEMO%' OR u.Correo LIKE '%.invalid' FOR JSON PATH, INCLUDE_NULL_VALUES)) Usuarios,
 JSON_QUERY((SELECT SCHEMA_NAME(o.schema_id) Esquema,o.name Nombre
 FROM sys.procedures o WHERE o.name IN(N'sp_RegistrarCliente',N'sp_ActualizarDatosCliente',N'sp_ActualizarNitCliente',N'sp_InactivarCliente',N'sp_RegistrarProducto',N'sp_ActualizarProducto',N'sp_RegistrarProveedor',N'sp_ActualizarProveedor',N'sp_RegistrarUsuario',N'sp_ActualizarRolesUsuario') ORDER BY o.name FOR JSON PATH)) ProcedimientosDisponibles,
 JSON_QUERY((SELECT c.name Columna,TYPE_NAME(c.user_type_id) Tipo FROM sys.columns c WHERE c.object_id=OBJECT_ID(N'dbo.Factura') ORDER BY c.column_id FOR JSON PATH)) EsquemaFactura,
 JSON_QUERY((SELECT TablaAfectada,COUNT_BIG(*) Eventos,MIN(FechaHora) PrimeraFechaUTC,MAX(FechaHora) UltimaFechaUTC FROM dbo.Bitacora_Transacciones GROUP BY TablaAfectada FOR JSON PATH)) ResumenAuditoria,
 JSON_QUERY((SELECT a.BitacoraTransaccionId,a.TablaAfectada,a.IdentificadorRegistro,a.Operacion,a.FechaHora,a.ActorUsuarioId FROM dbo.Bitacora_Transacciones a
 WHERE a.ValorAnterior LIKE '%DEMO%' OR a.ValorNuevo LIKE '%DEMO%' OR a.ValorAnterior LIKE '%.invalid%' OR a.ValorNuevo LIKE '%.invalid%'
 ORDER BY a.BitacoraTransaccionId FOR JSON PATH, INCLUDE_NULL_VALUES)) EventosAuditoriaDemo
FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
SELECT @Resultado;
