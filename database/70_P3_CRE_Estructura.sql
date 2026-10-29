-- LAB ONLY. All 70-77 GO batches MUST share ONE external transaction, stop on first error.
-- No USE, no automatic COMMIT. See docs/parte3/creditos/README.md. NOT EXECUTED.
SET XACT_ABORT ON; SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON;
IF DB_NAME() <> N'SecureFinanceERP_Lab_Dylan' OR @@TRANCOUNT=0
 THROW 57000,'Requiere SecureFinanceERP_Lab_Dylan y transaccion externa; abortar todos los batches.',1;
IF OBJECT_ID('dbo.P3_COT_ValidarOrigen','P') IS NULL OR OBJECT_ID('dbo.FacturaProductoEmision','U') IS NULL
 OR OBJECT_ID('dbo.sp_ParteII_ValidarPermiso','P') IS NULL
 THROW 57000,'Requiere 21,39,40,41-43 y usuario de aplicacion existentes.',1;
IF OBJECT_ID('dbo.Credito_Cliente','U') IS NOT NULL
 THROW 57000,'70 es de una sola instalacion; revisar version sin destruir datos.',1;
CREATE TABLE dbo.Credito_Cliente(
 ClienteId INT NOT NULL CONSTRAINT P3_CRE_PK_Credito PRIMARY KEY CONSTRAINT P3_CRE_FK_CreditoCliente REFERENCES dbo.Cliente(ClienteId),
 Activo BIT NOT NULL,Limite DECIMAL(19,2) NOT NULL,PlazoDias INT NOT NULL,
 Version ROWVERSION NOT NULL,
 CONSTRAINT P3_CRE_CK_Credito CHECK(Limite>0 AND PlazoDias BETWEEN 1 AND 3650)
);
CREATE TABLE dbo.P3_CRE_Cuenta(
 FacturaId INT NOT NULL CONSTRAINT P3_CRE_PK_Cuenta PRIMARY KEY CONSTRAINT P3_CRE_FK_CuentaFactura REFERENCES dbo.Factura(FacturaId),
 ClienteId INT NOT NULL CONSTRAINT P3_CRE_FK_CuentaCliente REFERENCES dbo.Credito_Cliente(ClienteId),
 Total DECIMAL(19,2) NOT NULL,Saldo DECIMAL(19,2) NOT NULL,
 FechaHora DATETIME2(3) NOT NULL,PlazoDias INT NOT NULL,NumeroCuotas INT NOT NULL,
 CONSTRAINT P3_CRE_CK_Cuenta CHECK(Total>0 AND Saldo BETWEEN 0 AND Total AND PlazoDias BETWEEN 1 AND 3650 AND NumeroCuotas BETWEEN 1 AND 120 AND NumeroCuotas<=PlazoDias)
);
CREATE INDEX P3_CRE_IX_CuentaCliente ON dbo.P3_CRE_Cuenta(ClienteId,FacturaId) INCLUDE(Saldo);
CREATE TABLE dbo.P3_CRE_Cuota(
 FacturaId INT NOT NULL CONSTRAINT P3_CRE_FK_CuotaCuenta REFERENCES dbo.P3_CRE_Cuenta(FacturaId),Numero INT NOT NULL,
 VenceEn DATETIME2(3) NOT NULL,Importe DECIMAL(19,2) NOT NULL,Abonado DECIMAL(19,2) NOT NULL CONSTRAINT P3_CRE_DF_CuotaAbonado DEFAULT 0,
 CONSTRAINT P3_CRE_PK_Cuota PRIMARY KEY(FacturaId,Numero),
 CONSTRAINT P3_CRE_CK_Cuota CHECK(Numero>0 AND Importe>0 AND Abonado BETWEEN 0 AND Importe)
);
CREATE TABLE dbo.P3_CRE_Operacion(
 OperacionId UNIQUEIDENTIFIER NOT NULL CONSTRAINT P3_CRE_PK_Operacion PRIMARY KEY,
 SolicitudHash BINARY(32) NOT NULL,Resultado NVARCHAR(MAX) NOT NULL CONSTRAINT P3_CRE_CK_OperacionJson CHECK(ISJSON(Resultado)=1),
 FechaHora DATETIME2(3) NOT NULL CONSTRAINT P3_CRE_DF_OperacionFecha DEFAULT SYSUTCDATETIME()
);
CREATE TABLE dbo.Abono_Factura(
 AbonoId BIGINT IDENTITY NOT NULL CONSTRAINT P3_CRE_PK_Abono PRIMARY KEY,
 OperacionId UNIQUEIDENTIFIER NOT NULL CONSTRAINT P3_CRE_UQ_AbonoOperacion UNIQUE,
 SolicitudHash BINARY(32) NOT NULL,FacturaId INT NOT NULL CONSTRAINT P3_CRE_FK_AbonoCuenta REFERENCES dbo.P3_CRE_Cuenta(FacturaId),
 ClienteId INT NOT NULL CONSTRAINT P3_CRE_FK_AbonoCliente REFERENCES dbo.Credito_Cliente(ClienteId),ActorUsuarioId INT NOT NULL CONSTRAINT P3_CRE_FK_AbonoActor REFERENCES dbo.Usuario(UsuarioId),
 Monto DECIMAL(19,2) NOT NULL CONSTRAINT P3_CRE_CK_AbonoMonto CHECK(Monto>0),Referencia NVARCHAR(100) NOT NULL,
 FechaHora DATETIME2(3) NOT NULL,SaldoPosterior DECIMAL(19,2) NOT NULL CONSTRAINT P3_CRE_CK_AbonoSaldo CHECK(SaldoPosterior>=0)
);
CREATE TABLE dbo.P3_CRE_ReciboCaja(
 ReciboId BIGINT IDENTITY NOT NULL CONSTRAINT P3_CRE_PK_Recibo PRIMARY KEY,
 AbonoId BIGINT NOT NULL CONSTRAINT P3_CRE_UQ_ReciboAbono UNIQUE CONSTRAINT P3_CRE_FK_ReciboAbono REFERENCES dbo.Abono_Factura(AbonoId),
 Monto DECIMAL(19,2) NOT NULL CONSTRAINT P3_CRE_CK_ReciboMonto CHECK(Monto>0),FechaHora DATETIME2(3) NOT NULL
);
CREATE TABLE dbo.P3_CRE_AplicacionCuota(
 AbonoId BIGINT NOT NULL CONSTRAINT P3_CRE_FK_AplicacionAbono REFERENCES dbo.Abono_Factura(AbonoId),FacturaId INT NOT NULL,Numero INT NOT NULL,
 Monto DECIMAL(19,2) NOT NULL CONSTRAINT P3_CRE_CK_AplicacionMonto CHECK(Monto>0),
 CONSTRAINT P3_CRE_PK_Aplicacion PRIMARY KEY(AbonoId,FacturaId,Numero),
 CONSTRAINT P3_CRE_FK_AplicacionCuota FOREIGN KEY(FacturaId,Numero) REFERENCES dbo.P3_CRE_Cuota(FacturaId,Numero)
);
CREATE TABLE dbo.P3_CRE_Historial(
 HistorialId BIGINT IDENTITY NOT NULL CONSTRAINT P3_CRE_PK_Historial PRIMARY KEY,
 ClienteId INT NOT NULL CONSTRAINT P3_CRE_FK_HistorialCliente REFERENCES dbo.Cliente(ClienteId),FacturaId INT NULL CONSTRAINT P3_CRE_FK_HistorialFactura REFERENCES dbo.Factura(FacturaId),
 Evento VARCHAR(20) NOT NULL,ActorUsuarioId INT NOT NULL CONSTRAINT P3_CRE_FK_HistorialActor REFERENCES dbo.Usuario(UsuarioId),
 OperacionId UNIQUEIDENTIFIER NOT NULL,Motivo NVARCHAR(250) NOT NULL,
 Antes NVARCHAR(MAX) NULL,Despues NVARCHAR(MAX) NOT NULL,
 FechaHora DATETIME2(3) NOT NULL CONSTRAINT P3_CRE_DF_HistorialFecha DEFAULT SYSUTCDATETIME()
);
GO
CREATE OR ALTER PROCEDURE dbo.P3_CRE_ValidarEntorno AS
BEGIN
 IF DB_NAME() <> N'SecureFinanceERP_Lab_Dylan' THROW 57000,'Credito habilitado solo en laboratorio Dylan.',1;
