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
 IF COL_LENGTH('dbo.Bitacora_Transacciones','Motivo') IS NULL
 EXEC sys.sp_executesql N'ALTER TABLE dbo.Bitacora_Transacciones ADD Motivo NVARCHAR(250) NULL;';
 EXEC sys.sp_executesql N'CREATE OR ALTER TRIGGER dbo.tr_Cliente_Auditar_Insert ON dbo.Cliente AFTER INSERT
AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.Bitacora_Transacciones(TablaAfectada,Operacion,IdentificadorRegistro,ValorAnterior,ValorNuevo,ActorUsuarioId,OperacionId,Motivo)
 SELECT N''Cliente'',''INSERT'',CONVERT(NVARCHAR(4000),i.ClienteId),j.Anterior,j.Nuevo,
 TRY_CONVERT(INT,SESSION_CONTEXT(N''ParteII.Actor'')),TRY_CONVERT(UNIQUEIDENTIFIER,SESSION_CONTEXT(N''ParteII.Operacion'')),TRY_CONVERT(NVARCHAR(250),SESSION_CONTEXT(N''ParteII.Motivo''))
 FROM inserted i
 CROSS APPLY(SELECT NULL AS Anterior,(SELECT i.ClienteId,i.NIT,i.Nombre,i.Correo,i.Telefono,i.Activo,i.FechaCreacion,i.FechaInactivacion,i.MotivoInactivacion FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER) AS Nuevo) j
 ;
END;';
 EXEC sys.sp_executesql N'CREATE OR ALTER TRIGGER dbo.tr_Cliente_Auditar_Update ON dbo.Cliente AFTER UPDATE
AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.Bitacora_Transacciones(TablaAfectada,Operacion,IdentificadorRegistro,ValorAnterior,ValorNuevo,ActorUsuarioId,OperacionId,Motivo)
 SELECT N''Cliente'',''UPDATE'',CONVERT(NVARCHAR(4000),i.ClienteId),j.Anterior,j.Nuevo,
 TRY_CONVERT(INT,SESSION_CONTEXT(N''ParteII.Actor'')),TRY_CONVERT(UNIQUEIDENTIFIER,SESSION_CONTEXT(N''ParteII.Operacion'')),TRY_CONVERT(NVARCHAR(250),SESSION_CONTEXT(N''ParteII.Motivo''))
 FROM inserted i JOIN deleted d ON d.ClienteId=i.ClienteId
 CROSS APPLY(SELECT (SELECT d.ClienteId,d.NIT,d.Nombre,d.Correo,d.Telefono,d.Activo,d.FechaCreacion,d.FechaInactivacion,d.MotivoInactivacion FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER) AS Anterior,(SELECT i.ClienteId,i.NIT,i.Nombre,i.Correo,i.Telefono,i.Activo,i.FechaCreacion,i.FechaInactivacion,i.MotivoInactivacion FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER) AS Nuevo) j
 WHERE CONVERT(VARBINARY(MAX),j.Anterior)<>CONVERT(VARBINARY(MAX),j.Nuevo);
END;';
 EXEC sys.sp_executesql N'CREATE OR ALTER TRIGGER dbo.tr_Cliente_Auditar_Delete ON dbo.Cliente AFTER DELETE
AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.Bitacora_Transacciones(TablaAfectada,Operacion,IdentificadorRegistro,ValorAnterior,ValorNuevo,ActorUsuarioId,OperacionId,Motivo)
 SELECT N''Cliente'',''DELETE'',CONVERT(NVARCHAR(4000),d.ClienteId),j.Anterior,j.Nuevo,
 TRY_CONVERT(INT,SESSION_CONTEXT(N''ParteII.Actor'')),TRY_CONVERT(UNIQUEIDENTIFIER,SESSION_CONTEXT(N''ParteII.Operacion'')),TRY_CONVERT(NVARCHAR(250),SESSION_CONTEXT(N''ParteII.Motivo''))
 FROM deleted d
 CROSS APPLY(SELECT (SELECT d.ClienteId,d.NIT,d.Nombre,d.Correo,d.Telefono,d.Activo,d.FechaCreacion,d.FechaInactivacion,d.MotivoInactivacion FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER) AS Anterior,NULL AS Nuevo) j
 ;
