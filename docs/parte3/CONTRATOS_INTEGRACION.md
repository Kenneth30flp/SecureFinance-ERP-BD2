# Contratos de integración — Parte III

## Consulta comercial de Cotizaciones (44)

El rediseño añade P3_COT_PrepararFormulario y P3_COT_BuscarCatalogo mediante 44,
solo lectura y con COTIZACIONES_CREAR vigente. GET de búsqueda por cliente/NIT
y producto/SKU devuelve como máximo ocho resultados y una indicación de página
siguiente; el formulario no descarga el catálogo completo. No cambia los POST,
precios definitivos, motor 43, caja ni Kardex. No hay filtro por prefijo QA.
Los datos de demostración y pruebas se separan físicamente por base y archivo
de estado; la demostración no recibe escrituras de los ejecutores automáticos.
Ver [rediseño y entornos](cotizaciones/redisenio/README.md).

## Extensión UC09 autorizada en la rama de Kenneth

Por orden expresa posterior de Kenneth, coordinador de integración, la rama
feature/p3-kenneth-cotizaciones implementa el contrato de
[UC09_IMPLEMENTACION.md](cotizaciones/UC09_IMPLEMENTACION.md) sin exigir
aprobación de cuentas de José/Dylan como condición para desarrollar y validar.
No se atribuye aprobación externa. Su incorporación a esta rama común sigue
mediante PR #12, sin merge automático ni despliegue sobre la principal.

La migración 43 añade al final `@P3CotizacionId INT=NULL` a ambos procedimientos
de venta, conserva el camino NULL y sus hashes históricos, y reutiliza el motor
único para contado/global con precios pactados SQL. No cambia el TVP ni Kardex.
El wrapper cierra la cotización atómicamente incluso si se invoca directamente;
UC09 orquesta la misma transacción. José debe evitar doble descuento al integrar
promociones; Dylan debe extender explícitamente modalidad/bodega/huella sin
invalidar los reintentos existentes. Los importes son históricos, mientras la
identidad textual de la factura sigue capturándose al facturar según 39.

Las firmas y fuentes descritas abajo corresponden a la base Parte II; para
extender el motor después de UC09 partir de 43, conservando la compatibilidad.

## Base técnica y alcance

El responsable de integración autorizó expresamente el commit
`224164a5d1ce8222d3951d82d7afb164f31c3d72` como base técnica de Parte III.
Esta selección no afirma que sea el commit exacto de la evaluación académica.
Rama común: `integracion/parte3`. No incorpora un merge de main ni del PR #11;
ese PR conserva su estado independiente.

Esta entrega contiene únicamente coordinación. No instala SQL, cambia datos,
configuración o credenciales, ni implementa los seis módulos.

## Arquitectura existente

Node.js >=24, Express, sesiones express-session, EJS, CSS y JavaScript de
navegador; SQL Server mediante `mssql`, consultas parametrizadas y TVP.
`server.js` compone rutas, controladores y servicios con dependencias
inyectables. `src/config/database.js` comparte el pool; no copiar su
configuración ni crear conexiones con credenciales nuevas.

Los catálogos e inventario usan `src/routes/kennethRoutes.js`,
`src/controllers/kennethController.js` y servicios por entidad. Posventa está
en `src/modules/edward`; analítica, en `src/modules/jose`. Facturación tiene
rutas y servicios propios. Las migraciones incrementales están en `database/`.
La definición vigente de un objeto es la última migración que lo modifica,
no necesariamente su archivo de creación ni el instalador Full.

## Facturación: contrato compartido

Fuentes: `src/services/ventaService.js`, `src/routes/ventaRoutes.js`,
`database/21_ParteII_IntegracionFacturacionKardex.sql`,
`database/37_ERP_VentaIdempotente.sql` y `database/39_ERP_HistorialFacturas.sql`.

