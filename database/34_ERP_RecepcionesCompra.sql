SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
IF OBJECT_ID('dbo.ProductoProveedor','U') IS NULL THROW 54800,'Requiere migracion 33.',1;
BEGIN TRY
 BEGIN TRANSACTION;
 IF OBJECT_ID('dbo.RecepcionCompra','U') IS NULL
 CREATE TABLE dbo.RecepcionCompra(
  RecepcionId BIGINT IDENTITY PRIMARY KEY,
  OperacionId UNIQUEIDENTIFIER NOT NULL UNIQUE,
  ProveedorId INT NOT NULL REFERENCES dbo.Proveedor(ProveedorId),
  ProveedorNombreEmision NVARCHAR(150) NULL,
  ProveedorNITEmision NVARCHAR(25) NULL,
  UsuarioId INT NOT NULL REFERENCES dbo.Usuario(UsuarioId),
  DocumentoRespaldo NVARCHAR(100) NOT NULL CHECK(LEN(LTRIM(RTRIM(DocumentoRespaldo)))>0),
  Motivo NVARCHAR(250) NOT NULL,
  FechaHora DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME()
 );
 IF COL_LENGTH('dbo.RecepcionCompra','ProveedorNombreEmision') IS NULL ALTER TABLE dbo.RecepcionCompra ADD ProveedorNombreEmision NVARCHAR(150) NULL;
 IF COL_LENGTH('dbo.RecepcionCompra','ProveedorNITEmision') IS NULL ALTER TABLE dbo.RecepcionCompra ADD ProveedorNITEmision NVARCHAR(25) NULL;
 IF OBJECT_ID('dbo.DetalleRecepcionCompra','U') IS NULL
 CREATE TABLE dbo.DetalleRecepcionCompra(
  RecepcionId BIGINT NOT NULL REFERENCES dbo.RecepcionCompra(RecepcionId),
  ProductoId INT NOT NULL REFERENCES dbo.Producto(ProductoId),
  Cantidad INT NOT NULL CHECK(Cantidad>0),
  CostoUnitario DECIMAL(19,2) NULL CHECK(CostoUnitario>=0),
  KardexId BIGINT NOT NULL UNIQUE REFERENCES dbo.Kardex_Inventario(KardexId),
  PRIMARY KEY(RecepcionId,ProductoId)
 );
 IF ISNULL(COL_LENGTH('dbo.RecepcionCompra','OperacionId'),-1)<>16 OR ISNULL(COL_LENGTH('dbo.RecepcionCompra','RecepcionId'),-1)<>8
 OR ISNULL(COL_LENGTH('dbo.DetalleRecepcionCompra','KardexId'),-1)<>8 OR ISNULL(COL_LENGTH('dbo.DetalleRecepcionCompra','Cantidad'),-1)<>4
 OR NOT EXISTS(SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID('dbo.DetalleRecepcionCompra') AND referenced_object_id=OBJECT_ID('dbo.Kardex_Inventario') AND is_disabled=0 AND is_not_trusted=0)
 THROW 54800,'Recepcion existente incompatible: revisar tipos y FK sin eliminar datos.',1;
 COMMIT;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK;
 THROW;
END CATCH;
GO
CREATE OR ALTER TRIGGER dbo.tr_ERP_RecepcionInmutable ON dbo.RecepcionCompra AFTER UPDATE,DELETE AS
BEGIN
 IF EXISTS(SELECT 1 FROM deleted) THROW 54805,'La recepcion historica es inmutable.',1;
END;
GO
CREATE OR ALTER TRIGGER dbo.tr_ERP_DetalleRecepcionInmutable ON dbo.DetalleRecepcionCompra AFTER UPDATE,DELETE AS
BEGIN
 IF EXISTS(SELECT 1 FROM deleted) THROW 54805,'El detalle de recepcion es inmutable.',1;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_ERP_RegistrarAjuste
 @ActorUsuarioId INT,@ProductoId INT,@TipoMovimiento VARCHAR(25),@Cantidad INT,
 @DocumentoRespaldo NVARCHAR(100),@OperacionId UNIQUEIDENTIFIER,@LineaOperacion INT,
 @Motivo NVARCHAR(250),@VersionEsperada BINARY(8) AS
