-- Edward: cobertura futura por detalle; nunca reconstruye cobertura de ventas antiguas.
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
IF OBJECT_ID('dbo.NotaCredito','U') IS NULL THROW 54600,'Requiere migracion 24.',1;
BEGIN TRANSACTION;
IF OBJECT_ID('dbo.CoberturaGarantiaVenta','U') IS NULL
CREATE TABLE dbo.CoberturaGarantiaVenta(
 DetalleFacturaId INT PRIMARY KEY REFERENCES dbo.DetalleFactura(DetalleFacturaId),
 GarantiaMeses SMALLINT NULL CHECK(GarantiaMeses>=0),
 FechaVencimiento DATETIME2(3) NULL
);
IF OBJECT_ID('dbo.Ticket_Garantia','U') IS NULL
BEGIN
 CREATE TABLE dbo.Ticket_Garantia(
 TicketId INT IDENTITY PRIMARY KEY,
 OperacionId UNIQUEIDENTIFIER NOT NULL UNIQUE,
 DetalleFacturaId INT NOT NULL REFERENCES dbo.DetalleFactura(DetalleFacturaId),
 Motivo NVARCHAR(250) NOT NULL CHECK(LEN(LTRIM(RTRIM(Motivo)))>0),
 Estado VARCHAR(15) NOT NULL DEFAULT 'RECIBIDO' CHECK(Estado IN('RECIBIDO','EN_REVISION','APROBADO','RECHAZADO','ENTREGADO')),
 ResponsableId INT NOT NULL REFERENCES dbo.Usuario(UsuarioId),
 FechaApertura DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 FechaResolucion DATETIME2(3) NULL,
 Cobertura VARCHAR(20) NOT NULL CHECK(Cobertura IN('VIGENTE','VENCIDA','SIN_COBERTURA','NO_VERIFICADA')),
 Evidencia NVARCHAR(250) NULL,
 Version ROWVERSION);
 CREATE INDEX IX_Ticket_EstadoFecha ON dbo.Ticket_Garantia(Estado,FechaApertura) INCLUDE(DetalleFacturaId,ResponsableId,FechaResolucion);
END;
IF OBJECT_ID('dbo.Historial_Garantia','U') IS NULL
BEGIN
 CREATE TABLE dbo.Historial_Garantia(
 HistorialId BIGINT IDENTITY PRIMARY KEY,
 TicketId INT NOT NULL REFERENCES dbo.Ticket_Garantia(TicketId),
 EstadoAnterior VARCHAR(15) NULL,
 EstadoNuevo VARCHAR(15) NOT NULL CHECK(EstadoNuevo IN('RECIBIDO','EN_REVISION','APROBADO','RECHAZADO','ENTREGADO')),
 FechaHora DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 UsuarioId INT NOT NULL REFERENCES dbo.Usuario(UsuarioId),
 Diagnostico NVARCHAR(2000) NOT NULL CHECK(LEN(LTRIM(RTRIM(Diagnostico)))>0));
 CREATE INDEX IX_Historial_Ticket ON dbo.Historial_Garantia(TicketId,HistorialId);
