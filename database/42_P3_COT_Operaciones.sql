SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
IF OBJECT_ID('dbo.P3_COT_Vigencias','IF') IS NULL THROW 54900,'Requiere migracion 41.',1;
GO
CREATE OR ALTER PROCEDURE dbo.P3_COT_Crear
 @ActorUsuarioId INT,@ClienteId INT,@VenceEn DATETIME2(3),
 @Detalle dbo.TipoDetalleVentaDescuento READONLY,
 @OperacionId UNIQUEIDENTIFIER,@Observaciones NVARCHAR(MAX)=NULL
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
 BEGIN TRANSACTION;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'COTIZACIONES_CREAR';
 IF @OperacionId IS NULL OR @ClienteId IS NULL OR @VenceEn IS NULL
 OR DATALENGTH(@Observaciones)>2000 THROW 54902,'Datos de cotizacion invalidos.',1;
 IF NOT EXISTS(SELECT 1 FROM @Detalle) OR (SELECT COUNT(*) FROM @Detalle)>100
 OR EXISTS(SELECT 1 FROM @Detalle WHERE ProductoId<1 OR Cantidad<1 OR DescuentoPorcentaje NOT BETWEEN 0 AND 100)
 OR EXISTS(SELECT ProductoId FROM @Detalle GROUP BY ProductoId HAVING COUNT(*)>1)
 THROW 54902,'Entre 1 y 100 lineas unicas y cantidades positivas.',1;
 DECLARE @Canon NVARCHAR(MAX)=(SELECT ProductoId,Cantidad,DescuentoPorcentaje FROM @Detalle ORDER BY ProductoId FOR JSON PATH),
 @Hash BINARY(32),@Id INT,@Anterior BINARY(32),@Lock INT,@Resource NVARCHAR(255)=CONCAT(N'P3.COT.Crear.',@OperacionId);
 SET @Hash=HASHBYTES('SHA2_256',CONCAT(@ActorUsuarioId,N'|',@ClienteId,N'|',CONVERT(NVARCHAR(30),@VenceEn,126),N'|',COALESCE(@Observaciones,N''),N'|',@Canon));
 EXEC @Lock=sys.sp_getapplock @Resource=@Resource,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
 IF @Lock<0 THROW 54903,'Operacion ocupada.',1;
 SELECT @Id=CotizacionId,@Anterior=SolicitudHash FROM dbo.P3_COT_Cotizacion WITH(UPDLOCK,HOLDLOCK) WHERE OperacionId=@OperacionId;
 IF @Id IS NOT NULL
 BEGIN
  IF @Anterior<>@Hash THROW 54903,'Referencia usada con otros datos.',1;
 END
 ELSE
 BEGIN
 DECLARE @Ahora DATETIME2(3)=SYSUTCDATETIME(),@Nombre NVARCHAR(150),@NIT NVARCHAR(25),@Max DECIMAL(5,2);
 IF @VenceEn<=@Ahora OR @VenceEn>DATEADD(DAY,90,@Ahora) THROW 54902,'Vigencia debe ser futura y de hasta 90 dias.',1;
 SELECT @Nombre=Nombre,@NIT=NIT FROM dbo.Cliente WITH(HOLDLOCK) WHERE ClienteId=@ClienteId AND Activo=1;
 IF @Nombre IS NULL THROW 54904,'Cliente inexistente o inactivo.',1;
 SELECT @Max=MaxDescuento FROM dbo.fn_ObtenerPoliticaVenta(@ActorUsuarioId);
 IF @Max IS NULL OR EXISTS(SELECT 1 FROM @Detalle WHERE DescuentoPorcentaje>@Max) THROW 54902,'Descuento no autorizado.',1;
 DECLARE @L TABLE(ProductoId INT PRIMARY KEY,SKU NVARCHAR(40),Descripcion NVARCHAR(200),Cantidad INT,
 Precio DECIMAL(12,2),Porcentaje DECIMAL(5,2),Bruto DECIMAL(19,2),Descuento DECIMAL(19,2));
 -- Orden estable y HOLDLOCK: una emision toma un snapshot consistente sin reservar stock.
 DECLARE @Producto INT=0,@Siguiente INT,@Precio DECIMAL(12,2),@SKU NVARCHAR(40),@Descripcion NVARCHAR(200),@Cantidad INT,@Porcentaje DECIMAL(5,2),@Bruto DECIMAL(19,2);
 WHILE 1=1
 BEGIN
  SELECT @Siguiente=MIN(ProductoId) FROM @Detalle WHERE ProductoId>@Producto;
  IF @Siguiente IS NULL BREAK;
  SET @Producto=@Siguiente; SET @Precio=NULL;
  SELECT @Precio=Precio,@SKU=Codigo,@Descripcion=Descripcion FROM dbo.Producto WITH(HOLDLOCK) WHERE ProductoId=@Producto AND Activo=1;
  IF @Precio IS NULL THROW 54904,'Producto inexistente o inactivo.',1;
  SELECT @Cantidad=Cantidad,@Porcentaje=DescuentoPorcentaje FROM @Detalle WHERE ProductoId=@Producto;
  SET @Bruto=@Precio*CONVERT(DECIMAL(10,0),@Cantidad);
  INSERT @L VALUES(@Producto,@SKU,@Descripcion,@Cantidad,@Precio,@Porcentaje,@Bruto,ROUND(@Bruto*@Porcentaje/CONVERT(DECIMAL(5,2),100),2));
 END;
 DECLARE @Subtotal DECIMAL(19,2),@Descuento DECIMAL(19,2),@IVA DECIMAL(19,2);
 SELECT @Subtotal=SUM(Bruto),@Descuento=SUM(Descuento) FROM @L;
 SET @IVA=ROUND((@Subtotal-@Descuento)*CONVERT(DECIMAL(3,2),0.12),2);
 INSERT dbo.P3_COT_Cotizacion(ClienteId,ClienteNombre,ClienteNIT,UsuarioId,FechaCreacion,VenceEn,Subtotal,Descuento,IVA,Total,Observaciones,OperacionId,SolicitudHash)
 VALUES(@ClienteId,@Nombre,@NIT,@ActorUsuarioId,@Ahora,@VenceEn,@Subtotal,@Descuento,@IVA,@Subtotal-@Descuento+@IVA,@Observaciones,@OperacionId,@Hash);
 SET @Id=CONVERT(INT,SCOPE_IDENTITY());
 INSERT dbo.P3_COT_Detalle(CotizacionId,ProductoId,SKU,Descripcion,Cantidad,PrecioUnitario,DescuentoPorcentaje,Subtotal,DescuentoMonto)
 SELECT @Id,ProductoId,SKU,Descripcion,Cantidad,Precio,Porcentaje,Bruto,Descuento FROM @L;
 INSERT dbo.P3_COT_HistorialEstado(CotizacionId,EstadoAnterior,EstadoNuevo,ActorUsuarioId,OperacionId,Motivo)
 VALUES(@Id,NULL,'ACTIVA',@ActorUsuarioId,@OperacionId,N'Emision de cotizacion');
 INSERT dbo.Bitacora_Transacciones(TablaAfectada,Operacion,IdentificadorRegistro,ValorNuevo,ActorUsuarioId,OperacionId,Motivo)
 SELECT N'P3_COT_Cotizacion','INSERT',CONVERT(NVARCHAR(20),@Id),
 (SELECT CotizacionId,Numero,ClienteId,Subtotal,Descuento,IVA,Total,VenceEn FROM dbo.P3_COT_Cotizacion WHERE CotizacionId=@Id FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),
 @ActorUsuarioId,@OperacionId,N'Emision de cotizacion sin afectar inventario';
 END;
 SELECT CotizacionId,Numero,EstadoVigente Estado,CONVERT(VARCHAR(21),Total) Total FROM dbo.P3_COT_Vigencias() WHERE CotizacionId=@Id;
 COMMIT;
 END TRY BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK; THROW; END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.P3_COT_Consultar
 @ActorUsuarioId INT,@Id INT=NULL,@Numero NVARCHAR(14)=NULL,@Cliente NVARCHAR(150)=NULL,
 @Estado VARCHAR(15)=NULL,@Desde DATETIME2(3)=NULL,@Hasta DATETIME2(3)=NULL,@Desplazamiento INT=0
AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'COTIZACIONES_CONSULTAR';
 IF @Desplazamiento<0 OR @Desplazamiento>2000000 OR (@Estado IS NOT NULL AND @Estado NOT IN('ACTIVA','VENCIDA','PROCESADA','CANCELADA'))
 THROW 54902,'Filtros invalidos.',1;
 SELECT c.CotizacionId,c.Numero,c.ClienteId,c.ClienteNombre,c.ClienteNIT,c.UsuarioId,u.NombreUsuario Responsable,
 c.FechaCreacion,c.VenceEn,c.EstadoVigente Estado,c.FacturaId,c.Observaciones,c.OperacionId,
 CONVERT(VARCHAR(21),c.Subtotal) Subtotal,CONVERT(VARCHAR(21),c.Descuento) Descuento,
 CONVERT(VARCHAR(21),c.SubtotalNeto) SubtotalNeto,CONVERT(VARCHAR(21),c.IVA) IVA,CONVERT(VARCHAR(21),c.Total) Total
 FROM dbo.P3_COT_Vigencias() c JOIN dbo.Usuario u ON u.UsuarioId=c.UsuarioId
 WHERE (@Id IS NULL OR c.CotizacionId=@Id) AND (@Numero IS NULL OR c.Numero=@Numero)
 AND (@Cliente IS NULL OR c.ClienteNombre LIKE N'%'+@Cliente+N'%' OR c.ClienteNIT LIKE N'%'+@Cliente+N'%')
 AND (@Estado IS NULL OR c.EstadoVigente=@Estado) AND (@Desde IS NULL OR c.FechaCreacion>=@Desde) AND (@Hasta IS NULL OR c.FechaCreacion<@Hasta)
 ORDER BY c.CotizacionId DESC OFFSET @Desplazamiento ROWS FETCH NEXT 21 ROWS ONLY;
 IF @Id IS NOT NULL
 BEGIN
 SELECT ProductoId,SKU,Descripcion,Cantidad,CONVERT(VARCHAR(21),PrecioUnitario) PrecioUnitario,
 CONVERT(VARCHAR(6),DescuentoPorcentaje) DescuentoPorcentaje,CONVERT(VARCHAR(21),Subtotal) Subtotal,
 CONVERT(VARCHAR(21),DescuentoMonto) DescuentoMonto,CONVERT(VARCHAR(21),SubtotalNeto) SubtotalNeto
 FROM dbo.P3_COT_Detalle WHERE CotizacionId=@Id ORDER BY ProductoId;
 SELECT h.EstadoAnterior,h.EstadoNuevo,h.FechaHora,h.Motivo,u.NombreUsuario Responsable
 FROM dbo.P3_COT_HistorialEstado h JOIN dbo.Usuario u ON u.UsuarioId=h.ActorUsuarioId WHERE CotizacionId=@Id ORDER BY HistorialId;
 END;
