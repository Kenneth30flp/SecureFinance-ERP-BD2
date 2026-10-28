# UC09: contrato final propuesto para aprobación

**Actualización posterior autorizada:** Kenneth aprobó expresamente implementar
esta revisión en la rama individual y dispensó aprobaciones previas de José/Dylan.
El contrato implementado, pruebas y límites están en
[UC09_IMPLEMENTACION.md](UC09_IMPLEMENTACION.md). Las condiciones de aprobación
que siguen se conservan como registro histórico y quedaron sustituidas por esa
orden; no son un bloqueo vigente ni representan aprobaciones de terceros.

Revisión 2, 2026-10-27. **PROPUESTA, NO IMPLEMENTACIÓN NI APROBACIÓN FINAL.**
Código revisado: `1c6f813b470283c3b8bf54108163688392ae20bb`.
Rama: `feature/p3-kenneth-cotizaciones`. Destino: `integracion/parte3`.
Este documento precisa y reemplaza las ambigüedades de la propuesta inicial;
ambos documentos deben leerse como una única propuesta con esta revisión vigente.

## Evidencia de coordinación consultada

El [PR #12](https://github.com/Kenneth30flp/SecureFinance-ERP-BD2/pull/12)
estaba abierto, en borrador y mergeable/clean al consultar la API de GitHub.
Su HEAD coincidía con el commit revisado. Se leyeron íntegramente:

- `/pulls/12/reviews`: sin revisiones publicadas.
- `/issues/12/comments`: sin comentarios de conversación.
- `/pulls/12/comments`: sin comentarios de revisión de código.
- `docs/parte3/CONTRATOS_INTEGRACION.md` y documentos de Cotizaciones.
- Historial de `docs/parte3` en todas las referencias obtenidas con fetch:
  solo preparación y entrega independiente; sin registro de aprobaciones.

No se encontraron aprobaciones expresas de José o Dylan en esas fuentes.
Esto no acredita conversaciones externas: no se presumen ni se sustituyen.
El integrador expresó en esta conversación aceptación **condicionada** del
parámetro opcional, exigiendo revisar y obtener la aprobación de los afectados.
Esa instrucción no se registra como aprobación de José o de Dylan.

| Responsable | Alcance a aprobar | Estado comprobado |
| --- | --- | --- |
| Integrador | Compatibilidad, alcance y habilitación tras coordinación | Aceptación condicionada en conversación; falta cierre del contrato revisado |
| José | Política de descuentos, promociones futuras y motivo | Sin aprobación expresa localizada |
| Dylan | Contado, caja, inventario global, futura modalidad/bodega y concurrencia | Sin aprobación expresa localizada |
| Kenneth | Implementación y pruebas después de las aprobaciones | Responsable técnico; no sustituye las aprobaciones anteriores |

Para levantar el bloqueo, cada responsable debe aprobar expresamente esta
revisión en el PR o en documentación compartida, identificando su responsabilidad
y el commit documental revisado. Registrar enlace, identidad y fecha reales.
Una aprobación genérica de la interfaz, el silencio o una aprobación de otra
versión del contrato no bastan. No se enviaron mensajes privados ni se asignaron
revisiones a cuentas cuya identidad no esté confirmada.

## Definiciones efectivas y compatibilidad

Las definiciones incrementales vigentes son migración 37 para el wrapper,
21 para el núcleo/Kardex, y 39 para snapshots/comprobantes. No hay una definición
posterior que las reemplace en esta rama. El instalador Full no determina la
versión incremental efectiva. Las migraciones 21, 37, 41 y 42 quedan intactas.

Firmas propuestas, exclusivamente después de aprobación:

```sql
dbo.sp_ERP_ProcesarVenta
 @ClienteId INT,
 @UsuarioId INT,
 @Detalle dbo.TipoDetalleVentaDescuento READONLY,
 @OperacionId UNIQUEIDENTIFIER,
 @MotivoDescuento NVARCHAR(80)=NULL,
 @P3CotizacionId INT=NULL

dbo.sp_ProcesarVentaTransaccional
 @ClienteId INT,
 @UsuarioId INT,
 @Detalle dbo.TipoDetalleVentaDescuento READONLY,
 @FacturaId INT=NULL OUTPUT,
 @MotivoDescuento NVARCHAR(80)=NULL,
 @P3CotizacionId INT=NULL

dbo.sp_ConvertirCotizacionAFactura
 @CotizacionId INT,
 @ActorUsuarioId INT,
 @OperacionId UNIQUEIDENTIFIER
```

Se mantiene orden, tipo, valor predeterminado y semántica de cada parámetro
actual. Llamadas posicionales y nominales existentes siguen sin enviar el nuevo
parámetro. NULL no incorpora consultas de cotización ni validaciones de permisos
nuevos al flujo normal; conserva su política, precios, resultados y errores.
No se cambia el TVP, SolicitudVentaERP, Factura, DetalleFactura o sus triggers.
No se añade modalidad de crédito ni BodegaId en esta revisión.

Para el camino NULL debe conservarse **literalmente** la composición actual del
hash: SHA2_256 de cliente, usuario, COALESCE(motivo,''), separadores y JSON de
líneas ordenadas. No prefijar versión ni añadir NULL, espacios o separadores.
Conservar también la normalización actual del motivo en ese camino: cambiarla
alteraría las huellas históricas. Regresión obligatoria con un registro previo
de SolicitudVentaERP y su hash, sin UPDATE sobre el libro inmutable.

Para cotización, usar una huella separada con prefijo `P3COT:v1`, CotizacionId,
cliente, actor, motivo determinista y líneas históricas canónicas, incluidos
precios/descuentos. Misma tabla de idempotencia, sin alterar su esquema. Una
referencia del camino normal no puede reutilizarse en el camino cotización ni
viceversa. El UUID de conversión es distinto del UUID de emisión.

## Validaciones de origen y acceso

UC09 no recibe cliente, líneas, precios, descuento, medio de pago ni bodega
desde HTTP. Los obtiene de SQL. La sesión determina el actor; CSRF y RBAC se
verifican antes de invocar SQL. SQL exige COTIZACIONES_CONVERTIR y VENTAS_REGISTRAR,
usuario activo y autorización del documento.

**Decisión de acceso a aprobar:** creador de la cotización, o usuario que sea
Administrador activo, siempre con los dos permisos vigentes. Un usuario común
no puede convertir la cotización de otro creador por conocer su ID. Dos
administradores autorizados pueden competir por el mismo documento, pero solo
uno lo convierte. No se confunde permiso de consulta con permiso de conversión.

El wrapper valida por sí mismo esa autorización y el documento bloqueado;
no basta que UC09 haya validado. ClienteId debe coincidir. Comparar las líneas
del TVP en ambos sentidos con las líneas SQL, además de cardinalidad y unicidad:
ProductoId, Cantidad y DescuentoPorcentaje deben coincidir exactamente. Nunca
usar un precio enviado por el llamador ni SESSION_CONTEXT como prueba de origen.
El núcleo vuelve a comprobar origen/condiciones al tomar los precios históricos.

Mantener DENY EXECUTE al núcleo para securefinance_app y auditar que ningún
procedimiento nuevo conceda un acceso alternativo a ese núcleo sin wrapper.
Una llamada directa autorizada al wrapper con origen válido debe completar
**todo** el cierre de cotización; con origen ajeno/inventado o líneas distintas
debe fallar. No dejar una vía que emita factura y mantenga la cotización ACTIVA.

La cuenta SQL de aplicación sigue siendo una cuenta de servicio: los permisos
por actor no convierten un UsuarioId arbitrario en una identidad SQL personal.
HTTP nunca permite elegir ese actor; no se atribuye a esta extensión una nueva
garantía de autenticación SQL individual que la arquitectura actual no ofrece.

## Precios, descuentos, identidad documental y promociones

El núcleo mantiene bloqueo/validación de Producto activo y stock disponible,
pero usa P3_COT_Detalle.PrecioUnitario y su descuento para calcular los importes.
Conservar DECIMAL, descuento por línea y redondeo del motor, IVA 12% sobre neto
global. Comparar líneas, Subtotal, Descuento, SubtotalNeto, IVA y Total contra
la cotización **antes de confirmar**; cualquier diferencia revierte todo.
No cambiar temporalmente Producto.Precio ni corregir una factura ya emitida.

El actor de conversión debe poder autorizar el porcentaje pactado según
fn_ObtenerPoliticaVenta en ese momento. Si no puede, rechazar; no bajar el
descuento ni modificar el pacto silenciosamente.

La cotización actual no almacena MotivoDescuento ni procedencia de promoción.
**Propuesta para José:** las cotizaciones actuales se tratan como descuento
manual pactado; motivo de factura determinista `Ajuste comercial` cuando haya
descuento, NULL si no lo hay. No inferir una promoción desde Observaciones ni
etiquetar esas cotizaciones retroactivamente como promocionales. El wrapper
rechaza un motivo distinto para el origen cotización. La emisión futura con
promoción requerirá un contrato propio y evidencia de su incorporación una
sola vez; no reevaluar promociones al convertir esta versión.

**Identidad descriptiva a aprobar:** la cotización conserva su SKU, descripción,
nombre y NIT capturados al cotizar. La factura conserva la política vigente de
emisión: SKU/descripción de Producto y nombre/NIT del cliente al facturar. El
trigger tr_ERP_FacturaProductoEmision (39) ya captura esa identidad y el
comprobante prioriza FacturaProductoEmision; cambiar solo el JSON del wrapper
para poner la descripción cotizada daría comprobantes contradictorios.
Por ello la respuesta/cache del wrapper deben coincidir con el snapshot de
factura existente. Congelar **importes** no implica reescribir esos snapshots.
Si se exige trasladar también la identidad textual de la cotización a factura,
se necesita otra propuesta y aprobación de cambios a los triggers compartidos.

## Contado y multibodega: decisiones de Dylan

Solo contado: un MovimientoCaja por Total mediante el motor existente. No
crear otro movimiento, no aplicar notas de crédito ni simular cuentas por
cobrar. La extensión no se anuncia como compatible operativamente con crédito
hasta que su contrato real esté integrado. No aceptar modalidad ignorada.

Solo inventario global: no inventar bodegas ni migrar existencias históricas.
Una futura bodega de salida y modalidad de crédito deberán intervenir en el
contrato, la huella, los permisos y los bloqueos antes de habilitarse. Dylan
debe confirmar que la extensión opcional y el orden de locks no contradicen su
trabajo y que Kenneth es propietario del cambio común propuesto en esta fase.

## Transacción, cierre e idempotencia

El núcleo actual abre/confirma transacción solo si es propia. El wrapper actual
abre un nivel BEGIN TRANSACTION y lo equilibra con COMMIT; bajo una transacción
externa ese COMMIT no es confirmación durable independiente. Ambos pueden
revertir toda la transacción activa en CATCH; el llamador debe contemplarlo.

UC09 abre la transacción externa y llama al wrapper con líneas recuperadas de
SQL. El wrapper, dentro de esa transacción, crea la factura por el núcleo único,
almacena SolicitudVentaERP, cierra la cotización con Estado=PROCESADA y FacturaId,
inserta historial PROCESADA con actor/UUID y auditoría. Esto ocurre también si
el wrapper se invoca directamente. UC09 no repite ese cierre ni sus efectos.
Si el wrapper es la entrada externa, su COMMIT confirma el conjunto; si UC09
es la entrada, solo el COMMIT final de UC09 lo hace durable. No introducir
SAVEPOINT ni confirmar después de un error que haya revertido el conjunto.

Orden propuesto común a UC09 y al wrapper directo: validación del actor;
cabecera de cotización UPDLOCK/HOLDLOCK; applock `ERP.Venta.<UUID>` y fila del
libro; bloqueo compartido InventarioCorteParteII; validación del cliente y
política; productos por PK ascendente; Kardex y cierre documental. UC09 no
adquiere anticipadamente locks de producto, caja o UUID en orden inverso.
Revisar también cancelación y corte de inventario en las pruebas de contención.

Para primera conversión validar ACTIVA y reloj SQL antes de efectos de venta.
Al obtener todos los bloqueos necesarios y antes de generar Factura, volver a
validar vencimiento para que una espera por stock no habilite un pacto expirado.
Después del cierre, un reintento de resultado confirmado es una consulta
idempotente, no otra conversión: validar permisos/documento/actor/UUID/huella,
vínculo FacturaId e historial, y devolver el comprobante persistido aunque haya
expirado desde el COMMIT o ya no haya stock. No ejecutar otra vez el núcleo ni
exigir stock de una salida ya realizada. Un actor distinto o UUID distinto
no recibe ese trato de reintento, aunque ambos tengan permisos.

No usar solamente Estado=PROCESADA para inferir idempotencia. Si no coinciden
libro, factura e historial, rechazar y diagnosticar sin reparar automáticamente.
Un UUID reutilizado con distinta carga, actor, cotización o camino de venta
produce conflicto. No reasignar una factura existente a otra cotización.

Conservar los dos recordsets y sus columnas actuales en el wrapper (incluidos
tipos monetarios string). UC09 expone esos recordsets más un tercero de metadatos:
CotizacionId INT, FacturaId INT, Estado VARCHAR(15), OperacionId UNIQUEIDENTIFIER.
El servicio espera la finalización de la llamada/transacción completa antes de
anunciar éxito y construye el enlace desde FacturaId validado, no desde texto SQL.
El SQL no debe presentar un resultado intermedio como confirmación durable.

## Instalación e interfaz después de aprobación

43–49 no tienen archivos funcionales en esta revisión. Se propone 43 para la
extensión del motor y UC09, sin editar 21/37/41/42. Si se divide el cambio, se
debe documentar orden y garantizar que no se habilite el flujo parcialmente.
No alterar triggers compartidos con el alcance descriptivo aquí propuesto.

Instalar/validar primero en una copia restaurada. No ejecutar migraciones ni
pruebas de escritura en SecureFinanceERP. No actualizar el instalador Full ni
permisos de otros módulos unilateralmente.

La UI solo habilitará convertir cuando se verifiquen instalación de la firma
nueva, UC09 y EXECUTE efectivos, además de estado/permiso. No basta OBJECT_ID:
el motor viejo sin el parámetro opcional debe mantener el botón no disponible.
Conservar UUID estable, CSRF, confirmación, bloqueo de doble envío y mensajes
seguros para vigencia, stock, RBAC, conflicto y resultado incierto. No exponer
una venta de catálogo como sustituto de la conversión a precio histórico.

## Matriz de aceptación que deberá ejecutarse

| Caso | Aserción obligatoria en SQL real de laboratorio |
| --- | --- |
| A–E | Precio Q100 × 2, catálogo cambia a Q120, factura a Q100, catálogo a Q120; comparar todos los importes, stock, un Kardex por línea y un ingreso de caja |
| F | Mismo actor/UUID/cotización devuelve misma factura sin nuevos efectos, incluso tras vencer o agotarse stock |
| G | Otro UUID sobre cotización procesada falla sin escrituras |
| H | Dos actores autorizados simultáneos: una factura; dos cotizaciones por último stock: una salida y nunca stock negativo |
| I | Vencida/cancelada no genera factura; probar también vencimiento durante espera de bloqueo |
| J | Stock insuficiente conserva ACTIVA, sin factura/caja/Kardex parcial |
| K | Fallo de laboratorio después de Factura y antes de completar Kardex revierte factura, detalle, libro, caja, stock y estado; retirar inyección antes de pruebas finales |
| L | Wrapper directo con origen ajeno/inexistente o TVP/cliente/motivo alterado falla; origen válido autorizado cierra cotización de forma atómica |
| M | Venta normal posicional/nominal sin parámetro y con NULL explícito conserva política, importes y resultados |
| N | Reintento de SolicitudVentaERP anterior conserva hash, factura y JSON sin UPDATE del libro; colisión entre caminos falla |
| O | HTTP anónimo, sin permiso, CSRF inválido, actor falsificado; SQL con actor sin permiso, descuento no autorizado y acceso directo al núcleo denegado |
| Descriptivos | Cambiar SKU/descripción y nombre/NIT entre emisión y conversión; cotización conserva snapshot propio y factura/cache coinciden con su snapshot al facturar |

Pruebas adicionales: npm run check, npm test, Chromium escritorio/móvil,
git diff --check, integridad SQL y comparación de documentos anteriores.
Ningún caso de conversión se declara aprobado en esta revisión documental.

## Decisiones pendientes exactas

1. **José:** aceptar descuento manual congelado, política vigente del actor,
   motivo determinista y ausencia de aplicación/reevaluación promocional.
2. **Dylan:** aceptar solo contado/caja única e inventario global; coordinar
   puntos de extensión futuros y el propietario/orden de cambios compartidos.
3. **Integrador y afectados:** aceptar regla creador/Administrador, cierre
   obligatorio en wrapper directo y política descriptiva de factura vigente.
4. **Todos los revisores afectados:** aprobar firmas opcionales, compatibilidad
   de huellas/recordsets, reglas de reintento, transacción y matriz de aceptación.

Hasta registrar esas aprobaciones explícitas, mantener el PR en borrador y
conservar intactos los procedimientos compartidos, sin crear migración 43.

## Verificación de esta actualización documental

Diff limitado a este documento, la propuesta inicial y el texto del PR.
`git diff --check` satisfactorio. Sin cambios en database/, src/, server.js ni
package.json respecto de 1c6f813; no se ejecutaron SQL, migraciones o pruebas de
conversión en esta revisión. Los resultados anteriores siguen identificados
en RESULTADOS.md y no acreditan UC09. No se modificó el PR #11.
