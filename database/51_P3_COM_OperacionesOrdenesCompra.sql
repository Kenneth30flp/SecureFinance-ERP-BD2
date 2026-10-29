SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
SET XACT_ABORT ON;
IF @@TRANCOUNT=0 THROW 55000,'El instalador debe abrir una transaccion.',1;
IF OBJECT_ID('dbo.P3_COM_AuditarEstado','TR') IS NULL THROW 55000,'Requiere migracion 50 completa.',1;
GO
CREATE OR ALTER PROCEDURE dbo.P3_COM_Crear
 @ActorUsuarioId INT,@ProveedorId INT,@Detalle NVARCHAR(MAX),
 @OperacionId UNIQUEIDENTIFIER,@Observaciones NVARCHAR(MAX)=NULL
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 SET ANSI_WARNINGS ON; SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET NUMERIC_ROUNDABORT OFF;
 BEGIN TRY
 BEGIN TRANSACTION;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'COMPRAS_CREAR';
 IF @OperacionId IS NULL OR @ProveedorId IS NULL OR @ProveedorId<=0
 OR DATALENGTH(@Observaciones)>2000 OR @Detalle IS NULL OR DATALENGTH(@Detalle)>100000
 OR ISJSON(@Detalle)<>1 THROW 55002,'Datos de orden invalidos.',1;
 -- JSON permite tabuladores/saltos de linea antes del arreglo.
 IF LEFT(LTRIM(REPLACE(REPLACE(REPLACE(@Detalle,NCHAR(9),N' '),NCHAR(10),N' '),NCHAR(13),N' ')),1)<>'[' THROW 55002,'Detalle debe ser un arreglo JSON.',1;
 -- Costos como cadenas: evita conversion monetaria a Number en el cliente.
 IF (SELECT COUNT(*) FROM OPENJSON(@Detalle)) NOT BETWEEN 1 AND 100
 OR EXISTS(SELECT 1 FROM OPENJSON(@Detalle) WHERE type<>5)
 THROW 55002,'Entre 1 y 100 objetos de detalle.',1;
 IF EXISTS(SELECT 1 FROM OPENJSON(@Detalle) a WHERE
  (SELECT COUNT(*) FROM OPENJSON(a.value))<>3 OR
  (SELECT COUNT(*) FROM OPENJSON(a.value) WHERE [key] COLLATE Latin1_General_100_BIN2='ProductoId' AND type=2)<>1 OR
  (SELECT COUNT(*) FROM OPENJSON(a.value) WHERE [key] COLLATE Latin1_General_100_BIN2='Cantidad' AND type=2)<>1 OR
  (SELECT COUNT(*) FROM OPENJSON(a.value) WHERE [key] COLLATE Latin1_General_100_BIN2='CostoUnitario' AND type=1)<>1)
 THROW 55002,'Columnas o tipos de detalle invalidos.',1;
 DECLARE @Raw TABLE(Producto NVARCHAR(MAX),Cantidad NVARCHAR(MAX),Costo NVARCHAR(MAX));
 INSERT @Raw SELECT JSON_VALUE(value,'$.ProductoId'),JSON_VALUE(value,'$.Cantidad'),JSON_VALUE(value,'$.CostoUnitario') FROM OPENJSON(@Detalle);
 IF EXISTS(SELECT 1 FROM @Raw WHERE Producto IS NULL OR Cantidad IS NULL OR Costo IS NULL
 OR Producto COLLATE Latin1_General_100_BIN2 LIKE '%[^0-9]%'
 OR Cantidad COLLATE Latin1_General_100_BIN2 LIKE '%[^0-9]%'
 OR ISNULL(TRY_CONVERT(INT,Producto),0)<=0 OR ISNULL(TRY_CONVERT(INT,Cantidad),0)<=0
 OR LEN(Costo)=0 OR DATALENGTH(Costo)<>LEN(Costo)*2
 OR Costo COLLATE Latin1_General_100_BIN2 LIKE '%[^0-9.]%'
 OR LEFT(Costo,1)='.' OR RIGHT(Costo,1)='.'
 OR LEN(Costo)-LEN(REPLACE(Costo,'.',''))>1
 OR (LEN(Costo)>1 AND LEFT(Costo,1)='0' AND SUBSTRING(Costo,2,1)<>'.')
 OR (CHARINDEX('.',Costo)>0 AND LEN(Costo)-CHARINDEX('.',Costo)>4)
 OR TRY_CONVERT(DECIMAL(19,4),Costo) IS NULL)
 THROW 55002,'Cantidades enteras positivas y costos decimales de hasta cuatro decimales.',1;
 IF EXISTS(SELECT TRY_CONVERT(INT,Producto) FROM @Raw GROUP BY TRY_CONVERT(INT,Producto) HAVING COUNT(*)>1)
 THROW 55002,'No se permiten productos repetidos.',1;
 DECLARE @Lineas TABLE(ProductoId INT PRIMARY KEY,Cantidad INT,CostoUnitario DECIMAL(19,4),SKU NVARCHAR(40),Descripcion NVARCHAR(200));
 INSERT @Lineas(ProductoId,Cantidad,CostoUnitario) SELECT CONVERT(INT,Producto),CONVERT(INT,Cantidad),CONVERT(DECIMAL(19,4),Costo) FROM @Raw;
 DECLARE @Canon NVARCHAR(MAX)=(SELECT ProductoId,Cantidad,CostoUnitario FROM @Lineas ORDER BY ProductoId FOR JSON PATH),@Hash BINARY(32);
 SET @Hash=HASHBYTES('SHA2_256',(SELECT @ActorUsuarioId Actor,@ProveedorId Proveedor,@Observaciones Observaciones,JSON_QUERY(@Canon) Detalle FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER));
 DECLARE @Lock INT,@Resource NVARCHAR(255)=CONCAT(N'P3.COM.Operacion.',@OperacionId),@Id INT;
 EXEC @Lock=sys.sp_getapplock @Resource=@Resource,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
 IF @Lock<0 THROW 55003,'Operacion ocupada.',1;
 -- El applock serializa este UUID; evitar bloqueos de rango entre UUID distintos.
 SELECT @Id=OrdenCompraId FROM dbo.P3_COM_HistorialEstado WHERE OperacionId=@OperacionId;
 IF @Id IS NOT NULL
 BEGIN
  IF NOT EXISTS(SELECT 1 FROM dbo.P3_COM_HistorialEstado WHERE OperacionId=@OperacionId AND Accion='CREAR' AND SolicitudHash=@Hash)
  THROW 55003,'Referencia utilizada con otros datos.',1;
 END
 ELSE
 BEGIN
  DECLARE @Nombre NVARCHAR(150),@NIT NVARCHAR(25),@P INT=0,@Next INT,@SKU NVARCHAR(40),@Descripcion NVARCHAR(200);
  SELECT @Nombre=Nombre,@NIT=NIT FROM dbo.Proveedor WITH(HOLDLOCK) WHERE ProveedorId=@ProveedorId AND Activo=1;
  IF @Nombre IS NULL THROW 55004,'Proveedor inexistente o inactivo.',1;
  -- Lecturas compartidas retenidas, por producto ascendente. No escribe catalogos.
  WHILE 1=1
  BEGIN
   SELECT @Next=MIN(ProductoId) FROM @Lineas WHERE ProductoId>@P;
   IF @Next IS NULL BREAK;
   SET @P=@Next; SET @SKU=NULL;
   SELECT @SKU=Codigo,@Descripcion=Descripcion FROM dbo.Producto WITH(HOLDLOCK) WHERE ProductoId=@P AND Activo=1;
   IF @SKU IS NULL OR NOT EXISTS(SELECT 1 FROM dbo.ProductoProveedor WITH(HOLDLOCK) WHERE ProductoId=@P AND ProveedorId=@ProveedorId AND Activo=1)
   THROW 55004,'Producto o relacion comercial inexistente o inactiva.',1;
   UPDATE @Lineas SET SKU=@SKU,Descripcion=@Descripcion WHERE ProductoId=@P;
  END;
  DECLARE @Total DECIMAL(32,4)=(SELECT SUM(CONVERT(DECIMAL(10,0),Cantidad)*CostoUnitario) FROM @Lineas);
  INSERT dbo.P3_COM_OrdenCompra(ProveedorId,ProveedorNombre,ProveedorNIT,CreadorUsuarioId,Observaciones,Total)
  VALUES(@ProveedorId,@Nombre,@NIT,@ActorUsuarioId,@Observaciones,@Total);
  SET @Id=CONVERT(INT,SCOPE_IDENTITY());
  INSERT dbo.P3_COM_DetalleOrdenCompra(OrdenCompraId,ProductoId,SKU,Descripcion,Cantidad,CostoUnitario)
  SELECT @Id,ProductoId,SKU,Descripcion,Cantidad,CostoUnitario FROM @Lineas;
  INSERT dbo.P3_COM_HistorialEstado(OrdenCompraId,OperacionId,SolicitudHash,Accion,EstadoAnterior,EstadoNuevo,ActorUsuarioId,Motivo,VersionResultado)
  SELECT @Id,@OperacionId,@Hash,'CREAR',NULL,'BORRADOR',@ActorUsuarioId,N'Creacion de orden',Version FROM dbo.P3_COM_OrdenCompra WHERE OrdenCompraId=@Id;
 END;
 COMMIT;
 -- Resultado de la operacion original, solo despues de confirmar esta llamada.
 SELECT h.OrdenCompraId,o.Numero,h.EstadoNuevo Estado,h.VersionResultado Version,h.OperacionId,h.FechaHora,CONVERT(VARCHAR(40),o.Total) Total
 FROM dbo.P3_COM_HistorialEstado h JOIN dbo.P3_COM_OrdenCompra o ON o.OrdenCompraId=h.OrdenCompraId WHERE h.OperacionId=@OperacionId;
 END TRY BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK; THROW; END CATCH;