```sql
dbo.sp_ERP_ProcesarVenta
 @ClienteId INT, @UsuarioId INT,
 @Detalle dbo.TipoDetalleVentaDescuento READONLY,
 @OperacionId UNIQUEIDENTIFIER, @MotivoDescuento NVARCHAR(80)=NULL

dbo.sp_ProcesarVentaTransaccional
 @ClienteId INT, @UsuarioId INT,
 @Detalle dbo.TipoDetalleVentaDescuento READONLY,
 @FacturaId INT=NULL OUTPUT, @MotivoDescuento NVARCHAR(80)=NULL
```

El TVP tiene exactamente `ProductoId INT`, `Cantidad INT` y
`DescuentoPorcentaje DECIMAL(5,2)`, no nulos. No recibe precio pactado,
promoción, bodega ni modalidad de crédito.

El servicio llama al wrapper ERP. SQL valida cliente/usuario activos,
política `fn_ObtenerPoliticaVenta`, descuentos, productos y stock. Bloquea
productos por PK ascendente con UPDLOCK/HOLDLOCK. Toma `Producto.Precio`,
calcula descuentos por línea y el IVA sobre el neto global con DECIMAL y
redondeo a centavos. Crea `Factura`, `DetalleFactura`, efectos de caja y
salidas mediante Kardex en la misma transacción; no repetir esas escrituras.

El primer recordset contiene FacturaId, FechaHora, Subtotal, Descuento,
SubtotalNeto, IVA, Total, Cliente, NIT, Cajero y MotivoDescuento. El segundo
contiene ProductoId, Descripcion, Cantidad, PrecioUnitario, Subtotal,
DescuentoPorcentaje, DescuentoMonto y SubtotalNeto. Los importes monetarios
de respuesta se convierten a cadenas; conservar precisión en JavaScript.

`SolicitudVentaERP` conserva OperacionId (PK), FacturaId único, UsuarioId,
SolicitudHash, Comprobante y Detalle JSON, FechaHora. Su trigger impide
UPDATE/DELETE. El wrapper serializa por `ERP.Venta.<UUID>` y almacena la
respuesta; reintento idéntico devuelve el comprobante, carga distinta falla.
El hash incluye cliente, usuario, motivo y líneas ordenadas por producto.

`FACTURAS_CONSULTAR` habilita `/facturacion/historial` y
`/facturacion/facturas/:id`; `VENTAS_REGISTRAR` habilita registrar ventas.
`sp_ERP_ConsultarFacturas` y `sp_ERP_ConsultarComprobante` consultan documentos
persistidos. No reconstruir importes históricos desde el catálogo actual.

**Limitación para Cotizaciones:** el contrato actual no congela precios
externos al catálogo. Kenneth debe proponer una extensión compatible y
coordinarla con José y Dylan antes de modificar el núcleo. No cambiar
temporalmente Producto.Precio, recalcular después de facturar ni duplicar
el motor de venta. Conservar firma y comportamiento para consumidores actuales.

## Kardex

Fuente vigente: migración 21; integración de devoluciones: 24.

```sql
dbo.sp_RegistrarMovimientoKardex
 @ProductoId INT, @TipoMovimiento VARCHAR(25), @Cantidad INT,
 @ActorUsuarioId INT, @DocumentoRespaldo NVARCHAR(MAX),
 @OperacionId UNIQUEIDENTIFIER, @LineaOperacion INT, @Motivo NVARCHAR(MAX),
 @DetalleFacturaId INT=NULL, @VersionEsperada BINARY(8)=NULL,
 @DevolverResultado BIT=1
```

Es el punto central de escritura de stock. Tipos existentes: COMPRA, VENTA,
AJUSTE_INGRESO, AJUSTE_EGRESO y DEVOLUCION. Cantidad positiva; la dirección
depende del tipo. VENTA exige DetalleFacturaId y los otros tipos lo excluyen.
Los ajustes exigen VersionEsperada. Documento admite hasta 100 caracteres y
motivo hasta 250, validados también por SQL.

Requiere `ConfiguracionInventario` habilitada, apertura aprobada e
IntegracionVersion=2. Concilia stock con el último saldo de
`Kardex_Inventario`. Serializa OperacionId/LineaOperacion y compara la carga
al reintentar. Bloquea producto, rechaza stock negativo y registra stock
anterior/resultante. No volver a descontar documentos anteriores al corte.

