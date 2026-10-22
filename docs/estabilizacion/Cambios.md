# Estabilización funcional ERP — Kenneth

Rama: `feature/estabilizacion-funcional-erp`. Base: `6e8324b`, que contiene PR #6, #8, #9 y #10. `origin/main` estaba actualizado y el árbol de trabajo limpio. No se descartaron cambios, no se modificó main ni se alteraron credenciales. Se conserva Node/Express/EJS/CSS/JavaScript/SQL Server.

## Cambios y decisiones

| Fallo comprobado | Corrección | Evidencia |
| --- | --- | --- |
| La ficha de producto no ofrece recepción | Acción separada «Ingresar existencias» hacia Inventario, confirmación, proveedor y documento | SQL A/B y navegador con SQL |
| Compra sin proveedor histórico | RecepcionCompra + DetalleRecepcionCompra con FK al único Kardex central | SQL A–E, concurrencia |
| Un solo proveedor por SKU | ProductoProveedor; principal compatible, alternativos activables, productos por proveedor | Regresión SQL y consultas web |
| Notas limitadas a PENDIENTE | Libro inmutable de aplicaciones con saldo previo/final y reembolsos externos documentados | SQL H–J, concurrencia, navegador |
| Venta reintentada puede duplicarse | SolicitudVentaERP y wrapper transaccional con operación estable y comprobante persistido | Regresión y venta concurrente |
| Una nota de importe cero no puede avanzar | Emisión LIQUIDADA sin crear pagos ni aplicaciones; auditoría de normalización | EdgeCases SQL |
| Analítica visible en inglés y GTQ sin agrupación | Textos en español, agrupación monetaria sobre cadenas decimales | Vistas y pruebas UI |
| README negaba recuperación ya implementada | Referencia a documentación vigente | Código existente y regresiones Node |

## Recepción de mercancía

Productos → seleccionar SKU → **Ingresar existencias** → Inventario → abrir **Ingresar existencias o registrar ajuste** → tipo Compra → proveedor activo → cantidad → documento y motivo → revisar stock previsto → confirmar.

También se accede directamente desde Inventario. Se consulta/busca al proveedor por nombre o NIT. La primera recepción documentada puede crear la relación comercial con ese SKU. No cambia el proveedor principal ni atribuye el stock antiguo. La recepción es de un producto por confirmación; cabecera y detalle permiten conservar las referencias de cada compra sin duplicar el SKU.

El comprobante histórico Kardex muestra stock anterior, cantidad, saldo resultante, fecha UTC, proveedor, documento, responsable y OperacionId. Cada recepción nueva conserva también nombre y NIT del proveedor al emitirla. Las filas antiguas sin recepción indican **Sin evidencia histórica**. La vista previa no reserva existencias: el saldo definitivo procede de SQL.

La única escritura de Stock continúa dentro de `sp_RegistrarMovimientoKardex`. Recepción, relación comercial nueva, movimiento y auditoría se confirman juntos. El costo unitario es opcional: NULL significa desconocido y nunca sustituye PrecioCosto. No se implementa valoración promedio, cuentas por pagar ni una compra pagada ficticia.

## Crédito

`Estado = EMITIDA` conserva el estado documental. `EstadoCredito = PENDIENTE / PARCIAL / LIQUIDADA` refleja el saldo, independiente de la factura original. Se permiten aplicaciones parciales y finales hasta el saldo disponible. Una nota de total cero nace liquidada sin aplicaciones monetarias.

La operación implementada es **REEMBOLSO_DOCUMENTADO**: un operador autorizado registra el monto y la referencia de un reembolso efectuado externamente. El ERP **no ejecuta transferencias**, verifica bancos ni fabrica pagos. La verificación del comprobante externo corresponde al operador autorizado. El formulario lo explica y pide confirmación. La historia conserva actor, fecha, operación y saldos; se imprime junto con la nota.

No se ofrece compensación contra ventas futuras: el modelo actual registra ventas pagadas en caja y no dispone de cuentas por cobrar. Agregarla exige integrar un medio de pago por crédito dentro de la misma transacción de venta, con conciliación contable; no corresponde descontar una factura histórica ya pagada.

`NOTAS_CREDITO_APLICAR` es un permiso nuevo. No se asigna automáticamente a todos los administradores; el despliegue requiere asignarlo al rol financiero revisado. Consulta y registro son permisos distintos. Las escrituras verifican nuevamente en SQL los permisos vigentes del actor de sesión.

## Venta

