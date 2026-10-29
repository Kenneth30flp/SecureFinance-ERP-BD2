-- 61: motor determinista de promociones. Sin SQL dinámico, sin tablas temporales.
-- Repetible (CREATE OR ALTER). Requiere 60.
--
-- Reglas de cálculo por línea (Subtotal = PrecioUnitario × Cantidad, DECIMAL(19,2)):
--  PORCENTAJE / CATEGORIA / VOLUMEN: BeneficioTeorico = ROUND(Subtotal × Porcentaje / 100, 2).
--  DOS_POR_UNO: UnidadesBonificadas = FLOOR(Cantidad / 2); BeneficioTeorico = Precio × Bonificadas.
--  TopeDescuento (opcional) limita BeneficioTeorico por línea.
--  El importe registrable debe cumplir el CHECK existente de DetalleFactura:
--  DescuentoMonto = ROUND(Subtotal × DescuentoPorcentaje / 100, 2) con DECIMAL(5,2).
--  Para porcentajes sin tope se usa el porcentaje configurado (importe exacto). En 2x1 y
--  topes se usa el MAYOR porcentaje de dos decimales cuyo importe NO supera el beneficio
--  teórico; nunca se concede más de lo autorizado. Redondeo: ROUND a centavos (mitad arriba).
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
IF OBJECT_ID('dbo.P3_PRO_Promocion','U') IS NULL THROW 57100,'Requiere migracion 60.',1;
GO
CREATE OR ALTER FUNCTION dbo.P3_PRO_fn_Estados(@Ahora DATETIME2(3))
RETURNS TABLE AS RETURN
 SELECT p.PromocionId,
  CONVERT(VARCHAR(10),CASE WHEN p.VigenteHasta<=@Ahora THEN 'VENCIDA' WHEN p.Activa=0 THEN 'INACTIVA'
   WHEN p.VigenteDesde>@Ahora THEN 'PROGRAMADA' ELSE 'VIGENTE' END) Estado
 FROM dbo.P3_PRO_Promocion p;
GO
-- Instantánea JSON de la regla: historial anterior/nuevo y evidencia conservada en la factura.
CREATE OR ALTER FUNCTION dbo.P3_PRO_fn_Regla(@PromocionId INT)
RETURNS NVARCHAR(MAX) AS
BEGIN
 RETURN (SELECT p.PromocionId,p.Codigo,p.Nombre,p.Descripcion,p.TipoCodigo,
   CONVERT(VARCHAR(6),p.Porcentaje) Porcentaje,p.CantidadMinima,CONVERT(VARCHAR(21),p.TopeDescuento) TopeDescuento,
   p.VigenteDesde,p.VigenteHasta,p.Activa,
   JSON_QUERY(COALESCE((SELECT x.ProductoId FROM dbo.P3_PRO_PromocionProducto x WHERE x.PromocionId=p.PromocionId ORDER BY x.ProductoId FOR JSON PATH),N'[]')) Productos,
   JSON_QUERY(COALESCE((SELECT x.CategoriaId FROM dbo.P3_PRO_PromocionCategoria x WHERE x.PromocionId=p.PromocionId ORDER BY x.CategoriaId FOR JSON PATH),N'[]')) Categorias
  FROM dbo.P3_PRO_Promocion p WHERE p.PromocionId=@PromocionId
  FOR JSON PATH,WITHOUT_ARRAY_WRAPPER,INCLUDE_NULL_VALUES);
END;
GO
-- Auxiliar justificada: la función escalar del PDF devuelve solo un importe; esta TVF
-- en línea expone todas las candidatas elegibles con su ranking para que la venta
-- registre QUÉ promoción ganó, sin duplicar la fórmula.
-- Desempate determinista: mayor importe registrable, mayor beneficio teórico, menor PromocionId.
CREATE OR ALTER FUNCTION dbo.P3_PRO_fn_EvaluarPromociones
 (@ProductoId INT,@CategoriaId INT,@Cantidad INT,@PrecioUnitario DECIMAL(12,2),@FechaOperacion DATETIME2(3))
