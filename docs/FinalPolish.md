# SecureFinance ERP — entrega final

## Resultado

Dashboard con cuatro KPIs SQL reales; jornada Guatemala UTC−6, importes exactos
y roles actuales de SQL. Facturación conserva sus descuentos, política por rol,
modal de confirmación y comprobante autoritativo imprimible; mejora ficha del
cliente, stock, jerarquía de importes y bloqueo durante procesamiento.
Usuarios y Roles administra acceso en un dialog nativo con foco, Escape y
protecciones existentes. Auditoría conserva sus tres vistas y filtros, agrega
contadores y destaca la vista activa. Mensajes corporativos uniformes en login,
contraseñas, ventas, usuarios y errores de auditoría.

No se modificó la base real. No se hicieron checkout, reset, clean, commit,
push ni merge. Se preservó el trabajo previo sin cerrar.

## Archivos de esta mejora

Modificados:

- `server.js`, `package.json`.
- `src/controllers/authController.js`, `src/controllers/auditoriaController.js`, `src/routes/authRoutes.js`.
- `src/views/dashboard.ejs`, `src/views/facturacion.ejs`, `src/views/usuarios.ejs`, `src/views/auditoria.ejs`, `src/views/login.ejs`, `src/views/password.ejs`.
- `src/public/css/styles.css`, `src/public/js/facturacion.js`, `src/public/js/usuarios.js`.
- `database/10_AppPermissions.sql`, `database/SecureFinanceERP_Full.sql`.
- `database/tests/TransactionIntegrationTests.js`, `database/tests/UserAdministrationIntegrationTests.js`.
- `tests/auth.test.js`, `tests/audit.test.js`, `tests/venta.test.js`, `tests/facturacion.test.js`, `tests/usuarios.test.js`, `tests/password.test.js`, `tests/browser/operationsDesk.browser.js`.

Nuevos:

- `src/services/dashboardService.js`, `src/controllers/dashboardController.js`, `src/routes/dashboardRoutes.js`.
- `src/public/js/messages.js`.
- `database/14_DashboardSummary.sql`, `database/tests/DashboardSummaryTests.sql`.
- `tests/dashboard.test.js`, `docs/FinalPolish.md`.

Algunos archivos modificados ya eran nuevos sin seguimiento antes de este polish.
El estado Git al final incluye todos los cambios previos, además de esta entrega.

## SQL y aplicación manual sobre la base actual

Objeto nuevo: `dbo.sp_ObtenerResumenDashboard @UsuarioId INT`.
Devuelve VentasDia, FacturasDia, ProductosStockBajo, EventosDMLDia,
FechaOperacion y RolesActuales. No cambia tablas, descuentos ni datos históricos.
Ventas/facturas/stock requieren VENTAS_REGISTRAR o AUDITORIA_CONSULTAR en SQL;
eventos DML requieren AUDITORIA_CONSULTAR. Sin permiso devuelve NULL, mostrado
como «Sin permiso de consulta». Ante fallo se mantiene el dashboard disponible
con aviso y sin inventar ceros. Stock bajo: producto activo con Stock ≤ 5.

La jornada usa [06:00 UTC del día local, 06:00 UTC siguiente), coherente con
las fechas UTC almacenadas. Se conceden únicamente permisos EXECUTE al
procedimiento. El instalador completo y permisos están sincronizados.

La base actual ya tiene descuentos y Operations Desk. **Solo necesita 14**.
Orden exacto:

1. Detener la aplicación y respaldar SecureFinanceERP.
2. Desde la raíz del proyecto, ejecutar como administrador SQL:

```powershell
sqlcmd -S localhost -E -C -b -f 65001 -i ".\database\14_DashboardSummary.sql"
if ($LASTEXITCODE -ne 0) { throw 'Falló la instalación del resumen del dashboard.' }
```

