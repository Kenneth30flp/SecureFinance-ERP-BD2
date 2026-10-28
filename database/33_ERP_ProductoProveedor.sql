-- Incremental. Seleccionar destino y validar respaldo antes del despliegue.
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
IF OBJECT_ID('dbo.sp_ConsultarKardexWeb','P') IS NULL OR OBJECT_ID('dbo.sp_ObtenerDashboardVentas','P') IS NULL THROW 54800,'Requiere migraciones 15-32.',1;
BEGIN TRY
 BEGIN TRANSACTION;
 IF OBJECT_ID('dbo.ProductoProveedor','U') IS NULL
 CREATE TABLE dbo.ProductoProveedor(
  ProductoId INT NOT NULL REFERENCES dbo.Producto(ProductoId),
  ProveedorId INT NOT NULL REFERENCES dbo.Proveedor(ProveedorId),
  Activo BIT NOT NULL DEFAULT 1,
  FechaAsociacion DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
  PRIMARY KEY(ProductoId,ProveedorId)
 );
 IF ISNULL(COL_LENGTH('dbo.ProductoProveedor','ProductoId'),-1)<>4 OR ISNULL(COL_LENGTH('dbo.ProductoProveedor','ProveedorId'),-1)<>4
 OR ISNULL(COL_LENGTH('dbo.ProductoProveedor','Activo'),-1)<>1
 OR NOT EXISTS(SELECT 1 FROM sys.key_constraints WHERE parent_object_id=OBJECT_ID('dbo.ProductoProveedor') AND type='PK')
 OR (SELECT COUNT(*) FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID('dbo.ProductoProveedor') AND is_disabled=0 AND is_not_trusted=0 AND referenced_object_id IN(OBJECT_ID('dbo.Producto'),OBJECT_ID('dbo.Proveedor')))<>2
 THROW 54800,'ProductoProveedor existente incompatible: revisar esquema sin eliminar datos.',1;
 -- Solo conserva asociaciones conocidas; no atribuye existencias anteriores.
 INSERT dbo.ProductoProveedor(ProductoId,ProveedorId)
 SELECT p.ProductoId,p.ProveedorId FROM dbo.Producto p
 WHERE p.ProveedorId IS NOT NULL AND NOT EXISTS(
 SELECT 1 FROM dbo.ProductoProveedor r WITH(UPDLOCK,HOLDLOCK)
 WHERE r.ProductoId=p.ProductoId AND r.ProveedorId=p.ProveedorId);
 COMMIT;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK;
 THROW;
END CATCH;
GO
CREATE OR ALTER PROCEDURE dbo.sp_ConsultarProductoProveedor
 @ActorUsuarioId INT,@ProductoId INT=NULL,@ProveedorId INT=NULL AS
BEGIN
 SET NOCOUNT ON;
 DECLARE @Permiso NVARCHAR(100)=CASE WHEN @ProductoId IS NOT NULL THEN N'PRODUCTOS_CONSULTAR' ELSE N'PROVEEDORES_CONSULTAR' END;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,@Permiso;
 IF @ProductoId IS NULL AND @ProveedorId IS NULL THROW 54102,'Seleccione producto o proveedor.',1;
 -- Incluye proveedor principal aunque haya sido cambiado despues de esta migracion.
 ;WITH relaciones AS(
 SELECT ProductoId,ProveedorId,Activo FROM dbo.ProductoProveedor
 UNION ALL
 SELECT p.ProductoId,p.ProveedorId,CONVERT(BIT,1) FROM dbo.Producto p
 WHERE p.ProveedorId IS NOT NULL AND NOT EXISTS(SELECT 1 FROM dbo.ProductoProveedor r WHERE r.ProductoId=p.ProductoId AND r.ProveedorId=p.ProveedorId)
 )
 SELECT r.ProductoId,r.ProveedorId,r.Activo,p.Codigo,p.Descripcion,v.Nombre Proveedor,v.Activo ProveedorActivo,
 CONVERT(BIT,CASE WHEN p.ProveedorId=r.ProveedorId THEN 1 ELSE 0 END) Principal
 FROM relaciones r JOIN dbo.Producto p ON p.ProductoId=r.ProductoId JOIN dbo.Proveedor v ON v.ProveedorId=r.ProveedorId
 WHERE (@ProductoId IS NULL OR r.ProductoId=@ProductoId) AND (@ProveedorId IS NULL OR r.ProveedorId=@ProveedorId)
 ORDER BY p.Codigo,v.Nombre;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_AsociarProductoProveedor
 @ActorUsuarioId INT,@ProductoId INT,@ProveedorId INT,@Activo BIT AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
 BEGIN TRANSACTION;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'PRODUCTOS_ADMINISTRAR';
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'PROVEEDORES_CONSULTAR';
 IF @Activo IS NULL OR NOT EXISTS(SELECT 1 FROM dbo.Producto WITH(UPDLOCK,HOLDLOCK) WHERE ProductoId=@ProductoId)
 THROW 54104,'Producto inexistente.',1;
 IF NOT EXISTS(SELECT 1 FROM dbo.Proveedor WITH(UPDLOCK,HOLDLOCK) WHERE ProveedorId=@ProveedorId AND (@Activo=0 OR Activo=1)) THROW 54104,'Proveedor inexistente o inactivo.',1;
 IF @Activo=0 AND EXISTS(SELECT 1 FROM dbo.Producto WHERE ProductoId=@ProductoId AND ProveedorId=@ProveedorId) THROW 54102,'Cambie primero el proveedor principal.',1;
 DECLARE @Anterior BIT;
 SELECT @Anterior=Activo FROM dbo.ProductoProveedor WITH(UPDLOCK,HOLDLOCK) WHERE ProductoId=@ProductoId AND ProveedorId=@ProveedorId;
 IF @Anterior IS NULL INSERT dbo.ProductoProveedor(ProductoId,ProveedorId,Activo) VALUES(@ProductoId,@ProveedorId,@Activo);
 ELSE UPDATE dbo.ProductoProveedor SET Activo=@Activo WHERE ProductoId=@ProductoId AND ProveedorId=@ProveedorId;
 DECLARE @Op UNIQUEIDENTIFIER=NEWID();
 INSERT dbo.Bitacora_Transacciones(TablaAfectada,Operacion,IdentificadorRegistro,ValorAnterior,ValorNuevo,ActorUsuarioId,OperacionId,Motivo)
 VALUES(N'ProductoProveedor',CASE WHEN @Anterior IS NULL THEN 'INSERT' ELSE 'UPDATE' END,CONCAT(@ProductoId,N'/',@ProveedorId),CONVERT(NVARCHAR(1),@Anterior),CONVERT(NVARCHAR(1),@Activo),@ActorUsuarioId,@Op,N'Mantenimiento de relacion comercial');
 COMMIT;
 SELECT @ProductoId ProductoId;
 END TRY
 BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK;
 THROW;
 END CATCH;
END;
GO