RETURNS TABLE AS RETURN
WITH Base AS(
 SELECT CONVERT(DECIMAL(19,2),@PrecioUnitario*CONVERT(DECIMAL(10,0),@Cantidad)) Subtotal,
  (SELECT pc.CategoriaId FROM dbo.P3_PRO_ProductoCategoria pc
   JOIN dbo.P3_PRO_Categoria c ON c.CategoriaId=pc.CategoriaId AND c.Activa=1
   WHERE pc.ProductoId=@ProductoId) CategoriaProducto
 WHERE @ProductoId>0 AND @Cantidad>0 AND @PrecioUnitario>0 AND @FechaOperacion IS NOT NULL
),Candidatas AS(
 SELECT p.PromocionId,p.Codigo,p.Nombre,p.TipoCodigo,p.Porcentaje,p.TopeDescuento,b.Subtotal,
  CASE WHEN p.TipoCodigo='DOS_POR_UNO' THEN @Cantidad/2 ELSE 0 END UnidadesBonificadas
 FROM dbo.P3_PRO_Promocion p CROSS JOIN Base b
 WHERE p.Activa=1 AND p.VigenteDesde<=@FechaOperacion AND @FechaOperacion<p.VigenteHasta
  AND @Cantidad>=COALESCE(p.CantidadMinima,1)
  AND ((p.TipoCodigo<>'CATEGORIA' AND EXISTS(SELECT 1 FROM dbo.P3_PRO_PromocionProducto e
         WHERE e.PromocionId=p.PromocionId AND e.ProductoId=@ProductoId))
   OR (p.TipoCodigo='CATEGORIA' AND b.CategoriaProducto IS NOT NULL
       AND (@CategoriaId IS NULL OR @CategoriaId=b.CategoriaProducto)
       AND EXISTS(SELECT 1 FROM dbo.P3_PRO_PromocionCategoria e
         WHERE e.PromocionId=p.PromocionId AND e.CategoriaId=b.CategoriaProducto)))
),Beneficios AS(
 SELECT c.*,t.Bruto,
  CONVERT(DECIMAL(19,2),CASE WHEN c.TopeDescuento<t.Bruto THEN c.TopeDescuento ELSE t.Bruto END) BeneficioTeorico
 FROM Candidatas c
 CROSS APPLY(SELECT CONVERT(DECIMAL(19,2),CASE WHEN c.TipoCodigo='DOS_POR_UNO'
   THEN @PrecioUnitario*CONVERT(DECIMAL(10,0),c.UnidadesBonificadas)
   ELSE ROUND(c.Subtotal*c.Porcentaje/CONVERT(DECIMAL(5,2),100),2) END) Bruto) t
),Registrables AS(
 SELECT b.*,r.DescuentoPorcentaje,
  CONVERT(DECIMAL(19,2),ROUND(b.Subtotal*r.DescuentoPorcentaje/CONVERT(DECIMAL(5,2),100),2)) DescuentoMonto
 FROM Beneficios b
 CROSS APPLY(SELECT CONVERT(DECIMAL(5,2),FLOOR(b.BeneficioTeorico*10000/NULLIF(b.Subtotal,0))/100) Aproximado) a
 CROSS APPLY(SELECT CONVERT(DECIMAL(5,2),CASE
   WHEN b.TipoCodigo<>'DOS_POR_UNO' AND b.BeneficioTeorico=b.Bruto THEN b.Porcentaje
   ELSE (SELECT MAX(v.P) FROM (VALUES(a.Aproximado-0.01),(a.Aproximado),(a.Aproximado+0.01)) v(P)
     WHERE v.P BETWEEN 0 AND 100
      AND ROUND(b.Subtotal*CONVERT(DECIMAL(5,2),v.P)/CONVERT(DECIMAL(5,2),100),2)<=b.BeneficioTeorico) END) DescuentoPorcentaje) r
)
SELECT PromocionId,Codigo,Nombre,TipoCodigo,Subtotal,UnidadesBonificadas,BeneficioTeorico,DescuentoPorcentaje,DescuentoMonto,
 CONVERT(INT,ROW_NUMBER() OVER(ORDER BY DescuentoMonto DESC,BeneficioTeorico DESC,PromocionId ASC)) Rango