END;
GO
-- Interno: sin EXECUTE directo para la cuenta de aplicacion.
CREATE OR ALTER PROCEDURE dbo.P3_COM_Transicionar
 @ActorUsuarioId INT,@OrdenCompraId INT,@OperacionId UNIQUEIDENTIFIER,
 @VersionEsperada BINARY(8),@Motivo NVARCHAR(MAX),@Accion VARCHAR(10)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 SET ANSI_WARNINGS ON; SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET NUMERIC_ROUNDABORT OFF;
 BEGIN TRY
 BEGIN TRANSACTION;
 IF @Accion IS NULL OR @Accion NOT IN('ENVIAR','APROBAR','CANCELAR') THROW 55002,'Accion invalida.',1;
 DECLARE @Permiso NVARCHAR(100)=CASE @Accion WHEN 'ENVIAR' THEN N'COMPRAS_CREAR' WHEN 'APROBAR' THEN N'COMPRAS_APROBAR' ELSE N'COMPRAS_CANCELAR' END;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,@Permiso;
 IF @OrdenCompraId IS NULL OR @OrdenCompraId<=0 OR @OperacionId IS NULL OR @VersionEsperada IS NULL
 OR NULLIF(LTRIM(RTRIM(@Motivo)),N'') IS NULL OR DATALENGTH(@Motivo)>500 THROW 55002,'Datos de transicion invalidos.',1;
 DECLARE @Hash BINARY(32)=HASHBYTES('SHA2_256',(SELECT @ActorUsuarioId Actor,@OrdenCompraId Orden,@Accion Accion,@Motivo Motivo,CONVERT(VARCHAR(16),@VersionEsperada,2) Version FOR JSON PATH,WITHOUT_ARRAY_WRAPPER));
 DECLARE @Lock INT,@Resource NVARCHAR(255)=CONCAT(N'P3.COM.Operacion.',@OperacionId);
 EXEC @Lock=sys.sp_getapplock @Resource=@Resource,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
 IF @Lock<0 THROW 55003,'Operacion ocupada.',1;
 IF EXISTS(SELECT 1 FROM dbo.P3_COM_HistorialEstado WHERE OperacionId=@OperacionId)
 BEGIN
  IF NOT EXISTS(SELECT 1 FROM dbo.P3_COM_HistorialEstado WHERE OperacionId=@OperacionId AND Accion=@Accion AND SolicitudHash=@Hash)
  THROW 55003,'Referencia utilizada con otros datos.',1;
 END
 ELSE
 BEGIN
  DECLARE @Estado VARCHAR(25),@Version BINARY(8),@Creador INT,@Proveedor INT,@Nuevo VARCHAR(25);
  SELECT @Estado=Estado,@Version=Version,@Creador=CreadorUsuarioId,@Proveedor=ProveedorId FROM dbo.P3_COM_OrdenCompra WITH(UPDLOCK,HOLDLOCK) WHERE OrdenCompraId=@OrdenCompraId;
  IF @Estado IS NULL THROW 55004,'Orden inexistente.',1;
  IF @Version<>@VersionEsperada THROW 55003,'Version obsoleta; consulte la orden.',1;
  IF (@Accion='ENVIAR' AND @Estado<>'BORRADOR') OR (@Accion='APROBAR' AND @Estado<>'PENDIENTE_APROBACION')
  OR (@Accion='CANCELAR' AND @Estado NOT IN('BORRADOR','PENDIENTE_APROBACION','APROBADA')) THROW 55005,'Transicion no permitida.',1;
  IF @Accion='APROBAR' AND @Creador=@ActorUsuarioId THROW 55001,'El creador no puede aprobar su propia orden.',1;
  IF @Accion IN('ENVIAR','APROBAR')
  BEGIN
   IF NOT EXISTS(SELECT 1 FROM dbo.Proveedor WITH(HOLDLOCK) WHERE ProveedorId=@Proveedor AND Activo=1)
   THROW 55004,'Proveedor inactivo.',1;
   -- Mismo orden puntual que en creacion; el optimizador no decide el orden
   -- de adquisicion de todos los bloqueos mediante un JOIN de catalogos.
   DECLARE @Producto INT=0,@Siguiente INT;
   IF NOT EXISTS(SELECT 1 FROM dbo.P3_COM_DetalleOrdenCompra WHERE OrdenCompraId=@OrdenCompraId)
   THROW 55005,'Orden sin detalle.',1;
   WHILE 1=1
   BEGIN
    SELECT @Siguiente=MIN(ProductoId) FROM dbo.P3_COM_DetalleOrdenCompra WHERE OrdenCompraId=@OrdenCompraId AND ProductoId>@Producto;
    IF @Siguiente IS NULL BREAK;
    SET @Producto=@Siguiente;
    IF NOT EXISTS(SELECT 1 FROM dbo.Producto WITH(HOLDLOCK) WHERE ProductoId=@Producto AND Activo=1)
     OR NOT EXISTS(SELECT 1 FROM dbo.ProductoProveedor WITH(HOLDLOCK) WHERE ProductoId=@Producto AND ProveedorId=@Proveedor AND Activo=1)
    THROW 55004,'Producto o relacion comercial inactiva.',1;
   END;
  END;
  SET @Nuevo=CASE @Accion WHEN 'ENVIAR' THEN 'PENDIENTE_APROBACION' WHEN 'APROBAR' THEN 'APROBADA' ELSE 'CANCELADA' END;
  UPDATE dbo.P3_COM_OrdenCompra SET Estado=@Nuevo WHERE OrdenCompraId=@OrdenCompraId;
  INSERT dbo.P3_COM_HistorialEstado(OrdenCompraId,OperacionId,SolicitudHash,Accion,EstadoAnterior,EstadoNuevo,ActorUsuarioId,Motivo,VersionResultado)
  SELECT @OrdenCompraId,@OperacionId,@Hash,@Accion,@Estado,@Nuevo,@ActorUsuarioId,@Motivo,Version FROM dbo.P3_COM_OrdenCompra WHERE OrdenCompraId=@OrdenCompraId;
 END;
 COMMIT;
 SELECT OrdenCompraId,EstadoNuevo Estado,VersionResultado Version,OperacionId,FechaHora FROM dbo.P3_COM_HistorialEstado WHERE OperacionId=@OperacionId;
 END TRY BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK; THROW; END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.P3_COM_EnviarAprobacion
 @ActorUsuarioId INT,@OrdenCompraId INT,@OperacionId UNIQUEIDENTIFIER,@VersionEsperada BINARY(8),@Motivo NVARCHAR(MAX)
AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.P3_COM_Transicionar @ActorUsuarioId,@OrdenCompraId,@OperacionId,@VersionEsperada,@Motivo,'ENVIAR';
END;
GO
CREATE OR ALTER PROCEDURE dbo.P3_COM_Aprobar
 @ActorUsuarioId INT,@OrdenCompraId INT,@OperacionId UNIQUEIDENTIFIER,@VersionEsperada BINARY(8),@Motivo NVARCHAR(MAX)
AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.P3_COM_Transicionar @ActorUsuarioId,@OrdenCompraId,@OperacionId,@VersionEsperada,@Motivo,'APROBAR';
END;
GO
CREATE OR ALTER PROCEDURE dbo.P3_COM_Cancelar
 @ActorUsuarioId INT,@OrdenCompraId INT,@OperacionId UNIQUEIDENTIFIER,@VersionEsperada BINARY(8),@Motivo NVARCHAR(MAX)
AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.P3_COM_Transicionar @ActorUsuarioId,@OrdenCompraId,@OperacionId,@VersionEsperada,@Motivo,'CANCELAR';
END;
GO
CREATE OR ALTER PROCEDURE dbo.P3_COM_Consultar
 @ActorUsuarioId INT,@OrdenCompraId INT=NULL,@Estado VARCHAR(25)=NULL,@Desplazamiento INT=0
AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'COMPRAS_CONSULTAR';
 IF @OrdenCompraId<=0 OR @Desplazamiento IS NULL OR @Desplazamiento NOT BETWEEN 0 AND 1000000
 OR (@OrdenCompraId IS NOT NULL AND (@Estado IS NOT NULL OR @Desplazamiento<>0))
 OR (@Estado IS NOT NULL AND @Estado NOT IN('BORRADOR','PENDIENTE_APROBACION','APROBADA','PARCIALMENTE_RECIBIDA','RECIBIDA','CANCELADA')) THROW 55002,'Filtros invalidos.',1;
 SELECT OrdenCompraId,Numero,ProveedorId,ProveedorNombre,ProveedorNIT,CreadorUsuarioId,FechaCreacion,Observaciones,
 CONVERT(VARCHAR(40),Total) Total,Estado,Version FROM dbo.P3_COM_OrdenCompra
 WHERE (@OrdenCompraId IS NULL OR OrdenCompraId=@OrdenCompraId) AND (@Estado IS NULL OR Estado=@Estado)
 ORDER BY OrdenCompraId DESC OFFSET @Desplazamiento ROWS FETCH NEXT 51 ROWS ONLY;
 IF @OrdenCompraId IS NOT NULL
 SELECT ProductoId,SKU,Descripcion,Cantidad,CONVERT(VARCHAR(25),CostoUnitario) CostoUnitario,CONVERT(VARCHAR(40),Subtotal) Subtotal
 FROM dbo.P3_COM_DetalleOrdenCompra WHERE OrdenCompraId=@OrdenCompraId ORDER BY ProductoId;