END;';
 EXEC sys.sp_executesql N'CREATE OR ALTER TRIGGER dbo.tr_Producto_Auditar_Insert ON dbo.Producto AFTER INSERT
AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.Bitacora_Transacciones(TablaAfectada,Operacion,IdentificadorRegistro,ValorAnterior,ValorNuevo,ActorUsuarioId,OperacionId,Motivo)
 SELECT N''Producto'',''INSERT'',CONVERT(NVARCHAR(4000),i.ProductoId),j.Anterior,j.Nuevo,
 TRY_CONVERT(INT,SESSION_CONTEXT(N''ParteII.Actor'')),TRY_CONVERT(UNIQUEIDENTIFIER,SESSION_CONTEXT(N''ParteII.Operacion'')),TRY_CONVERT(NVARCHAR(250),SESSION_CONTEXT(N''ParteII.Motivo''))
 FROM inserted i
 CROSS APPLY(SELECT NULL AS Anterior,(SELECT i.ProductoId,i.Codigo,i.Descripcion,i.Precio,i.Stock,i.Activo,i.FechaCreacion,i.ProveedorId,i.PrecioCosto,i.Fotografia,i.StockMinimo,i.PuntoReorden,i.GarantiaMeses FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER) AS Nuevo) j
 ;
END;';
 EXEC sys.sp_executesql N'CREATE OR ALTER TRIGGER dbo.tr_Producto_Auditar_Update ON dbo.Producto AFTER UPDATE
AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.Bitacora_Transacciones(TablaAfectada,Operacion,IdentificadorRegistro,ValorAnterior,ValorNuevo,ActorUsuarioId,OperacionId,Motivo)
 SELECT N''Producto'',''UPDATE'',CONVERT(NVARCHAR(4000),i.ProductoId),j.Anterior,j.Nuevo,
 TRY_CONVERT(INT,SESSION_CONTEXT(N''ParteII.Actor'')),TRY_CONVERT(UNIQUEIDENTIFIER,SESSION_CONTEXT(N''ParteII.Operacion'')),TRY_CONVERT(NVARCHAR(250),SESSION_CONTEXT(N''ParteII.Motivo''))
 FROM inserted i JOIN deleted d ON d.ProductoId=i.ProductoId
 CROSS APPLY(SELECT (SELECT d.ProductoId,d.Codigo,d.Descripcion,d.Precio,d.Stock,d.Activo,d.FechaCreacion,d.ProveedorId,d.PrecioCosto,d.Fotografia,d.StockMinimo,d.PuntoReorden,d.GarantiaMeses FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER) AS Anterior,(SELECT i.ProductoId,i.Codigo,i.Descripcion,i.Precio,i.Stock,i.Activo,i.FechaCreacion,i.ProveedorId,i.PrecioCosto,i.Fotografia,i.StockMinimo,i.PuntoReorden,i.GarantiaMeses FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER) AS Nuevo) j
 WHERE CONVERT(VARBINARY(MAX),j.Anterior)<>CONVERT(VARBINARY(MAX),j.Nuevo);
END;';
 EXEC sys.sp_executesql N'CREATE OR ALTER TRIGGER dbo.tr_Producto_Auditar_Delete ON dbo.Producto AFTER DELETE
AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.Bitacora_Transacciones(TablaAfectada,Operacion,IdentificadorRegistro,ValorAnterior,ValorNuevo,ActorUsuarioId,OperacionId,Motivo)
 SELECT N''Producto'',''DELETE'',CONVERT(NVARCHAR(4000),d.ProductoId),j.Anterior,j.Nuevo,
 TRY_CONVERT(INT,SESSION_CONTEXT(N''ParteII.Actor'')),TRY_CONVERT(UNIQUEIDENTIFIER,SESSION_CONTEXT(N''ParteII.Operacion'')),TRY_CONVERT(NVARCHAR(250),SESSION_CONTEXT(N''ParteII.Motivo''))
 FROM deleted d
 CROSS APPLY(SELECT (SELECT d.ProductoId,d.Codigo,d.Descripcion,d.Precio,d.Stock,d.Activo,d.FechaCreacion,d.ProveedorId,d.PrecioCosto,d.Fotografia,d.StockMinimo,d.PuntoReorden,d.GarantiaMeses FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER) AS Anterior,NULL AS Nuevo) j
 ;
END;';
 EXEC sys.sp_executesql N'CREATE OR ALTER TRIGGER dbo.tr_Kardex_Auditar_Insert ON dbo.Kardex_Inventario AFTER INSERT
AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.Bitacora_Transacciones(TablaAfectada,Operacion,IdentificadorRegistro,ValorAnterior,ValorNuevo,ActorUsuarioId,OperacionId,Motivo)
 SELECT N''Kardex_Inventario'',''INSERT'',CONVERT(NVARCHAR(4000),i.KardexId),NULL,
 (SELECT i.KardexId,i.ProductoId,i.TipoMovimiento,i.Cantidad,i.StockAnterior,i.StockResultante,i.DocumentoRespaldo,i.UsuarioId,i.FechaHora,i.DetalleFacturaId,i.OperacionId,i.LineaOperacion,i.Motivo FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER),i.UsuarioId,i.OperacionId,i.Motivo
 FROM inserted i;
END;';
 EXEC sys.sp_executesql N'CREATE OR ALTER TRIGGER dbo.tr_Kardex_Inmutable ON dbo.Kardex_Inventario AFTER UPDATE, DELETE
AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM deleted) THROW 54201, ''Kardex inmutable; utilice un movimiento compensatorio autorizado.'', 1;
END;';
 EXEC sys.sp_executesql N'CREATE OR ALTER TRIGGER dbo.tr_Factura_IdentidadEmision ON dbo.Factura AFTER INSERT
AS
BEGIN
 SET NOCOUNT ON;
 -- Solo filas recien emitidas. Nunca reconstruye facturas anteriores.
 UPDATE f SET ClienteNITEmision=c.NIT,ClienteNombreEmision=c.Nombre
 FROM dbo.Factura f JOIN inserted i ON i.FacturaId=f.FacturaId
 JOIN dbo.Cliente c WITH(HOLDLOCK) ON c.ClienteId=i.ClienteId;
END;';
 EXEC sys.sp_executesql N'CREATE OR ALTER TRIGGER dbo.tr_Factura_ProtegerIdentidad ON dbo.Factura AFTER UPDATE
AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM inserted i JOIN deleted d ON d.FacturaId=i.FacturaId
 WHERE EXISTS(SELECT i.ClienteId,CONVERT(VARBINARY(50),i.ClienteNITEmision),CONVERT(VARBINARY(300),i.ClienteNombreEmision) EXCEPT SELECT d.ClienteId,CONVERT(VARBINARY(50),d.ClienteNITEmision),CONVERT(VARBINARY(300),d.ClienteNombreEmision))
 AND NOT (TRIGGER_NESTLEVEL(OBJECT_ID(''dbo.tr_Factura_IdentidadEmision''),''AFTER'',''DML'')>0 AND d.ClienteNITEmision IS NULL AND d.ClienteNombreEmision IS NULL AND d.ClienteId=i.ClienteId))
 THROW 54202, ''Identidad de emision inmutable.'', 1;
END;';
 COMMIT TRANSACTION;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 THROW;
END CATCH;
GO
