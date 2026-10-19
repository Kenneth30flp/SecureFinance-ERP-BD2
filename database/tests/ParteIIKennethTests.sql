-- SOLO una copia aislada previamente instalada. Nunca ejecutar en SecureFinanceERP.
-- Cada caso crea fixtures en una transaccion que se revierte. No modifica la BD real.
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
SET XACT_ABORT ON;
IF LEFT(DB_NAME(),LEN(N'SecureFinanceERP_ParteII_Test_'))<>N'SecureFinanceERP_ParteII_Test_' THROW 54900,'Nombre de base de pruebas no autorizado.',1;
IF @@TRANCOUNT<>0 THROW 54900,'Ejecutar sin transaccion exterior.',1;
IF DATABASE_PRINCIPAL_ID('securefinance_app') IS NULL THROW 54900,'Falta usuario de pruebas y script 20.',1;
DECLARE @Caso INT=1,@Esperado NVARCHAR(100),@Error INT,@MensajeError NVARCHAR(4000),@Actor INT,@Rol INT,@Prov INT,@P INT,@C INT,@F INT,@N INT,@Permitido INT,@DescripcionCaso NVARCHAR(120),
 @Tag NVARCHAR(32),@SKU NVARCHAR(40),@NitInicial NVARCHAR(25),@NitNuevo NVARCHAR(25),@Op UNIQUEIDENTIFIER,@AperturaPrueba UNIQUEIDENTIFIER,@V BINARY(8),@Detalle dbo.TipoDetalleVentaDescuento;
