SET XACT_ABORT ON; SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON;
IF DB_NAME() <> N'SecureFinanceERP_Lab_Dylan' OR @@TRANCOUNT=0 THROW 57000,'Laboratorio y transaccion externa requeridos.',1;
GO
-- INTERNAL: caller owns transaction. Lock profile before invoice/products; never store available credit.
CREATE OR ALTER PROCEDURE dbo.P3_CRE_ValidarFinanciacion
 @ActorUsuarioId INT,@ClienteId INT,@PlazoDias INT,@NumeroCuotas INT,@Total DECIMAL(19,2)=NULL
AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.P3_CRE_ValidarEntorno;
 IF @@TRANCOUNT=0 THROW 57000,'Financiacion requiere transaccion.',1;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'CREDITOS_FACTURAR';
 IF @PlazoDias IS NULL OR @NumeroCuotas IS NULL OR @PlazoDias NOT BETWEEN 1 AND 3650
  OR @NumeroCuotas NOT BETWEEN 1 AND 120 OR @NumeroCuotas>@PlazoDias THROW 57002,'Plan invalido.',1;
 DECLARE @Limite DECIMAL(19,2),@Activo BIT,@Plazo INT,@Deuda DECIMAL(38,2);
 SELECT @Limite=Limite,@Activo=Activo,@Plazo=PlazoDias FROM dbo.Credito_Cliente WITH(UPDLOCK,HOLDLOCK) WHERE ClienteId=@ClienteId;
 IF @Limite IS NULL OR @Activo<>1 THROW 57005,'Credito no autorizado o inactivo.',1;
 IF NOT EXISTS(SELECT 1 FROM dbo.Cliente WITH(HOLDLOCK) WHERE ClienteId=@ClienteId AND Activo=1) THROW 57004,'Cliente inactivo.',1;
 IF @PlazoDias>@Plazo THROW 57005,'Plazo supera autorizacion.',1;
 SELECT @Deuda=COALESCE(SUM(Saldo),0) FROM dbo.P3_CRE_Cuenta WHERE ClienteId=@ClienteId;
 -- Compare the wide SUM before narrowing. Never add DECIMAL(38,2): SQL may reduce its scale.
 IF @Deuda>@Limite THROW 57005,'Deuda superior al limite; requiere conciliacion.',1;
 IF @Total IS NOT NULL AND (@Total<=0 OR @Total<CONVERT(DECIMAL(19,2),@NumeroCuotas)/100
  OR @Total>@Limite-CONVERT(DECIMAL(19,2),@Deuda))
  THROW 57005,'Total definitivo excede disponible o no admite cuotas positivas.',1;
END;
GO
CREATE OR ALTER PROCEDURE dbo.P3_CRE_CrearCuenta
 @ActorUsuarioId INT,@ClienteId INT,@FacturaId INT,@PlazoDias INT,@NumeroCuotas INT,@OperacionId UNIQUEIDENTIFIER
AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.P3_CRE_ValidarEntorno;
 IF @@TRANCOUNT=0 OR @OperacionId IS NULL THROW 57000,'Cuenta requiere transaccion y operacion.',1;
 -- Establish profile lock BEFORE reading invoice, including internal callers.
 EXEC dbo.P3_CRE_ValidarFinanciacion @ActorUsuarioId,@ClienteId,@PlazoDias,@NumeroCuotas;
 DECLARE @Total DECIMAL(19,2),@Fecha DATETIME2(3);
 SELECT @Total=Total,@Fecha=FechaHora FROM dbo.Factura WITH(UPDLOCK,HOLDLOCK)
 WHERE FacturaId=@FacturaId AND ClienteId=@ClienteId AND Estado='EMITIDA';
 IF @Total IS NULL OR EXISTS(SELECT 1 FROM dbo.MovimientoCaja WHERE FacturaId=@FacturaId)
  OR EXISTS(SELECT 1 FROM dbo.P3_CRE_Cuenta WHERE FacturaId=@FacturaId) THROW 57003,'Factura incompatible con cuenta nueva.',1;
 EXEC dbo.P3_CRE_ValidarFinanciacion @ActorUsuarioId,@ClienteId,@PlazoDias,@NumeroCuotas,@Total;
 INSERT dbo.P3_CRE_Cuenta(FacturaId,ClienteId,Total,Saldo,FechaHora,PlazoDias,NumeroCuotas)
 VALUES(@FacturaId,@ClienteId,@Total,@Total,@Fecha,@PlazoDias,@NumeroCuotas);
 DECLARE @I INT=1,@Base DECIMAL(19,2)=CONVERT(DECIMAL(19,2),FLOOR(@Total*100/@NumeroCuotas)/100),@Importe DECIMAL(19,2);
 WHILE @I<=@NumeroCuotas
 BEGIN
  SET @Importe=CASE WHEN @I=@NumeroCuotas THEN @Total-@Base*(@NumeroCuotas-1) ELSE @Base END;
  INSERT dbo.P3_CRE_Cuota(FacturaId,Numero,VenceEn,Importe)
  VALUES(@FacturaId,@I,DATEADD(DAY,(@PlazoDias*@I+@NumeroCuotas-1)/@NumeroCuotas,@Fecha),@Importe);
  SET @I+=1;
 END;
 DECLARE @Json NVARCHAR(MAX)=(SELECT @FacturaId FacturaId,@Total Total,@PlazoDias PlazoDias,@NumeroCuotas NumeroCuotas FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
 EXEC dbo.P3_CRE_Auditar @ClienteId,@FacturaId,'VENTA_CREDITO',@ActorUsuarioId,@OperacionId,N'Financiacion de venta',NULL,@Json;
END;
GO
