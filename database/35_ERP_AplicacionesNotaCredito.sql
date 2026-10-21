SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
IF OBJECT_ID('dbo.NotaCredito','U') IS NULL THROW 54800,'Requiere migraciones Edward.',1;
BEGIN TRY
 BEGIN TRANSACTION;
 -- La restriccion original tiene nombre generado por SQL Server.
 DECLARE @Sql NVARCHAR(MAX)=N'';
 -- No quitar una restriccion adicional desconocida que tambien use esta columna.
 DECLARE @Def NVARCHAR(MAX);
 DECLARE checksCredito CURSOR LOCAL FAST_FORWARD FOR
 SELECT LOWER(definition) FROM sys.check_constraints WHERE parent_object_id=OBJECT_ID('dbo.NotaCredito') AND definition LIKE '%EstadoCredito%';
 OPEN checksCredito;FETCH NEXT FROM checksCredito INTO @Def;
 WHILE @@FETCH_STATUS=0
 BEGIN
 SET @Def=REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(@Def,N'estadocredito',N''),N'''pendiente''',N''),N'''parcial''',N''),N'''liquidada''',N''),N'[',N''),N']',N''),N'(',N''),N')',N''),N' ',N''),N'=',N''),N',',N''),N'or',N''),CHAR(13),N''),CHAR(10),N'');
 SET @Def=REPLACE(@Def,N'in',N'');
 IF LEN(@Def)>0 THROW 54800,'Restriccion de credito desconocida: revisar sin eliminarla.',1;
 FETCH NEXT FROM checksCredito INTO @Def;
 END;
 CLOSE checksCredito;DEALLOCATE checksCredito;
 SELECT @Sql=@Sql+N'ALTER TABLE dbo.NotaCredito DROP CONSTRAINT '+QUOTENAME(c.name)+N';'
 FROM sys.check_constraints c WHERE c.parent_object_id=OBJECT_ID('dbo.NotaCredito')
 AND c.definition LIKE '%EstadoCredito%';
 EXEC sys.sp_executesql @Sql;
 ALTER TABLE dbo.NotaCredito WITH CHECK ADD CONSTRAINT CK_ERP_EstadoCredito CHECK(EstadoCredito IN('PENDIENTE','PARCIAL','LIQUIDADA'));
 IF OBJECT_ID('dbo.AplicacionNotaCredito','U') IS NULL
 CREATE TABLE dbo.AplicacionNotaCredito(
  AplicacionId BIGINT IDENTITY PRIMARY KEY,
  NotaCreditoId INT NOT NULL REFERENCES dbo.NotaCredito(NotaCreditoId),
  OperacionId UNIQUEIDENTIFIER NOT NULL UNIQUE,
  Monto DECIMAL(19,2) NOT NULL CHECK(Monto>0),
  SaldoPrevio DECIMAL(19,2) NOT NULL,
  SaldoFinal DECIMAL(19,2) NOT NULL,
  Tipo VARCHAR(30) NOT NULL CHECK(Tipo='REEMBOLSO_DOCUMENTADO'),
  ReferenciaDocumental NVARCHAR(100) NOT NULL CHECK(LEN(LTRIM(RTRIM(ReferenciaDocumental)))>0),
  UsuarioId INT NOT NULL REFERENCES dbo.Usuario(UsuarioId),
  FechaHora DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
  CHECK(SaldoFinal>=0 AND SaldoPrevio-Monto=SaldoFinal)
 );
 IF ISNULL(COL_LENGTH('dbo.AplicacionNotaCredito','OperacionId'),-1)<>16
 OR ISNULL(COL_LENGTH('dbo.AplicacionNotaCredito','NotaCreditoId'),-1)<>4
 OR NOT EXISTS(SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID('dbo.AplicacionNotaCredito') AND referenced_object_id=OBJECT_ID('dbo.NotaCredito') AND is_disabled=0 AND is_not_trusted=0)
 THROW 54800,'Libro de aplicaciones incompatible: revisar sin eliminar datos.',1;
 IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.AplicacionNotaCredito') AND name='IX_AplicacionNC_Nota')
 CREATE INDEX IX_AplicacionNC_Nota ON dbo.AplicacionNotaCredito(NotaCreditoId,AplicacionId) INCLUDE(Monto);
 -- Una nota de importe cero no tiene saldo que pueda aplicarse.
 DECLARE @Cero TABLE(NotaCreditoId INT);
 UPDATE dbo.NotaCredito SET EstadoCredito='LIQUIDADA' OUTPUT inserted.NotaCreditoId INTO @Cero WHERE Total=0 AND EstadoCredito='PENDIENTE';
 INSERT dbo.Bitacora_Transacciones(TablaAfectada,Operacion,IdentificadorRegistro,ValorAnterior,ValorNuevo,OperacionId,Motivo)
 SELECT N'NotaCredito','UPDATE',CONVERT(NVARCHAR(20),NotaCreditoId),N'PENDIENTE',N'LIQUIDADA',NEWID(),N'Migracion 35: nota de importe cero, sin saldo aplicable' FROM @Cero;
 COMMIT;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK;
 THROW;
