-- Edward: incremental despues de 23. Contexto explicito del DBA.
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
SET XACT_ABORT ON;
IF OBJECT_ID('dbo.sp_ActualizarDatosCliente','P') IS NULL THROW 54600,'Requiere migraciones 15-23.',1;
BEGIN TRANSACTION;
IF OBJECT_ID('dbo.DevolucionCliente','U') IS NULL
CREATE TABLE dbo.DevolucionCliente(
 DevolucionId INT IDENTITY PRIMARY KEY,
 OperacionId UNIQUEIDENTIFIER NOT NULL UNIQUE,
 FacturaId INT NOT NULL REFERENCES dbo.Factura(FacturaId),
 UsuarioId INT NOT NULL REFERENCES dbo.Usuario(UsuarioId),
 Motivo NVARCHAR(250) NOT NULL CHECK(LEN(LTRIM(RTRIM(Motivo)))>0),
 SolicitudHash BINARY(32) NOT NULL,
 FechaHora DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME()
);
IF OBJECT_ID('dbo.DetalleDevolucion','U') IS NULL
BEGIN
 CREATE TABLE dbo.DetalleDevolucion(
 DetalleDevolucionId INT IDENTITY PRIMARY KEY,
 DevolucionId INT NOT NULL REFERENCES dbo.DevolucionCliente(DevolucionId),
 DetalleFacturaId INT NOT NULL REFERENCES dbo.DetalleFactura(DetalleFacturaId),
 Cantidad INT NOT NULL CHECK(Cantidad>0), Reingresar BIT NOT NULL,
 Subtotal DECIMAL(19,2) NOT NULL CHECK(Subtotal>=0),
 Descuento DECIMAL(19,2) NOT NULL,
 IVA DECIMAL(19,2) NOT NULL CHECK(IVA>=0),
 Total AS (Subtotal-Descuento+IVA) PERSISTED,
 UNIQUE(DevolucionId,DetalleFacturaId),
 CHECK(Descuento>=0 AND Descuento<=Subtotal));
 CREATE INDEX IX_DetalleDevolucion_Original ON dbo.DetalleDevolucion(DetalleFacturaId) INCLUDE(Cantidad);
