SET NOCOUNT ON; SET XACT_ABORT ON; SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON;
IF DB_NAME() COLLATE Latin1_General_100_BIN2<>N'SecureFinanceERP_Lab_Dylan' OR DATALENGTH(DB_NAME())<>DATALENGTH(N'SecureFinanceERP_Lab_Dylan') OR @@TRANCOUNT=0 OR XACT_STATE()<>1 THROW 58000,'Laboratorio y transaccion externa requeridos.',1;
EXEC(N'CREATE OR ALTER PROCEDURE dbo.P3_BOD_RegistrarCompra
 @ActorUsuarioId INT,@OperacionId UNIQUEIDENTIFIER,@BodegaId INT,@ProductoId INT,@ProveedorId INT,
 @Cantidad INT,@DocumentoRespaldo NVARCHAR(100),@Motivo NVARCHAR(250),@CostoUnitario DECIMAL(19,2)=NULL
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 SET ANSI_PADDING ON; SET ANSI_WARNINGS ON; SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET NUMERIC_ROUNDABORT OFF;
 -- Root wrapper: rechazar contexto ajeno SIN borrarlo. No permitir anidamiento implicito.
 IF SESSION_CONTEXT(N''P3_BOD.BodegaId'') IS NOT NULL THROW 58003,''Contexto de bodega ya ocupado.'',1;
 DECLARE @Propia BIT=CASE WHEN @@TRANCOUNT=0 THEN 1 ELSE 0 END,
  @ActorPrevio SQL_VARIANT=SESSION_CONTEXT(N''ParteII.Actor''),
  @OperacionPrevia SQL_VARIANT=SESSION_CONTEXT(N''ParteII.Operacion''),
  @MotivoPrevio SQL_VARIANT=SESSION_CONTEXT(N''ParteII.Motivo'');
 BEGIN TRY
  IF @Propia=1 BEGIN TRANSACTION;
  EXEC dbo.P3_BOD_Autorizar @ActorUsuarioId,N''BODEGAS_CONSULTAR'';
  EXEC dbo.P3_BOD_Autorizar @ActorUsuarioId,N''INVENTARIO_REGISTRAR'';
  IF @BodegaId IS NULL OR @ProductoId IS NULL OR @ProveedorId IS NULL OR @Cantidad IS NULL OR @Cantidad<=0 OR @CostoUnitario<0 OR NULLIF(LTRIM(RTRIM(@DocumentoRespaldo)),N'''') IS NULL OR NULLIF(LTRIM(RTRIM(@Motivo)),N'''') IS NULL THROW 58002,''Recepcion invalida.'',1;
  DECLARE @Carga NVARCHAR(MAX)=(SELECT N''COMPRA'' Accion,@BodegaId BodegaId,@ProductoId ProductoId,@ProveedorId ProveedorId,@Cantidad Cantidad,@DocumentoRespaldo DocumentoRespaldo,@Motivo Motivo,@CostoUnitario CostoUnitario FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER),@Respuesta NVARCHAR(MAX);
  EXEC dbo.P3_BOD_Reintento @ActorUsuarioId,@OperacionId,@Carga,@Respuesta OUTPUT;
  IF @Respuesta IS NULL
  BEGIN
   IF EXISTS(SELECT 1 FROM dbo.RecepcionCompra WHERE OperacionId=@OperacionId) THROW 58003,''Referencia pertenece a otro flujo de compra.'',1;
   DECLARE @StockAnterior INT,@CostoAnterior DECIMAL(12,2),@StockNuevo BIGINT,
    @CostoPromedio DECIMAL(12,2)=NULL,@PoliticaCosto VARCHAR(25)=''SIN_COSTO_RECEPCION'';
   SELECT @StockAnterior=Stock,@CostoAnterior=PrecioCosto FROM dbo.Producto WITH(UPDLOCK,HOLDLOCK) WHERE ProductoId=@ProductoId AND Activo=1;
   IF @StockAnterior IS NULL THROW 58004,''Producto inexistente o inactivo.'',1;
   SET @StockNuevo=CONVERT(BIGINT,@StockAnterior)+CONVERT(BIGINT,@Cantidad);
   IF @StockNuevo>2147483647 OR @StockAnterior<0 THROW 58005,''Stock fuera de rango.'',1;
   IF @CostoUnitario IS NOT NULL
   BEGIN
    IF @StockAnterior=0
    BEGIN
     SET @CostoPromedio=TRY_CONVERT(DECIMAL(12,2),@CostoUnitario);
     SET @PoliticaCosto=''INICIAL'';
    END
    ELSE
    BEGIN
     IF @CostoAnterior IS NULL OR @CostoAnterior<0 THROW 58008,''Stock previo con costo desconocido o invalido; requiere valoracion autorizada.'',1;
     DECLARE @ValorAnterior DECIMAL(30,2)=@CostoAnterior*CONVERT(DECIMAL(10,0),@StockAnterior),
      @ValorIngreso DECIMAL(30,2)=@CostoUnitario*CONVERT(DECIMAL(10,0),@Cantidad),
      @Centavos DECIMAL(31,0),@Residuo DECIMAL(31,0),@CentavosRedondeados DECIMAL(31,0);
     SET @Centavos=CONVERT(DECIMAL(31,0),(CONVERT(DECIMAL(31,2),@ValorAnterior)+CONVERT(DECIMAL(31,2),@ValorIngreso))*CONVERT(DECIMAL(3,0),100));
     -- Division exacta por cociente/resto: evita que la escala reducida de DECIMAL
     -- redondee un valor cercano a medio centavo ANTES del redondeo monetario.
     SET @Residuo=@Centavos%CONVERT(DECIMAL(10,0),@StockNuevo);
     SET @CentavosRedondeados=(@Centavos-@Residuo)/CONVERT(DECIMAL(10,0),@StockNuevo)
      +CASE WHEN @Residuo*2>=@StockNuevo THEN 1 ELSE 0 END;
     IF @CentavosRedondeados<0 OR @CentavosRedondeados>999999999999 THROW 58008,''Costo promedio fuera de DECIMAL(12,2).'',1;
     SET @CostoPromedio=CONVERT(DECIMAL(12,2),@CentavosRedondeados/CONVERT(DECIMAL(3,0),100));
     SET @PoliticaCosto=''PONDERADO'';
    END;
    IF @CostoPromedio IS NULL THROW 58008,''Costo inicial fuera de DECIMAL(12,2).'',1;
   END;
   EXEC dbo.P3_BOD_BloquearUbicaciones @ProductoId,@BodegaId,@BodegaId;
   EXEC sys.sp_set_session_context @key=N''P3_BOD.BodegaId'',@value=@BodegaId;
   EXEC dbo.sp_RegistrarRecepcionCompra @ActorUsuarioId=@ActorUsuarioId,@ProductoId=@ProductoId,@ProveedorId=@ProveedorId,@Cantidad=@Cantidad,@DocumentoRespaldo=@DocumentoRespaldo,@Motivo=@Motivo,@OperacionId=@OperacionId,@CostoUnitario=@CostoUnitario;
   -- Si un flujo heredado gano el UUID concurrentemente, 34 podria devolver replay.
   -- Con Producto aun bloqueado, exigir el ingreso nuevo antes de valorar evita adoptarlo/recalcularlo.
   IF NOT EXISTS(SELECT 1 FROM dbo.Producto WHERE ProductoId=@ProductoId AND Stock=@StockNuevo)
    THROW 58003,''La recepcion no produjo el ingreso nuevo esperado; consulte su referencia.'',1;
   -- 34 hizo UNA entrada y conserva el costo unitario ORIGINAL del documento.
   -- Esta extension propia solo cambia costo; el trigger DML existente audita el antes/despues.
   IF @CostoUnitario IS NOT NULL
   BEGIN
    EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=@ActorUsuarioId;
    EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=@OperacionId;
    EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=@Motivo;
    UPDATE dbo.Producto SET PrecioCosto=@CostoPromedio WHERE ProductoId=@ProductoId AND (PrecioCosto IS NULL OR PrecioCosto<>@CostoPromedio);
   END;
   SET @Respuesta=(SELECT CONVERT(VARCHAR(20),r.RecepcionId) RecepcionId,r.OperacionId,@BodegaId BodegaId,
    CONVERT(VARCHAR(21),d.CostoUnitario) CostoUnitario,CONVERT(VARCHAR(21),@CostoPromedio) CostoPromedio,
    CONVERT(VARCHAR(21),p.PrecioCosto) PrecioCostoResultante,CONVERT(BIT,CASE WHEN @CostoUnitario IS NULL THEN 0 ELSE 1 END) CostoPromedioAplicado,@PoliticaCosto PoliticaCosto
    FROM dbo.RecepcionCompra r JOIN dbo.DetalleRecepcionCompra d ON d.RecepcionId=r.RecepcionId JOIN dbo.Producto p ON p.ProductoId=d.ProductoId
    WHERE r.OperacionId=@OperacionId FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER);
   IF @Respuesta IS NULL THROW 58003,''Recepcion no confirmada.'',1;
   INSERT dbo.P3_BOD_Operacion(OperacionId,ActorUsuarioId,Carga,Respuesta) VALUES(@OperacionId,@ActorUsuarioId,@Carga,@Respuesta);
  END;
   EXEC sys.sp_set_session_context @key=N''P3_BOD.BodegaId'',@value=NULL;
   EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=@ActorPrevio;
   EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=@OperacionPrevia;
   EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=@MotivoPrevio;
  IF @Propia=1 COMMIT;
  SELECT @Respuesta Respuesta;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK;
   EXEC sys.sp_set_session_context @key=N''P3_BOD.BodegaId'',@value=NULL;
   EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=@ActorPrevio;
   EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=@OperacionPrevia;
   EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=@MotivoPrevio;
  THROW;
 END CATCH;
END;');
EXEC(N'CREATE OR ALTER PROCEDURE dbo.P3_BOD_ConvertirCotizacion
 @ActorUsuarioId INT,@CotizacionId INT,@OperacionId UNIQUEIDENTIFIER,@BodegaId INT,
 @Credito BIT=0,@PlazoDias INT=NULL,@NumeroCuotas INT=1
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 SET ANSI_PADDING ON; SET ANSI_WARNINGS ON; SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET NUMERIC_ROUNDABORT OFF;
 IF SESSION_CONTEXT(N''P3_BOD.BodegaId'') IS NOT NULL THROW 58003,''Contexto de bodega ya ocupado.'',1;
 DECLARE @Propia BIT=CASE WHEN @@TRANCOUNT=0 THEN 1 ELSE 0 END;
 BEGIN TRY
  IF @Propia=1 BEGIN TRANSACTION;
  EXEC dbo.P3_BOD_Autorizar @ActorUsuarioId,N''BODEGAS_CONSULTAR'';
  EXEC dbo.P3_BOD_Autorizar @ActorUsuarioId,N''COTIZACIONES_CONVERTIR'';
  EXEC dbo.P3_BOD_Autorizar @ActorUsuarioId,N''VENTAS_REGISTRAR'';
  IF @CotizacionId IS NULL OR @BodegaId IS NULL OR @Credito IS NULL OR @NumeroCuotas IS NULL OR @NumeroCuotas<1
   OR (@Credito=0 AND (@PlazoDias IS NOT NULL OR @NumeroCuotas<>1)) OR (@Credito=1 AND (@PlazoDias IS NULL OR @PlazoDias<1 OR @PlazoDias>3650 OR @NumeroCuotas>120)) THROW 58002,''Modalidad invalida.'',1;
  DECLARE @Carga NVARCHAR(MAX)=(SELECT N''COTIZACION'' Accion,@CotizacionId CotizacionId,@BodegaId BodegaId,@Credito Credito,@PlazoDias PlazoDias,@NumeroCuotas NumeroCuotas FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER),@Respuesta NVARCHAR(MAX);
  EXEC dbo.P3_BOD_Reintento @ActorUsuarioId,@OperacionId,@Carga,@Respuesta OUTPUT;
  IF @Respuesta IS NULL
  BEGIN
   IF EXISTS(SELECT 1 FROM dbo.SolicitudVentaERP WHERE OperacionId=@OperacionId) THROW 58003,''Referencia pertenece a otro flujo de venta.'',1;
   EXEC dbo.P3_BOD_ValidarBodegaVenta @ActorUsuarioId=@ActorUsuarioId,@BodegaId=@BodegaId;
   -- El converter conserva su orden cotizacion -> credito (si aplica) -> productos.
   -- No prebloquear Producto/locales ni consultar disponibilidad antes del replay del core.
   -- El espejo Kardex valida y bloquea la existencia local dentro de esa misma transaccion.
   IF @Credito=1
   BEGIN
    IF OBJECT_ID(''dbo.P3_CRE_ConvertirCotizacionCredito'',''P'') IS NULL THROW 58007,''Modulo de credito no instalado.'',1;
    -- Credito es propietario de SU contexto raiz; recibe bodega explicita y debe limpiar ambas rutas.
    EXEC dbo.P3_CRE_ConvertirCotizacionCredito @ActorUsuarioId=@ActorUsuarioId,@CotizacionId=@CotizacionId,@OperacionId=@OperacionId,@PlazoDias=@PlazoDias,@NumeroCuotas=@NumeroCuotas,@BodegaId=@BodegaId;
   END
   ELSE
   BEGIN
    EXEC sys.sp_set_session_context @key=N''P3_BOD.BodegaId'',@value=@BodegaId;
    EXEC dbo.sp_ConvertirCotizacionAFactura @CotizacionId=@CotizacionId,@ActorUsuarioId=@ActorUsuarioId,@OperacionId=@OperacionId;
   END;
   SET @Respuesta=(SELECT CotizacionId,FacturaId,Estado,@BodegaId BodegaId,@Credito Credito,@OperacionId OperacionId FROM dbo.P3_COT_Cotizacion WHERE CotizacionId=@CotizacionId AND Estado=''PROCESADA'' AND FacturaId IS NOT NULL FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
   IF @Respuesta IS NULL THROW 58003,''Conversion no confirmada.'',1;
   INSERT dbo.P3_BOD_Operacion(OperacionId,ActorUsuarioId,Carga,Respuesta) VALUES(@OperacionId,@ActorUsuarioId,@Carga,@Respuesta);
  END;
  EXEC sys.sp_set_session_context @key=N''P3_BOD.BodegaId'',@value=NULL;
  IF @Propia=1 COMMIT;
  SELECT @Respuesta Respuesta;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK;
  EXEC sys.sp_set_session_context @key=N''P3_BOD.BodegaId'',@value=NULL;
  THROW;
 END CATCH;
END;');
