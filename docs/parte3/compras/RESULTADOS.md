# Resultados reales de la entrega — 2026-10-29

Rama comprobada: `feature/p3-edward-compras`. Se continuó desde los archivos
existentes sin cambiar de rama ni sustituir el trabajo por otra implementación.
No se realizó commit, push, PR, merge ni escritura en SQL Server.

## Verificaciones ejecutadas

| Comando | Resultado y alcance |
| --- | --- |
| `npm.cmd run check` | PASS; sintaxis Node de la aplicación, scripts y pruebas incluidos |
| `npm.cmd test` | PASS: **138 pruebas, 0 fallidas, 0 omitidas**; servicios simulados/contratos, sin escritura SQL |
| `npm.cmd run test:ui:compras` | PASS; Chromium real con datos y servicios sintéticos |
| `node tests/browser/operationsDesk.browser.js` | PASS; regresión visual/funcional simulada de escritorio operativo |
| `node tests/browser/edward.browser.js` | PASS; regresión simulada de posventa, garantías y navegación |
| `git diff --check` | PASS; sin errores de espacios en cambios rastreados |
| Revisión de archivos nuevos | Sin espacios finales, archivos privados ni patrones de claves privadas/tokens detectados |

Node incluye pruebas de autorización, CSRF, actor de sesión, autoaprobación
rechazada según error SQL simulado, validación de cantidades/costos, errores
seguros, parámetros tipados, respuestas parciales no confirmadas, paginación,
navegación y límites monetarios BigInt. Hay 23 pruebas propias de Compras:
13 de servicio/validación/laboratorio y 10 web/contratos. Las otras 115 son
regresiones existentes, incluyendo ventas, facturación, catálogos, inventario,
devoluciones, cotizaciones, auditoría y autenticación.

El test nuevo de preparación lee Full y las migraciones requeridas y comprueba
que el instalador puede preparar sus lotes en memoria, sin conectar al motor.
Las inspecciones estáticas de SQL no se presentan como compilación T-SQL.

## Navegador

Compras: listado, alta, detalle y valoración a 1440/1024/768/390 px, sin
desbordamiento horizontal. Selección de proveedor/producto, cálculo exacto,
diálogo nativo con Tab/Escape, creación simulada, rechazo visual de sobreentrega,
recepción parcial simulada, pendientes, historial, impresión PDF y reintento
con UUID/carga conservados después de una respuesta incierta y recarga.
Sin excepciones JavaScript observadas.

Escritorio operativo: 1920/1366/1024/768/390/320 px, viewport equivalente al
200%, movimiento reducido, roles, teclado, auditoría, confirmación de venta,
comprobante, impresión y política de cajero, todos con servicios simulados.

Posventa: 1920/1366/768/390/320 px, confirmación/cancelación, comprobante,
impresión, garantías, conflicto preservando diagnóstico/foco, doble envío,
RBAC, filtros, errores de servicio y accesibilidad, con servicios simulados.

Evidencia local ignorada por Git: `.data/compras-ui/` y logs
`.data/compras-*.log`. Las capturas/PDF son demostraciones sintéticas, no
documentos operativos. Se inspeccionaron capturas del detalle y del alta móvil.

## SQL: no ejecutado

No hay credenciales `COMPRAS_LAB_USER`, `COMPRAS_LAB_PASSWORD` ni identidad
esperada de laboratorio configuradas en el proceso de esta reanudación.
Se comprobó solamente su presencia/ausencia, sin mostrar valores ni leer
credenciales privadas. La identidad Windows del diagnóstico previo era
sysadmin y no se utilizó para pruebas. En esta reanudación no se abrió una
conexión SQL.

Quedan pendientes contra un motor real: instalación/repetibilidad de 50–55,
permisos efectivos, aprobaciones, recepción parcial/completa, sobreentregas,
reintentos, transiciones concurrentes, rollback posterior a cambios de stock,
valoración de compras/ventas/devoluciones/ajustes y costos heredados extremos.
Los escenarios están preparados en `database/tests/ComprasIntegration.js`.
La conexión restringida y el laboratorio deben superar las guardas antes de
cualquier escritura. Instrucciones exactas en [README.md](README.md).

No se ejecutaron los navegadores de Kenneth, Cotizaciones y Estabilización
que requieren SQL real o laboratorios anteriores: no satisfacen el entorno
autorizado de esta entrega. Sus suites Node sí están incluidas en `npm test`.

## Correcciones finales de esta reanudación

- Ampliado el libro auxiliar a valores DECIMAL(36,8) y costos/promedios
  DECIMAL(25,8): admite los 17 dígitos enteros del costo heredado DECIMAL(19,2).
  Nuevo escenario SQL preparado para ese extremo; no ejecutado.
- Consulta de valoración distingue correctamente saldo cero sin movimientos
  y comprueba coincidencia de saldo al indicar un corte actualizado.
- Preflight adicional de tipos, PK/FK de tablas propias; permisos finales
  limitados expresamente al esquema dbo.
- CSRF valida también el formato del token guardado antes de comparar buffers.
- Recuperación local valida destino/estructura de la operación pendiente;
  errores inesperados no se tratan como rechazos definitivos. Un rechazo al
  reintentar una operación incierta conserva la referencia original.
- Completados resultados, inventario de archivos, mensaje de commit y PR.

## Alcance de Git y estado de entrega

Los únicos archivos preexistentes modificados son `server.js`, `package.json`,
`src/config/moduleCatalog.js`, `src/views/partials/navigation.ejs` y el contrato
de integración. Sus cambios registran Compras, sus pruebas y documentación.
No se modificaron Full, migraciones compartidas, procedimientos/tablas de
Kardex/recepción/facturación, CSS común ni lógica de módulos de compañeros.

Los nuevos archivos pertenecen a migraciones 50–55, módulo Compras,
vistas/assets, pruebas, ejecutor de laboratorio y documentación. Consultar
[ARCHIVOS.md](ARCHIVOS.md) para el inventario completo.

Listo para commit de implementación/revisión. **No certificado como módulo
completamente funcional en SQL Server**. Antes de fusionar/desplegar hace
falta ejecutar y aprobar el laboratorio restringido. Multibodega sigue
dependiendo del contrato de Dylan; el inventario global permanece operativo
en el diseño. La valoración se actualiza de forma explícita, no automática.
