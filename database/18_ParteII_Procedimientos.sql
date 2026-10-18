SET NOCOUNT ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
BEGIN TRY
 BEGIN TRANSACTION;
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId INT, @Permiso NVARCHAR(100)
AS
BEGIN
 SET NOCOUNT ON;
 SET ANSI_WARNINGS ON;
 SET ARITHABORT ON;
 SET CONCAT_NULL_YIELDS_NULL ON;
 SET NUMERIC_ROUNDABORT OFF;
 IF NOT EXISTS(SELECT 1 FROM dbo.Usuario u WITH(HOLDLOCK)
 JOIN dbo.Usuario_Rol ur WITH(HOLDLOCK) ON ur.UsuarioId=u.UsuarioId
 JOIN dbo.Rol r WITH(HOLDLOCK) ON r.RolId=ur.RolId AND r.Activo=1
 JOIN dbo.Rol_Permiso rp WITH(HOLDLOCK) ON rp.RolId=r.RolId
 JOIN dbo.Permiso p WITH(HOLDLOCK) ON p.PermisoId=rp.PermisoId AND p.Activo=1
 WHERE u.UsuarioId=@ActorUsuarioId AND u.Activo=1 AND p.Codigo=@Permiso)
 THROW 54101, ''Usuario inactivo o permiso insuficiente.'', 1;
