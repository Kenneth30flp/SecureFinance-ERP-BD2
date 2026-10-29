-- 62: administración de promociones con RBAC SQL, idempotencia por OperacionId,
-- control de versión ROWVERSION e historial inmutable (anterior/nuevo).
-- Repetible (CREATE OR ALTER). Requiere 60-61.
-- Bloqueo de reglas: los cambios toman sp_getapplock 'P3.PRO.Reglas' exclusivo y cada
-- venta con promociones lo toma compartido hasta su COMMIT; una venta ve la regla
-- completa anterior o posterior al cambio, nunca una mezcla.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
IF OBJECT_ID('dbo.fn_ObtenerDescuentoPromocional','FN') IS NULL THROW 57100,'Requiere migracion 61.',1;
GO
CREATE OR ALTER PROCEDURE dbo.P3_PRO_ValidarConfiguracion
 @TipoCodigo VARCHAR(20),@Porcentaje DECIMAL(5,2),@CantidadMinima INT,@TopeDescuento DECIMAL(19,2),
 @VigenteDesde DATETIME2(3),@VigenteHasta DATETIME2(3),
 @Productos dbo.P3_PRO_TipoListaIds READONLY,@Categorias dbo.P3_PRO_TipoListaIds READONLY
AS
BEGIN
 SET NOCOUNT ON;
 DECLARE @Elegibilidad VARCHAR(10)=(SELECT Elegibilidad FROM dbo.P3_PRO_TipoPromocion WHERE TipoCodigo=@TipoCodigo);
 IF @Elegibilidad IS NULL THROW 57102,'Tipo de promocion invalido.',1;
 IF @TipoCodigo='DOS_POR_UNO' AND (@Porcentaje IS NOT NULL OR ISNULL(@CantidadMinima,2)<>2)
  THROW 57102,'La promocion 2x1 no admite porcentaje y su minimo es de 2 unidades.',1;
 IF @TipoCodigo<>'DOS_POR_UNO' AND (@Porcentaje IS NULL OR @Porcentaje<0.01 OR @Porcentaje>90.00)
  THROW 57102,'El porcentaje debe estar entre 0.01 y 90.00.',1;
 IF @TipoCodigo='VOLUMEN' AND (@CantidadMinima IS NULL OR @CantidadMinima<2 OR @CantidadMinima>100000)
  THROW 57102,'El descuento por volumen requiere una cantidad minima entre 2 y 100000.',1;
 IF @TipoCodigo IN('PORCENTAJE','CATEGORIA') AND @CantidadMinima IS NOT NULL AND (@CantidadMinima<1 OR @CantidadMinima>100000)
  THROW 57102,'La cantidad minima debe estar entre 1 y 100000.',1;
 IF @TopeDescuento IS NOT NULL AND (@TopeDescuento<=0 OR @TopeDescuento>9999999.99)
  THROW 57102,'El tope de descuento por linea debe ser positivo.',1;
 IF @VigenteDesde IS NULL OR @VigenteHasta IS NULL OR @VigenteHasta<=@VigenteDesde
  OR @VigenteHasta>DATEADD(DAY,367,@VigenteDesde) OR @VigenteHasta<=SYSUTCDATETIME()
  THROW 57102,'La vigencia debe terminar en el futuro, despues de su inicio y durar como maximo un ano.',1;
 IF @Elegibilidad='PRODUCTO' AND (EXISTS(SELECT 1 FROM @Categorias) OR NOT EXISTS(SELECT 1 FROM @Productos) OR (SELECT COUNT(*) FROM @Productos)>200)
  THROW 57102,'Selecciona entre 1 y 200 productos elegibles y ninguna categoria.',1;
 IF @Elegibilidad='CATEGORIA' AND (EXISTS(SELECT 1 FROM @Productos) OR NOT EXISTS(SELECT 1 FROM @Categorias) OR (SELECT COUNT(*) FROM @Categorias)>50)
  THROW 57102,'Selecciona entre 1 y 50 categorias elegibles y ningun producto.',1;
 IF EXISTS(SELECT 1 FROM @Productos x LEFT JOIN dbo.Producto p ON p.ProductoId=x.Id AND p.Activo=1 WHERE p.ProductoId IS NULL)
  THROW 57102,'Un producto elegible no existe o esta inactivo.',1;
 IF EXISTS(SELECT 1 FROM @Categorias x LEFT JOIN dbo.P3_PRO_Categoria c ON c.CategoriaId=x.Id AND c.Activa=1 WHERE c.CategoriaId IS NULL)
  THROW 57102,'Una categoria elegible no existe o esta inactiva.',1;
END;
GO
-- Política de superposición: promociones de TIPOS distintos pueden coincidir y la venta
-- elige el mayor beneficio; dos promociones ACTIVAS del MISMO tipo, con vigencias que se
-- cruzan y algún producto/categoría común, se rechazan para evitar reglas duplicadas.
CREATE OR ALTER PROCEDURE dbo.P3_PRO_ValidarSuperposicion @PromocionId INT
AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM dbo.P3_PRO_Promocion a
  JOIN dbo.P3_PRO_Promocion b ON b.PromocionId<>a.PromocionId AND b.TipoCodigo=a.TipoCodigo AND b.Activa=1
   AND b.VigenteDesde<a.VigenteHasta AND a.VigenteDesde<b.VigenteHasta AND b.VigenteHasta>SYSUTCDATETIME()
  WHERE a.PromocionId=@PromocionId AND a.Activa=1
   AND (EXISTS(SELECT ProductoId FROM dbo.P3_PRO_PromocionProducto WHERE PromocionId=a.PromocionId
       INTERSECT SELECT ProductoId FROM dbo.P3_PRO_PromocionProducto WHERE PromocionId=b.PromocionId)
    OR EXISTS(SELECT CategoriaId FROM dbo.P3_PRO_PromocionCategoria WHERE PromocionId=a.PromocionId
       INTERSECT SELECT CategoriaId FROM dbo.P3_PRO_PromocionCategoria WHERE PromocionId=b.PromocionId)))
  THROW 57109,'Existe otra promocion activa del mismo tipo para los mismos productos o categorias en una vigencia superpuesta.',1;
