SET XACT_ABORT ON; SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON;
IF OBJECT_ID('dbo.sp_RegistrarRecepcionCompra','P') IS NULL THROW 54800,'Requiere migraciones 33-36.',1;
IF OBJECT_ID('dbo.SolicitudVentaERP','U') IS NULL
CREATE TABLE dbo.SolicitudVentaERP(
 OperacionId UNIQUEIDENTIFIER PRIMARY KEY,
 FacturaId INT NOT NULL UNIQUE REFERENCES dbo.Factura(FacturaId),
 UsuarioId INT NOT NULL REFERENCES dbo.Usuario(UsuarioId),
 SolicitudHash BINARY(32) NOT NULL,
 Comprobante NVARCHAR(MAX) NOT NULL CHECK(ISJSON(Comprobante)=1),
 Detalle NVARCHAR(MAX) NOT NULL CHECK(ISJSON(Detalle)=1),
 FechaHora DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME()
);
GO
CREATE OR ALTER TRIGGER dbo.tr_ERP_SolicitudVentaInmutable ON dbo.SolicitudVentaERP AFTER UPDATE,DELETE AS
BEGIN
 IF EXISTS(SELECT 1 FROM deleted) THROW 54805,'La solicitud de venta y su comprobante son inmutables.',1;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_ERP_ProcesarVenta
 @ClienteId INT,@UsuarioId INT,@Detalle dbo.TipoDetalleVentaDescuento READONLY,
 @OperacionId UNIQUEIDENTIFIER,@MotivoDescuento NVARCHAR(80)=NULL AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
 BEGIN TRANSACTION;
 EXEC dbo.sp_ParteII_ValidarPermiso @UsuarioId,N'VENTAS_REGISTRAR';
 IF @OperacionId IS NULL THROW 54802,'Operacion requerida.',1;
 DECLARE @Canon NVARCHAR(MAX)=(SELECT ProductoId,Cantidad,DescuentoPorcentaje FROM @Detalle ORDER BY ProductoId FOR JSON PATH),
 @Hash BINARY(32),@Resource NVARCHAR(255)=CONCAT(N'ERP.Venta.',@OperacionId),@Lock INT,@F INT,@Prev BINARY(32),@Header NVARCHAR(MAX),@Lines NVARCHAR(MAX);
 SET @Hash=HASHBYTES('SHA2_256',CONCAT(@ClienteId,N'|',@UsuarioId,N'|',COALESCE(@MotivoDescuento,N''),N'|',@Canon));
 EXEC @Lock=sys.sp_getapplock @Resource=@Resource,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
 IF @Lock<0 THROW 54803,'Venta ocupada.',1;
 SELECT @F=FacturaId,@Prev=SolicitudHash,@Header=Comprobante,@Lines=Detalle FROM dbo.SolicitudVentaERP WITH(UPDLOCK,HOLDLOCK) WHERE OperacionId=@OperacionId;
 IF @F IS NOT NULL
 BEGIN
 IF @Prev<>@Hash THROW 54803,'Referencia utilizada con otros datos.',1;
 SELECT * FROM OPENJSON(@Header) WITH(FacturaId INT,FechaHora DATETIME2(3),Subtotal VARCHAR(21),Descuento VARCHAR(21),SubtotalNeto VARCHAR(21),IVA VARCHAR(21),Total VARCHAR(21),Cliente NVARCHAR(150),NIT NVARCHAR(25),Cajero NVARCHAR(50),MotivoDescuento NVARCHAR(80));
 SELECT * FROM OPENJSON(@Lines) WITH(ProductoId INT,Descripcion NVARCHAR(200),Cantidad INT,PrecioUnitario VARCHAR(21),Subtotal VARCHAR(21),DescuentoPorcentaje VARCHAR(6),DescuentoMonto VARCHAR(21),SubtotalNeto VARCHAR(21));
 END
 ELSE
 BEGIN
 -- Conserva el procedimiento existente como unica operacion de venta y egreso.
 EXEC dbo.sp_ProcesarVentaTransaccional @ClienteId=@ClienteId,@UsuarioId=@UsuarioId,@Detalle=@Detalle,@FacturaId=@F OUTPUT,@MotivoDescuento=@MotivoDescuento;
 SELECT @Header=(SELECT f.FacturaId,f.FechaHora,CONVERT(VARCHAR(21),f.Subtotal) Subtotal,
 CONVERT(VARCHAR(21),f.DescuentoTotal) Descuento,CONVERT(VARCHAR(21),f.Subtotal-f.DescuentoTotal) SubtotalNeto,
 CONVERT(VARCHAR(21),f.IVA) IVA,CONVERT(VARCHAR(21),f.Total) Total,f.ClienteNombreEmision Cliente,f.ClienteNITEmision NIT,u.NombreUsuario Cajero,f.MotivoDescuento
 FROM dbo.Factura f JOIN dbo.Usuario u ON u.UsuarioId=f.UsuarioId WHERE f.FacturaId=@F FOR JSON PATH,WITHOUT_ARRAY_WRAPPER,INCLUDE_NULL_VALUES);
 SELECT @Lines=(SELECT d.ProductoId,p.Descripcion,d.Cantidad,CONVERT(VARCHAR(21),d.PrecioUnitario) PrecioUnitario,
 CONVERT(VARCHAR(21),d.Subtotal) Subtotal,CONVERT(VARCHAR(6),d.DescuentoPorcentaje) DescuentoPorcentaje,
 CONVERT(VARCHAR(21),d.DescuentoMonto) DescuentoMonto,CONVERT(VARCHAR(21),d.SubtotalNeto) SubtotalNeto
 FROM dbo.DetalleFactura d JOIN dbo.Producto p ON p.ProductoId=d.ProductoId WHERE d.FacturaId=@F ORDER BY d.ProductoId FOR JSON PATH);
 INSERT dbo.SolicitudVentaERP(OperacionId,FacturaId,UsuarioId,SolicitudHash,Comprobante,Detalle) VALUES(@OperacionId,@F,@UsuarioId,@Hash,@Header,@Lines);
 END;
 COMMIT;
 END TRY
 BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK;
 THROW;
 END CATCH;
END;
GO
GRANT EXECUTE ON dbo.sp_ERP_ProcesarVenta TO securefinance_app;
DENY EXECUTE ON dbo.sp_ProcesarVentaTransaccional TO securefinance_app;
DENY EXECUTE ON dbo.sp_ProcesarVentaSinDescuento TO securefinance_app;
DENY SELECT,INSERT,UPDATE,DELETE ON dbo.SolicitudVentaERP TO securefinance_app;
GO