3. Debe mostrar `OK: Dashboard summary installed.`. El script es idempotente
   y otorga EXECUTE si el usuario securefinance_app ya existe.
4. Reiniciar con `npm.cmd start`; iniciar sesión y abrir Dashboard.

Usar la instancia SQL configurada en el proyecto si difiere de localhost.
En SSMS puede ejecutarse el archivo completo con una cuenta administradora.
No ejecutar Full ni 05 sobre la base existente. No hace falta ejecutar 10
para esta actualización: 14 incluye el grant específico. Si faltan migraciones
anteriores, su orden es 12_SalesDiscounts → 13_OperationsDesk → 14_DashboardSummary.
Una instalación vacía usa SecureFinanceERP_Full.sql, que incluye el resumen.

## Validación

- `npm.cmd run check`: **PASS (exit 0)**; sintaxis de aplicación, frontend y suites.
- `npm.cmd test`: **43/43 PASS, 0 fallos**; regresión Node/HTTP/DOM, autenticación, CSRF, recuperación,
  contraseña, RBAC, roles, descuentos, modal, envío único y recibo SQL.
- `git diff --check`: **PASS (exit 0)**, sin errores de espacios. Los avisos LF/CRLF son del
  ajuste de finales de línea de Git, no fallos de este comando.
- `node database/tests/TransactionIntegrationTests.js localhost`: **PASS**; migración
  sobre histórico real, repetibilidad, siete suites SQL, permisos mínimos,
  recibo real y ventas concurrentes/stock/rollback; base temporal eliminada.
- `node database/tests/UserAdministrationIntegrationTests.js localhost`:
  **PASS**; instalador completo, siete suites SQL y concurrencia de tokens y revocación
  del último administrador; base temporal eliminada.
- `node tests/browser/operationsDesk.browser.js`: **PASS**; Chromium real con servicios
  simulados, 1366×768 y 1920×1080, KPIs, roles, foco/teclado, tabs, scroll,
  venta, impresión/PDF y límite del Cajero. Sin acceso a la base real.

Las nuevas pruebas SQL verifican límites UTC inclusivos/exclusivos, sumas y
conteos reales, productos activos, roles actuales y métricas restringidas.

## Ensayo manual para mañana

1. Login con Administrador; verificar KPIs reales y roles en Dashboard.
2. Revisar Dashboard, Facturación, Usuarios y Auditoría en ambas resoluciones.
3. Seleccionar cliente por nombre/NIT y comprobar su ficha.
4. Cable HDMI Q35.90, cantidad 1, descuento 10%: neto Q32.31,
   IVA Q3.88, total Q36.19. Modificar cantidad y verificar stock/ahorro.
5. Cancelar confirmación: no venta. Confirmar con doble clic: una factura.
6. Revisar cliente, NIT, cajero, fecha, detalle y totales del comprobante;
   imprimir a PDF sin sidebar/botones; Nueva venta carga formulario limpio.
7. Cajero: 10% permitido, 25% rechazado. Administrador: 100% permitido.
8. Probar stock insuficiente y comprobar que no se registra una venta parcial.
9. Abrir roles: valores correctos, Escape/Cancelar y foco en botón original;
   guardar y probar protección del último Administrador activo.
10. Abrir las tres vistas de Auditoría, aplicar/limpiar filtros, expandir JSON
    y verificar descuento/neto del histórico.
11. Auditor sin facturación; Cajero sin administración de usuarios.
12. Recuperación/cambio de contraseña, cierre y nueva sesión; mensajes coherentes.

## Estado del repositorio al entregar

Los resultados siguientes incluyen el trabajo previo. `git diff --stat` no
cuenta archivos nuevos sin seguimiento; estos están enumerados en git status.

### git status --short

