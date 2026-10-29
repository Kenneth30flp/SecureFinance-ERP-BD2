# Módulo 4 — Motor de descuentos y promociones (José)

Responsable: José Miguel de León Aguilar. Rama `feature/p3-jose-promociones`,
base `integracion/parte3`. Migraciones reservadas 60–69, prefijo `P3_PRO_`.

## 1. Alcance

Implementa el módulo completo de promociones sobre facturación de contado:
- Interfaz `/promociones` (consulta, alta, edición, activar/desactivar, filtros,
  vigencia, condiciones, historial).
- Modelo de datos incremental con integridad referencial y estados.
- Función escalar obligatoria `dbo.fn_ObtenerDescuentoPromocional`.
- Resolución determinista de "mejor promoción" sin acumulación con el
  descuento manual existente.
- Integración con `sp_ERP_ProcesarVenta` / `sp_ProcesarVentaTransaccional`
  mediante un parámetro opcional (`@P3AplicarPromociones`), sin romper el
  contrato vigente para Cotizaciones (UC09) ni para llamadas históricas.
- Seguridad SQL por procedimiento (RBAC), permisos Express y ocultamiento en
  la interfaz para quien no los tiene.
- Pruebas de aceptación en un laboratorio aislado y pruebas Node de unidad e
  HTTP.

No se modificó `Producto`, `Factura`, `DetalleFactura`,
`TipoDetalleVentaDescuento`, `SolicitudVentaERP` ni el TVP existente. No se
alteró el descuento manual por línea: sigue existiendo y compite contra la
promoción línea por línea.

## 2. Migraciones

| Archivo | Contenido |
| --- | --- |
| `60_P3_PRO_EstructuraPromociones.sql` | Tablas, catálogo de tipos, extensión de categorías, historial inmutable, aplicaciones por factura, permisos. |
| `61_P3_PRO_MotorPromociones.sql` | Funciones de estado, regla en JSON, `P3_PRO_fn_EvaluarPromociones`, `fn_ObtenerDescuentoPromocional`, `P3_PRO_fn_ResolverLinea`, `P3_PRO_SimularVenta`. |
| `62_P3_PRO_Administracion.sql` | CRUD de reglas, categorías, validación de configuración y de superposición, consultas e historial. |
| `63_P3_PRO_IntegracionFacturacion.sql` | Copia íntegra de la definición vigente de `sp_ProcesarVentaTransaccional` y `sp_ERP_ProcesarVenta` (migración 43) con el parámetro opcional `@P3AplicarPromociones` añadido **al final**; aplicación registrada por línea; consulta de evidencia para el comprobante. |

Todas son `CREATE OR ALTER`, repetibles, con bloque `BEGIN TRY/CATCH` y
transacción donde corresponde. 60 valida que exista Parte II hasta 40 y
Cotizaciones 41–43 antes de instalar.

## 3. Modelo de datos

- `P3_PRO_TipoPromocion`: catálogo fijo (`PORCENTAJE`, `CATEGORIA`,
  `DOS_POR_UNO`, `VOLUMEN`) con su elegibilidad (`PRODUCTO`/`CATEGORIA`).
- `P3_PRO_Categoria` / `P3_PRO_ProductoCategoria`: extensión incremental.
  El catálogo no tenía categorías de producto; se agregó una tabla propia con
  **una categoría por producto** (clave primaria `ProductoId`), sin tocar
  `Producto` ni inventar relaciones con proveedores o Kardex.
- `P3_PRO_Promocion`: regla con tipo, condiciones (`Porcentaje`,
  `CantidadMinima`, `TopeDescuento` opcional), vigencia `[VigenteDesde,
  VigenteHasta)`, `Activa`, auditoría de creación/modificación y
  `ROWVERSION` para control de concurrencia optimista. `CHECK` por tipo
  impide, por ejemplo, un 2x1 con porcentaje o una promoción con 95%.
- `P3_PRO_PromocionProducto` / `P3_PRO_PromocionCategoria`: elegibilidad
  exclusiva según el tipo (nunca ambas a la vez).
- `P3_PRO_HistorialPromocion` / `P3_PRO_HistorialCategoria`: inmutables
  (`AFTER UPDATE,DELETE` lanza error), con `ValorAnterior`/`ValorNuevo` JSON,
  actor, fecha UTC, `OperacionId` único (idempotencia) y motivo obligatorio.
