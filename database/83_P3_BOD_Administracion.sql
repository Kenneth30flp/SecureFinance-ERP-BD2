SET NOCOUNT ON; SET XACT_ABORT ON; SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON;
IF DB_NAME() COLLATE Latin1_General_100_BIN2<>dbo.P3_INT_Destino() OR DATALENGTH(DB_NAME())<>DATALENGTH(dbo.P3_INT_Destino()) OR @@TRANCOUNT=0 OR XACT_STATE()<>1 THROW 58000,'Laboratorio y transaccion externa requeridos.',1;
EXEC(N'CREATE OR ALTER PROCEDURE dbo.P3_BOD_GuardarBodega
 @ActorUsuarioId INT,@OperacionId UNIQUEIDENTIFIER,@Nombre NVARCHAR(100),@Activo BIT,@IsCentral BIT,
 @Motivo NVARCHAR(250),@BodegaId INT=NULL,@VersionEsperada BINARY(8)=NULL
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 SET ANSI_PADDING ON; SET ANSI_WARNINGS ON; SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET NUMERIC_ROUNDABORT OFF;
 DECLARE @Propia BIT=CASE WHEN @@TRANCOUNT=0 THEN 1 ELSE 0 END;
 BEGIN TRY
  IF @Propia=1 BEGIN TRANSACTION;
  EXEC dbo.P3_BOD_Autorizar @ActorUsuarioId,N''BODEGAS_ADMINISTRAR'';
  IF @Activo IS NULL OR @IsCentral IS NULL OR (@IsCentral=1 AND @Activo=0) OR NULLIF(LTRIM(RTRIM(@Nombre)),N'''') IS NULL OR NULLIF(LTRIM(RTRIM(@Motivo)),N'''') IS NULL OR (@BodegaId IS NOT NULL AND @VersionEsperada IS NULL) THROW 58002,''Datos de bodega invalidos.'',1;
  DECLARE @Carga NVARCHAR(MAX)=(SELECT N''BODEGA'' Accion,@BodegaId BodegaId,@Nombre Nombre,@Activo Activo,@IsCentral IsCentral,CONVERT(VARCHAR(16),@VersionEsperada,2) Version,@Motivo Motivo FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER),@Respuesta NVARCHAR(MAX),@N BIGINT;
  EXEC dbo.P3_BOD_Reintento @ActorUsuarioId,@OperacionId,@Carga,@Respuesta OUTPUT;
  IF @Respuesta IS NULL
  BEGIN
   -- Administracion infrecuente: barrera global de productos antes de ubicaciones.
   -- Evita que desactivacion/cambio de central compita con un despacho/venta.
   SELECT @N=COUNT_BIG(*) FROM dbo.Producto WITH(TABLOCKX,HOLDLOCK);
   IF @BodegaId IS NOT NULL AND NOT EXISTS(SELECT 1 FROM dbo.P3_BOD_Bodega WITH(UPDLOCK,HOLDLOCK) WHERE BodegaId=@BodegaId AND Version=@VersionEsperada) THROW 58003,''Bodega o version obsoleta.'',1;
   IF @Activo=0 AND (EXISTS(SELECT 1 FROM dbo.P3_BOD_Stock WITH(HOLDLOCK) WHERE BodegaId=@BodegaId AND Cantidad>0) OR EXISTS(SELECT 1 FROM dbo.P3_BOD_Transferencia WITH(HOLDLOCK) WHERE (OrigenId=@BodegaId OR DestinoId=@BodegaId) AND Estado IN(''PREPARADA'',''DESPACHADA''))) THROW 58005,''Bodega con stock o transferencias pendientes.'',1;
   IF @IsCentral=0 AND EXISTS(SELECT 1 FROM dbo.P3_BOD_Bodega WHERE BodegaId=@BodegaId AND IsCentral=1) THROW 58002,''Asigne primero otra bodega central activa.'',1;
   IF EXISTS(SELECT 1 FROM dbo.P3_BOD_Bodega WHERE Nombre=@Nombre AND (@BodegaId IS NULL OR BodegaId<>@BodegaId)) THROW 58003,''Nombre de bodega ya utilizado.'',1;
   IF @IsCentral=1 UPDATE dbo.P3_BOD_Bodega SET IsCentral=0 WHERE IsCentral=1;
   IF @BodegaId IS NULL
   BEGIN
    INSERT dbo.P3_BOD_Bodega(Nombre,Activo,IsCentral) VALUES(@Nombre,@Activo,@IsCentral);
    SET @BodegaId=CONVERT(INT,SCOPE_IDENTITY());
   END
   ELSE UPDATE dbo.P3_BOD_Bodega SET Nombre=@Nombre,Activo=@Activo,IsCentral=@IsCentral WHERE BodegaId=@BodegaId;
   IF @IsCentral=1 UPDATE dbo.P3_BOD_Configuracion SET CentralId=@BodegaId WHERE ConfiguracionId=1;
   SET @Respuesta=(SELECT BodegaId,Nombre,Activo,IsCentral,CONVERT(VARCHAR(16),CAST(Version AS varbinary(8)),2) Version,@OperacionId OperacionId FROM dbo.P3_BOD_Bodega WHERE BodegaId=@BodegaId FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
   INSERT dbo.P3_BOD_Operacion(OperacionId,ActorUsuarioId,Carga,Respuesta) VALUES(@OperacionId,@ActorUsuarioId,@Carga,@Respuesta);
   INSERT dbo.Bitacora_Transacciones(TablaAfectada,Operacion,IdentificadorRegistro,ValorNuevo,ActorUsuarioId,OperacionId,Motivo)
   VALUES(N''P3_BOD_Bodega'',CASE WHEN @VersionEsperada IS NULL THEN ''INSERT'' ELSE ''UPDATE'' END,CONVERT(NVARCHAR(20),@BodegaId),@Respuesta,@ActorUsuarioId,@OperacionId,@Motivo);
  END;
  IF @Propia=1 COMMIT;
  SELECT @Respuesta Respuesta;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK;
  THROW;
 END CATCH;
END;');
