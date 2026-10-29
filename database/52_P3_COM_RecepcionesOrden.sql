SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON; SET XACT_ABORT ON;
IF @@TRANCOUNT=0 THROW 55000,'Instalador transaccional requerido.',1;
IF OBJECT_ID('dbo.P3_COM_Transicionar','P') IS NULL OR OBJECT_ID('dbo.sp_RegistrarRecepcionCompra','P') IS NULL THROW 55000,'Requiere 34,36,50,51.',1;
IF OBJECT_ID('dbo.P3_COM_RecepcionOrden','U') IS NULL
BEGIN
 CREATE TABLE dbo.P3_COM_RecepcionOrden(
  OperacionId UNIQUEIDENTIFIER PRIMARY KEY,
  OrdenCompraId INT NOT NULL REFERENCES dbo.P3_COM_OrdenCompra(OrdenCompraId),
  ActorUsuarioId INT NOT NULL REFERENCES dbo.Usuario(UsuarioId),
  FechaHora DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
  DocumentoRespaldo NVARCHAR(100) NOT NULL CHECK(LEN(LTRIM(RTRIM(DocumentoRespaldo)))>0),
  Motivo NVARCHAR(250) NOT NULL CHECK(LEN(LTRIM(RTRIM(Motivo)))>0),
  UNIQUE(OperacionId,OrdenCompraId)
 );
 CREATE TABLE dbo.P3_COM_AplicacionRecepcion(
  OperacionId UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.P3_COM_RecepcionOrden(OperacionId),
  OrdenCompraId INT NOT NULL,
  ProductoId INT NOT NULL,
  Cantidad INT NOT NULL CHECK(Cantidad>0),
  CostoDocumentado DECIMAL(19,4) NOT NULL CHECK(CostoDocumentado>=0),
  RecepcionId BIGINT NOT NULL,
  KardexId BIGINT NOT NULL UNIQUE REFERENCES dbo.Kardex_Inventario(KardexId),
  OperacionHija UNIQUEIDENTIFIER NOT NULL UNIQUE,
  PRIMARY KEY(OperacionId,ProductoId),
  UNIQUE(RecepcionId,ProductoId),
  FOREIGN KEY(OperacionId,OrdenCompraId) REFERENCES dbo.P3_COM_RecepcionOrden(OperacionId,OrdenCompraId),
  FOREIGN KEY(OrdenCompraId,ProductoId) REFERENCES dbo.P3_COM_DetalleOrdenCompra(OrdenCompraId,ProductoId),
  FOREIGN KEY(RecepcionId,ProductoId) REFERENCES dbo.DetalleRecepcionCompra(RecepcionId,ProductoId)
 );
 CREATE INDEX IX_P3_COM_Recibido ON dbo.P3_COM_AplicacionRecepcion(OrdenCompraId,ProductoId) INCLUDE(Cantidad);
END;
IF OBJECT_ID('dbo.P3_COM_AplicacionRecepcion','U') IS NULL
 OR (SELECT COUNT(*) FROM sys.key_constraints WHERE parent_object_id IN(OBJECT_ID('dbo.P3_COM_AplicacionRecepcion'),OBJECT_ID('dbo.P3_COM_RecepcionOrden')) AND type='PK')<>2
 OR (SELECT COUNT(*) FROM sys.foreign_keys WHERE parent_object_id IN(OBJECT_ID('dbo.P3_COM_AplicacionRecepcion'),OBJECT_ID('dbo.P3_COM_RecepcionOrden')))<>7
 OR NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.P3_COM_AplicacionRecepcion') AND name='CostoDocumentado' AND TYPE_NAME(system_type_id)='decimal' AND precision=19 AND scale=4 AND is_nullable=0)
 OR EXISTS(SELECT 1 FROM sys.foreign_keys WHERE parent_object_id IN(OBJECT_ID('dbo.P3_COM_AplicacionRecepcion'),OBJECT_ID('dbo.P3_COM_RecepcionOrden')) AND (is_disabled=1 OR is_not_trusted=1))
 THROW 55000,'Esquema de recepciones de orden incompatible.',1;