Respeta transacción externa en éxito; ante error puede revertir toda la
transacción activa. El llamador debe admitir rollback completo. Limpia
SESSION_CONTEXT de actor, operación y motivo. La devolución usa el trigger
`tr_DetalleDevolucion_Reingreso`, con DevolverResultado=0, y relaciona detalle
con Kardex mediante `DevolucionKardex`; no alterar ese vínculo.

## Inventario y productos

Fuentes: `inventarioService.js`, `productoService.js`, migraciones 22, 33–34,
36 y 38. `sp_ConsultarEstadoInventario` consulta el estado;
`sp_ERP_ConsultarKardex` recibe actor, ProductoId, Desde/Hasta DATETIME2(3)
y Desplazamiento. Fechas almacenadas en UTC; filtros web convierten días de
Guatemala mediante `operationalDates.js`. Usar intervalos [Desde,Hasta).

`sp_RegistrarRecepcionCompra` recibe ActorUsuarioId, ProductoId, ProveedorId,
Cantidad, DocumentoRespaldo NVARCHAR(100), Motivo NVARCHAR(250), OperacionId
UNIQUEIDENTIFIER y CostoUnitario DECIMAL(19,2), opcional. Registra recepción,
detalle y Kardex juntos; costo desconocido no equivale a cero ni cambia
PrecioCosto. `sp_ERP_RegistrarAjuste` mantiene control de versión y referencia.

`sp_ConsultarProductosWeb`, `sp_ERP_RegistrarProducto`,
`sp_ActualizarProducto`, `sp_ConsultarProductoProveedor` y
`sp_AsociarProductoProveedor` son los puntos de catálogo. Migración 38 genera
SKU desde SQL; no crear otra secuencia o duplicar el producto por proveedor.
Inventario actual es global por Producto.Stock: aún no hay contrato de bodega.

## Clientes

Fuentes: `clienteService.js`, migraciones 18, 22, 23 y 40.
`sp_ConsultarClientesWeb` usa ActorUsuarioId, Buscar NVARCHAR(150), Id INT y
Desplazamiento INT. Alta: `sp_RegistrarCliente`; datos de contacto:
`sp_ActualizarDatosCliente`; cambio fiscal: `sp_ActualizarNitCliente`;
inactivación: `sp_InactivarCliente`. No mezclar cambio de NIT con edición general.

`sp_ReactivarCliente` recibe ActorUsuarioId INT, ClienteId INT,
VersionEsperada BINARY(8), Motivo NVARCHAR(250) y OperacionId UNIQUEIDENTIFIER.
`sp_ConsultarHistorialEstadoCliente` recibe actor y ClienteId. La reactivación
solo cambia Activo y conserva documentos e historia; usa libro inmutable,
ROWVERSION, RBAC SQL e idempotencia. El servicio representa Version como
hexadecimal de 16 caracteres. Permisos separados: CLIENTES_CONSULTAR,
CLIENTES_REGISTRAR, CLIENTES_EDITAR, CLIENTES_ACTUALIZAR_NIT,
CLIENTES_INACTIVAR y CLIENTES_REACTIVAR.

## Proveedores

Fuentes: `proveedorService.js`, migraciones 16, 18, 22 y 33.
`sp_ConsultarProveedoresWeb` comparte filtros de catálogo.
`sp_RegistrarProveedor` y `sp_ActualizarProveedor` reciben actor y los datos
NIT, Nombre, Correo, Telefono, Direccion, Fotografia; actualizar incorpora
ProveedorId, VersionEsperada y Activo. Respetar parámetros tipados del servicio.
`ProductoProveedor` representa relaciones múltiples; conservar proveedor
principal y referencias históricas de `RecepcionCompra`/`DetalleRecepcionCompra`.
Permisos: PROVEEDORES_CONSULTAR y PROVEEDORES_ADMINISTRAR.

## Créditos existentes y Auditoría

