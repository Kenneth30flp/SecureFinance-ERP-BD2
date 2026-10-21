-- José / RBAC de consulta analítica. Incremental, repetible y sin DML general.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() IN ('master','model','msdb','tempdb') THROW 56020, 'Seleccione la base de aplicación.', 1;
IF OBJECT_ID('dbo.sp_ObtenerDashboardVentas','P') IS NULL THROW 56020, 'Requiere la migración 31.', 1;
BEGIN TRY
  BEGIN TRANSACTION;
  INSERT dbo.Permiso(Codigo, Descripcion)
  SELECT v.Codigo, v.Descripcion
  FROM (VALUES
    (N'ANALITICA_CONSULTAR', N'Consultar analítica avanzada de ventas, clientes y abastecimiento'),
    (N'REPORTES_EJECUTIVOS_CONSULTAR', N'Consultar el dashboard ejecutivo de ventas')
  ) v(Codigo, Descripcion)
  WHERE NOT EXISTS (SELECT 1 FROM dbo.Permiso p WITH (UPDLOCK, HOLDLOCK) WHERE p.Codigo = v.Codigo);

  INSERT dbo.Rol_Permiso(RolId, PermisoId)
  SELECT r.RolId, p.PermisoId
  FROM dbo.Rol r CROSS JOIN dbo.Permiso p
  WHERE r.Nombre = N'Administrador' AND r.Activo = 1
    AND p.Codigo IN (N'ANALITICA_CONSULTAR', N'REPORTES_EJECUTIVOS_CONSULTAR') AND p.Activo = 1
    AND NOT EXISTS (SELECT 1 FROM dbo.Rol_Permiso rp WHERE rp.RolId = r.RolId AND rp.PermisoId = p.PermisoId);

  IF DATABASE_PRINCIPAL_ID(N'securefinance_app') IS NULL THROW 56021, 'Falta usuario SQL dedicado.', 1;
  GRANT EXECUTE ON OBJECT::dbo.sp_ObtenerDashboardVentas TO securefinance_app;
  COMMIT TRANSACTION;
END TRY
BEGIN CATCH
  IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
  THROW;
END CATCH;
GO
