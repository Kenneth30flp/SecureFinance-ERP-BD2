-- Parte II / Kenneth. Incremental; ejecutar en la base destino seleccionada.
-- No contiene USE: permite validacion aislada. No ejecutar sobre produccion sin aprobacion.
SET NOCOUNT ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
BEGIN TRY
 BEGIN TRANSACTION;
 IF OBJECT_ID('dbo.Proveedor','U') IS NULL
 BEGIN
 CREATE TABLE dbo.Proveedor (
 ProveedorId INT IDENTITY CONSTRAINT PK_Proveedor PRIMARY KEY,
 NIT NVARCHAR(25) NOT NULL,
 NITNormalizado AS CONVERT(NVARCHAR(25),UPPER(REPLACE(LTRIM(RTRIM(NIT)),N'-',N''))) PERSISTED,
 Nombre NVARCHAR(150) NOT NULL,
 Correo NVARCHAR(254) NULL, Telefono NVARCHAR(25) NULL,
 Direccion NVARCHAR(300) NULL,
 Fotografia VARCHAR(40) NULL,
 Activo BIT NOT NULL CONSTRAINT DF_Proveedor_Activo DEFAULT 1,
 FechaCreacion DATETIME2(3) NOT NULL CONSTRAINT DF_Proveedor_Fecha DEFAULT SYSUTCDATETIME(),
 Version ROWVERSION,
 CONSTRAINT CK_Proveedor_Texto CHECK (LEN(LTRIM(RTRIM(NIT)))>0 AND LEN(LTRIM(RTRIM(Nombre)))>0),
 CONSTRAINT CK_Proveedor_Foto CHECK (Fotografia IS NULL OR (LEN(Fotografia)=40 AND RIGHT(Fotografia,4) COLLATE Latin1_General_100_BIN2 IN ('.jpg','.png') AND LEFT(Fotografia,36) COLLATE Latin1_General_100_BIN2=LOWER(CONVERT(CHAR(36),TRY_CONVERT(UNIQUEIDENTIFIER,LEFT(Fotografia,36)))) AND TRY_CONVERT(UNIQUEIDENTIFIER,LEFT(Fotografia,36)) IS NOT NULL))
 );
 END;
 IF COL_LENGTH('dbo.Producto','ProveedorId') IS NULL
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Producto ADD ProveedorId INT NULL CONSTRAINT FK_Producto_Proveedor REFERENCES dbo.Proveedor(ProveedorId);';
 IF COL_LENGTH('dbo.Producto','PrecioCosto') IS NULL
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Producto ADD PrecioCosto DECIMAL(12,2) NULL;';
 IF COL_LENGTH('dbo.Producto','Fotografia') IS NULL
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Producto ADD Fotografia VARCHAR(40) NULL;';
 IF COL_LENGTH('dbo.Producto','StockMinimo') IS NULL
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Producto ADD StockMinimo INT NOT NULL CONSTRAINT DF_Producto_StockMinimo DEFAULT 5 WITH VALUES;';
 IF COL_LENGTH('dbo.Producto','PuntoReorden') IS NULL
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Producto ADD PuntoReorden INT NOT NULL CONSTRAINT DF_Producto_PuntoReorden DEFAULT 5 WITH VALUES;';
 IF COL_LENGTH('dbo.Producto','GarantiaMeses') IS NULL
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Producto ADD GarantiaMeses SMALLINT NULL;';
 IF COL_LENGTH('dbo.Producto','Version') IS NULL
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Producto ADD Version ROWVERSION;';
 IF COL_LENGTH('dbo.Cliente','Version') IS NULL
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Cliente ADD Version ROWVERSION;';
 IF COL_LENGTH('dbo.Cliente','FechaInactivacion') IS NULL
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Cliente ADD FechaInactivacion DATETIME2(3) NULL;';
 IF COL_LENGTH('dbo.Cliente','MotivoInactivacion') IS NULL
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Cliente ADD MotivoInactivacion NVARCHAR(250) NULL;';
 IF COL_LENGTH('dbo.Cliente','NITNormalizado') IS NULL
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Cliente ADD NITNormalizado AS CONVERT(NVARCHAR(25),UPPER(REPLACE(LTRIM(RTRIM(NIT)),N''-'',N''''))) PERSISTED;';
 IF COL_LENGTH('dbo.Factura','ClienteNITEmision') IS NULL
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Factura ADD ClienteNITEmision NVARCHAR(25) NULL;';
 IF COL_LENGTH('dbo.Factura','ClienteNombreEmision') IS NULL
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Factura ADD ClienteNombreEmision NVARCHAR(150) NULL;';
 IF COL_LENGTH('dbo.Bitacora_Transacciones','ActorUsuarioId') IS NULL
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Bitacora_Transacciones ADD ActorUsuarioId INT NULL CONSTRAINT FK_BitacoraTransacciones_Actor REFERENCES dbo.Usuario(UsuarioId);';
 IF COL_LENGTH('dbo.Bitacora_Transacciones','OperacionId') IS NULL
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Bitacora_Transacciones ADD OperacionId UNIQUEIDENTIFIER NULL;';
 IF OBJECT_ID('dbo.CK_Producto_Costo','C') IS NULL
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Producto WITH CHECK ADD CONSTRAINT CK_Producto_Costo CHECK (PrecioCosto IS NULL OR PrecioCosto>=0);';
 IF OBJECT_ID('dbo.CK_Producto_Reposicion','C') IS NULL
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Producto WITH CHECK ADD CONSTRAINT CK_Producto_Reposicion CHECK (StockMinimo>=0 AND PuntoReorden>=StockMinimo);';
 IF OBJECT_ID('dbo.CK_Producto_Garantia','C') IS NULL
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Producto WITH CHECK ADD CONSTRAINT CK_Producto_Garantia CHECK (GarantiaMeses IS NULL OR GarantiaMeses>=0);';
 IF OBJECT_ID('dbo.CK_Producto_Foto','C') IS NULL
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Producto WITH CHECK ADD CONSTRAINT CK_Producto_Foto CHECK (Fotografia IS NULL OR (LEN(Fotografia)=40 AND RIGHT(Fotografia,4) COLLATE Latin1_General_100_BIN2 IN (''.jpg'',''.png'') AND TRY_CONVERT(UNIQUEIDENTIFIER,LEFT(Fotografia,36)) IS NOT NULL AND LEFT(Fotografia,36) COLLATE Latin1_General_100_BIN2=LOWER(CONVERT(CHAR(36),TRY_CONVERT(UNIQUEIDENTIFIER,LEFT(Fotografia,36))))));';
 IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.Cliente') AND name='UX_Cliente_NITNormalizado')
 EXEC sys.sp_executesql N'CREATE UNIQUE INDEX UX_Cliente_NITNormalizado ON dbo.Cliente(NITNormalizado);';
 IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.Proveedor') AND name='UX_Proveedor_NITNormalizado')
 EXEC sys.sp_executesql N'CREATE UNIQUE INDEX UX_Proveedor_NITNormalizado ON dbo.Proveedor(NITNormalizado);';
 IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.Proveedor') AND name='IX_Proveedor_Nombre')
 EXEC sys.sp_executesql N'CREATE  INDEX IX_Proveedor_Nombre ON dbo.Proveedor(Nombre, ProveedorId);';
 IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.Producto') AND name='IX_Producto_Proveedor')
 EXEC sys.sp_executesql N'CREATE  INDEX IX_Producto_Proveedor ON dbo.Producto(ProveedorId, ProductoId);';
 IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.Producto') AND name='IX_Producto_Descripcion')
 EXEC sys.sp_executesql N'CREATE  INDEX IX_Producto_Descripcion ON dbo.Producto(Descripcion, ProductoId);';
 IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.Cliente') AND name='IX_Cliente_Administracion')
 EXEC sys.sp_executesql N'CREATE  INDEX IX_Cliente_Administracion ON dbo.Cliente(Activo, Nombre, ClienteId);';
 IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Producto') AND name='PrecioCosto' AND TYPE_NAME(system_type_id)='decimal' AND max_length=9) THROW 54001, 'Esquema incompatible: Producto.PrecioCosto', 1;
 IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Producto') AND name='Fotografia' AND TYPE_NAME(system_type_id)='varchar' AND max_length=40) THROW 54001, 'Esquema incompatible: Producto.Fotografia', 1;
 IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Producto') AND name='Version' AND TYPE_NAME(system_type_id)='timestamp' AND max_length=8) THROW 54001, 'Esquema incompatible: Producto.Version', 1;
 IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Cliente') AND name='Version' AND TYPE_NAME(system_type_id)='timestamp' AND max_length=8) THROW 54001, 'Esquema incompatible: Cliente.Version', 1;
 IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Factura') AND name='ClienteNITEmision' AND TYPE_NAME(system_type_id)='nvarchar' AND max_length=50) THROW 54001, 'Esquema incompatible: Factura.ClienteNITEmision', 1;
 IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Proveedor') AND name='ProveedorId' AND TYPE_NAME(system_type_id)='int' AND max_length=4) THROW 54001, 'Esquema incompatible: Proveedor.ProveedorId', 1;

 IF OBJECT_ID('dbo.CK_Cliente_NITNormalizado','C') IS NULL
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Cliente WITH CHECK ADD CONSTRAINT CK_Cliente_NITNormalizado CHECK(LEN(NITNormalizado)>0);';
 IF OBJECT_ID('dbo.CK_Proveedor_NITNormalizado','C') IS NULL
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Proveedor WITH CHECK ADD CONSTRAINT CK_Proveedor_NITNormalizado CHECK(LEN(NITNormalizado)>0);';
 IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Proveedor') AND name='NIT' AND TYPE_NAME(system_type_id)='nvarchar' AND max_length=50) THROW 54001, 'Columna incompatible: Proveedor.NIT',1;
 IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Proveedor') AND name='Nombre' AND TYPE_NAME(system_type_id)='nvarchar' AND max_length=300) THROW 54001, 'Columna incompatible: Proveedor.Nombre',1;
 IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Proveedor') AND name='Fotografia' AND TYPE_NAME(system_type_id)='varchar' AND max_length=40) THROW 54001, 'Columna incompatible: Proveedor.Fotografia',1;
 IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Proveedor') AND name='Version' AND TYPE_NAME(system_type_id)='timestamp' AND max_length=8) THROW 54001, 'Columna incompatible: Proveedor.Version',1;
 IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Proveedor') AND name='NITNormalizado' AND TYPE_NAME(system_type_id)='nvarchar' AND max_length=50) THROW 54001, 'Columna incompatible: Proveedor.NITNormalizado',1;
 IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Producto') AND name='ProveedorId' AND TYPE_NAME(system_type_id)='int' AND max_length=4) THROW 54001, 'Columna incompatible: Producto.ProveedorId',1;
 IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Producto') AND name='PrecioCosto' AND TYPE_NAME(system_type_id)='decimal' AND max_length=9) THROW 54001, 'Columna incompatible: Producto.PrecioCosto',1;
 IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Producto') AND name='StockMinimo' AND TYPE_NAME(system_type_id)='int' AND max_length=4) THROW 54001, 'Columna incompatible: Producto.StockMinimo',1;
 IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Producto') AND name='PuntoReorden' AND TYPE_NAME(system_type_id)='int' AND max_length=4) THROW 54001, 'Columna incompatible: Producto.PuntoReorden',1;
 IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Producto') AND name='GarantiaMeses' AND TYPE_NAME(system_type_id)='smallint' AND max_length=2) THROW 54001, 'Columna incompatible: Producto.GarantiaMeses',1;
 IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Cliente') AND name='NITNormalizado' AND TYPE_NAME(system_type_id)='nvarchar' AND max_length=50) THROW 54001, 'Columna incompatible: Cliente.NITNormalizado',1;
 IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Cliente') AND name='FechaInactivacion' AND TYPE_NAME(system_type_id)='datetime2' AND scale=3) THROW 54001, 'Columna incompatible: Cliente.FechaInactivacion',1;
 IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Cliente') AND name='MotivoInactivacion' AND TYPE_NAME(system_type_id)='nvarchar' AND max_length=500) THROW 54001, 'Columna incompatible: Cliente.MotivoInactivacion',1;
 IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Factura') AND name='ClienteNombreEmision' AND TYPE_NAME(system_type_id)='nvarchar' AND max_length=300) THROW 54001, 'Columna incompatible: Factura.ClienteNombreEmision',1;
 IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Bitacora_Transacciones') AND name='ActorUsuarioId' AND TYPE_NAME(system_type_id)='int' AND max_length=4) THROW 54001, 'Columna incompatible: Bitacora_Transacciones.ActorUsuarioId',1;
 IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Bitacora_Transacciones') AND name='OperacionId' AND TYPE_NAME(system_type_id)='uniqueidentifier' AND max_length=16) THROW 54001, 'Columna incompatible: Bitacora_Transacciones.OperacionId',1;
 IF EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Producto') AND name='PrecioCosto' AND (precision<>12 OR scale<>2)) THROW 54001,'Precision de costo incompatible.',1;
 IF NOT EXISTS(SELECT 1 FROM sys.foreign_key_columns WHERE constraint_object_id=OBJECT_ID('dbo.FK_Producto_Proveedor') AND parent_object_id=OBJECT_ID('dbo.Producto') AND parent_column_id=COLUMNPROPERTY(OBJECT_ID('dbo.Producto'),'ProveedorId','ColumnId') AND referenced_object_id=OBJECT_ID('dbo.Proveedor') AND referenced_column_id=COLUMNPROPERTY(OBJECT_ID('dbo.Proveedor'),'ProveedorId','ColumnId')) THROW 54001,'FK de proveedor incompatible.',1;
 IF EXISTS(SELECT 1 FROM sys.check_constraints WHERE parent_object_id IN(OBJECT_ID('dbo.Proveedor'),OBJECT_ID('dbo.Producto'),OBJECT_ID('dbo.Cliente')) AND (is_disabled=1 OR is_not_trusted=1)) THROW 54001,'CHECK deshabilitado o no confiable.',1;
 IF EXISTS(SELECT 1 FROM sys.foreign_keys WHERE name IN ('FK_Producto_Proveedor','FK_BitacoraTransacciones_Actor') AND (is_disabled=1 OR is_not_trusted=1)) THROW 54001,'FK no confiable.',1;

 -- Verificar definiciones propias tambien al repetir; no aceptar solo el nombre.
 IF NOT EXISTS(SELECT 1 FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Proveedor_Texto') AND is_disabled=0 AND is_not_trusted=0) THROW 54001,'CHECK ausente o no confiable: CK_Proveedor_Texto',1;
 IF OBJECT_ID('dbo.CK_Proveedor_Texto_ValidacionEtapaII') IS NOT NULL THROW 54001,'Nombre de validacion ocupado: CK_Proveedor_Texto_ValidacionEtapaII',1;
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Proveedor WITH CHECK ADD CONSTRAINT CK_Proveedor_Texto_ValidacionEtapaII CHECK(LEN(LTRIM(RTRIM(NIT)))>0 AND LEN(LTRIM(RTRIM(Nombre)))>0);';
 IF (SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(definition),N'[',N''),N']',N''),N' ',N''),N'(',N''),N')',N''),CHAR(13),N''),CHAR(10),N'') FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Proveedor_Texto'))<>(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(definition),N'[',N''),N']',N''),N' ',N''),N'(',N''),N')',N''),CHAR(13),N''),CHAR(10),N'') FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Proveedor_Texto_ValidacionEtapaII')) THROW 54001,'CHECK incompatible: CK_Proveedor_Texto',1;
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Proveedor DROP CONSTRAINT CK_Proveedor_Texto_ValidacionEtapaII;';
 IF NOT EXISTS(SELECT 1 FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Proveedor_Foto') AND is_disabled=0 AND is_not_trusted=0) THROW 54001,'CHECK ausente o no confiable: CK_Proveedor_Foto',1;
 IF OBJECT_ID('dbo.CK_Proveedor_Foto_ValidacionEtapaII') IS NOT NULL THROW 54001,'Nombre de validacion ocupado: CK_Proveedor_Foto_ValidacionEtapaII',1;
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Proveedor WITH CHECK ADD CONSTRAINT CK_Proveedor_Foto_ValidacionEtapaII CHECK(Fotografia IS NULL OR (LEN(Fotografia)=40 AND RIGHT(Fotografia,4) COLLATE Latin1_General_100_BIN2 IN (''.jpg'',''.png'') AND LEFT(Fotografia,36) COLLATE Latin1_General_100_BIN2=LOWER(CONVERT(CHAR(36),TRY_CONVERT(UNIQUEIDENTIFIER,LEFT(Fotografia,36)))) AND TRY_CONVERT(UNIQUEIDENTIFIER,LEFT(Fotografia,36)) IS NOT NULL));';
 IF (SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(definition),N'[',N''),N']',N''),N' ',N''),N'(',N''),N')',N''),CHAR(13),N''),CHAR(10),N'') FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Proveedor_Foto'))<>(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(definition),N'[',N''),N']',N''),N' ',N''),N'(',N''),N')',N''),CHAR(13),N''),CHAR(10),N'') FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Proveedor_Foto_ValidacionEtapaII')) THROW 54001,'CHECK incompatible: CK_Proveedor_Foto',1;
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Proveedor DROP CONSTRAINT CK_Proveedor_Foto_ValidacionEtapaII;';
 IF NOT EXISTS(SELECT 1 FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Producto_Costo') AND is_disabled=0 AND is_not_trusted=0) THROW 54001,'CHECK ausente o no confiable: CK_Producto_Costo',1;
 IF OBJECT_ID('dbo.CK_Producto_Costo_ValidacionEtapaII') IS NOT NULL THROW 54001,'Nombre de validacion ocupado: CK_Producto_Costo_ValidacionEtapaII',1;
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Producto WITH CHECK ADD CONSTRAINT CK_Producto_Costo_ValidacionEtapaII CHECK(PrecioCosto IS NULL OR PrecioCosto>=0);';
 IF (SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(definition),N'[',N''),N']',N''),N' ',N''),N'(',N''),N')',N''),CHAR(13),N''),CHAR(10),N'') FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Producto_Costo'))<>(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(definition),N'[',N''),N']',N''),N' ',N''),N'(',N''),N')',N''),CHAR(13),N''),CHAR(10),N'') FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Producto_Costo_ValidacionEtapaII')) THROW 54001,'CHECK incompatible: CK_Producto_Costo',1;
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Producto DROP CONSTRAINT CK_Producto_Costo_ValidacionEtapaII;';
 IF NOT EXISTS(SELECT 1 FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Producto_Reposicion') AND is_disabled=0 AND is_not_trusted=0) THROW 54001,'CHECK ausente o no confiable: CK_Producto_Reposicion',1;
 IF OBJECT_ID('dbo.CK_Producto_Reposicion_ValidacionEtapaII') IS NOT NULL THROW 54001,'Nombre de validacion ocupado: CK_Producto_Reposicion_ValidacionEtapaII',1;
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Producto WITH CHECK ADD CONSTRAINT CK_Producto_Reposicion_ValidacionEtapaII CHECK(StockMinimo>=0 AND PuntoReorden>=StockMinimo);';
 IF (SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(definition),N'[',N''),N']',N''),N' ',N''),N'(',N''),N')',N''),CHAR(13),N''),CHAR(10),N'') FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Producto_Reposicion'))<>(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(definition),N'[',N''),N']',N''),N' ',N''),N'(',N''),N')',N''),CHAR(13),N''),CHAR(10),N'') FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Producto_Reposicion_ValidacionEtapaII')) THROW 54001,'CHECK incompatible: CK_Producto_Reposicion',1;
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Producto DROP CONSTRAINT CK_Producto_Reposicion_ValidacionEtapaII;';
 IF NOT EXISTS(SELECT 1 FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Producto_Garantia') AND is_disabled=0 AND is_not_trusted=0) THROW 54001,'CHECK ausente o no confiable: CK_Producto_Garantia',1;
 IF OBJECT_ID('dbo.CK_Producto_Garantia_ValidacionEtapaII') IS NOT NULL THROW 54001,'Nombre de validacion ocupado: CK_Producto_Garantia_ValidacionEtapaII',1;
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Producto WITH CHECK ADD CONSTRAINT CK_Producto_Garantia_ValidacionEtapaII CHECK(GarantiaMeses IS NULL OR GarantiaMeses>=0);';
 IF (SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(definition),N'[',N''),N']',N''),N' ',N''),N'(',N''),N')',N''),CHAR(13),N''),CHAR(10),N'') FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Producto_Garantia'))<>(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(definition),N'[',N''),N']',N''),N' ',N''),N'(',N''),N')',N''),CHAR(13),N''),CHAR(10),N'') FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Producto_Garantia_ValidacionEtapaII')) THROW 54001,'CHECK incompatible: CK_Producto_Garantia',1;
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Producto DROP CONSTRAINT CK_Producto_Garantia_ValidacionEtapaII;';
 IF NOT EXISTS(SELECT 1 FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Producto_Foto') AND is_disabled=0 AND is_not_trusted=0) THROW 54001,'CHECK ausente o no confiable: CK_Producto_Foto',1;
 IF OBJECT_ID('dbo.CK_Producto_Foto_ValidacionEtapaII') IS NOT NULL THROW 54001,'Nombre de validacion ocupado: CK_Producto_Foto_ValidacionEtapaII',1;
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Producto WITH CHECK ADD CONSTRAINT CK_Producto_Foto_ValidacionEtapaII CHECK(Fotografia IS NULL OR (LEN(Fotografia)=40 AND RIGHT(Fotografia,4) COLLATE Latin1_General_100_BIN2 IN (''.jpg'',''.png'') AND TRY_CONVERT(UNIQUEIDENTIFIER,LEFT(Fotografia,36)) IS NOT NULL AND LEFT(Fotografia,36) COLLATE Latin1_General_100_BIN2=LOWER(CONVERT(CHAR(36),TRY_CONVERT(UNIQUEIDENTIFIER,LEFT(Fotografia,36))))));';
 IF (SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(definition),N'[',N''),N']',N''),N' ',N''),N'(',N''),N')',N''),CHAR(13),N''),CHAR(10),N'') FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Producto_Foto'))<>(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(definition),N'[',N''),N']',N''),N' ',N''),N'(',N''),N')',N''),CHAR(13),N''),CHAR(10),N'') FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Producto_Foto_ValidacionEtapaII')) THROW 54001,'CHECK incompatible: CK_Producto_Foto',1;
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Producto DROP CONSTRAINT CK_Producto_Foto_ValidacionEtapaII;';
 IF NOT EXISTS(SELECT 1 FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Cliente_NITNormalizado') AND is_disabled=0 AND is_not_trusted=0) THROW 54001,'CHECK ausente o no confiable: CK_Cliente_NITNormalizado',1;
 IF OBJECT_ID('dbo.CK_Cliente_NITNormalizado_ValidacionEtapaII') IS NOT NULL THROW 54001,'Nombre de validacion ocupado: CK_Cliente_NITNormalizado_ValidacionEtapaII',1;
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Cliente WITH CHECK ADD CONSTRAINT CK_Cliente_NITNormalizado_ValidacionEtapaII CHECK(LEN(NITNormalizado)>0);';
 IF (SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(definition),N'[',N''),N']',N''),N' ',N''),N'(',N''),N')',N''),CHAR(13),N''),CHAR(10),N'') FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Cliente_NITNormalizado'))<>(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(definition),N'[',N''),N']',N''),N' ',N''),N'(',N''),N')',N''),CHAR(13),N''),CHAR(10),N'') FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Cliente_NITNormalizado_ValidacionEtapaII')) THROW 54001,'CHECK incompatible: CK_Cliente_NITNormalizado',1;
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Cliente DROP CONSTRAINT CK_Cliente_NITNormalizado_ValidacionEtapaII;';
 IF NOT EXISTS(SELECT 1 FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Proveedor_NITNormalizado') AND is_disabled=0 AND is_not_trusted=0) THROW 54001,'CHECK ausente o no confiable: CK_Proveedor_NITNormalizado',1;
 IF OBJECT_ID('dbo.CK_Proveedor_NITNormalizado_ValidacionEtapaII') IS NOT NULL THROW 54001,'Nombre de validacion ocupado: CK_Proveedor_NITNormalizado_ValidacionEtapaII',1;
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Proveedor WITH CHECK ADD CONSTRAINT CK_Proveedor_NITNormalizado_ValidacionEtapaII CHECK(LEN(NITNormalizado)>0);';
 IF (SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(definition),N'[',N''),N']',N''),N' ',N''),N'(',N''),N')',N''),CHAR(13),N''),CHAR(10),N'') FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Proveedor_NITNormalizado'))<>(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(definition),N'[',N''),N']',N''),N' ',N''),N'(',N''),N')',N''),CHAR(13),N''),CHAR(10),N'') FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Proveedor_NITNormalizado_ValidacionEtapaII')) THROW 54001,'CHECK incompatible: CK_Proveedor_NITNormalizado',1;
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Proveedor DROP CONSTRAINT CK_Proveedor_NITNormalizado_ValidacionEtapaII;';
 IF NOT EXISTS(SELECT 1 FROM sys.indexes x WHERE x.object_id=OBJECT_ID('dbo.Cliente') AND x.name='UX_Cliente_NITNormalizado' AND x.is_unique=1 AND x.is_disabled=0 AND (SELECT STRING_AGG(CONVERT(NVARCHAR(MAX),c.name),N',') WITHIN GROUP(ORDER BY ic.key_ordinal) FROM sys.index_columns ic JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id WHERE ic.object_id=x.object_id AND ic.index_id=x.index_id AND ic.key_ordinal>0)=N'NITNormalizado') THROW 54001,'Indice incompatible: UX_Cliente_NITNormalizado',1;
 IF NOT EXISTS(SELECT 1 FROM sys.indexes x WHERE x.object_id=OBJECT_ID('dbo.Proveedor') AND x.name='UX_Proveedor_NITNormalizado' AND x.is_unique=1 AND x.is_disabled=0 AND (SELECT STRING_AGG(CONVERT(NVARCHAR(MAX),c.name),N',') WITHIN GROUP(ORDER BY ic.key_ordinal) FROM sys.index_columns ic JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id WHERE ic.object_id=x.object_id AND ic.index_id=x.index_id AND ic.key_ordinal>0)=N'NITNormalizado') THROW 54001,'Indice incompatible: UX_Proveedor_NITNormalizado',1;
 IF NOT EXISTS(SELECT 1 FROM sys.indexes x WHERE x.object_id=OBJECT_ID('dbo.Proveedor') AND x.name='IX_Proveedor_Nombre' AND x.is_unique=0 AND x.is_disabled=0 AND (SELECT STRING_AGG(CONVERT(NVARCHAR(MAX),c.name),N',') WITHIN GROUP(ORDER BY ic.key_ordinal) FROM sys.index_columns ic JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id WHERE ic.object_id=x.object_id AND ic.index_id=x.index_id AND ic.key_ordinal>0)=N'Nombre,ProveedorId') THROW 54001,'Indice incompatible: IX_Proveedor_Nombre',1;
 IF NOT EXISTS(SELECT 1 FROM sys.indexes x WHERE x.object_id=OBJECT_ID('dbo.Producto') AND x.name='IX_Producto_Proveedor' AND x.is_unique=0 AND x.is_disabled=0 AND (SELECT STRING_AGG(CONVERT(NVARCHAR(MAX),c.name),N',') WITHIN GROUP(ORDER BY ic.key_ordinal) FROM sys.index_columns ic JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id WHERE ic.object_id=x.object_id AND ic.index_id=x.index_id AND ic.key_ordinal>0)=N'ProveedorId,ProductoId') THROW 54001,'Indice incompatible: IX_Producto_Proveedor',1;
 IF NOT EXISTS(SELECT 1 FROM sys.indexes x WHERE x.object_id=OBJECT_ID('dbo.Producto') AND x.name='IX_Producto_Descripcion' AND x.is_unique=0 AND x.is_disabled=0 AND (SELECT STRING_AGG(CONVERT(NVARCHAR(MAX),c.name),N',') WITHIN GROUP(ORDER BY ic.key_ordinal) FROM sys.index_columns ic JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id WHERE ic.object_id=x.object_id AND ic.index_id=x.index_id AND ic.key_ordinal>0)=N'Descripcion,ProductoId') THROW 54001,'Indice incompatible: IX_Producto_Descripcion',1;
 IF NOT EXISTS(SELECT 1 FROM sys.indexes x WHERE x.object_id=OBJECT_ID('dbo.Cliente') AND x.name='IX_Cliente_Administracion' AND x.is_unique=0 AND x.is_disabled=0 AND (SELECT STRING_AGG(CONVERT(NVARCHAR(MAX),c.name),N',') WITHIN GROUP(ORDER BY ic.key_ordinal) FROM sys.index_columns ic JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id WHERE ic.object_id=x.object_id AND ic.index_id=x.index_id AND ic.key_ordinal>0)=N'Activo,Nombre,ClienteId') THROW 54001,'Indice incompatible: IX_Cliente_Administracion',1;
 IF NOT EXISTS(SELECT 1 FROM sys.computed_columns WHERE object_id=OBJECT_ID('dbo.Cliente') AND name='NITNormalizado' AND is_persisted=1 AND REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(definition),N'[',N''),N']',N''),N' ',N''),N'(',N''),N')',N''),CHAR(13),N''),CHAR(10),N'')=REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(N'CONVERT(NVARCHAR(25),UPPER(REPLACE(LTRIM(RTRIM(NIT)),N''-'',N'''')))'),N'[',N''),N']',N''),N' ',N''),N'(',N''),N')',N''),CHAR(13),N''),CHAR(10),N'')) THROW 54001,'Normalizacion incompatible: Cliente',1;
 IF NOT EXISTS(SELECT 1 FROM sys.computed_columns WHERE object_id=OBJECT_ID('dbo.Proveedor') AND name='NITNormalizado' AND is_persisted=1 AND REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(definition),N'[',N''),N']',N''),N' ',N''),N'(',N''),N')',N''),CHAR(13),N''),CHAR(10),N'')=REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(N'CONVERT(NVARCHAR(25),UPPER(REPLACE(LTRIM(RTRIM(NIT)),N''-'',N'''')))'),N'[',N''),N']',N''),N' ',N''),N'(',N''),N')',N''),CHAR(13),N''),CHAR(10),N'')) THROW 54001,'Normalizacion incompatible: Proveedor',1;
 COMMIT TRANSACTION;
END TRY
BEGIN CATCH
 IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
 THROW;
END CATCH;
GO
