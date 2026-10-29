-- Libro auxiliar derivado. No altera Kardex, stock ni PrecioCosto.
-- Los costos legacy DECIMAL(19,2) admiten 17 digitos enteros; conservar ese
-- dominio en costos/promedios y su producto por cantidades INT, sin overflow.
SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON; SET XACT_ABORT ON;
IF @@TRANCOUNT=0 THROW 55000,'Instalador transaccional requerido.',1;
IF OBJECT_ID('dbo.P3_COM_AplicacionRecepcion','U') IS NULL THROW 55000,'Requiere 52.',1;
IF OBJECT_ID('dbo.P3_COM_Valoracion','U') IS NULL
BEGIN
 CREATE TABLE dbo.P3_COM_Valoracion(
  KardexId BIGINT PRIMARY KEY REFERENCES dbo.Kardex_Inventario(KardexId),
  ProductoId INT NOT NULL REFERENCES dbo.Producto(ProductoId),
  StockResultante INT NOT NULL CHECK(StockResultante>=0),
  ValorAnterior DECIMAL(36,8) NULL,
  CostoAplicado DECIMAL(25,8) NULL,
  ValorResultante DECIMAL(36,8) NULL,
  PromedioResultante DECIMAL(25,8) NULL,
  Completa BIT NOT NULL,
  Razon NVARCHAR(150) NOT NULL,
  FechaCalculo DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
  ActorUsuarioId INT NOT NULL REFERENCES dbo.Usuario(UsuarioId),
  CONSTRAINT CK_P3_COM_Valoracion CHECK(
   (Completa=0 AND ValorResultante IS NULL AND PromedioResultante IS NULL) OR
   (Completa=1 AND ValorResultante IS NOT NULL AND ValorResultante>=0 AND PromedioResultante IS NOT NULL AND PromedioResultante>=0))
 );
 CREATE INDEX IX_P3_COM_ValoracionProducto ON dbo.P3_COM_Valoracion(ProductoId,KardexId DESC);
END;
IF (SELECT COUNT(*) FROM sys.columns WHERE object_id=OBJECT_ID('dbo.P3_COM_Valoracion') AND name IN('ValorAnterior','ValorResultante') AND TYPE_NAME(system_type_id)='decimal' AND precision=36 AND scale=8)<>2
 OR (SELECT COUNT(*) FROM sys.columns WHERE object_id=OBJECT_ID('dbo.P3_COM_Valoracion') AND name IN('CostoAplicado','PromedioResultante') AND TYPE_NAME(system_type_id)='decimal' AND precision=25 AND scale=8)<>2
 THROW 55000,'Precision del libro de valoracion incompatible; revisar esquema.',1;
