-- Incremental UI/catalog completion after reviewing the supplied Kenneth prompt.
SET XACT_ABORT ON; SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON;
IF DB_NAME() COLLATE Latin1_General_100_BIN2<>N'SecureFinanceERP_Lab_Dylan' OR DATALENGTH(DB_NAME())<>DATALENGTH(N'SecureFinanceERP_Lab_Dylan') OR @@TRANCOUNT<>1 OR XACT_STATE()<>1
 THROW 58000,'Solo laboratorio y transaccion externa.',1;
IF COL_LENGTH('dbo.P3_BOD_Bodega','Codigo') IS NULL
BEGIN
 ALTER TABLE dbo.P3_BOD_Bodega ADD Codigo nvarchar(40) NOT NULL
  CONSTRAINT P3_BOD_DF_Codigo DEFAULT(N'BOD-'+REPLACE(CONVERT(nvarchar(36),NEWID()),N'-',N'')) WITH VALUES;
 CREATE UNIQUE INDEX P3_BOD_UQ_Codigo ON dbo.P3_BOD_Bodega(Codigo);
END;
IF COL_LENGTH('dbo.P3_BOD_Bodega','Direccion') IS NULL ALTER TABLE dbo.P3_BOD_Bodega ADD Direccion nvarchar(250) NULL;
IF COL_LENGTH('dbo.P3_BOD_Bodega','Responsable') IS NULL ALTER TABLE dbo.P3_BOD_Bodega ADD Responsable nvarchar(150) NULL;
GO
CREATE OR ALTER PROCEDURE dbo.P3_BOD_GuardarBodega
 @ActorUsuarioId INT,@OperacionId UNIQUEIDENTIFIER,@Nombre NVARCHAR(100),@Activo BIT,@IsCentral BIT,
 @Motivo NVARCHAR(250),@BodegaId INT=NULL,@VersionEsperada BINARY(8)=NULL,
 @Codigo NVARCHAR(MAX)=NULL,@Direccion NVARCHAR(MAX)=NULL,@Responsable NVARCHAR(MAX)=NULL
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 SET ANSI_PADDING ON; SET ANSI_WARNINGS ON; SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET NUMERIC_ROUNDABORT OFF;
 DECLARE @Propia bit=CASE WHEN @@TRANCOUNT=0 THEN 1 ELSE 0 END;
 BEGIN TRY
  IF @Propia=1 BEGIN TRANSACTION;
  EXEC dbo.P3_BOD_Autorizar @ActorUsuarioId,N'BODEGAS_ADMINISTRAR';
  SET @Codigo=NULLIF(UPPER(LTRIM(RTRIM(@Codigo))),N'');
  IF @Activo IS NULL OR @IsCentral IS NULL OR (@IsCentral=1 AND @Activo=0)
   OR NULLIF(LTRIM(RTRIM(@Nombre)),N'') IS NULL OR NULLIF(LTRIM(RTRIM(@Motivo)),N'') IS NULL
   OR (@BodegaId IS NOT NULL AND @VersionEsperada IS NULL)
   OR DATALENGTH(@Codigo)>80 OR DATALENGTH(@Direccion)>500 OR DATALENGTH(@Responsable)>300
   OR (@Codigo IS NOT NULL AND @Codigo COLLATE Latin1_General_100_BIN2 LIKE N'%[^-A-Z0-9_]%')
   THROW 58002,'Datos de bodega invalidos.',1;
  DECLARE @Carga nvarchar(max),@Respuesta nvarchar(max),@N bigint;
  IF @Codigo IS NULL AND @Direccion IS NULL AND @Responsable IS NULL
   SET @Carga=(SELECT N'BODEGA' Accion,@BodegaId BodegaId,@Nombre Nombre,@Activo Activo,@IsCentral IsCentral,CONVERT(varchar(16),@VersionEsperada,2) Version,@Motivo Motivo FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER);
  ELSE
   SET @Carga=(SELECT N'BODEGA_V2' Accion,@BodegaId BodegaId,@Nombre Nombre,@Activo Activo,@IsCentral IsCentral,CONVERT(varchar(16),@VersionEsperada,2) Version,@Motivo Motivo,@Codigo Codigo,@Direccion Direccion,@Responsable Responsable FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER);
  EXEC dbo.P3_BOD_Reintento @ActorUsuarioId,@OperacionId,@Carga,@Respuesta OUTPUT;
  IF @Respuesta IS NULL
  BEGIN
   SELECT @N=COUNT_BIG(*) FROM dbo.Producto WITH(TABLOCKX,HOLDLOCK);
   IF @BodegaId IS NOT NULL AND NOT EXISTS(SELECT 1 FROM dbo.P3_BOD_Bodega WITH(UPDLOCK,HOLDLOCK) WHERE BodegaId=@BodegaId AND Version=@VersionEsperada) THROW 58003,'Version obsoleta.',1;
   IF @Activo=0 AND (EXISTS(SELECT 1 FROM dbo.P3_BOD_Stock WITH(HOLDLOCK) WHERE BodegaId=@BodegaId AND Cantidad>0) OR EXISTS(SELECT 1 FROM dbo.P3_BOD_Transferencia WITH(HOLDLOCK) WHERE (OrigenId=@BodegaId OR DestinoId=@BodegaId) AND Estado IN('PREPARADA','DESPACHADA'))) THROW 58005,'Bodega con stock o transferencias pendientes.',1;
   IF @IsCentral=0 AND EXISTS(SELECT 1 FROM dbo.P3_BOD_Bodega WHERE BodegaId=@BodegaId AND IsCentral=1) THROW 58002,'Asigne otra central activa primero.',1;
   IF EXISTS(SELECT 1 FROM dbo.P3_BOD_Bodega WHERE (Nombre=@Nombre OR (@Codigo IS NOT NULL AND Codigo=@Codigo)) AND (@BodegaId IS NULL OR BodegaId<>@BodegaId)) THROW 58003,'Nombre o codigo utilizado.',1;
   IF @IsCentral=1 UPDATE dbo.P3_BOD_Bodega SET IsCentral=0 WHERE IsCentral=1;
   IF @BodegaId IS NULL
   BEGIN
    IF @Codigo IS NULL SET @Codigo=N'BOD-'+REPLACE(CONVERT(nvarchar(36),NEWID()),N'-',N'');
    INSERT dbo.P3_BOD_Bodega(Nombre,Activo,IsCentral,Codigo,Direccion,Responsable)
    VALUES(@Nombre,@Activo,@IsCentral,@Codigo,NULLIF(@Direccion,N''),NULLIF(@Responsable,N''));
    SET @BodegaId=CONVERT(int,SCOPE_IDENTITY());
   END
   ELSE UPDATE dbo.P3_BOD_Bodega SET Nombre=@Nombre,Activo=@Activo,IsCentral=@IsCentral,
    Codigo=COALESCE(@Codigo,Codigo),Direccion=CASE WHEN @Direccion IS NULL THEN Direccion ELSE NULLIF(@Direccion,N'') END,
    Responsable=CASE WHEN @Responsable IS NULL THEN Responsable ELSE NULLIF(@Responsable,N'') END WHERE BodegaId=@BodegaId;
   IF @IsCentral=1 UPDATE dbo.P3_BOD_Configuracion SET CentralId=@BodegaId WHERE ConfiguracionId=1;
   SET @Respuesta=(SELECT BodegaId,Nombre,Codigo,Direccion,Responsable,Activo,IsCentral,CONVERT(varchar(16),CONVERT(binary(8),Version),2) Version,@OperacionId OperacionId FROM dbo.P3_BOD_Bodega WHERE BodegaId=@BodegaId FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
   INSERT dbo.P3_BOD_Operacion(OperacionId,ActorUsuarioId,Carga,Respuesta) VALUES(@OperacionId,@ActorUsuarioId,@Carga,@Respuesta);
   INSERT dbo.Bitacora_Transacciones(TablaAfectada,Operacion,IdentificadorRegistro,ValorNuevo,ActorUsuarioId,OperacionId,Motivo)
   VALUES(N'P3_BOD_Bodega',CASE WHEN @VersionEsperada IS NULL THEN 'INSERT' ELSE 'UPDATE' END,CONVERT(nvarchar(20),@BodegaId),@Respuesta,@ActorUsuarioId,@OperacionId,@Motivo);
  END;
  IF @Propia=1 COMMIT;
  SELECT @Respuesta Respuesta;
 END TRY BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK; THROW; END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.P3_BOD_Consultar
 @ActorUsuarioId INT,@Seccion varchar(15),@BodegaId INT=NULL,@ProductoId INT=NULL,
 @TransferenciaId INT=NULL,@Desplazamiento INT=0,@Desde datetime2(3)=NULL,@Hasta datetime2(3)=NULL,
 @Buscar nvarchar(128)=NULL,@Estado varchar(12)=NULL
AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.P3_BOD_Autorizar @ActorUsuarioId,N'BODEGAS_CONSULTAR';
 IF @Seccion IS NULL OR @Seccion NOT IN('bodegas','inventario','transferencias','kardex','detalle') OR @Desplazamiento IS NULL OR @Desplazamiento<0 OR @Desplazamiento>2000000 OR @BodegaId<=0 OR @ProductoId<=0 OR @Desde>=@Hasta
  OR (@Seccion='detalle' AND (@TransferenciaId IS NULL OR @TransferenciaId<=0))
  OR (@Estado IS NOT NULL AND @Estado NOT IN('PREPARADA','DESPACHADA','RECIBIDA')) THROW 58002,'Filtros invalidos.',1;
 IF @Seccion='bodegas'
 BEGIN
  SELECT b.BodegaId,b.Nombre,b.Codigo,b.Direccion,b.Responsable,b.Activo,b.IsCentral,CONVERT(varchar(16),CONVERT(binary(8),b.Version),2) Version,COALESCE(s.Stock,0) Stock
  FROM dbo.P3_BOD_Bodega b OUTER APPLY(SELECT SUM(CONVERT(bigint,Cantidad)) Stock FROM dbo.P3_BOD_Stock WHERE BodegaId=b.BodegaId) s
  WHERE (@BodegaId IS NULL OR b.BodegaId=@BodegaId) AND (@Buscar IS NULL OR CHARINDEX(@Buscar,b.Codigo)>0 OR CHARINDEX(@Buscar,b.Nombre)>0)
  ORDER BY b.BodegaId OFFSET @Desplazamiento ROWS FETCH NEXT 21 ROWS ONLY;
  RETURN;
 END;
 IF @Seccion='inventario'
 BEGIN
  SELECT c.*,s.Cantidad ExistenciaBodega FROM dbo.P3_BOD_Conciliacion c LEFT JOIN dbo.P3_BOD_Stock s ON s.ProductoId=c.ProductoId AND s.BodegaId=@BodegaId
  WHERE (@ProductoId IS NULL OR c.ProductoId=@ProductoId) AND (@Buscar IS NULL OR CHARINDEX(@Buscar,c.Codigo)>0 OR CHARINDEX(@Buscar,c.Descripcion)>0)
  ORDER BY c.ProductoId OFFSET @Desplazamiento ROWS FETCH NEXT 21 ROWS ONLY;
  SELECT COALESCE(SUM(CONVERT(bigint,c.Stock)),0) StockGlobal,COALESCE(SUM(c.StockLocal),0) StockLocal,COALESCE(SUM(c.Transito),0) Transito,
   COALESCE(SUM(CASE WHEN c.Diferencia<>0 THEN CONVERT(bigint,1) ELSE CONVERT(bigint,0) END),0) Descuadres
  FROM dbo.P3_BOD_Conciliacion c WHERE (@ProductoId IS NULL OR c.ProductoId=@ProductoId)
   AND (@Buscar IS NULL OR CHARINDEX(@Buscar,c.Codigo)>0 OR CHARINDEX(@Buscar,c.Descripcion)>0);
  RETURN;
 END;
 IF @Seccion IN('transferencias','detalle')
 BEGIN
  SELECT t.TransferenciaId,t.ProductoId,p.Codigo,p.Descripcion,t.OrigenId,o.Nombre Origen,t.DestinoId,d.Nombre Destino,t.Cantidad,t.Estado,t.Motivo,t.ActorUsuarioId,t.FechaHora,
   CONVERT(varchar(16),CONVERT(binary(8),t.Version),2) Version
  FROM dbo.P3_BOD_Transferencia t JOIN dbo.P3_BOD_Bodega o ON o.BodegaId=t.OrigenId JOIN dbo.P3_BOD_Bodega d ON d.BodegaId=t.DestinoId JOIN dbo.Producto p ON p.ProductoId=t.ProductoId
  WHERE (@ProductoId IS NULL OR t.ProductoId=@ProductoId) AND (@BodegaId IS NULL OR t.OrigenId=@BodegaId OR t.DestinoId=@BodegaId)
   AND (@TransferenciaId IS NULL OR t.TransferenciaId=@TransferenciaId) AND (@Desde IS NULL OR t.FechaHora>=@Desde) AND (@Hasta IS NULL OR t.FechaHora<@Hasta)
   AND (@Buscar IS NULL OR CHARINDEX(@Buscar,p.Codigo)>0 OR CHARINDEX(@Buscar,p.Descripcion)>0) AND (@Estado IS NULL OR t.Estado=@Estado)
  ORDER BY t.TransferenciaId DESC OFFSET @Desplazamiento ROWS FETCH NEXT 21 ROWS ONLY;
  IF @Seccion='detalle' SELECT l.*,u.NombreUsuario Actor,b.Nombre Bodega FROM dbo.P3_BOD_Ledger l JOIN dbo.Usuario u ON u.UsuarioId=l.ActorUsuarioId JOIN dbo.P3_BOD_Bodega b ON b.BodegaId=l.BodegaId WHERE l.TransferenciaId=@TransferenciaId ORDER BY l.MovimientoId;
  RETURN;
 END;
 SELECT l.*,u.NombreUsuario Actor,b.Nombre Bodega,p.Codigo FROM dbo.P3_BOD_Ledger l JOIN dbo.Usuario u ON u.UsuarioId=l.ActorUsuarioId JOIN dbo.P3_BOD_Bodega b ON b.BodegaId=l.BodegaId JOIN dbo.Producto p ON p.ProductoId=l.ProductoId
 WHERE (@ProductoId IS NULL OR l.ProductoId=@ProductoId) AND (@BodegaId IS NULL OR l.BodegaId=@BodegaId) AND (@Desde IS NULL OR l.FechaHora>=@Desde) AND (@Hasta IS NULL OR l.FechaHora<@Hasta)
  AND (@Buscar IS NULL OR CHARINDEX(@Buscar,p.Codigo)>0)
 ORDER BY l.MovimientoId DESC OFFSET @Desplazamiento ROWS FETCH NEXT 21 ROWS ONLY;
END;
GO
