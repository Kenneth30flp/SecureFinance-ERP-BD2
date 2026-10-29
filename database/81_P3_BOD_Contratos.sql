SET NOCOUNT ON; SET XACT_ABORT ON; SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON;
IF DB_NAME() COLLATE Latin1_General_100_BIN2<>N'SecureFinanceERP_Lab_Dylan' OR DATALENGTH(DB_NAME())<>DATALENGTH(N'SecureFinanceERP_Lab_Dylan') OR @@TRANCOUNT=0 OR XACT_STATE()<>1 THROW 58000,'Laboratorio y transaccion externa requeridos.',1;
EXEC(N'CREATE OR ALTER PROCEDURE dbo.P3_BOD_Autorizar @ActorUsuarioId INT,@Permiso NVARCHAR(100)
AS
BEGIN
 SET NOCOUNT ON;
 IF DB_NAME() COLLATE Latin1_General_100_BIN2<>N''SecureFinanceERP_Lab_Dylan'' OR DATALENGTH(DB_NAME())<>DATALENGTH(N''SecureFinanceERP_Lab_Dylan'') THROW 58000,''Base no autorizada para Mod5.'',1;
 IF @Permiso IS NULL OR @Permiso NOT IN(N''BODEGAS_CONSULTAR'',N''BODEGAS_ADMINISTRAR'',N''TRANSFERENCIAS_CREAR'',N''TRANSFERENCIAS_DESPACHAR'',N''TRANSFERENCIAS_RECIBIR'',N''INVENTARIO_REGISTRAR'',N''COTIZACIONES_CONVERTIR'',N''VENTAS_REGISTRAR'') THROW 58002,''Permiso invalido.'',1;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,@Permiso;
END;');
-- Helpers internos: sin GRANT al usuario de aplicacion.
EXEC(N'CREATE OR ALTER PROCEDURE dbo.P3_BOD_ValidarBodegaVenta
 @ActorUsuarioId INT,@BodegaId INT
AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.P3_BOD_Autorizar @ActorUsuarioId,N''BODEGAS_CONSULTAR'';
 IF @BodegaId IS NULL OR @BodegaId<=0 THROW 58002,''Identificador de bodega invalido.'',1;
 -- Solo validacion; no retener locks de ubicacion antes de cotizacion/credito/Producto.
 IF NOT EXISTS(SELECT 1 FROM dbo.P3_BOD_Bodega WITH(READCOMMITTEDLOCK) WHERE BodegaId=@BodegaId AND Activo=1)
 THROW 58004,''Bodega inexistente o inactiva.'',1;
END;');
EXEC(N'CREATE OR ALTER PROCEDURE dbo.P3_BOD_Reintento
 @ActorUsuarioId INT,@OperacionId UNIQUEIDENTIFIER,@Carga NVARCHAR(MAX),@Respuesta NVARCHAR(MAX) OUTPUT
AS
BEGIN
 SET NOCOUNT ON;
 IF @@TRANCOUNT=0 OR @OperacionId IS NULL OR ISJSON(@Carga)<>1 THROW 58002,''Operacion invalida.'',1;
 DECLARE @R NVARCHAR(255)=CONCAT(N''P3_BOD.OP.'',@OperacionId),@L INT;
 EXEC @L=sys.sp_getapplock @Resource=@R,@LockMode=''Exclusive'',@LockOwner=''Transaction'',@LockTimeout=10000;
 IF @L<0 THROW 58003,''Operacion ocupada.'',1;
 SET @Respuesta=NULL;
 SELECT @Respuesta=Respuesta FROM dbo.P3_BOD_Operacion WHERE OperacionId=@OperacionId;
 IF @Respuesta IS NOT NULL AND NOT EXISTS(SELECT 1 FROM dbo.P3_BOD_Operacion WHERE OperacionId=@OperacionId AND ActorUsuarioId=@ActorUsuarioId AND CONVERT(VARBINARY(MAX),Carga)=CONVERT(VARBINARY(MAX),@Carga)) THROW 58003,''Referencia utilizada con otra carga o actor.'',1;
END;');
EXEC(N'CREATE OR ALTER PROCEDURE dbo.P3_BOD_BloquearUbicaciones
 @ProductoId INT,@OrigenId INT,@DestinoId INT
AS
BEGIN
 SET NOCOUNT ON;
 -- El llamador YA posee UPDLOCK/HOLDLOCK del Producto. Orden puntual, no ORDER BY sobre UPDATE.
 DECLARE @A INT=CASE WHEN @OrigenId<@DestinoId THEN @OrigenId ELSE @DestinoId END,
 @B INT=CASE WHEN @OrigenId<@DestinoId THEN @DestinoId ELSE @OrigenId END,@Activo BIT;
 SELECT @Activo=Activo FROM dbo.P3_BOD_Bodega WITH(HOLDLOCK) WHERE BodegaId=@A;
 IF ISNULL(@Activo,0)=0 THROW 58004,''Bodega inexistente o inactiva.'',1;
 SET @Activo=NULL;
 SELECT @Activo=Activo FROM dbo.P3_BOD_Bodega WITH(HOLDLOCK) WHERE BodegaId=@B;
 IF ISNULL(@Activo,0)=0 THROW 58004,''Bodega inexistente o inactiva.'',1;
 IF NOT EXISTS(SELECT 1 FROM dbo.P3_BOD_Stock WITH(UPDLOCK,HOLDLOCK) WHERE ProductoId=@ProductoId AND BodegaId=@A)
 INSERT dbo.P3_BOD_Stock(ProductoId,BodegaId,Cantidad) VALUES(@ProductoId,@A,0);
 IF NOT EXISTS(SELECT 1 FROM dbo.P3_BOD_Stock WITH(UPDLOCK,HOLDLOCK) WHERE ProductoId=@ProductoId AND BodegaId=@B)
 INSERT dbo.P3_BOD_Stock(ProductoId,BodegaId,Cantidad) VALUES(@ProductoId,@B,0);
END;');
EXEC(N'CREATE OR ALTER PROCEDURE dbo.P3_BOD_ValidarSaldo @ProductoId INT
AS
BEGIN
 SET NOCOUNT ON;
 -- Solo llamar con el bloqueo de Producto ya adquirido por el escritor.
 IF NOT EXISTS(SELECT 1 FROM dbo.Producto p
 OUTER APPLY(SELECT SUM(CONVERT(BIGINT,Cantidad)) Local FROM dbo.P3_BOD_Stock WHERE ProductoId=p.ProductoId) s
 OUTER APPLY(SELECT SUM(CONVERT(BIGINT,Cantidad)) Transito FROM dbo.P3_BOD_Transferencia WHERE ProductoId=p.ProductoId AND Estado=''DESPACHADA'') t
 WHERE p.ProductoId=@ProductoId AND CONVERT(BIGINT,p.Stock)=COALESCE(s.Local,0)+COALESCE(t.Transito,0))
 THROW 58005,''Existencias locales y globales sin conciliar.'',1;
END;');
EXEC(N'CREATE OR ALTER TRIGGER dbo.P3_BOD_LedgerInmutable ON dbo.P3_BOD_Ledger AFTER UPDATE,DELETE AS
BEGIN SET NOCOUNT ON; IF EXISTS(SELECT 1 FROM deleted) THROW 58006,''Ledger local inmutable.'',1; END;');
EXEC(N'CREATE OR ALTER TRIGGER dbo.P3_BOD_OperacionInmutable ON dbo.P3_BOD_Operacion AFTER UPDATE,DELETE AS
BEGIN SET NOCOUNT ON; IF EXISTS(SELECT 1 FROM deleted) THROW 58006,''Libro de operaciones inmutable.'',1; END;');
EXEC(N'CREATE OR ALTER TRIGGER dbo.P3_BOD_SnapshotInmutable ON dbo.P3_BOD_Snapshot AFTER UPDATE,DELETE AS
BEGIN SET NOCOUNT ON; IF EXISTS(SELECT 1 FROM deleted) THROW 58006,''Snapshot inicial inmutable.'',1; END;');
EXEC(N'CREATE OR ALTER TRIGGER dbo.P3_BOD_TransferenciaIdentidad ON dbo.P3_BOD_Transferencia AFTER UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM deleted d LEFT JOIN inserted i ON i.TransferenciaId=d.TransferenciaId
 WHERE i.TransferenciaId IS NULL OR i.ProductoId<>d.ProductoId OR i.OrigenId<>d.OrigenId OR i.DestinoId<>d.DestinoId
 OR i.Cantidad<>d.Cantidad OR i.ActorUsuarioId<>d.ActorUsuarioId OR i.FechaHora<>d.FechaHora
 OR CONVERT(VARBINARY(MAX),i.Motivo)<>CONVERT(VARBINARY(MAX),d.Motivo)
 OR NOT((d.Estado=''PREPARADA'' AND i.Estado=''DESPACHADA'') OR (d.Estado=''DESPACHADA'' AND i.Estado=''RECIBIDA'')))
 THROW 58006,''Transferencia inmutable salvo avance de fase.'',1;
END;');
