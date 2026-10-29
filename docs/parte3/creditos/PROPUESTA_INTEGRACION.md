# PROPOSED: Extension Compartida de Ventas Para Credito

Estado: implementacion propuesta por solicitud explicita del usuario, **NO
aprobacion de Kenneth**, pendiente de su revision escrita antes de integracion
o ejecucion. Fuente exacta: `43_P3_COT_ConversionFactura.sql` en `1bca099`.
No se modifica 43 ni se reemplaza el TVP. 76 contiene las tres definiciones
completas derivadas de esa fuente, no un motor paralelo ni un parche secreto
de precio del producto.

## Firmas Compartidas Propuestas

Todos los parametros preexistentes conservan nombre, tipo, posicion y valor
por defecto. Se agregan condiciones al final; credito no tiene efecto si no
se solicita. Recordsets publicos de factura/detalle/metadatos sin columnas
nuevas para no romper consumidores.

```sql
dbo.sp_ProcesarVentaTransaccional
 @ClienteId INT, @UsuarioId INT,
 @Detalle dbo.TipoDetalleVentaDescuento READONLY,
 @FacturaId INT=NULL OUTPUT, @MotivoDescuento NVARCHAR(80)=NULL,
 @P3CotizacionId INT=NULL,
 @P3Credito BIT=0, @P3PlazoDias INT=NULL, @P3NumeroCuotas INT=1

dbo.sp_ERP_ProcesarVenta
 @ClienteId INT, @UsuarioId INT,
 @Detalle dbo.TipoDetalleVentaDescuento READONLY,
 @OperacionId UNIQUEIDENTIFIER, @MotivoDescuento NVARCHAR(80)=NULL,
 @P3CotizacionId INT=NULL,
 @P3Credito BIT=0, @P3PlazoDias INT=NULL, @P3NumeroCuotas INT=1

dbo.sp_ConvertirCotizacionAFactura
 @CotizacionId INT, @ActorUsuarioId INT, @OperacionId UNIQUEIDENTIFIER,
 @P3Credito BIT=0, @P3PlazoDias INT=NULL, @P3NumeroCuotas INT=1
```

Contado conserva literalmente las dos expresiones SHA-256 de 43: la original
sin cotizacion y `P3COT:v1` con cotizacion congelada. Credito envuelve esa
huella en `P3CRE:v1|HEX(hash43)|plazo|cuotas|bodega-o-GLOBAL`. Cambiar modalidad,
plazo, cuotas, origen, actor o bodega bajo el mismo UUID falla. El libro
SolicitudVentaERP y app lock ERP.Venta.UUID siguen siendo los existentes.
No se crean ni modifican columnas/TVP ni se reinterpreta un hash historico.

La validacion de cotizacion y cierre atomico de UC09 se mantienen: propiedad
del actor o Administrador, permisos vigentes, lineas/motivo/total pactados,
estado activo, vencimiento revalidado despues de esperar stock, transicion
unica e historia. Los reintentos procesados tienen que conservar el vinculo
factura/actor/operacion. No se convierte una cancelada o vencida en una venta
nueva. Un replay identico ya confirmado no vuelve a consumir cupo ni stock.

Flujo credito: validar permiso CREDITOS_FACTURAR; bloquear perfil antes de
producto/factura; conservar el calculo de stock, descuentos, IVA y snapshot de
43; validar total definitivo contra deuda derivada y limite; insertar factura
y detalles; invocar Kardex central, nunca otro UPDATE de stock; crear cuenta y
plan en lugar del unico INSERT de caja. Un error revierte la transaccion
completa del llamador, como 21/43. Los contextos ParteII se limpian en ambos
caminos del motor. Los parametros nuevos no cambian las reglas comerciales
de Jose ni reaplican un descuento al pacto de Kenneth.

## Objetos Publicos Nuevos

```sql
dbo.P3_CRE_AdministrarCredito
 @ActorUsuarioId INT, @ClienteId INT, @Activo BIT,
 @Limite DECIMAL(19,2), @PlazoDias INT, @VersionEsperada BINARY(8),
 @Motivo NVARCHAR(MAX), @OperacionId UNIQUEIDENTIFIER

dbo.sp_RegistrarAbonoCliente
 @ActorUsuarioId INT, @ClienteId INT, @FacturaId INT, @Monto DECIMAL(19,2),
 @Referencia NVARCHAR(MAX), @OperacionId UNIQUEIDENTIFIER

dbo.P3_CRE_Consultar
 @ActorUsuarioId INT, @ClienteId INT=NULL, @FacturaId INT=NULL,
 @Estado VARCHAR(10)=NULL, @Desde DATETIME2(3)=NULL, @Hasta DATETIME2(3)=NULL,
 @Desplazamiento INT=0

dbo.P3_CRE_ConsultarRecibo @ActorUsuarioId INT, @AbonoId BIGINT

dbo.P3_CRE_ConsultarCaja
 @ActorUsuarioId INT, @Desde DATETIME2(3)=NULL, @Hasta DATETIME2(3)=NULL,
 @Desplazamiento INT=0

dbo.P3_CRE_ConvertirCotizacionCredito
 @ActorUsuarioId INT, @CotizacionId INT, @OperacionId UNIQUEIDENTIFIER,
 @PlazoDias INT, @NumeroCuotas INT=1, @BodegaId INT=NULL
```