END;';
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.sp_RegistrarProveedor @ActorUsuarioId INT, @NIT NVARCHAR(MAX), @Nombre NVARCHAR(MAX), @Correo NVARCHAR(MAX)=NULL, @Telefono NVARCHAR(MAX)=NULL, @Direccion NVARCHAR(MAX)=NULL, @Fotografia VARCHAR(MAX)=NULL, @ProveedorId INT=NULL OUTPUT
AS
BEGIN
 SET NOCOUNT ON;
 SET ANSI_WARNINGS ON;
 SET ARITHABORT ON;
 SET CONCAT_NULL_YIELDS_NULL ON;
 SET NUMERIC_ROUNDABORT OFF;
 SET XACT_ABORT ON;
 EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=NULL;
 BEGIN TRY
  BEGIN TRANSACTION;
  EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId, N''PROVEEDORES_ADMINISTRAR'';
  EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=@ActorUsuarioId;
  SET @NIT=UPPER(REPLACE(LTRIM(RTRIM(@NIT)),N''-'',N''''));
  IF @NIT IS NULL OR LEN(LTRIM(RTRIM(@NIT)))=0 OR DATALENGTH(@NIT)>50 OR @NIT COLLATE Latin1_General_100_BIN2 LIKE N''%[^0-9A-Z]%'' THROW 54102, ''NIT invalido; use letras y numeros sin separadores.'', 1;
  SET @Nombre=LTRIM(RTRIM(@Nombre));
  IF @Nombre IS NULL OR LEN(LTRIM(RTRIM(@Nombre)))=0 OR DATALENGTH(@Nombre)>300 OR DATALENGTH(@Correo)>508 OR DATALENGTH(@Telefono)>50 OR DATALENGTH(@Direccion)>600  THROW 54102, ''Datos de proveedor invalidos.'', 1;
  IF @Fotografia IS NOT NULL AND (DATALENGTH(@Fotografia)<>40 OR RIGHT(@Fotografia,4) COLLATE Latin1_General_100_BIN2 NOT IN (''.jpg'',''.png'') OR TRY_CONVERT(UNIQUEIDENTIFIER,LEFT(@Fotografia,36)) IS NULL OR LEFT(@Fotografia,36) COLLATE Latin1_General_100_BIN2 <> LOWER(CONVERT(CHAR(36),TRY_CONVERT(UNIQUEIDENTIFIER,LEFT(@Fotografia,36))))) THROW 54102, ''Fotografia: solo UUID canonico en minusculas y extension jpg/png.'', 1;
  INSERT dbo.Proveedor(NIT,Nombre,Correo,Telefono,Direccion,Fotografia) VALUES(@NIT,@Nombre,@Correo,@Telefono,@Direccion,@Fotografia);
  SET @ProveedorId=CONVERT(INT,SCOPE_IDENTITY());
  SELECT ProveedorId,NIT,Nombre,Correo,Telefono,Direccion,Fotografia,Activo,FechaCreacion,Version FROM dbo.Proveedor WHERE ProveedorId=@ProveedorId;
  COMMIT TRANSACTION;
  EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=NULL;
  EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=NULL;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
  EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=NULL;
  EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=NULL;
  THROW;
 END CATCH;
END;';
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.sp_ActualizarProveedor @ActorUsuarioId INT, @NIT NVARCHAR(MAX), @Nombre NVARCHAR(MAX), @Correo NVARCHAR(MAX)=NULL, @Telefono NVARCHAR(MAX)=NULL, @Direccion NVARCHAR(MAX)=NULL, @Fotografia VARCHAR(MAX)=NULL, @ProveedorId INT=NULL, @VersionEsperada BINARY(8)=NULL, @Activo BIT=1
AS
BEGIN
 SET NOCOUNT ON;
 SET ANSI_WARNINGS ON;
 SET ARITHABORT ON;
 SET CONCAT_NULL_YIELDS_NULL ON;
 SET NUMERIC_ROUNDABORT OFF;
 SET XACT_ABORT ON;
 EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=NULL;
 BEGIN TRY
  BEGIN TRANSACTION;
  EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId, N''PROVEEDORES_ADMINISTRAR'';
  EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=@ActorUsuarioId;
  SET @NIT=UPPER(REPLACE(LTRIM(RTRIM(@NIT)),N''-'',N''''));
  IF @NIT IS NULL OR LEN(LTRIM(RTRIM(@NIT)))=0 OR DATALENGTH(@NIT)>50 OR @NIT COLLATE Latin1_General_100_BIN2 LIKE N''%[^0-9A-Z]%'' THROW 54102, ''NIT invalido; use letras y numeros sin separadores.'', 1;
  SET @Nombre=LTRIM(RTRIM(@Nombre));
  IF @Nombre IS NULL OR LEN(LTRIM(RTRIM(@Nombre)))=0 OR DATALENGTH(@Nombre)>300 OR DATALENGTH(@Correo)>508 OR DATALENGTH(@Telefono)>50 OR DATALENGTH(@Direccion)>600 OR @Activo IS NULL THROW 54102, ''Datos de proveedor invalidos.'', 1;
  IF @Fotografia IS NOT NULL AND (DATALENGTH(@Fotografia)<>40 OR RIGHT(@Fotografia,4) COLLATE Latin1_General_100_BIN2 NOT IN (''.jpg'',''.png'') OR TRY_CONVERT(UNIQUEIDENTIFIER,LEFT(@Fotografia,36)) IS NULL OR LEFT(@Fotografia,36) COLLATE Latin1_General_100_BIN2 <> LOWER(CONVERT(CHAR(36),TRY_CONVERT(UNIQUEIDENTIFIER,LEFT(@Fotografia,36))))) THROW 54102, ''Fotografia: solo UUID canonico en minusculas y extension jpg/png.'', 1;
  IF @VersionEsperada IS NULL OR NOT EXISTS(SELECT 1 FROM dbo.Proveedor WITH(UPDLOCK,HOLDLOCK) WHERE ProveedorId=@ProveedorId AND Version=@VersionEsperada) THROW 54103, ''Proveedor inexistente o version obsoleta.'', 1;
  UPDATE dbo.Proveedor SET NIT=@NIT,Nombre=@Nombre,Correo=@Correo,Telefono=@Telefono,Direccion=@Direccion,Fotografia=@Fotografia,Activo=@Activo WHERE ProveedorId=@ProveedorId;
  SELECT ProveedorId,NIT,Nombre,Correo,Telefono,Direccion,Fotografia,Activo,FechaCreacion,Version FROM dbo.Proveedor WHERE ProveedorId=@ProveedorId;
  COMMIT TRANSACTION;
  EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=NULL;
  EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=NULL;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
  EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=NULL;
  EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=NULL;
  THROW;
 END CATCH;
END;';
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.sp_RegistrarProducto @ActorUsuarioId INT, @Codigo NVARCHAR(MAX), @Descripcion NVARCHAR(MAX), @Precio DECIMAL(12,2), @PrecioCosto DECIMAL(12,2), @ProveedorId INT, @StockMinimo INT=5, @PuntoReorden INT=5, @GarantiaMeses SMALLINT=0, @Fotografia VARCHAR(MAX)=NULL, @ProductoId INT=NULL OUTPUT
AS
BEGIN
 SET NOCOUNT ON;
 SET ANSI_WARNINGS ON;
 SET ARITHABORT ON;
 SET CONCAT_NULL_YIELDS_NULL ON;
 SET NUMERIC_ROUNDABORT OFF;
 SET XACT_ABORT ON;
 EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=NULL;
 BEGIN TRY
  BEGIN TRANSACTION;
  EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId, N''PRODUCTOS_ADMINISTRAR'';
  EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=@ActorUsuarioId;
  SET @Codigo=LTRIM(RTRIM(@Codigo)); SET @Descripcion=LTRIM(RTRIM(@Descripcion));
  IF @Codigo IS NULL OR LEN(LTRIM(RTRIM(@Codigo)))=0 OR DATALENGTH(@Codigo)>80 OR @Descripcion IS NULL OR LEN(LTRIM(RTRIM(@Descripcion)))=0 OR DATALENGTH(@Descripcion)>400 OR @Precio IS NULL OR @Precio<0 OR @PrecioCosto IS NULL OR @PrecioCosto<0 OR @StockMinimo IS NULL OR @StockMinimo<0 OR @PuntoReorden IS NULL OR @PuntoReorden<@StockMinimo OR @GarantiaMeses IS NULL OR @GarantiaMeses<0  THROW 54102, ''Datos de producto invalidos.'', 1;
  IF @Fotografia IS NOT NULL AND (DATALENGTH(@Fotografia)<>40 OR RIGHT(@Fotografia,4) COLLATE Latin1_General_100_BIN2 NOT IN (''.jpg'',''.png'') OR TRY_CONVERT(UNIQUEIDENTIFIER,LEFT(@Fotografia,36)) IS NULL OR LEFT(@Fotografia,36) COLLATE Latin1_General_100_BIN2 <> LOWER(CONVERT(CHAR(36),TRY_CONVERT(UNIQUEIDENTIFIER,LEFT(@Fotografia,36))))) THROW 54102, ''Fotografia: solo UUID canonico en minusculas y extension jpg/png.'', 1;
  IF NOT EXISTS(SELECT 1 FROM dbo.Proveedor WITH(HOLDLOCK) WHERE ProveedorId=@ProveedorId AND Activo=1) THROW 54104, ''Proveedor inexistente o inactivo.'', 1;
  INSERT dbo.Producto(Codigo,Descripcion,Precio,PrecioCosto,ProveedorId,StockMinimo,PuntoReorden,GarantiaMeses,Fotografia) VALUES(@Codigo,@Descripcion,@Precio,@PrecioCosto,@ProveedorId,@StockMinimo,@PuntoReorden,@GarantiaMeses,@Fotografia);
  SET @ProductoId=CONVERT(INT,SCOPE_IDENTITY());
  SELECT ProductoId,Codigo,Descripcion,Precio,Stock,PrecioCosto,ProveedorId,StockMinimo,PuntoReorden,GarantiaMeses,Fotografia,Activo,FechaCreacion,Version FROM dbo.Producto WHERE ProductoId=@ProductoId;
  COMMIT TRANSACTION;
  EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=NULL;
  EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=NULL;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
  EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=NULL;
  EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=NULL;
  THROW;
 END CATCH;
END;';
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.sp_ActualizarProducto @ActorUsuarioId INT, @Codigo NVARCHAR(MAX), @Descripcion NVARCHAR(MAX), @Precio DECIMAL(12,2), @PrecioCosto DECIMAL(12,2), @ProveedorId INT, @StockMinimo INT=5, @PuntoReorden INT=5, @GarantiaMeses SMALLINT=0, @Fotografia VARCHAR(MAX)=NULL, @ProductoId INT=NULL, @VersionEsperada BINARY(8)=NULL, @Activo BIT=1
AS
BEGIN
 SET NOCOUNT ON;
 SET ANSI_WARNINGS ON;
 SET ARITHABORT ON;
 SET CONCAT_NULL_YIELDS_NULL ON;
 SET NUMERIC_ROUNDABORT OFF;
 SET XACT_ABORT ON;
 EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=NULL;
 BEGIN TRY
  BEGIN TRANSACTION;
  EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId, N''PRODUCTOS_ADMINISTRAR'';
  EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=@ActorUsuarioId;
  SET @Codigo=LTRIM(RTRIM(@Codigo)); SET @Descripcion=LTRIM(RTRIM(@Descripcion));
  IF @Codigo IS NULL OR LEN(LTRIM(RTRIM(@Codigo)))=0 OR DATALENGTH(@Codigo)>80 OR @Descripcion IS NULL OR LEN(LTRIM(RTRIM(@Descripcion)))=0 OR DATALENGTH(@Descripcion)>400 OR @Precio IS NULL OR @Precio<0 OR @PrecioCosto IS NULL OR @PrecioCosto<0 OR @StockMinimo IS NULL OR @StockMinimo<0 OR @PuntoReorden IS NULL OR @PuntoReorden<@StockMinimo OR @GarantiaMeses IS NULL OR @GarantiaMeses<0 OR @Activo IS NULL THROW 54102, ''Datos de producto invalidos.'', 1;
  IF @Fotografia IS NOT NULL AND (DATALENGTH(@Fotografia)<>40 OR RIGHT(@Fotografia,4) COLLATE Latin1_General_100_BIN2 NOT IN (''.jpg'',''.png'') OR TRY_CONVERT(UNIQUEIDENTIFIER,LEFT(@Fotografia,36)) IS NULL OR LEFT(@Fotografia,36) COLLATE Latin1_General_100_BIN2 <> LOWER(CONVERT(CHAR(36),TRY_CONVERT(UNIQUEIDENTIFIER,LEFT(@Fotografia,36))))) THROW 54102, ''Fotografia: solo UUID canonico en minusculas y extension jpg/png.'', 1;
  IF NOT EXISTS(SELECT 1 FROM dbo.Proveedor WITH(HOLDLOCK) WHERE ProveedorId=@ProveedorId AND Activo=1) THROW 54104, ''Proveedor inexistente o inactivo.'', 1;
  IF @VersionEsperada IS NULL OR NOT EXISTS(SELECT 1 FROM dbo.Producto WITH(UPDLOCK,HOLDLOCK) WHERE ProductoId=@ProductoId AND Version=@VersionEsperada) THROW 54103, ''Producto inexistente o version obsoleta.'', 1;
  UPDATE dbo.Producto SET Codigo=@Codigo,Descripcion=@Descripcion,Precio=@Precio,PrecioCosto=@PrecioCosto,ProveedorId=@ProveedorId,StockMinimo=@StockMinimo,PuntoReorden=@PuntoReorden,GarantiaMeses=@GarantiaMeses,Fotografia=@Fotografia,Activo=@Activo WHERE ProductoId=@ProductoId;
  SELECT ProductoId,Codigo,Descripcion,Precio,Stock,PrecioCosto,ProveedorId,StockMinimo,PuntoReorden,GarantiaMeses,Fotografia,Activo,FechaCreacion,Version FROM dbo.Producto WHERE ProductoId=@ProductoId;
  COMMIT TRANSACTION;
  EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=NULL;
  EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=NULL;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
  EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=NULL;
  EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=NULL;
  THROW;
 END CATCH;
END;';
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.sp_ActualizarNitCliente @ClienteId INT, @NIT NVARCHAR(MAX), @ActorUsuarioId INT, @VersionEsperada BINARY(8), @Motivo NVARCHAR(MAX)
AS
BEGIN
 SET NOCOUNT ON;
 SET ANSI_WARNINGS ON;
 SET ARITHABORT ON;
 SET CONCAT_NULL_YIELDS_NULL ON;
 SET NUMERIC_ROUNDABORT OFF;
 SET XACT_ABORT ON;
 EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=NULL;
 BEGIN TRY
  BEGIN TRANSACTION;
  EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId, N''CLIENTES_ACTUALIZAR_NIT'';
  EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=@ActorUsuarioId;
  SET @NIT=UPPER(REPLACE(LTRIM(RTRIM(@NIT)),N''-'',N''''));
  IF @NIT IS NULL OR LEN(LTRIM(RTRIM(@NIT)))=0 OR DATALENGTH(@NIT)>50 OR @NIT COLLATE Latin1_General_100_BIN2 LIKE N''%[^0-9A-Z]%'' THROW 54102, ''NIT invalido; use letras y numeros sin separadores.'', 1;
  IF @Motivo IS NULL OR LEN(LTRIM(RTRIM(@Motivo)))=0 OR DATALENGTH(@Motivo)>500 THROW 54102, ''Motivo obligatorio de hasta 250 caracteres.'', 1;
  IF @VersionEsperada IS NULL OR NOT EXISTS(SELECT 1 FROM dbo.Cliente WITH(UPDLOCK,HOLDLOCK) WHERE ClienteId=@ClienteId AND Version=@VersionEsperada) THROW 54103, ''Cliente inexistente o version obsoleta.'', 1;
  DECLARE @MotivoContexto NVARCHAR(250)=@Motivo;
  EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=@MotivoContexto;
  UPDATE dbo.Cliente SET NIT=@NIT WHERE ClienteId=@ClienteId AND (NIT COLLATE Latin1_General_100_BIN2<>@NIT COLLATE Latin1_General_100_BIN2 OR DATALENGTH(NIT)<>DATALENGTH(@NIT));
  EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=NULL;
  SELECT ClienteId,NIT,Nombre,Activo,Version FROM dbo.Cliente WHERE ClienteId=@ClienteId;
  COMMIT TRANSACTION;
  EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=NULL;
  EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=NULL;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
  EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=NULL;
  EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=NULL;
  THROW;
 END CATCH;
END;';
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.sp_InactivarCliente @ClienteId INT, @ActorUsuarioId INT, @VersionEsperada BINARY(8), @Motivo NVARCHAR(MAX)
AS
BEGIN
 SET NOCOUNT ON;
 SET ANSI_WARNINGS ON;
 SET ARITHABORT ON;
 SET CONCAT_NULL_YIELDS_NULL ON;
 SET NUMERIC_ROUNDABORT OFF;
 SET XACT_ABORT ON;
 EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=NULL;
 BEGIN TRY
  BEGIN TRANSACTION;
  EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId, N''CLIENTES_INACTIVAR'';
  EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=@ActorUsuarioId;
  IF @Motivo IS NULL OR LEN(LTRIM(RTRIM(@Motivo)))=0 OR DATALENGTH(@Motivo)>500 THROW 54102, ''Motivo obligatorio de hasta 250 caracteres.'', 1;
  IF @VersionEsperada IS NULL OR NOT EXISTS(SELECT 1 FROM dbo.Cliente WITH(UPDLOCK,HOLDLOCK) WHERE ClienteId=@ClienteId AND Version=@VersionEsperada) THROW 54103, ''Cliente inexistente o version obsoleta.'', 1;
  UPDATE dbo.Cliente SET Activo=0,FechaInactivacion=SYSUTCDATETIME(),MotivoInactivacion=@Motivo WHERE ClienteId=@ClienteId AND Activo=1;
  SELECT ClienteId,NIT,Nombre,Activo,Version FROM dbo.Cliente WHERE ClienteId=@ClienteId;
  COMMIT TRANSACTION;
  EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=NULL;
  EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=NULL;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
  EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=NULL;
  EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=NULL;
  THROW;
 END CATCH;
END;';
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.sp_RegistrarMovimientoKardex @ProductoId INT, @TipoMovimiento VARCHAR(25), @Cantidad INT, @ActorUsuarioId INT,
 @DocumentoRespaldo NVARCHAR(MAX), @OperacionId UNIQUEIDENTIFIER, @LineaOperacion INT,
 @Motivo NVARCHAR(MAX), @DetalleFacturaId INT=NULL, @VersionEsperada BINARY(8)=NULL
AS
BEGIN
 SET NOCOUNT ON;
 SET ANSI_WARNINGS ON;
 SET ARITHABORT ON;
 SET CONCAT_NULL_YIELDS_NULL ON;
 SET NUMERIC_ROUNDABORT OFF;
 SET XACT_ABORT ON;
 EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=NULL;
 BEGIN TRY
  BEGIN TRANSACTION;

  DECLARE @Permiso NVARCHAR(100)=CASE WHEN @TipoMovimiento IN (''AJUSTE_INGRESO'',''AJUSTE_EGRESO'') THEN N''INVENTARIO_AJUSTAR'' WHEN @TipoMovimiento=''VENTA'' THEN N''VENTAS_REGISTRAR'' ELSE N''INVENTARIO_REGISTRAR'' END;
  EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,@Permiso;
  EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=@ActorUsuarioId;
  EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=@OperacionId;
  IF NOT EXISTS(SELECT 1 FROM dbo.ConfiguracionInventario WITH(HOLDLOCK) WHERE ConfiguracionId=1 AND Habilitado=1) THROW 54110, ''Kardex deshabilitado: requiere apertura e integracion aprobadas.'', 1;
  IF @OperacionId IS NULL OR @LineaOperacion IS NULL OR @LineaOperacion<=0 OR @Cantidad IS NULL OR @Cantidad<=0 OR @TipoMovimiento IS NULL OR @TipoMovimiento NOT IN (''COMPRA'',''VENTA'',''AJUSTE_INGRESO'',''AJUSTE_EGRESO'',''DEVOLUCION'') OR @DocumentoRespaldo IS NULL OR LEN(LTRIM(RTRIM(@DocumentoRespaldo)))=0 OR DATALENGTH(@DocumentoRespaldo)>200 OR @Motivo IS NULL OR LEN(LTRIM(RTRIM(@Motivo)))=0 OR DATALENGTH(@Motivo)>500 THROW 54102, ''Movimiento invalido.'', 1;
  IF (@TipoMovimiento=''VENTA'' AND @DetalleFacturaId IS NULL) OR (@TipoMovimiento<>''VENTA'' AND @DetalleFacturaId IS NOT NULL) THROW 54102, ''Referencia de venta incompatible.'', 1;
  IF @TipoMovimiento IN (''AJUSTE_INGRESO'',''AJUSTE_EGRESO'') AND @VersionEsperada IS NULL THROW 54103, ''El ajuste requiere version esperada.'', 1;
  DECLARE @Lock INT, @Resource NVARCHAR(255)=CONCAT(N''ParteII.Kardex.'',CONVERT(NVARCHAR(36),@OperacionId),N''.'',@LineaOperacion);
  EXEC @Lock=sys.sp_getapplock @Resource=@Resource,@LockMode=''Exclusive'',@LockOwner=''Transaction'',@LockTimeout=10000;
  IF @Lock<0 THROW 54111, ''No fue posible bloquear la operacion.'', 1;
  DECLARE @Existente BIGINT=(SELECT KardexId FROM dbo.Kardex_Inventario WITH(UPDLOCK,HOLDLOCK) WHERE OperacionId=@OperacionId AND LineaOperacion=@LineaOperacion);
  IF @Existente IS NOT NULL
  BEGIN
   IF NOT EXISTS(SELECT 1 FROM dbo.Kardex_Inventario WHERE KardexId=@Existente AND ProductoId=@ProductoId AND TipoMovimiento=@TipoMovimiento AND Cantidad=@Cantidad AND UsuarioId=@ActorUsuarioId AND DocumentoRespaldo COLLATE Latin1_General_100_BIN2=@DocumentoRespaldo COLLATE Latin1_General_100_BIN2 AND DATALENGTH(DocumentoRespaldo)=DATALENGTH(@DocumentoRespaldo) AND Motivo COLLATE Latin1_General_100_BIN2=@Motivo COLLATE Latin1_General_100_BIN2 AND DATALENGTH(Motivo)=DATALENGTH(@Motivo) AND (DetalleFacturaId=@DetalleFacturaId OR (DetalleFacturaId IS NULL AND @DetalleFacturaId IS NULL))) THROW 54112, ''Clave idempotente reutilizada con datos distintos.'', 1;
  END
  ELSE
  BEGIN
   DECLARE @Stock INT,@Version BINARY(8),@Nuevo BIGINT;
   SELECT @Stock=Stock,@Version=Version FROM dbo.Producto WITH(UPDLOCK,HOLDLOCK) WHERE ProductoId=@ProductoId AND Activo=1;
   IF @Stock IS NULL THROW 54104, ''Producto inexistente o inactivo.'', 1;
   IF @VersionEsperada IS NOT NULL AND @Version<>@VersionEsperada THROW 54103, ''Version de producto obsoleta.'', 1;
   IF @TipoMovimiento=''VENTA'' AND NOT EXISTS(SELECT 1 FROM dbo.DetalleFactura WITH(HOLDLOCK) WHERE DetalleFacturaId=@DetalleFacturaId AND ProductoId=@ProductoId AND Cantidad=@Cantidad) THROW 54104, ''Detalle de venta incompatible.'', 1;
   SET @Nuevo=CONVERT(BIGINT,@Stock)+CASE WHEN @TipoMovimiento IN (''VENTA'',''AJUSTE_EGRESO'') THEN -CONVERT(BIGINT,@Cantidad) ELSE CONVERT(BIGINT,@Cantidad) END;
   IF @Nuevo<0 OR @Nuevo>2147483647 THROW 54113, ''Stock insuficiente o fuera de rango.'', 1;
   UPDATE dbo.Producto SET Stock=CONVERT(INT,@Nuevo) WHERE ProductoId=@ProductoId;
   INSERT dbo.Kardex_Inventario(OperacionId,LineaOperacion,ProductoId,TipoMovimiento,Cantidad,UsuarioId,DocumentoRespaldo,DetalleFacturaId,StockAnterior,StockResultante,Motivo)
   VALUES(@OperacionId,@LineaOperacion,@ProductoId,@TipoMovimiento,@Cantidad,@ActorUsuarioId,@DocumentoRespaldo,@DetalleFacturaId,@Stock,CONVERT(INT,@Nuevo),@Motivo);
   SET @Existente=CONVERT(BIGINT,SCOPE_IDENTITY());
  END;
  SELECT KardexId,OperacionId,LineaOperacion,ProductoId,TipoMovimiento,Cantidad,FechaHora,UsuarioId,DocumentoRespaldo,DetalleFacturaId,StockAnterior,StockResultante,Motivo FROM dbo.Kardex_Inventario WHERE KardexId=@Existente;
  COMMIT TRANSACTION;
  EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=NULL;
  EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=NULL;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
  EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=NULL;
  EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=NULL;
  THROW;
 END CATCH;
END;';
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.sp_ConsultarProveedores @ActorUsuarioId INT, @Desplazamiento INT=0, @Limite INT=100
AS
BEGIN
 SET NOCOUNT ON;
 SET ANSI_WARNINGS ON;
 SET ARITHABORT ON;
 SET CONCAT_NULL_YIELDS_NULL ON;
 SET NUMERIC_ROUNDABORT OFF;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N''PROVEEDORES_CONSULTAR'';
 IF @Desplazamiento IS NULL OR @Desplazamiento<0 OR @Limite IS NULL OR @Limite NOT BETWEEN 1 AND 500 THROW 54102, ''Paginacion invalida.'', 1;

 SELECT ProveedorId,NIT,Nombre,Correo,Telefono,Direccion,Fotografia,Activo,FechaCreacion,Version FROM dbo.Proveedor ORDER BY Nombre,ProveedorId OFFSET @Desplazamiento ROWS FETCH NEXT @Limite ROWS ONLY;
END;';
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.sp_ConsultarProductos @ActorUsuarioId INT, @Desplazamiento INT=0, @Limite INT=100, @IncluirCosto BIT=0
AS
BEGIN
 SET NOCOUNT ON;
 SET ANSI_WARNINGS ON;
 SET ARITHABORT ON;
 SET CONCAT_NULL_YIELDS_NULL ON;
 SET NUMERIC_ROUNDABORT OFF;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N''PRODUCTOS_CONSULTAR'';
 IF @IncluirCosto IS NULL THROW 54102, ''Indicador de costo invalido.'',1;
 IF @IncluirCosto=1 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N''PRODUCTOS_ADMINISTRAR'';
 IF @Desplazamiento IS NULL OR @Desplazamiento<0 OR @Limite IS NULL OR @Limite NOT BETWEEN 1 AND 500 THROW 54102, ''Paginacion invalida.'', 1;

 SELECT ProductoId,Codigo,Descripcion,Precio,CASE WHEN @IncluirCosto=1 THEN PrecioCosto END AS PrecioCosto,Stock,ProveedorId,Fotografia,StockMinimo,PuntoReorden,GarantiaMeses,Activo,FechaCreacion,Version FROM dbo.Producto ORDER BY Descripcion,ProductoId OFFSET @Desplazamiento ROWS FETCH NEXT @Limite ROWS ONLY;
END;';
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.sp_ConsultarClientesAdministracion @ActorUsuarioId INT, @Desplazamiento INT=0, @Limite INT=100
AS
BEGIN
 SET NOCOUNT ON;
 SET ANSI_WARNINGS ON;
 SET ARITHABORT ON;
 SET CONCAT_NULL_YIELDS_NULL ON;
 SET NUMERIC_ROUNDABORT OFF;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N''CLIENTES_CONSULTAR'';
 IF @Desplazamiento IS NULL OR @Desplazamiento<0 OR @Limite IS NULL OR @Limite NOT BETWEEN 1 AND 500 THROW 54102, ''Paginacion invalida.'', 1;

 SELECT ClienteId,NIT,Nombre,Correo,Telefono,Activo,FechaCreacion,FechaInactivacion,MotivoInactivacion,Version FROM dbo.Cliente ORDER BY Nombre,ClienteId OFFSET @Desplazamiento ROWS FETCH NEXT @Limite ROWS ONLY;
END;';
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.sp_ConsultarKardex @ActorUsuarioId INT, @Desplazamiento INT=0, @Limite INT=100, @ProductoId INT=NULL, @Desde DATETIME2(3)=NULL, @Hasta DATETIME2(3)=NULL
AS
BEGIN
 SET NOCOUNT ON;
 SET ANSI_WARNINGS ON;
 SET ARITHABORT ON;
 SET CONCAT_NULL_YIELDS_NULL ON;
 SET NUMERIC_ROUNDABORT OFF;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N''INVENTARIO_CONSULTAR'';
 IF @Desplazamiento IS NULL OR @Desplazamiento<0 OR @Limite IS NULL OR @Limite NOT BETWEEN 1 AND 500 THROW 54102, ''Paginacion invalida.'', 1;
 IF @Desde>=@Hasta THROW 54102, ''Periodo invalido.'', 1;
 SELECT KardexId,OperacionId,LineaOperacion,ProductoId,TipoMovimiento,Cantidad,FechaHora,UsuarioId,DocumentoRespaldo,DetalleFacturaId,StockAnterior,StockResultante,Motivo FROM dbo.Kardex_Inventario WHERE (@ProductoId IS NULL OR ProductoId=@ProductoId) AND (@Desde IS NULL OR FechaHora>=@Desde) AND (@Hasta IS NULL OR FechaHora<@Hasta) ORDER BY FechaHora,KardexId OFFSET @Desplazamiento ROWS FETCH NEXT @Limite ROWS ONLY;
END;';
 COMMIT TRANSACTION;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 THROW;
END CATCH;
GO