END;
GO
CREATE OR ALTER PROCEDURE dbo.P3_PRO_PrepararFormulario @ActorUsuarioId INT
AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'PROMOCIONES_CONSULTAR';
 SELECT TipoCodigo,Nombre,Descripcion,Elegibilidad FROM dbo.P3_PRO_TipoPromocion ORDER BY CASE TipoCodigo WHEN 'PORCENTAJE' THEN 1 WHEN 'CATEGORIA' THEN 2 WHEN 'DOS_POR_UNO' THEN 3 ELSE 4 END;
 SELECT c.CategoriaId,c.Nombre,c.Activa,(SELECT COUNT(*) FROM dbo.P3_PRO_ProductoCategoria pc WHERE pc.CategoriaId=c.CategoriaId) Productos
 FROM dbo.P3_PRO_Categoria c ORDER BY c.Nombre;
 SELECT SYSUTCDATETIME() Ahora;
END;
GO
CREATE OR ALTER PROCEDURE dbo.P3_PRO_BuscarProductos @ActorUsuarioId INT,@Buscar NVARCHAR(150)=NULL,@CategoriaId INT=NULL
AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'PROMOCIONES_CONSULTAR';
 SET @Buscar=NULLIF(LTRIM(RTRIM(@Buscar)),N'');
 IF DATALENGTH(@Buscar)>300 THROW 57102,'Busqueda demasiado extensa.',1;
 SELECT TOP(9) p.ProductoId,p.Codigo,p.Descripcion,CONVERT(VARCHAR(21),p.Precio) Precio,pc.CategoriaId,c.Nombre Categoria
 FROM dbo.Producto p LEFT JOIN dbo.P3_PRO_ProductoCategoria pc ON pc.ProductoId=p.ProductoId
 LEFT JOIN dbo.P3_PRO_Categoria c ON c.CategoriaId=pc.CategoriaId
 WHERE p.Activo=1 AND (@CategoriaId IS NULL OR pc.CategoriaId=@CategoriaId)
  AND (@Buscar IS NULL OR p.Codigo LIKE N'%'+@Buscar+N'%' OR p.Descripcion LIKE N'%'+@Buscar+N'%')
 ORDER BY p.Codigo,p.ProductoId;
END;
GO
CREATE OR ALTER PROCEDURE dbo.P3_PRO_Consultar
 @ActorUsuarioId INT,@Id INT=NULL,@Buscar NVARCHAR(150)=NULL,@Tipo VARCHAR(20)=NULL,@Estado VARCHAR(10)=NULL,@Desplazamiento INT=0
AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'PROMOCIONES_CONSULTAR';
 SET @Buscar=NULLIF(LTRIM(RTRIM(@Buscar)),N'');
 IF @Desplazamiento<0 OR @Desplazamiento>2000000 OR DATALENGTH(@Buscar)>300
  OR (@Estado IS NOT NULL AND @Estado NOT IN('VIGENTE','PROGRAMADA','INACTIVA','VENCIDA'))
  OR (@Tipo IS NOT NULL AND NOT EXISTS(SELECT 1 FROM dbo.P3_PRO_TipoPromocion WHERE TipoCodigo=@Tipo))
  THROW 57102,'Filtros invalidos.',1;
 DECLARE @Ahora DATETIME2(3)=SYSUTCDATETIME();
 SELECT p.PromocionId,p.Codigo,p.Nombre,p.Descripcion,p.TipoCodigo,t.Nombre Tipo,t.Elegibilidad,
  CONVERT(VARCHAR(6),p.Porcentaje) Porcentaje,p.CantidadMinima,CONVERT(VARCHAR(21),p.TopeDescuento) TopeDescuento,
  p.VigenteDesde,p.VigenteHasta,p.Activa,e.Estado,CONVERT(VARCHAR(16),CONVERT(BINARY(8),p.Version),2) Version,
  uc.NombreUsuario CreadaPor,p.FechaCreacion,um.NombreUsuario ModificadaPor,p.FechaModificacion,
  (SELECT COUNT(*) FROM dbo.P3_PRO_PromocionProducto x WHERE x.PromocionId=p.PromocionId) Productos,
  (SELECT COUNT(*) FROM dbo.P3_PRO_PromocionCategoria x WHERE x.PromocionId=p.PromocionId) Categorias,
  (SELECT COUNT(*) FROM dbo.P3_PRO_AplicacionFactura x WHERE x.PromocionId=p.PromocionId) Aplicaciones,
  CONVERT(VARCHAR(21),(SELECT ISNULL(SUM(x.DescuentoMonto),0) FROM dbo.P3_PRO_AplicacionFactura x WHERE x.PromocionId=p.PromocionId)) DescuentoOtorgado
 FROM dbo.P3_PRO_Promocion p JOIN dbo.P3_PRO_TipoPromocion t ON t.TipoCodigo=p.TipoCodigo
 JOIN dbo.P3_PRO_fn_Estados(@Ahora) e ON e.PromocionId=p.PromocionId
 JOIN dbo.Usuario uc ON uc.UsuarioId=p.CreadaPor JOIN dbo.Usuario um ON um.UsuarioId=p.ModificadaPor
 WHERE (@Id IS NULL OR p.PromocionId=@Id) AND (@Tipo IS NULL OR p.TipoCodigo=@Tipo) AND (@Estado IS NULL OR e.Estado=@Estado)
  AND (@Buscar IS NULL OR p.Codigo LIKE N'%'+@Buscar+N'%' OR p.Nombre LIKE N'%'+@Buscar+N'%')
 ORDER BY CASE e.Estado WHEN 'VIGENTE' THEN 1 WHEN 'PROGRAMADA' THEN 2 WHEN 'INACTIVA' THEN 3 ELSE 4 END,p.PromocionId DESC
 OFFSET @Desplazamiento ROWS FETCH NEXT 21 ROWS ONLY;
 IF @Id IS NOT NULL
 BEGIN
  SELECT pr.ProductoId,pr.Codigo,pr.Descripcion,CONVERT(VARCHAR(21),pr.Precio) Precio,pr.Activo
  FROM dbo.P3_PRO_PromocionProducto x JOIN dbo.Producto pr ON pr.ProductoId=x.ProductoId WHERE x.PromocionId=@Id ORDER BY pr.Codigo;
  SELECT c.CategoriaId,c.Nombre,c.Activa,(SELECT COUNT(*) FROM dbo.P3_PRO_ProductoCategoria pc WHERE pc.CategoriaId=c.CategoriaId) Productos
  FROM dbo.P3_PRO_PromocionCategoria x JOIN dbo.P3_PRO_Categoria c ON c.CategoriaId=x.CategoriaId WHERE x.PromocionId=@Id ORDER BY c.Nombre;
  SELECT h.HistorialId,h.Accion,h.FechaHora,u.NombreUsuario Responsable,h.Motivo,h.CamposModificados,h.ValorAnterior,h.ValorNuevo
  FROM dbo.P3_PRO_HistorialPromocion h JOIN dbo.Usuario u ON u.UsuarioId=h.ActorUsuarioId WHERE h.PromocionId=@Id ORDER BY h.HistorialId DESC;
  SELECT TOP(20) a.FacturaId,a.FechaHora,pr.Codigo,pr.Descripcion,a.Cantidad,a.UnidadesBonificadas,
   CONVERT(VARCHAR(6),a.DescuentoPorcentaje) DescuentoPorcentaje,CONVERT(VARCHAR(21),a.DescuentoMonto) DescuentoMonto
  FROM dbo.P3_PRO_AplicacionFactura a JOIN dbo.Producto pr ON pr.ProductoId=a.ProductoId WHERE a.PromocionId=@Id ORDER BY a.AplicacionId DESC;
 END;