Administrar devuelve un recordset con perfil/version/UUID persistidos (replay
devuelve el resultado original). Abonar devuelve AbonoId/ReciboId como strings,
UUID, cliente, factura, actor, fecha, referencia, monto y saldo posterior a
ese abono. Consultar devuelve cuentas, perfil, cuotas, abonos recientes e
historial, en ese orden. ConsultarRecibo devuelve recibo y aplicaciones FIFO.
ConvertirCredito devuelve exactamente los tres recordsets de UC09: factura,
detalle, metadatos CotizacionId/FacturaId/Estado/OperacionId.
ConsultarCaja devuelve resumen (EfectivoContado/EfectivoAbonos/EfectivoTotal,
strings DECIMAL(38,2)) y pagina de movimientos CONTADO/ABONO con identificadores
y monto string. Es un informe propio, no modifica reportes legacy.

Helpers internos, sin permiso EXECUTE directo para el login web:

```sql
dbo.P3_CRE_ValidarEntorno
dbo.P3_CRE_Auditar @ClienteId INT,@FacturaId INT,@Evento VARCHAR(20),
 @ActorUsuarioId INT,@OperacionId UNIQUEIDENTIFIER,@Motivo NVARCHAR(250),
 @Antes NVARCHAR(MAX),@Despues NVARCHAR(MAX)
dbo.P3_CRE_ValidarFinanciacion @ActorUsuarioId INT,@ClienteId INT,
 @PlazoDias INT,@NumeroCuotas INT,@Total DECIMAL(19,2)=NULL
dbo.P3_CRE_CrearCuenta @ActorUsuarioId INT,@ClienteId INT,@FacturaId INT,
 @PlazoDias INT,@NumeroCuotas INT,@OperacionId UNIQUEIDENTIFIER
```

Auditar registra historia propia y Bitacora_Transacciones sin cambiar triggers
ajenos. Venta sigue usando el UUID interno que el motor historico genera
para Kardex; el UUID publico se conserva en SolicitudVentaERP y en el cierre
de cotizacion. Ambas historias se correlacionan por FacturaId. Abono y perfil
conservan directamente el UUID publico en su historia propia.

## Contrato BOD

Fachada publica de firma fija indicada arriba. BOD puede invocarla cuando
este instalada. Con BodegaId se abre transaccion explicita, se exige el helper
opcional `dbo.P3_BOD_ValidarBodegaVenta @ActorUsuarioId INT,@BodegaId INT`, se
valida bodega activa/actor y se establece SESSION_CONTEXT(N'P3_BOD.BodegaId')
antes de invocar al conversor extendido. **Si ya existe cualquier valor no
NULL de esa clave al entrar, 77 rechaza 57009 fuera de TRY y antes de BEGIN
TRANSACTION; no lo borra, adopta ni sustituye.** Solo marca ContextoPropio tras
establecerlo con exito y solo ese contexto se limpia al salir o en CATCH. Si
no se pidio bodega no toca la clave. El wrapper ERP tambien valida el contexto
si lo recibe directamente para credito.

Actualizacion acordada por el usuario para BOD: 81 incorporara
`P3_BOD_ValidarBodegaVenta @ActorUsuarioId INT,@BodegaId INT`, sin GRANT directo
al login app, sin resultsets, verificando BODEGAS_CONSULTAR y bodega activa.
76/77 usan llamada estatica dentro de la cadena de propiedad dbo y traducen
2812 (helper/dependencia ausente) a 57008, sin fallback. No usan OBJECT_ID para
decidir si existe en runtime: puede ocultar un helper interno sin permisos de
metadatos. No se eleva EXECUTE AS OWNER ni se cambia la identidad SQL de
auditoria. Falta verificar esta cadena bajo el login web real en laboratorio.

BOD85 invocara 77 **sin establecer contexto ni abrir transaccion externa** y
eliminara prebloqueos de Producto, evitando invertir quote -> credito ->
Producto. Creditos no modifica ese archivo ni comprueba un worktree ajeno.
El helper solo valida: no debe mutar stock y su infraestructura/trigger deben
estar preparados. Esta coordinacion no demuestra que BOD este instalado.

El contrato acordado de movimientos es: Kardex central cambia stock global
exactamente una vez; un trigger BOD AFTER INSERT de ese libro refleja cada
movimiento en la ubicacion elegida, sin segundo descuento global. Creditos no
crea ni modifica ese trigger, tablas BOD ni el worktree BOD. Sin BOD ni
BodegaId se conserva inventario global existente. Probar conjuntamente falta
de bodega activa, falta de stock local, rollback de trigger y limpieza de
contexto antes de declarar integrada la combinacion.

## Revision Requerida

Kenneth: firmas/defaults/resultados/hashes de contado y UC09, permisos,
propiedad/conversion, congelacion de precios y replay. Jose: no doble
descuento, coherencia de reportes de ventas frente a caja. Responsable BOD:
helper, contexto, orden de bloqueos y trigger. Integrador: fuentes vigentes
antes de 76, instalacion transaccional, conciliacion, permisos efectivos y
recuperacion ensayada. **No existe evidencia de estas aprobaciones o pruebas
SQL en esta entrega.**

La revision de defaults completos y la matriz de escenarios estan en
[REVISION_COMPATIBILIDAD.md](REVISION_COMPATIBILIDAD.md). Los tests fuente
proyectan el camino de contado de cada procedimiento de 76 y comparan todos
sus tokens con 43; no sustituyen compilacion, metadata o ejecucion SQL real.
