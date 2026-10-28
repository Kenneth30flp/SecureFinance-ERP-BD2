# Validación ejecutada — 2026-10-27

Este archivo conserva la validación de la entrega independiente. Para la versión
completa con conversión consultar [RESULTADOS_UC09.md](RESULTADOS_UC09.md).

Base de laboratorio: `SecureFinanceERP_P3_COT_20261027210601_0f1e9dec`.
Restauración nueva desde respaldo COPY_ONLY existente; 40 instalada solo en
copia porque el respaldo la precedía. No se aplicó SQL a SecureFinanceERP.

| Verificación | Resultado |
| --- | --- |
| npm run check | PASS, incluye sintaxis de archivos nuevos |
| npm test | 102/102 PASS, cero fallidas/omitidas; siete pruebas nuevas Node |
| git diff --check | PASS |
| CotizacionesIntegration.js | PASS, 14 grupos de aserciones SQL reales |
| Chromium con SQL real | PASS, nueve comprobaciones; desktop 1366 y anchos 768/390/320 |
| Reaplicación 41–42 | PASS, documentos/detalles/historial conservados |
| Comparación contra baseline de laboratorio | PASS: no se agregaron Factura, DetalleFactura, MovimientoCaja ni Kardex |
| Hashes de núcleo de venta y Kardex | PASS, sin cambios |
| Conciliación historial / Bitacora_Transacciones | PASS |
| CHECKDB / CHECKCONSTRAINTS | PASS |

SQL real cubrió: emisión con descuento, totales, producto sin stock cotizable,
ausencia de descuento de existencias, reintento, referencia con otra carga,
emisión simultánea idéntica, varias líneas, catálogo 100→120 con snapshot 100,
filtros, paginación, cliente/producto inexistente, cliente inactivo, cantidad
inválida, sin líneas, vigencia inválida, actor sin permiso, denegación SELECT
directo, rollback por línea inválida posterior, cancelación idempotente y TVF
de expiración sin escritura de estado.

Se detectó un desborde del formulario a 768 px durante la primera ejecución
de navegador. Se corrigió con mínimos de columnas y controles; repetición
completa PASS sin desbordes globales ni excepciones JavaScript. Las pruebas
Node iniciales detectaron un error EJS y validación de página cero; corregidos.
No quedan pruebas fallidas de la parte independiente en la ejecución final.

**Pendientes, no ejecutadas ni aprobadas:** conversión, factura congelada,
salidas de inventario/Kardex por conversión, dos actores convirtiendo, reintento
de conversión, competencia por último stock y rollback tras insertar Factura.
UC09 requiere aprobar el contrato compartido. El procedimiento obligatorio
sp_ConvertirCotizacionAFactura aún no existe; no se incluye un sustituto falso.

Las regresiones de Facturación de la suite Node usan sus fixtures existentes;
no equivalen a una nueva venta SQL real. Los hashes SQL confirman que el núcleo
compartido no se alteró, pero tampoco sustituyen esa futura regresión de UC09.

Las sesiones de navegador son fixtures de autenticación identificados. Los
servicios, procedimientos, documentos y consultas son SQL real de laboratorio.
