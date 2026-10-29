-- PROPOSED: pending Kenneth review, NOT approved for integration/execution.
-- Based on the THREE complete definitions in 43 at 1bca099. 43/TVP/Kardex unchanged.
-- Apply only through external-transaction, stop-on-first-error laboratory installer.
SET XACT_ABORT ON; SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON;
IF DB_NAME() <> N'SecureFinanceERP_Lab_Dylan' OR @@TRANCOUNT=0 THROW 57000,'Laboratorio y transaccion externa requeridos.',1;
IF OBJECT_ID('dbo.P3_CRE_CrearCuenta','P') IS NULL OR OBJECT_ID('dbo.P3_COT_ValidarOrigen','P') IS NULL
 THROW 57000,'Requiere 43 y 70-75.',1;
GO
CREATE OR ALTER PROCEDURE dbo.sp_ProcesarVentaTransaccional
 @ClienteId INT,@UsuarioId INT,@Detalle dbo.TipoDetalleVentaDescuento READONLY,
 @FacturaId INT=NULL OUTPUT,@MotivoDescuento NVARCHAR(80)=NULL,@P3CotizacionId INT=NULL,
 @P3Credito BIT=0,@P3PlazoDias INT=NULL,@P3NumeroCuotas INT=1
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 SET ANSI_WARNINGS ON; SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET NUMERIC_ROUNDABORT OFF;
 DECLARE @Propia BIT=CASE WHEN @@TRANCOUNT=0 THEN 1 ELSE 0 END,@OperacionId UNIQUEIDENTIFIER=NEWID();
 EXEC sys.sp_set_session_context @key=N'ParteII.Actor',@value=NULL;
 EXEC sys.sp_set_session_context @key=N'ParteII.Operacion',@value=NULL;
 EXEC sys.sp_set_session_context @key=N'ParteII.Motivo',@value=NULL;
 SET @FacturaId=NULL;
 BEGIN TRY
  IF @Propia=1 BEGIN TRANSACTION;
  IF @P3CotizacionId IS NOT NULL
   EXEC dbo.P3_COT_ValidarOrigen @CotizacionId=@P3CotizacionId,@ActorUsuarioId=@UsuarioId,
    @ClienteId=@ClienteId,@Detalle=@Detalle,@MotivoDescuento=@MotivoDescuento;
  IF @P3Credito IS NULL THROW 57002,'Modalidad invalida.',1;
  IF @P3Credito=1
   EXEC dbo.P3_CRE_ValidarFinanciacion @UsuarioId,@ClienteId,@P3PlazoDias,@P3NumeroCuotas;
  DECLARE @BloqueoCorte INT;
  EXEC @BloqueoCorte=sys.sp_getapplock @Resource=N'InventarioCorteParteII',@LockMode='Shared',@LockOwner='Transaction',@LockTimeout=10000;
  IF @BloqueoCorte<0 THROW 54401,'No se obtuvo bloqueo de inventario.',1;
  IF NOT EXISTS(SELECT 1 FROM dbo.ConfiguracionInventario WITH(HOLDLOCK) WHERE ConfiguracionId=1 AND Habilitado=1 AND IntegracionVersion=2 AND AperturaId IS NOT NULL) THROW 54110,'Venta bloqueada hasta aprobar apertura y habilitacion.',1;
  IF NOT EXISTS(SELECT 1 FROM @Detalle) THROW 52001,'La venta debe contener productos.',1;
  IF (SELECT COUNT_BIG(*) FROM @Detalle)>100 THROW 52002,'La venta admite hasta 100 productos.',1;
  IF EXISTS(SELECT 1 FROM @Detalle WHERE Cantidad<=0 OR ProductoId<=0) THROW 52003,'Producto o cantidad inválidos.',1;
  IF EXISTS(SELECT ProductoId FROM @Detalle GROUP BY ProductoId HAVING COUNT(*)>1) THROW 52004,'No se permiten productos repetidos.',1;
  IF EXISTS(SELECT 1 FROM @Detalle WHERE DescuentoPorcentaje IS NULL OR DescuentoPorcentaje<0 OR DescuentoPorcentaje>100)
   THROW 52011,'El descuento debe estar entre 0.00 y 100.00.',1;
  DECLARE @Activo BIT,@ClienteNombre NVARCHAR(150),@NIT NVARCHAR(25),@Cajero NVARCHAR(50);
  SELECT @Activo=Activo,@ClienteNombre=Nombre,@NIT=NIT FROM dbo.Cliente WITH(HOLDLOCK) WHERE ClienteId=@ClienteId;
  IF @Activo IS NULL THROW 52005,'El cliente no existe.',1;
  IF @Activo=0 THROW 52006,'El cliente está inactivo.',1;
  IF NOT EXISTS(SELECT 1 FROM dbo.Usuario WITH(HOLDLOCK) WHERE UsuarioId=@UsuarioId AND Activo=1) THROW 52007,'El usuario no existe o está inactivo.',1;
  DECLARE @MaxDescuento DECIMAL(5,2),@PuedeVender BIT;
  SELECT @MaxDescuento=MaxDescuento,@PuedeVender=PuedeVender FROM dbo.fn_ObtenerPoliticaVenta(@UsuarioId);
  IF @PuedeVender=0 THROW 52013,'No tienes permiso para registrar ventas.',1;
  IF EXISTS(SELECT 1 FROM @Detalle WHERE DescuentoPorcentaje>@MaxDescuento) THROW 52012,'El descuento máximo autorizado para tu rol es 10%.',1;
  SET @MotivoDescuento=NULLIF(LTRIM(RTRIM(@MotivoDescuento)),N'');
  IF @MotivoDescuento IS NOT NULL AND @MotivoDescuento NOT IN
   (N'Promoción',N'Cliente frecuente',N'Ajuste comercial',N'Autorización administrativa',N'Otro')
   THROW 52014,'Selecciona un motivo de descuento válido.',1;
  IF NOT EXISTS(SELECT 1 FROM @Detalle WHERE DescuentoPorcentaje>0) SET @MotivoDescuento=NULL;
  SELECT @Cajero=NombreUsuario FROM dbo.Usuario WITH(HOLDLOCK) WHERE UsuarioId=@UsuarioId;
  EXEC sys.sp_set_session_context @key=N'ParteII.Actor',@value=@UsuarioId;
  EXEC sys.sp_set_session_context @key=N'ParteII.Operacion',@value=@OperacionId;
  DECLARE @Lineas TABLE(ProductoId INT PRIMARY KEY,Cantidad INT,PrecioUnitario DECIMAL(12,2),Subtotal DECIMAL(19,2),
   DescuentoPorcentaje DECIMAL(5,2),DescuentoMonto DECIMAL(19,2),SubtotalNeto DECIMAL(19,2),Descripcion NVARCHAR(200));
  DECLARE @ProductoId INT=0,@Siguiente INT,@Cantidad INT,@Precio DECIMAL(12,2),@Stock INT,@Porcentaje DECIMAL(5,2),
   @Bruto DECIMAL(19,2),@MontoDescuento DECIMAL(19,2),@Descripcion NVARCHAR(200);
  -- Original 43: one pricing/discount engine and ordered product locks.
  WHILE 1=1
  BEGIN
   SELECT @Siguiente=MIN(ProductoId) FROM @Detalle WHERE ProductoId>@ProductoId;
   IF @Siguiente IS NULL BREAK;
   SET @ProductoId=@Siguiente;
   SELECT @Cantidad=Cantidad,@Porcentaje=DescuentoPorcentaje FROM @Detalle WHERE ProductoId=@ProductoId;
   SELECT @Precio=NULL,@Stock=NULL,@Activo=NULL;
   SELECT @Precio=Precio,@Stock=Stock,@Activo=Activo,@Descripcion=Descripcion
    FROM dbo.Producto WITH(UPDLOCK,HOLDLOCK) WHERE ProductoId=@ProductoId;
   IF @Precio IS NULL THROW 52008,'Un producto no existe.',1;
   IF @Activo=0 THROW 52009,'Un producto está inactivo.',1;
   IF @Stock<@Cantidad THROW 52010,'Stock insuficiente para uno de los productos.',1;
   IF @P3CotizacionId IS NOT NULL SELECT @Precio=PrecioUnitario FROM dbo.P3_COT_Detalle WHERE CotizacionId=@P3CotizacionId AND ProductoId=@ProductoId;
   SET @Bruto=@Precio*CONVERT(DECIMAL(10,0),@Cantidad);
   SET @MontoDescuento=ROUND(@Bruto*@Porcentaje/CONVERT(DECIMAL(5,2),100),2);
   INSERT @Lineas VALUES(@ProductoId,@Cantidad,@Precio,@Bruto,@Porcentaje,@MontoDescuento,@Bruto-@MontoDescuento,@Descripcion);
  END;
  DECLARE @Descuento DECIMAL(19,2),@SubtotalNeto DECIMAL(19,2),@Subtotal DECIMAL(19,2),@IVA DECIMAL(19,2),@Total DECIMAL(19,2),@FechaHora DATETIME2(3)=SYSUTCDATETIME();
  SELECT @Subtotal=SUM(Subtotal),@Descuento=SUM(DescuentoMonto),@SubtotalNeto=SUM(SubtotalNeto) FROM @Lineas;
  SET @IVA=ROUND(@SubtotalNeto*CONVERT(DECIMAL(3,2),0.12),2);
  SET @Total=@SubtotalNeto+@IVA;
  IF @P3CotizacionId IS NOT NULL
  BEGIN
   IF NOT EXISTS(SELECT 1 FROM dbo.P3_COT_Cotizacion WHERE CotizacionId=@P3CotizacionId AND Estado='ACTIVA' AND VenceEn>SYSUTCDATETIME()) THROW 54910,'Cotizacion vencida durante la espera de inventario.',1;
   IF NOT EXISTS(SELECT 1 FROM dbo.P3_COT_Cotizacion WHERE CotizacionId=@P3CotizacionId AND Subtotal=@Subtotal AND Descuento=@Descuento AND SubtotalNeto=@SubtotalNeto AND IVA=@IVA AND Total=@Total)
    OR EXISTS(SELECT ProductoId,Cantidad,PrecioUnitario,DescuentoPorcentaje,Subtotal,DescuentoMonto FROM @Lineas EXCEPT
     SELECT ProductoId,Cantidad,PrecioUnitario,DescuentoPorcentaje,Subtotal,DescuentoMonto FROM dbo.P3_COT_Detalle WHERE CotizacionId=@P3CotizacionId)
    THROW 54912,'Importes de cotizacion incompatibles.',1;
  END;
  -- Definitive SQL total validated BEFORE invoice, stock or cash writes.
  IF @P3Credito=1 EXEC dbo.P3_CRE_ValidarFinanciacion @UsuarioId,@ClienteId,@P3PlazoDias,@P3NumeroCuotas,@Total;
  INSERT dbo.Factura(ClienteId,UsuarioId,FechaHora,Subtotal,DescuentoTotal,IVA,Total,MotivoDescuento)
   VALUES(@ClienteId,@UsuarioId,@FechaHora,@Subtotal,@Descuento,@IVA,@Total,@MotivoDescuento);
  SET @FacturaId=CONVERT(INT,SCOPE_IDENTITY());
  INSERT dbo.DetalleFactura(FacturaId,ProductoId,Cantidad,PrecioUnitario,Subtotal,DescuentoPorcentaje,DescuentoMonto)
   SELECT @FacturaId,ProductoId,Cantidad,PrecioUnitario,Subtotal,DescuentoPorcentaje,DescuentoMonto FROM @Lineas;
  DECLARE @DetalleFacturaId INT,@DocumentoVenta NVARCHAR(100)=CONCAT(N'FACTURA:',@FacturaId);
  SET @ProductoId=0;
  WHILE 1=1
  BEGIN
   SELECT @Siguiente=MIN(ProductoId) FROM @Lineas WHERE ProductoId>@ProductoId;
   IF @Siguiente IS NULL BREAK;
   SET @ProductoId=@Siguiente;
   SELECT @Cantidad=Cantidad FROM @Lineas WHERE ProductoId=@ProductoId;
   SELECT @DetalleFacturaId=DetalleFacturaId FROM dbo.DetalleFactura WHERE FacturaId=@FacturaId AND ProductoId=@ProductoId;
   EXEC dbo.sp_RegistrarMovimientoKardex @ProductoId=@ProductoId,@TipoMovimiento='VENTA',@Cantidad=@Cantidad,@ActorUsuarioId=@UsuarioId,
    @DocumentoRespaldo=@DocumentoVenta,@OperacionId=@OperacionId,@LineaOperacion=@DetalleFacturaId,@Motivo=N'Venta transaccional',@DetalleFacturaId=@DetalleFacturaId,@DevolverResultado=0;
  END;
  EXEC sys.sp_set_session_context @key=N'ParteII.Actor',@value=@UsuarioId;
  EXEC sys.sp_set_session_context @key=N'ParteII.Operacion',@value=@OperacionId;
  IF @P3Credito=0 INSERT dbo.MovimientoCaja(FacturaId,Monto,FechaHora) VALUES(@FacturaId,@Total,@FechaHora);
  ELSE EXEC dbo.P3_CRE_CrearCuenta @UsuarioId,@ClienteId,@FacturaId,@P3PlazoDias,@P3NumeroCuotas,@OperacionId;
  IF @Propia=1 COMMIT TRANSACTION;
  EXEC sys.sp_set_session_context @key=N'ParteII.Actor',@value=NULL;
  EXEC sys.sp_set_session_context @key=N'ParteII.Operacion',@value=NULL;
  EXEC sys.sp_set_session_context @key=N'ParteII.Motivo',@value=NULL;
  SELECT @FacturaId FacturaId,@FechaHora FechaHora,CONVERT(VARCHAR(21),@Subtotal) Subtotal,CONVERT(VARCHAR(21),@Descuento) Descuento,
   CONVERT(VARCHAR(21),@SubtotalNeto) SubtotalNeto,CONVERT(VARCHAR(21),@IVA) IVA,CONVERT(VARCHAR(21),@Total) Total,
   @ClienteNombre Cliente,@NIT NIT,@Cajero Cajero,@MotivoDescuento MotivoDescuento;
  SELECT ProductoId,Descripcion,Cantidad,CONVERT(VARCHAR(21),PrecioUnitario) PrecioUnitario,CONVERT(VARCHAR(21),Subtotal) Subtotal,
   CONVERT(VARCHAR(6),DescuentoPorcentaje) DescuentoPorcentaje,CONVERT(VARCHAR(21),DescuentoMonto) DescuentoMonto,CONVERT(VARCHAR(21),SubtotalNeto) SubtotalNeto
   FROM @Lineas ORDER BY ProductoId;
 END TRY BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
  EXEC sys.sp_set_session_context @key=N'ParteII.Actor',@value=NULL;
  EXEC sys.sp_set_session_context @key=N'ParteII.Operacion',@value=NULL;
  EXEC sys.sp_set_session_context @key=N'ParteII.Motivo',@value=NULL;
  SET @FacturaId=NULL; THROW;
 END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_ERP_ProcesarVenta
 @ClienteId INT,@UsuarioId INT,@Detalle dbo.TipoDetalleVentaDescuento READONLY,
 @OperacionId UNIQUEIDENTIFIER,@MotivoDescuento NVARCHAR(80)=NULL,@P3CotizacionId INT=NULL,
 @P3Credito BIT=0,@P3PlazoDias INT=NULL,@P3NumeroCuotas INT=1
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRANSACTION;
  EXEC dbo.sp_ParteII_ValidarPermiso @UsuarioId,N'VENTAS_REGISTRAR';
  IF @OperacionId IS NULL THROW 54802,'Operacion requerida.',1;
  IF @P3CotizacionId IS NOT NULL EXEC dbo.P3_COT_ValidarOrigen @CotizacionId=@P3CotizacionId,@ActorUsuarioId=@UsuarioId,
   @ClienteId=@ClienteId,@Detalle=@Detalle,@MotivoDescuento=@MotivoDescuento,@PermitirProcesada=1;
  DECLARE @Canon NVARCHAR(MAX)=(SELECT ProductoId,Cantidad,DescuentoPorcentaje FROM @Detalle ORDER BY ProductoId FOR JSON PATH),
   @Hash BINARY(32),@Resource NVARCHAR(255)=CONCAT(N'ERP.Venta.',@OperacionId),@Lock INT,@F INT,@Prev BINARY(32),@Header NVARCHAR(MAX),@Lines NVARCHAR(MAX);
  SET @Hash=HASHBYTES('SHA2_256',CONCAT(@ClienteId,N'|',@UsuarioId,N'|',COALESCE(@MotivoDescuento,N''),N'|',@Canon));
  -- The two original 43 hash expressions are UNCHANGED for cash.
  IF @P3CotizacionId IS NOT NULL
  BEGIN
   SELECT @Canon=(SELECT ProductoId,Cantidad,PrecioUnitario,DescuentoPorcentaje,Subtotal,DescuentoMonto,SubtotalNeto
    FROM dbo.P3_COT_Detalle WHERE CotizacionId=@P3CotizacionId ORDER BY ProductoId FOR JSON PATH);
   SET @Hash=HASHBYTES('SHA2_256',CONCAT(N'P3COT:v1|',@P3CotizacionId,N'|',@ClienteId,N'|',@UsuarioId,N'|',COALESCE(@MotivoDescuento,N''),N'|',@Canon));
  END;
  IF @P3Credito IS NULL THROW 57002,'Modalidad invalida.',1;
  IF @P3Credito=1
  BEGIN
   EXEC dbo.P3_CRE_ValidarEntorno;
   EXEC dbo.sp_ParteII_ValidarPermiso @UsuarioId,N'CREDITOS_FACTURAR';
   IF SESSION_CONTEXT(N'P3_BOD.BodegaId') IS NOT NULL
   BEGIN
    DECLARE @BodegaSeleccionada INT=TRY_CONVERT(INT,SESSION_CONTEXT(N'P3_BOD.BodegaId'));
    IF @BodegaSeleccionada IS NULL OR @BodegaSeleccionada<1 THROW 57002,'Contexto de bodega invalido.',1;
    BEGIN TRY
     EXEC dbo.P3_BOD_ValidarBodegaVenta @ActorUsuarioId=@UsuarioId,@BodegaId=@BodegaSeleccionada;
    END TRY BEGIN CATCH
     IF ERROR_NUMBER()=2812 THROW 57008,'Falta validacion de bodega; no se factura sobre stock global.',1;
     THROW;
    END CATCH;
   END;
   IF @P3PlazoDias IS NULL OR @P3NumeroCuotas IS NULL OR @P3PlazoDias NOT BETWEEN 1 AND 3650
    OR @P3NumeroCuotas NOT BETWEEN 1 AND 120 OR @P3NumeroCuotas>@P3PlazoDias THROW 57002,'Plan invalido.',1;
   SET @Hash=HASHBYTES('SHA2_256',CONCAT(N'P3CRE:v1|',CONVERT(VARCHAR(64),@Hash,2),N'|',@P3PlazoDias,N'|',@P3NumeroCuotas,N'|',
    COALESCE(CONVERT(NVARCHAR(20),TRY_CONVERT(INT,SESSION_CONTEXT(N'P3_BOD.BodegaId'))),N'GLOBAL')));
  END;
  EXEC @Lock=sys.sp_getapplock @Resource=@Resource,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
  IF @Lock<0 THROW 54803,'Venta ocupada.',1;
  SELECT @F=FacturaId,@Prev=SolicitudHash,@Header=Comprobante,@Lines=Detalle FROM dbo.SolicitudVentaERP WITH(UPDLOCK,HOLDLOCK) WHERE OperacionId=@OperacionId;
  IF @F IS NOT NULL
  BEGIN
   IF @Prev<>@Hash THROW 54803,'Referencia utilizada con otros datos.',1;
   IF @P3CotizacionId IS NOT NULL AND NOT EXISTS(
    SELECT 1 FROM dbo.P3_COT_Cotizacion c JOIN dbo.P3_COT_HistorialEstado h ON h.CotizacionId=c.CotizacionId
    WHERE c.CotizacionId=@P3CotizacionId AND c.Estado='PROCESADA' AND c.FacturaId=@F
     AND h.EstadoNuevo='PROCESADA' AND h.ActorUsuarioId=@UsuarioId AND h.OperacionId=@OperacionId)
    THROW 54903,'Vinculo de conversion incompatible.',1;
   SELECT * FROM OPENJSON(@Header) WITH(FacturaId INT,FechaHora DATETIME2(3),Subtotal VARCHAR(21),Descuento VARCHAR(21),SubtotalNeto VARCHAR(21),IVA VARCHAR(21),Total VARCHAR(21),Cliente NVARCHAR(150),NIT NVARCHAR(25),Cajero NVARCHAR(50),MotivoDescuento NVARCHAR(80));
   SELECT * FROM OPENJSON(@Lines) WITH(ProductoId INT,Descripcion NVARCHAR(200),Cantidad INT,PrecioUnitario VARCHAR(21),Subtotal VARCHAR(21),DescuentoPorcentaje VARCHAR(6),DescuentoMonto VARCHAR(21),SubtotalNeto VARCHAR(21));
  END
  ELSE
  BEGIN
   IF @P3CotizacionId IS NOT NULL
   BEGIN
    IF NOT EXISTS(SELECT 1 FROM dbo.P3_COT_Cotizacion WHERE CotizacionId=@P3CotizacionId AND Estado='ACTIVA') THROW 54903,'La cotizacion ya fue procesada o cancelada.',1;
    IF EXISTS(SELECT 1 FROM dbo.P3_COT_HistorialEstado WHERE OperacionId=@OperacionId) THROW 54903,'Referencia ya utilizada en otro evento.',1;
   END;
   EXEC dbo.sp_ProcesarVentaTransaccional @ClienteId=@ClienteId,@UsuarioId=@UsuarioId,@Detalle=@Detalle,@FacturaId=@F OUTPUT,
    @MotivoDescuento=@MotivoDescuento,@P3CotizacionId=@P3CotizacionId,@P3Credito=@P3Credito,@P3PlazoDias=@P3PlazoDias,@P3NumeroCuotas=@P3NumeroCuotas;
   SELECT @Header=(SELECT f.FacturaId,f.FechaHora,CONVERT(VARCHAR(21),f.Subtotal) Subtotal,CONVERT(VARCHAR(21),f.DescuentoTotal) Descuento,
    CONVERT(VARCHAR(21),f.Subtotal-f.DescuentoTotal) SubtotalNeto,CONVERT(VARCHAR(21),f.IVA) IVA,CONVERT(VARCHAR(21),f.Total) Total,
    f.ClienteNombreEmision Cliente,f.ClienteNITEmision NIT,u.NombreUsuario Cajero,f.MotivoDescuento
    FROM dbo.Factura f JOIN dbo.Usuario u ON u.UsuarioId=f.UsuarioId WHERE f.FacturaId=@F FOR JSON PATH,WITHOUT_ARRAY_WRAPPER,INCLUDE_NULL_VALUES);
   SELECT @Lines=(SELECT d.ProductoId,p.Descripcion,d.Cantidad,CONVERT(VARCHAR(21),d.PrecioUnitario) PrecioUnitario,
    CONVERT(VARCHAR(21),d.Subtotal) Subtotal,CONVERT(VARCHAR(6),d.DescuentoPorcentaje) DescuentoPorcentaje,
    CONVERT(VARCHAR(21),d.DescuentoMonto) DescuentoMonto,CONVERT(VARCHAR(21),d.SubtotalNeto) SubtotalNeto
    FROM dbo.DetalleFactura d JOIN dbo.Producto p ON p.ProductoId=d.ProductoId WHERE d.FacturaId=@F ORDER BY d.ProductoId FOR JSON PATH);
   INSERT dbo.SolicitudVentaERP(OperacionId,FacturaId,UsuarioId,SolicitudHash,Comprobante,Detalle) VALUES(@OperacionId,@F,@UsuarioId,@Hash,@Header,@Lines);
   IF @P3CotizacionId IS NOT NULL
   BEGIN
    UPDATE dbo.P3_COT_Cotizacion SET Estado='PROCESADA',FacturaId=@F WHERE CotizacionId=@P3CotizacionId AND Estado='ACTIVA';
    IF @@ROWCOUNT<>1 THROW 54903,'No fue posible cerrar la cotizacion.',1;
    DECLARE @ConversionMotivo NVARCHAR(250)=CASE WHEN @P3Credito=1 THEN N'Conversion a factura de credito' ELSE N'Conversion a factura de contado' END;
    INSERT dbo.P3_COT_HistorialEstado(CotizacionId,EstadoAnterior,EstadoNuevo,ActorUsuarioId,OperacionId,Motivo)
     VALUES(@P3CotizacionId,'ACTIVA','PROCESADA',@UsuarioId,@OperacionId,@ConversionMotivo);
    INSERT dbo.Bitacora_Transacciones(TablaAfectada,Operacion,IdentificadorRegistro,ValorAnterior,ValorNuevo,ActorUsuarioId,OperacionId,Motivo)
     VALUES(N'P3_COT_Cotizacion','UPDATE',CONVERT(NVARCHAR(20),@P3CotizacionId),N'{"Estado":"ACTIVA"}',
      CONCAT(N'{"Estado":"PROCESADA","FacturaId":',@F,N'}'),@UsuarioId,@OperacionId,@ConversionMotivo);
   END;
  END;
  COMMIT;
 END TRY BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK; THROW; END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_ConvertirCotizacionAFactura
 @CotizacionId INT,@ActorUsuarioId INT,@OperacionId UNIQUEIDENTIFIER,
 @P3Credito BIT=0,@P3PlazoDias INT=NULL,@P3NumeroCuotas INT=1
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRANSACTION;
  EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'COTIZACIONES_CONVERTIR';
  EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'VENTAS_REGISTRAR';
  DECLARE @ClienteId INT,@Motivo NVARCHAR(80),@Detalle dbo.TipoDetalleVentaDescuento;
  SELECT @ClienteId=ClienteId FROM dbo.P3_COT_Cotizacion WITH(UPDLOCK,HOLDLOCK) WHERE CotizacionId=@CotizacionId;
  IF @ClienteId IS NULL THROW 54904,'Cotizacion inexistente.',1;
  INSERT @Detalle(ProductoId,Cantidad,DescuentoPorcentaje) SELECT ProductoId,Cantidad,DescuentoPorcentaje FROM dbo.P3_COT_Detalle WHERE CotizacionId=@CotizacionId;
  SET @Motivo=CASE WHEN EXISTS(SELECT 1 FROM @Detalle WHERE DescuentoPorcentaje>0) THEN N'Ajuste comercial' ELSE NULL END;
  EXEC dbo.sp_ERP_ProcesarVenta @ClienteId=@ClienteId,@UsuarioId=@ActorUsuarioId,@Detalle=@Detalle,
   @OperacionId=@OperacionId,@MotivoDescuento=@Motivo,@P3CotizacionId=@CotizacionId,
   @P3Credito=@P3Credito,@P3PlazoDias=@P3PlazoDias,@P3NumeroCuotas=@P3NumeroCuotas;
  DECLARE @FacturaId INT=(SELECT FacturaId FROM dbo.P3_COT_Cotizacion WHERE CotizacionId=@CotizacionId AND Estado='PROCESADA');
  IF @FacturaId IS NULL THROW 54903,'Conversion no confirmada.',1;
  COMMIT;
  SELECT @CotizacionId CotizacionId,@FacturaId FacturaId,CONVERT(VARCHAR(15),'PROCESADA') Estado,@OperacionId OperacionId;
 END TRY BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK; THROW; END CATCH;
END;
GO
