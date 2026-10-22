# Reparación local e integración 33–37 — 21 de octubre de 2026

Estado final: despliegue local completado en `SecureFinanceERP`, usando `feature/estabilizacion-funcional-erp`. Esta evidencia actualiza las afirmaciones anteriores de que las migraciones solo estaban en laboratorio. No se fusionó `main`.

## Causa comprobada

Al comenzar, el árbol estaba limpio en `8ff9652ac4cb831df598dd75a32c9cfb84667c10`. No existía un proceso ERP escuchando en 3000; el único Node visible ejecutaba Codex. Por tanto, no se atribuye una carpeta o commit a un supuesto proceso anterior que ya no existía.

El `.env` seleccionaba la principal, `SecureFinanceERP`, con `securefinance_app`. La identidad se confirmó mediante conexión SQL real. Los seis procedimientos solicitados no existían: SQL Server devolvió `EREQUEST / 2812`, y una lectura administrativa confirmó su ausencia. No eran errores 229 de permisos, contratos de parámetros ni errores del controlador.

- Inventario: la lista base funcionaba, pero seleccionar automáticamente el primer producto invocaba `dbo.sp_ERP_ConsultarKardex`, añadido por 34.
- Proveedores: la lista base funcionaba, pero seleccionar automáticamente el primer proveedor invocaba `dbo.sp_ConsultarProductoProveedor`, añadido por 33.
- Productos tenía la misma incompatibilidad al abrir una ficha con relaciones. Las operaciones nuevas de recepción, ajuste, venta y crédito también requerían los otros objetos ausentes.

## Corrección y recuperación

Se comprobó la presencia de los objetos declarados por las migraciones previas 01–32 aplicables, sin ejecutar instaladores completos ni semillas. Los números 27–29 no existen como archivos en este repositorio. No se afirma que haya una tabla histórica de migraciones: la comprobación se hizo sobre objetos reales y después mediante restauración, migración y ejecución de los contratos.

Se creó un backup completo actual `COPY_ONLY WITH CHECKSUM`, se ejecutó `RESTORE VERIFYONLY WITH CHECKSUM` y se restauró con archivos separados en `SecureFinanceERP_Estabilizacion_20261021184145`. Pasaron `DBCC CHECKDB`, `DBCC CHECKCONSTRAINTS` y la comparación de cantidades y hashes SHA-256 con orden por clave primaria. Se conservaron productos, proveedores, clientes, facturas y detalles, caja, Kardex y apertura, devoluciones, créditos, garantías e historial, y asignaciones existentes. La comparación de créditos admite exclusivamente la normalización documentada de notas de importe cero de la migración 35.

33–37 se aplicaron primero en esa copia. Pasaron integridad, preservación y permisos efectivos por impersonación de `securefinance_app`. Las pruebas de escritura se hicieron exclusivamente allí.

Para la principal se comprobó que no había sesiones de aplicación activas y se mantuvo el backend detenido. Se usó `RESTRICTED_USER WITH NO_WAIT` durante las actualizaciones y conciliación. Una primera comprobación de permisos se detuvo porque ese modo también prohíbe impersonar al usuario de aplicación. Se conservó el modo restringido y no se abrió el backend. Los scripts incrementales se reaplicaron de forma idempotente; se completaron las comprobaciones de datos, se salió del modo restringido y se verificaron permisos antes del arranque de Node.

La revisión automática rechazó una propuesta intermedia de deshabilitar el login SQL por el riesgo de dejarlo bloqueado. Esa propuesta no se ejecutó y se retiró del script. El despliegue terminado no deshabilita ni cambia logins ni contraseñas.

El permiso empresarial `NOTAS_CREDITO_APLICAR` se asignó explícitamente solo al rol activo Administrador, comprobando antes su permiso existente `DEVOLUCIONES_AUTORIZAR`. La asignación queda en `Bitacora_Transacciones`. La migración 36 sigue sin asignarlo automáticamente a roles. No se ampliaron privilegios SQL: las operaciones directas de stock y las entradas antiguas de venta/Kardex continúan denegadas.

Se añadió una comprobación previa al arranque HTTP para detectar procedimientos ausentes o EXECUTE denegado. El arranque registra PID, carpeta e identidad SQL real en logs del servidor. El ejecutor de Kenneth registra procedimiento, código, número, estado y línea del error SQL; no registra parámetros, mensajes potencialmente sensibles ni credenciales. La interfaz conserva mensajes seguros y su apariencia corporativa.

## Rutas y datos

Las siguientes rutas pasaron con SQL real, RBAC y una sesión Express QA identificada, tanto en la copia antes de pruebas comerciales como en la principal después del despliegue:

