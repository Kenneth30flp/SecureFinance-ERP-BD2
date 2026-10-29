SET XACT_ABORT ON;
IF @@TRANCOUNT=0 THROW 55000,'Instalador transaccional requerido.',1;
IF OBJECT_ID('dbo.P3_COM_BuscarCatalogo','P') IS NULL THROW 55000,'Requiere 54.',1;
-- Aplicar a todas las tablas propias las mismas protecciones de columna de 50.
DECLARE @Tabla SYSNAME,@Columnas NVARCHAR(MAX),@Sql NVARCHAR(MAX);
DECLARE objetos CURSOR LOCAL FAST_FORWARD FOR SELECT t.name,STRING_AGG(CONVERT(NVARCHAR(MAX),QUOTENAME(c.name)),N',')
 FROM sys.tables t JOIN sys.columns c ON c.object_id=t.object_id WHERE t.schema_id=SCHEMA_ID('dbo') AND t.name LIKE 'P3[_]COM[_]%' GROUP BY t.name;
OPEN objetos; FETCH NEXT FROM objetos INTO @Tabla,@Columnas;
WHILE @@FETCH_STATUS=0
BEGIN
 SET @Sql=N'DENY SELECT,INSERT,UPDATE,DELETE,ALTER,TAKE OWNERSHIP ON OBJECT::dbo.'+QUOTENAME(@Tabla)+N' TO securefinance_app; DENY SELECT,UPDATE ON OBJECT::dbo.'+QUOTENAME(@Tabla)+N' ('+@Columnas+N') TO securefinance_app;';
 EXEC sys.sp_executesql @Sql;
 FETCH NEXT FROM objetos INTO @Tabla,@Columnas;
END;
CLOSE objetos; DEALLOCATE objetos;
GO
