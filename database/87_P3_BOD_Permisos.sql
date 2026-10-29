SET NOCOUNT ON; SET XACT_ABORT ON; SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON;
IF DB_NAME() COLLATE Latin1_General_100_BIN2<>N'SecureFinanceERP_Lab_Dylan' OR DATALENGTH(DB_NAME())<>DATALENGTH(N'SecureFinanceERP_Lab_Dylan') OR @@TRANCOUNT=0 OR XACT_STATE()<>1 THROW 58000,'Laboratorio y transaccion externa requeridos.',1;
IF DATABASE_PRINCIPAL_ID(N'securefinance_app') IS NULL THROW 58000,'Falta usuario de aplicacion.',1;
INSERT dbo.Permiso(Codigo,Descripcion)
SELECT Codigo,Descripcion FROM(VALUES
 (N'BODEGAS_CONSULTAR',N'Consultar inventario local, transito y evidencia'),
 (N'BODEGAS_ADMINISTRAR',N'Administrar bodegas y central activa'),
 (N'TRANSFERENCIAS_CREAR',N'Preparar propuesta sin reservar stock'),
 (N'TRANSFERENCIAS_DESPACHAR',N'Despachar existencia local a transito'),
 (N'TRANSFERENCIAS_RECIBIR',N'Recibir transito en destino'))v(Codigo,Descripcion)
WHERE NOT EXISTS(SELECT 1 FROM dbo.Permiso p WHERE p.Codigo=v.Codigo);
IF NOT EXISTS(SELECT 1 FROM dbo.Rol WHERE Nombre=N'Administrador' AND Activo=1)
 OR NOT EXISTS(SELECT 1 FROM dbo.Rol WHERE Nombre=N'Auditor' AND Activo=1) THROW 58000,'Requiere roles Administrador y Auditor activos.',1;
INSERT dbo.Rol_Permiso(RolId,PermisoId)
SELECT r.RolId,p.PermisoId FROM dbo.Rol r CROSS JOIN dbo.Permiso p
WHERE r.Activo=1 AND p.Codigo IN(N'BODEGAS_CONSULTAR',N'BODEGAS_ADMINISTRAR',N'TRANSFERENCIAS_CREAR',N'TRANSFERENCIAS_DESPACHAR',N'TRANSFERENCIAS_RECIBIR')
AND (r.Nombre=N'Administrador' OR (r.Nombre=N'Auditor' AND p.Codigo=N'BODEGAS_CONSULTAR'))
AND NOT EXISTS(SELECT 1 FROM dbo.Rol_Permiso rp WHERE rp.RolId=r.RolId AND rp.PermisoId=p.PermisoId);
GRANT EXECUTE ON dbo.P3_BOD_Autorizar TO securefinance_app;
GRANT EXECUTE ON dbo.P3_BOD_Consultar TO securefinance_app;
GRANT EXECUTE ON dbo.P3_BOD_ConsultarOperacion TO securefinance_app;
GRANT EXECUTE ON dbo.P3_BOD_GuardarBodega TO securefinance_app;
GRANT EXECUTE ON dbo.sp_TransferirStockBodegas TO securefinance_app;
GRANT EXECUTE ON dbo.P3_BOD_AvanzarTransferencia TO securefinance_app;
GRANT EXECUTE ON dbo.P3_BOD_RegistrarCompra TO securefinance_app;
GRANT EXECUTE ON dbo.P3_BOD_ConvertirCotizacion TO securefinance_app;
DENY EXECUTE ON dbo.P3_BOD_Reintento TO securefinance_app;
DENY EXECUTE ON dbo.P3_BOD_BloquearUbicaciones TO securefinance_app;
DENY EXECUTE ON dbo.P3_BOD_ValidarSaldo TO securefinance_app;
DENY EXECUTE ON dbo.P3_BOD_ValidarBodegaVenta TO securefinance_app;
DENY SELECT,INSERT,UPDATE,DELETE ON dbo.P3_BOD_Bodega TO securefinance_app;
DENY SELECT,INSERT,UPDATE,DELETE ON dbo.P3_BOD_Configuracion TO securefinance_app;
DENY SELECT,INSERT,UPDATE,DELETE ON dbo.P3_BOD_Stock TO securefinance_app;
DENY SELECT,INSERT,UPDATE,DELETE ON dbo.P3_BOD_Snapshot TO securefinance_app;
DENY SELECT,INSERT,UPDATE,DELETE ON dbo.P3_BOD_Transferencia TO securefinance_app;
DENY SELECT,INSERT,UPDATE,DELETE ON dbo.P3_BOD_Operacion TO securefinance_app;
DENY SELECT,INSERT,UPDATE,DELETE ON dbo.P3_BOD_Ledger TO securefinance_app;
DENY SELECT ON dbo.P3_BOD_Conciliacion TO securefinance_app;
