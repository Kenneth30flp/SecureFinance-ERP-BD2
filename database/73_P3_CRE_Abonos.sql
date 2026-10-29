SET XACT_ABORT ON; SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON;
IF DB_NAME() <> N'SecureFinanceERP_Lab_Dylan' OR @@TRANCOUNT=0 THROW 57000,'Laboratorio y transaccion externa requeridos.',1;
GO
CREATE OR ALTER PROCEDURE dbo.sp_RegistrarAbonoCliente
 @ActorUsuarioId INT,@ClienteId INT,@FacturaId INT,@Monto DECIMAL(19,2),@Referencia NVARCHAR(MAX),@OperacionId UNIQUEIDENTIFIER
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 EXEC dbo.P3_CRE_ValidarEntorno;
 BEGIN TRY
  BEGIN TRANSACTION;
  EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'CREDITOS_ABONAR';
  SET @Referencia=LTRIM(RTRIM(@Referencia));
  IF @ClienteId IS NULL OR @ClienteId<1 OR @FacturaId IS NULL OR @FacturaId<1 OR @Monto IS NULL OR @Monto<=0
   OR @OperacionId IS NULL OR @Referencia IS NULL OR LEN(@Referencia)=0 OR DATALENGTH(@Referencia)>200
   THROW 57002,'Datos del abono invalidos.',1;
  DECLARE @Canon NVARCHAR(MAX)=(SELECT @ActorUsuarioId Actor,@ClienteId Cliente,@FacturaId Factura,@Monto Monto,@Referencia Referencia FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),
   @Hash BINARY(32),@Prev BINARY(32),@AbonoId BIGINT,@Lock INT,@Resource NVARCHAR(255)=CONCAT(N'P3_CRE.Abono.',@OperacionId);
  SET @Hash=HASHBYTES('SHA2_256',@Canon);
  EXEC @Lock=sys.sp_getapplock @Resource=@Resource,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
  IF @Lock<0 THROW 57003,'Abono ocupado; conserve UUID.',1;
  SELECT @AbonoId=AbonoId,@Prev=SolicitudHash FROM dbo.Abono_Factura WITH(UPDLOCK,HOLDLOCK) WHERE OperacionId=@OperacionId;
  IF @AbonoId IS NOT NULL
  BEGIN
   IF @Prev<>@Hash THROW 57003,'Referencia de abono reutilizada con otros datos.',1;
  END
  ELSE
  BEGIN
   DECLARE @Perfil INT,@Saldo DECIMAL(19,2),@Antes NVARCHAR(MAX),@Despues NVARCHAR(MAX),@Ahora DATETIME2(3)=SYSUTCDATETIME();
   SELECT @Perfil=ClienteId FROM dbo.Credito_Cliente WITH(UPDLOCK,HOLDLOCK) WHERE ClienteId=@ClienteId;
   IF @Perfil IS NULL THROW 57004,'Cliente sin perfil.',1;
   -- Repayment remains possible for administratively disabled profiles/clients.
   IF NOT EXISTS(SELECT 1 FROM dbo.Factura WITH(UPDLOCK,HOLDLOCK) WHERE FacturaId=@FacturaId AND ClienteId=@ClienteId AND Estado='EMITIDA')
    THROW 57004,'La factura no pertenece al cliente.',1;
   SELECT @Saldo=Saldo FROM dbo.P3_CRE_Cuenta WITH(UPDLOCK,HOLDLOCK) WHERE FacturaId=@FacturaId AND ClienteId=@ClienteId;
   IF @Saldo IS NULL THROW 57004,'Factura sin cuenta por cobrar.',1;
   IF @Monto>@Saldo THROW 57006,'El abono excede el saldo pendiente.',1;
   IF @Saldo<>(SELECT SUM(Importe-Abonado) FROM dbo.P3_CRE_Cuota WHERE FacturaId=@FacturaId)
    THROW 57000,'Cuenta y cuotas no concilian; no se aplico abono.',1;
   SET @Antes=(SELECT @Saldo Saldo FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
   INSERT dbo.Abono_Factura(OperacionId,SolicitudHash,FacturaId,ClienteId,ActorUsuarioId,Monto,Referencia,FechaHora,SaldoPosterior)
   VALUES(@OperacionId,@Hash,@FacturaId,@ClienteId,@ActorUsuarioId,@Monto,@Referencia,@Ahora,@Saldo-@Monto);
   SET @AbonoId=CONVERT(BIGINT,SCOPE_IDENTITY());
   DECLARE @Resto DECIMAL(19,2)=@Monto,@Numero INT,@Pendiente DECIMAL(19,2),@Aplicado DECIMAL(19,2);
   WHILE @Resto>0
   BEGIN
    SET @Numero=NULL;
    SELECT TOP(1) @Numero=Numero,@Pendiente=Importe-Abonado FROM dbo.P3_CRE_Cuota WITH(UPDLOCK,HOLDLOCK)
     WHERE FacturaId=@FacturaId AND Abonado<Importe ORDER BY VenceEn,Numero;
    IF @Numero IS NULL THROW 57000,'No hay cuotas suficientes; abono revertido.',1;
    SET @Aplicado=CASE WHEN @Resto<@Pendiente THEN @Resto ELSE @Pendiente END;
    UPDATE dbo.P3_CRE_Cuota SET Abonado=Abonado+@Aplicado WHERE FacturaId=@FacturaId AND Numero=@Numero;
    INSERT dbo.P3_CRE_AplicacionCuota(AbonoId,FacturaId,Numero,Monto) VALUES(@AbonoId,@FacturaId,@Numero,@Aplicado);
    SET @Resto-=@Aplicado;
   END;
   UPDATE dbo.P3_CRE_Cuenta SET Saldo=Saldo-@Monto WHERE FacturaId=@FacturaId;
   INSERT dbo.P3_CRE_ReciboCaja(AbonoId,Monto,FechaHora) VALUES(@AbonoId,@Monto,@Ahora);
   SET @Despues=(SELECT CONVERT(VARCHAR(20),@AbonoId) AbonoId,@Monto Monto,@Saldo-@Monto Saldo FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
   EXEC dbo.P3_CRE_Auditar @ClienteId,@FacturaId,'ABONO',@ActorUsuarioId,@OperacionId,N'Abono a factura',@Antes,@Despues;
  END;
  COMMIT;
  -- Every replay returns original immutable receipt and original post-payment balance.
  SELECT CONVERT(VARCHAR(20),a.AbonoId) AbonoId,CONVERT(VARCHAR(20),r.ReciboId) ReciboId,
   a.OperacionId,a.ClienteId,a.FacturaId,a.ActorUsuarioId,a.FechaHora,a.Referencia,
   CONVERT(VARCHAR(21),a.Monto) Monto,CONVERT(VARCHAR(21),a.SaldoPosterior) SaldoPosterior
  FROM dbo.Abono_Factura a JOIN dbo.P3_CRE_ReciboCaja r ON r.AbonoId=a.AbonoId WHERE a.AbonoId=@AbonoId;
 END TRY BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK; THROW; END CATCH;
END;
GO
