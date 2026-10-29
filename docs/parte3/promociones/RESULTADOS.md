# Resultados de pruebas — Promociones (José)

Ejecutado el 2026-10-29 sobre esta rama, con SQL Server local (instancia por
defecto, autenticación de Windows). Laboratorio aislado creado de cero, sin
tocar `SecureFinanceERP` ni ninguna otra base existente.

## Laboratorio aislado

`database/tests/promocionesLab.js --build` crea una base **nueva**,
`SecureFinanceERP_P3_PRO_<fecha>_<hex>`, marcada con una propiedad extendida
(`Promociones.TestRun`), e instala en ella: el instalador `Full.sql`
(seguridad, negocio, auditoría), las migraciones 15–44 (Parte II completa y
Cotizaciones 41–43, saltando los huecos 27–29 inexistentes) y un login de
SQL Server exclusivo del laboratorio para la cuenta de aplicación
(`sfapp_<base>`, `CHECK_POLICY=OFF`, sin `db_owner`). `--install` aplica
60–63. El estado queda en `.data/promociones-lab.json` (no versionado).

Última ejecución: base `SecureFinanceERP_P3_PRO_20261029002709_7bd25017`,
login `sfapp_P3_PRO_20261029002709_7bd25017`. Reconstruida **dos veces**
desde cero para probar reproducibilidad del instalador; ambas veces con el
mismo resultado.

## `node database/tests/PromocionesIntegration.js`

**29/29 PASS.** Cubre los 20 escenarios de aceptación del PDF más la
verificación del contrato histórico, la vista previa, la función escalar,
la reinstalación y la integridad final:

| # | Prueba | Resultado |
| --- | --- | --- |
| 0 | Contrato de venta sin promociones intacto (huella histórica SHA-256, firma posicional, dos recordsets) | PASS |
| 1 | Crear promoción porcentual (inactiva) y activarla | PASS |
| 2 | Crear promoción 2x1 | PASS |
| 3 | Crear promoción por volumen | PASS |
| 4 | Crear promoción por categoría (extensión incremental de categorías) | PASS |
| — | Reglas fuera de condiciones autorizadas rechazadas (tipo, mínimo, porcentaje, elegibilidad, vigencia, código duplicado) | PASS |
| 5 | Venta con promoción vigente + línea sin promoción; IVA 12% y total exactos | PASS |
| 6 | Venta sin promoción elegible | PASS |
| — | 2x1: `FLOOR(cantidad/2)` bonificadas, importe nunca supera el beneficio teórico | PASS |
| — | Volumen: no aplica bajo el mínimo, aplica desde el mínimo configurado | PASS |
| — | Categoría: solo el producto asignado recibe el beneficio | PASS |
| 7 | Venta con promoción futura (`PROGRAMADA`) no aplica | PASS |
| 8 | Venta con promoción vencida no aplica; no se edita una regla vencida | PASS |
| 9 | Dos reglas elegibles → se elige el mayor descuento monetario | PASS |
| — | Empate determinista: gana la regla más antigua (`PromocionId` menor) | PASS |
| 10 | Comprobar IVA y total | PASS (incluido en los casos anteriores) |
| 11 | Sin descuento doble: por línea gana el mayor entre manual y promoción, nunca la suma | PASS |
| — | Superposición del mismo tipo y producto rechazada al activar | PASS |
| 12 | Verificar factura histórica (comprobante y aplicación conservados) | PASS |
| 13/14 | Cambiar/desactivar la regla tras la venta: factura pasada intacta (hash SHA-256 de tablas previas), historial anterior/nuevo, triggers de protección (`P3_PRO_PromocionProtegida`, inmutabilidad) | PASS |
| 15 | Reintentar una venta con promoción (mismo comprobante); otra carga u otro modo con la misma referencia se rechaza | PASS |
| 16 | Concurrencia: 8 ventas simultáneas por 5 unidades → 5 facturas con promoción y stock en 0; misma referencia simultánea → un solo comprobante; desactivación concurrente de la regla espera/resuelve sin mezclar estados | PASS |
| 17 | Usuario sin autorización: cajero no consulta ni administra reglas (SQL 54101); DML directo y función escalar vía el login de aplicación denegados; el cajero sí vende con la regla vigente y su propio tope de descuento manual (10%) | PASS |
| 18 | Integración con cotización convertida: conserva el precio pactado (Q201.60) sin reevaluar la promoción del 25%; combinar cotización + promociones se rechaza explícitamente (57111) | PASS |
| 19 | ROLLBACK ante error (trigger de falla tras insertar en Kardex): factura, detalle, aplicación, caja y stock revierten completos; la misma referencia se recupera después | PASS |
| — | Vista previa SQL coincide con los importes definitivos de la venta | PASS |
| — | `dbo.fn_ObtenerDescuentoPromocional`: parámetros tipados, fecha de operación, categoría propia vs. ajena, comparación de beneficios | PASS |
| — | Reinstalación 60–63 repetible: datos, facturas e idempotencia conservados | PASS |
| — | `DBCC CHECKDB`, `DBCC CHECKCONSTRAINTS` y consistencia `P3_PRO_AplicacionFactura`↔`DetalleFactura` | PASS |

