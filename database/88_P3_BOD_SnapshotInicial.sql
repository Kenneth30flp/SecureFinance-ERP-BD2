-- Corte NUEVO de ubicaciones, no historia reconstruida. No habilita Kardex global.
SET NOCOUNT ON; SET XACT_ABORT ON; SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON;
IF DB_NAME() COLLATE Latin1_General_100_BIN2<>dbo.P3_INT_Destino() OR DATALENGTH(DB_NAME())<>DATALENGTH(dbo.P3_INT_Destino()) OR @@TRANCOUNT=0 OR XACT_STATE()<>1 THROW 58000,'Laboratorio y transaccion externa requeridos.',1;
IF EXISTS(SELECT 1 FROM dbo.P3_BOD_Configuracion) OR EXISTS(SELECT 1 FROM dbo.P3_BOD_Snapshot)
 OR EXISTS(SELECT 1 FROM dbo.P3_BOD_Bodega) OR EXISTS(SELECT 1 FROM dbo.P3_BOD_Stock) THROW 58000,'Snapshot inicial unico; no sobreescribir.',1;
DECLARE @N BIGINT,@Central INT,@Snapshot UNIQUEIDENTIFIER=NEWID(),@Fecha DATETIME2(3);
SELECT @N=COUNT_BIG(*) FROM dbo.Producto WITH(TABLOCKX,HOLDLOCK);
SET @Fecha=SYSUTCDATETIME();
-- Son datos iniciales editables por administracion, nunca condiciones de negocio.
INSERT dbo.P3_BOD_Bodega(Nombre,IsCentral) VALUES(N'Bodega Central',1);
SET @Central=CONVERT(INT,SCOPE_IDENTITY());
INSERT dbo.P3_BOD_Bodega(Nombre) VALUES(N'Tienda Z1'),(N'Tienda Z10');
INSERT dbo.P3_BOD_Configuracion(ConfiguracionId,CentralId,SnapshotId,FechaSnapshot) VALUES(1,@Central,@Snapshot,@Fecha);
INSERT dbo.P3_BOD_Snapshot(ProductoId,BodegaId,Cantidad,SnapshotId,FechaHora) SELECT ProductoId,@Central,Stock,@Snapshot,@Fecha FROM dbo.Producto;
INSERT dbo.P3_BOD_Stock(ProductoId,BodegaId,Cantidad) SELECT ProductoId,@Central,Stock FROM dbo.Producto;
-- CERO INSERT global Kardex, CERO UPDATE Producto/ConfiguracionInventario.