END;
GO
CREATE OR ALTER PROCEDURE dbo.P3_COM_ConsultarHistorial
 @ActorUsuarioId INT,@OrdenCompraId INT
AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'COMPRAS_CONSULTAR';
 IF @OrdenCompraId IS NULL OR @OrdenCompraId<=0 THROW 55002,'Orden invalida.',1;
 SELECT HistorialId,OrdenCompraId,OperacionId,Accion,EstadoAnterior,EstadoNuevo,ActorUsuarioId,FechaHora,Motivo,VersionResultado
 FROM dbo.P3_COM_HistorialEstado WHERE OrdenCompraId=@OrdenCompraId ORDER BY HistorialId;
END;
GO
GRANT EXECUTE ON dbo.P3_COM_Crear TO securefinance_app;
GRANT EXECUTE ON dbo.P3_COM_Consultar TO securefinance_app;
GRANT EXECUTE ON dbo.P3_COM_EnviarAprobacion TO securefinance_app;
GRANT EXECUTE ON dbo.P3_COM_Aprobar TO securefinance_app;
GRANT EXECUTE ON dbo.P3_COM_Cancelar TO securefinance_app;
GRANT EXECUTE ON dbo.P3_COM_ConsultarHistorial TO securefinance_app;
DENY EXECUTE ON dbo.P3_COM_Transicionar TO securefinance_app;
GO
