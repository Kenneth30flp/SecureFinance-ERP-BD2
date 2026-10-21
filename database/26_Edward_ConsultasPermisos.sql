-- Edward: consultas parametrizadas y permisos minimos; no asigna permisos a usuarios.
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
IF OBJECT_ID('dbo.Ticket_Garantia','U') IS NULL THROW 54600,'Requiere migracion 25.',1;
GO
CREATE OR ALTER PROCEDURE dbo.sp_Edward_ConsultarFactura @ActorUsuarioId INT,@FacturaId INT,@Garantia BIT=0 AS
BEGIN
 SET NOCOUNT ON;
 DECLARE @Permiso NVARCHAR(100)=CASE WHEN @Garantia=1 THEN N'GARANTIAS_CONSULTAR' ELSE N'DEVOLUCIONES_CONSULTAR' END;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,@Permiso;
 SELECT f.FacturaId,f.ClienteId,COALESCE(f.ClienteNombreEmision,c.Nombre) Cliente,
 f.ClienteNITEmision NIT,f.FechaHora,CONVERT(VARCHAR(21),f.Total) Total
 FROM dbo.Factura f JOIN dbo.Cliente c ON c.ClienteId=f.ClienteId WHERE f.FacturaId=@FacturaId;
 SELECT d.DetalleFacturaId,d.ProductoId,p.Descripcion,d.Cantidad,COALESCE(a.Devuelto,0) Devuelto,d.Cantidad-COALESCE(a.Devuelto,0) Disponible,
 CONVERT(VARCHAR(21),d.PrecioUnitario) PrecioUnitario,CONVERT(VARCHAR(21),d.DescuentoMonto) DescuentoMonto
 FROM dbo.DetalleFactura d JOIN dbo.Producto p ON p.ProductoId=d.ProductoId
 OUTER APPLY(SELECT SUM(Cantidad) Devuelto FROM dbo.DetalleDevolucion WHERE DetalleFacturaId=d.DetalleFacturaId) a
 WHERE d.FacturaId=@FacturaId ORDER BY d.DetalleFacturaId;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_Edward_ConsultarDevoluciones
 @ActorUsuarioId INT,@Id INT=NULL,@Desde DATETIME2(3)=NULL,@Hasta DATETIME2(3)=NULL,@Desplazamiento INT=0 AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'DEVOLUCIONES_CONSULTAR';
 IF @Desplazamiento IS NULL OR @Desplazamiento<0 OR @Desde>=@Hasta THROW 54602,'Filtros invalidos.',1;
 SELECT d.DevolucionId,d.OperacionId,d.FacturaId,f.ClienteId,COALESCE(f.ClienteNombreEmision,c.Nombre) Cliente,
 f.ClienteNITEmision NIT,d.FechaHora,d.Motivo,u.NombreUsuario Responsable,n.NotaCreditoId,n.Estado,n.EstadoCredito,
 CONVERT(VARCHAR(21),n.Subtotal) Subtotal,CONVERT(VARCHAR(21),n.Descuento) Descuento,
 CONVERT(VARCHAR(21),n.IVA) IVA,CONVERT(VARCHAR(21),n.Total) Total
 FROM dbo.DevolucionCliente d JOIN dbo.NotaCredito n ON n.DevolucionId=d.DevolucionId
 JOIN dbo.Factura f ON f.FacturaId=d.FacturaId JOIN dbo.Cliente c ON c.ClienteId=f.ClienteId JOIN dbo.Usuario u ON u.UsuarioId=d.UsuarioId
 WHERE (@Id IS NULL OR d.DevolucionId=@Id) AND (@Desde IS NULL OR d.FechaHora>=@Desde) AND (@Hasta IS NULL OR d.FechaHora<@Hasta)
 ORDER BY d.DevolucionId DESC OFFSET @Desplazamiento ROWS FETCH NEXT 51 ROWS ONLY;
 IF @Id IS NOT NULL
 SELECT d.DetalleFacturaId,p.Descripcion,d.Cantidad,d.Reingresar,k.KardexId,
 CONVERT(VARCHAR(21),f.PrecioUnitario) PrecioUnitario,CONVERT(VARCHAR(21),f.DescuentoPorcentaje) DescuentoPorcentaje,
 CONVERT(VARCHAR(21),d.Subtotal) Subtotal,CONVERT(VARCHAR(21),d.Descuento) Descuento,CONVERT(VARCHAR(21),d.IVA) IVA,CONVERT(VARCHAR(21),d.Total) Total
 FROM dbo.DetalleDevolucion d JOIN dbo.DetalleFactura f ON f.DetalleFacturaId=d.DetalleFacturaId JOIN dbo.Producto p ON p.ProductoId=f.ProductoId
 LEFT JOIN dbo.DevolucionKardex k ON k.DetalleDevolucionId=d.DetalleDevolucionId
 WHERE d.DevolucionId=@Id ORDER BY d.DetalleDevolucionId;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_Edward_ConsultarGarantias
 @ActorUsuarioId INT,@Id INT=NULL,@Buscar NVARCHAR(150)=N'',@Estado VARCHAR(15)=NULL,
 @Desde DATETIME2(3)=NULL,@Hasta DATETIME2(3)=NULL,@Desplazamiento INT=0,@SoloActivos BIT=0 AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'GARANTIAS_CONSULTAR';
 IF @Desplazamiento IS NULL OR @Desplazamiento<0 OR @Desde>=@Hasta OR @Buscar IS NULL
 OR (@Estado IS NOT NULL AND @Estado NOT IN('RECIBIDO','EN_REVISION','APROBADO','RECHAZADO','ENTREGADO')) THROW 54602,'Filtros invalidos.',1;
 SELECT t.TicketId,t.DetalleFacturaId,d.FacturaId,f.ClienteId,COALESCE(f.ClienteNombreEmision,c.Nombre) Cliente,
 d.ProductoId,p.Descripcion,t.Estado,t.Cobertura,t.Evidencia,t.Motivo,t.ResponsableId,u.NombreUsuario Responsable,t.FechaApertura,t.FechaResolucion,t.Version
 FROM dbo.Ticket_Garantia t JOIN dbo.DetalleFactura d ON d.DetalleFacturaId=t.DetalleFacturaId
 JOIN dbo.Factura f ON f.FacturaId=d.FacturaId JOIN dbo.Cliente c ON c.ClienteId=f.ClienteId
 JOIN dbo.Producto p ON p.ProductoId=d.ProductoId JOIN dbo.Usuario u ON u.UsuarioId=t.ResponsableId
 WHERE (@Id IS NULL OR t.TicketId=@Id) AND (@Estado IS NULL OR t.Estado=@Estado) AND (@SoloActivos=0 OR t.Estado<>'ENTREGADO')
 AND (@Desde IS NULL OR t.FechaApertura>=@Desde) AND (@Hasta IS NULL OR t.FechaApertura<@Hasta)
 AND (@Buscar=N'' OR CHARINDEX(@Buscar,COALESCE(f.ClienteNombreEmision,c.Nombre))>0 OR CHARINDEX(@Buscar,p.Descripcion)>0
 OR CHARINDEX(@Buscar,p.Codigo)>0 OR TRY_CONVERT(INT,@Buscar)=t.TicketId OR TRY_CONVERT(INT,@Buscar)=d.FacturaId)
 ORDER BY t.TicketId DESC OFFSET @Desplazamiento ROWS FETCH NEXT 51 ROWS ONLY;
 IF @Id IS NOT NULL
 SELECT h.HistorialId,h.EstadoAnterior,h.EstadoNuevo,h.FechaHora,h.Diagnostico,u.NombreUsuario Responsable
 FROM dbo.Historial_Garantia h JOIN dbo.Usuario u ON u.UsuarioId=h.UsuarioId WHERE h.TicketId=@Id ORDER BY h.HistorialId;
