SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON; SET XACT_ABORT ON;
IF @@TRANCOUNT=0 THROW 55000,'Instalador transaccional requerido.',1;
IF OBJECT_ID('dbo.P3_COM_Valoracion','U') IS NULL THROW 55000,'Requiere 50-53.',1;
GO
CREATE OR ALTER PROCEDURE dbo.P3_COM_Consultar
 @ActorUsuarioId INT,@OrdenCompraId INT=NULL,@Estado VARCHAR(25)=NULL,@Desplazamiento INT=0,@Buscar NVARCHAR(150)=N'',@RecepcionesDesplazamiento INT=0
AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'COMPRAS_CONSULTAR';
 IF @OrdenCompraId<=0 OR @Desplazamiento IS NULL OR @Desplazamiento NOT BETWEEN 0 AND 1000000 OR @Buscar IS NULL
 OR @RecepcionesDesplazamiento IS NULL OR @RecepcionesDesplazamiento NOT BETWEEN 0 AND 1000000
 OR (@Estado IS NOT NULL AND @Estado NOT IN('BORRADOR','PENDIENTE_APROBACION','APROBADA','PARCIALMENTE_RECIBIDA','RECIBIDA','CANCELADA'))
 OR (@OrdenCompraId IS NOT NULL AND (@Estado IS NOT NULL OR @Desplazamiento<>0 OR @Buscar<>N'')) THROW 55002,'Filtros invalidos.',1;
 SELECT o.OrdenCompraId,o.Numero,o.ProveedorId,o.ProveedorNombre,o.ProveedorNIT,o.CreadorUsuarioId,u.NombreUsuario Creador,o.FechaCreacion,o.Observaciones,
 CONVERT(VARCHAR(40),o.Total) Total,o.Estado,o.Version FROM dbo.P3_COM_OrdenCompra o JOIN dbo.Usuario u ON u.UsuarioId=o.CreadorUsuarioId
 WHERE (@OrdenCompraId IS NULL OR OrdenCompraId=@OrdenCompraId) AND (@Estado IS NULL OR Estado=@Estado)
 AND (@Buscar=N'' OR CHARINDEX(@Buscar,o.Numero)>0 OR CHARINDEX(@Buscar,o.ProveedorNombre)>0 OR CHARINDEX(@Buscar,o.ProveedorNIT)>0)
 ORDER BY OrdenCompraId DESC OFFSET @Desplazamiento ROWS FETCH NEXT 51 ROWS ONLY;
 IF @OrdenCompraId IS NOT NULL
 BEGIN
  SELECT d.ProductoId,d.SKU,d.Descripcion,d.Cantidad,CONVERT(VARCHAR(25),d.CostoUnitario) CostoUnitario,CONVERT(VARCHAR(40),d.Subtotal) Subtotal,
   COALESCE(r.Recibido,0) Recibido,CONVERT(BIGINT,d.Cantidad)-COALESCE(r.Recibido,0) Pendiente
  FROM dbo.P3_COM_DetalleOrdenCompra d OUTER APPLY(SELECT SUM(CONVERT(BIGINT,a.Cantidad)) Recibido FROM dbo.P3_COM_AplicacionRecepcion a WHERE a.OrdenCompraId=d.OrdenCompraId AND a.ProductoId=d.ProductoId) r
  WHERE d.OrdenCompraId=@OrdenCompraId ORDER BY d.ProductoId;
  SELECT r.OperacionId,r.FechaHora,r.DocumentoRespaldo,r.Motivo,u.NombreUsuario Actor,a.ProductoId,d.SKU,d.Descripcion,a.Cantidad,
   CONVERT(VARCHAR(25),a.CostoDocumentado) CostoDocumentado,a.RecepcionId,a.KardexId
  FROM dbo.P3_COM_RecepcionOrden r JOIN dbo.P3_COM_AplicacionRecepcion a ON a.OperacionId=r.OperacionId
   JOIN dbo.P3_COM_DetalleOrdenCompra d ON d.OrdenCompraId=a.OrdenCompraId AND d.ProductoId=a.ProductoId JOIN dbo.Usuario u ON u.UsuarioId=r.ActorUsuarioId
  WHERE r.OrdenCompraId=@OrdenCompraId ORDER BY r.FechaHora DESC,r.OperacionId,a.ProductoId OFFSET @RecepcionesDesplazamiento ROWS FETCH NEXT 51 ROWS ONLY;
 END;
END;
GO
CREATE OR ALTER PROCEDURE dbo.P3_COM_ConsultarHistorial @ActorUsuarioId INT,@OrdenCompraId INT,@Desplazamiento INT=0 AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'COMPRAS_CONSULTAR';
 IF @OrdenCompraId IS NULL OR @OrdenCompraId<=0 OR @Desplazamiento IS NULL OR @Desplazamiento NOT BETWEEN 0 AND 1000000 THROW 55002,'Filtros invalidos.',1;
 SELECT HistorialId,OrdenCompraId,OperacionId,Accion,EstadoAnterior,EstadoNuevo,ActorUsuarioId,FechaHora,Motivo,VersionResultado
 FROM dbo.P3_COM_HistorialEstado WHERE OrdenCompraId=@OrdenCompraId ORDER BY HistorialId OFFSET @Desplazamiento ROWS FETCH NEXT 51 ROWS ONLY;
END;
GO
CREATE OR ALTER PROCEDURE dbo.P3_COM_BuscarCatalogo @ActorUsuarioId INT,@Clase VARCHAR(12),@ProveedorId INT=NULL,@Buscar NVARCHAR(150)=N'',@Pagina INT=1 AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'COMPRAS_CREAR';
 IF @Clase IS NULL OR @Clase NOT IN('proveedores','productos') OR @Buscar IS NULL OR @Pagina IS NULL OR @Pagina NOT BETWEEN 1 AND 100001 THROW 55002,'Busqueda invalida.',1;
 DECLARE @Offset INT=(@Pagina-1)*10;
 IF @Clase='proveedores'
 BEGIN
  EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'PROVEEDORES_CONSULTAR';
  SELECT ProveedorId Id,Nombre,NIT Referencia FROM dbo.Proveedor WHERE Activo=1 AND (@Buscar=N'' OR CHARINDEX(@Buscar,Nombre)>0 OR CHARINDEX(@Buscar,NIT)>0)
  ORDER BY Nombre,ProveedorId OFFSET @Offset ROWS FETCH NEXT 11 ROWS ONLY;
 END
 ELSE
 BEGIN
  EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'PRODUCTOS_CONSULTAR';
  IF @ProveedorId IS NULL OR @ProveedorId<=0 THROW 55002,'Seleccione proveedor.',1;
  SELECT p.ProductoId Id,p.Descripcion Nombre,p.Codigo Referencia FROM dbo.Producto p
   JOIN dbo.ProductoProveedor pp ON pp.ProductoId=p.ProductoId JOIN dbo.Proveedor v ON v.ProveedorId=pp.ProveedorId
  WHERE pp.ProveedorId=@ProveedorId AND p.Activo=1 AND pp.Activo=1 AND v.Activo=1 AND (@Buscar=N'' OR CHARINDEX(@Buscar,p.Descripcion)>0 OR CHARINDEX(@Buscar,p.Codigo)>0)
  ORDER BY p.Descripcion,p.ProductoId OFFSET @Offset ROWS FETCH NEXT 11 ROWS ONLY;
 END;
END;
GO
GRANT EXECUTE ON dbo.P3_COM_BuscarCatalogo TO securefinance_app;
GRANT EXECUTE ON dbo.P3_COM_Consultar TO securefinance_app;
GO
