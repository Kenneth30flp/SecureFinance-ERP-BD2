SET XACT_ABORT ON; SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON;
IF DB_NAME() <> N'SecureFinanceERP_Lab_Dylan' OR @@TRANCOUNT=0 THROW 57000,'Laboratorio y transaccion externa requeridos.',1;
IF DATABASE_PRINCIPAL_ID(N'securefinance_app') IS NULL THROW 57000,'Usuario de aplicacion no instalado.',1;
IF NOT EXISTS(SELECT 1 FROM dbo.Rol WHERE Nombre=N'Administrador' AND Activo=1) THROW 57000,'Falta rol Administrador activo.',1;
INSERT dbo.Permiso(Codigo,Descripcion)
SELECT v.Codigo,v.Descripcion FROM (VALUES
 (N'CREDITOS_CONSULTAR',N'Consultar cuentas por cobrar, perfiles, cuotas y recibos'),
 (N'CREDITOS_ADMINISTRAR',N'Autorizar o desactivar credito con version y motivo'),
 (N'CREDITOS_ABONAR',N'Registrar abonos inmutables a facturas de credito'),
 (N'CREDITOS_FACTURAR',N'Facturar cotizaciones a credito')) v(Codigo,Descripcion)
WHERE NOT EXISTS(SELECT 1 FROM dbo.Permiso p WITH(UPDLOCK,HOLDLOCK) WHERE p.Codigo=v.Codigo);
INSERT dbo.Rol_Permiso(RolId,PermisoId)
SELECT r.RolId,p.PermisoId FROM dbo.Rol r CROSS JOIN dbo.Permiso p
WHERE r.Activo=1 AND p.Codigo IN(N'CREDITOS_CONSULTAR',N'CREDITOS_ADMINISTRAR',N'CREDITOS_ABONAR',N'CREDITOS_FACTURAR')
 AND (r.Nombre=N'Administrador' OR (r.Nombre=N'Auditor' AND p.Codigo=N'CREDITOS_CONSULTAR')
 OR (r.Nombre=N'Cajero' AND p.Codigo IN(N'CREDITOS_CONSULTAR',N'CREDITOS_ABONAR')))
 AND NOT EXISTS(SELECT 1 FROM dbo.Rol_Permiso rp WHERE rp.RolId=r.RolId AND rp.PermisoId=p.PermisoId);
-- No broad schema grants. Internal helpers cannot be invoked by the web login.
GRANT EXECUTE ON dbo.P3_CRE_Consultar TO securefinance_app;
GRANT EXECUTE ON dbo.P3_CRE_ConsultarCaja TO securefinance_app;
GRANT EXECUTE ON dbo.P3_CRE_ConsultarRecibo TO securefinance_app;
GRANT EXECUTE ON dbo.P3_CRE_AdministrarCredito TO securefinance_app;
GRANT EXECUTE ON dbo.sp_RegistrarAbonoCliente TO securefinance_app;
DENY EXECUTE ON dbo.P3_CRE_ValidarFinanciacion TO securefinance_app;
DENY EXECUTE ON dbo.P3_CRE_CrearCuenta TO securefinance_app;
DENY EXECUTE ON dbo.P3_CRE_Auditar TO securefinance_app;
DENY EXECUTE ON dbo.P3_CRE_ValidarEntorno TO securefinance_app;
DECLARE @Tabla SYSNAME,@Sql NVARCHAR(MAX);
DECLARE libros CURSOR LOCAL FAST_FORWARD FOR SELECT n FROM (VALUES
 (N'Credito_Cliente'),(N'P3_CRE_Cuenta'),(N'P3_CRE_Cuota'),(N'Abono_Factura'),(N'P3_CRE_ReciboCaja'),
 (N'P3_CRE_AplicacionCuota'),(N'P3_CRE_Operacion'),(N'P3_CRE_Historial')) t(n);
OPEN libros; FETCH NEXT FROM libros INTO @Tabla;
WHILE @@FETCH_STATUS=0
BEGIN
 SET @Sql=N'DENY SELECT,INSERT,UPDATE,DELETE ON dbo.'+QUOTENAME(@Tabla)+N' TO securefinance_app;';
 EXEC sys.sp_executesql @Sql;
 IF @Tabla NOT IN(N'Credito_Cliente',N'P3_CRE_Cuenta',N'P3_CRE_Cuota')
 BEGIN
  SET @Sql=N'CREATE OR ALTER TRIGGER dbo.'+QUOTENAME(N'P3_CRE_Inmutable_'+@Tabla)+N' ON dbo.'+QUOTENAME(@Tabla)+
   N' INSTEAD OF UPDATE,DELETE AS BEGIN SET NOCOUNT ON; THROW 57007,''Libro de credito inmutable.'',1; END;';
  EXEC sys.sp_executesql @Sql;
 END;
 FETCH NEXT FROM libros INTO @Tabla;
END;
CLOSE libros; DEALLOCATE libros;
GO