FROM Registrables WHERE DescuentoMonto>0;
GO
-- Función escalar obligatoria del PDF: mejor descuento promocional monetario elegible
-- para una línea. @CategoriaId NULL usa la categoría asignada; si se indica, debe coincidir
-- con la asignada (no permite invocar una categoría ajena). Devuelve 0.00 si no hay beneficio.
CREATE OR ALTER FUNCTION dbo.fn_ObtenerDescuentoPromocional
 (@ProductoId INT,@CategoriaId INT,@Cantidad INT,@PrecioUnitario DECIMAL(12,2),@FechaOperacion DATETIME2(3))
RETURNS DECIMAL(19,2) AS
BEGIN
 DECLARE @Monto DECIMAL(19,2);
 SELECT @Monto=DescuentoMonto
 FROM dbo.P3_PRO_fn_EvaluarPromociones(@ProductoId,@CategoriaId,@Cantidad,@PrecioUnitario,@FechaOperacion)
 WHERE Rango=1;
 RETURN COALESCE(@Monto,CONVERT(DECIMAL(19,2),0));
END;
GO
-- Política sin acumulación: por línea se aplica el MAYOR entre el descuento manual
-- autorizado y la mejor promoción; nunca ambos. En empate gana la promoción (regla trazable).
CREATE OR ALTER FUNCTION dbo.P3_PRO_fn_ResolverLinea
 (@ProductoId INT,@Cantidad INT,@PrecioUnitario DECIMAL(12,2),@DescuentoManual DECIMAL(5,2),@FechaOperacion DATETIME2(3))
RETURNS TABLE AS RETURN
SELECT b.Subtotal,b.DescuentoManualMonto,m.DescuentoPromocional,e.PromocionId,e.Codigo,e.Nombre,e.TipoCodigo,
 e.UnidadesBonificadas,e.BeneficioTeorico,e.DescuentoPorcentaje PorcentajePromocional,e.DescuentoMonto MontoPromocional,
 CONVERT(BIT,CASE WHEN m.DescuentoPromocional>0 AND m.DescuentoPromocional>=b.DescuentoManualMonto THEN 1 ELSE 0 END) AplicaPromocion
FROM (SELECT CONVERT(DECIMAL(19,2),@PrecioUnitario*CONVERT(DECIMAL(10,0),@Cantidad)) Subtotal) s
CROSS APPLY(SELECT s.Subtotal,CONVERT(DECIMAL(19,2),ROUND(s.Subtotal*@DescuentoManual/CONVERT(DECIMAL(5,2),100),2)) DescuentoManualMonto) b
CROSS APPLY(SELECT dbo.fn_ObtenerDescuentoPromocional(@ProductoId,NULL,@Cantidad,@PrecioUnitario,@FechaOperacion) DescuentoPromocional) m
OUTER APPLY(SELECT TOP(1) * FROM dbo.P3_PRO_fn_EvaluarPromociones(@ProductoId,NULL,@Cantidad,@PrecioUnitario,@FechaOperacion) WHERE Rango=1) e;
GO
-- Vista previa informativa para Facturación. No escribe, no bloquea y no reserva.
-- El cálculo definitivo lo repite sp_ProcesarVentaTransaccional al confirmar.
CREATE OR ALTER PROCEDURE dbo.P3_PRO_SimularVenta
 @ActorUsuarioId INT,@Detalle dbo.TipoDetalleVentaDescuento READONLY
AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'VENTAS_REGISTRAR';
 IF NOT EXISTS(SELECT 1 FROM @Detalle) OR (SELECT COUNT(*) FROM @Detalle)>100
  OR EXISTS(SELECT 1 FROM @Detalle WHERE ProductoId<1 OR Cantidad<1 OR DescuentoPorcentaje NOT BETWEEN 0 AND 100)
  OR EXISTS(SELECT ProductoId FROM @Detalle GROUP BY ProductoId HAVING COUNT(*)>1)
  THROW 57102,'Entre 1 y 100 lineas unicas, cantidades positivas y descuentos entre 0 y 100.',1;
 DECLARE @Ahora DATETIME2(3)=SYSUTCDATETIME();
 DECLARE @L TABLE(ProductoId INT PRIMARY KEY,Descripcion NVARCHAR(200),Cantidad INT,PrecioUnitario DECIMAL(12,2),Subtotal DECIMAL(19,2),
  DescuentoPorcentaje DECIMAL(5,2),DescuentoMonto DECIMAL(19,2),Origen VARCHAR(10),PromocionId INT,Codigo NVARCHAR(30),Nombre NVARCHAR(120),
  TipoCodigo VARCHAR(20),UnidadesBonificadas INT,BeneficioTeorico DECIMAL(19,2),DescuentoManual DECIMAL(5,2));
 INSERT @L
 SELECT d.ProductoId,p.Descripcion,d.Cantidad,p.Precio,r.Subtotal,
  CASE WHEN r.AplicaPromocion=1 THEN r.PorcentajePromocional ELSE d.DescuentoPorcentaje END,
  CASE WHEN r.AplicaPromocion=1 THEN r.MontoPromocional ELSE r.DescuentoManualMonto END,
  CASE WHEN r.AplicaPromocion=1 THEN 'PROMOCION' WHEN d.DescuentoPorcentaje>0 THEN 'MANUAL' ELSE 'NINGUNO' END,
  CASE WHEN r.AplicaPromocion=1 THEN r.PromocionId END,CASE WHEN r.AplicaPromocion=1 THEN r.Codigo END,
  r.Nombre,r.TipoCodigo,r.UnidadesBonificadas,r.BeneficioTeorico,d.DescuentoPorcentaje
 FROM @Detalle d JOIN dbo.Producto p ON p.ProductoId=d.ProductoId AND p.Activo=1
 CROSS APPLY dbo.P3_PRO_fn_ResolverLinea(d.ProductoId,d.Cantidad,p.Precio,d.DescuentoPorcentaje,@Ahora) r;
 IF (SELECT COUNT(*) FROM @L)<>(SELECT COUNT(*) FROM @Detalle) THROW 57102,'Un producto no existe o esta inactivo.',1;
 DECLARE @Subtotal DECIMAL(19,2),@Descuento DECIMAL(19,2),@Neto DECIMAL(19,2),@IVA DECIMAL(19,2);
 SELECT @Subtotal=SUM(Subtotal),@Descuento=SUM(DescuentoMonto) FROM @L;
 SET @Neto=@Subtotal-@Descuento;
 SET @IVA=ROUND(@Neto*CONVERT(DECIMAL(3,2),0.12),2);
 SELECT @Ahora FechaEvaluacion,CONVERT(VARCHAR(21),@Subtotal) Subtotal,CONVERT(VARCHAR(21),@Descuento) Descuento,
  CONVERT(VARCHAR(21),@Neto) SubtotalNeto,CONVERT(VARCHAR(21),@IVA) IVA,CONVERT(VARCHAR(21),@Neto+@IVA) Total;
 SELECT ProductoId,Descripcion,Cantidad,CONVERT(VARCHAR(21),PrecioUnitario) PrecioUnitario,CONVERT(VARCHAR(21),Subtotal) Subtotal,
  CONVERT(VARCHAR(6),DescuentoPorcentaje) DescuentoPorcentaje,CONVERT(VARCHAR(21),DescuentoMonto) DescuentoMonto,
  CONVERT(VARCHAR(21),Subtotal-DescuentoMonto) SubtotalNeto,Origen,PromocionId,Codigo,
  CASE WHEN Origen='PROMOCION' THEN Nombre END Promocion,CASE WHEN Origen='PROMOCION' THEN TipoCodigo END TipoCodigo,
  CASE WHEN Origen='PROMOCION' THEN UnidadesBonificadas ELSE 0 END UnidadesBonificadas,
  CASE WHEN Origen='PROMOCION' THEN CONVERT(VARCHAR(21),BeneficioTeorico) END BeneficioTeorico,
  CASE WHEN Origen<>'PROMOCION' AND Nombre IS NOT NULL THEN Nombre END PromocionDescartada,
  CONVERT(VARCHAR(6),DescuentoManual) DescuentoManual
 FROM @L ORDER BY ProductoId;
END;
GO
GRANT EXECUTE ON dbo.P3_PRO_SimularVenta TO securefinance_app;
DENY SELECT ON dbo.P3_PRO_fn_Estados TO securefinance_app;
DENY SELECT ON dbo.P3_PRO_fn_EvaluarPromociones TO securefinance_app;
DENY SELECT ON dbo.P3_PRO_fn_ResolverLinea TO securefinance_app;
DENY EXECUTE ON dbo.P3_PRO_fn_Regla TO securefinance_app;
DENY EXECUTE ON dbo.fn_ObtenerDescuentoPromocional TO securefinance_app;
GO