El crédito actual es una **nota de crédito de posventa**, no una cuenta por
cobrar. Migraciones 24–26 y 35; `src/modules/edward/services.js`:
`sp_ConsultarAplicacionesNotaCredito` recibe actor y NotaCreditoId;
`sp_RegistrarAplicacionNotaCredito` recibe además Monto DECIMAL(19,2),
ReferenciaDocumental NVARCHAR(100) y OperacionId UNIQUEIDENTIFIER. Registra
REEMBOLSO_DOCUMENTADO externo; no ejecuta pagos. Estado documental EMITIDA
y EstadoCredito PENDIENTE/PARCIAL/LIQUIDADA son conceptos separados.
No marcar ventas futuras al crédito como efectivo ni consumir notas dos veces.

`auditoriaService.js` consume `sp_ConsultarBitacoraAcceso`,
`sp_ConsultarAuditoriaTransacciones` y `sp_ConsultarHistoricoVentas`, con
fechas y filtros tipados. Auditoría DML existente usa triggers y
`Bitacora_Transacciones`; la Parte II añade contexto ParteII.Actor,
ParteII.Operacion y ParteII.Motivo. Conservar actor, fechas UTC, JSON histórico
y limpieza de contexto en éxito/error. Auditoría DDL futura no reemplaza DML
ni debe registrar secretos. No reescribir eventos anteriores.

## Autenticación, autorización y seguridad

`authService.js` llama `sp_Login` y `sp_ObtenerPermisosUsuario`; el controlador
crea sesión con usuarioId y permisos. `requireAuth` exige sesión y redirige
a cambio de contraseña cuando corresponde. No confiar en actor enviado por
el navegador. RBAC HTTP no sustituye autorización vigente SQL:
`sp_ParteII_ValidarPermiso` es el contrato compartido de Parte II.

CSRF existente es específico de cada flujo: ventas usa ventaCsrf; catálogos
usan kennethCsrf y encabezado X-CSRF-Token. Adoptar el patrón sin sustituir
tokens globalmente. Validar entradas, parametrizar SQL y emitir errores seguros.
La cuenta securefinance_app ejecuta procedimientos concretos: migración 37
deniega ejecución directa de ventas antiguas; no conceder DML directo ni db_owner.

## Idempotencia y concurrencia

Conservar UUID durante reintentos y comparar la carga completa. No generar
una referencia nueva ante resultado incierto. UUID no sustituye CSRF ni RBAC.
Kardex usa clave operación/línea; ventas usa libro y hash propios; clientes
usa libro de reactivación. No reutilizar libros de otro dominio con semántica
distinta. Respetar orden de bloqueos y transacción única; probar concurrencia,
rollback y efectos exactamente una vez en laboratorio.

## Dependencias entre módulos de Parte III

| Módulo | Contratos que debe coordinar |
| --- | --- |
| Cotizaciones — Kenneth | Facturación, Cliente, Producto; precios congelados y descuentos con José; contado/crédito y futura bodega con Dylan |
| Compras — Edward | Proveedor, ProductoProveedor, RecepcionCompra y Kardex; futura bodega con Dylan; evitar doble ingreso |
| Promociones — José | Política de venta, descuentos y redondeo; acordar cuándo se evalúa/congela una promoción y evitar doble aplicación |
| Créditos — Dylan | Factura, caja y medios de pago; separar cuentas por cobrar de notas de crédito; coordinar conversión con Kenneth |
| Multibodega — Dylan | Kardex, venta, compra, devoluciones y cotizaciones; definir bodega de salida sin inventar historia |
| Auditoría DDL — Dylan | Triggers, permisos y despliegues de todos; preservar auditoría DML y excluir secretos |

Los contratos futuros son pendientes de diseño, no funciones implementadas.
Mientras crédito y multibodega no estén integrados, el punto de partida es
venta de contado e inventario global. Cualquier ampliación debe explicitar
efectos de caja, stock, idempotencia y compatibilidad histórica.

## Reservas y ramas individuales