END;
GO
CREATE OR ALTER PROCEDURE dbo.P3_PRO_Crear
 @ActorUsuarioId INT,@OperacionId UNIQUEIDENTIFIER,@Codigo NVARCHAR(MAX),@Nombre NVARCHAR(MAX),@Descripcion NVARCHAR(MAX)=NULL,
 @TipoCodigo VARCHAR(20),@Porcentaje DECIMAL(5,2)=NULL,@CantidadMinima INT=NULL,@TopeDescuento DECIMAL(19,2)=NULL,
 @VigenteDesde DATETIME2(3),@VigenteHasta DATETIME2(3),
 @Productos dbo.P3_PRO_TipoListaIds READONLY,@Categorias dbo.P3_PRO_TipoListaIds READONLY,@Motivo NVARCHAR(MAX)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
 BEGIN TRANSACTION;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'PROMOCIONES_CREAR';
 SELECT @Codigo=UPPER(LTRIM(RTRIM(@Codigo))),@Nombre=LTRIM(RTRIM(@Nombre)),@Descripcion=NULLIF(LTRIM(RTRIM(@Descripcion)),N''),@Motivo=LTRIM(RTRIM(@Motivo));
 IF @TipoCodigo='DOS_POR_UNO' SET @CantidadMinima=ISNULL(@CantidadMinima,2);
 IF @OperacionId IS NULL OR @Codigo IS NULL OR LEN(@Codigo)=0 OR LEN(@Codigo)>30 OR @Codigo COLLATE Latin1_General_100_BIN2 LIKE N'%[^-A-Z0-9_]%'
  OR @Nombre IS NULL OR LEN(@Nombre)=0 OR LEN(@Nombre)>120 OR LEN(@Descripcion)>250 OR @Motivo IS NULL OR LEN(@Motivo)=0 OR LEN(@Motivo)>250
  THROW 57102,'Codigo (A-Z, 0-9, guion; maximo 30), nombre (maximo 120) y motivo son obligatorios.',1;
 DECLARE @Canon NVARCHAR(MAX)=(SELECT @ActorUsuarioId Actor,@Codigo Codigo,@Nombre Nombre,@Descripcion Descripcion,@TipoCodigo Tipo,
   CONVERT(VARCHAR(6),@Porcentaje) Porcentaje,@CantidadMinima CantidadMinima,CONVERT(VARCHAR(21),@TopeDescuento) Tope,
   @VigenteDesde Desde,@VigenteHasta Hasta,@Motivo Motivo,
   JSON_QUERY(COALESCE((SELECT Id FROM @Productos ORDER BY Id FOR JSON PATH),N'[]')) Productos,
   JSON_QUERY(COALESCE((SELECT Id FROM @Categorias ORDER BY Id FOR JSON PATH),N'[]')) Categorias
   FOR JSON PATH,WITHOUT_ARRAY_WRAPPER,INCLUDE_NULL_VALUES);
 DECLARE @Hash BINARY(32)=HASHBYTES('SHA2_256',CONCAT(N'P3PRO:CREAR:v1|',@Canon)),@Lock INT,@Id INT,@Previo BINARY(32),
  @Recurso NVARCHAR(255)=CONCAT(N'P3.PRO.Operacion.',@OperacionId);
 EXEC @Lock=sys.sp_getapplock @Resource=@Recurso,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
 IF @Lock<0 THROW 57105,'Operacion ocupada.',1;
 SELECT @Id=PromocionId,@Previo=SolicitudHash FROM dbo.P3_PRO_HistorialPromocion WITH(UPDLOCK,HOLDLOCK) WHERE OperacionId=@OperacionId;
 IF @Id IS NOT NULL
 BEGIN
  IF @Previo<>@Hash THROW 57105,'Referencia utilizada con otros datos.',1;
 END
 ELSE
 BEGIN
  EXEC @Lock=sys.sp_getapplock @Resource=N'P3.PRO.Reglas',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
  IF @Lock<0 THROW 57105,'Reglas promocionales ocupadas; intenta nuevamente.',1;
  EXEC dbo.P3_PRO_ValidarConfiguracion @TipoCodigo,@Porcentaje,@CantidadMinima,@TopeDescuento,@VigenteDesde,@VigenteHasta,@Productos,@Categorias;
  IF EXISTS(SELECT 1 FROM dbo.P3_PRO_Promocion WITH(UPDLOCK,HOLDLOCK) WHERE Codigo=@Codigo) THROW 57106,'Ya existe una promocion con ese codigo.',1;
  INSERT dbo.P3_PRO_Promocion(Codigo,Nombre,Descripcion,TipoCodigo,Porcentaje,CantidadMinima,TopeDescuento,VigenteDesde,VigenteHasta,Activa,CreadaPor,ModificadaPor)
  VALUES(@Codigo,@Nombre,@Descripcion,@TipoCodigo,@Porcentaje,@CantidadMinima,@TopeDescuento,@VigenteDesde,@VigenteHasta,0,@ActorUsuarioId,@ActorUsuarioId);
  SET @Id=CONVERT(INT,SCOPE_IDENTITY());
  INSERT dbo.P3_PRO_PromocionProducto(PromocionId,ProductoId) SELECT @Id,Id FROM @Productos;
  INSERT dbo.P3_PRO_PromocionCategoria(PromocionId,CategoriaId) SELECT @Id,Id FROM @Categorias;
  DECLARE @Nuevo NVARCHAR(MAX)=dbo.P3_PRO_fn_Regla(@Id);
  INSERT dbo.P3_PRO_HistorialPromocion(PromocionId,Accion,ValorAnterior,ValorNuevo,CamposModificados,ActorUsuarioId,OperacionId,SolicitudHash,Motivo)
  VALUES(@Id,'CREAR',NULL,@Nuevo,NULL,@ActorUsuarioId,@OperacionId,@Hash,@Motivo);
  INSERT dbo.Bitacora_Transacciones(TablaAfectada,Operacion,IdentificadorRegistro,ValorAnterior,ValorNuevo,ActorUsuarioId,OperacionId,Motivo)
  VALUES(N'P3_PRO_Promocion','INSERT',CONVERT(NVARCHAR(20),@Id),NULL,@Nuevo,@ActorUsuarioId,@OperacionId,@Motivo);
 END;
 COMMIT;
 SELECT p.PromocionId,p.Codigo,e.Estado,CONVERT(VARCHAR(16),CONVERT(BINARY(8),p.Version),2) Version
 FROM dbo.P3_PRO_Promocion p JOIN dbo.P3_PRO_fn_Estados(SYSUTCDATETIME()) e ON e.PromocionId=p.PromocionId WHERE p.PromocionId=@Id;
 END TRY BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK; THROW; END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.P3_PRO_Actualizar
 @ActorUsuarioId INT,@PromocionId INT,@VersionEsperada BINARY(8),@OperacionId UNIQUEIDENTIFIER,
 @Nombre NVARCHAR(MAX),@Descripcion NVARCHAR(MAX)=NULL,@TipoCodigo VARCHAR(20),@Porcentaje DECIMAL(5,2)=NULL,
 @CantidadMinima INT=NULL,@TopeDescuento DECIMAL(19,2)=NULL,@VigenteDesde DATETIME2(3),@VigenteHasta DATETIME2(3),
 @Productos dbo.P3_PRO_TipoListaIds READONLY,@Categorias dbo.P3_PRO_TipoListaIds READONLY,@Motivo NVARCHAR(MAX)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
 BEGIN TRANSACTION;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'PROMOCIONES_MODIFICAR';
 SELECT @Nombre=LTRIM(RTRIM(@Nombre)),@Descripcion=NULLIF(LTRIM(RTRIM(@Descripcion)),N''),@Motivo=LTRIM(RTRIM(@Motivo));
 IF @TipoCodigo='DOS_POR_UNO' SET @CantidadMinima=ISNULL(@CantidadMinima,2);
 IF @OperacionId IS NULL OR @PromocionId IS NULL OR @VersionEsperada IS NULL OR @Nombre IS NULL OR LEN(@Nombre)=0 OR LEN(@Nombre)>120
  OR LEN(@Descripcion)>250 OR @Motivo IS NULL OR LEN(@Motivo)=0 OR LEN(@Motivo)>250
  THROW 57102,'Nombre (maximo 120), version y motivo son obligatorios.',1;
 DECLARE @Canon NVARCHAR(MAX)=(SELECT @ActorUsuarioId Actor,@PromocionId Id,CONVERT(VARCHAR(16),@VersionEsperada,2) Version,@Nombre Nombre,@Descripcion Descripcion,
   @TipoCodigo Tipo,CONVERT(VARCHAR(6),@Porcentaje) Porcentaje,@CantidadMinima CantidadMinima,CONVERT(VARCHAR(21),@TopeDescuento) Tope,
   @VigenteDesde Desde,@VigenteHasta Hasta,@Motivo Motivo,
   JSON_QUERY(COALESCE((SELECT Id FROM @Productos ORDER BY Id FOR JSON PATH),N'[]')) Productos,
   JSON_QUERY(COALESCE((SELECT Id FROM @Categorias ORDER BY Id FOR JSON PATH),N'[]')) Categorias
   FOR JSON PATH,WITHOUT_ARRAY_WRAPPER,INCLUDE_NULL_VALUES);
 DECLARE @Hash BINARY(32)=HASHBYTES('SHA2_256',CONCAT(N'P3PRO:EDITAR:v1|',@Canon)),@Lock INT,@Previo BINARY(32),@PrevioId INT,
  @Recurso NVARCHAR(255)=CONCAT(N'P3.PRO.Operacion.',@OperacionId);
 EXEC @Lock=sys.sp_getapplock @Resource=@Recurso,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
 IF @Lock<0 THROW 57105,'Operacion ocupada.',1;
 SELECT @PrevioId=PromocionId,@Previo=SolicitudHash FROM dbo.P3_PRO_HistorialPromocion WITH(UPDLOCK,HOLDLOCK) WHERE OperacionId=@OperacionId;
 IF @PrevioId IS NOT NULL
 BEGIN
  IF @Previo<>@Hash OR @PrevioId<>@PromocionId THROW 57105,'Referencia utilizada con otros datos.',1;
 END
 ELSE
 BEGIN
  EXEC @Lock=sys.sp_getapplock @Resource=N'P3.PRO.Reglas',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
  IF @Lock<0 THROW 57105,'Reglas promocionales ocupadas; intenta nuevamente.',1;
  DECLARE @Version BINARY(8),@Estado VARCHAR(10),@Activa BIT,@ATipo VARCHAR(20),@APorcentaje DECIMAL(5,2),@AMinima INT,@ATope DECIMAL(19,2),
   @ADesde DATETIME2(3),@AHasta DATETIME2(3),@ANombre NVARCHAR(120),@ADescripcion NVARCHAR(250),@Aplicada BIT;
  SELECT @Version=p.Version,@Activa=p.Activa,@ATipo=p.TipoCodigo,@APorcentaje=p.Porcentaje,@AMinima=p.CantidadMinima,@ATope=p.TopeDescuento,
   @ADesde=p.VigenteDesde,@AHasta=p.VigenteHasta,@ANombre=p.Nombre,@ADescripcion=p.Descripcion
  FROM dbo.P3_PRO_Promocion p WITH(UPDLOCK,HOLDLOCK) WHERE p.PromocionId=@PromocionId;
  IF @Version IS NULL THROW 57110,'Promocion inexistente.',1;
  IF @Version<>@VersionEsperada THROW 57107,'La promocion cambio desde que la consultaste. Actualiza la pagina.',1;
  SELECT @Estado=Estado FROM dbo.P3_PRO_fn_Estados(SYSUTCDATETIME()) WHERE PromocionId=@PromocionId;
  IF @Estado='VENCIDA' THROW 57108,'Las promociones vencidas se conservan como historial y no se editan.',1;
  SET @Aplicada=CASE WHEN EXISTS(SELECT 1 FROM dbo.P3_PRO_AplicacionFactura WHERE PromocionId=@PromocionId) THEN 1 ELSE 0 END;
  DECLARE @ProductosIguales BIT=CASE WHEN EXISTS(SELECT Id FROM @Productos EXCEPT SELECT ProductoId FROM dbo.P3_PRO_PromocionProducto WHERE PromocionId=@PromocionId)
    OR EXISTS(SELECT ProductoId FROM dbo.P3_PRO_PromocionProducto WHERE PromocionId=@PromocionId EXCEPT SELECT Id FROM @Productos) THEN 0 ELSE 1 END,
   @CategoriasIguales BIT=CASE WHEN EXISTS(SELECT Id FROM @Categorias EXCEPT SELECT CategoriaId FROM dbo.P3_PRO_PromocionCategoria WHERE PromocionId=@PromocionId)
    OR EXISTS(SELECT CategoriaId FROM dbo.P3_PRO_PromocionCategoria WHERE PromocionId=@PromocionId EXCEPT SELECT Id FROM @Categorias) THEN 0 ELSE 1 END;
  DECLARE @Campos NVARCHAR(400)=CONCAT_WS(N',',
   CASE WHEN CONVERT(VARBINARY(400),@Nombre)<>CONVERT(VARBINARY(400),@ANombre) THEN N'Nombre' END,
   CASE WHEN ISNULL(CONVERT(VARBINARY(600),@Descripcion),0x)<>ISNULL(CONVERT(VARBINARY(600),@ADescripcion),0x) THEN N'Descripcion' END,
   CASE WHEN @TipoCodigo<>@ATipo THEN N'Tipo' END,
   CASE WHEN ISNULL(@Porcentaje,-1)<>ISNULL(@APorcentaje,-1) THEN N'Porcentaje' END,
   CASE WHEN ISNULL(@CantidadMinima,-1)<>ISNULL(@AMinima,-1) THEN N'CantidadMinima' END,
   CASE WHEN ISNULL(@TopeDescuento,-1)<>ISNULL(@ATope,-1) THEN N'TopeDescuento' END,
   CASE WHEN @VigenteDesde<>@ADesde THEN N'VigenteDesde' END,
   CASE WHEN @VigenteHasta<>@AHasta THEN N'VigenteHasta' END,
   CASE WHEN @ProductosIguales=0 THEN N'Productos' END,
   CASE WHEN @CategoriasIguales=0 THEN N'Categorias' END);
  IF @Campos=N'' THROW 57102,'No hay cambios para guardar.',1;
  -- Regla aplicada en facturas: solo nombre, descripción o cierre anticipado de vigencia.
  IF @Aplicada=1 AND (@TipoCodigo<>@ATipo OR ISNULL(@Porcentaje,-1)<>ISNULL(@APorcentaje,-1) OR ISNULL(@CantidadMinima,-1)<>ISNULL(@AMinima,-1)
   OR ISNULL(@TopeDescuento,-1)<>ISNULL(@ATope,-1) OR @VigenteDesde<>@ADesde OR @VigenteHasta>@AHasta OR @ProductosIguales=0 OR @CategoriasIguales=0)
   THROW 57108,'La promocion ya se aplico en facturas: solo puedes cambiar nombre, descripcion o adelantar su fin. Crea una nueva regla para otras condiciones.',1;
  EXEC dbo.P3_PRO_ValidarConfiguracion @TipoCodigo,@Porcentaje,@CantidadMinima,@TopeDescuento,@VigenteDesde,@VigenteHasta,@Productos,@Categorias;
  DECLARE @Anterior NVARCHAR(MAX)=dbo.P3_PRO_fn_Regla(@PromocionId);
  UPDATE dbo.P3_PRO_Promocion SET Nombre=@Nombre,Descripcion=@Descripcion,TipoCodigo=@TipoCodigo,Porcentaje=@Porcentaje,CantidadMinima=@CantidadMinima,
   TopeDescuento=@TopeDescuento,VigenteDesde=@VigenteDesde,VigenteHasta=@VigenteHasta,ModificadaPor=@ActorUsuarioId,FechaModificacion=SYSUTCDATETIME()
  WHERE PromocionId=@PromocionId AND Version=@VersionEsperada;
  IF @@ROWCOUNT<>1 THROW 57107,'La promocion cambio desde que la consultaste. Actualiza la pagina.',1;
  IF @ProductosIguales=0
  BEGIN
   DELETE dbo.P3_PRO_PromocionProducto WHERE PromocionId=@PromocionId AND ProductoId NOT IN(SELECT Id FROM @Productos);
   INSERT dbo.P3_PRO_PromocionProducto(PromocionId,ProductoId) SELECT @PromocionId,Id FROM @Productos x
   WHERE NOT EXISTS(SELECT 1 FROM dbo.P3_PRO_PromocionProducto e WHERE e.PromocionId=@PromocionId AND e.ProductoId=x.Id);
  END;
  IF @CategoriasIguales=0
  BEGIN
   DELETE dbo.P3_PRO_PromocionCategoria WHERE PromocionId=@PromocionId AND CategoriaId NOT IN(SELECT Id FROM @Categorias);
   INSERT dbo.P3_PRO_PromocionCategoria(PromocionId,CategoriaId) SELECT @PromocionId,Id FROM @Categorias x
   WHERE NOT EXISTS(SELECT 1 FROM dbo.P3_PRO_PromocionCategoria e WHERE e.PromocionId=@PromocionId AND e.CategoriaId=x.Id);
  END;
  IF @Activa=1 EXEC dbo.P3_PRO_ValidarSuperposicion @PromocionId;
  DECLARE @Nuevo NVARCHAR(MAX)=dbo.P3_PRO_fn_Regla(@PromocionId);
  INSERT dbo.P3_PRO_HistorialPromocion(PromocionId,Accion,ValorAnterior,ValorNuevo,CamposModificados,ActorUsuarioId,OperacionId,SolicitudHash,Motivo)
  VALUES(@PromocionId,'EDITAR',@Anterior,@Nuevo,@Campos,@ActorUsuarioId,@OperacionId,@Hash,@Motivo);
  INSERT dbo.Bitacora_Transacciones(TablaAfectada,Operacion,IdentificadorRegistro,ValorAnterior,ValorNuevo,ActorUsuarioId,OperacionId,Motivo)
  VALUES(N'P3_PRO_Promocion','UPDATE',CONVERT(NVARCHAR(20),@PromocionId),@Anterior,@Nuevo,@ActorUsuarioId,@OperacionId,@Motivo);
 END;
 COMMIT;
 SELECT p.PromocionId,p.Codigo,e.Estado,CONVERT(VARCHAR(16),CONVERT(BINARY(8),p.Version),2) Version
 FROM dbo.P3_PRO_Promocion p JOIN dbo.P3_PRO_fn_Estados(SYSUTCDATETIME()) e ON e.PromocionId=p.PromocionId WHERE p.PromocionId=@PromocionId;
 END TRY BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK; THROW; END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.P3_PRO_CambiarEstado
 @ActorUsuarioId INT,@PromocionId INT,@VersionEsperada BINARY(8),@Activa BIT,@OperacionId UNIQUEIDENTIFIER,@Motivo NVARCHAR(MAX)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
 BEGIN TRANSACTION;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'PROMOCIONES_ACTIVAR';
 SET @Motivo=LTRIM(RTRIM(@Motivo));
 IF @OperacionId IS NULL OR @PromocionId IS NULL OR @VersionEsperada IS NULL OR @Activa IS NULL OR @Motivo IS NULL OR LEN(@Motivo)=0 OR LEN(@Motivo)>250
  THROW 57102,'Version, estado solicitado y motivo son obligatorios.',1;
 DECLARE @Hash BINARY(32)=HASHBYTES('SHA2_256',CONCAT(N'P3PRO:ESTADO:v1|',@ActorUsuarioId,N'|',@PromocionId,N'|',CONVERT(VARCHAR(16),@VersionEsperada,2),N'|',@Activa,N'|',@Motivo)),
  @Lock INT,@Previo BINARY(32),@PrevioId INT,@Recurso NVARCHAR(255)=CONCAT(N'P3.PRO.Operacion.',@OperacionId);
 EXEC @Lock=sys.sp_getapplock @Resource=@Recurso,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
 IF @Lock<0 THROW 57105,'Operacion ocupada.',1;
 SELECT @PrevioId=PromocionId,@Previo=SolicitudHash FROM dbo.P3_PRO_HistorialPromocion WITH(UPDLOCK,HOLDLOCK) WHERE OperacionId=@OperacionId;
 IF @PrevioId IS NOT NULL
 BEGIN
  IF @Previo<>@Hash OR @PrevioId<>@PromocionId THROW 57105,'Referencia utilizada con otros datos.',1;
 END
 ELSE
 BEGIN
  EXEC @Lock=sys.sp_getapplock @Resource=N'P3.PRO.Reglas',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
  IF @Lock<0 THROW 57105,'Reglas promocionales ocupadas; intenta nuevamente.',1;
  DECLARE @Version BINARY(8),@Actual BIT,@Hasta DATETIME2(3);
  SELECT @Version=Version,@Actual=Activa,@Hasta=VigenteHasta FROM dbo.P3_PRO_Promocion WITH(UPDLOCK,HOLDLOCK) WHERE PromocionId=@PromocionId;
  IF @Version IS NULL THROW 57110,'Promocion inexistente.',1;
  IF @Version<>@VersionEsperada THROW 57107,'La promocion cambio desde que la consultaste. Actualiza la pagina.',1;
  IF @Actual=@Activa THROW 57108,'La promocion ya tiene el estado solicitado.',1;
  IF @Activa=1 AND @Hasta<=SYSUTCDATETIME() THROW 57108,'Una promocion vencida no puede activarse.',1;
  IF @Activa=1 AND NOT EXISTS(SELECT 1 FROM dbo.P3_PRO_PromocionProducto x JOIN dbo.Producto p ON p.ProductoId=x.ProductoId AND p.Activo=1 WHERE x.PromocionId=@PromocionId)
   AND NOT EXISTS(SELECT 1 FROM dbo.P3_PRO_PromocionCategoria x JOIN dbo.P3_PRO_Categoria c ON c.CategoriaId=x.CategoriaId AND c.Activa=1 WHERE x.PromocionId=@PromocionId)
   THROW 57108,'La promocion no tiene productos o categorias activas elegibles.',1;
  DECLARE @Anterior NVARCHAR(MAX)=dbo.P3_PRO_fn_Regla(@PromocionId);
  UPDATE dbo.P3_PRO_Promocion SET Activa=@Activa,ModificadaPor=@ActorUsuarioId,FechaModificacion=SYSUTCDATETIME()
  WHERE PromocionId=@PromocionId AND Version=@VersionEsperada;
  IF @@ROWCOUNT<>1 THROW 57107,'La promocion cambio desde que la consultaste. Actualiza la pagina.',1;
  IF @Activa=1 EXEC dbo.P3_PRO_ValidarSuperposicion @PromocionId;
  DECLARE @Nuevo NVARCHAR(MAX)=dbo.P3_PRO_fn_Regla(@PromocionId);
  INSERT dbo.P3_PRO_HistorialPromocion(PromocionId,Accion,ValorAnterior,ValorNuevo,CamposModificados,ActorUsuarioId,OperacionId,SolicitudHash,Motivo)
  VALUES(@PromocionId,CASE WHEN @Activa=1 THEN 'ACTIVAR' ELSE 'DESACTIVAR' END,@Anterior,@Nuevo,N'Activa',@ActorUsuarioId,@OperacionId,@Hash,@Motivo);
  INSERT dbo.Bitacora_Transacciones(TablaAfectada,Operacion,IdentificadorRegistro,ValorAnterior,ValorNuevo,ActorUsuarioId,OperacionId,Motivo)
  VALUES(N'P3_PRO_Promocion','UPDATE',CONVERT(NVARCHAR(20),@PromocionId),@Anterior,@Nuevo,@ActorUsuarioId,@OperacionId,@Motivo);
 END;
 COMMIT;
 SELECT p.PromocionId,p.Codigo,e.Estado,CONVERT(VARCHAR(16),CONVERT(BINARY(8),p.Version),2) Version
 FROM dbo.P3_PRO_Promocion p JOIN dbo.P3_PRO_fn_Estados(SYSUTCDATETIME()) e ON e.PromocionId=p.PromocionId WHERE p.PromocionId=@PromocionId;
 END TRY BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK; THROW; END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.P3_PRO_CrearCategoria
 @ActorUsuarioId INT,@Nombre NVARCHAR(MAX),@OperacionId UNIQUEIDENTIFIER,@Motivo NVARCHAR(MAX)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
 BEGIN TRANSACTION;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'PROMOCIONES_MODIFICAR';
 SELECT @Nombre=LTRIM(RTRIM(@Nombre)),@Motivo=LTRIM(RTRIM(@Motivo));
 IF @OperacionId IS NULL OR @Nombre IS NULL OR LEN(@Nombre)=0 OR LEN(@Nombre)>80 OR @Motivo IS NULL OR LEN(@Motivo)=0 OR LEN(@Motivo)>250
  THROW 57102,'Nombre de categoria (maximo 80) y motivo son obligatorios.',1;
 DECLARE @Hash BINARY(32)=HASHBYTES('SHA2_256',CONCAT(N'P3PRO:CATEGORIA:v1|',@ActorUsuarioId,N'|',@Nombre,N'|',@Motivo)),@Lock INT,@Id INT,@Previo BINARY(32),
  @Recurso NVARCHAR(255)=CONCAT(N'P3.PRO.Operacion.',@OperacionId);
 EXEC @Lock=sys.sp_getapplock @Resource=@Recurso,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
 IF @Lock<0 THROW 57105,'Operacion ocupada.',1;
 SELECT @Id=CategoriaId,@Previo=SolicitudHash FROM dbo.P3_PRO_HistorialCategoria WITH(UPDLOCK,HOLDLOCK) WHERE OperacionId=@OperacionId;
 IF @Previo IS NOT NULL
 BEGIN
  IF @Previo<>@Hash THROW 57105,'Referencia utilizada con otros datos.',1;
 END
 ELSE
 BEGIN
  IF EXISTS(SELECT 1 FROM dbo.P3_PRO_Categoria WITH(UPDLOCK,HOLDLOCK) WHERE Nombre=@Nombre) THROW 57106,'Ya existe una categoria con ese nombre.',1;
  INSERT dbo.P3_PRO_Categoria(Nombre,CreadaPor) VALUES(@Nombre,@ActorUsuarioId);
  SET @Id=CONVERT(INT,SCOPE_IDENTITY());
  INSERT dbo.P3_PRO_HistorialCategoria(Accion,CategoriaId,ActorUsuarioId,OperacionId,SolicitudHash,Motivo)
  VALUES('CREAR_CATEGORIA',@Id,@ActorUsuarioId,@OperacionId,@Hash,@Motivo);
  INSERT dbo.Bitacora_Transacciones(TablaAfectada,Operacion,IdentificadorRegistro,ValorAnterior,ValorNuevo,ActorUsuarioId,OperacionId,Motivo)
  VALUES(N'P3_PRO_Categoria','INSERT',CONVERT(NVARCHAR(20),@Id),NULL,(SELECT @Id CategoriaId,@Nombre Nombre FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),@ActorUsuarioId,@OperacionId,@Motivo);
 END;
 COMMIT;
 SELECT CategoriaId,Nombre FROM dbo.P3_PRO_Categoria WHERE CategoriaId=@Id;
 END TRY BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK; THROW; END CATCH;