```text
 M database/05_BusinessTables.sql
 M database/06_TransactionProcedures.sql
 M database/07_AuditCore.sql
 M database/07_TransactionPermissions.sql
 M database/08_AuditTriggers.sql
 M database/10_AppPermissions.sql
 M database/SecureFinanceERP_Full.sql
 M database/tests/AuditTests.sql
 M database/tests/TransactionIntegrationTests.js
 M database/tests/TransactionTests.sql
 M package.json
 M server.js
 M src/controllers/auditoriaController.js
 M src/controllers/authController.js
 M src/controllers/ventaController.js
 M src/middleware/authMiddleware.js
 M src/public/css/styles.css
 M src/public/js/facturacion.js
 M src/routes/authRoutes.js
 M src/services/ventaService.js
 M src/views/auditoria.ejs
 M src/views/dashboard.ejs
 M src/views/facturacion.ejs
 M src/views/login.ejs
 M tests/audit.test.js
 M tests/auth.test.js
 M tests/facturacion.test.js
 M tests/venta.test.js
?? database/11_UserAdministration.sql
?? database/12_PasswordRecovery.sql
?? database/12_SalesDiscounts.sql
?? database/13_OperationsDesk.sql
?? database/14_DashboardSummary.sql
?? database/tests/DashboardSummaryTests.sql
?? database/tests/OperationsDeskTests.sql
?? database/tests/PasswordRecoveryTests.sql
?? database/tests/SalesDiscountTests.sql
?? database/tests/UserAdministrationIntegrationTests.js
?? database/tests/UserAdministrationTests.sql
?? docs/FinalPolish.md
?? docs/OperationsDesk.md
?? docs/PasswordRecovery.md
?? docs/SalesDiscounts.md
?? docs/UserAdministration.md
?? src/controllers/dashboardController.js
?? src/controllers/passwordController.js
?? src/controllers/usuarioController.js
?? src/public/js/messages.js
?? src/public/js/usuarios.js
?? src/routes/dashboardRoutes.js
?? src/routes/passwordRoutes.js
?? src/routes/usuarioRoutes.js
?? src/services/dashboardService.js
?? src/services/passwordService.js
?? src/services/usuarioService.js
?? src/views/password.ejs
?? src/views/usuarios.ejs
?? tests/browser/
?? tests/dashboard.test.js
?? tests/password.test.js
?? tests/usuarios.test.js
```

### git diff --stat

```text
 database/05_BusinessTables.sql                |  15 +-
 database/06_TransactionProcedures.sql         | 115 +++++--
 database/07_AuditCore.sql                     |   5 +-
 database/07_TransactionPermissions.sql        |   3 +
 database/08_AuditTriggers.sql                 |   2 +-
 database/10_AppPermissions.sql                |  16 +
 database/SecureFinanceERP_Full.sql            | 459 +++++++++++++++++++++++---
 database/tests/AuditTests.sql                 |   4 +-
 database/tests/TransactionIntegrationTests.js |  89 ++++-
 database/tests/TransactionTests.sql           |   2 +-
 package.json                                  |   9 +-
 server.js                                     |  16 +-
 src/controllers/auditoriaController.js        |  40 ++-
 src/controllers/authController.js             |   5 +-
 src/controllers/ventaController.js            |  36 +-
 src/middleware/authMiddleware.js              |  13 +-
 src/public/css/styles.css                     | 139 ++++++++
 src/public/js/facturacion.js                  | 224 ++++++++++---
 src/routes/authRoutes.js                      |   6 +-
 src/services/ventaService.js                  |  15 +-
 src/views/auditoria.ejs                       |  77 ++++-
 src/views/dashboard.ejs                       |  14 +-
 src/views/facturacion.ejs                     |  47 ++-
 src/views/login.ejs                           |   3 +-
 tests/audit.test.js                           |  51 ++-
 tests/auth.test.js                            |   8 +-
 tests/facturacion.test.js                     | 154 ++++++++-
 tests/venta.test.js                           |  87 ++++-
 28 files changed, 1433 insertions(+), 221 deletions(-)
```