- `P3_PRO_AplicacionFactura`: una fila por línea de factura con promoción
  aplicada (clave única por `DetalleFacturaId`: una promoción por línea).
  Conserva cantidad, precio, unidades bonificadas, beneficio teórico,
  porcentaje/monto registrado, el **descuento manual descartado**, la
  versión de la regla (`ROWVERSION`) y una copia JSON de la regla completa al
  momento de facturar. Es inmutable.

### Política de estados

`VENCIDA` (vigencia terminada) > `INACTIVA` (`Activa=0`) > `PROGRAMADA`
(`VigenteDesde` futuro) > `VIGENTE` (el resto). Solo `VIGENTE` participa en
ventas. Una regla ya aplicada en facturas solo admite cambiar nombre,
descripción o adelantar su fin (trigger `P3_PRO_PromocionProtegida`); sus
productos/categorías quedan congelados (`P3_PRO_ElegibilidadProtegida`).

### Superposición

Dos promociones **activas del mismo tipo**, con vigencias que se cruzan y al
menos un producto o categoría en común, se rechazan al activarlas
(`P3_PRO_ValidarSuperposicion`, error 57109). Promociones de **tipos
distintos** sí pueden coincidir: la venta elige la de mayor beneficio
(desempate abajo).

## 4. Función escalar obligatoria

```sql
dbo.fn_ObtenerDescuentoPromocional
 (@ProductoId INT, @CategoriaId INT, @Cantidad INT,
  @PrecioUnitario DECIMAL(12,2), @FechaOperacion DATETIME2(3))
RETURNS DECIMAL(19,2)
```

Determinista: dados los mismos parámetros y el mismo estado de reglas,
devuelve siempre el mismo importe. `@CategoriaId` es opcional; si se indica,
debe coincidir con la categoría asignada al producto (no permite "probar"
una categoría ajena). Internamente usa la TVF auxiliar
`P3_PRO_fn_EvaluarPromociones` (justificada: expone el ranking completo para
que la venta registre **qué** promoción ganó, sin duplicar la fórmula) y
`P3_PRO_fn_Regla` (serializa la regla a JSON para el historial y la
evidencia). No hay SQL dinámico concatenado en ningún objeto del módulo.

### Cálculo por tipo

- `PORCENTAJE` / `CATEGORIA` / `VOLUMEN`: `BeneficioTeorico = ROUND(Subtotal
  × Porcentaje / 100, 2)`. En `VOLUMEN` solo aplica si `Cantidad >=
  CantidadMinima`.
- `DOS_POR_UNO`: `UnidadesBonificadas = FLOOR(Cantidad / 2)`;
  `BeneficioTeorico = PrecioUnitario × UnidadesBonificadas` (de cada dos
  unidades iguales en la línea, se bonifica una).
- `TopeDescuento` (opcional) limita el beneficio teórico por línea.
- El **importe registrable** respeta el `CHECK` existente de
  `DetalleFactura` (`DescuentoMonto = ROUND(Subtotal × DescuentoPorcentaje /
  100, 2)` con `DescuentoPorcentaje DECIMAL(5,2)`). Cuando el beneficio
  teórico coincide exactamente con `Subtotal × Porcentaje / 100` (porcentaje
  simple sin tope) se usa el porcentaje configurado. En 2x1 y en topes se
  busca el mayor porcentaje de dos decimales cuyo importe no exceda el
  beneficio teórico: nunca se concede más de lo autorizado por la regla.

### Mejor promoción y desempate

Cuando varias reglas son elegibles para una línea, gana la de **mayor
importe monetario registrable**; en empate, la de **mayor beneficio
teórico**; en empate persistente, la de **menor `PromocionId`** (la más
antigua). Esto es determinista y se implementa con `ROW_NUMBER() OVER(ORDER
BY DescuentoMonto DESC, BeneficioTeorico DESC, PromocionId ASC)`.

## 5. Política de aplicación (acordada para evitar duplicados)

- **No se acumulan promociones ni promoción + descuento manual.** Por línea
  se compara el descuento manual autorizado contra la mejor promoción
  elegible y se aplica el **mayor** de los dos; en empate gana la promoción
  (deja evidencia trazable). El perdedor se registra como
  `DescuentoManualDescartado` en `P3_PRO_AplicacionFactura`, nunca se suma.
- **Límite por rol:** se mantiene `fn_ObtenerPoliticaVenta`
  (`MaxDescuento`); el descuento manual sigue topado al 10% para cajeros y
  100% para Administrador. La promoción no está sujeta a ese límite (es una
  regla autorizada por quien tiene `PROMOCIONES_ACTIVAR`), pero si gana el
  manual, sigue limitado por la política de rol vigente del actor.
