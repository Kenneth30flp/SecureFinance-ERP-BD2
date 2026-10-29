SET NOCOUNT ON; SET XACT_ABORT ON; SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON;
IF DB_NAME() COLLATE Latin1_General_100_BIN2<>N'SecureFinanceERP_Lab_Dylan' OR DATALENGTH(DB_NAME())<>DATALENGTH(N'SecureFinanceERP_Lab_Dylan') OR @@TRANCOUNT=0 OR XACT_STATE()<>1 THROW 58000,'Laboratorio y transaccion externa requeridos.',1;
EXEC(N'CREATE OR ALTER VIEW dbo.P3_BOD_Conciliacion AS
 SELECT p.ProductoId,p.Codigo,p.Descripcion,p.Stock,
 COALESCE(s.Local,CONVERT(BIGINT,0)) StockLocal,COALESCE(t.Transito,CONVERT(BIGINT,0)) Transito,
 CONVERT(BIGINT,p.Stock)-COALESCE(s.Local,0)-COALESCE(t.Transito,0) Diferencia
 FROM dbo.Producto p
 OUTER APPLY(SELECT SUM(CONVERT(BIGINT,Cantidad)) Local FROM dbo.P3_BOD_Stock WHERE ProductoId=p.ProductoId) s
 OUTER APPLY(SELECT SUM(CONVERT(BIGINT,Cantidad)) Transito FROM dbo.P3_BOD_Transferencia WHERE ProductoId=p.ProductoId AND Estado=''DESPACHADA'') t;');
EXEC(N'CREATE OR ALTER PROCEDURE dbo.P3_BOD_Consultar
 @ActorUsuarioId INT,@Seccion VARCHAR(15),@BodegaId INT=NULL,@ProductoId INT=NULL,
 @TransferenciaId INT=NULL,@Desplazamiento INT=0,@Desde DATETIME2(3)=NULL,@Hasta DATETIME2(3)=NULL
AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.P3_BOD_Autorizar @ActorUsuarioId,N''BODEGAS_CONSULTAR'';
 IF @Seccion IS NULL OR @Seccion NOT IN(''bodegas'',''inventario'',''transferencias'',''kardex'',''detalle'') OR @Desplazamiento IS NULL OR @Desplazamiento<0 OR @Desplazamiento>2000000 OR @BodegaId<=0 OR @ProductoId<=0 OR @Desde>=@Hasta OR (@Seccion=''detalle'' AND (@TransferenciaId IS NULL OR @TransferenciaId<=0)) THROW 58002,''Filtros invalidos.'',1;
 IF @Seccion=''bodegas''
 BEGIN
  SELECT b.BodegaId,b.Nombre,b.Activo,b.IsCentral,CONVERT(VARCHAR(16),b.Version,2) Version,COALESCE(s.Stock,0) Stock
  FROM dbo.P3_BOD_Bodega b OUTER APPLY(SELECT SUM(CONVERT(BIGINT,Cantidad)) Stock FROM dbo.P3_BOD_Stock WHERE BodegaId=b.BodegaId) s
  WHERE (@BodegaId IS NULL OR b.BodegaId=@BodegaId) ORDER BY b.BodegaId OFFSET @Desplazamiento ROWS FETCH NEXT 21 ROWS ONLY;
  RETURN;
 END;
 IF @Seccion=''inventario''
 BEGIN
  SELECT c.*,s.Cantidad ExistenciaBodega FROM dbo.P3_BOD_Conciliacion c LEFT JOIN dbo.P3_BOD_Stock s ON s.ProductoId=c.ProductoId AND s.BodegaId=@BodegaId
  WHERE (@ProductoId IS NULL OR c.ProductoId=@ProductoId) ORDER BY c.ProductoId OFFSET @Desplazamiento ROWS FETCH NEXT 21 ROWS ONLY;
  SELECT SUM(CONVERT(BIGINT,p.Stock)) StockGlobal,SUM(CONVERT(BIGINT,c.StockLocal)) StockLocal,SUM(CONVERT(BIGINT,c.Transito)) Transito,
   SUM(CASE WHEN c.Diferencia<>0 THEN CONVERT(BIGINT,1) ELSE CONVERT(BIGINT,0) END) Descuadres
  FROM dbo.Producto p JOIN dbo.P3_BOD_Conciliacion c ON c.ProductoId=p.ProductoId WHERE (@ProductoId IS NULL OR p.ProductoId=@ProductoId);
  RETURN;
 END;
 IF @Seccion IN(''transferencias'',''detalle'')
 BEGIN
  SELECT t.TransferenciaId,t.ProductoId,p.Codigo,p.Descripcion,t.OrigenId,o.Nombre Origen,t.DestinoId,d.Nombre Destino,t.Cantidad,t.Estado,t.Motivo,t.ActorUsuarioId,t.FechaHora,CONVERT(VARCHAR(16),t.Version,2) Version
  FROM dbo.P3_BOD_Transferencia t JOIN dbo.P3_BOD_Bodega o ON o.BodegaId=t.OrigenId JOIN dbo.P3_BOD_Bodega d ON d.BodegaId=t.DestinoId JOIN dbo.Producto p ON p.ProductoId=t.ProductoId
  WHERE (@ProductoId IS NULL OR t.ProductoId=@ProductoId) AND (@BodegaId IS NULL OR t.OrigenId=@BodegaId OR t.DestinoId=@BodegaId)
   AND (@TransferenciaId IS NULL OR t.TransferenciaId=@TransferenciaId) AND (@Desde IS NULL OR t.FechaHora>=@Desde) AND (@Hasta IS NULL OR t.FechaHora<@Hasta)
  ORDER BY t.TransferenciaId DESC OFFSET @Desplazamiento ROWS FETCH NEXT 21 ROWS ONLY;
  IF @Seccion=''detalle''
   SELECT l.*,u.NombreUsuario Actor,b.Nombre Bodega FROM dbo.P3_BOD_Ledger l JOIN dbo.Usuario u ON u.UsuarioId=l.ActorUsuarioId JOIN dbo.P3_BOD_Bodega b ON b.BodegaId=l.BodegaId WHERE l.TransferenciaId=@TransferenciaId ORDER BY l.MovimientoId;
  RETURN;
 END;
 IF @Seccion=''kardex''
 BEGIN
  SELECT l.*,u.NombreUsuario Actor,b.Nombre Bodega,p.Codigo FROM dbo.P3_BOD_Ledger l JOIN dbo.Usuario u ON u.UsuarioId=l.ActorUsuarioId JOIN dbo.P3_BOD_Bodega b ON b.BodegaId=l.BodegaId JOIN dbo.Producto p ON p.ProductoId=l.ProductoId
  WHERE (@ProductoId IS NULL OR l.ProductoId=@ProductoId) AND (@BodegaId IS NULL OR l.BodegaId=@BodegaId) AND (@Desde IS NULL OR l.FechaHora>=@Desde) AND (@Hasta IS NULL OR l.FechaHora<@Hasta)
  ORDER BY l.MovimientoId DESC OFFSET @Desplazamiento ROWS FETCH NEXT 21 ROWS ONLY;
  RETURN;
 END;
END;');
EXEC(N'CREATE OR ALTER PROCEDURE dbo.P3_BOD_ConsultarOperacion @ActorUsuarioId INT,@OperacionId UNIQUEIDENTIFIER
AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.P3_BOD_Autorizar @ActorUsuarioId,N''BODEGAS_CONSULTAR'';
 IF @OperacionId IS NULL THROW 58002,''Referencia invalida.'',1;
 SELECT OperacionId,Respuesta,FechaHora FROM dbo.P3_BOD_Operacion WHERE OperacionId=@OperacionId AND ActorUsuarioId=@ActorUsuarioId;
END;');