La página emite un UUID estable por formulario. `sp_ERP_ProcesarVenta` serializa la operación, conserva una huella canónica y llama una sola vez a `sp_ProcesarVentaTransaccional`; no recalcula IVA/descuentos ni descuenta stock nuevamente. Conserva el comprobante para responder reintentos. La misma referencia con contenido distinto se rechaza. Se bloquea la ejecución directa desde la cuenta de aplicación de los procedimientos antiguos de venta y del Kardex; la cadena de propiedad conserva sus llamadas internas.

## Cobertura de revisión y límites

| Área | Validación realizada | Límite |
| --- | --- | --- |
| Login, sesiones, recuperación, usuarios y roles | Revisión de rutas, permisos, servicios y pruebas Node existentes; sesión Express en navegador | Login SQL con contraseña existente pendiente; no se cambiaron credenciales. No se prueba entrega real de correo |
| Inventario, productos y proveedores | Recepción real, múltiples proveedores, relaciones, rollback, permisos SQL, concurrencia, navegador y fotografía cubierta por regresiones Node | Alta/edición/foto no se volvieron a ejecutar con SQL desde navegador |
| Clientes | Inactivación SQL preserva factura; regresiones de alta, edición y NIT; selección y consulta web | No se cambió NIT fiscal real en laboratorio |
| Facturación | Venta SQL/UI, comprobante, Kardex, caja, idempotencia y concurrencia; descuentos/IVA por regresiones existentes | No integración con FEL ni medios bancarios externos |
| Devoluciones | Factura y detalle reales, parcial, reingreso, nota única, defecto sin reingreso, reintentos | No se ejecutaron todas las suites históricas |
| Notas de crédito | Parcial/final, saldo, rechazo de exceso, doble envío, concurrencia, impresión y navegador | Reembolso es registro documental externo |
| Garantías | Apertura vinculada a venta QA real, diagnóstico, historial, transición inválida y versión obsoleta | No se afirma completar todas las combinaciones de cobertura en esta entrega |
| Dashboard y analítica | TVF de José conciliadas con tablas, reposición con stock actual, tickets, consultas con permiso, páginas reales | Ventas son importes facturados brutos; devoluciones/créditos no reescriben ventas originales |
| Auditoría y seguridad | Actor de sesión, CSRF/RBAC, parámetros SQL, DML directo denegado, auditoría y DBCC | No es una certificación de seguridad ni prueba de recuperación de correo |

Los tickets y comprobantes QA se crearon exclusivamente en la base aislada y se identifican como tales. No representan atenciones, compras o reembolsos operativos. No se renombraron identidades DEMO ni se tocó la NC-1 operativa.

## Pruebas y evidencia

Se verificó un respaldo existente con RESTORE VERIFYONLY, se restauró en `SecureFinanceERP_Estabilizacion_20261021` con archivos separados y se ejecutó DBCC CHECKDB. El respaldo era anterior a posventa: se aplicaron 24–26 y 30–32 en la copia antes de 33–37. Nunca se ejecutó Full. Las migraciones históricas no fueron editadas.

- [Resultados SQL A–O y regresiones](evidencias/sql-resultados.txt).
- [Concurrencia](evidencias/concurrencia.txt).
- [Resultados del navegador con SQL](evidencias/navegador.json).
- [Capturas y comprobante](evidencias/).
- Scripts reproducibles en `database/tests/Stabilization*.{sql,js}` y `tests/browser/stabilization.browser.js`.

El navegador adicional usa SQL real y cookies de sesión reales. La ejecución identificada `SESSION_FIXTURE_NOT_REAL_LOGIN` sustituye exclusivamente la autenticación; **no demuestra login SQL con contraseña real**. El modo predeterminado exige credenciales existentes en `.data/qa-login.local.json` (ignorado por Git), sin cambiarlas ni incluirlas en evidencias.

La [comprobación posterior acotada del login](LoginReal.md) confirmó el destino aislado y la protección anónima de los cinco módulos solicitados. Se preparó y ejecutó un acceso manual seguro en navegador, sin exigir archivos al operador. El plazo de quince minutos terminó sin confirmar una sesión autenticada y el perfil temporal fue eliminado. El acceso autenticado sigue pendiente; el PR permanece en borrador.

Los fixtures HTTP de las pruebas existentes se ampliaron para el nuevo proveedor requerido y los nuevos contratos de procedimientos/UUID. No se eliminaron aserciones de negocio ni se marcaron pruebas como omitidas.
