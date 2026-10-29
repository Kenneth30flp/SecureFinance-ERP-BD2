-- Catalogo sintetico, sin identidades, credenciales, fixtures ni historia.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() COLLATE Latin1_General_100_BIN2 <> N'SecureFinanceERP_Lab_Dylan'
 OR @@TRANCOUNT <> 1 OR XACT_STATE() <> 1
 THROW 54980, 'Requiere laboratorio exacto y una transaccion externa activa.', 1;
IF OBJECT_ID(N'dbo.Rol', N'U') IS NULL OR OBJECT_ID(N'dbo.Permiso', N'U') IS NULL
 OR OBJECT_ID(N'dbo.Rol_Permiso', N'U') IS NULL OR OBJECT_ID(N'dbo.Usuario', N'U') IS NULL
 THROW 54980, 'Falta la estructura de seguridad nueva.', 1;
IF EXISTS (SELECT 1 FROM dbo.Rol) OR EXISTS (SELECT 1 FROM dbo.Permiso)
 OR EXISTS (SELECT 1 FROM dbo.Rol_Permiso) OR EXISTS (SELECT 1 FROM dbo.Usuario)
 OR EXISTS (SELECT 1 FROM dbo.Usuario_Rol) OR EXISTS (SELECT 1 FROM dbo.Token_Recuperacion)
 OR EXISTS (SELECT 1 FROM dbo.Bitacora_Acceso)
 THROW 54980, 'Solo se admite seguridad vacia; no se reconstruyen catalogos existentes.', 1;

INSERT dbo.Rol (Nombre, Descripcion) VALUES
 (N'Administrador', N'Administracion del laboratorio'),
 (N'Cajero', N'Operaciones de venta autorizadas'),
 (N'Auditor', N'Consulta de auditoria');
INSERT dbo.Permiso (Codigo, Descripcion) VALUES
 (N'USUARIOS_ADMINISTRAR', N'Administrar usuarios y roles'),
 (N'VENTAS_REGISTRAR', N'Registrar ventas'),
 (N'AUDITORIA_CONSULTAR', N'Consultar auditoria');
INSERT dbo.Rol_Permiso (RolId, PermisoId)
SELECT r.RolId, p.PermisoId
FROM dbo.Rol r CROSS JOIN dbo.Permiso p
WHERE r.Nombre = N'Administrador'
 OR (r.Nombre = N'Cajero' AND p.Codigo = N'VENTAS_REGISTRAR')
 OR (r.Nombre = N'Auditor' AND p.Codigo = N'AUDITORIA_CONSULTAR');
GO
