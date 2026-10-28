-- Solo consultas de catalogo. No altera motor UC09, existencias ni documentos.
SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON; SET XACT_ABORT ON;
IF OBJECT_ID('dbo.sp_ConvertirCotizacionAFactura','P') IS NULL
 THROW 54900,'Requiere Cotizaciones 41-43.',1;
GO
CREATE OR ALTER PROCEDURE dbo.P3_COT_PrepararFormulario @ActorUsuarioId INT AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'COTIZACIONES_CREAR';
 SELECT MaxDescuento,SYSUTCDATETIME() Ahora FROM dbo.fn_ObtenerPoliticaVenta(@ActorUsuarioId);
END;
GO
CREATE OR ALTER PROCEDURE dbo.P3_COT_BuscarCatalogo
 @ActorUsuarioId INT,@Clase VARCHAR(10),@Buscar NVARCHAR(150)=N'',@Pagina INT=1,@Limite INT=8
AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'COTIZACIONES_CREAR';
 IF @Clase IS NULL OR @Clase NOT IN('clientes','productos') OR @Pagina IS NULL OR @Pagina NOT BETWEEN 1 AND 100001
 OR @Limite IS NULL OR @Limite NOT BETWEEN 1 AND 20 OR @Buscar IS NULL
 THROW 54902,'Parametros de busqueda invalidos.',1;
 DECLARE @Offset INT=(@Pagina-1)*@Limite,@Fetch INT=@Limite+1;
 SET @Buscar=LTRIM(RTRIM(@Buscar));
 IF @Clase='clientes'
 SELECT ClienteId Id,Nombre,NIT Referencia FROM dbo.Cliente
 WHERE Activo=1 AND (@Buscar=N'' OR CHARINDEX(@Buscar,Nombre)>0 OR CHARINDEX(@Buscar,NIT)>0)
 ORDER BY Nombre,ClienteId OFFSET @Offset ROWS FETCH NEXT @Fetch ROWS ONLY;
 ELSE
 SELECT ProductoId Id,Descripcion Nombre,Codigo Referencia,CONVERT(VARCHAR(21),Precio) Precio,Stock
 FROM dbo.Producto WHERE Activo=1 AND (@Buscar=N'' OR CHARINDEX(@Buscar,Descripcion)>0 OR CHARINDEX(@Buscar,Codigo)>0)
 ORDER BY CASE WHEN Stock>0 THEN 0 ELSE 1 END,Descripcion,ProductoId
 OFFSET @Offset ROWS FETCH NEXT @Fetch ROWS ONLY;
END;
GO
GRANT EXECUTE ON dbo.P3_COT_PrepararFormulario TO securefinance_app;
GRANT EXECUTE ON dbo.P3_COT_BuscarCatalogo TO securefinance_app;
GO