END;
GO
BEGIN TRY
 BEGIN TRANSACTION;
 INSERT dbo.Permiso(Codigo,Descripcion)
 SELECT Codigo,N'Edward posventa: '+Codigo FROM(VALUES(N'DEVOLUCIONES_CONSULTAR'),(N'DEVOLUCIONES_REGISTRAR'),(N'DEVOLUCIONES_AUTORIZAR'),(N'GARANTIAS_CONSULTAR'),(N'GARANTIAS_GESTIONAR')) p(Codigo)
 WHERE NOT EXISTS(SELECT 1 FROM dbo.Permiso WITH(UPDLOCK,HOLDLOCK) WHERE Codigo=p.Codigo);
 IF DATABASE_PRINCIPAL_ID(N'securefinance_app') IS NULL OR IS_ROLEMEMBER('db_owner','securefinance_app')=1 OR IS_ROLEMEMBER('db_datawriter','securefinance_app')=1 OR IS_ROLEMEMBER('db_datareader','securefinance_app')=1 THROW 54600,'Requiere cuenta de aplicacion dedicada con permisos minimos.',1;
 GRANT EXECUTE ON dbo.sp_ProcesarDevolucionCliente TO securefinance_app;
 GRANT EXECUTE ON dbo.sp_CrearTicketGarantia TO securefinance_app;
 GRANT EXECUTE ON dbo.sp_ActualizarEstadoGarantia TO securefinance_app;
 GRANT EXECUTE ON dbo.sp_Edward_ConsultarFactura TO securefinance_app;
 GRANT EXECUTE ON dbo.sp_Edward_ConsultarDevoluciones TO securefinance_app;
 GRANT EXECUTE ON dbo.sp_Edward_ConsultarGarantias TO securefinance_app;
 DENY SELECT,INSERT,UPDATE,DELETE ON dbo.DevolucionCliente TO securefinance_app;
 DENY SELECT,INSERT,UPDATE,DELETE ON dbo.DetalleDevolucion TO securefinance_app;
 DENY SELECT,INSERT,UPDATE,DELETE ON dbo.DevolucionKardex TO securefinance_app;
 DENY SELECT,INSERT,UPDATE,DELETE ON dbo.NotaCredito TO securefinance_app;
 DENY SELECT,INSERT,UPDATE,DELETE ON dbo.CoberturaGarantiaVenta TO securefinance_app;
 DENY SELECT,INSERT,UPDATE,DELETE ON dbo.Ticket_Garantia TO securefinance_app;
 DENY SELECT,INSERT,UPDATE,DELETE ON dbo.Historial_Garantia TO securefinance_app;
 COMMIT;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK;
 THROW;
END CATCH;
GO