Revisión del 2026-10-27: máximo incremental encontrado **40**, incluyendo
historial de referencias locales y remotas obtenidas con fetch. No se
encontraron archivos 41–99. Existen huecos 27–29: no reutilizarlos.
Estas reservas asignan números; no crean migraciones funcionales.

| Responsable / módulo | Rango exclusivo | Prefijo reservado para objetos nuevos | Rama |
| --- | --- | --- | --- |
| Kenneth / Cotizaciones | 41–49 | P3_COT_ | feature/p3-kenneth-cotizaciones |
| Edward / Compras | 50–59 | P3_COM_ | feature/p3-edward-compras |
| José / Promociones | 60–69 | P3_PRO_ | feature/p3-jose-promociones |
| Dylan / Créditos | 70–79 | P3_CRE_ | feature/p3-dylan-creditos |
| Dylan / Multibodega | 80–89 | P3_BOD_ | feature/p3-dylan-multibodega |
| Dylan / Auditoría DDL | 90–99 | P3_DDL_ | feature/p3-dylan-auditoria-ddl |
| Rubén / Documentación | Sin migraciones | No aplica | docs/p3-ruben-documentacion |

Todas las ramas individuales deben crearse desde `integracion/parte3`
después de publicar esta preparación; aquí solo se definen. Para nuevas
migraciones usar `NN_P3_MOD_Descripcion.sql` dentro del rango asignado.
Los prefijos no obligan a renombrar objetos existentes ni reemplazan nombres
académicos obligatorios, como `dbo.sp_ConvertirCotizacionAFactura`.
No consumir rangos ajenos; registrar reasignaciones antes de usarlas.

## Puntos compartidos y coordinación obligatoria

**Toda modificación de un procedimiento compartido de Facturación, Kardex o
de su contrato SQL debe coordinarse antes de implementarse.** No modificar
simultáneamente `sp_ERP_ProcesarVenta`, `sp_ProcesarVentaTransaccional`,
`TipoDetalleVentaDescuento`, `SolicitudVentaERP`,
`sp_RegistrarMovimientoKardex`, apertura/habilitación/conciliación, política
de descuentos, tablas Factura/DetalleFactura/Producto ni sus triggers.

El responsable propone firma, tipos, resultados, bloqueos, permisos,
idempotencia, compatibilidad y pruebas. El integrador y responsables afectados
acuerdan el contrato por escrito en un PR/documento antes de implementar;
asignar un único propietario del cambio compartido y actualizar este documento.
No resolver diferencias sobrescribiendo cambios de compañeros.

Otros archivos sensibles a integración: `server.js`, `package.json`,
`src/config/integration.js`, rutas/servicios de venta, `kennethRoutes.js`,
`kennethController.js`, JavaScript compartido, navegación EJS, CSS común,
permisos, triggers y `SecureFinanceERP_Full.sql`. Anunciar cambios y limitar
el diff a lo necesario; preferir archivos propios por módulo.

## Pull Requests, validación y despliegue

1. Partir de la rama común publicada y comprobar árbol limpio/rango disponible.
2. PR individual dirigido a `integracion/parte3`, sin merge automático,
   force-push ni cambios ajenos. No fusionar/cerrar el PR #11 como efecto lateral.
3. Describir comportamiento, objetos SQL, orden incremental, dependencias,
   permisos, riesgos, evidencias y pendientes. Revisión del integrador y de
   responsables de contratos compartidos antes de fusionar.
4. Ejecutar `npm run check`, `npm test` y `git diff --check`. Pruebas SQL y
   navegador de escritura solo en laboratorio aislado; distinguir mocks de
   SQL real. No declarar resultados que no se ejecutaron.
5. No incluir .env, credenciales, respaldos ni datos personales. No ejecutar
   Full, migraciones o pruebas de escritura sobre SecureFinanceERP.
6. Cada entrega SQL documenta preflight, respaldo recuperable, dependencias,
   orden de ejecución, repetibilidad, permisos mínimos, pruebas posteriores y
   recuperación ensayada en copia. No editar migraciones históricas aplicadas.
7. Rubén recopila evidencias reales con propósito, origen, entorno y resultado;
   capturas o sesiones fixture deben identificarse como tales.

