-- Fixture SINTETICO separado. Ejecutar ANTES de instalar Mod5, solo con autorizacion futura.
-- No crea usuarios, claves, aperturas ni habilita Kardex. Nunca toca productos existentes.
-- El DBA debe establecer SESSION_CONTEXT(N'P3_BOD.TestActor') con un Administrador activo.
SET NOCOUNT ON; SET XACT_ABORT ON;
IF DB_NAME() COLLATE Latin1_General_100_BIN2<>N'SecureFinanceERP_Lab_Dylan' OR DATALENGTH(DB_NAME())<>DATALENGTH(N'SecureFinanceERP_Lab_Dylan') OR @@TRANCOUNT<>0
 THROW 58000,'Fixture exclusivo del laboratorio Dylan.',1;
IF OBJECT_ID('dbo.P3_BOD_Bodega','U') IS NOT NULL OR EXISTS(SELECT 1 FROM dbo.ConfiguracionInventario WHERE Habilitado=1)
 OR EXISTS(SELECT 1 FROM dbo.Apertura_Inventario) THROW 58000,'Fixture requiere copia nueva, Mod5 ausente y Kardex sin apertura.',1;
DECLARE @Actor INT=TRY_CONVERT(INT,SESSION_CONTEXT(N'P3_BOD.TestActor')),@Proveedor INT,@Producto INT,@Op UNIQUEIDENTIFIER=NEWID();
EXEC dbo.sp_ParteII_ValidarPermiso @Actor,N'PRODUCTOS_ADMINISTRAR';
IF EXISTS(SELECT 1 FROM dbo.Producto WHERE Codigo=N'P3BOD-QA-100') THROW 58000,'Fixture ya existe; no duplicar.',1;
BEGIN TRY
 BEGIN TRANSACTION;
 EXEC sys.sp_set_session_context @key=N'ParteII.Actor',@value=@Actor;
 EXEC sys.sp_set_session_context @key=N'ParteII.Operacion',@value=@Op;
 INSERT dbo.Proveedor(NIT,Nombre) VALUES(N'P3BODQA100',N'PROVEEDOR SINTETICO MOD5');
 SET @Proveedor=CONVERT(INT,SCOPE_IDENTITY());
 INSERT dbo.Producto(Codigo,Descripcion,Precio,PrecioCosto,ProveedorId,Stock)
 VALUES(N'P3BOD-QA-100',N'FIXTURE SINTETICO 100 UNIDADES A COSTO 20 - NO COMERCIAL',100.00,20.00,@Proveedor,100);
 SET @Producto=CONVERT(INT,SCOPE_IDENTITY());
 INSERT dbo.Producto(Codigo,Descripcion,Precio,PrecioCosto,ProveedorId,Stock)
 VALUES(N'P3BOD-QA-COST0',N'FIXTURE SINTETICO STOCK CERO COSTO DESCONOCIDO - NO COMERCIAL',100.00,NULL,@Proveedor,0);
 COMMIT;
 EXEC sys.sp_set_session_context @key=N'ParteII.Actor',@value=NULL;
 EXEC sys.sp_set_session_context @key=N'ParteII.Operacion',@value=NULL;
 SELECT @Producto ProductoId,@Proveedor ProveedorId,N'Fixture real de laboratorio, no historia Kardex.' Nota;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK;
 EXEC sys.sp_set_session_context @key=N'ParteII.Actor',@value=NULL;
 EXEC sys.sp_set_session_context @key=N'ParteII.Operacion',@value=NULL;
 THROW;
END CATCH;