END;
COMMIT;
GO
CREATE OR ALTER TRIGGER dbo.tr_DetalleFactura_CoberturaGarantia ON dbo.DetalleFactura AFTER INSERT AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.CoberturaGarantiaVenta(DetalleFacturaId,GarantiaMeses,FechaVencimiento)
 SELECT i.DetalleFacturaId,p.GarantiaMeses,
 CASE WHEN p.GarantiaMeses IS NOT NULL THEN DATEADD(MONTH,p.GarantiaMeses,f.FechaHora) END
 FROM inserted i JOIN dbo.Producto p WITH(HOLDLOCK) ON p.ProductoId=i.ProductoId JOIN dbo.Factura f ON f.FacturaId=i.FacturaId;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_CrearTicketGarantia
 @ActorUsuarioId INT,@DetalleFacturaId INT,@OperacionId UNIQUEIDENTIFIER,@Motivo NVARCHAR(MAX)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 DECLARE @Propia BIT=CASE WHEN @@TRANCOUNT=0 THEN 1 ELSE 0 END;
 BEGIN TRY
 IF @Propia=1 BEGIN TRANSACTION;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'GARANTIAS_GESTIONAR';
 IF @OperacionId IS NULL OR @Motivo IS NULL OR LEN(LTRIM(RTRIM(@Motivo)))=0 OR DATALENGTH(@Motivo)>500 THROW 54602,'Datos de ticket invalidos.',1;
 DECLARE @Lock INT,@Resource NVARCHAR(255)=CONCAT(N'Edward.Ticket.',@OperacionId),@Id INT;
 EXEC @Lock=sys.sp_getapplock @Resource=@Resource,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
 IF @Lock<0 THROW 54603,'Solicitud ocupada.',1;
 SELECT @Id=TicketId FROM dbo.Ticket_Garantia WITH(UPDLOCK,HOLDLOCK) WHERE OperacionId=@OperacionId;
 IF @Id IS NOT NULL
 BEGIN
 IF NOT EXISTS(SELECT 1 FROM dbo.Ticket_Garantia t JOIN dbo.Historial_Garantia h ON h.TicketId=t.TicketId AND h.EstadoAnterior IS NULL
 WHERE t.TicketId=@Id AND t.DetalleFacturaId=@DetalleFacturaId AND h.UsuarioId=@ActorUsuarioId
 AND CONVERT(VARBINARY(MAX),t.Motivo)=CONVERT(VARBINARY(MAX),@Motivo)) THROW 54603,'Referencia usada con otros datos.',1;
 END
 ELSE
 BEGIN
 IF NOT EXISTS(SELECT 1 FROM dbo.DetalleFactura WHERE DetalleFacturaId=@DetalleFacturaId) THROW 54604,'Detalle de factura inexistente.',1;
 DECLARE @Meses SMALLINT,@Vence DATETIME2(3),@Cobertura VARCHAR(20);
 SELECT @Meses=GarantiaMeses,@Vence=FechaVencimiento FROM dbo.CoberturaGarantiaVenta WHERE DetalleFacturaId=@DetalleFacturaId;
 SET @Cobertura=CASE WHEN @Meses IS NULL THEN 'NO_VERIFICADA' WHEN @Meses=0 THEN 'SIN_COBERTURA' WHEN @Vence<SYSUTCDATETIME() THEN 'VENCIDA' ELSE 'VIGENTE' END;
 INSERT dbo.Ticket_Garantia(OperacionId,DetalleFacturaId,Motivo,ResponsableId,Cobertura) VALUES(@OperacionId,@DetalleFacturaId,@Motivo,@ActorUsuarioId,@Cobertura);
 SET @Id=CONVERT(INT,SCOPE_IDENTITY());
 INSERT dbo.Historial_Garantia(TicketId,EstadoAnterior,EstadoNuevo,UsuarioId,Diagnostico) VALUES(@Id,NULL,'RECIBIDO',@ActorUsuarioId,@Motivo);
 END;
 IF @Propia=1 COMMIT TRANSACTION;
 SELECT TicketId,Version FROM dbo.Ticket_Garantia WHERE TicketId=@Id;
 END TRY
 BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 THROW;
 END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_ActualizarEstadoGarantia
 @ActorUsuarioId INT,@TicketId INT,@VersionEsperada BINARY(8),@Estado VARCHAR(15),
 @Diagnostico NVARCHAR(MAX),@Evidencia NVARCHAR(MAX)=NULL
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 DECLARE @Propia BIT=CASE WHEN @@TRANCOUNT=0 THEN 1 ELSE 0 END;
 BEGIN TRY
 IF @Propia=1 BEGIN TRANSACTION;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'GARANTIAS_GESTIONAR';
 IF @Diagnostico IS NULL OR LEN(LTRIM(RTRIM(@Diagnostico)))=0 OR DATALENGTH(@Diagnostico)>4000 OR DATALENGTH(@Evidencia)>500 THROW 54602,'Diagnostico invalido.',1;
 DECLARE @Anterior VARCHAR(15),@Version BINARY(8),@Cobertura VARCHAR(20);
 SELECT @Anterior=Estado,@Version=Version,@Cobertura=Cobertura FROM dbo.Ticket_Garantia WITH(UPDLOCK,HOLDLOCK) WHERE TicketId=@TicketId;
 IF @Anterior IS NULL THROW 54604,'Ticket inexistente.',1;
 IF @VersionEsperada IS NULL OR @Version<>@VersionEsperada THROW 54603,'El ticket cambio. Recargue antes de guardar; conserve su diagnostico.',1;
 IF @Estado IS NULL OR NOT(
 (@Anterior='RECIBIDO' AND @Estado='EN_REVISION') OR
 (@Anterior='EN_REVISION' AND @Estado IN('APROBADO','RECHAZADO')) OR
 (@Anterior IN('APROBADO','RECHAZADO') AND @Estado='ENTREGADO') OR
 (@Anterior=@Estado AND @Anterior<>'ENTREGADO'))
 THROW 54606,'Transicion no permitida.',1;
 IF @Estado='APROBADO' AND @Cobertura IN('VENCIDA','SIN_COBERTURA') THROW 54606,'La cobertura registrada no permite aprobacion.',1;
 IF @Estado='APROBADO' AND @Cobertura='NO_VERIFICADA' AND NULLIF(LTRIM(RTRIM(@Evidencia)),N'') IS NULL THROW 54606,'La cobertura historica requiere referencia documental verificada.',1;
 UPDATE dbo.Ticket_Garantia SET Estado=@Estado,ResponsableId=@ActorUsuarioId,
 Evidencia=COALESCE(NULLIF(LTRIM(RTRIM(@Evidencia)),N''),Evidencia),
 FechaResolucion=CASE WHEN @Estado='ENTREGADO' THEN SYSUTCDATETIME() ELSE FechaResolucion END WHERE TicketId=@TicketId;
 INSERT dbo.Historial_Garantia(TicketId,EstadoAnterior,EstadoNuevo,UsuarioId,Diagnostico)
 VALUES(@TicketId,@Anterior,@Estado,@ActorUsuarioId,@Diagnostico);
 IF @Propia=1 COMMIT TRANSACTION;
 SELECT TicketId,Version FROM dbo.Ticket_Garantia WHERE TicketId=@TicketId;
 END TRY
 BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 THROW;
 END CATCH;
END;
GO
CREATE OR ALTER TRIGGER dbo.tr_HistorialGarantia_Auditoria ON dbo.Historial_Garantia AFTER INSERT AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.Bitacora_Transacciones(TablaAfectada,Operacion,IdentificadorRegistro,ValorAnterior,ValorNuevo,ActorUsuarioId,OperacionId)
 SELECT N'Ticket_Garantia',CASE WHEN i.EstadoAnterior IS NULL THEN 'INSERT' ELSE 'UPDATE' END,CONVERT(NVARCHAR(20),i.TicketId),
 i.EstadoAnterior,(SELECT i.EstadoNuevo,i.Diagnostico,t.Evidencia FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),i.UsuarioId,t.OperacionId
 FROM inserted i JOIN dbo.Ticket_Garantia t ON t.TicketId=i.TicketId;
END;
GO
CREATE OR ALTER TRIGGER dbo.tr_HistorialGarantia_Inmutable ON dbo.Historial_Garantia AFTER UPDATE,DELETE AS
BEGIN
 IF EXISTS(SELECT 1 FROM deleted) THROW 54606,'Historial inmutable.',1;
END;
GO
