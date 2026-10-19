-- Parte II fase 2. Ejecutar en el contexto destino explicitamente seleccionado.
-- Instala DESHABILITADO: apertura y habilitacion son acciones separadas del DBA.
-- Requiere 15..20. No contiene USE, apertura automatica ni cambios de Stock.
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
SET XACT_ABORT ON;
IF DB_NAME() IN ('master','model','msdb','tempdb') THROW 54400,'Seleccione la base de aplicacion o de prueba.',1;
IF OBJECT_ID('dbo.sp_RegistrarMovimientoKardex','P') IS NULL OR COL_LENGTH('dbo.Producto','Version') IS NULL OR COL_LENGTH('dbo.Bitacora_Transacciones','ActorUsuarioId') IS NULL THROW 54400,'Instale 15..20 antes de 21.',1;
BEGIN TRY
 BEGIN TRANSACTION;

 IF OBJECT_ID('dbo.Apertura_Inventario','U') IS NULL
 CREATE TABLE dbo.Apertura_Inventario(
  AperturaId UNIQUEIDENTIFIER CONSTRAINT PK_Apertura_Inventario PRIMARY KEY,
  CorteUnico TINYINT NOT NULL CONSTRAINT DF_Apertura_Corte DEFAULT 1 CONSTRAINT UQ_Apertura_Corte UNIQUE CONSTRAINT CK_Apertura_Corte CHECK(CorteUnico=1),
  UsuarioId INT NOT NULL CONSTRAINT FK_Apertura_Usuario REFERENCES dbo.Usuario(UsuarioId),
  FechaHora DATETIME2(3) NOT NULL CONSTRAINT DF_Apertura_Fecha DEFAULT SYSUTCDATETIME(),
  DocumentoRespaldo NVARCHAR(100) NOT NULL CONSTRAINT UQ_Apertura_Documento UNIQUE,
  Motivo NVARCHAR(250) NOT NULL,
  FacturaLimiteId INT NOT NULL CONSTRAINT CK_Apertura_FacturaLimite CHECK(FacturaLimiteId>=0),
  ProductosRegistrados BIGINT NOT NULL CONSTRAINT CK_Apertura_Productos CHECK(ProductosRegistrados>=0),
  CONSTRAINT CK_Apertura_Texto CHECK(LEN(LTRIM(RTRIM(DocumentoRespaldo)))>0 AND LEN(LTRIM(RTRIM(Motivo)))>0)
 );
 IF COL_LENGTH('dbo.Apertura_Inventario','FacturaLimiteId') IS NULL
 BEGIN
  IF EXISTS(SELECT 1 FROM dbo.Apertura_Inventario) THROW 54400,'No se reconstruye el limite de un corte anterior desconocido.',1;
  EXEC sys.sp_executesql N'ALTER TABLE dbo.Apertura_Inventario ADD FacturaLimiteId INT NOT NULL CONSTRAINT DF_Apertura_FacturaLimite DEFAULT 0 WITH VALUES;';
 END;
 IF COL_LENGTH('dbo.ConfiguracionInventario','IntegracionVersion') IS NULL
 EXEC sys.sp_executesql N'ALTER TABLE dbo.ConfiguracionInventario ADD IntegracionVersion SMALLINT NOT NULL CONSTRAINT DF_Configuracion_Integracion DEFAULT 0 WITH VALUES;';
 IF COL_LENGTH('dbo.ConfiguracionInventario','AperturaId') IS NULL
 EXEC sys.sp_executesql N'ALTER TABLE dbo.ConfiguracionInventario ADD AperturaId UNIQUEIDENTIFIER NULL CONSTRAINT FK_Configuracion_Apertura REFERENCES dbo.Apertura_Inventario(AperturaId);';
 IF COL_LENGTH('dbo.Kardex_Inventario','AperturaId') IS NULL
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Kardex_Inventario ADD AperturaId UNIQUEIDENTIFIER NULL CONSTRAINT FK_Kardex_Apertura REFERENCES dbo.Apertura_Inventario(AperturaId);';
 IF EXISTS(SELECT 1 FROM dbo.ConfiguracionInventario WHERE Habilitado=1) AND NOT EXISTS(SELECT 1 FROM dbo.Apertura_Inventario)
 THROW 54400,'Deshabilite escritores y concilie antes de instalar; no se acepta Kardex activo sin apertura.',1;
 ALTER TABLE dbo.Kardex_Inventario DROP CONSTRAINT CK_Kardex_Tipo;
 ALTER TABLE dbo.Kardex_Inventario WITH CHECK ADD CONSTRAINT CK_Kardex_Tipo CHECK(TipoMovimiento IN ('COMPRA','VENTA','AJUSTE_INGRESO','AJUSTE_EGRESO','DEVOLUCION','APERTURA'));
 ALTER TABLE dbo.Kardex_Inventario DROP CONSTRAINT CK_Kardex_Cantidad;
 ALTER TABLE dbo.Kardex_Inventario WITH CHECK ADD CONSTRAINT CK_Kardex_Cantidad CHECK(Cantidad>0 OR (TipoMovimiento='APERTURA' AND Cantidad=0));
 IF OBJECT_ID('dbo.CK_Kardex_Apertura','C') IS NULL
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Kardex_Inventario WITH CHECK ADD CONSTRAINT CK_Kardex_Apertura CHECK((TipoMovimiento=''APERTURA'' AND AperturaId IS NOT NULL AND StockAnterior=0 AND StockResultante=Cantidad AND OperacionId=AperturaId AND LineaOperacion=ProductoId) OR (TipoMovimiento<>''APERTURA'' AND AperturaId IS NULL));';
 IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.Kardex_Inventario') AND name='UX_Kardex_AperturaProducto')
 EXEC sys.sp_executesql N'CREATE UNIQUE INDEX UX_Kardex_AperturaProducto ON dbo.Kardex_Inventario(ProductoId) WHERE TipoMovimiento=''APERTURA'';';
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.sp_AbrirKardexInventario @AperturaId UNIQUEIDENTIFIER,@ActorUsuarioId INT,@DocumentoRespaldo NVARCHAR(MAX),@Motivo NVARCHAR(MAX)
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 SET ANSI_WARNINGS ON;
 SET ARITHABORT ON;
 SET CONCAT_NULL_YIELDS_NULL ON;
 SET NUMERIC_ROUNDABORT OFF;
 DECLARE @Propia BIT=CASE WHEN @@TRANCOUNT=0 THEN 1 ELSE 0 END;
 EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=NULL;
 BEGIN TRY
  IF @Propia=1 BEGIN TRANSACTION;
  DECLARE @Bloqueo INT;
  EXEC @Bloqueo=sys.sp_getapplock @Resource=N''InventarioCorteParteII'',@LockMode=''Exclusive'',@LockOwner=''Transaction'',@LockTimeout=10000;
  IF @Bloqueo<0 THROW 54401,''No se obtuvo bloqueo exclusivo de corte.'',1;
  EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N''INVENTARIO_APERTURAR'';

  IF @AperturaId IS NULL OR @DocumentoRespaldo IS NULL OR LEN(LTRIM(RTRIM(@DocumentoRespaldo)))=0 OR DATALENGTH(@DocumentoRespaldo)>200 OR @Motivo IS NULL OR LEN(LTRIM(RTRIM(@Motivo)))=0 OR DATALENGTH(@Motivo)>500 THROW 54402,''Datos de apertura invalidos.'',1;
  IF EXISTS(SELECT 1 FROM dbo.Apertura_Inventario WITH(UPDLOCK,HOLDLOCK))
  BEGIN
   IF NOT EXISTS(SELECT 1 FROM dbo.Apertura_Inventario WHERE AperturaId=@AperturaId AND UsuarioId=@ActorUsuarioId AND CONVERT(VARBINARY(MAX),DocumentoRespaldo)=CONVERT(VARBINARY(MAX),@DocumentoRespaldo) AND CONVERT(VARBINARY(MAX),Motivo)=CONVERT(VARBINARY(MAX),@Motivo)) THROW 54403,''Ya existe otro corte o cambio el contenido del reintento.'',1;
   IF (SELECT COUNT_BIG(*) FROM dbo.Kardex_Inventario WHERE AperturaId=@AperturaId)<>(SELECT ProductosRegistrados FROM dbo.Apertura_Inventario WHERE AperturaId=@AperturaId) THROW 54404,''Apertura incompleta.'',1;
  END
  ELSE
  BEGIN
   IF EXISTS(SELECT 1 FROM dbo.ConfiguracionInventario WITH(UPDLOCK,HOLDLOCK) WHERE Habilitado=1) OR EXISTS(SELECT 1 FROM dbo.Kardex_Inventario) THROW 54404,''El corte inicial requiere inventario deshabilitado y libro vacio.'',1;
   DECLARE @Productos BIGINT;
   SELECT @Productos=COUNT_BIG(*) FROM dbo.Producto WITH(TABLOCKX,HOLDLOCK);
   EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=@ActorUsuarioId;
   EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=@AperturaId;
   DECLARE @FacturaLimite INT=(SELECT COALESCE(MAX(FacturaId),0) FROM dbo.Factura WITH(HOLDLOCK));
   INSERT dbo.Apertura_Inventario(AperturaId,UsuarioId,DocumentoRespaldo,Motivo,ProductosRegistrados,FacturaLimiteId) VALUES(@AperturaId,@ActorUsuarioId,@DocumentoRespaldo,@Motivo,@Productos,@FacturaLimite);
   INSERT dbo.Kardex_Inventario(OperacionId,LineaOperacion,ProductoId,TipoMovimiento,Cantidad,UsuarioId,DocumentoRespaldo,StockAnterior,StockResultante,Motivo,AperturaId)
   SELECT @AperturaId,ProductoId,ProductoId,''APERTURA'',Stock,@ActorUsuarioId,@DocumentoRespaldo,0,Stock,@Motivo,@AperturaId FROM dbo.Producto;
   -- No UPDATE Producto: la apertura registra el saldo que ya existe.
   UPDATE dbo.ConfiguracionInventario SET AperturaId=@AperturaId WHERE ConfiguracionId=1;
  END;
  SELECT AperturaId,UsuarioId,FechaHora,DocumentoRespaldo,ProductosRegistrados FROM dbo.Apertura_Inventario WHERE AperturaId=@AperturaId;
  IF @Propia=1 COMMIT TRANSACTION;
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
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.sp_HabilitarKardexInventario @AperturaId UNIQUEIDENTIFIER,@ActorUsuarioId INT
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 SET ANSI_WARNINGS ON;
 SET ARITHABORT ON;
 SET CONCAT_NULL_YIELDS_NULL ON;
 SET NUMERIC_ROUNDABORT OFF;
 DECLARE @Propia BIT=CASE WHEN @@TRANCOUNT=0 THEN 1 ELSE 0 END;
 EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=NULL;
 BEGIN TRY
  IF @Propia=1 BEGIN TRANSACTION;
  DECLARE @Bloqueo INT;
  EXEC @Bloqueo=sys.sp_getapplock @Resource=N''InventarioCorteParteII'',@LockMode=''Exclusive'',@LockOwner=''Transaction'',@LockTimeout=10000;
  IF @Bloqueo<0 THROW 54401,''No se obtuvo bloqueo exclusivo de corte.'',1;
  EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N''INVENTARIO_APERTURAR'';

  IF NOT EXISTS(SELECT 1 FROM dbo.ConfiguracionInventario WITH(UPDLOCK,HOLDLOCK) WHERE ConfiguracionId=1 AND IntegracionVersion=2 AND AperturaId=@AperturaId) THROW 54405,''Falta integrar venta o la apertura no coincide.'',1;
  IF NOT EXISTS(SELECT 1 FROM dbo.Apertura_Inventario WHERE AperturaId=@AperturaId AND ProductosRegistrados=(SELECT COUNT_BIG(*) FROM dbo.Kardex_Inventario WHERE AperturaId=@AperturaId)) THROW 54404,''Apertura incompleta.'',1;
  IF EXISTS(SELECT 1 FROM dbo.Producto p WITH(TABLOCKX,HOLDLOCK) OUTER APPLY(SELECT SUM(CASE WHEN k.TipoMovimiento IN (''VENTA'',''AJUSTE_EGRESO'') THEN -CONVERT(BIGINT,k.Cantidad) ELSE CONVERT(BIGINT,k.Cantidad) END) Saldo FROM dbo.Kardex_Inventario k WHERE k.ProductoId=p.ProductoId) s WHERE CONVERT(BIGINT,p.Stock)<>COALESCE(s.Saldo,0)) THROW 54407,''Stock y libro no concilian.'',1;
  UPDATE dbo.ConfiguracionInventario SET Habilitado=1,FechaActivacion=COALESCE(FechaActivacion,SYSUTCDATETIME()) WHERE ConfiguracionId=1;
  SELECT ConfiguracionId,Habilitado,FechaActivacion,AperturaId,IntegracionVersion FROM dbo.ConfiguracionInventario;
  IF @Propia=1 COMMIT TRANSACTION;
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
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.sp_ConsultarConciliacionInventario @ActorUsuarioId INT
AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N''INVENTARIO_CONSULTAR'';
 SELECT p.ProductoId,p.Codigo,p.Stock,COALESCE(s.Saldo,0) AS SaldoKardex,CONVERT(BIGINT,p.Stock)-COALESCE(s.Saldo,0) AS Diferencia
 FROM dbo.Producto p OUTER APPLY(SELECT SUM(CASE WHEN k.TipoMovimiento IN (''VENTA'',''AJUSTE_EGRESO'') THEN -CONVERT(BIGINT,k.Cantidad) ELSE CONVERT(BIGINT,k.Cantidad) END) Saldo FROM dbo.Kardex_Inventario k WHERE k.ProductoId=p.ProductoId) s ORDER BY p.ProductoId;