DENY SELECT,INSERT,UPDATE,DELETE ON dbo.P3_COM_Valoracion TO securefinance_app;
GO
CREATE OR ALTER TRIGGER dbo.P3_COM_ValoracionInmutable ON dbo.P3_COM_Valoracion AFTER UPDATE,DELETE AS
BEGIN IF EXISTS(SELECT 1 FROM deleted) THROW 55005,'Valoracion historica inmutable.',1; END;
GO
CREATE OR ALTER PROCEDURE dbo.P3_COM_ActualizarValoracion @ActorUsuarioId INT,@ProductoId INT AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
 BEGIN TRANSACTION;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'COMPRAS_CONSULTAR';
 IF @ProductoId IS NULL OR @ProductoId<=0 THROW 55002,'Producto invalido.',1;
 -- Producto primero: coincide con el escritor de stock; bloquea una recepcion
 -- hasta que su detalle/costo documentado tambien este confirmado.
 DECLARE @Stock INT;
 SELECT @Stock=Stock FROM dbo.Producto WITH(UPDLOCK,HOLDLOCK) WHERE ProductoId=@ProductoId;
 IF @Stock IS NULL THROW 55004,'Producto inexistente.',1;
 DECLARE @Last BIGINT=0,@V DECIMAL(36,8)=0,@Avg DECIMAL(25,8)=0,@Saldo INT=0,@Complete BIT=1;
 SELECT TOP(1) @Last=KardexId,@V=ValorResultante,@Avg=PromedioResultante,@Saldo=StockResultante,@Complete=Completa FROM dbo.P3_COM_Valoracion WHERE ProductoId=@ProductoId ORDER BY KardexId DESC;
 DECLARE @K BIGINT,@Tipo VARCHAR(25),@Q INT,@Before INT,@After INT,@Cost DECIMAL(25,8),@Old DECIMAL(36,8),@Reason NVARCHAR(150);
 DECLARE movimientos CURSOR LOCAL FAST_FORWARD FOR SELECT KardexId,TipoMovimiento,Cantidad,StockAnterior,StockResultante FROM dbo.Kardex_Inventario WHERE ProductoId=@ProductoId AND KardexId>@Last ORDER BY KardexId;
 OPEN movimientos;
 FETCH NEXT FROM movimientos INTO @K,@Tipo,@Q,@Before,@After;
 WHILE @@FETCH_STATUS=0
 BEGIN
  IF @Last=0 AND @Before<>0 BEGIN SET @Saldo=@Before; SET @Complete=0; SET @V=NULL; SET @Avg=NULL; END;
  IF @Saldo<>@Before THROW 55007,'Libro de cantidades no conciliado.',1;
  SET @Old=@V; SET @Cost=NULL; SET @Reason=N'Saldo historico sin valoracion completa';
  IF @Tipo='COMPRA'
  BEGIN
   SELECT @Cost=COALESCE(a.CostoDocumentado,d.CostoUnitario) FROM dbo.DetalleRecepcionCompra d LEFT JOIN dbo.P3_COM_AplicacionRecepcion a ON a.KardexId=d.KardexId WHERE d.KardexId=@K;
   IF @Cost IS NULL BEGIN SET @Complete=0; SET @Reason=N'Entrada sin costo documentado'; END;
  END
  ELSE IF @Tipo='DEVOLUCION'
  BEGIN
   -- Devuelve al costo comprobado de la salida original, no al precio de venta.
   SELECT @Cost=v.CostoAplicado FROM dbo.DevolucionKardex dk JOIN dbo.DetalleDevolucion dd ON dd.DetalleDevolucionId=dk.DetalleDevolucionId
    JOIN dbo.Kardex_Inventario original ON original.DetalleFacturaId=dd.DetalleFacturaId AND original.TipoMovimiento='VENTA'
    JOIN dbo.P3_COM_Valoracion v ON v.KardexId=original.KardexId WHERE dk.KardexId=@K;
   IF @Cost IS NULL BEGIN SET @Complete=0; SET @Reason=N'Devolucion sin costo comprobado de la salida original'; END;
  END
  ELSE IF @Tipo IN('APERTURA','AJUSTE_INGRESO')
  BEGIN
   IF @Q>0 BEGIN SET @Complete=0; SET @Reason=N'Apertura o ajuste de ingreso sin costo documentado'; END;
  END
  ELSE IF @Tipo IN('VENTA','AJUSTE_EGRESO') AND @Complete=1 SET @Cost=@Avg;
  IF @Complete=1 AND @Tipo IN('COMPRA','DEVOLUCION')
   SET @V=CONVERT(DECIMAL(36,8),@V+CONVERT(DECIMAL(10,0),@Q)*@Cost);
  IF @Complete=1 AND @Tipo IN('VENTA','AJUSTE_EGRESO')
  BEGIN
   -- Prorratear el remanente con doce decimales internos evita multiplicar
   -- el promedio redondeado por miles de millones de unidades. No truncar negativos.
   SET @V=CONVERT(DECIMAL(36,8),CONVERT(DECIMAL(30,12),@V/CONVERT(DECIMAL(10,0),@Before))*CONVERT(DECIMAL(10,0),@After));
  END;
  IF @After=0 BEGIN SET @Complete=1; SET @V=0; SET @Avg=0; SET @Reason=N'Saldo cero comprobado'; END
  ELSE IF @Complete=1 BEGIN SET @Avg=CONVERT(DECIMAL(25,8),@V/CONVERT(DECIMAL(10,0),@After)); SET @Reason=N'Promedio movil con costos documentados'; END
  ELSE BEGIN SET @V=NULL; SET @Avg=NULL; END;
  INSERT dbo.P3_COM_Valoracion(KardexId,ProductoId,StockResultante,ValorAnterior,CostoAplicado,ValorResultante,PromedioResultante,Completa,Razon,ActorUsuarioId)
   VALUES(@K,@ProductoId,@After,@Old,@Cost,@V,@Avg,@Complete,@Reason,@ActorUsuarioId);
  SET @Saldo=@After; SET @Last=@K;
  FETCH NEXT FROM movimientos INTO @K,@Tipo,@Q,@Before,@After;
 END;
 CLOSE movimientos; DEALLOCATE movimientos;
 IF @Saldo<>@Stock AND @Last>0 THROW 55007,'Stock y Kardex no concilian.',1;
 COMMIT;
 SELECT @ProductoId ProductoId,@Last KardexId,@Stock Stock,
  CONVERT(BIT,CASE WHEN @Last=0 AND @Stock>0 THEN 0 ELSE @Complete END) Completa,
  CASE WHEN @Last=0 AND @Stock>0 THEN NULL ELSE CONVERT(VARCHAR(45),@V) END Valor,
  CASE WHEN @Last=0 AND @Stock>0 THEN NULL ELSE CONVERT(VARCHAR(35),@Avg) END Promedio;
 END TRY BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK; THROW; END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.P3_COM_ConsultarValoracion @ActorUsuarioId INT,@ProductoId INT,@Desplazamiento INT=0 AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'COMPRAS_CONSULTAR';
 IF @ProductoId IS NULL OR @ProductoId<=0 OR @Desplazamiento IS NULL OR @Desplazamiento NOT BETWEEN 0 AND 1000000 THROW 55002,'Filtros invalidos.',1;
 SELECT p.ProductoId,p.Codigo,p.Descripcion,p.Stock,v.KardexId,
  CONVERT(BIT,CASE WHEN k.KardexId IS NULL AND p.Stock=0 THEN 1 ELSE COALESCE(v.Completa,0) END) Completa,
  CASE WHEN k.KardexId IS NULL AND p.Stock=0 THEN N'Saldo cero sin movimientos' ELSE v.Razon END Razon,v.FechaCalculo,
  CASE WHEN k.KardexId IS NULL AND p.Stock=0 THEN '0.00000000' ELSE CONVERT(VARCHAR(45),v.ValorResultante) END Valor,
  CASE WHEN k.KardexId IS NULL AND p.Stock=0 THEN '0.00000000' ELSE CONVERT(VARCHAR(35),v.PromedioResultante) END Promedio,
  CONVERT(BIT,CASE WHEN (v.KardexId=k.KardexId AND v.StockResultante=p.Stock) OR (k.KardexId IS NULL AND p.Stock=0) THEN 1 ELSE 0 END) Actualizada
 FROM dbo.Producto p OUTER APPLY(SELECT TOP(1) * FROM dbo.P3_COM_Valoracion WHERE ProductoId=p.ProductoId ORDER BY KardexId DESC) v
 OUTER APPLY(SELECT MAX(KardexId) KardexId FROM dbo.Kardex_Inventario WHERE ProductoId=p.ProductoId) k WHERE p.ProductoId=@ProductoId;
 SELECT v.KardexId,k.TipoMovimiento,k.Cantidad,k.FechaHora,v.StockResultante,v.Completa,v.Razon,
 CONVERT(VARCHAR(35),v.CostoAplicado) CostoAplicado,CONVERT(VARCHAR(45),v.ValorResultante) Valor,CONVERT(VARCHAR(35),v.PromedioResultante) Promedio
 FROM dbo.P3_COM_Valoracion v JOIN dbo.Kardex_Inventario k ON k.KardexId=v.KardexId WHERE v.ProductoId=@ProductoId ORDER BY v.KardexId DESC OFFSET @Desplazamiento ROWS FETCH NEXT 51 ROWS ONLY;
END;
GO
GRANT EXECUTE ON dbo.P3_COM_ActualizarValoracion TO securefinance_app;
GRANT EXECUTE ON dbo.P3_COM_ConsultarValoracion TO securefinance_app;
GO