| Ruta | Resultado |
| --- | --- |
| `/dashboard` | Resumen y operación sin advertencias de carga |
| `/facturacion` | Clientes, catálogo y política cargados |
| `/inventario` | Productos, stock y Kardex; selección de los cuatro productos |
| `/productos` | Catálogo y fichas de edición de los cuatro productos |
| `/proveedores` | Directorio y fichas de edición de ambos proveedores |
| `/clientes` | Directorio con NIT procedentes de SQL |
| `/devoluciones` | Consulta cargada |
| `/notas-credito` | Consulta cargada |
| `/garantias` | Consulta cargada |
| `/analitica` | Informe cargado |
| `/auditoria` | Consultas cargadas |
| `/usuarios` | Usuarios y roles cargados |

El verificador exige HTTP 200, HTML de módulo, ausencia de mensajes de fallo y presencia de valores reales de productos, stock, proveedores y clientes. No usa datos ficticios como respuesta. La sesión sustituye únicamente la autenticación y se identifica como `SESSION_FIXTURE_NOT_REAL_LOGIN`: no acredita login manual. No se capturó ni almacenó contraseña web. En la principal solo se enviaron consultas y GET de módulos, además de la sesión en memoria; ninguna venta, compra ni devolución de prueba.

Métricas principales al terminar: 4 productos, 210 unidades totales, 15 facturas, 6 movimientos Kardex, 2 proveedores, 3 clientes y 1 nota de crédito. Las operaciones QA no se añadieron a estos datos.

## Validación ejecutada

- Pruebas dirigidas Node de Kenneth, crédito y prearranque: 25/25.
- Laboratorio actual, SQL A–O: compras 90→100, reintento único, segundo proveedor, rollback, permisos, venta/Kardex, devolución idempotente, crédito parcial/liquidado, exceso rechazado, garantía e historial, transición inválida y preservación de factura al inactivar cliente.
- Regresión SQL dirigida: venta idempotente y clave incompatible, wrapper de ajuste y denegación directa, relaciones, TVF y dashboard.
- Casos límite SQL: proveedor inactivo, nota de cero liquidada y denegación de DML directo.
- Chromium con servicios SQL reales en la copia actual: recepción, venta y comprobante, devolución, crédito pendiente/parcial/liquidado y comprobante PDF, garantía y diagnóstico, navegación, ausencia de excepciones JS y vista móvil.
- Catálogo con servicios SQL reales en la copia: alta/edición/inactivación/reactivación de proveedor, relaciones múltiples, edición de producto y fotografía persistida, sin alterar stock por edición.
- `npm.cmd run check`: PASS.
- `npm.cmd test`: **81/81 PASS**, cero fallidas y omitidas; una sola regresión general.
- `npm.cmd run test:ui`: PASS.
- `npm.cmd run test:ui:edward`: PASS.
- `git diff --check`: PASS.

Las suites visuales generales usan servicios simulados; el recorrido Chromium adicional sí usa SQL real. No se presenta una prueba simulada como evidencia de integración SQL.

Las pruebas SQL históricas conservan sus aserciones. El ejecutor para la copia actual adapta solo el nombre de base autorizado y el selector del SKU: el respaldo actual contiene `CABLE`, mientras el laboratorio anterior usaba `DEMO-CABLE`. No se renombraron productos principales para satisfacer fixtures.

## Operación y entrega

Principal: `SecureFinanceERP`, ONLINE / MULTI_USER. Instaladas 33, 34, 35, 36 y 37; ninguna de estas cinco queda pendiente. Los datos y funcionalidades de la rama se conservan. No se ejecutó `SecureFinanceERP_Full.sql`, no hubo borrados históricos ni datos de demostración en la principal.

Backend: `node server.js`, escucha local en `127.0.0.1:3000`, con logs privados `.data/erp-runtime.stdout.log` y `.data/erp-runtime.stderr.log`. El PID inicial tras recuperación fue 29864; un reinicio posterior puede cambiarlo. `/health` devuelve `status: ok`.

Herramientas reproducibles: `DeployIncrementalERP.ps1` (Prepare/Laboratory/Deploy), `VerifyERPReadOnly.js`, `RunCurrentERPWorkflows.ps1`, `VerifyCurrentCatalog.js` y `tests/browser/stabilization.browser.js --session-fixture --database=<copia> --product-code=CABLE`. Los archivos locales `.data` conservan ruta de backup, hashes, resultados y capturas; se excluyen de Git. No repetir pruebas de stock inicial sobre una copia ya utilizada.

PR: [#11](https://github.com/Kenneth30flp/SecureFinance-ERP-BD2/pull/11). El login manual legítimo sigue sin acreditarse y ya no se utiliza para bloquear la reparación o las comprobaciones SQL. No hay merge automático.
