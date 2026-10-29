-- PROPOSED dependency: extension 76, pending Kenneth review. No deployment performed.
SET XACT_ABORT ON; SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON;
IF DB_NAME() <> dbo.P3_INT_Destino() OR @@TRANCOUNT=0 THROW 57000,'Laboratorio y transaccion externa requeridos.',1;
IF NOT EXISTS(SELECT 1 FROM sys.parameters WHERE object_id=OBJECT_ID('dbo.sp_ConvertirCotizacionAFactura') AND name='@P3Credito')
 THROW 57000,'Requiere extension propuesta 76 aprobada previamente.',1;
GO
CREATE OR ALTER PROCEDURE dbo.P3_CRE_ConvertirCotizacionCredito
 @ActorUsuarioId INT,@CotizacionId INT,@OperacionId UNIQUEIDENTIFIER,@PlazoDias INT,@NumeroCuotas INT=1,@BodegaId INT=NULL
AS
BEGIN
 SET NOCOUNT ON;
 -- Reject a caller's context OUTSIDE TRY and before opening/rolling back any transaction.
 IF SESSION_CONTEXT(N'P3_BOD.BodegaId') IS NOT NULL
  THROW 57009,'Contexto de bodega ocupado por otro flujo; Creditos no lo modifica.',1;
 SET XACT_ABORT ON;
 EXEC dbo.P3_CRE_ValidarEntorno;
 DECLARE @ContextoPropio BIT=0;
 BEGIN TRY
  BEGIN TRANSACTION;
  EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'CREDITOS_FACTURAR';
  IF @CotizacionId IS NULL OR @CotizacionId<1 OR @OperacionId IS NULL THROW 57002,'Cotizacion o referencia invalida.',1;
  IF @BodegaId IS NOT NULL
  BEGIN
   IF @BodegaId<1 THROW 57002,'Bodega invalida.',1;
   -- Static same-owner call needs no app GRANT; OBJECT_ID could hide an internal helper.
   BEGIN TRY
    EXEC dbo.P3_BOD_ValidarBodegaVenta @ActorUsuarioId=@ActorUsuarioId,@BodegaId=@BodegaId;
   END TRY BEGIN CATCH
    IF ERROR_NUMBER()=2812 THROW 57008,'Falta integracion P3_BOD_ValidarBodegaVenta; no se usa inventario global.',1;
    THROW;
   END CATCH;
    EXEC sys.sp_set_session_context @key=N'P3_BOD.BodegaId',@value=@BodegaId;
    SET @ContextoPropio=1;
  END;
  EXEC dbo.sp_ConvertirCotizacionAFactura @CotizacionId=@CotizacionId,@ActorUsuarioId=@ActorUsuarioId,@OperacionId=@OperacionId,
   @P3Credito=1,@P3PlazoDias=@PlazoDias,@P3NumeroCuotas=@NumeroCuotas;
  COMMIT;
  IF @ContextoPropio=1 EXEC sys.sp_set_session_context @key=N'P3_BOD.BodegaId',@value=NULL;
 END TRY BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK;
  IF @ContextoPropio=1 EXEC sys.sp_set_session_context @key=N'P3_BOD.BodegaId',@value=NULL;
  THROW;
 END CATCH;
END;
GO
GRANT EXECUTE ON dbo.P3_CRE_ConvertirCotizacionCredito TO securefinance_app;
GO
