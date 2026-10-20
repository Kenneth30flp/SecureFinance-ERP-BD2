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

 IF OBJECT_ID('dbo.ConfiguracionInventario','U') IS NULL
 CREATE TABLE dbo.ConfiguracionInventario (
 ConfiguracionId TINYINT CONSTRAINT PK_ConfiguracionInventario PRIMARY KEY CONSTRAINT CK_ConfiguracionInventario_Id CHECK (ConfiguracionId=1),
 Habilitado BIT NOT NULL CONSTRAINT DF_ConfiguracionInventario_Habilitado DEFAULT 0,
 FechaActivacion DATETIME2(3) NULL
 );
 IF NOT EXISTS (SELECT 1 FROM dbo.ConfiguracionInventario WHERE ConfiguracionId=1)
 INSERT dbo.ConfiguracionInventario(ConfiguracionId,Habilitado) VALUES(1,0);
 IF OBJECT_ID('dbo.Kardex_Inventario','U') IS NULL
 BEGIN
 CREATE TABLE dbo.Kardex_Inventario (
 KardexId BIGINT IDENTITY CONSTRAINT PK_Kardex_Inventario PRIMARY KEY,
 OperacionId UNIQUEIDENTIFIER NOT NULL, LineaOperacion INT NOT NULL,
 ProductoId INT NOT NULL CONSTRAINT FK_Kardex_Producto REFERENCES dbo.Producto(ProductoId),
 TipoMovimiento VARCHAR(25) NOT NULL,
 Cantidad INT NOT NULL,
 FechaHora DATETIME2(3) NOT NULL CONSTRAINT DF_Kardex_Fecha DEFAULT SYSUTCDATETIME(),
 UsuarioId INT NOT NULL CONSTRAINT FK_Kardex_Usuario REFERENCES dbo.Usuario(UsuarioId),
 DocumentoRespaldo NVARCHAR(100) NOT NULL,
 DetalleFacturaId INT NULL,
 StockAnterior INT NOT NULL, StockResultante INT NOT NULL,
 Motivo NVARCHAR(250) NOT NULL,
 CONSTRAINT UQ_Kardex_Operacion UNIQUE (OperacionId,LineaOperacion),
 CONSTRAINT CK_Kardex_Linea CHECK (LineaOperacion>0),
 CONSTRAINT CK_Kardex_Cantidad CHECK (Cantidad>0),
 CONSTRAINT CK_Kardex_Tipo CHECK (TipoMovimiento IN ('COMPRA','VENTA','AJUSTE_INGRESO','AJUSTE_EGRESO','DEVOLUCION')),
 CONSTRAINT CK_Kardex_Texto CHECK (LEN(LTRIM(RTRIM(DocumentoRespaldo)))>0 AND LEN(LTRIM(RTRIM(Motivo)))>0),
 CONSTRAINT CK_Kardex_Saldo CHECK (StockAnterior>=0 AND StockResultante>=0 AND CONVERT(BIGINT,StockResultante)=CONVERT(BIGINT,StockAnterior)+CASE WHEN TipoMovimiento IN ('VENTA','AJUSTE_EGRESO') THEN -CONVERT(BIGINT,Cantidad) ELSE CONVERT(BIGINT,Cantidad) END),
 CONSTRAINT CK_Kardex_Venta CHECK ((TipoMovimiento='VENTA' AND DetalleFacturaId IS NOT NULL) OR (TipoMovimiento<>'VENTA' AND DetalleFacturaId IS NULL))
 );
 CREATE INDEX IX_Kardex_Producto ON dbo.Kardex_Inventario(ProductoId,KardexId) INCLUDE(FechaHora,TipoMovimiento,Cantidad,StockAnterior,StockResultante);
 CREATE INDEX IX_Kardex_Fecha ON dbo.Kardex_Inventario(FechaHora,KardexId) INCLUDE(ProductoId,TipoMovimiento,Cantidad);
 CREATE UNIQUE INDEX UX_Kardex_Venta ON dbo.Kardex_Inventario(DetalleFacturaId) WHERE DetalleFacturaId IS NOT NULL;
 END;
 IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.DetalleFactura') AND name='UX_DetalleFactura_IdProducto')
 CREATE UNIQUE INDEX UX_DetalleFactura_IdProducto ON dbo.DetalleFactura(DetalleFacturaId,ProductoId);
 IF OBJECT_ID('dbo.FK_Kardex_DetalleProducto','F') IS NULL
 ALTER TABLE dbo.Kardex_Inventario WITH CHECK ADD CONSTRAINT FK_Kardex_DetalleProducto FOREIGN KEY(DetalleFacturaId,ProductoId) REFERENCES dbo.DetalleFactura(DetalleFacturaId,ProductoId);
 IF COL_LENGTH('dbo.Kardex_Inventario','StockResultante')<>4 OR COL_LENGTH('dbo.ConfiguracionInventario','Habilitado')<>1 THROW 54001, 'Estructura Kardex incompatible.', 1;


 -- Verificar definiciones propias tambien al repetir; no aceptar solo el nombre.
 IF NOT EXISTS(SELECT 1 FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_ConfiguracionInventario_Id') AND is_disabled=0 AND is_not_trusted=0) THROW 54001,'CHECK ausente o no confiable: CK_ConfiguracionInventario_Id',1;
 IF OBJECT_ID('dbo.CK_ConfiguracionInventario_Id_ValidacionEtapaII') IS NOT NULL THROW 54001,'Nombre de validacion ocupado: CK_ConfiguracionInventario_Id_ValidacionEtapaII',1;
 EXEC sys.sp_executesql N'ALTER TABLE dbo.ConfiguracionInventario WITH CHECK ADD CONSTRAINT CK_ConfiguracionInventario_Id_ValidacionEtapaII CHECK(ConfiguracionId=1);';
 IF (SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(definition),N'[',N''),N']',N''),N' ',N''),N'(',N''),N')',N''),CHAR(13),N''),CHAR(10),N'') FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_ConfiguracionInventario_Id'))<>(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(definition),N'[',N''),N']',N''),N' ',N''),N'(',N''),N')',N''),CHAR(13),N''),CHAR(10),N'') FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_ConfiguracionInventario_Id_ValidacionEtapaII')) THROW 54001,'CHECK incompatible: CK_ConfiguracionInventario_Id',1;
 EXEC sys.sp_executesql N'ALTER TABLE dbo.ConfiguracionInventario DROP CONSTRAINT CK_ConfiguracionInventario_Id_ValidacionEtapaII;';
 IF NOT EXISTS(SELECT 1 FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Kardex_Linea') AND is_disabled=0 AND is_not_trusted=0) THROW 54001,'CHECK ausente o no confiable: CK_Kardex_Linea',1;
 IF OBJECT_ID('dbo.CK_Kardex_Linea_ValidacionEtapaII') IS NOT NULL THROW 54001,'Nombre de validacion ocupado: CK_Kardex_Linea_ValidacionEtapaII',1;
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Kardex_Inventario WITH CHECK ADD CONSTRAINT CK_Kardex_Linea_ValidacionEtapaII CHECK(LineaOperacion>0);';
 IF (SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(definition),N'[',N''),N']',N''),N' ',N''),N'(',N''),N')',N''),CHAR(13),N''),CHAR(10),N'') FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Kardex_Linea'))<>(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(definition),N'[',N''),N']',N''),N' ',N''),N'(',N''),N')',N''),CHAR(13),N''),CHAR(10),N'') FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Kardex_Linea_ValidacionEtapaII')) THROW 54001,'CHECK incompatible: CK_Kardex_Linea',1;
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Kardex_Inventario DROP CONSTRAINT CK_Kardex_Linea_ValidacionEtapaII;';
 IF NOT EXISTS(SELECT 1 FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Kardex_Cantidad') AND is_disabled=0 AND is_not_trusted=0) THROW 54001,'CHECK ausente o no confiable: CK_Kardex_Cantidad',1;
 IF OBJECT_ID('dbo.CK_Kardex_Cantidad_ValidacionEtapaII') IS NOT NULL THROW 54001,'Nombre de validacion ocupado: CK_Kardex_Cantidad_ValidacionEtapaII',1;
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Kardex_Inventario WITH CHECK ADD CONSTRAINT CK_Kardex_Cantidad_ValidacionEtapaII CHECK(Cantidad>0);';
 IF (SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(definition),N'[',N''),N']',N''),N' ',N''),N'(',N''),N')',N''),CHAR(13),N''),CHAR(10),N'') FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Kardex_Cantidad'))<>(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(definition),N'[',N''),N']',N''),N' ',N''),N'(',N''),N')',N''),CHAR(13),N''),CHAR(10),N'') FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Kardex_Cantidad_ValidacionEtapaII')) THROW 54001,'CHECK incompatible: CK_Kardex_Cantidad',1;
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Kardex_Inventario DROP CONSTRAINT CK_Kardex_Cantidad_ValidacionEtapaII;';
 IF NOT EXISTS(SELECT 1 FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Kardex_Tipo') AND is_disabled=0 AND is_not_trusted=0) THROW 54001,'CHECK ausente o no confiable: CK_Kardex_Tipo',1;
 IF OBJECT_ID('dbo.CK_Kardex_Tipo_ValidacionEtapaII') IS NOT NULL THROW 54001,'Nombre de validacion ocupado: CK_Kardex_Tipo_ValidacionEtapaII',1;
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Kardex_Inventario WITH CHECK ADD CONSTRAINT CK_Kardex_Tipo_ValidacionEtapaII CHECK(TipoMovimiento IN (''COMPRA'',''VENTA'',''AJUSTE_INGRESO'',''AJUSTE_EGRESO'',''DEVOLUCION''));';
 IF (SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(definition),N'[',N''),N']',N''),N' ',N''),N'(',N''),N')',N''),CHAR(13),N''),CHAR(10),N'') FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Kardex_Tipo'))<>(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(definition),N'[',N''),N']',N''),N' ',N''),N'(',N''),N')',N''),CHAR(13),N''),CHAR(10),N'') FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Kardex_Tipo_ValidacionEtapaII')) THROW 54001,'CHECK incompatible: CK_Kardex_Tipo',1;
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Kardex_Inventario DROP CONSTRAINT CK_Kardex_Tipo_ValidacionEtapaII;';
 IF NOT EXISTS(SELECT 1 FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Kardex_Texto') AND is_disabled=0 AND is_not_trusted=0) THROW 54001,'CHECK ausente o no confiable: CK_Kardex_Texto',1;
 IF OBJECT_ID('dbo.CK_Kardex_Texto_ValidacionEtapaII') IS NOT NULL THROW 54001,'Nombre de validacion ocupado: CK_Kardex_Texto_ValidacionEtapaII',1;
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Kardex_Inventario WITH CHECK ADD CONSTRAINT CK_Kardex_Texto_ValidacionEtapaII CHECK(LEN(LTRIM(RTRIM(DocumentoRespaldo)))>0 AND LEN(LTRIM(RTRIM(Motivo)))>0);';
 IF (SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(definition),N'[',N''),N']',N''),N' ',N''),N'(',N''),N')',N''),CHAR(13),N''),CHAR(10),N'') FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Kardex_Texto'))<>(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(definition),N'[',N''),N']',N''),N' ',N''),N'(',N''),N')',N''),CHAR(13),N''),CHAR(10),N'') FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Kardex_Texto_ValidacionEtapaII')) THROW 54001,'CHECK incompatible: CK_Kardex_Texto',1;
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Kardex_Inventario DROP CONSTRAINT CK_Kardex_Texto_ValidacionEtapaII;';
 IF NOT EXISTS(SELECT 1 FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Kardex_Saldo') AND is_disabled=0 AND is_not_trusted=0) THROW 54001,'CHECK ausente o no confiable: CK_Kardex_Saldo',1;
 IF OBJECT_ID('dbo.CK_Kardex_Saldo_ValidacionEtapaII') IS NOT NULL THROW 54001,'Nombre de validacion ocupado: CK_Kardex_Saldo_ValidacionEtapaII',1;
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Kardex_Inventario WITH CHECK ADD CONSTRAINT CK_Kardex_Saldo_ValidacionEtapaII CHECK(StockAnterior>=0 AND StockResultante>=0 AND CONVERT(BIGINT,StockResultante)=CONVERT(BIGINT,StockAnterior)+CASE WHEN TipoMovimiento IN (''VENTA'',''AJUSTE_EGRESO'') THEN -CONVERT(BIGINT,Cantidad) ELSE CONVERT(BIGINT,Cantidad) END);';
 IF (SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(definition),N'[',N''),N']',N''),N' ',N''),N'(',N''),N')',N''),CHAR(13),N''),CHAR(10),N'') FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Kardex_Saldo'))<>(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(definition),N'[',N''),N']',N''),N' ',N''),N'(',N''),N')',N''),CHAR(13),N''),CHAR(10),N'') FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Kardex_Saldo_ValidacionEtapaII')) THROW 54001,'CHECK incompatible: CK_Kardex_Saldo',1;
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Kardex_Inventario DROP CONSTRAINT CK_Kardex_Saldo_ValidacionEtapaII;';
 IF NOT EXISTS(SELECT 1 FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Kardex_Venta') AND is_disabled=0 AND is_not_trusted=0) THROW 54001,'CHECK ausente o no confiable: CK_Kardex_Venta',1;
 IF OBJECT_ID('dbo.CK_Kardex_Venta_ValidacionEtapaII') IS NOT NULL THROW 54001,'Nombre de validacion ocupado: CK_Kardex_Venta_ValidacionEtapaII',1;
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Kardex_Inventario WITH CHECK ADD CONSTRAINT CK_Kardex_Venta_ValidacionEtapaII CHECK((TipoMovimiento=''VENTA'' AND DetalleFacturaId IS NOT NULL) OR (TipoMovimiento<>''VENTA'' AND DetalleFacturaId IS NULL));';
 IF (SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(definition),N'[',N''),N']',N''),N' ',N''),N'(',N''),N')',N''),CHAR(13),N''),CHAR(10),N'') FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Kardex_Venta'))<>(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(definition),N'[',N''),N']',N''),N' ',N''),N'(',N''),N')',N''),CHAR(13),N''),CHAR(10),N'') FROM sys.check_constraints WHERE object_id=OBJECT_ID('dbo.CK_Kardex_Venta_ValidacionEtapaII')) THROW 54001,'CHECK incompatible: CK_Kardex_Venta',1;
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Kardex_Inventario DROP CONSTRAINT CK_Kardex_Venta_ValidacionEtapaII;';
 IF NOT EXISTS(SELECT 1 FROM sys.indexes x WHERE x.object_id=OBJECT_ID('dbo.Kardex_Inventario') AND x.name='UQ_Kardex_Operacion' AND x.is_unique=1 AND x.is_disabled=0 AND (SELECT STRING_AGG(CONVERT(NVARCHAR(MAX),c.name),N',') WITHIN GROUP(ORDER BY ic.key_ordinal) FROM sys.index_columns ic JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id WHERE ic.object_id=x.object_id AND ic.index_id=x.index_id AND ic.key_ordinal>0)=N'OperacionId,LineaOperacion') THROW 54001,'Indice incompatible: UQ_Kardex_Operacion',1;
 IF NOT EXISTS(SELECT 1 FROM sys.indexes x WHERE x.object_id=OBJECT_ID('dbo.Kardex_Inventario') AND x.name='IX_Kardex_Producto' AND x.is_unique=0 AND x.is_disabled=0 AND (SELECT STRING_AGG(CONVERT(NVARCHAR(MAX),c.name),N',') WITHIN GROUP(ORDER BY ic.key_ordinal) FROM sys.index_columns ic JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id WHERE ic.object_id=x.object_id AND ic.index_id=x.index_id AND ic.key_ordinal>0)=N'ProductoId,KardexId') THROW 54001,'Indice incompatible: IX_Kardex_Producto',1;
 IF NOT EXISTS(SELECT 1 FROM sys.indexes x WHERE x.object_id=OBJECT_ID('dbo.Kardex_Inventario') AND x.name='IX_Kardex_Fecha' AND x.is_unique=0 AND x.is_disabled=0 AND (SELECT STRING_AGG(CONVERT(NVARCHAR(MAX),c.name),N',') WITHIN GROUP(ORDER BY ic.key_ordinal) FROM sys.index_columns ic JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id WHERE ic.object_id=x.object_id AND ic.index_id=x.index_id AND ic.key_ordinal>0)=N'FechaHora,KardexId') THROW 54001,'Indice incompatible: IX_Kardex_Fecha',1;
 IF NOT EXISTS(SELECT 1 FROM sys.indexes x WHERE x.object_id=OBJECT_ID('dbo.Kardex_Inventario') AND x.name='UX_Kardex_Venta' AND x.is_unique=1 AND x.is_disabled=0 AND (SELECT STRING_AGG(CONVERT(NVARCHAR(MAX),c.name),N',') WITHIN GROUP(ORDER BY ic.key_ordinal) FROM sys.index_columns ic JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id WHERE ic.object_id=x.object_id AND ic.index_id=x.index_id AND ic.key_ordinal>0)=N'DetalleFacturaId') THROW 54001,'Indice incompatible: UX_Kardex_Venta',1;
 IF NOT EXISTS(SELECT 1 FROM sys.indexes x WHERE x.object_id=OBJECT_ID('dbo.DetalleFactura') AND x.name='UX_DetalleFactura_IdProducto' AND x.is_unique=1 AND x.is_disabled=0 AND (SELECT STRING_AGG(CONVERT(NVARCHAR(MAX),c.name),N',') WITHIN GROUP(ORDER BY ic.key_ordinal) FROM sys.index_columns ic JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id WHERE ic.object_id=x.object_id AND ic.index_id=x.index_id AND ic.key_ordinal>0)=N'DetalleFacturaId,ProductoId') THROW 54001,'Indice incompatible: UX_DetalleFactura_IdProducto',1;
 IF NOT EXISTS(SELECT 1 FROM sys.foreign_keys WHERE object_id=OBJECT_ID('dbo.FK_Kardex_DetalleProducto') AND referenced_object_id=OBJECT_ID('dbo.DetalleFactura') AND is_disabled=0 AND is_not_trusted=0 AND delete_referential_action=0 AND update_referential_action=0) THROW 54001,'FK de detalle incompatible.',1;
 IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.Kardex_Inventario') AND name='UX_Kardex_Venta' AND has_filter=1 AND REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(filter_definition),N'[',N''),N']',N''),N' ',N''),N'(',N''),N')',N''),CHAR(13),N''),CHAR(10),N'')=REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(N'DetalleFacturaId IS NOT NULL'),N'[',N''),N']',N''),N' ',N''),N'(',N''),N')',N''),CHAR(13),N''),CHAR(10),N'')) THROW 54001,'Filtro de venta incompatible.',1;

 -- Forma y referencias del libro: abortar si un objeto previo tiene otro contrato.
 IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Kardex_Inventario') AND name='KardexId' AND TYPE_NAME(system_type_id)='bigint' AND max_length=8 AND is_nullable=0) THROW 54001,'Columna Kardex incompatible: KardexId',1;
 IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Kardex_Inventario') AND name='OperacionId' AND TYPE_NAME(system_type_id)='uniqueidentifier' AND max_length=16 AND is_nullable=0) THROW 54001,'Columna Kardex incompatible: OperacionId',1;
 IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Kardex_Inventario') AND name='LineaOperacion' AND TYPE_NAME(system_type_id)='int' AND max_length=4 AND is_nullable=0) THROW 54001,'Columna Kardex incompatible: LineaOperacion',1;
 IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Kardex_Inventario') AND name='ProductoId' AND TYPE_NAME(system_type_id)='int' AND max_length=4 AND is_nullable=0) THROW 54001,'Columna Kardex incompatible: ProductoId',1;
 IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Kardex_Inventario') AND name='TipoMovimiento' AND TYPE_NAME(system_type_id)='varchar' AND max_length=25 AND is_nullable=0) THROW 54001,'Columna Kardex incompatible: TipoMovimiento',1;
 IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Kardex_Inventario') AND name='Cantidad' AND TYPE_NAME(system_type_id)='int' AND max_length=4 AND is_nullable=0) THROW 54001,'Columna Kardex incompatible: Cantidad',1;
 IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Kardex_Inventario') AND name='UsuarioId' AND TYPE_NAME(system_type_id)='int' AND max_length=4 AND is_nullable=0) THROW 54001,'Columna Kardex incompatible: UsuarioId',1;
 IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Kardex_Inventario') AND name='DocumentoRespaldo' AND TYPE_NAME(system_type_id)='nvarchar' AND max_length=200 AND is_nullable=0) THROW 54001,'Columna Kardex incompatible: DocumentoRespaldo',1;
 IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Kardex_Inventario') AND name='DetalleFacturaId' AND TYPE_NAME(system_type_id)='int' AND max_length=4 AND is_nullable=1) THROW 54001,'Columna Kardex incompatible: DetalleFacturaId',1;
 IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Kardex_Inventario') AND name='StockAnterior' AND TYPE_NAME(system_type_id)='int' AND max_length=4 AND is_nullable=0) THROW 54001,'Columna Kardex incompatible: StockAnterior',1;
 IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Kardex_Inventario') AND name='StockResultante' AND TYPE_NAME(system_type_id)='int' AND max_length=4 AND is_nullable=0) THROW 54001,'Columna Kardex incompatible: StockResultante',1;
 IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Kardex_Inventario') AND name='Motivo' AND TYPE_NAME(system_type_id)='nvarchar' AND max_length=500 AND is_nullable=0) THROW 54001,'Columna Kardex incompatible: Motivo',1;
 IF NOT EXISTS(SELECT 1 FROM sys.foreign_keys f JOIN sys.foreign_key_columns fc ON fc.constraint_object_id=f.object_id WHERE f.object_id=OBJECT_ID('dbo.FK_Kardex_Producto') AND f.parent_object_id=OBJECT_ID('dbo.Kardex_Inventario') AND f.referenced_object_id=OBJECT_ID('dbo.Producto') AND fc.parent_column_id=COLUMNPROPERTY(f.parent_object_id,'ProductoId','ColumnId') AND fc.referenced_column_id=COLUMNPROPERTY(f.referenced_object_id,'ProductoId','ColumnId') AND f.is_disabled=0 AND f.is_not_trusted=0 AND f.delete_referential_action=0 AND f.update_referential_action=0) THROW 54001,'FK incompatible: FK_Kardex_Producto',1;
 IF NOT EXISTS(SELECT 1 FROM sys.foreign_keys f JOIN sys.foreign_key_columns fc ON fc.constraint_object_id=f.object_id WHERE f.object_id=OBJECT_ID('dbo.FK_Kardex_Usuario') AND f.parent_object_id=OBJECT_ID('dbo.Kardex_Inventario') AND f.referenced_object_id=OBJECT_ID('dbo.Usuario') AND fc.parent_column_id=COLUMNPROPERTY(f.parent_object_id,'UsuarioId','ColumnId') AND fc.referenced_column_id=COLUMNPROPERTY(f.referenced_object_id,'UsuarioId','ColumnId') AND f.is_disabled=0 AND f.is_not_trusted=0 AND f.delete_referential_action=0 AND f.update_referential_action=0) THROW 54001,'FK incompatible: FK_Kardex_Usuario',1;
 IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Kardex_Inventario') AND name='KardexId' AND is_identity=1) THROW 54001,'KardexId debe ser IDENTITY.',1;
 IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Kardex_Inventario') AND name='FechaHora' AND TYPE_NAME(system_type_id)='datetime2' AND scale=3 AND is_nullable=0) THROW 54001,'Fecha Kardex incompatible.',1;
 IF (SELECT COUNT(*) FROM sys.foreign_key_columns WHERE constraint_object_id=OBJECT_ID('dbo.FK_Kardex_DetalleProducto'))<>2 THROW 54001,'FK compuesta incompleta.',1;
 IF NOT EXISTS(SELECT 1 FROM sys.foreign_key_columns WHERE constraint_object_id=OBJECT_ID('dbo.FK_Kardex_DetalleProducto') AND parent_column_id=COLUMNPROPERTY(OBJECT_ID('dbo.Kardex_Inventario'),'ProductoId','ColumnId') AND referenced_column_id=COLUMNPROPERTY(OBJECT_ID('dbo.DetalleFactura'),'ProductoId','ColumnId')) THROW 54001,'Producto de detalle incompatible.',1;
 COMMIT TRANSACTION;
END TRY
BEGIN CATCH
 IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
 THROW;
END CATCH;
GO
