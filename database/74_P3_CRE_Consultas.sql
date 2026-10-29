SET XACT_ABORT ON; SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON;
IF DB_NAME() <> N'SecureFinanceERP_Lab_Dylan' OR @@TRANCOUNT=0 THROW 57000,'Laboratorio y transaccion externa requeridos.',1;
GO
CREATE OR ALTER VIEW dbo.P3_CRE_EstadoCuota AS
 SELECT FacturaId,Numero,VenceEn,Importe,Abonado,Importe-Abonado Saldo,
 CONVERT(VARCHAR(10),CASE WHEN Abonado=Importe THEN 'PAGADA' WHEN VenceEn<=SYSUTCDATETIME() THEN 'VENCIDA'
  WHEN Abonado>0 THEN 'PARCIAL' ELSE 'PENDIENTE' END) Estado
 FROM dbo.P3_CRE_Cuota;
GO
CREATE OR ALTER VIEW dbo.P3_CRE_EstadoCuenta AS
 SELECT c.FacturaId,c.ClienteId,c.Total,c.Saldo,c.FechaHora,c.PlazoDias,c.NumeroCuotas,
 DATEADD(DAY,c.PlazoDias,c.FechaHora) VenceEn,
 CONVERT(VARCHAR(10),CASE WHEN c.Saldo=0 THEN 'PAGADA'
  WHEN EXISTS(SELECT 1 FROM dbo.P3_CRE_Cuota q WHERE q.FacturaId=c.FacturaId AND q.Importe>q.Abonado AND q.VenceEn<=SYSUTCDATETIME()) THEN 'VENCIDA'
  WHEN c.Saldo<c.Total THEN 'PARCIAL' ELSE 'PENDIENTE' END) Estado
 FROM dbo.P3_CRE_Cuenta c;
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
  OR @Desde>=@Hasta OR (@Estado IS NOT NULL AND @Estado NOT IN('PENDIENTE','PARCIAL','PAGADA','VENCIDA'))
  THROW 57002,'Filtros invalidos.',1;
 SELECT c.FacturaId,c.ClienteId,f.ClienteNombreEmision Cliente,f.ClienteNITEmision NIT,c.FechaHora,c.VenceEn,c.Estado,
  c.PlazoDias,c.NumeroCuotas,CONVERT(VARCHAR(21),c.Total) Total,CONVERT(VARCHAR(21),c.Saldo) Saldo
 FROM dbo.P3_CRE_EstadoCuenta c JOIN dbo.Factura f ON f.FacturaId=c.FacturaId
 WHERE (@ClienteId IS NULL OR c.ClienteId=@ClienteId) AND (@FacturaId IS NULL OR c.FacturaId=@FacturaId)
  AND (@Estado IS NULL OR c.Estado=@Estado) AND (@Desde IS NULL OR c.FechaHora>=@Desde) AND (@Hasta IS NULL OR c.FechaHora<@Hasta)
 ORDER BY c.FechaHora DESC,c.FacturaId DESC OFFSET @Desplazamiento ROWS FETCH NEXT 21 ROWS ONLY;
 SELECT cl.ClienteId,cl.Nombre,cl.NIT,cl.Activo ClienteActivo,cr.Activo,cr.PlazoDias,
  CONVERT(VARCHAR(21),cr.Limite) Limite,CONVERT(VARCHAR(16),cr.Version,2) Version,
  CONVERT(VARCHAR(40),COALESCE(d.Deuda,0)) Deuda,
  CONVERT(VARCHAR(40),cr.Limite-COALESCE(d.Deuda,0)) Disponible
 FROM dbo.Cliente cl LEFT JOIN dbo.Credito_Cliente cr ON cr.ClienteId=cl.ClienteId
 OUTER APPLY(SELECT CONVERT(DECIMAL(19,2),SUM(Saldo)) Deuda FROM dbo.P3_CRE_Cuenta c WHERE c.ClienteId=cl.ClienteId) d
 WHERE cl.ClienteId=@ClienteId;
 SELECT q.FacturaId,q.Numero,q.VenceEn,q.Estado,CONVERT(VARCHAR(21),q.Importe) Importe,
  CONVERT(VARCHAR(21),q.Abonado) Abonado,CONVERT(VARCHAR(21),q.Saldo) Saldo
 FROM dbo.P3_CRE_EstadoCuota q JOIN dbo.P3_CRE_Cuenta c ON c.FacturaId=q.FacturaId
 WHERE q.FacturaId=@FacturaId AND (@ClienteId IS NULL OR c.ClienteId=@ClienteId) ORDER BY q.Numero;
 SELECT TOP(20) CONVERT(VARCHAR(20),a.AbonoId) AbonoId,CONVERT(VARCHAR(20),r.ReciboId) ReciboId,
  a.OperacionId,a.FacturaId,a.ClienteId,a.FechaHora,a.Referencia,CONVERT(VARCHAR(21),a.Monto) Monto,
  CONVERT(VARCHAR(21),a.SaldoPosterior) SaldoPosterior
 FROM dbo.Abono_Factura a JOIN dbo.P3_CRE_ReciboCaja r ON r.AbonoId=a.AbonoId
 WHERE (@ClienteId IS NULL OR a.ClienteId=@ClienteId) AND (@FacturaId IS NULL OR a.FacturaId=@FacturaId)
 ORDER BY a.AbonoId DESC;
 SELECT TOP(20) CONVERT(VARCHAR(20),HistorialId) HistorialId,Evento,ActorUsuarioId,OperacionId,Motivo,FechaHora,Antes,Despues
 FROM dbo.P3_CRE_Historial WHERE (@ClienteId IS NULL OR ClienteId=@ClienteId) AND (@FacturaId IS NULL OR FacturaId=@FacturaId)
 ORDER BY HistorialId DESC;