END;';
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.sp_RegistrarMovimientoKardex @ProductoId INT, @TipoMovimiento VARCHAR(25), @Cantidad INT, @ActorUsuarioId INT,
 @DocumentoRespaldo NVARCHAR(MAX), @OperacionId UNIQUEIDENTIFIER, @LineaOperacion INT,
 @Motivo NVARCHAR(MAX), @DetalleFacturaId INT=NULL, @VersionEsperada BINARY(8)=NULL, @DevolverResultado BIT=1
AS
BEGIN
 SET NOCOUNT ON;
 SET ANSI_WARNINGS ON;
 SET ARITHABORT ON;
 SET CONCAT_NULL_YIELDS_NULL ON;
 SET NUMERIC_ROUNDABORT OFF;
 SET XACT_ABORT ON;
 DECLARE @Propia BIT=CASE WHEN @@TRANCOUNT=0 THEN 1 ELSE 0 END;
 EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=NULL;
 BEGIN TRY
  IF @Propia=1 BEGIN TRANSACTION;
 DECLARE @BloqueoCorte INT;
 EXEC @BloqueoCorte=sys.sp_getapplock @Resource=N''InventarioCorteParteII'',@LockMode=''Shared'',@LockOwner=''Transaction'',@LockTimeout=10000;
 IF @BloqueoCorte<0 THROW 54401,''No se obtuvo bloqueo de inventario.'',1;
 IF @DevolverResultado IS NULL THROW 54102, ''Indicador de resultado invalido.'',1;

  DECLARE @Permiso NVARCHAR(100)=CASE WHEN @TipoMovimiento IN (''AJUSTE_INGRESO'',''AJUSTE_EGRESO'') THEN N''INVENTARIO_AJUSTAR'' WHEN @TipoMovimiento=''VENTA'' THEN N''VENTAS_REGISTRAR'' ELSE N''INVENTARIO_REGISTRAR'' END;
  EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,@Permiso;
  EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=@ActorUsuarioId;
  EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=@OperacionId;
  IF NOT EXISTS(SELECT 1 FROM dbo.ConfiguracionInventario WITH(HOLDLOCK) WHERE ConfiguracionId=1 AND Habilitado=1 AND IntegracionVersion=2 AND AperturaId IS NOT NULL) THROW 54110, ''Kardex deshabilitado: requiere apertura e integracion aprobadas.'', 1;
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
   DECLARE @SaldoLibro INT=(SELECT TOP(1) StockResultante FROM dbo.Kardex_Inventario WITH(HOLDLOCK) WHERE ProductoId=@ProductoId ORDER BY KardexId DESC);
   IF (@SaldoLibro IS NULL AND @Stock<>0) OR (@SaldoLibro IS NOT NULL AND @SaldoLibro<>@Stock) THROW 54407,''Existencias sin conciliar con el ultimo movimiento.'',1;
   IF @VersionEsperada IS NOT NULL AND @Version<>@VersionEsperada THROW 54103, ''Version de producto obsoleta.'', 1;
   IF @TipoMovimiento=''VENTA'' AND NOT EXISTS(SELECT 1 FROM dbo.DetalleFactura WITH(HOLDLOCK) WHERE DetalleFacturaId=@DetalleFacturaId AND ProductoId=@ProductoId AND Cantidad=@Cantidad) THROW 54104, ''Detalle de venta incompatible.'', 1;
   IF @TipoMovimiento=''VENTA'' AND NOT EXISTS(SELECT 1 FROM dbo.DetalleFactura d JOIN dbo.Factura f ON f.FacturaId=d.FacturaId CROSS JOIN dbo.ConfiguracionInventario c JOIN dbo.Apertura_Inventario a ON a.AperturaId=c.AperturaId WHERE d.DetalleFacturaId=@DetalleFacturaId AND f.FacturaId>a.FacturaLimiteId) THROW 54409,''No se vuelve a descontar una factura anterior al corte.'',1;
   SET @Nuevo=CONVERT(BIGINT,@Stock)+CASE WHEN @TipoMovimiento IN (''VENTA'',''AJUSTE_EGRESO'') THEN -CONVERT(BIGINT,@Cantidad) ELSE CONVERT(BIGINT,@Cantidad) END;
   IF @Nuevo<0 OR @Nuevo>2147483647 THROW 54113, ''Stock insuficiente o fuera de rango.'', 1;
   UPDATE dbo.Producto SET Stock=CONVERT(INT,@Nuevo) WHERE ProductoId=@ProductoId;
   INSERT dbo.Kardex_Inventario(OperacionId,LineaOperacion,ProductoId,TipoMovimiento,Cantidad,UsuarioId,DocumentoRespaldo,DetalleFacturaId,StockAnterior,StockResultante,Motivo)
   VALUES(@OperacionId,@LineaOperacion,@ProductoId,@TipoMovimiento,@Cantidad,@ActorUsuarioId,@DocumentoRespaldo,@DetalleFacturaId,@Stock,CONVERT(INT,@Nuevo),@Motivo);
   SET @Existente=CONVERT(BIGINT,SCOPE_IDENTITY());
  END;
  IF @DevolverResultado=1 SELECT KardexId,OperacionId,LineaOperacion,ProductoId,TipoMovimiento,Cantidad,FechaHora,UsuarioId,DocumentoRespaldo,DetalleFacturaId,StockAnterior,StockResultante,Motivo FROM dbo.Kardex_Inventario WHERE KardexId=@Existente;
  IF @Propia=1 COMMIT TRANSACTION;
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
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.sp_ProcesarVentaTransaccional
    @ClienteId INT,
    @UsuarioId INT,
    @Detalle dbo.TipoDetalleVentaDescuento READONLY,
    @FacturaId INT = NULL OUTPUT,
    @MotivoDescuento NVARCHAR(80) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET ANSI_WARNINGS ON;
    SET ARITHABORT ON;
    SET CONCAT_NULL_YIELDS_NULL ON;
    SET NUMERIC_ROUNDABORT OFF;
    DECLARE @Propia BIT=CASE WHEN @@TRANCOUNT=0 THEN 1 ELSE 0 END, @OperacionId UNIQUEIDENTIFIER=NEWID();
 EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=NULL;
    SET @FacturaId = NULL;
    BEGIN TRY
        IF @Propia=1 BEGIN TRANSACTION;
 DECLARE @BloqueoCorte INT;
 EXEC @BloqueoCorte=sys.sp_getapplock @Resource=N''InventarioCorteParteII'',@LockMode=''Shared'',@LockOwner=''Transaction'',@LockTimeout=10000;
 IF @BloqueoCorte<0 THROW 54401,''No se obtuvo bloqueo de inventario.'',1;
        IF NOT EXISTS(SELECT 1 FROM dbo.ConfiguracionInventario WITH(HOLDLOCK) WHERE ConfiguracionId=1 AND Habilitado=1 AND IntegracionVersion=2 AND AperturaId IS NOT NULL) THROW 54110,''Venta bloqueada hasta aprobar apertura y habilitacion.'',1;
        IF NOT EXISTS (SELECT 1 FROM @Detalle)
            THROW 52001, ''La venta debe contener productos.'', 1;
        IF (SELECT COUNT_BIG(*) FROM @Detalle) > 100
            THROW 52002, ''La venta admite hasta 100 productos.'', 1;
        IF EXISTS (SELECT 1 FROM @Detalle WHERE Cantidad <= 0 OR ProductoId <= 0)
            THROW 52003, ''Producto o cantidad inválidos.'', 1;
        IF EXISTS (SELECT ProductoId FROM @Detalle GROUP BY ProductoId HAVING COUNT(*) > 1)
            THROW 52004, ''No se permiten productos repetidos.'', 1;

        IF EXISTS (SELECT 1 FROM @Detalle WHERE DescuentoPorcentaje IS NULL OR DescuentoPorcentaje < 0 OR DescuentoPorcentaje > 100)
            THROW 52011, ''El descuento debe estar entre 0.00 y 100.00.'', 1;

        DECLARE @Activo BIT, @ClienteNombre NVARCHAR(150), @NIT NVARCHAR(25), @Cajero NVARCHAR(50);
        SELECT @Activo = Activo, @ClienteNombre = Nombre, @NIT = NIT
        FROM dbo.Cliente WITH (HOLDLOCK) WHERE ClienteId = @ClienteId;
        IF @Activo IS NULL THROW 52005, ''El cliente no existe.'', 1;
        IF @Activo = 0 THROW 52006, ''El cliente está inactivo.'', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WITH (HOLDLOCK) WHERE UsuarioId = @UsuarioId AND Activo = 1)
            THROW 52007, ''El usuario no existe o está inactivo.'', 1;
        DECLARE @MaxDescuento DECIMAL(5,2), @PuedeVender BIT;
        SELECT @MaxDescuento = MaxDescuento, @PuedeVender = PuedeVender
        FROM dbo.fn_ObtenerPoliticaVenta(@UsuarioId);
        IF @PuedeVender = 0 THROW 52013, ''No tienes permiso para registrar ventas.'', 1;
        IF EXISTS (SELECT 1 FROM @Detalle WHERE DescuentoPorcentaje > @MaxDescuento)
            THROW 52012, ''El descuento máximo autorizado para tu rol es 10%.'', 1;
        SET @MotivoDescuento = NULLIF(LTRIM(RTRIM(@MotivoDescuento)), N'''');
        IF @MotivoDescuento IS NOT NULL AND @MotivoDescuento NOT IN
            (N''Promoción'', N''Cliente frecuente'', N''Ajuste comercial'', N''Autorización administrativa'', N''Otro'')
            THROW 52014, ''Selecciona un motivo de descuento válido.'', 1;
        IF NOT EXISTS (SELECT 1 FROM @Detalle WHERE DescuentoPorcentaje > 0) SET @MotivoDescuento = NULL;
        SELECT @Cajero = NombreUsuario FROM dbo.Usuario WITH (HOLDLOCK) WHERE UsuarioId = @UsuarioId;

        EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=@UsuarioId;
        EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=@OperacionId;
        DECLARE @Lineas TABLE (ProductoId INT PRIMARY KEY, Cantidad INT,
            PrecioUnitario DECIMAL(12,2), Subtotal DECIMAL(19,2),
            DescuentoPorcentaje DECIMAL(5,2), DescuentoMonto DECIMAL(19,2), SubtotalNeto DECIMAL(19,2),
            Descripcion NVARCHAR(200));
        DECLARE @ProductoId INT = 0, @Siguiente INT, @Cantidad INT,
                @Precio DECIMAL(12,2), @Stock INT, @Porcentaje DECIMAL(5,2),
                @Bruto DECIMAL(19,2), @MontoDescuento DECIMAL(19,2), @Descripcion NVARCHAR(200);
        -- Acceso puntual por PK en orden ascendente, independiente del orden del TVP.
        -- UPDLOCK + HOLDLOCK conserva precio/stock hasta COMMIT y serializa ventas
        -- del mismo producto. No se reintentan ventas automáticamente tras un timeout.
        WHILE 1 = 1
        BEGIN
            SELECT @Siguiente = MIN(ProductoId) FROM @Detalle WHERE ProductoId > @ProductoId;
            IF @Siguiente IS NULL BREAK;
            SET @ProductoId = @Siguiente;
            SELECT @Cantidad = Cantidad, @Porcentaje = DescuentoPorcentaje FROM @Detalle WHERE ProductoId = @ProductoId;
            SELECT @Precio = NULL, @Stock = NULL, @Activo = NULL;
            SELECT @Precio = Precio, @Stock = Stock, @Activo = Activo, @Descripcion = Descripcion
            FROM dbo.Producto WITH (UPDLOCK, HOLDLOCK) WHERE ProductoId = @ProductoId;
            IF @Precio IS NULL THROW 52008, ''Un producto no existe.'', 1;
            IF @Activo = 0 THROW 52009, ''Un producto está inactivo.'', 1;
            IF @Stock < @Cantidad THROW 52010, ''Stock insuficiente para uno de los productos.'', 1;
            SET @Bruto = @Precio * CONVERT(DECIMAL(10,0), @Cantidad);
            SET @MontoDescuento = ROUND(@Bruto * @Porcentaje / CONVERT(DECIMAL(5,2), 100), 2);
            INSERT @Lineas VALUES (@ProductoId, @Cantidad, @Precio, @Bruto,
                @Porcentaje, @MontoDescuento, @Bruto - @MontoDescuento, @Descripcion);
            -- El mecanismo Kardex aplicara la salida despues de insertar el detalle.
        END;

        -- Descuento por línea e IVA sobre el neto global, redondeados a centavos.
        -- ROUND: mitades hacia arriba para importes no negativos; solo DECIMAL.
        DECLARE @Descuento DECIMAL(19,2), @SubtotalNeto DECIMAL(19,2),
                @Subtotal DECIMAL(19,2), @IVA DECIMAL(19,2), @Total DECIMAL(19,2),
                @FechaHora DATETIME2(3) = SYSUTCDATETIME();
        SELECT @Subtotal = SUM(Subtotal), @Descuento = SUM(DescuentoMonto),
            @SubtotalNeto = SUM(SubtotalNeto) FROM @Lineas;
        SET @IVA = ROUND(@SubtotalNeto * CONVERT(DECIMAL(3,2), 0.12), 2);
        SET @Total = @SubtotalNeto + @IVA;
        INSERT dbo.Factura (ClienteId, UsuarioId, FechaHora, Subtotal, DescuentoTotal, IVA, Total, MotivoDescuento)
        VALUES (@ClienteId, @UsuarioId, @FechaHora, @Subtotal, @Descuento, @IVA, @Total, @MotivoDescuento);
        SET @FacturaId = CONVERT(INT, SCOPE_IDENTITY());
        INSERT dbo.DetalleFactura (FacturaId, ProductoId, Cantidad, PrecioUnitario, Subtotal, DescuentoPorcentaje, DescuentoMonto)
        SELECT @FacturaId, ProductoId, Cantidad, PrecioUnitario, Subtotal, DescuentoPorcentaje, DescuentoMonto FROM @Lineas;
        DECLARE @DetalleFacturaId INT,@DocumentoVenta NVARCHAR(100)=CONCAT(N''FACTURA:'',@FacturaId);
        SET @ProductoId=0;
        WHILE 1=1
        BEGIN
            SELECT @Siguiente=MIN(ProductoId) FROM @Lineas WHERE ProductoId>@ProductoId;
            IF @Siguiente IS NULL BREAK;
            SET @ProductoId=@Siguiente;
            SELECT @Cantidad=Cantidad FROM @Lineas WHERE ProductoId=@ProductoId;
            SELECT @DetalleFacturaId=DetalleFacturaId FROM dbo.DetalleFactura WHERE FacturaId=@FacturaId AND ProductoId=@ProductoId;
            EXEC dbo.sp_RegistrarMovimientoKardex @ProductoId=@ProductoId,@TipoMovimiento=''VENTA'',@Cantidad=@Cantidad,@ActorUsuarioId=@UsuarioId,
                @DocumentoRespaldo=@DocumentoVenta,@OperacionId=@OperacionId,@LineaOperacion=@DetalleFacturaId,@Motivo=N''Venta transaccional'',@DetalleFacturaId=@DetalleFacturaId,@DevolverResultado=0;
        END;
        EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=@UsuarioId;
        EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=@OperacionId;
        INSERT dbo.MovimientoCaja (FacturaId, Monto, FechaHora) VALUES (@FacturaId, @Total, @FechaHora);
        IF @Propia=1 COMMIT TRANSACTION;
 EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=NULL;
        -- Strings monetarios evitan pérdida de centavos al convertir DECIMAL(19,2) a JS Number.
        SELECT @FacturaId AS FacturaId, @FechaHora AS FechaHora,
            CONVERT(VARCHAR(21), @Subtotal) AS Subtotal,
            CONVERT(VARCHAR(21), @Descuento) AS Descuento,
            CONVERT(VARCHAR(21), @SubtotalNeto) AS SubtotalNeto,
            CONVERT(VARCHAR(21), @IVA) AS IVA, CONVERT(VARCHAR(21), @Total) AS Total,
            @ClienteNombre AS Cliente, @NIT AS NIT, @Cajero AS Cajero, @MotivoDescuento AS MotivoDescuento;
        SELECT ProductoId, Descripcion, Cantidad,
            CONVERT(VARCHAR(21), PrecioUnitario) AS PrecioUnitario,
            CONVERT(VARCHAR(21), Subtotal) AS Subtotal,
            CONVERT(VARCHAR(6), DescuentoPorcentaje) AS DescuentoPorcentaje,
            CONVERT(VARCHAR(21), DescuentoMonto) AS DescuentoMonto,
            CONVERT(VARCHAR(21), SubtotalNeto) AS SubtotalNeto
        FROM @Lineas ORDER BY ProductoId;
    END TRY
    BEGIN CATCH
        -- Sin SAVEPOINT: la venta debe revertirse completa. Si el llamador abrió
        -- una transacción, también se revierte; Node llama el SP en autocommit.
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        SET @FacturaId = NULL;
        THROW;
    END CATCH;
END;';
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.sp_ProcesarVentaSinDescuento
    @ClienteId INT, @UsuarioId INT, @Detalle dbo.TipoDetalleVenta READONLY,
    @FacturaId INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Nuevo dbo.TipoDetalleVentaDescuento;
    INSERT @Nuevo (ProductoId, Cantidad, DescuentoPorcentaje)
    SELECT ProductoId, Cantidad, 0 FROM @Detalle;
    EXEC dbo.sp_ProcesarVentaTransaccional @ClienteId, @UsuarioId, @Nuevo, @FacturaId OUTPUT;
END;';
 EXEC sys.sp_executesql N'CREATE OR ALTER TRIGGER dbo.tr_Kardex_Auditar_Insert ON dbo.Kardex_Inventario AFTER INSERT
AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.Bitacora_Transacciones(TablaAfectada,Operacion,IdentificadorRegistro,ValorAnterior,ValorNuevo,ActorUsuarioId,OperacionId,Motivo)
 SELECT N''Kardex_Inventario'',''INSERT'',CONVERT(NVARCHAR(4000),i.KardexId),NULL,
 (SELECT i.KardexId,i.ProductoId,i.TipoMovimiento,i.Cantidad,i.StockAnterior,i.StockResultante,i.DocumentoRespaldo,i.UsuarioId,i.FechaHora,i.DetalleFacturaId,i.OperacionId,i.LineaOperacion,i.Motivo,i.AperturaId FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER),i.UsuarioId,i.OperacionId,i.Motivo
 FROM inserted i;
END;';
 EXEC sys.sp_executesql N'CREATE OR ALTER TRIGGER dbo.tr_Factura_Auditar_Insert
ON dbo.Factura
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.Bitacora_Transacciones
        (TablaAfectada, Operacion, UsuarioSQL, HostName, AppName,
         IdentificadorRegistro, ValorAnterior, ValorNuevo, ActorUsuarioId, OperacionId)
    SELECT N''Factura'', ''INSERT'', SUSER_SNAME(), HOST_NAME(), APP_NAME(),
           CONVERT(NVARCHAR(4000), i.FacturaId),
           NULL,
           (SELECT i.FacturaId, i.ClienteId, i.UsuarioId, i.FechaHora, i.Subtotal, i.DescuentoTotal, i.MotivoDescuento, i.IVA, i.Total, i.Estado FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
, TRY_CONVERT(INT,SESSION_CONTEXT(N''ParteII.Actor'')), TRY_CONVERT(UNIQUEIDENTIFIER,SESSION_CONTEXT(N''ParteII.Operacion''))
    FROM inserted AS i;
END;';
 EXEC sys.sp_executesql N'CREATE OR ALTER TRIGGER dbo.tr_Apertura_Inmutable ON dbo.Apertura_Inventario AFTER UPDATE,DELETE
AS BEGIN SET NOCOUNT ON; IF EXISTS(SELECT 1 FROM deleted) THROW 54408,''La apertura es inmutable.'',1; END;';

 IF NOT EXISTS(SELECT 1 FROM dbo.Permiso WITH(UPDLOCK,HOLDLOCK) WHERE Codigo=N'INVENTARIO_APERTURAR')
 INSERT dbo.Permiso(Codigo,Descripcion) VALUES(N'INVENTARIO_APERTURAR',N'Corte inicial y habilitacion por administrador autorizado');
 IF DATABASE_PRINCIPAL_ID(N'securefinance_app') IS NULL THROW 54400,'Falta usuario SQL de aplicacion.',1;
 GRANT EXECUTE ON OBJECT::dbo.sp_ConsultarConciliacionInventario TO securefinance_app;
 DENY EXECUTE ON OBJECT::dbo.sp_AbrirKardexInventario TO securefinance_app;
 DENY EXECUTE ON OBJECT::dbo.sp_HabilitarKardexInventario TO securefinance_app;
 DENY SELECT,INSERT,UPDATE,DELETE ON OBJECT::dbo.Apertura_Inventario TO securefinance_app;
 EXEC sys.sp_executesql N'UPDATE dbo.ConfiguracionInventario SET IntegracionVersion=2 WHERE ConfiguracionId=1 AND IntegracionVersion<>2;';

 COMMIT TRANSACTION;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 THROW;
END CATCH;
GO