END;
GO
CREATE OR ALTER PROCEDURE dbo.P3_COT_Catalogos @ActorUsuarioId INT AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'COTIZACIONES_CREAR';
 SELECT ClienteId,Nombre,NIT FROM dbo.Cliente WHERE Activo=1 ORDER BY Nombre,ClienteId;
 SELECT ProductoId,Codigo,Descripcion,CONVERT(VARCHAR(21),Precio) Precio,Stock FROM dbo.Producto WHERE Activo=1 ORDER BY Codigo;
 SELECT MaxDescuento,SYSUTCDATETIME() Ahora FROM dbo.fn_ObtenerPoliticaVenta(@ActorUsuarioId);
END;
GO
CREATE OR ALTER PROCEDURE dbo.P3_COT_Cancelar
 @ActorUsuarioId INT,@CotizacionId INT,@OperacionId UNIQUEIDENTIFIER,@Motivo NVARCHAR(MAX)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
 BEGIN TRANSACTION;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'COTIZACIONES_CANCELAR';
 IF @OperacionId IS NULL OR @Motivo IS NULL OR LEN(LTRIM(RTRIM(@Motivo)))=0 OR DATALENGTH(@Motivo)>500 THROW 54902,'Motivo y operacion requeridos.',1;
 DECLARE @Lock INT,@Resource NVARCHAR(255)=CONCAT(N'P3.COT.Cancelar.',@OperacionId);
 EXEC @Lock=sys.sp_getapplock @Resource=@Resource,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
 IF @Lock<0 THROW 54903,'Operacion ocupada.',1;
 IF EXISTS(SELECT 1 FROM dbo.P3_COT_HistorialEstado WITH(UPDLOCK,HOLDLOCK) WHERE OperacionId=@OperacionId)
 BEGIN
  IF NOT EXISTS(SELECT 1 FROM dbo.P3_COT_HistorialEstado WHERE OperacionId=@OperacionId AND CotizacionId=@CotizacionId AND EstadoNuevo='CANCELADA' AND ActorUsuarioId=@ActorUsuarioId AND CONVERT(VARBINARY(MAX),Motivo)=CONVERT(VARBINARY(MAX),@Motivo))
  THROW 54903,'Referencia usada con otros datos.',1;
 END
 ELSE
 BEGIN
 IF NOT EXISTS(SELECT 1 FROM dbo.P3_COT_Cotizacion WITH(UPDLOCK,HOLDLOCK) WHERE CotizacionId=@CotizacionId) THROW 54904,'Cotizacion inexistente.',1;
 IF NOT EXISTS(SELECT 1 FROM dbo.P3_COT_Vigencias() WHERE CotizacionId=@CotizacionId AND EstadoVigente='ACTIVA') THROW 54903,'Solo puede cancelar una cotizacion activa.',1;
 UPDATE dbo.P3_COT_Cotizacion SET Estado='CANCELADA' WHERE CotizacionId=@CotizacionId;
 INSERT dbo.P3_COT_HistorialEstado(CotizacionId,EstadoAnterior,EstadoNuevo,ActorUsuarioId,OperacionId,Motivo)
 VALUES(@CotizacionId,'ACTIVA','CANCELADA',@ActorUsuarioId,@OperacionId,@Motivo);
 INSERT dbo.Bitacora_Transacciones(TablaAfectada,Operacion,IdentificadorRegistro,ValorAnterior,ValorNuevo,ActorUsuarioId,OperacionId,Motivo)
 VALUES(N'P3_COT_Cotizacion','UPDATE',CONVERT(NVARCHAR(20),@CotizacionId),N'{"Estado":"ACTIVA"}',N'{"Estado":"CANCELADA"}',@ActorUsuarioId,@OperacionId,@Motivo);
 END;
 SELECT @CotizacionId CotizacionId,'CANCELADA' Estado;
 COMMIT;
 END TRY BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK; THROW; END CATCH;
END;
GO
GRANT EXECUTE ON dbo.P3_COT_Crear TO securefinance_app;
GRANT EXECUTE ON dbo.P3_COT_Consultar TO securefinance_app;
GRANT EXECUTE ON dbo.P3_COT_Catalogos TO securefinance_app;
GRANT EXECUTE ON dbo.P3_COT_Cancelar TO securefinance_app;
GO