END;
GO
CREATE OR ALTER PROCEDURE dbo.P3_CRE_Auditar
 @ClienteId INT,@FacturaId INT,@Evento VARCHAR(20),@ActorUsuarioId INT,@OperacionId UNIQUEIDENTIFIER,
 @Motivo NVARCHAR(250),@Antes NVARCHAR(MAX),@Despues NVARCHAR(MAX)
AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.P3_CRE_ValidarEntorno;
 IF @@TRANCOUNT=0 THROW 57000,'Auditoria requiere transaccion.',1;
 INSERT dbo.P3_CRE_Historial(ClienteId,FacturaId,Evento,ActorUsuarioId,OperacionId,Motivo,Antes,Despues)
 VALUES(@ClienteId,@FacturaId,@Evento,@ActorUsuarioId,@OperacionId,@Motivo,@Antes,@Despues);
 INSERT dbo.Bitacora_Transacciones(TablaAfectada,Operacion,IdentificadorRegistro,ValorAnterior,ValorNuevo,ActorUsuarioId,OperacionId,Motivo)
 VALUES(N'P3_CRE_Historial','INSERT',CONVERT(NVARCHAR(20),SCOPE_IDENTITY()),@Antes,@Despues,@ActorUsuarioId,@OperacionId,@Motivo);
END;
GO
