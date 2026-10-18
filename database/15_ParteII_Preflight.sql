-- Parte II / Kenneth. Incremental; ejecutar en la base destino seleccionada.
-- No contiene USE: permite validacion aislada. No ejecutar sobre produccion sin aprobacion.
SET NOCOUNT ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;

IF DB_NAME() IN ('master','model','msdb','tempdb') THROW 54000, 'Seleccione la base de aplicacion o una copia aislada.', 1;
IF TRY_CONVERT(INT, SERVERPROPERTY('ProductMajorVersion')) < 14 THROW 54000, 'Parte I utiliza STRING_AGG: se requiere SQL Server 2017 o posterior.', 1;
IF (SELECT value_in_use FROM sys.configurations WHERE name='nested triggers')<>1 THROW 54000, 'La captura protegida de identidad requiere nested triggers habilitado.',1;
IF EXISTS (SELECT 1 FROM (VALUES ('Cliente'),('Producto'),('Factura'),('DetalleFactura'),('MovimientoCaja'),('Usuario'),('Rol'),('Permiso'),('Usuario_Rol'),('Rol_Permiso'),('Bitacora_Transacciones')) t(n) WHERE OBJECT_ID('dbo.'+n,'U') IS NULL)
 THROW 54000, 'Faltan tablas base de Parte I.', 1;
IF OBJECT_ID('dbo.sp_ProcesarVentaTransaccional','P') IS NULL OR OBJECT_ID('dbo.sp_ObtenerResumenDashboard','P') IS NULL OR TYPE_ID('dbo.TipoDetalleVentaDescuento') IS NULL
 THROW 54000, 'Instale y valide Parte I hasta 14 antes de continuar.', 1;
IF COL_LENGTH('dbo.Factura','MotivoDescuento') IS NULL OR COL_LENGTH('dbo.DetalleFactura','DescuentoMonto') IS NULL THROW 54000, 'Faltan ampliaciones de facturacion.', 1;
IF EXISTS (SELECT 1 FROM dbo.Producto WHERE Stock < 0 OR Precio < 0) THROW 54000, 'Existencias o precios inconsistentes.', 1;
IF EXISTS (SELECT 1 FROM dbo.Cliente WHERE LEN(LTRIM(RTRIM(NIT)))=0) THROW 54000, 'NIT vacio existente.', 1;
IF EXISTS (SELECT 1 FROM dbo.Cliente WHERE LEN(REPLACE(LTRIM(RTRIM(NIT)),N'-',N''))=0) THROW 54000, 'NIT sin contenido despues de normalizacion.',1;
IF EXISTS (SELECT UPPER(REPLACE(LTRIM(RTRIM(NIT)),N'-',N'')) FROM dbo.Cliente GROUP BY UPPER(REPLACE(LTRIM(RTRIM(NIT)),N'-',N'')) HAVING COUNT(*)>1)
 THROW 54000, 'Hay NIT equivalentes. Resolver manualmente; no se fusionan clientes.', 1;
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id IN (OBJECT_ID('dbo.Factura'),OBJECT_ID('dbo.DetalleFactura')) AND (is_disabled=1 OR is_not_trusted=1)) THROW 54000, 'FK de facturacion deshabilitada o no confiable.', 1;
PRINT 'OK prevalidacion; no se modificaron datos. Ejecutar 16 a 20 en orden, detenerse ante cualquier error.';
GO