ALTER TABLE dbo.P3_COM_HistorialEstado DROP CONSTRAINT CK_P3_COM_Transicion;
ALTER TABLE dbo.P3_COM_HistorialEstado WITH CHECK ADD CONSTRAINT CK_P3_COM_Transicion CHECK(
 (Accion='CREAR' AND EstadoAnterior IS NULL AND EstadoNuevo='BORRADOR') OR
 (EstadoAnterior IS NOT NULL AND (
 (Accion='ENVIAR' AND EstadoAnterior='BORRADOR' AND EstadoNuevo='PENDIENTE_APROBACION') OR
 (Accion='APROBAR' AND EstadoAnterior='PENDIENTE_APROBACION' AND EstadoNuevo='APROBADA') OR
 (Accion='CANCELAR' AND EstadoAnterior IN('BORRADOR','PENDIENTE_APROBACION','APROBADA') AND EstadoNuevo='CANCELADA') OR
 (Accion='RECIBIR' AND EstadoAnterior IN('APROBADA','PARCIALMENTE_RECIBIDA') AND EstadoNuevo IN('PARCIALMENTE_RECIBIDA','RECIBIDA')))));
INSERT dbo.Permiso(Codigo,Descripcion) SELECT 'COMPRAS_RECIBIR',N'Recibir ordenes aprobadas' WHERE NOT EXISTS(SELECT 1 FROM dbo.Permiso WHERE Codigo='COMPRAS_RECIBIR');
DENY SELECT,INSERT,UPDATE,DELETE ON dbo.P3_COM_RecepcionOrden TO securefinance_app;
DENY SELECT,INSERT,UPDATE,DELETE ON dbo.P3_COM_AplicacionRecepcion TO securefinance_app;
GO
CREATE OR ALTER TRIGGER dbo.P3_COM_OrdenProtegida ON dbo.P3_COM_OrdenCompra AFTER UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM deleted d LEFT JOIN inserted i ON i.OrdenCompraId=d.OrdenCompraId WHERE i.OrdenCompraId IS NULL) THROW 55005,'No se eliminan ordenes.',1;
 IF UPDATE(ProveedorId) OR UPDATE(ProveedorNombre) OR UPDATE(ProveedorNIT) OR UPDATE(CreadorUsuarioId) OR UPDATE(FechaCreacion) OR UPDATE(Observaciones) OR UPDATE(Total) THROW 55005,'Contenido comercial inmutable.',1;
 IF EXISTS(SELECT 1 FROM inserted i JOIN deleted d ON d.OrdenCompraId=i.OrdenCompraId WHERE NOT(
 (d.Estado='BORRADOR' AND i.Estado='PENDIENTE_APROBACION') OR
 (d.Estado='PENDIENTE_APROBACION' AND i.Estado='APROBADA') OR
 (d.Estado IN('BORRADOR','PENDIENTE_APROBACION','APROBADA') AND i.Estado='CANCELADA') OR
 (d.Estado IN('APROBADA','PARCIALMENTE_RECIBIDA') AND i.Estado IN('PARCIALMENTE_RECIBIDA','RECIBIDA')))) THROW 55005,'Transicion invalida.',1;
