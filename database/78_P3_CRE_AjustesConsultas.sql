-- Incremental correction after real SQL/UI review: rowversion, overdue amounts and receipt balances.
SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON; SET XACT_ABORT ON;
IF DB_NAME() COLLATE Latin1_General_100_BIN2 <> N'SecureFinanceERP_Lab_Dylan' OR @@TRANCOUNT<>1 OR XACT_STATE()<>1
 THROW 57000,'Solo laboratorio confirmado con transaccion externa.',1;
GO
CREATE OR ALTER PROCEDURE dbo.P3_CRE_Consultar
 @ActorUsuarioId INT,@ClienteId INT=NULL,@FacturaId INT=NULL,@Estado VARCHAR(10)=NULL,
 @Desde DATETIME2(3)=NULL,@Hasta DATETIME2(3)=NULL,@Desplazamiento INT=0
AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.P3_CRE_ValidarEntorno;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'CREDITOS_CONSULTAR';
 IF @Desplazamiento IS NULL OR @Desplazamiento NOT BETWEEN 0 AND 2000000 OR @ClienteId<1 OR @FacturaId<1
  OR @Desde>=@Hasta OR (@Estado IS NOT NULL AND @Estado NOT IN('PENDIENTE','PARCIAL','PAGADA','VENCIDA')) THROW 57002,'Filtros invalidos.',1;
 DECLARE @Corte datetime2(3)=SYSUTCDATETIME();
 SELECT c.FacturaId,c.ClienteId,f.ClienteNombreEmision Cliente,f.ClienteNITEmision NIT,c.FechaHora,c.VenceEn,c.Estado,
  c.PlazoDias,c.NumeroCuotas,CONVERT(varchar(21),c.Total) Total,CONVERT(varchar(21),c.Saldo) Saldo,
  CONVERT(varchar(40),COALESCE(m.Vencido,0)) SaldoVencido,COALESCE(m.Dias,0) DiasMora,@Corte FechaCorte
 FROM dbo.P3_CRE_EstadoCuenta c JOIN dbo.Factura f ON f.FacturaId=c.FacturaId
 OUTER APPLY(SELECT SUM(q.Importe-q.Abonado) Vencido,
  MAX(DATEDIFF(DAY,DATEADD(HOUR,-6,q.VenceEn),DATEADD(HOUR,-6,@Corte))) Dias
  FROM dbo.P3_CRE_Cuota q WHERE q.FacturaId=c.FacturaId AND q.Importe>q.Abonado AND q.VenceEn<=@Corte) m
 WHERE (@ClienteId IS NULL OR c.ClienteId=@ClienteId) AND (@FacturaId IS NULL OR c.FacturaId=@FacturaId)
  AND (@Estado IS NULL OR c.Estado=@Estado) AND (@Desde IS NULL OR c.FechaHora>=@Desde) AND (@Hasta IS NULL OR c.FechaHora<@Hasta)
 ORDER BY c.FechaHora DESC,c.FacturaId DESC OFFSET @Desplazamiento ROWS FETCH NEXT 21 ROWS ONLY;
 SELECT cl.ClienteId,cl.Nombre,cl.NIT,cl.Activo ClienteActivo,cr.Activo,cr.PlazoDias,
  CONVERT(varchar(21),cr.Limite) Limite,CONVERT(varchar(16),CONVERT(binary(8),cr.Version),2) Version,
  CONVERT(varchar(40),COALESCE(d.Deuda,0)) Deuda,CONVERT(varchar(40),cr.Limite-COALESCE(d.Deuda,0)) Disponible,
  CONVERT(varchar(40),COALESCE(m.Vencido,0)) SaldoVencido,COALESCE(m.Dias,0) DiasMora,@Corte FechaCorte,
  h.ActorUsuarioId AutorizadoPor,h.FechaHora FechaAutorizacion
 FROM dbo.Cliente cl LEFT JOIN dbo.Credito_Cliente cr ON cr.ClienteId=cl.ClienteId
 OUTER APPLY(SELECT SUM(Saldo) Deuda FROM dbo.P3_CRE_Cuenta c WHERE c.ClienteId=cl.ClienteId) d
 OUTER APPLY(SELECT SUM(q.Importe-q.Abonado) Vencido,
  MAX(DATEDIFF(DAY,DATEADD(HOUR,-6,q.VenceEn),DATEADD(HOUR,-6,@Corte))) Dias
  FROM dbo.P3_CRE_Cuota q JOIN dbo.P3_CRE_Cuenta c ON c.FacturaId=q.FacturaId
  WHERE c.ClienteId=cl.ClienteId AND q.Importe>q.Abonado AND q.VenceEn<=@Corte) m
 OUTER APPLY(SELECT TOP(1) ActorUsuarioId,FechaHora FROM dbo.P3_CRE_Historial
  WHERE ClienteId=cl.ClienteId AND FacturaId IS NULL ORDER BY HistorialId) h
 WHERE cl.ClienteId=@ClienteId;
 SELECT q.FacturaId,q.Numero,q.VenceEn,q.Estado,CONVERT(varchar(21),q.Importe) Importe,
  CONVERT(varchar(21),q.Abonado) Abonado,CONVERT(varchar(21),q.Saldo) Saldo
 FROM dbo.P3_CRE_EstadoCuota q JOIN dbo.P3_CRE_Cuenta c ON c.FacturaId=q.FacturaId
 WHERE q.FacturaId=@FacturaId AND (@ClienteId IS NULL OR c.ClienteId=@ClienteId) ORDER BY q.Numero;
 SELECT TOP(20) CONVERT(varchar(20),a.AbonoId) AbonoId,CONVERT(varchar(20),r.ReciboId) ReciboId,
  a.OperacionId,a.FacturaId,a.ClienteId,a.FechaHora,a.Referencia,CONVERT(varchar(21),a.Monto) Monto,
  CONVERT(varchar(21),a.SaldoPosterior) SaldoPosterior,CONVERT(varchar(21),a.Monto+a.SaldoPosterior) SaldoAnterior
 FROM dbo.Abono_Factura a JOIN dbo.P3_CRE_ReciboCaja r ON r.AbonoId=a.AbonoId
 WHERE (@ClienteId IS NULL OR a.ClienteId=@ClienteId) AND (@FacturaId IS NULL OR a.FacturaId=@FacturaId) ORDER BY a.AbonoId DESC;
 SELECT TOP(20) CONVERT(varchar(20),HistorialId) HistorialId,Evento,ActorUsuarioId,OperacionId,Motivo,FechaHora,Antes,Despues
 FROM dbo.P3_CRE_Historial WHERE (@ClienteId IS NULL OR ClienteId=@ClienteId) AND (@FacturaId IS NULL OR FacturaId=@FacturaId) ORDER BY HistorialId DESC;