- **IVA y redondeo:** sin cambios respecto al motor existente — 12% sobre el
  subtotal neto global (`SUM(Subtotal) − SUM(DescuentoMonto)`), `ROUND` a
  centavos con mitades hacia arriba, solo `DECIMAL`.
- **Vigencia:** se evalúa a `SYSUTCDATETIME()` dentro de la misma
  transacción del `sp_ProcesarVentaTransaccional`, después de bloquear
  `Producto` (`UPDLOCK`/`HOLDLOCK`) y de tomar `sp_getapplock
  'P3.PRO.Reglas'` en modo compartido. Una edición o activación concurrente
  (modo exclusivo) espera o hace esperar a la venta: nunca se mezcla una
  regla a medio cambiar con la transacción de venta.
- **Productos no elegibles:** un producto sin promoción asociada (o con
  categoría inactiva/sin categoría) simplemente no recibe beneficio; solo
  compite el descuento manual de la línea.
- **Cotizaciones (coordinado con Kenneth):** una cotización convertida
  (`@P3CotizacionId` no nulo) **nunca** reevalúa promociones — conserva el
  precio pactado congelado en la cotización. Combinar ambos parámetros se
  rechaza explícitamente (error 57111) para que no exista ambigüedad sobre
  cuál importe es el que manda.

## 6. Integración SQL con facturación (contrato extendido, no reemplazado)

`sp_ProcesarVentaTransaccional` y `sp_ERP_ProcesarVenta` ganan **un único
parámetro opcional al final**, `@P3AplicarPromociones BIT = 0`:

- Con `0`/`NULL` (valor por defecto): el cuerpo ejecutado, la huella
  SHA-256, el TVP, los bloqueos y los dos recordsets de respuesta son
  **idénticos** a la migración 43 — incluida la llamada posicional antigua
  (`EXEC dbo.sp_ERP_ProcesarVenta @Cliente,@Usuario,@Detalle,@OperacionId`).
  Node solo envía `1` cuando la extensión está instalada **y** quien llama
  pidió promociones explícitamente (`ventaService.promocionesInstaladas()`).
- Con `1` (ruta exclusiva de Facturación de contado, sin cotización): toma
  el bloqueo compartido de reglas, evalúa `P3_PRO_fn_ResolverLinea` por
  línea ya bloqueada, sustituye `DescuentoPorcentaje`/`DescuentoMonto` de la
  línea cuando gana la promoción, inserta `Factura`/`DetalleFactura` igual
  que siempre y **además** inserta `P3_PRO_AplicacionFactura` dentro de la
  **misma transacción**, antes del `COMMIT`. Si alguna aplicación resulta
  inconsistente (p. ej. el importe no coincide con el escalar), se lanza
  57112 y toda la venta revierte.
- La huella de idempotencia usa un prefijo distinto (`P3PRO:v1|...`) cuando
  se piden promociones, así una venta con promociones nunca puede
  "reclamar" el comprobante de una venta sin ellas con el mismo UUID, y
  viceversa (ambos sentidos probados).
- El reintento de una venta ya registrada **no reevalúa** reglas: devuelve
  el comprobante y la evidencia de promoción ya guardados
  (`P3_PRO_AplicacionesDeFactura`), igual que el resto del comprobante
  histórico.
- Kardex, caja y el resto de la operación ACID no cambian: siguen dentro de
  la misma transacción, con el mismo orden de bloqueos por PK ascendente.

No se reemplazó el procedimiento compartido: se extendió conservando su
firma, su comportamiento por defecto y las pruebas de regresión de Parte II
y de UC09 (ver `database/tests/PromocionesIntegration.js`, primera prueba).

## 7. Seguridad

Permisos nuevos, asignados inicialmente solo a `Administrador` (igual
patrón que Cotizaciones):

| Código | Uso |
| --- | --- |
| `PROMOCIONES_CONSULTAR` | Ver reglas, condiciones, vigencia e historial. |
| `PROMOCIONES_CREAR` | Crear reglas (quedan `INACTIVA`). |
| `PROMOCIONES_MODIFICAR` | Editar reglas y administrar categorías. |
| `PROMOCIONES_ACTIVAR` | Activar/desactivar una regla ya creada. |

Un cajero (rol `Cajero`, solo `VENTAS_REGISTRAR`) **no** puede crear,
editar, activar ni siquiera *consultar* reglas (`sp_ParteII_ValidarPermiso`
lo rechaza con 54101 en SQL; Express lo oculta de `/promociones` y del
menú; la interfaz no muestra el enlace). Sí participa automáticamente de la
mejor promoción al vender, porque esa evaluación ocurre dentro del motor de
venta, no en una ruta administrativa.