END;
GO
-- @CategoriaId NULL retira la categoría. Las facturas anteriores conservan su regla aplicada.
CREATE OR ALTER PROCEDURE dbo.P3_PRO_AsignarCategoria
 @ActorUsuarioId INT,@ProductoId INT,@CategoriaId INT=NULL,@OperacionId UNIQUEIDENTIFIER,@Motivo NVARCHAR(MAX)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
 BEGIN TRANSACTION;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'PROMOCIONES_MODIFICAR';
 SET @Motivo=LTRIM(RTRIM(@Motivo));
 IF @OperacionId IS NULL OR @ProductoId IS NULL OR @Motivo IS NULL OR LEN(@Motivo)=0 OR LEN(@Motivo)>250
  THROW 57102,'Producto y motivo son obligatorios.',1;
 DECLARE @Hash BINARY(32)=HASHBYTES('SHA2_256',CONCAT(N'P3PRO:ASIGNAR:v1|',@ActorUsuarioId,N'|',@ProductoId,N'|',@CategoriaId,N'|',@Motivo)),@Lock INT,@Previo BINARY(32),
  @Recurso NVARCHAR(255)=CONCAT(N'P3.PRO.Operacion.',@OperacionId);
 EXEC @Lock=sys.sp_getapplock @Resource=@Recurso,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
 IF @Lock<0 THROW 57105,'Operacion ocupada.',1;
 SELECT @Previo=SolicitudHash FROM dbo.P3_PRO_HistorialCategoria WITH(UPDLOCK,HOLDLOCK) WHERE OperacionId=@OperacionId;
 IF @Previo IS NOT NULL
 BEGIN
  IF @Previo<>@Hash THROW 57105,'Referencia utilizada con otros datos.',1;
 END
 ELSE
 BEGIN
  EXEC @Lock=sys.sp_getapplock @Resource=N'P3.PRO.Reglas',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
  IF @Lock<0 THROW 57105,'Reglas promocionales ocupadas; intenta nuevamente.',1;
  IF NOT EXISTS(SELECT 1 FROM dbo.Producto WHERE ProductoId=@ProductoId) THROW 57110,'Producto inexistente.',1;
  IF @CategoriaId IS NOT NULL AND NOT EXISTS(SELECT 1 FROM dbo.P3_PRO_Categoria WHERE CategoriaId=@CategoriaId AND Activa=1) THROW 57110,'Categoria inexistente o inactiva.',1;
  DECLARE @Anterior INT=(SELECT CategoriaId FROM dbo.P3_PRO_ProductoCategoria WITH(UPDLOCK,HOLDLOCK) WHERE ProductoId=@ProductoId);
  IF (@Anterior IS NULL AND @CategoriaId IS NULL) OR @Anterior=@CategoriaId THROW 57108,'El producto ya tiene esa categoria.',1;
  IF @CategoriaId IS NULL DELETE dbo.P3_PRO_ProductoCategoria WHERE ProductoId=@ProductoId;
  ELSE IF @Anterior IS NULL INSERT dbo.P3_PRO_ProductoCategoria(ProductoId,CategoriaId,AsignadaPor) VALUES(@ProductoId,@CategoriaId,@ActorUsuarioId);
  ELSE UPDATE dbo.P3_PRO_ProductoCategoria SET CategoriaId=@CategoriaId,AsignadaPor=@ActorUsuarioId,FechaAsignacion=SYSUTCDATETIME() WHERE ProductoId=@ProductoId;
  INSERT dbo.P3_PRO_HistorialCategoria(Accion,CategoriaId,ProductoId,CategoriaAnteriorId,ActorUsuarioId,OperacionId,SolicitudHash,Motivo)
  VALUES(CASE WHEN @CategoriaId IS NULL THEN 'RETIRAR' ELSE 'ASIGNAR' END,@CategoriaId,@ProductoId,@Anterior,@ActorUsuarioId,@OperacionId,@Hash,@Motivo);
  INSERT dbo.Bitacora_Transacciones(TablaAfectada,Operacion,IdentificadorRegistro,ValorAnterior,ValorNuevo,ActorUsuarioId,OperacionId,Motivo)
  VALUES(N'P3_PRO_ProductoCategoria',CASE WHEN @CategoriaId IS NULL THEN 'DELETE' WHEN @Anterior IS NULL THEN 'INSERT' ELSE 'UPDATE' END,CONVERT(NVARCHAR(20),@ProductoId),
   CASE WHEN @Anterior IS NOT NULL THEN CONCAT(N'{"CategoriaId":',@Anterior,N'}') END,
   CASE WHEN @CategoriaId IS NOT NULL THEN CONCAT(N'{"CategoriaId":',@CategoriaId,N'}') END,@ActorUsuarioId,@OperacionId,@Motivo);
 END;
 COMMIT;
 SELECT @ProductoId ProductoId,(SELECT CategoriaId FROM dbo.P3_PRO_ProductoCategoria WHERE ProductoId=@ProductoId) CategoriaId;
 END TRY BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK; THROW; END CATCH;
END;
GO
GRANT EXECUTE ON dbo.P3_PRO_PrepararFormulario TO securefinance_app;
GRANT EXECUTE ON dbo.P3_PRO_BuscarProductos TO securefinance_app;
GRANT EXECUTE ON dbo.P3_PRO_Consultar TO securefinance_app;
GRANT EXECUTE ON dbo.P3_PRO_Crear TO securefinance_app;
GRANT EXECUTE ON dbo.P3_PRO_Actualizar TO securefinance_app;
GRANT EXECUTE ON dbo.P3_PRO_CambiarEstado TO securefinance_app;
GRANT EXECUTE ON dbo.P3_PRO_CrearCategoria TO securefinance_app;
GRANT EXECUTE ON dbo.P3_PRO_AsignarCategoria TO securefinance_app;
DENY EXECUTE ON dbo.P3_PRO_ValidarConfiguracion TO securefinance_app;
DENY EXECUTE ON dbo.P3_PRO_ValidarSuperposicion TO securefinance_app;
GO
