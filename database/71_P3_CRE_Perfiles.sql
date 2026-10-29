SET XACT_ABORT ON; SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON;
IF DB_NAME() <> dbo.P3_INT_Destino() OR @@TRANCOUNT=0 THROW 57000,'Laboratorio y transaccion externa requeridos.',1;
GO
CREATE OR ALTER PROCEDURE dbo.P3_CRE_AdministrarCredito
 @ActorUsuarioId INT,@ClienteId INT,@Activo BIT,@Limite DECIMAL(19,2),@PlazoDias INT,
 @VersionEsperada BINARY(8),@Motivo NVARCHAR(MAX),@OperacionId UNIQUEIDENTIFIER
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 EXEC dbo.P3_CRE_ValidarEntorno;
 BEGIN TRY
  BEGIN TRANSACTION;
  EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'CREDITOS_ADMINISTRAR';
  SET @Motivo=LTRIM(RTRIM(@Motivo));
  IF @ClienteId IS NULL OR @ClienteId<1 OR @Activo IS NULL OR @Limite IS NULL OR @Limite<=0
   OR @PlazoDias IS NULL OR @PlazoDias NOT BETWEEN 1 AND 3650 OR @OperacionId IS NULL
   OR @Motivo IS NULL OR LEN(@Motivo)=0 OR DATALENGTH(@Motivo)>500
   THROW 57002,'Perfil, motivo o referencia invalidos.',1;
  DECLARE @Canon NVARCHAR(MAX)=(SELECT @ActorUsuarioId Actor,@ClienteId Cliente,@Activo Activo,@Limite Limite,
   @PlazoDias Plazo,@VersionEsperada Version,@Motivo Motivo FOR JSON PATH,WITHOUT_ARRAY_WRAPPER,INCLUDE_NULL_VALUES),
   @Hash BINARY(32),@Anterior BINARY(32),@Resultado NVARCHAR(MAX),@Antes NVARCHAR(MAX),@Lock INT,
   @Resource NVARCHAR(255)=CONCAT(N'P3_CRE.Perfil.',@OperacionId);
  SET @Hash=HASHBYTES('SHA2_256',@Canon);
  EXEC @Lock=sys.sp_getapplock @Resource=@Resource,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
  IF @Lock<0 THROW 57003,'Operacion ocupada; conserve UUID.',1;
  SELECT @Anterior=SolicitudHash,@Resultado=Resultado FROM dbo.P3_CRE_Operacion WITH(UPDLOCK,HOLDLOCK) WHERE OperacionId=@OperacionId;
  IF @Anterior IS NOT NULL
  BEGIN
   IF @Anterior<>@Hash THROW 57003,'Referencia reutilizada con otros datos.',1;
  END
  ELSE
  BEGIN
   DECLARE @Version BINARY(8),@Deuda DECIMAL(38,2);
   SELECT @Version=Version FROM dbo.Credito_Cliente WITH(UPDLOCK,HOLDLOCK) WHERE ClienteId=@ClienteId;
   IF NOT EXISTS(SELECT 1 FROM dbo.Cliente WITH(HOLDLOCK) WHERE ClienteId=@ClienteId AND Activo=1)
    THROW 57004,'Cliente inexistente o inactivo.',1;
   IF (@Version IS NULL AND @VersionEsperada IS NOT NULL) OR (@Version IS NOT NULL AND (@VersionEsperada IS NULL OR @Version<>@VersionEsperada))
    THROW 57003,'Version obsoleta; consulte el perfil.',1;
   SELECT @Deuda=COALESCE(SUM(Saldo),0) FROM dbo.P3_CRE_Cuenta WHERE ClienteId=@ClienteId;
   IF @Limite<@Deuda THROW 57005,'El limite no puede ser inferior a la deuda.',1;
   SELECT @Antes=(SELECT Activo,Limite,PlazoDias,CONVERT(VARCHAR(16),CONVERT(BINARY(8),Version),2) Version FROM dbo.Credito_Cliente WHERE ClienteId=@ClienteId FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
   IF @Version IS NULL INSERT dbo.Credito_Cliente(ClienteId,Activo,Limite,PlazoDias) VALUES(@ClienteId,@Activo,@Limite,@PlazoDias);
   ELSE UPDATE dbo.Credito_Cliente SET Activo=@Activo,Limite=@Limite,PlazoDias=@PlazoDias WHERE ClienteId=@ClienteId;
   SELECT @Resultado=(SELECT ClienteId,Activo,CONVERT(VARCHAR(21),Limite) Limite,PlazoDias,CONVERT(VARCHAR(16),CONVERT(BINARY(8),Version),2) Version,
    @OperacionId OperacionId FROM dbo.Credito_Cliente WHERE ClienteId=@ClienteId FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
   INSERT dbo.P3_CRE_Operacion(OperacionId,SolicitudHash,Resultado) VALUES(@OperacionId,@Hash,@Resultado);
   DECLARE @Razon NVARCHAR(250)=@Motivo;
   EXEC dbo.P3_CRE_Auditar @ClienteId,NULL,'PERFIL',@ActorUsuarioId,@OperacionId,@Razon,@Antes,@Resultado;
  END;
  COMMIT;
  SELECT * FROM OPENJSON(@Resultado) WITH(ClienteId INT,Activo BIT,Limite VARCHAR(21),PlazoDias INT,Version VARCHAR(16),OperacionId UNIQUEIDENTIFIER);
 END TRY BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK; THROW; END CATCH;
END;
GO
