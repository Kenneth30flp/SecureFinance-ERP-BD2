SET NOCOUNT ON; SET XACT_ABORT ON; SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON;
IF DB_NAME() COLLATE Latin1_General_100_BIN2<>N'SecureFinanceERP_Lab_Dylan' OR DATALENGTH(DB_NAME())<>DATALENGTH(N'SecureFinanceERP_Lab_Dylan') OR @@TRANCOUNT=0 OR XACT_STATE()<>1 THROW 58000,'Laboratorio y transaccion externa requeridos.',1;
EXEC(N'CREATE OR ALTER PROCEDURE dbo.sp_TransferirStockBodegas
 @ActorUsuarioId INT,@OperacionId UNIQUEIDENTIFIER,@ProductoId INT,@OrigenId INT,@DestinoId INT,
 @Cantidad INT,@Motivo NVARCHAR(250)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 SET ANSI_PADDING ON; SET ANSI_WARNINGS ON; SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET NUMERIC_ROUNDABORT OFF;
 DECLARE @Propia BIT=CASE WHEN @@TRANCOUNT=0 THEN 1 ELSE 0 END;
 BEGIN TRY
  IF @Propia=1 BEGIN TRANSACTION;
  EXEC dbo.P3_BOD_Autorizar @ActorUsuarioId,N''TRANSFERENCIAS_CREAR'';
  IF @ProductoId IS NULL OR @OrigenId IS NULL OR @DestinoId IS NULL OR @OrigenId=@DestinoId OR @Cantidad IS NULL OR @Cantidad<=0 OR NULLIF(LTRIM(RTRIM(@Motivo)),N'''') IS NULL THROW 58002,''Propuesta invalida.'',1;
  DECLARE @Carga NVARCHAR(MAX)=(SELECT N''PREPARAR'' Accion,@ProductoId ProductoId,@OrigenId OrigenId,@DestinoId DestinoId,@Cantidad Cantidad,@Motivo Motivo FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),@Respuesta NVARCHAR(MAX),@Id INT;
  EXEC dbo.P3_BOD_Reintento @ActorUsuarioId,@OperacionId,@Carga,@Respuesta OUTPUT;
  IF @Respuesta IS NULL
  BEGIN
   IF NOT EXISTS(SELECT 1 FROM dbo.Producto WITH(UPDLOCK,HOLDLOCK) WHERE ProductoId=@ProductoId AND Activo=1) THROW 58004,''Producto inexistente o inactivo.'',1;
   EXEC dbo.P3_BOD_BloquearUbicaciones @ProductoId,@OrigenId,@DestinoId;
   EXEC dbo.P3_BOD_ValidarSaldo @ProductoId;
   IF NOT EXISTS(SELECT 1 FROM dbo.P3_BOD_Stock WHERE ProductoId=@ProductoId AND BodegaId=@OrigenId AND Cantidad>=@Cantidad) THROW 58005,''Existencia local insuficiente.'',1;
   INSERT dbo.P3_BOD_Transferencia(ProductoId,OrigenId,DestinoId,Cantidad,Estado,Motivo,ActorUsuarioId)
   VALUES(@ProductoId,@OrigenId,@DestinoId,@Cantidad,''PREPARADA'',@Motivo,@ActorUsuarioId);
   SET @Id=CONVERT(INT,SCOPE_IDENTITY());
   SET @Respuesta=(SELECT TransferenciaId,Estado,CONVERT(VARCHAR(16),CAST(Version AS varbinary(8)),2) Version,@OperacionId OperacionId FROM dbo.P3_BOD_Transferencia WHERE TransferenciaId=@Id FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
   INSERT dbo.P3_BOD_Operacion(OperacionId,ActorUsuarioId,Carga,Respuesta) VALUES(@OperacionId,@ActorUsuarioId,@Carga,@Respuesta);
   INSERT dbo.Bitacora_Transacciones(TablaAfectada,Operacion,IdentificadorRegistro,ValorNuevo,ActorUsuarioId,OperacionId,Motivo)
   VALUES(N''P3_BOD_Transferencia'',''INSERT'',CONVERT(NVARCHAR(20),@Id),@Carga,@ActorUsuarioId,@OperacionId,@Motivo);
  END;
  IF @Propia=1 COMMIT;
  SELECT @Respuesta Respuesta;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK;
  THROW;
 END CATCH;
END;');
EXEC(N'CREATE OR ALTER PROCEDURE dbo.P3_BOD_AvanzarTransferencia
 @ActorUsuarioId INT,@OperacionId UNIQUEIDENTIFIER,@TransferenciaId INT,
 @Accion VARCHAR(10),@VersionEsperada BINARY(8),@Motivo NVARCHAR(250)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 SET ANSI_PADDING ON; SET ANSI_WARNINGS ON; SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET NUMERIC_ROUNDABORT OFF;
 DECLARE @Propia BIT=CASE WHEN @@TRANCOUNT=0 THEN 1 ELSE 0 END;
 BEGIN TRY
  IF @Propia=1 BEGIN TRANSACTION;
  DECLARE @Permiso NVARCHAR(100)=CASE @Accion WHEN ''DESPACHAR'' THEN N''TRANSFERENCIAS_DESPACHAR'' WHEN ''RECIBIR'' THEN N''TRANSFERENCIAS_RECIBIR'' END;
  IF @Permiso IS NULL OR @VersionEsperada IS NULL OR @TransferenciaId IS NULL OR NULLIF(LTRIM(RTRIM(@Motivo)),N'''') IS NULL THROW 58002,''Fase invalida.'',1;
  EXEC dbo.P3_BOD_Autorizar @ActorUsuarioId,@Permiso;
  DECLARE @Carga NVARCHAR(MAX)=(SELECT @Accion Accion,@TransferenciaId TransferenciaId,CONVERT(VARCHAR(16),@VersionEsperada,2) Version,@Motivo Motivo FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),@Respuesta NVARCHAR(MAX);
  EXEC dbo.P3_BOD_Reintento @ActorUsuarioId,@OperacionId,@Carga,@Respuesta OUTPUT;
  IF @Respuesta IS NULL
  BEGIN
   -- Lectura sin bloqueo retenido solo descubre identidad INMUTABLE. Nunca bloquear cabecera primero.
   DECLARE @P INT,@O INT,@D INT,@C INT,@B INT,@Anterior INT,@Nuevo BIGINT,@Estado VARCHAR(12),@Tipo VARCHAR(25);
   SELECT @P=ProductoId,@O=OrigenId,@D=DestinoId FROM dbo.P3_BOD_Transferencia WITH(READCOMMITTEDLOCK) WHERE TransferenciaId=@TransferenciaId;
   IF @P IS NULL THROW 58004,''Transferencia inexistente.'',1;
   IF NOT EXISTS(SELECT 1 FROM dbo.Producto WITH(UPDLOCK,HOLDLOCK) WHERE ProductoId=@P AND Activo=1) THROW 58004,''Producto inexistente o inactivo.'',1;
   EXEC dbo.P3_BOD_BloquearUbicaciones @P,@O,@D;
   EXEC dbo.P3_BOD_ValidarSaldo @P;
   SELECT @C=Cantidad,@Estado=Estado FROM dbo.P3_BOD_Transferencia WITH(UPDLOCK,HOLDLOCK) WHERE TransferenciaId=@TransferenciaId AND Version=@VersionEsperada;
   IF @C IS NULL OR (@Accion=''DESPACHAR'' AND @Estado<>''PREPARADA'') OR (@Accion=''RECIBIR'' AND @Estado<>''DESPACHADA'') THROW 58003,''Estado o version obsoletos.'',1;
   SET @B=CASE WHEN @Accion=''DESPACHAR'' THEN @O ELSE @D END;
   SET @Tipo=CASE WHEN @Accion=''DESPACHAR'' THEN ''TRANSFERENCIA_SALIDA'' ELSE ''TRANSFERENCIA_ENTRADA'' END;
   SELECT @Anterior=Cantidad FROM dbo.P3_BOD_Stock WHERE ProductoId=@P AND BodegaId=@B;
   SET @Nuevo=CONVERT(BIGINT,@Anterior)+CASE WHEN @Accion=''DESPACHAR'' THEN -CONVERT(BIGINT,@C) ELSE CONVERT(BIGINT,@C) END;
   IF @Nuevo<0 OR @Nuevo>2147483647 THROW 58005,''Existencia local insuficiente o fuera de rango.'',1;
   UPDATE dbo.P3_BOD_Stock SET Cantidad=CONVERT(INT,@Nuevo) WHERE ProductoId=@P AND BodegaId=@B;
   UPDATE dbo.P3_BOD_Transferencia SET Estado=CASE WHEN @Accion=''DESPACHAR'' THEN ''DESPACHADA'' ELSE ''RECIBIDA'' END WHERE TransferenciaId=@TransferenciaId AND Version=@VersionEsperada;
   IF @@ROWCOUNT<>1 THROW 58003,''La transferencia cambio.'',1;
   INSERT dbo.P3_BOD_Ledger(ProductoId,BodegaId,Tipo,Cantidad,SaldoAnterior,SaldoResultante,ActorUsuarioId,OperacionId,Referencia,Motivo,TransferenciaId)
   VALUES(@P,@B,@Tipo,@C,@Anterior,CONVERT(INT,@Nuevo),@ActorUsuarioId,@OperacionId,CONCAT(N''TRANSFERENCIA:'',@TransferenciaId),@Motivo,@TransferenciaId);
   SET @Respuesta=(SELECT TransferenciaId,Estado,CONVERT(VARCHAR(16),CAST(Version AS varbinary(8)),2) Version,@OperacionId OperacionId FROM dbo.P3_BOD_Transferencia WHERE TransferenciaId=@TransferenciaId FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
   INSERT dbo.P3_BOD_Operacion(OperacionId,ActorUsuarioId,Carga,Respuesta) VALUES(@OperacionId,@ActorUsuarioId,@Carga,@Respuesta);
   INSERT dbo.Bitacora_Transacciones(TablaAfectada,Operacion,IdentificadorRegistro,ValorAnterior,ValorNuevo,ActorUsuarioId,OperacionId,Motivo)
   VALUES(N''P3_BOD_Transferencia'',''UPDATE'',CONVERT(NVARCHAR(20),@TransferenciaId),@Estado,@Respuesta,@ActorUsuarioId,@OperacionId,@Motivo);
  END;
  IF @Propia=1 COMMIT;
  SELECT @Respuesta Respuesta;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK;
  THROW;
 END CATCH;
END;');