DECLARE @IntegracionActiva BIT=CASE WHEN OBJECT_ID('dbo.sp_AbrirKardexInventario','P') IS NULL THEN 0 ELSE 1 END;
DECLARE @Descripciones TABLE(Id INT PRIMARY KEY,Descripcion NVARCHAR(120));
INSERT @Descripciones VALUES (1,N'Proveedor registrado'),(2,N'SKU unico'),(3,N'Costo no negativo'),(4,N'Ingreso compra'),(5,N'Egreso y saldo'),(6,N'Stock negativo'),(7,N'Rollback posterior a stock'),(8,N'Reintento identico'),(9,N'Reintento conflictivo'),(10,N'Cambio NIT'),(11,N'NIT duplicado'),(12,N'Inactivacion y factura'),(13,N'Identidad de emision'),(14,N'DML set based y no-op'),(15,N'Permisos minimos'),(16,N'Compatibilidad Parte I'),(17,N'Cliente inactivo no vende'),(18,N'Concurrencia optimista'),(19,N'Fotografia insegura'),(20,N'FK proveedor'),(21,N'RBAC actor'),(22,N'Kardex bloqueado antes de apertura'),(23,N'Kardex inmutable'),(24,N'Snapshot inmutable'),(25,N'NIT vacio'),(26,N'Devolucion preparada'),(27,N'Factura anterior sin reconstruccion'),(28,N'Egreso por venta');
CREATE TABLE #ResultadosKenneth(Id INT PRIMARY KEY,Descripcion NVARCHAR(120),Resultado VARCHAR(4),ErrorEsperado INT NULL,MensajeError NVARCHAR(4000) NULL);
DECLARE @ConsultaProveedor TABLE(ProveedorId INT,NIT NVARCHAR(25),Nombre NVARCHAR(150),Correo NVARCHAR(254),Telefono NVARCHAR(25),Direccion NVARCHAR(300),Fotografia VARCHAR(40),Activo BIT,FechaCreacion DATETIME2(3),Version BINARY(8));
DECLARE @ConsultaProducto TABLE(ProductoId INT,Codigo NVARCHAR(40),Descripcion NVARCHAR(200),Precio DECIMAL(12,2),PrecioCosto DECIMAL(12,2),Stock INT,ProveedorId INT,Fotografia VARCHAR(40),StockMinimo INT,PuntoReorden INT,GarantiaMeses SMALLINT,Activo BIT,FechaCreacion DATETIME2(3),Version BINARY(8));
WHILE @Caso<=28
BEGIN
 SET @Tag=REPLACE(CONVERT(NVARCHAR(36),NEWID()),N'-',N''); SET @SKU=@Tag;
 SET @NitInicial=N'A'+LEFT(@Tag,23); SET @NitNuevo=N'B'+LEFT(@Tag,23); SET @Op=NEWID();
 SET @Error=NULL; SET @MensajeError=NULL; SET @Esperado=NULL; DELETE FROM @Detalle;
 SELECT @DescripcionCaso=Descripcion FROM @Descripciones WHERE Id=@Caso;
 BEGIN TRY
  BEGIN TRANSACTION;
  INSERT dbo.Usuario(NombreUsuario,NombreCompleto,Correo,PasswordHash,Salt) VALUES(@Tag,N'Actor pruebas',@Tag+N'@example.invalid',CRYPT_GEN_RANDOM(64),CRYPT_GEN_RANDOM(32)); SET @Actor=SCOPE_IDENTITY();
  INSERT dbo.Rol(Nombre) VALUES(@Tag); SET @Rol=SCOPE_IDENTITY();
  INSERT dbo.Usuario_Rol(UsuarioId,RolId) VALUES(@Actor,@Rol);
  INSERT dbo.Rol_Permiso(RolId,PermisoId) SELECT @Rol,PermisoId FROM dbo.Permiso WHERE Codigo IN (N'INVENTARIO_REGISTRAR',N'INVENTARIO_AJUSTAR',N'INVENTARIO_CONSULTAR',N'PRODUCTOS_ADMINISTRAR',N'PRODUCTOS_CONSULTAR',N'PROVEEDORES_ADMINISTRAR',N'PROVEEDORES_CONSULTAR',N'CLIENTES_ACTUALIZAR_NIT',N'CLIENTES_INACTIVAR',N'CLIENTES_CONSULTAR',N'VENTAS_REGISTRAR',N'INVENTARIO_APERTURAR');
  EXEC dbo.sp_RegistrarProveedor @ActorUsuarioId=@Actor,@NIT=@NitInicial,@Nombre=N'Proveedor de prueba',@ProveedorId=@Prov OUTPUT;
  EXEC dbo.sp_RegistrarProducto @ActorUsuarioId=@Actor,@Codigo=@SKU,@Descripcion=N'Producto de prueba',@Precio=10,@PrecioCosto=5,@ProveedorId=@Prov,@ProductoId=@P OUTPUT;
  INSERT dbo.Cliente(NIT,Nombre) VALUES(@NitInicial,N'Cliente prueba'); SET @C=SCOPE_IDENTITY();
  IF @IntegracionActiva=1
  BEGIN
   -- El fixture de saldo previo nace ANTES de su apertura; no se altera el libro.
   IF @Caso=16 UPDATE dbo.Producto SET Stock=5 WHERE ProductoId=@P;
   SET @AperturaPrueba=NEWID();
   EXEC dbo.sp_AbrirKardexInventario @AperturaPrueba,@Actor,@Tag,N'Apertura fixture';
   EXEC dbo.sp_HabilitarKardexInventario @AperturaPrueba,@Actor;
  END
  ELSE UPDATE dbo.ConfiguracionInventario SET Habilitado=1 WHERE ConfiguracionId=1;
  IF @Caso=1
  BEGIN
   SET @Esperado=NULL;
   -- Proveedor registrado, consultado y editado; producto editado/consultado.
   DELETE FROM @ConsultaProveedor; DELETE FROM @ConsultaProducto;
   INSERT @ConsultaProveedor EXEC dbo.sp_ConsultarProveedores @ActorUsuarioId=@Actor;
   IF NOT EXISTS(SELECT 1 FROM @ConsultaProveedor WHERE ProveedorId=@Prov AND Nombre=N'Proveedor de prueba') THROW 54900,'Consulta de proveedor incorrecta.',1;
   SELECT @V=Version FROM dbo.Proveedor WHERE ProveedorId=@Prov;
   EXEC dbo.sp_ActualizarProveedor @ActorUsuarioId=@Actor,@NIT=@NitInicial,@Nombre=N'Proveedor editado',@ProveedorId=@Prov,@VersionEsperada=@V;
   IF NOT EXISTS(SELECT 1 FROM dbo.Proveedor WHERE ProveedorId=@Prov AND Nombre=N'Proveedor editado' AND Version<>@V) THROW 54900,'Edicion de proveedor incorrecta.',1;
   SELECT @V=Version FROM dbo.Producto WHERE ProductoId=@P;
   EXEC dbo.sp_ActualizarProducto @ActorUsuarioId=@Actor,@Codigo=@SKU,@Descripcion=N'Producto editado',@Precio=10,@PrecioCosto=6,@ProveedorId=@Prov,@ProductoId=@P,@VersionEsperada=@V;
   INSERT @ConsultaProducto EXEC dbo.sp_ConsultarProductos @ActorUsuarioId=@Actor,@IncluirCosto=1;
   IF NOT EXISTS(SELECT 1 FROM @ConsultaProducto WHERE ProductoId=@P AND Descripcion=N'Producto editado' AND PrecioCosto=6 AND Stock=0 AND Version<>@V) THROW 54900,'Edicion/consulta de producto incorrecta.',1;
   IF NOT EXISTS(SELECT 1 FROM dbo.Proveedor WHERE ProveedorId=@Prov AND Nombre=N'Proveedor editado') THROW 54900,'Proveedor no registrado.',1;
  END;
  IF @Caso=2
  BEGIN
   SET @Esperado=N'2601,2627';
   -- SKU unico
   EXEC dbo.sp_RegistrarProducto @ActorUsuarioId=@Actor,@Codigo=@SKU,@Descripcion=N'Duplicado',@Precio=10,@PrecioCosto=5,@ProveedorId=@Prov;
  END;
  IF @Caso=3
  BEGIN
   SET @Esperado=N'54102';
   -- Costo no negativo
   EXEC dbo.sp_RegistrarProducto @ActorUsuarioId=@Actor,@Codigo=N'NEGATIVO',@Descripcion=N'Negativo',@Precio=10,@PrecioCosto=-1,@ProveedorId=@Prov;
  END;
  IF @Caso=4
  BEGIN
   SET @Esperado=NULL;
   -- Ingreso compra
   EXEC dbo.sp_RegistrarMovimientoKardex @P,'COMPRA',10,@Actor,N'COMPRA-1',@Op,1,N'Prueba'; IF (SELECT Stock FROM dbo.Producto WHERE ProductoId=@P)<>10 THROW 54900,'Ingreso incorrecto.',1;
  END;
  IF @Caso=5
  BEGIN
   SET @Esperado=NULL;
   -- Egreso y saldo
   EXEC dbo.sp_RegistrarMovimientoKardex @P,'COMPRA',10,@Actor,N'COMPRA-1',@Op,1,N'Prueba'; SELECT @V=Version FROM dbo.Producto WHERE ProductoId=@P; EXEC dbo.sp_RegistrarMovimientoKardex @P,'AJUSTE_EGRESO',3,@Actor,N'AJUSTE-1',@Op,2,N'Ajuste autorizado',NULL,@V; IF NOT EXISTS(SELECT 1 FROM dbo.Kardex_Inventario WHERE OperacionId=@Op AND LineaOperacion=2 AND StockAnterior=10 AND StockResultante=7) THROW 54900,'Saldo incorrecto.',1;
  END;
  IF @Caso=6
  BEGIN
   SET @Esperado=N'54113';
   -- Stock negativo
   SELECT @V=Version FROM dbo.Producto WHERE ProductoId=@P; EXEC dbo.sp_RegistrarMovimientoKardex @P,'AJUSTE_EGRESO',1,@Actor,N'AJUSTE-1',@Op,1,N'Prueba',NULL,@V;
  END;
  IF @Caso=7
  BEGIN
   SET @Esperado=N'547';
   -- Rollback posterior a stock
   ALTER TABLE dbo.Kardex_Inventario ADD CONSTRAINT CK_Kardex_PruebaRollback CHECK(Motivo<>N'FORZAR'); EXEC dbo.sp_RegistrarMovimientoKardex @P,'COMPRA',10,@Actor,N'COMPRA-1',@Op,1,N'FORZAR';
  END;
  IF @Caso=8
  BEGIN
   SET @Esperado=NULL;
   -- Reintento identico
   EXEC dbo.sp_RegistrarMovimientoKardex @P,'COMPRA',10,@Actor,N'COMPRA-1',@Op,1,N'Prueba'; EXEC dbo.sp_RegistrarMovimientoKardex @P,'COMPRA',10,@Actor,N'COMPRA-1',@Op,1,N'Prueba'; IF (SELECT COUNT(*) FROM dbo.Kardex_Inventario WHERE OperacionId=@Op)<>1 OR (SELECT Stock FROM dbo.Producto WHERE ProductoId=@P)<>10 THROW 54900,'Movimiento duplicado.',1;
  END;
  IF @Caso=9
  BEGIN
   SET @Esperado=N'54112';
   -- Reintento conflictivo
   EXEC dbo.sp_RegistrarMovimientoKardex @P,'COMPRA',10,@Actor,N'COMPRA-1',@Op,1,N'Prueba'; EXEC dbo.sp_RegistrarMovimientoKardex @P,'COMPRA',11,@Actor,N'COMPRA-1',@Op,1,N'Prueba';
  END;
  IF @Caso=10
  BEGIN
   SET @Esperado=NULL;
   -- Cambio NIT
   SELECT @V=Version FROM dbo.Cliente WHERE ClienteId=@C; EXEC dbo.sp_ActualizarNitCliente @C,@NitNuevo,@Actor,@V,N'Correccion'; IF NOT EXISTS(SELECT 1 FROM dbo.Cliente WHERE ClienteId=@C AND NIT=@NitNuevo) THROW 54900,'NIT no actualizado.',1; IF NOT EXISTS(SELECT 1 FROM dbo.Bitacora_Transacciones WHERE TablaAfectada=N'Cliente' AND IdentificadorRegistro=CONVERT(NVARCHAR(4000),@C) AND Operacion='UPDATE' AND ActorUsuarioId=@Actor AND JSON_VALUE(ValorAnterior,'$.NIT')=@NitInicial AND JSON_VALUE(ValorNuevo,'$.NIT')=@NitNuevo AND Motivo=N'Correccion') THROW 54900,'Auditoria de NIT incompleta.',1;
  END;
  IF @Caso=11
  BEGIN
   SET @Esperado=N'2601,2627';
   -- NIT duplicado
   INSERT dbo.Cliente(NIT,Nombre) VALUES(@NitNuevo,N'Otro'); SELECT @V=Version FROM dbo.Cliente WHERE ClienteId=@C; EXEC dbo.sp_ActualizarNitCliente @C,@NitNuevo,@Actor,@V,N'Conflicto';
  END;
  IF @Caso=12
  BEGIN
   SET @Esperado=NULL;
   -- Inactivacion y factura
   INSERT dbo.Factura(ClienteId,UsuarioId,Subtotal,IVA,Total) VALUES(@C,@Actor,10,1.2,11.2); SET @F=SCOPE_IDENTITY(); SELECT @V=Version FROM dbo.Cliente WHERE ClienteId=@C; EXEC dbo.sp_InactivarCliente @C,@Actor,@V,N'Baja solicitada'; IF NOT EXISTS(SELECT 1 FROM dbo.Cliente WHERE ClienteId=@C AND Activo=0 AND FechaInactivacion IS NOT NULL) OR NOT EXISTS(SELECT 1 FROM dbo.Factura WHERE FacturaId=@F AND ClienteId=@C) THROW 54900,'Inactivacion destruyo historia.',1;
  END;
  IF @Caso=13
  BEGIN
   SET @Esperado=NULL;
   -- Identidad de emision
   INSERT dbo.Factura(ClienteId,UsuarioId,Subtotal,IVA,Total) VALUES(@C,@Actor,10,1.2,11.2); SET @F=SCOPE_IDENTITY(); SELECT @V=Version FROM dbo.Cliente WHERE ClienteId=@C; EXEC dbo.sp_ActualizarNitCliente @C,@NitNuevo,@Actor,@V,N'Correccion'; IF NOT EXISTS(SELECT 1 FROM dbo.Factura WHERE FacturaId=@F AND ClienteNITEmision=@NitInicial AND ClienteNombreEmision=N'Cliente prueba') THROW 54900,'Se altero identidad de emision.',1;
  END;
  IF @Caso=14
  BEGIN
   SET @Esperado=NULL;
   -- DML set based y no-op
   INSERT dbo.Cliente(NIT,Nombre) VALUES(@NitNuevo,N'Otro'); SELECT @N=COUNT(*) FROM dbo.Bitacora_Transacciones WHERE TablaAfectada='Cliente' AND Operacion='UPDATE'; UPDATE dbo.Cliente SET Correo=Correo WHERE ClienteId=@C OR NIT=@NitNuevo; IF (SELECT COUNT(*) FROM dbo.Bitacora_Transacciones WHERE TablaAfectada='Cliente' AND Operacion='UPDATE')<>@N THROW 54900,'Auditoria no-op.',1; UPDATE dbo.Cliente SET Correo=N'prueba@example.invalid' WHERE ClienteId=@C OR NIT=@NitNuevo; IF (SELECT COUNT(*) FROM dbo.Bitacora_Transacciones WHERE TablaAfectada='Cliente' AND Operacion='UPDATE')<>@N+2 THROW 54900,'Auditoria multirregistro.',1; SELECT @N=COUNT(*) FROM dbo.Bitacora_Transacciones WHERE TablaAfectada='Producto' AND Operacion='UPDATE'; UPDATE dbo.Producto SET Descripcion=N'Descripcion editada' WHERE ProductoId=@P; IF (SELECT COUNT(*) FROM dbo.Bitacora_Transacciones WHERE TablaAfectada='Producto' AND Operacion='UPDATE')<>@N+1 THROW 54900,'Cambio de descripcion sin auditoria.',1;
  END;
  IF @Caso=14
  BEGIN
   IF NOT EXISTS(SELECT 1 FROM dbo.Bitacora_Transacciones WHERE TablaAfectada=N'Cliente' AND Operacion='INSERT' AND IdentificadorRegistro=CONVERT(NVARCHAR(4000),@C) AND ValorAnterior IS NULL AND JSON_VALUE(ValorNuevo,'$.NIT')=@NitInicial) THROW 54900,'INSERT de cliente no auditado.',1;
   DELETE dbo.Cliente WHERE NIT=@NitNuevo;
   IF NOT EXISTS(SELECT 1 FROM dbo.Bitacora_Transacciones WHERE TablaAfectada=N'Cliente' AND Operacion='DELETE' AND JSON_VALUE(ValorAnterior,'$.NIT')=@NitNuevo AND ValorNuevo IS NULL) THROW 54900,'DELETE de cliente no auditado.',1;
  END;
  IF @Caso=15
  BEGIN
   SET @Esperado=NULL;
   -- Permisos minimos
   EXECUTE AS USER='securefinance_app'; SELECT @N=COALESCE(HAS_PERMS_BY_NAME('dbo.Producto','OBJECT','UPDATE'),0)+COALESCE(HAS_PERMS_BY_NAME('dbo.Cliente','OBJECT','SELECT'),0)+COALESCE(HAS_PERMS_BY_NAME('dbo.Kardex_Inventario','OBJECT','INSERT'),0)+COALESCE(HAS_PERMS_BY_NAME('dbo.ConfiguracionInventario','OBJECT','UPDATE'),0)+COALESCE(HAS_PERMS_BY_NAME('dbo.sp_ParteII_ValidarPermiso','OBJECT','EXECUTE'),0); SELECT @Permitido=HAS_PERMS_BY_NAME('dbo.sp_RegistrarMovimientoKardex','OBJECT','EXECUTE'); EXEC dbo.sp_ConsultarProductos @ActorUsuarioId=@Actor; REVERT; IF @N<>0 OR @Permitido<>1 THROW 54900,'Privilegios SQL incorrectos.',1;
  END;
  IF @Caso=16
  BEGIN
   SET @Esperado=NULL;
   -- Compatibilidad Parte I
   UPDATE dbo.Producto SET Stock=5 WHERE ProductoId=@P; INSERT @Detalle(ProductoId,Cantidad,DescuentoPorcentaje) VALUES(@P,2,10); EXEC dbo.sp_ProcesarVentaTransaccional @ClienteId=@C,@UsuarioId=@Actor,@Detalle=@Detalle,@FacturaId=@F OUTPUT; IF NOT EXISTS(SELECT 1 FROM dbo.Factura WHERE FacturaId=@F AND Subtotal=20 AND DescuentoTotal=2 AND IVA=2.16 AND Total=20.16) OR NOT EXISTS(SELECT 1 FROM dbo.MovimientoCaja WHERE FacturaId=@F AND Monto=20.16) OR (SELECT Stock FROM dbo.Producto WHERE ProductoId=@P)<>3 THROW 54900,'Regresion venta Parte I.',1; IF @IntegracionActiva=0 AND EXISTS(SELECT 1 FROM dbo.Kardex_Inventario WHERE ProductoId=@P) THROW 54900,'Integracion prematura de venta.',1;
   IF @IntegracionActiva=1 AND (SELECT COUNT(*) FROM dbo.Kardex_Inventario WHERE ProductoId=@P AND TipoMovimiento='VENTA' AND Cantidad=2 AND StockAnterior=5 AND StockResultante=3)<>1 THROW 54900,'Venta integrada sin una salida exacta.',1;
  END;
  IF @Caso=17
  BEGIN
   SET @Esperado=N'52006';
   -- Cliente inactivo no vende
   SELECT @V=Version FROM dbo.Cliente WHERE ClienteId=@C; EXEC dbo.sp_InactivarCliente @C,@Actor,@V,N'Baja'; INSERT @Detalle VALUES(@P,1,0); EXEC dbo.sp_ProcesarVentaTransaccional @C,@Actor,@Detalle,@F OUTPUT;
  END;
  IF @Caso=18
  BEGIN
   SET @Esperado=N'54103';
   -- Concurrencia optimista
   SELECT @V=Version FROM dbo.Cliente WHERE ClienteId=@C; UPDATE dbo.Cliente SET Telefono=N'123' WHERE ClienteId=@C; EXEC dbo.sp_ActualizarNitCliente @C,@NitNuevo,@Actor,@V,N'Edicion obsoleta';
  END;
  IF @Caso=19
  BEGIN
   SET @Esperado=N'54102';
   -- Fotografia insegura
   EXEC dbo.sp_RegistrarProducto @ActorUsuarioId=@Actor,@Codigo=N'FOTO',@Descripcion=N'Foto',@Precio=1,@PrecioCosto=1,@ProveedorId=@Prov,@Fotografia='../privado.jpg';
  END;
  IF @Caso=20
  BEGIN
   SET @Esperado=N'547';
   -- FK proveedor
   UPDATE dbo.Producto SET ProveedorId=-1 WHERE ProductoId=@P;
  END;
  IF @Caso=21
  BEGIN
   SET @Esperado=N'54101';
   -- RBAC actor
   UPDATE dbo.Usuario SET Activo=0 WHERE UsuarioId=@Actor; EXEC dbo.sp_ConsultarProductos @ActorUsuarioId=@Actor;
  END;
  IF @Caso=22
  BEGIN
   SET @Esperado=N'54110';
   -- Kardex bloqueado antes de apertura
   UPDATE dbo.ConfiguracionInventario SET Habilitado=0 WHERE ConfiguracionId=1; EXEC dbo.sp_RegistrarMovimientoKardex @P,'COMPRA',1,@Actor,N'COMPRA-1',@Op,1,N'Prueba';
  END;
  IF @Caso=23
  BEGIN
   SET @Esperado=N'54201';
   -- Kardex inmutable
   EXEC dbo.sp_RegistrarMovimientoKardex @P,'COMPRA',1,@Actor,N'COMPRA-1',@Op,1,N'Prueba'; DELETE dbo.Kardex_Inventario WHERE OperacionId=@Op;
  END;
  IF @Caso=24
  BEGIN
   SET @Esperado=N'54202';
   -- Snapshot inmutable
   INSERT dbo.Factura(ClienteId,UsuarioId,Subtotal,IVA,Total) VALUES(@C,@Actor,10,1.2,11.2); SET @F=SCOPE_IDENTITY(); UPDATE dbo.Factura SET ClienteNITEmision=N'OTRO' WHERE FacturaId=@F;
  END;
  IF @Caso=25
  BEGIN
   SET @Esperado=N'54102';
   -- NIT vacio
   SELECT @V=Version FROM dbo.Cliente WHERE ClienteId=@C; EXEC dbo.sp_ActualizarNitCliente @C,N' - ',@Actor,@V,N'Invalido';
  END;
  IF @Caso=26
  BEGIN
   SET @Esperado=NULL;
   -- Devolucion preparada
   EXEC dbo.sp_RegistrarMovimientoKardex @P,'DEVOLUCION',2,@Actor,N'DEV-PRUEBA',@Op,1,N'Contrato futuro'; IF (SELECT Stock FROM dbo.Producto WHERE ProductoId=@P)<>2 THROW 54900,'Entrada devolucion incorrecta.',1;
  END;
  IF @Caso=27
  BEGIN
   SET @Esperado=NULL;
   -- Factura anterior sin reconstruccion
   DISABLE TRIGGER dbo.tr_Factura_IdentidadEmision ON dbo.Factura; INSERT dbo.Factura(ClienteId,UsuarioId,Subtotal,IVA,Total) VALUES(@C,@Actor,10,1.2,11.2); SET @F=SCOPE_IDENTITY(); ENABLE TRIGGER dbo.tr_Factura_IdentidadEmision ON dbo.Factura; SELECT @V=Version FROM dbo.Cliente WHERE ClienteId=@C; EXEC dbo.sp_ActualizarNitCliente @C,@NitNuevo,@Actor,@V,N'Correccion'; IF EXISTS(SELECT 1 FROM dbo.Factura WHERE FacturaId=@F AND (ClienteNITEmision IS NOT NULL OR ClienteNombreEmision IS NOT NULL)) THROW 54900,'Historia inventada.',1;
  END;
  IF @Caso=28
  BEGIN
   -- Egreso por venta del mecanismo nuevo, solo en base aislada.
   EXEC dbo.sp_RegistrarMovimientoKardex @P,'COMPRA',5,@Actor,N'COMPRA-1',@Op,1,N'Prueba';
   INSERT dbo.Factura(ClienteId,UsuarioId,Subtotal,IVA,Total) VALUES(@C,@Actor,30,3.6,33.6); SET @F=SCOPE_IDENTITY();
   INSERT dbo.DetalleFactura(FacturaId,ProductoId,Cantidad,PrecioUnitario,Subtotal) VALUES(@F,@P,3,10,30);
   DECLARE @D INT=CONVERT(INT,SCOPE_IDENTITY());
   EXEC dbo.sp_RegistrarMovimientoKardex @P,'VENTA',3,@Actor,N'VENTA-1',@Op,2,N'Prueba',@D;
   IF (SELECT Stock FROM dbo.Producto WHERE ProductoId=@P)<>2 OR NOT EXISTS(SELECT 1 FROM dbo.Kardex_Inventario WHERE DetalleFacturaId=@D AND StockAnterior=5 AND StockResultante=2) THROW 54900,'Egreso de venta incorrecto.',1;
  END;
  IF @Esperado IS NOT NULL THROW 54900,'Se esperaba rechazo y la operacion fue aceptada.',1;
  IF SESSION_CONTEXT(N'ParteII.Actor') IS NOT NULL OR SESSION_CONTEXT(N'ParteII.Operacion') IS NOT NULL OR SESSION_CONTEXT(N'ParteII.Motivo') IS NOT NULL THROW 54900,'Contexto de solicitud filtrado.',1;
  ROLLBACK TRANSACTION;
 END TRY
 BEGIN CATCH
  SET @Error=ERROR_NUMBER();
  SET @MensajeError=ERROR_MESSAGE();
  -- Comprobar rollback del escritor ANTES de la limpieza del test.
  DECLARE @RollbackPendiente BIT=CASE WHEN @Caso IN(2,3,6,7,9,11,17,18,19,22,25)
    AND @@TRANCOUNT<>0 THEN 1 ELSE 0 END;
  -- Una transaccion no confirmable debe revertirse ANTES de REVERT.
  IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
  IF USER_NAME()=N'securefinance_app' REVERT;
  IF @RollbackPendiente=1 THROW 54900,'El procedimiento dejo una transaccion abierta tras fallar.',1;
  IF @Esperado IS NULL OR NOT EXISTS(SELECT 1 FROM STRING_SPLIT(@Esperado,N',') WHERE TRY_CONVERT(INT,value)=@Error)
  BEGIN
   PRINT CONCAT(N'FAIL|',@Caso,N'|', @DescripcionCaso,N'|',@Error,N'|',ERROR_PROCEDURE(),N':',ERROR_LINE(),N'|',ERROR_MESSAGE());
   THROW;
  END;
  IF EXISTS(SELECT 1 FROM dbo.Producto WHERE Codigo=@SKU) OR EXISTS(SELECT 1 FROM dbo.Kardex_Inventario WHERE OperacionId=@Op) OR EXISTS(SELECT 1 FROM dbo.Bitacora_Transacciones WHERE OperacionId=@Op) THROW 54900,'Rollback incompleto.',1;
  IF SESSION_CONTEXT(N'ParteII.Actor') IS NOT NULL OR SESSION_CONTEXT(N'ParteII.Operacion') IS NOT NULL OR SESSION_CONTEXT(N'ParteII.Motivo') IS NOT NULL THROW 54900,'Contexto filtrado tras error.',1;
 END CATCH;
 INSERT #ResultadosKenneth SELECT @Caso,Descripcion,'PASS',@Error,@MensajeError FROM @Descripciones WHERE Id=@Caso;
 PRINT CONCAT(N'PASS|',@Caso,N'|',@DescripcionCaso,N'|ErrorEsperado=',COALESCE(CONVERT(VARCHAR(10),@Error),'ninguno'));
 IF @MensajeError IS NOT NULL PRINT CONCAT(N'ERROR_ESPERADO|',@Caso,N'|',REPLACE(REPLACE(@MensajeError,CHAR(13),N' '),CHAR(10),N' '));
 SET @Caso+=1;
END;
SELECT Id,Descripcion,Resultado,ErrorEsperado,MensajeError FROM #ResultadosKenneth ORDER BY Id;
PRINT N'OK: 28 casos Parte II. Ejecutados solo en la base de prueba seleccionada.';
GO
