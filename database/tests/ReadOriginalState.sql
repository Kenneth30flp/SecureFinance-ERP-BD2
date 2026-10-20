-- SOLO LECTURA. No ejecutar SPs de negocio, ni DML/DDL en la base original.
SET NOCOUNT ON;
IF DB_NAME()<>N'SecureFinanceERP' THROW 54900,'Esta lectura requiere la base original explicitamente seleccionada.',1;
SELECT N'Producto' AS Objeto,COUNT_BIG(*) AS Filas,
 CONVERT(VARCHAR(64),HASHBYTES('SHA2_256',CONVERT(VARBINARY(MAX),(SELECT ProductoId,Codigo,Descripcion,Precio,Stock,Activo,FechaCreacion FROM dbo.Producto ORDER BY ProductoId FOR JSON PATH,INCLUDE_NULL_VALUES))),2) AS SHA256 FROM dbo.Producto
UNION ALL
SELECT N'Factura',COUNT_BIG(*),CONVERT(VARCHAR(64),HASHBYTES('SHA2_256',CONVERT(VARBINARY(MAX),(SELECT * FROM dbo.Factura ORDER BY FacturaId FOR JSON PATH,INCLUDE_NULL_VALUES))),2) FROM dbo.Factura
UNION ALL
SELECT N'DetalleFactura',COUNT_BIG(*),CONVERT(VARCHAR(64),HASHBYTES('SHA2_256',CONVERT(VARBINARY(MAX),(SELECT * FROM dbo.DetalleFactura ORDER BY DetalleFacturaId FOR JSON PATH,INCLUDE_NULL_VALUES))),2) FROM dbo.DetalleFactura
UNION ALL
SELECT N'MovimientoCaja',COUNT_BIG(*),CONVERT(VARCHAR(64),HASHBYTES('SHA2_256',CONVERT(VARBINARY(MAX),(SELECT * FROM dbo.MovimientoCaja ORDER BY MovimientoCajaId FOR JSON PATH,INCLUDE_NULL_VALUES))),2) FROM dbo.MovimientoCaja
UNION ALL
SELECT N'Usuario_Rol',COUNT_BIG(*),CONVERT(VARCHAR(64),HASHBYTES('SHA2_256',CONVERT(VARBINARY(MAX),(SELECT * FROM dbo.Usuario_Rol ORDER BY UsuarioId,RolId FOR JSON PATH,INCLUDE_NULL_VALUES))),2) FROM dbo.Usuario_Rol
UNION ALL
SELECT N'Rol_Permiso',COUNT_BIG(*),CONVERT(VARCHAR(64),HASHBYTES('SHA2_256',CONVERT(VARBINARY(MAX),(SELECT * FROM dbo.Rol_Permiso ORDER BY RolId,PermisoId FOR JSON PATH,INCLUDE_NULL_VALUES))),2) FROM dbo.Rol_Permiso
UNION ALL
SELECT N'Modulos',COUNT_BIG(*),CONVERT(VARCHAR(64),HASHBYTES('SHA2_256',CONVERT(VARBINARY(MAX),(SELECT object_id,definition FROM sys.sql_modules ORDER BY object_id FOR JSON PATH,INCLUDE_NULL_VALUES))),2) FROM sys.sql_modules;
IF OBJECT_ID('dbo.Kardex_Inventario','U') IS NULL
 SELECT N'Kardex' AS Objeto,N'NO_INSTALADO' AS Estado;
ELSE
 EXEC sys.sp_executesql N'SELECT N''Kardex'' AS Objeto,COUNT_BIG(*) AS Filas,CONVERT(VARCHAR(64),HASHBYTES(''SHA2_256'',CONVERT(VARBINARY(MAX),(SELECT * FROM dbo.Kardex_Inventario ORDER BY KardexId FOR JSON PATH,INCLUDE_NULL_VALUES))),2) AS SHA256 FROM dbo.Kardex_Inventario;';
IF OBJECT_ID('dbo.ConfiguracionInventario','U') IS NULL
 SELECT N'ConfiguracionInventario' AS Objeto,N'NO_INSTALADO' AS Estado;
ELSE
 EXEC sys.sp_executesql N'SELECT ConfiguracionId,Habilitado,FechaActivacion FROM dbo.ConfiguracionInventario ORDER BY ConfiguracionId;';