Todas las tablas del módulo están en `DENY SELECT/INSERT/UPDATE/DELETE` para
`securefinance_app`; solo los procedimientos públicos (`P3_PRO_Crear`,
`P3_PRO_Actualizar`, `P3_PRO_CambiarEstado`, `P3_PRO_Consultar`,
`P3_PRO_PrepararFormulario`, `P3_PRO_BuscarProductos`,
`P3_PRO_CrearCategoria`, `P3_PRO_AsignarCategoria`, `P3_PRO_SimularVenta`,
`P3_PRO_ConsultarAplicacionesFactura`) tienen `GRANT EXECUTE`. Las funciones
auxiliares y los procedimientos de validación internos están en `DENY`. La
autoría (actor, operación, motivo) se registra en `P3_PRO_HistorialPromocion`
/ `P3_PRO_HistorialCategoria` y en `Bitacora_Transacciones`, con valor
anterior y nuevo en JSON.

CSRF propio del módulo (`X-CSRF-Token` por sesión, token de 32 bytes), igual
patrón que `cotizaciones.js`/`kenneth.js`. Idempotencia por `OperacionId`
(UUID v4) con `sp_getapplock` exclusivo por operación y comparación de la
carga completa (hash SHA-256) para rechazar una referencia reutilizada con
datos distintos.

## 8. Interfaz

`/promociones` (consulta con filtros por código/nombre, tipo y estado),
`/promociones/nueva` y `/promociones/:id/editar` (alta/edición con
condiciones según tipo, selector de productos o categorías), `/promociones/:id`
(detalle con condición, elegibilidad, aplicaciones recientes, historial
anterior/nuevo y acción de activar/desactivar) y `/promociones/categorias`
(alta de categorías y asignación producto↔categoría). La vista previa de
Facturación (`/facturacion`) consulta `GET /promociones/vista-previa`
(solo lectura, mismo cálculo SQL) para mostrar el beneficio estimado por
línea mientras se captura la venta; el **cálculo definitivo** siempre ocurre
en `sp_ProcesarVentaTransaccional` al confirmar. El comprobante de factura
(`/facturacion/facturas/:id`) muestra la promoción aplicada a cada línea,
leída de `P3_PRO_AplicacionFactura` a través de
`P3_PRO_ConsultarAplicacionesFactura` (permiso `FACTURAS_CONSULTAR`).

CSS reutiliza el lenguaje visual de `cotizaciones.css` (tarjetas, estados,
tablas) y añade `promociones.css` propio con prefijo `pro-`, sin modificar
reglas existentes.

## 9. Coordinación con el equipo

- **Kenneth (Cotizaciones):** una cotización convertida nunca aplica
  promociones (sección 5); se probó explícitamente que combinar ambos
  parámetros se rechaza y que la conversión sigue dando exactamente el
  mismo total que antes de este módulo (prueba "contrato de venta sin
  promociones intacto").
- **Dylan (Créditos/Multibodega/Auditoría DDL):** el módulo no toca medios
  de pago, bodega ni triggers de auditoría DDL; usa el mismo
  `Bitacora_Transacciones` y el mismo patrón de inmutabilidad por trigger
  que el resto del sistema.
- El contrato de `sp_ERP_ProcesarVenta`/`sp_ProcesarVentaTransaccional` se
  extendió únicamente al final de la lista de parámetros, preservando la
  firma anterior para cualquier otro consumidor.

## 10. Pendientes conocidos

- El laboratorio de pruebas (`database/tests/promocionesLab.js`) crea un
  login de SQL Server propio del laboratorio (nombre derivado del nombre de
  la base) porque el bloque de permisos de `10_AppPermissions.sql`/Full.sql
  comprueba el nombre literal `securefinance_app` a nivel de servidor; el
  script repite esos mismos `GRANT` explícitamente tras crear el `USER`.
  Esto es exclusivo del arnés de pruebas, no cambia la instalación real.
- Se detectaron y corrigieron dos particularidades de SQL Server durante la
  implementación, documentadas como comentarios en el código:
  `CONVERT(VARCHAR(n), rowversion_column, 2)` no aplica el estilo hex salvo
  que se convierta primero a `BINARY(8)`; y un patrón `LIKE
  '%[^A-Z0-9_-]%'` bajo collation `_BIN2` requiere el guion al **inicio**
  del conjunto de caracteres (`[^-A-Z0-9_]`) para no interpretarse como
  rango.
