-- Incremental: apply before deploying the new product-registration backend.
-- Never rewrites existing product codes, identities or business relationships.
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
IF OBJECT_ID('dbo.sp_RegistrarProducto','P') IS NULL
 OR DATABASE_PRINCIPAL_ID(N'securefinance_app') IS NULL
 THROW 54800,'Requiere alta de productos y cuenta de aplicacion existentes.',1;
IF NOT EXISTS(SELECT 1 FROM sys.indexes i JOIN sys.index_columns ic
 ON ic.object_id=i.object_id AND ic.index_id=i.index_id
 JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id
 WHERE i.object_id=OBJECT_ID('dbo.Producto') AND i.is_unique=1 AND i.is_disabled=0
 AND i.has_filter=0 AND c.name='Codigo' AND ic.key_ordinal=1
 AND NOT EXISTS(SELECT 1 FROM sys.index_columns k WHERE k.object_id=i.object_id
 AND k.index_id=i.index_id AND k.key_ordinal>1))
 THROW 54800,'Requiere unicidad efectiva de Producto.Codigo.',1;
BEGIN TRY
 BEGIN TRANSACTION;
 DECLARE @Lock int;
 EXEC @Lock=sys.sp_getapplock @Resource=N'ERP.Producto.SKU',@LockMode='Exclusive',
 @LockOwner='Transaction',@LockTimeout=15000;
 IF @Lock<0 THROW 54803,'Alta de productos ocupada. Reintenta.',1;
 IF OBJECT_ID('dbo.SeqProductoSKU','SO') IS NULL
 BEGIN
  -- Initialization only, protected against concurrent inserts until commit.
  -- Runtime allocation always uses NEXT VALUE FOR, never MAX + 1.
  DECLARE @Start bigint,@Sql nvarchar(max);
  SELECT @Start=ISNULL(MAX(CONVERT(bigint,ProductoId)),0)+1
  FROM dbo.Producto WITH(TABLOCKX,HOLDLOCK);
  SET @Sql=N'CREATE SEQUENCE dbo.SeqProductoSKU AS bigint START WITH '+CONVERT(nvarchar(20),@Start)
   +N' INCREMENT BY 1 MINVALUE 1 NO MAXVALUE NO CYCLE NO CACHE;';
  EXEC sys.sp_executesql @Sql;
 END;
 IF NOT EXISTS(SELECT 1 FROM sys.sequences WHERE object_id=OBJECT_ID('dbo.SeqProductoSKU')
 AND system_type_id=127 AND CONVERT(bigint,increment)=1 AND is_cycling=0)
 THROW 54800,'Secuencia SKU existente incompatible; no reiniciar.',1;
 COMMIT;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK;
 THROW;
END CATCH;
GO
CREATE OR ALTER PROCEDURE dbo.sp_ERP_RegistrarProducto
 @ActorUsuarioId int,@Codigo nvarchar(max)=NULL,@Descripcion nvarchar(max)=NULL,
 @Precio decimal(12,2)=NULL,@PrecioCosto decimal(12,2)=NULL,@ProveedorId int=NULL,
 @StockMinimo int=5,@PuntoReorden int=5,@GarantiaMeses smallint=0,
 @Fotografia varchar(max)=NULL,@CodigoAutomatico bit=1
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRANSACTION;
  EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'PRODUCTOS_ADMINISTRAR';
  IF @CodigoAutomatico IS NULL THROW 54102,'Selecciona SKU automatico o manual.',1;
  DECLARE @Lock int,@Numero bigint,@Digits varchar(20);
  EXEC @Lock=sys.sp_getapplock @Resource=N'ERP.Producto.SKU',@LockMode='Exclusive',
   @LockOwner='Transaction',@LockTimeout=15000;
  IF @Lock<0 THROW 54803,'Alta de productos ocupada. Reintenta.',1;
  IF @CodigoAutomatico=1
  BEGIN
   WHILE 1=1
   BEGIN
    SET @Numero=NEXT VALUE FOR dbo.SeqProductoSKU;
    SET @Digits=CONVERT(varchar(20),@Numero);
    SET @Codigo=N'PRD-'+REPLICATE('0',CASE WHEN LEN(@Digits)<6 THEN 6-LEN(@Digits) ELSE 0 END)+@Digits;
    -- Range lock also protects against older clients and concurrent code edits.
    IF NOT EXISTS(SELECT 1 FROM dbo.Producto WITH(UPDLOCK,HOLDLOCK) WHERE Codigo=@Codigo) BREAK;
   END;
  END;
  -- Keep the established validation, stock defaults, RBAC, audit and result row.
  -- In manual mode the unique index rejects duplicates with 2601/2627.
  EXEC dbo.sp_RegistrarProducto @ActorUsuarioId=@ActorUsuarioId,@Codigo=@Codigo,
   @Descripcion=@Descripcion,@Precio=@Precio,@PrecioCosto=@PrecioCosto,@ProveedorId=@ProveedorId,
   @StockMinimo=@StockMinimo,@PuntoReorden=@PuntoReorden,@GarantiaMeses=@GarantiaMeses,@Fotografia=@Fotografia;
  COMMIT;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK;
  THROW;
 END CATCH;
END;
GO
GRANT EXECUTE ON dbo.sp_ERP_RegistrarProducto TO securefinance_app;
GO