END CATCH;
GO
CREATE OR ALTER TRIGGER dbo.tr_ERP_NotaCreditoSaldoCero ON dbo.NotaCredito AFTER INSERT AS
BEGIN
 SET NOCOUNT ON;
 UPDATE n SET EstadoCredito='LIQUIDADA' FROM dbo.NotaCredito n JOIN inserted i ON i.NotaCreditoId=n.NotaCreditoId WHERE i.Total=0;
 INSERT dbo.Bitacora_Transacciones(TablaAfectada,Operacion,IdentificadorRegistro,ValorNuevo,ActorUsuarioId,OperacionId,Motivo)
 SELECT N'NotaCredito','INSERT',CONVERT(NVARCHAR(20),i.NotaCreditoId),N'EMITIDA / LIQUIDADA / saldo 0',d.UsuarioId,d.OperacionId,N'Nota emitida con importe cero; sin reembolso'
 FROM inserted i JOIN dbo.DevolucionCliente d ON d.DevolucionId=i.DevolucionId WHERE i.Total=0;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_RegistrarAplicacionNotaCredito
 @ActorUsuarioId INT,@NotaCreditoId INT,@Monto DECIMAL(19,2),@ReferenciaDocumental NVARCHAR(100),@OperacionId UNIQUEIDENTIFIER AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
 BEGIN TRANSACTION;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'NOTAS_CREDITO_APLICAR';
 IF @OperacionId IS NULL OR @Monto IS NULL OR @Monto<=0 OR NULLIF(LTRIM(RTRIM(@ReferenciaDocumental)),N'') IS NULL
 THROW 54802,'Aplicacion invalida.',1;
 DECLARE @Lock INT,@Resource NVARCHAR(255)=CONCAT(N'ERP.Credito.',@OperacionId),@Id BIGINT,@Total DECIMAL(19,2),@Saldo DECIMAL(19,2);
 EXEC @Lock=sys.sp_getapplock @Resource=@Resource,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
 IF @Lock<0 THROW 54803,'Operacion ocupada.',1;
 SELECT @Id=AplicacionId FROM dbo.AplicacionNotaCredito WITH(UPDLOCK,HOLDLOCK) WHERE OperacionId=@OperacionId;
 IF @Id IS NOT NULL
 BEGIN
 IF NOT EXISTS(SELECT 1 FROM dbo.AplicacionNotaCredito WHERE AplicacionId=@Id AND NotaCreditoId=@NotaCreditoId
 AND Monto=@Monto AND UsuarioId=@ActorUsuarioId
 AND ReferenciaDocumental COLLATE Latin1_General_100_BIN2=@ReferenciaDocumental COLLATE Latin1_General_100_BIN2
 AND DATALENGTH(ReferenciaDocumental)=DATALENGTH(@ReferenciaDocumental)) THROW 54803,'Operacion utilizada con otros datos.',1;
 END
 ELSE
 BEGIN
 SELECT @Total=Total FROM dbo.NotaCredito WITH(UPDLOCK,HOLDLOCK) WHERE NotaCreditoId=@NotaCreditoId AND Estado='EMITIDA';
 IF @Total IS NULL THROW 54802,'Nota inexistente.',1;
 SELECT @Saldo=@Total-COALESCE(SUM(Monto),0) FROM dbo.AplicacionNotaCredito WHERE NotaCreditoId=@NotaCreditoId;
 IF @Monto>@Saldo THROW 54804,'El monto supera el saldo disponible.',1;
 INSERT dbo.AplicacionNotaCredito(NotaCreditoId,OperacionId,Monto,SaldoPrevio,SaldoFinal,Tipo,ReferenciaDocumental,UsuarioId)
 VALUES(@NotaCreditoId,@OperacionId,@Monto,@Saldo,@Saldo-@Monto,'REEMBOLSO_DOCUMENTADO',@ReferenciaDocumental,@ActorUsuarioId);
 SET @Id=SCOPE_IDENTITY();
 UPDATE dbo.NotaCredito SET EstadoCredito=CASE WHEN @Saldo=@Monto THEN 'LIQUIDADA' ELSE 'PARCIAL' END WHERE NotaCreditoId=@NotaCreditoId;
 INSERT dbo.Bitacora_Transacciones(TablaAfectada,Operacion,IdentificadorRegistro,ValorNuevo,ActorUsuarioId,OperacionId,Motivo)
 VALUES(N'AplicacionNotaCredito','INSERT',CONVERT(NVARCHAR(20),@Id),
 (SELECT @NotaCreditoId NotaCreditoId,@Monto Monto,@Saldo SaldoPrevio,@Saldo-@Monto SaldoFinal,@ReferenciaDocumental ReferenciaDocumental FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),
 @ActorUsuarioId,@OperacionId,N'Reembolso externo documentado; ERP no ejecuta transferencias');
 END;
 SELECT * FROM dbo.AplicacionNotaCredito WHERE AplicacionId=@Id;
 COMMIT;
 END TRY
 BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK;
 THROW;
 END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_ConsultarAplicacionesNotaCredito @ActorUsuarioId INT,@NotaCreditoId INT AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'DEVOLUCIONES_CONSULTAR';
 SELECT n.NotaCreditoId,CONVERT(VARCHAR(30),n.Total-COALESCE(a.Aplicado,0)) SaldoDisponible,n.EstadoCredito
 FROM dbo.NotaCredito n OUTER APPLY(SELECT SUM(Monto) Aplicado FROM dbo.AplicacionNotaCredito WHERE NotaCreditoId=n.NotaCreditoId) a
 WHERE n.NotaCreditoId=@NotaCreditoId;
 SELECT a.AplicacionId,a.NotaCreditoId,a.OperacionId,CONVERT(VARCHAR(30),a.Monto) Monto,
 CONVERT(VARCHAR(30),a.SaldoPrevio) SaldoPrevio,CONVERT(VARCHAR(30),a.SaldoFinal) SaldoFinal,
 a.Tipo,a.ReferenciaDocumental,a.FechaHora,u.NombreUsuario Responsable FROM dbo.AplicacionNotaCredito a JOIN dbo.Usuario u ON u.UsuarioId=a.UsuarioId
 WHERE a.NotaCreditoId=@NotaCreditoId ORDER BY a.AplicacionId;
END;
GO
CREATE OR ALTER TRIGGER dbo.tr_ERP_AplicacionesInmutables ON dbo.AplicacionNotaCredito INSTEAD OF UPDATE,DELETE AS
BEGIN
 THROW 54805,'El libro de aplicaciones es inmutable.',1;
END;
GO
