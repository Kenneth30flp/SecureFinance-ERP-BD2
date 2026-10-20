-- Consultas para los espacios operativos. No habilita Kardex ni cambia datos.
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
IF DB_NAME() IN ('master','model','msdb','tempdb') THROW 54500,'Seleccione la base de aplicacion.',1;
IF OBJECT_ID('dbo.sp_HabilitarKardexInventario','P') IS NULL THROW 54500,'Requiere migracion 21.',1;
BEGIN TRY
 BEGIN TRANSACTION;
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.sp_ConsultarEstadoInventario @ActorUsuarioId INT AS
 BEGIN
 SET NOCOUNT ON;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N''INVENTARIO_CONSULTAR'';
 SELECT Habilitado,IntegracionVersion,FechaActivacion FROM dbo.ConfiguracionInventario WHERE ConfiguracionId=1;
 END;';
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.sp_ConsultarProductosWeb @ActorUsuarioId INT,@Buscar NVARCHAR(150)=N'''',@Id INT=NULL,@Desplazamiento INT=0,@Inventario BIT=0,@IncluirCosto BIT=0 AS
 BEGIN
 SET NOCOUNT ON;
 DECLARE @Permiso NVARCHAR(100)=CASE WHEN @Inventario=1 THEN N''INVENTARIO_CONSULTAR'' ELSE N''PRODUCTOS_CONSULTAR'' END;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,@Permiso;
 IF @IncluirCosto=1 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N''PRODUCTOS_ADMINISTRAR'';
 IF @Inventario IS NULL OR @IncluirCosto IS NULL OR @Buscar IS NULL OR @Desplazamiento IS NULL OR @Desplazamiento<0 THROW 54102,''Filtros invalidos.'',1;
 SELECT p.ProductoId,p.Codigo,p.Descripcion,p.Precio,CASE WHEN @IncluirCosto=1 THEN p.PrecioCosto END PrecioCosto,p.Stock,p.ProveedorId,v.Nombre Proveedor,p.Fotografia,p.StockMinimo,p.PuntoReorden,p.GarantiaMeses,p.Activo,p.FechaCreacion,p.Version
 FROM dbo.Producto p LEFT JOIN dbo.Proveedor v ON v.ProveedorId=p.ProveedorId
 WHERE (@Id IS NULL OR p.ProductoId=@Id) AND (@Buscar=N'''' OR CHARINDEX(@Buscar,p.Codigo)>0 OR CHARINDEX(@Buscar,p.Descripcion)>0)
 ORDER BY p.Descripcion,p.ProductoId OFFSET @Desplazamiento ROWS FETCH NEXT 51 ROWS ONLY;
 END;';
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.sp_ConsultarProveedoresWeb @ActorUsuarioId INT,@Buscar NVARCHAR(150)=N'''',@Id INT=NULL,@Desplazamiento INT=0 AS
 BEGIN
 SET NOCOUNT ON;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N''PROVEEDORES_CONSULTAR'';
 IF @Buscar IS NULL OR @Desplazamiento IS NULL OR @Desplazamiento<0 THROW 54102,''Filtros invalidos.'',1;
 SELECT ProveedorId,NIT,Nombre,Correo,Telefono,Direccion,Fotografia,Activo,FechaCreacion,Version FROM dbo.Proveedor
 WHERE (@Id IS NULL OR ProveedorId=@Id) AND (@Buscar=N'''' OR CHARINDEX(@Buscar,Nombre)>0 OR CHARINDEX(@Buscar,NIT)>0)
 ORDER BY Nombre,ProveedorId OFFSET @Desplazamiento ROWS FETCH NEXT 51 ROWS ONLY;
 END;';
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.sp_ConsultarClientesWeb @ActorUsuarioId INT,@Buscar NVARCHAR(150)=N'''',@Id INT=NULL,@Desplazamiento INT=0 AS
 BEGIN
 SET NOCOUNT ON;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N''CLIENTES_CONSULTAR'';
 IF @Buscar IS NULL OR @Desplazamiento IS NULL OR @Desplazamiento<0 THROW 54102,''Filtros invalidos.'',1;
 SELECT ClienteId,NIT,Nombre,Correo,Telefono,Activo,FechaCreacion,FechaInactivacion,MotivoInactivacion,Version FROM dbo.Cliente
 WHERE (@Id IS NULL OR ClienteId=@Id) AND (@Buscar=N'''' OR CHARINDEX(@Buscar,Nombre)>0 OR CHARINDEX(@Buscar,NIT)>0)
 ORDER BY Nombre,ClienteId OFFSET @Desplazamiento ROWS FETCH NEXT 51 ROWS ONLY;
 END;';
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.sp_ConsultarKardexWeb @ActorUsuarioId INT,@ProductoId INT,@Desde DATETIME2(3)=NULL,@Hasta DATETIME2(3)=NULL,@Desplazamiento INT=0 AS
 BEGIN
 SET NOCOUNT ON;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N''INVENTARIO_CONSULTAR'';
 IF @ProductoId IS NULL OR @ProductoId<1 OR @Desplazamiento IS NULL OR @Desplazamiento<0 OR @Desde>=@Hasta THROW 54102,''Filtros invalidos.'',1;
 SELECT k.KardexId,k.ProductoId,k.TipoMovimiento,k.Cantidad,k.FechaHora,k.UsuarioId,u.NombreUsuario Actor,k.DocumentoRespaldo,k.StockAnterior,k.StockResultante,k.Motivo
 FROM dbo.Kardex_Inventario k JOIN dbo.Usuario u ON u.UsuarioId=k.UsuarioId
 WHERE k.ProductoId=@ProductoId AND (@Desde IS NULL OR k.FechaHora>=@Desde) AND (@Hasta IS NULL OR k.FechaHora<@Hasta)
 ORDER BY k.FechaHora DESC,k.KardexId DESC OFFSET @Desplazamiento ROWS FETCH NEXT 51 ROWS ONLY;
 END;';
 GRANT EXECUTE ON OBJECT::dbo.sp_ConsultarEstadoInventario TO securefinance_app;
 GRANT EXECUTE ON OBJECT::dbo.sp_ConsultarProductosWeb TO securefinance_app;
 GRANT EXECUTE ON OBJECT::dbo.sp_ConsultarProveedoresWeb TO securefinance_app;
 GRANT EXECUTE ON OBJECT::dbo.sp_ConsultarClientesWeb TO securefinance_app;
 GRANT EXECUTE ON OBJECT::dbo.sp_ConsultarKardexWeb TO securefinance_app;
 COMMIT TRANSACTION;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 THROW;
END CATCH;
GO