## Validación de esta preparación

La preparación no requiere conexión SQL. Ejecutar y registrar en la entrega
los resultados de `npm run check`, `npm test` y `git diff --check`, comprobar
que el único cambio de contenido sea documental y cotejar el SHA publicado
con HEAD. La publicación de esta rama habilita iniciar Cotizaciones; no
autoriza alterar unilateralmente los contratos compartidos.

Resultados ejecutados el 2026-10-27 sobre la base autorizada con este único
documento añadido: `npm.cmd run check` PASS; `npm.cmd test` PASS (95 pruebas,
0 fallidas, 0 omitidas). No se ejecutaron pruebas SQL reales ni migraciones
en esta preparación. Los resultados de la suite Node no acreditan ejecución
de procedimientos contra SQL Server.

## Creditos Mod3: Propuesta en Worktree de Dylan

Estado **PROPOSED, pendiente de revision escrita de Kenneth antes de integrar
o ejecutar**. Implementacion preparada por solicitud explicita del usuario;
no se atribuye aprobacion de los responsables ni despliegue SQL. No se edita
43/39/21, el TVP o Kardex. Ver
[propuesta de firmas, hashes, bloqueo y BOD](creditos/PROPUESTA_INTEGRACION.md)
y [entrega de Mod3 y limites reales](creditos/README.md).

70-79 contienen exclusivamente Creditos. 76 propone extender las tres
definiciones vigentes de 43 con parametros opcionales finales
`@P3Credito BIT=0,@P3PlazoDias INT=NULL,@P3NumeroCuotas INT=1`, preservando
recordsets y las dos huellas de contado; credito agrega condiciones y bodega
a su propia huella. Mantiene un solo motor de precio/IVA/descuentos y el
Kardex central. Credito crea cuenta/cuotas en lugar de caja de contado.
No se cambian temporalmente precios del catalogo ni se duplican descuentos.

La fachada fija propuesta es
`dbo.P3_CRE_ConvertirCotizacionCredito @ActorUsuarioId INT,@CotizacionId INT,
@OperacionId UNIQUEIDENTIFIER,@PlazoDias INT,@NumeroCuotas INT=1,@BodegaId INT=NULL`.
La clave compartida BOD es `SESSION_CONTEXT(N'P3_BOD.BodegaId')`; BOD refleja
cada INSERT Kardex en ubicacion mediante su trigger, sin otro cambio de stock
global. Creditos no modifica BOD. Si se pide bodega exige el helper opcional
`P3_BOD_ValidarBodegaVenta @ActorUsuarioId INT,@BodegaId INT` acordado para 81:
sin GRANT app, sin resultsets, BODEGAS_CONSULTAR y bodega activa. Si falta se
rechaza, sin fallback silencioso. 77 rechaza contexto previo ocupado (57009)
antes de abrir transaccion y limpia solo el contexto que instalo. BOD85 debe
llamar sin contexto/transaccion externos ni prebloqueos de Producto.
Sin bodega y sin modulo BOD, se conserva el stock global existente.

Tablas academicas exactas `Credito_Cliente`, `Abono_Factura`; abono publico
`sp_RegistrarAbonoCliente`. Demas objetos propios `P3_CRE_`. Recibos en libro
`P3_CRE_ReciboCaja` (UNIQUE por abono): no se fuerza mas de una fila por factura
en MovimientoCaja ni se alteran movimientos historicos. **P3_CRE_ConsultarCaja
y GET /creditos/caja implementan un informe propio unificado** con permiso
CREDITOS_CONSULTAR, fechas UTC y SUM DECIMAL(38,2) como strings. El indicador
propio de Creditos muestra efectivo abonado, no deuda ni venta financiada.
Los dashboards e informes legacy siguen intactos: su integracion posterior
no se declara realizada.

SQL solo habilitado para `SecureFinanceERP_Lab_Dylan`; instalacion externa
transaccional a traves de todos los GO y abortar al primer fallo. TLS reportado
no confiable: no se establecieron conexiones ni se eludio su validacion.