END;
IF OBJECT_ID('dbo.DevolucionKardex','U') IS NULL
CREATE TABLE dbo.DevolucionKardex(
 DetalleDevolucionId INT PRIMARY KEY REFERENCES dbo.DetalleDevolucion(DetalleDevolucionId),
 KardexId BIGINT NOT NULL UNIQUE REFERENCES dbo.Kardex_Inventario(KardexId)
);
IF OBJECT_ID('dbo.NotaCredito','U') IS NULL
CREATE TABLE dbo.NotaCredito(
 NotaCreditoId INT IDENTITY PRIMARY KEY,
 DevolucionId INT NOT NULL UNIQUE REFERENCES dbo.DevolucionCliente(DevolucionId),
 Subtotal DECIMAL(19,2) NOT NULL,
 Descuento DECIMAL(19,2) NOT NULL,
 IVA DECIMAL(19,2) NOT NULL,
 Total DECIMAL(19,2) NOT NULL,
 Estado VARCHAR(15) NOT NULL DEFAULT 'EMITIDA' CHECK(Estado='EMITIDA'),
 EstadoCredito VARCHAR(20) NOT NULL DEFAULT 'PENDIENTE' CHECK(EstadoCredito='PENDIENTE'),
 CHECK(Subtotal>=0 AND Descuento BETWEEN 0 AND Subtotal AND IVA>=0 AND Total=Subtotal-Descuento+IVA)
);
COMMIT;
GO
CREATE OR ALTER TRIGGER dbo.tr_DetalleDevolucion_Reingreso ON dbo.DetalleDevolucion AFTER INSERT AS
BEGIN
 SET NOCOUNT ON;
 IF TRIGGER_NESTLEVEL(OBJECT_ID('dbo.tr_DetalleDevolucion_Reingreso'))>1 THROW 54602,'Recursion de devolucion prohibida.',1;
 DECLARE @Id INT,@Producto INT,@Cantidad INT,@Actor INT,@Operacion UNIQUEIDENTIFIER,@Documento NVARCHAR(100),@Motivo NVARCHAR(250);
 DECLARE lineas CURSOR LOCAL FAST_FORWARD FOR
 SELECT i.DetalleDevolucionId,f.ProductoId,i.Cantidad,d.UsuarioId,d.OperacionId,CONCAT(N'DEV-',d.DevolucionId),d.Motivo
 FROM inserted i JOIN dbo.DevolucionCliente d ON d.DevolucionId=i.DevolucionId
 JOIN dbo.DetalleFactura f ON f.DetalleFacturaId=i.DetalleFacturaId
 WHERE i.Reingresar=1 ORDER BY f.ProductoId,i.DetalleDevolucionId;
 OPEN lineas;
 FETCH NEXT FROM lineas INTO @Id,@Producto,@Cantidad,@Actor,@Operacion,@Documento,@Motivo;
 WHILE @@FETCH_STATUS=0
 BEGIN
  EXEC dbo.sp_RegistrarMovimientoKardex @ProductoId=@Producto,@TipoMovimiento='DEVOLUCION',
   @Cantidad=@Cantidad,@ActorUsuarioId=@Actor,@DocumentoRespaldo=@Documento,
   @OperacionId=@Operacion,@LineaOperacion=@Id,@Motivo=@Motivo,@DevolverResultado=0;
  INSERT dbo.DevolucionKardex(DetalleDevolucionId,KardexId)
  SELECT @Id,KardexId FROM dbo.Kardex_Inventario WHERE OperacionId=@Operacion AND LineaOperacion=@Id;
  IF @@ROWCOUNT<>1 THROW 54602,'No se registro el reingreso.',1;
  FETCH NEXT FROM lineas INTO @Id,@Producto,@Cantidad,@Actor,@Operacion,@Documento,@Motivo;
 END;
 CLOSE lineas; DEALLOCATE lineas;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_ProcesarDevolucionCliente
 @ActorUsuarioId INT,@FacturaId INT,@OperacionId UNIQUEIDENTIFIER,@Motivo NVARCHAR(MAX),@Detalles NVARCHAR(MAX)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 SET ANSI_WARNINGS ON; SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET NUMERIC_ROUNDABORT OFF;
 DECLARE @Propia BIT=CASE WHEN @@TRANCOUNT=0 THEN 1 ELSE 0 END;
 BEGIN TRY
 IF @Propia=1 BEGIN TRANSACTION;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'DEVOLUCIONES_REGISTRAR';
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'DEVOLUCIONES_AUTORIZAR';
 IF @OperacionId IS NULL OR @Motivo IS NULL OR LEN(LTRIM(RTRIM(@Motivo)))=0 OR DATALENGTH(@Motivo)>500
 OR ISJSON(@Detalles)<>1 OR @Detalles IS NULL OR LEFT(LTRIM(@Detalles),1)<>'['
 THROW 54602,'Solicitud de devolucion invalida.',1;
 DECLARE @Lineas TABLE(DetalleFacturaId INT, Cantidad INT, Reingresar BIT);
 INSERT @Lineas SELECT DetalleFacturaId,Cantidad,Reingresar FROM OPENJSON(@Detalles)
 WITH(DetalleFacturaId INT,Cantidad INT,Reingresar BIT);
 IF NOT EXISTS(SELECT 1 FROM @Lineas) OR (SELECT COUNT(*) FROM @Lineas)>100
 OR EXISTS(SELECT 1 FROM @Lineas WHERE DetalleFacturaId IS NULL OR Cantidad IS NULL OR Cantidad<=0 OR Reingresar IS NULL)
 OR EXISTS(SELECT DetalleFacturaId FROM @Lineas GROUP BY DetalleFacturaId HAVING COUNT(*)>1)
 THROW 54602,'Detalles o cantidades invalidos.',1;
 DECLARE @Canon NVARCHAR(MAX)=(SELECT DetalleFacturaId,Cantidad,Reingresar FROM @Lineas ORDER BY DetalleFacturaId FOR JSON PATH),
 @Hash BINARY(32),@Lock INT,@Resource NVARCHAR(255)=CONCAT(N'Edward.Devolucion.',@OperacionId);
 SET @Hash=HASHBYTES('SHA2_256',CONCAT(@FacturaId,N'|',@ActorUsuarioId,N'|',DATALENGTH(@Motivo),N'|',@Motivo,N'|',@Canon));
 EXEC @Lock=sys.sp_getapplock @Resource=@Resource,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
 IF @Lock<0 THROW 54603,'Operacion ocupada. Reintente con la misma referencia.',1;
 DECLARE @Id INT,@PrevHash BINARY(32);
 SELECT @Id=DevolucionId,@PrevHash=SolicitudHash FROM dbo.DevolucionCliente WITH(UPDLOCK,HOLDLOCK) WHERE OperacionId=@OperacionId;
 IF @Id IS NOT NULL
 BEGIN
  IF @PrevHash<>@Hash THROW 54603,'Referencia utilizada con otros datos.',1;
  IF @Propia=1 COMMIT TRANSACTION;
  SELECT @Id DevolucionId,NotaCreditoId FROM dbo.NotaCredito WHERE DevolucionId=@Id;
  RETURN;
 END;
 -- Serializa todas las devoluciones de una factura, incluyendo unidades e importes.
 DECLARE @TotalFactura DECIMAL(19,2),@Base DECIMAL(19,2),@Impuesto DECIMAL(19,2);
 SELECT @TotalFactura=Total,@Base=Subtotal-DescuentoTotal,@Impuesto=IVA FROM dbo.Factura WITH(UPDLOCK,HOLDLOCK) WHERE FacturaId=@FacturaId;
 IF @TotalFactura IS NULL THROW 54604,'Factura inexistente.',1;
 IF EXISTS(SELECT 1 FROM @Lineas l LEFT JOIN dbo.DetalleFactura f ON f.DetalleFacturaId=l.DetalleFacturaId AND f.FacturaId=@FacturaId WHERE f.DetalleFacturaId IS NULL)
 THROW 54604,'Producto ajeno a la factura.',1;
 DECLARE @Calculadas TABLE(DetalleFacturaId INT PRIMARY KEY,Cantidad INT,Reingresar BIT,Subtotal DECIMAL(19,2),Descuento DECIMAL(19,2),IVA DECIMAL(19,2));
 IF EXISTS(SELECT 1 FROM @Lineas l JOIN dbo.DetalleFactura f ON f.DetalleFacturaId=l.DetalleFacturaId
 OUTER APPLY(SELECT SUM(CONVERT(BIGINT,Cantidad)) Devuelto FROM dbo.DetalleDevolucion WHERE DetalleFacturaId=f.DetalleFacturaId) a
 WHERE CONVERT(BIGINT,l.Cantidad)+COALESCE(a.Devuelto,0)>f.Cantidad)
 THROW 54605,'Cantidad acumulada superior a la venta.',1;
 -- Prorrateo acumulado: diferencias de redondeos; la ultima unidad recupera el residuo.
 -- IVA por linea: diferencia de cuotas acumuladas en orden de detalle, conservando IVA de cabecera.
 ;WITH originales AS(
 SELECT f.*,SUM(SubtotalNeto) OVER(ORDER BY DetalleFacturaId ROWS UNBOUNDED PRECEDING) Acumulado
 FROM dbo.DetalleFactura f WHERE FacturaId=@FacturaId
 )
 INSERT @Calculadas
 SELECT l.DetalleFacturaId,l.Cantidad,l.Reingresar,
 ROUND(f.Subtotal*(CONVERT(DECIMAL(19,8),COALESCE(a.Q,0)+l.Cantidad)/f.Cantidad),2)-COALESCE(a.S,0),
 ROUND(f.DescuentoMonto*(CONVERT(DECIMAL(19,8),COALESCE(a.Q,0)+l.Cantidad)/f.Cantidad),2)-COALESCE(a.D,0),
 ROUND(t.IVA*(CONVERT(DECIMAL(19,8),COALESCE(a.Q,0)+l.Cantidad)/f.Cantidad),2)-COALESCE(a.I,0)
 FROM @Lineas l JOIN originales f ON f.DetalleFacturaId=l.DetalleFacturaId
 OUTER APPLY(SELECT SUM(Cantidad) Q,SUM(Subtotal) S,SUM(Descuento) D,SUM(IVA) I FROM dbo.DetalleDevolucion WHERE DetalleFacturaId=f.DetalleFacturaId) a
 CROSS APPLY(SELECT CASE WHEN @Base=0 THEN CONVERT(DECIMAL(19,2),0) ELSE
 ROUND(@Impuesto*(CONVERT(DECIMAL(28,10),f.Acumulado)/@Base),2)-
 ROUND(@Impuesto*(CONVERT(DECIMAL(28,10),f.Acumulado-f.SubtotalNeto)/@Base),2) END IVA) t;
 DECLARE @S DECIMAL(19,2),@D DECIMAL(19,2),@I DECIMAL(19,2),@Total DECIMAL(19,2);
 SELECT @S=SUM(Subtotal),@D=SUM(Descuento),@I=SUM(IVA) FROM @Calculadas;
 SET @Total=@S-@D+@I;
 IF @Total+COALESCE((SELECT SUM(n.Total) FROM dbo.NotaCredito n JOIN dbo.DevolucionCliente d ON d.DevolucionId=n.DevolucionId WHERE d.FacturaId=@FacturaId),0)>@TotalFactura
 THROW 54605,'Credito superior a la factura.',1;
 INSERT dbo.DevolucionCliente(OperacionId,FacturaId,UsuarioId,Motivo,SolicitudHash) VALUES(@OperacionId,@FacturaId,@ActorUsuarioId,@Motivo,@Hash);
 SET @Id=CONVERT(INT,SCOPE_IDENTITY());
 INSERT dbo.DetalleDevolucion(DevolucionId,DetalleFacturaId,Cantidad,Reingresar,Subtotal,Descuento,IVA)
 SELECT @Id,DetalleFacturaId,Cantidad,Reingresar,Subtotal,Descuento,IVA FROM @Calculadas;
 INSERT dbo.NotaCredito(DevolucionId,Subtotal,Descuento,IVA,Total) VALUES(@Id,@S,@D,@I,@Total);
 INSERT dbo.Bitacora_Transacciones(TablaAfectada,Operacion,IdentificadorRegistro,ValorNuevo,ActorUsuarioId,OperacionId,Motivo)
 VALUES(N'DevolucionCliente','INSERT',CONVERT(NVARCHAR(20),@Id),
 (SELECT @FacturaId FacturaId,@Total Total,@Canon Detalles FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),@ActorUsuarioId,@OperacionId,@Motivo);
 IF @Propia=1 COMMIT TRANSACTION;
 SELECT @Id DevolucionId,NotaCreditoId FROM dbo.NotaCredito WHERE DevolucionId=@Id;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
  THROW;
 END CATCH;
END;
GO