END;
GO
CREATE OR ALTER PROCEDURE dbo.P3_CRE_ConsultarCaja
 @ActorUsuarioId INT,@Desde DATETIME2(3)=NULL,@Hasta DATETIME2(3)=NULL,@Desplazamiento INT=0
AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.P3_CRE_ValidarEntorno;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'CREDITOS_CONSULTAR';
 IF @Desde>=@Hasta OR @Desplazamiento IS NULL OR @Desplazamiento NOT BETWEEN 0 AND 2000000
  THROW 57002,'Filtros de caja invalidos.',1;
 -- Materialize one read for a consistent summary/page; no persistent writes or invoice debt.
 DECLARE @Caja TABLE(Origen VARCHAR(7) NOT NULL,DocumentoId VARCHAR(20) NOT NULL,
  FacturaId INT NOT NULL,AbonoId VARCHAR(20) NULL,FechaHora DATETIME2(3) NOT NULL,Monto DECIMAL(19,2) NOT NULL);
 INSERT @Caja(Origen,DocumentoId,FacturaId,AbonoId,FechaHora,Monto)
 SELECT 'CONTADO',CONVERT(VARCHAR(20),m.MovimientoCajaId),m.FacturaId,NULL,m.FechaHora,m.Monto
 FROM dbo.MovimientoCaja m
 WHERE (@Desde IS NULL OR m.FechaHora>=@Desde) AND (@Hasta IS NULL OR m.FechaHora<@Hasta)
 UNION ALL
 SELECT 'ABONO',CONVERT(VARCHAR(20),r.ReciboId),a.FacturaId,CONVERT(VARCHAR(20),a.AbonoId),r.FechaHora,r.Monto
 FROM dbo.P3_CRE_ReciboCaja r JOIN dbo.Abono_Factura a ON a.AbonoId=r.AbonoId
 WHERE (@Desde IS NULL OR r.FechaHora>=@Desde) AND (@Hasta IS NULL OR r.FechaHora<@Hasta);
 -- Global cash can exceed one invoice's DECIMAL(19,2); keep SUM at DECIMAL(38,2).
 SELECT CONVERT(VARCHAR(40),COALESCE(SUM(CASE WHEN Origen='CONTADO' THEN Monto ELSE CONVERT(DECIMAL(19,2),0) END),0)) EfectivoContado,
  CONVERT(VARCHAR(40),COALESCE(SUM(CASE WHEN Origen='ABONO' THEN Monto ELSE CONVERT(DECIMAL(19,2),0) END),0)) EfectivoAbonos,
  CONVERT(VARCHAR(40),COALESCE(SUM(Monto),0)) EfectivoTotal FROM @Caja;
 SELECT Origen,DocumentoId,FacturaId,AbonoId,FechaHora,CONVERT(VARCHAR(21),Monto) Monto FROM @Caja
 ORDER BY FechaHora DESC,Origen,DocumentoId DESC OFFSET @Desplazamiento ROWS FETCH NEXT 21 ROWS ONLY;
END;
GO
CREATE OR ALTER PROCEDURE dbo.P3_CRE_ConsultarRecibo @ActorUsuarioId INT,@AbonoId BIGINT AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.P3_CRE_ValidarEntorno;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'CREDITOS_CONSULTAR';
 IF @AbonoId IS NULL OR @AbonoId<1 THROW 57002,'Abono invalido.',1;
 SELECT CONVERT(VARCHAR(20),a.AbonoId) AbonoId,CONVERT(VARCHAR(20),r.ReciboId) ReciboId,a.OperacionId,a.ClienteId,a.FacturaId,
  a.ActorUsuarioId,a.FechaHora,a.Referencia,CONVERT(VARCHAR(21),a.Monto) Monto,CONVERT(VARCHAR(21),a.SaldoPosterior) SaldoPosterior
 FROM dbo.Abono_Factura a JOIN dbo.P3_CRE_ReciboCaja r ON r.AbonoId=a.AbonoId WHERE a.AbonoId=@AbonoId;
 SELECT Numero,CONVERT(VARCHAR(21),Monto) Monto FROM dbo.P3_CRE_AplicacionCuota WHERE AbonoId=@AbonoId ORDER BY Numero;
END;
GO
