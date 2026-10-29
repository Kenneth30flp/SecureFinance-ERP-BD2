-- PROPUESTA de integracion compartida pendiente de revision de Kenneth. NO desplegado.
SET NOCOUNT ON; SET XACT_ABORT ON; SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON;
IF DB_NAME() COLLATE Latin1_General_100_BIN2<>dbo.P3_INT_Destino() OR DATALENGTH(DB_NAME())<>DATALENGTH(dbo.P3_INT_Destino()) OR @@TRANCOUNT=0 OR XACT_STATE()<>1 THROW 58000,'Laboratorio y transaccion externa requeridos.',1;
EXEC(N'CREATE OR ALTER TRIGGER dbo.P3_BOD_EspejoKardex ON dbo.Kardex_Inventario AFTER INSERT
AS
BEGIN
 SET NOCOUNT ON;
 SET ANSI_PADDING ON; SET ANSI_WARNINGS ON; SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET NUMERIC_ROUNDABORT OFF;
 IF EXISTS(SELECT 1 FROM inserted WHERE TipoMovimiento NOT IN(''COMPRA'',''VENTA'',''AJUSTE_INGRESO'',''AJUSTE_EGRESO'',''DEVOLUCION'',''APERTURA'')) THROW 58002,''Movimiento sin integracion local definida.'',1;
 -- APERTURA global describe stock ya incluido en el snapshot local. No duplicarlo.
 IF NOT EXISTS(SELECT 1 FROM inserted WHERE TipoMovimiento<>''APERTURA'') RETURN;
 IF DB_NAME() COLLATE Latin1_General_100_BIN2<>dbo.P3_INT_Destino() OR DATALENGTH(DB_NAME())<>DATALENGTH(dbo.P3_INT_Destino()) THROW 58000,''Base no autorizada para Mod5.'',1;
 DECLARE @Raw SQL_VARIANT=SESSION_CONTEXT(N''P3_BOD.BodegaId''),@B INT,@P INT=0,@Next INT,@Activo BIT;
 IF @Raw IS NOT NULL AND (SQL_VARIANT_PROPERTY(@Raw,''BaseType'')<>''int'' OR TRY_CONVERT(INT,@Raw)<=0) THROW 58002,''Contexto de bodega invalido.'',1;
 -- Primero TODOS los productos por PK ascendente; luego ubicaciones. Multirow seguro.
 WHILE 1=1
 BEGIN
  SELECT @Next=MIN(ProductoId) FROM inserted WHERE TipoMovimiento<>''APERTURA'' AND ProductoId>@P;
  IF @Next IS NULL BREAK;
  SET @P=@Next; SET @Activo=NULL;
  SELECT @Activo=Activo FROM dbo.Producto WITH(UPDLOCK,HOLDLOCK) WHERE ProductoId=@P;
  IF ISNULL(@Activo,0)=0 THROW 58004,''Producto inexistente o inactivo.'',1;
 END;
 SET @B=CASE WHEN @Raw IS NOT NULL THEN CONVERT(INT,@Raw) ELSE (SELECT CentralId FROM dbo.P3_BOD_Configuracion WITH(HOLDLOCK) WHERE ConfiguracionId=1) END;
 IF @B IS NULL OR NOT EXISTS(SELECT 1 FROM dbo.P3_BOD_Bodega WITH(HOLDLOCK) WHERE BodegaId=@B AND Activo=1) THROW 58004,''Bodega inexistente o inactiva.'',1;
 DECLARE @K BIGINT,@C INT,@Actor INT,@Op UNIQUEIDENTIFIER,@Tipo VARCHAR(25),@Ref NVARCHAR(100),@Motivo NVARCHAR(250),@Fecha DATETIME2(3),@Anterior INT,@Nuevo BIGINT,@Permiso NVARCHAR(100);
 DECLARE Mov CURSOR LOCAL FAST_FORWARD FOR SELECT KardexId,ProductoId,Cantidad,UsuarioId,OperacionId,TipoMovimiento,DocumentoRespaldo,Motivo,FechaHora FROM inserted WHERE TipoMovimiento<>''APERTURA'' ORDER BY ProductoId,KardexId;
 OPEN Mov;
 FETCH NEXT FROM Mov INTO @K,@P,@C,@Actor,@Op,@Tipo,@Ref,@Motivo,@Fecha;
 WHILE @@FETCH_STATUS=0
 BEGIN
  SET @Permiso=CASE WHEN @Tipo IN(''AJUSTE_INGRESO'',''AJUSTE_EGRESO'') THEN N''INVENTARIO_AJUSTAR'' WHEN @Tipo=''VENTA'' THEN N''VENTAS_REGISTRAR'' ELSE N''INVENTARIO_REGISTRAR'' END;
  EXEC dbo.sp_ParteII_ValidarPermiso @Actor,@Permiso;
  IF NOT EXISTS(SELECT 1 FROM dbo.P3_BOD_Stock WITH(UPDLOCK,HOLDLOCK) WHERE ProductoId=@P AND BodegaId=@B) INSERT dbo.P3_BOD_Stock(ProductoId,BodegaId,Cantidad) VALUES(@P,@B,0);
  SELECT @Anterior=Cantidad FROM dbo.P3_BOD_Stock WHERE ProductoId=@P AND BodegaId=@B;
  SET @Nuevo=CONVERT(BIGINT,@Anterior)+CASE WHEN @Tipo IN(''VENTA'',''AJUSTE_EGRESO'') THEN -CONVERT(BIGINT,@C) ELSE CONVERT(BIGINT,@C) END;
  IF @Nuevo<0 OR @Nuevo>2147483647 THROW 58005,''Existencia local insuficiente o fuera de rango.'',1;
  UPDATE dbo.P3_BOD_Stock SET Cantidad=CONVERT(INT,@Nuevo) WHERE ProductoId=@P AND BodegaId=@B;
  INSERT dbo.P3_BOD_Ledger(ProductoId,BodegaId,Tipo,Cantidad,SaldoAnterior,SaldoResultante,ActorUsuarioId,OperacionId,Referencia,Motivo,KardexId,FechaHora)
  VALUES(@P,@B,@Tipo,@C,@Anterior,CONVERT(INT,@Nuevo),@Actor,@Op,@Ref,@Motivo,@K,@Fecha);
  FETCH NEXT FROM Mov INTO @K,@P,@C,@Actor,@Op,@Tipo,@Ref,@Motivo,@Fecha;
 END;
 CLOSE Mov; DEALLOCATE Mov;
 SET @P=0;
 WHILE 1=1
 BEGIN
  SELECT @Next=MIN(ProductoId) FROM inserted WHERE TipoMovimiento<>''APERTURA'' AND ProductoId>@P;
  IF @Next IS NULL BREAK;
  SET @P=@Next;
  EXEC dbo.P3_BOD_ValidarSaldo @P;
 END;
 -- NUNCA UPDATE Producto.Stock: lo hizo el SP central dentro de la MISMA transaccion.
END;');