BEGIN
 SET NOCOUNT ON;
 IF @TipoMovimiento IS NULL OR @TipoMovimiento NOT IN('AJUSTE_INGRESO','AJUSTE_EGRESO') THROW 54102,'Solo ajustes autorizados.',1;
 EXEC dbo.sp_RegistrarMovimientoKardex @ProductoId=@ProductoId,@TipoMovimiento=@TipoMovimiento,@Cantidad=@Cantidad,
 @ActorUsuarioId=@ActorUsuarioId,@DocumentoRespaldo=@DocumentoRespaldo,@OperacionId=@OperacionId,
 @LineaOperacion=@LineaOperacion,@Motivo=@Motivo,@VersionEsperada=@VersionEsperada;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_RegistrarRecepcionCompra
 @ActorUsuarioId INT,@ProductoId INT,@ProveedorId INT,@Cantidad INT,
 @DocumentoRespaldo NVARCHAR(100),@Motivo NVARCHAR(250),@OperacionId UNIQUEIDENTIFIER,
 @CostoUnitario DECIMAL(19,2)=NULL
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
 BEGIN TRANSACTION;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'INVENTARIO_REGISTRAR';
 IF @OperacionId IS NULL OR @Cantidad IS NULL OR @Cantidad<=0 OR @CostoUnitario<0
 OR NULLIF(LTRIM(RTRIM(@DocumentoRespaldo)),N'') IS NULL OR NULLIF(LTRIM(RTRIM(@Motivo)),N'') IS NULL
 THROW 54802,'Recepcion invalida.',1;
 DECLARE @Lock INT,@Resource NVARCHAR(255)=CONCAT(N'ERP.Recepcion.',@OperacionId),@Id BIGINT;
 EXEC @Lock=sys.sp_getapplock @Resource=@Resource,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
 IF @Lock<0 THROW 54803,'Recepcion ocupada.',1;
 SELECT @Id=RecepcionId FROM dbo.RecepcionCompra WITH(UPDLOCK,HOLDLOCK) WHERE OperacionId=@OperacionId;
 IF @Id IS NOT NULL
 BEGIN
 IF NOT EXISTS(SELECT 1 FROM dbo.RecepcionCompra r JOIN dbo.DetalleRecepcionCompra d ON d.RecepcionId=r.RecepcionId
 WHERE r.RecepcionId=@Id AND r.UsuarioId=@ActorUsuarioId AND r.ProveedorId=@ProveedorId
 AND r.DocumentoRespaldo COLLATE Latin1_General_100_BIN2=@DocumentoRespaldo COLLATE Latin1_General_100_BIN2
 AND DATALENGTH(r.DocumentoRespaldo)=DATALENGTH(@DocumentoRespaldo)
 AND r.Motivo COLLATE Latin1_General_100_BIN2=@Motivo COLLATE Latin1_General_100_BIN2 AND DATALENGTH(r.Motivo)=DATALENGTH(@Motivo)
 AND d.ProductoId=@ProductoId AND d.Cantidad=@Cantidad
 AND (d.CostoUnitario=@CostoUnitario OR (d.CostoUnitario IS NULL AND @CostoUnitario IS NULL)))
 THROW 54803,'Operacion utilizada con otros datos.',1;
 END
 ELSE
 BEGIN
 DECLARE @ProveedorNombre NVARCHAR(150),@ProveedorNIT NVARCHAR(25);
 SELECT @ProveedorNombre=Nombre,@ProveedorNIT=NIT FROM dbo.Proveedor WITH(UPDLOCK,HOLDLOCK) WHERE ProveedorId=@ProveedorId AND Activo=1;
 IF @ProveedorNombre IS NULL
 THROW 54104,'Proveedor inexistente o inactivo.',1;
 IF NOT EXISTS(SELECT 1 FROM dbo.Producto WITH(UPDLOCK,HOLDLOCK) WHERE ProductoId=@ProductoId AND Activo=1)
 THROW 54104,'Producto inexistente o inactivo.',1;
 -- La primera recepcion documentada establece la relacion comercial, sin cambiar el principal.
 IF EXISTS(SELECT 1 FROM dbo.ProductoProveedor WITH(UPDLOCK,HOLDLOCK) WHERE ProductoId=@ProductoId AND ProveedorId=@ProveedorId AND Activo=0)
 THROW 54104,'Relacion comercial inactiva.',1;
 IF NOT EXISTS(SELECT 1 FROM dbo.ProductoProveedor WITH(UPDLOCK,HOLDLOCK) WHERE ProductoId=@ProductoId AND ProveedorId=@ProveedorId)
 INSERT dbo.ProductoProveedor(ProductoId,ProveedorId) VALUES(@ProductoId,@ProveedorId);
 INSERT dbo.RecepcionCompra(OperacionId,ProveedorId,ProveedorNombreEmision,ProveedorNITEmision,UsuarioId,DocumentoRespaldo,Motivo)
 VALUES(@OperacionId,@ProveedorId,@ProveedorNombre,@ProveedorNIT,@ActorUsuarioId,@DocumentoRespaldo,@Motivo);
 SET @Id=SCOPE_IDENTITY();
 EXEC dbo.sp_RegistrarMovimientoKardex @ProductoId=@ProductoId,@TipoMovimiento='COMPRA',@Cantidad=@Cantidad,
 @ActorUsuarioId=@ActorUsuarioId,@DocumentoRespaldo=@DocumentoRespaldo,@OperacionId=@OperacionId,
 @LineaOperacion=1,@Motivo=@Motivo,@DevolverResultado=0;
 INSERT dbo.DetalleRecepcionCompra(RecepcionId,ProductoId,Cantidad,CostoUnitario,KardexId)
 SELECT @Id,@ProductoId,@Cantidad,@CostoUnitario,KardexId FROM dbo.Kardex_Inventario
 WHERE OperacionId=@OperacionId AND LineaOperacion=1 AND ProductoId=@ProductoId AND TipoMovimiento='COMPRA';
 IF @@ROWCOUNT<>1 THROW 54802,'Recepcion sin movimiento Kardex.',1;
 INSERT dbo.Bitacora_Transacciones(TablaAfectada,Operacion,IdentificadorRegistro,ValorNuevo,ActorUsuarioId,OperacionId,Motivo)
 VALUES(N'RecepcionCompra','INSERT',CONVERT(NVARCHAR(20),@Id),
 (SELECT @ProveedorId ProveedorId,@ProductoId ProductoId,@Cantidad Cantidad,@DocumentoRespaldo DocumentoRespaldo FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),
 @ActorUsuarioId,@OperacionId,@Motivo);
 END;
 SELECT r.RecepcionId,r.OperacionId,r.FechaHora,r.ProveedorId,COALESCE(r.ProveedorNombreEmision,v.Nombre) Proveedor,r.ProveedorNITEmision,u.NombreUsuario Actor,d.KardexId,d.Cantidad,k.StockAnterior,k.StockResultante,r.DocumentoRespaldo
 FROM dbo.RecepcionCompra r JOIN dbo.DetalleRecepcionCompra d ON d.RecepcionId=r.RecepcionId
 JOIN dbo.Kardex_Inventario k ON k.KardexId=d.KardexId JOIN dbo.Proveedor v ON v.ProveedorId=r.ProveedorId
 JOIN dbo.Usuario u ON u.UsuarioId=r.UsuarioId WHERE r.RecepcionId=@Id;
 COMMIT;
 END TRY
 BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK;
 THROW;
 END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_ERP_ConsultarKardex
 @ActorUsuarioId INT,@ProductoId INT,@Desde DATETIME2(3)=NULL,@Hasta DATETIME2(3)=NULL,@Desplazamiento INT=0 AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'INVENTARIO_CONSULTAR';
 IF @ProductoId IS NULL OR @ProductoId<1 OR @Desplazamiento IS NULL OR @Desplazamiento<0 OR @Desde>=@Hasta THROW 54102,'Filtros invalidos.',1;
 SELECT k.*,u.NombreUsuario Actor,COALESCE(r.ProveedorNombreEmision,v.Nombre) Proveedor,r.ProveedorId,r.ProveedorNITEmision
 FROM dbo.Kardex_Inventario k JOIN dbo.Usuario u ON u.UsuarioId=k.UsuarioId
 LEFT JOIN dbo.DetalleRecepcionCompra d ON d.KardexId=k.KardexId
 LEFT JOIN dbo.RecepcionCompra r ON r.RecepcionId=d.RecepcionId
 LEFT JOIN dbo.Proveedor v ON v.ProveedorId=r.ProveedorId
 WHERE k.ProductoId=@ProductoId AND (@Desde IS NULL OR k.FechaHora>=@Desde) AND (@Hasta IS NULL OR k.FechaHora<@Hasta)
 ORDER BY k.FechaHora DESC,k.KardexId DESC OFFSET @Desplazamiento ROWS FETCH NEXT 51 ROWS ONLY;
END;
GO