Las pruebas insertan únicamente datos propios (prefijo `QA PRO`/`QAPRO`),
ejecutan sobre la base aislada y se valen de `promos`, `ventas`, `facturas`
y `cotizaciones` reales (mismos servicios que usa la aplicación en
producción), no mocks.

## `npm test` (unidad e HTTP, Node, sin SQL real)

**128/128 PASS**, incluidas 13 pruebas nuevas en `tests/promociones.test.js`:
validación de reglas por tipo/elegibilidad, validación de estado y filtros,
validación de la vista previa, mapeo del servicio a procedimientos/TVP
propios (sin texto dinámico), manejo de "extensión no instalada" (error
2812), navegación y escape HTML, RBAC por los cuatro permisos nuevos, CSRF
obligatorio en toda escritura, alta/edición/cambio de estado con CSRF
válido, alta y asignación de categorías, mensajes seguros para cada código
de error de negocio (sin exponer texto SQL interno), vista previa de
facturación de solo lectura, y la integración de `ventaService` que omite
el parámetro opcional cuando la extensión no está instalada. Las 115
pruebas preexistentes de otros módulos siguen pasando sin cambios.

## `npm run check`

PASS. Incluye `node --check` de los cinco archivos nuevos de JavaScript del
módulo y de los dos archivos nuevos del arnés de pruebas SQL.

## `git diff --check`

PASS, sin advertencias de espacios en blanco.

## Hallazgos de SQL Server documentados durante la implementación

1. `CONVERT(VARCHAR(16), columna_rowversion, 2)` no produce la
   representación hexadecimal esperada — copia los bytes crudos en lugar de
   aplicar el estilo 2. Es necesario convertir primero explícitamente a
   `BINARY(8)`: `CONVERT(VARCHAR(16), CONVERT(BINARY(8), columna), 2)`.
   Corregido en los cuatro `SELECT` de `62_P3_PRO_Administracion.sql` que
   devuelven `Version` al cliente.
2. Un patrón `LIKE N'%[^A-Z0-9_-]%'` evaluado con `COLLATE
   Latin1_General_100_BIN2` no trata el guion ni el guion bajo como
   literales al final del conjunto de caracteres — los excluye
   incorrectamente. Mover el guion al **inicio** del conjunto
   (`[^-A-Z0-9_]`) corrige el comportamiento sin perder la sensibilidad a
   mayúsculas que motivó usar `_BIN2`. Corregido en la validación de
   `@Codigo` de `P3_PRO_Crear`.
3. `sqlcmd` no preserva de forma fiable texto no ASCII (tildes, "ó", etc.)
   cuando el resultado se captura por `stdout`/pipe, incluso con `-f
   65001`/`-f i:65001,o:65001`: el *input* se interpreta correctamente con
   `-f i:65001`, pero la *salida* usa el codepage OEM de la consola salvo
   que se escriba a un archivo con `-u -o <archivo>` y se lea como
   UTF-16LE. El arnés de pruebas (`promocionesLab.js`) usa ese patrón para
   sus lecturas JSON; no afecta a la aplicación Node, que siempre consulta
   SQL Server mediante `mssql` (TDS binario), no mediante `sqlcmd`.