END;
GO
CREATE OR ALTER TRIGGER dbo.P3_COM_RecepcionInmutable ON dbo.P3_COM_RecepcionOrden AFTER UPDATE,DELETE AS
BEGIN IF EXISTS(SELECT 1 FROM deleted) THROW 55005,'Recepcion inmutable.',1; END;
GO
CREATE OR ALTER TRIGGER dbo.P3_COM_AplicacionInmutable ON dbo.P3_COM_AplicacionRecepcion AFTER UPDATE,DELETE AS
BEGIN IF EXISTS(SELECT 1 FROM deleted) THROW 55005,'Aplicacion inmutable.',1; END;
GO
CREATE OR ALTER PROCEDURE dbo.P3_COM_Recibir
 @ActorUsuarioId INT,@OrdenCompraId INT,@OperacionId UNIQUEIDENTIFIER,@VersionEsperada BINARY(8),
 @DocumentoRespaldo NVARCHAR(MAX),@Motivo NVARCHAR(MAX),@Detalle NVARCHAR(MAX)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON; SET ARITHABORT ON; SET ANSI_WARNINGS ON; SET CONCAT_NULL_YIELDS_NULL ON; SET NUMERIC_ROUNDABORT OFF;
 BEGIN TRY
 BEGIN TRANSACTION;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'COMPRAS_RECIBIR';
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'INVENTARIO_REGISTRAR';
 IF @OperacionId IS NULL OR @OrdenCompraId IS NULL OR @OrdenCompraId<=0 OR @VersionEsperada IS NULL
 OR NULLIF(LTRIM(RTRIM(@DocumentoRespaldo)),N'') IS NULL OR DATALENGTH(@DocumentoRespaldo)>200
 OR NULLIF(LTRIM(RTRIM(@Motivo)),N'') IS NULL OR DATALENGTH(@Motivo)>500
 OR @Detalle IS NULL OR DATALENGTH(@Detalle)>100000 OR ISJSON(@Detalle)<>1 THROW 55002,'Recepcion invalida.',1;
 IF LEFT(LTRIM(REPLACE(REPLACE(REPLACE(@Detalle,NCHAR(9),' '),NCHAR(10),' '),NCHAR(13),' ')),1)<>'['
 OR (SELECT COUNT(*) FROM OPENJSON(@Detalle)) NOT BETWEEN 1 AND 100
 OR EXISTS(SELECT 1 FROM OPENJSON(@Detalle) WHERE type<>5) THROW 55002,'Detalle invalido.',1;
 IF EXISTS(SELECT 1 FROM OPENJSON(@Detalle) a WHERE
 (SELECT COUNT(*) FROM OPENJSON(a.value))<>3 OR
 (SELECT COUNT(*) FROM OPENJSON(a.value) WHERE [key] COLLATE Latin1_General_100_BIN2='ProductoId' AND type=2)<>1 OR
 (SELECT COUNT(*) FROM OPENJSON(a.value) WHERE [key] COLLATE Latin1_General_100_BIN2='Cantidad' AND type=2)<>1 OR
 (SELECT COUNT(*) FROM OPENJSON(a.value) WHERE [key] COLLATE Latin1_General_100_BIN2='CostoUnitario' AND type=1)<>1) THROW 55002,'Columnas invalidas.',1;
 DECLARE @Raw TABLE(P NVARCHAR(MAX),Q NVARCHAR(MAX),C NVARCHAR(MAX));
 INSERT @Raw SELECT JSON_VALUE(value,'$.ProductoId'),JSON_VALUE(value,'$.Cantidad'),JSON_VALUE(value,'$.CostoUnitario') FROM OPENJSON(@Detalle);
 IF EXISTS(SELECT 1 FROM @Raw WHERE P IS NULL OR Q IS NULL OR C IS NULL
 OR P COLLATE Latin1_General_100_BIN2 LIKE '%[^0-9]%' OR Q COLLATE Latin1_General_100_BIN2 LIKE '%[^0-9]%'
 OR ISNULL(TRY_CONVERT(INT,P),0)<=0 OR ISNULL(TRY_CONVERT(INT,Q),0)<=0
 OR LEN(C)=0 OR DATALENGTH(C)<>LEN(C)*2 OR C COLLATE Latin1_General_100_BIN2 LIKE '%[^0-9.]%'
 OR LEFT(C,1)='.' OR RIGHT(C,1)='.' OR LEN(C)-LEN(REPLACE(C,'.',''))>1
 OR (CHARINDEX('.',C)>0 AND LEN(C)-CHARINDEX('.',C)>4) OR TRY_CONVERT(DECIMAL(19,4),C) IS NULL)
 THROW 55002,'Cantidades o costos invalidos.',1;
 IF EXISTS(SELECT TRY_CONVERT(INT,P) FROM @Raw GROUP BY TRY_CONVERT(INT,P) HAVING COUNT(*)>1) THROW 55002,'Producto repetido.',1;
 DECLARE @L TABLE(ProductoId INT PRIMARY KEY,Cantidad INT,Costo DECIMAL(19,4));
 INSERT @L SELECT CONVERT(INT,P),CONVERT(INT,Q),CONVERT(DECIMAL(19,4),C) FROM @Raw;
 DECLARE @Canon NVARCHAR(MAX)=(SELECT ProductoId,Cantidad,Costo FROM @L ORDER BY ProductoId FOR JSON PATH),@Hash BINARY(32);
 SET @Hash=HASHBYTES('SHA2_256',(SELECT @ActorUsuarioId Actor,@OrdenCompraId Orden,@DocumentoRespaldo Documento,@Motivo Motivo,CONVERT(VARCHAR(16),@VersionEsperada,2) Version,JSON_QUERY(@Canon) Detalle FOR JSON PATH,WITHOUT_ARRAY_WRAPPER));
 DECLARE @Lock INT,@Resource NVARCHAR(255)=CONCAT(N'P3.COM.Operacion.',@OperacionId);
 EXEC @Lock=sys.sp_getapplock @Resource=@Resource,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
 IF @Lock<0 THROW 55003,'Operacion ocupada.',1;
 IF EXISTS(SELECT 1 FROM dbo.P3_COM_HistorialEstado WHERE OperacionId=@OperacionId)
 BEGIN
  IF NOT EXISTS(SELECT 1 FROM dbo.P3_COM_HistorialEstado WHERE OperacionId=@OperacionId AND Accion='RECIBIR' AND SolicitudHash=@Hash) THROW 55003,'Referencia utilizada con otros datos.',1;
 END
 ELSE
 BEGIN
  DECLARE @Estado VARCHAR(25),@Version BINARY(8),@Proveedor INT;
  SELECT @Estado=Estado,@Version=Version,@Proveedor=ProveedorId FROM dbo.P3_COM_OrdenCompra WITH(UPDLOCK,HOLDLOCK) WHERE OrdenCompraId=@OrdenCompraId;
  IF @Estado IS NULL THROW 55004,'Orden inexistente.',1;
  IF @Version<>@VersionEsperada THROW 55003,'Version obsoleta.',1;
  IF @Estado NOT IN('APROBADA','PARCIALMENTE_RECIBIDA') THROW 55005,'Orden no admite recepciones.',1;
  -- Mantener el orden de bloqueos del receptor compartido: proveedor, producto,
  -- relacion. UPDLOCK evita conversiones simultaneas de locks compartidos.
  IF NOT EXISTS(SELECT 1 FROM dbo.Proveedor WITH(UPDLOCK,HOLDLOCK) WHERE ProveedorId=@Proveedor AND Activo=1) THROW 55004,'Proveedor inactivo.',1;
  IF EXISTS(SELECT 1 FROM @L l LEFT JOIN dbo.P3_COM_DetalleOrdenCompra d ON d.OrdenCompraId=@OrdenCompraId AND d.ProductoId=l.ProductoId
   OUTER APPLY(SELECT SUM(CONVERT(BIGINT,a.Cantidad)) Recibido FROM dbo.P3_COM_AplicacionRecepcion a WHERE a.OrdenCompraId=@OrdenCompraId AND a.ProductoId=l.ProductoId) r
   WHERE d.ProductoId IS NULL OR CONVERT(BIGINT,l.Cantidad)>CONVERT(BIGINT,d.Cantidad)-COALESCE(r.Recibido,0)) THROW 55006,'Producto ajeno o cantidad superior al pendiente.',1;
  INSERT dbo.P3_COM_RecepcionOrden(OperacionId,OrdenCompraId,ActorUsuarioId,DocumentoRespaldo,Motivo) VALUES(@OperacionId,@OrdenCompraId,@ActorUsuarioId,@DocumentoRespaldo,@Motivo);
  DECLARE @P INT=0,@Next INT,@Q INT,@Cost DECIMAL(19,4),@CostLegacy DECIMAL(19,2),@Child UNIQUEIDENTIFIER,@R BIGINT,@K BIGINT;
  WHILE 1=1
  BEGIN
   SELECT @Next=MIN(ProductoId) FROM @L WHERE ProductoId>@P;
   IF @Next IS NULL BREAK;
   SET @P=@Next;
   IF NOT EXISTS(SELECT 1 FROM dbo.Producto WITH(UPDLOCK,HOLDLOCK) WHERE ProductoId=@P AND Activo=1) THROW 55004,'Producto inactivo.',1;
   IF NOT EXISTS(SELECT 1 FROM dbo.ProductoProveedor WITH(UPDLOCK,HOLDLOCK) WHERE ProductoId=@P AND ProveedorId=@Proveedor AND Activo=1) THROW 55004,'Relacion comercial inactiva.',1;
   SELECT @Q=Cantidad,@Cost=Costo FROM @L WHERE ProductoId=@P;
   SET @Child=NEWID();
   -- Nunca redondear silenciosamente el contrato heredado de dos decimales.
   -- El tercer argumento trunca solo para comparar representabilidad:
   -- ROUND normal puede desbordar 999999999999999.9999 antes del CASE.
   SET @CostLegacy=CASE WHEN @Cost=ROUND(@Cost,2,1) THEN CONVERT(DECIMAL(19,2),@Cost) ELSE NULL END;
   -- Este SP produce su propio recordset. El consumidor toma la confirmacion final.
   EXEC dbo.sp_RegistrarRecepcionCompra @ActorUsuarioId=@ActorUsuarioId,@ProductoId=@P,@ProveedorId=@Proveedor,@Cantidad=@Q,
    @DocumentoRespaldo=@DocumentoRespaldo,@Motivo=@Motivo,@OperacionId=@Child,@CostoUnitario=@CostLegacy;
   SET @R=NULL; SET @K=NULL;
   SELECT @R=r.RecepcionId,@K=d.KardexId FROM dbo.RecepcionCompra r JOIN dbo.DetalleRecepcionCompra d ON d.RecepcionId=r.RecepcionId WHERE r.OperacionId=@Child AND d.ProductoId=@P;
   IF @R IS NULL OR @K IS NULL THROW 55006,'Recepcion sin detalle.',1;
   INSERT dbo.P3_COM_AplicacionRecepcion VALUES(@OperacionId,@OrdenCompraId,@P,@Q,@Cost,@R,@K,@Child);
  END;
  DECLARE @Nuevo VARCHAR(25)=CASE WHEN EXISTS(SELECT 1 FROM dbo.P3_COM_DetalleOrdenCompra d
   OUTER APPLY(SELECT SUM(CONVERT(BIGINT,a.Cantidad)) Recibido FROM dbo.P3_COM_AplicacionRecepcion a WHERE a.OrdenCompraId=d.OrdenCompraId AND a.ProductoId=d.ProductoId) r
   WHERE d.OrdenCompraId=@OrdenCompraId AND COALESCE(r.Recibido,0)<d.Cantidad) THEN 'PARCIALMENTE_RECIBIDA' ELSE 'RECIBIDA' END;
  UPDATE dbo.P3_COM_OrdenCompra SET Estado=@Nuevo WHERE OrdenCompraId=@OrdenCompraId;
  INSERT dbo.P3_COM_HistorialEstado(OrdenCompraId,OperacionId,SolicitudHash,Accion,EstadoAnterior,EstadoNuevo,ActorUsuarioId,Motivo,VersionResultado)
   SELECT @OrdenCompraId,@OperacionId,@Hash,'RECIBIR',@Estado,@Nuevo,@ActorUsuarioId,@Motivo,Version FROM dbo.P3_COM_OrdenCompra WHERE OrdenCompraId=@OrdenCompraId;
 END;
 COMMIT;
 SELECT OrdenCompraId,OperacionId,EstadoNuevo Estado,VersionResultado Version,FechaHora FROM dbo.P3_COM_HistorialEstado WHERE OperacionId=@OperacionId;
 END TRY BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK; THROW; END CATCH;
END;
GO
GRANT EXECUTE ON dbo.P3_COM_Recibir TO securefinance_app;
GO
