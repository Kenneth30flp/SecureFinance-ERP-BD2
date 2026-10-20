-- Cobertura adicional; no sustituye ni reduce los 28 casos originales.
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
SET XACT_ABORT ON;
IF LEFT(DB_NAME(),LEN(N'SecureFinanceERP_ParteII_Test_'))<>N'SecureFinanceERP_ParteII_Test_'
 THROW 54900,'Solo base aislada de pruebas.',1;
DECLARE @CasoExtra INT=1,@EsperadoExtra INT,@ErrorExtra INT,@ActorExtra INT,@RolExtra INT,@ProveedorExtra INT,@ProductoExtra INT,@ClienteExtra INT,
 @EtiquetaExtra NVARCHAR(32),@OperacionExtra UNIQUEIDENTIFIER,@AperturaExtra UNIQUEIDENTIFIER;
DECLARE @LecturaKardex TABLE(KardexId BIGINT,OperacionId UNIQUEIDENTIFIER,LineaOperacion INT,ProductoId INT,TipoMovimiento VARCHAR(25),Cantidad INT,FechaHora DATETIME2(3),UsuarioId INT,DocumentoRespaldo NVARCHAR(100),DetalleFacturaId INT,StockAnterior INT,StockResultante INT,Motivo NVARCHAR(250));
DECLARE @LecturaClientes TABLE(ClienteId INT,NIT NVARCHAR(25),Nombre NVARCHAR(150),Correo NVARCHAR(254),Telefono NVARCHAR(25),Activo BIT,FechaCreacion DATETIME2(3),FechaInactivacion DATETIME2(3),MotivoInactivacion NVARCHAR(250),Version BINARY(8));
WHILE @CasoExtra<=4
BEGIN
 SET @EtiquetaExtra=REPLACE(CONVERT(NVARCHAR(36),NEWID()),N'-',N'');
 SET @OperacionExtra=NEWID(); SET @ErrorExtra=NULL;
 SET @EsperadoExtra=CASE @CasoExtra WHEN 2 THEN 229 WHEN 3 THEN 54101 WHEN 4 THEN 547 END;
 BEGIN TRY
  BEGIN TRANSACTION;
  INSERT dbo.Usuario(NombreUsuario,NombreCompleto,Correo,PasswordHash,Salt)
  VALUES(@EtiquetaExtra,N'Actor extra',@EtiquetaExtra+N'@example.invalid',CRYPT_GEN_RANDOM(64),CRYPT_GEN_RANDOM(32));
  SET @ActorExtra=SCOPE_IDENTITY();
  INSERT dbo.Rol(Nombre) VALUES(@EtiquetaExtra); SET @RolExtra=SCOPE_IDENTITY();
  INSERT dbo.Usuario_Rol(UsuarioId,RolId) VALUES(@ActorExtra,@RolExtra);
  INSERT dbo.Rol_Permiso(RolId,PermisoId) SELECT @RolExtra,PermisoId FROM dbo.Permiso WHERE Activo=1;
  INSERT dbo.Proveedor(NIT,Nombre) VALUES(LEFT(@EtiquetaExtra,25),N'Proveedor extra'); SET @ProveedorExtra=SCOPE_IDENTITY();
  INSERT dbo.Producto(Codigo,Descripcion,Precio,PrecioCosto,ProveedorId) VALUES(@EtiquetaExtra,N'Producto extra',10,5,@ProveedorExtra); SET @ProductoExtra=SCOPE_IDENTITY();
  INSERT dbo.Cliente(NIT,Nombre,Activo) VALUES(LEFT(@EtiquetaExtra,25),N'Cliente extra inactivo',0); SET @ClienteExtra=SCOPE_IDENTITY();
  IF OBJECT_ID('dbo.sp_AbrirKardexInventario','P') IS NOT NULL
  BEGIN
   SET @AperturaExtra=NEWID();
   EXEC dbo.sp_AbrirKardexInventario @AperturaExtra,@ActorExtra,@EtiquetaExtra,N'Apertura fixture adicional';
   EXEC dbo.sp_HabilitarKardexInventario @AperturaExtra,@ActorExtra;
  END
  ELSE UPDATE dbo.ConfiguracionInventario SET Habilitado=1 WHERE ConfiguracionId=1;
  IF @CasoExtra=1
  BEGIN
   EXEC dbo.sp_RegistrarMovimientoKardex @ProductoExtra,'COMPRA',4,@ActorExtra,N'EXTRA',@OperacionExtra,1,N'Lectura verificada';
   INSERT @LecturaKardex EXEC dbo.sp_ConsultarKardex @ActorUsuarioId=@ActorExtra,@ProductoId=@ProductoExtra;
   IF NOT EXISTS(SELECT 1 FROM @LecturaKardex WHERE ProductoId=@ProductoExtra AND StockAnterior=0 AND StockResultante=4 AND Cantidad=4) THROW 54900,'Consulta Kardex incorrecta.',1;
   INSERT @LecturaClientes EXEC dbo.sp_ConsultarClientesAdministracion @ActorUsuarioId=@ActorExtra;
   IF NOT EXISTS(SELECT 1 FROM @LecturaClientes WHERE ClienteId=@ClienteExtra AND Activo=0) THROW 54900,'Consulta administrativa oculta historia inactiva.',1;
  END;
  IF @CasoExtra=2
  BEGIN
   EXECUTE AS USER=N'securefinance_app';
   EXEC sys.sp_executesql N'UPDATE dbo.Producto SET Stock=Stock+1 WHERE ProductoId=@Id;',N'@Id INT',@Id=@ProductoExtra;
   REVERT;
  END;
  IF @CasoExtra=3
  BEGIN
   DELETE dbo.Rol_Permiso WHERE RolId=@RolExtra;
   EXEC dbo.sp_RegistrarMovimientoKardex @ProductoExtra,'COMPRA',1,@ActorExtra,N'EXTRA',@OperacionExtra,1,N'No autorizado';
  END;
  IF @CasoExtra=4 UPDATE dbo.Producto SET PrecioCosto=-1 WHERE ProductoId=@ProductoExtra;
  IF @EsperadoExtra IS NOT NULL THROW 54900,'Se esperaba rechazo adicional.',1;
  ROLLBACK TRANSACTION;
 END TRY
 BEGIN CATCH
  SET @ErrorExtra=ERROR_NUMBER();
  IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
  IF USER_NAME()=N'securefinance_app' REVERT;
  IF @EsperadoExtra IS NULL OR @ErrorExtra<>@EsperadoExtra
  BEGIN
   PRINT CONCAT('FAIL|S',@CasoExtra,'|',@ErrorExtra,'|',ERROR_MESSAGE());
   THROW;
  END;
  IF EXISTS(SELECT 1 FROM dbo.Producto WHERE ProductoId=@ProductoExtra) OR EXISTS(SELECT 1 FROM dbo.Kardex_Inventario WHERE OperacionId=@OperacionExtra)
   THROW 54900,'Persistieron datos de la prueba adicional.',1;
 END CATCH;
 PRINT CONCAT('PASS|S',@CasoExtra,'|ErrorEsperado=',COALESCE(CONVERT(VARCHAR(10),@ErrorExtra),'ninguno'));
 SET @CasoExtra+=1;
END;
GO