END;
GO
CREATE OR ALTER PROCEDURE dbo.P3_CRE_ConsultarRecibo @ActorUsuarioId INT,@AbonoId BIGINT
AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.P3_CRE_ValidarEntorno;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'CREDITOS_CONSULTAR';
 IF @AbonoId IS NULL OR @AbonoId<=0 THROW 57002,'Abono invalido.',1;
 SELECT CONVERT(varchar(20),a.AbonoId) AbonoId,CONVERT(varchar(20),r.ReciboId) ReciboId,a.OperacionId,a.ClienteId,a.FacturaId,
  a.ActorUsuarioId,a.FechaHora,a.Referencia,CONVERT(varchar(21),a.Monto) Monto,CONVERT(varchar(21),a.SaldoPosterior) SaldoPosterior,
  CONVERT(varchar(21),a.Monto+a.SaldoPosterior) SaldoAnterior
 FROM dbo.Abono_Factura a JOIN dbo.P3_CRE_ReciboCaja r ON r.AbonoId=a.AbonoId WHERE a.AbonoId=@AbonoId;
 SELECT Numero,CONVERT(varchar(21),Monto) Monto FROM dbo.P3_CRE_AplicacionCuota WHERE AbonoId=@AbonoId ORDER BY Numero;
END;
GO
