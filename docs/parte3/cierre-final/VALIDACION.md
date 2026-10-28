# Validación ejecutada

Fecha local: 28 de octubre de 2026.

| Ejecutor | Resultado |
|---|---|
| `npm.cmd run check` | PASS, incluye catálogo y JavaScript de navegación |
| `npm.cmd test` | 115 PASS, 0 fallos, 0 omitidas |
| `CotizacionesIntegration.js` | 14 grupos SQL reales PASS |
| `CotizacionesUC09Integration.js` | 27 grupos SQL reales PASS |
| `CotizacionesBusquedaIntegration.js` | 7 grupos SQL reales PASS |
| `cotizaciones.browser.js` | 16 comprobaciones Chromium PASS |
| `cotizacionesDesign.browser.js` | 12 grupos Chromium PASS; contiene matriz de cinco anchos y cinco paneles |
| `git diff --check` | PASS |
| `verifyFinalDemo.ps1 -Compare` | PASS: DB_NAME, COT-6/7011 y hashes de cotizaciones, facturas y productos preservados |

SQL se ejecutó en `SecureFinanceERP_P3_COT_20261027213647_67c25f5a`. Las escrituras visuales se ejecutaron en `SecureFinanceERP_P3_COT_VISUAL_20261027233530_3fc452ba`. No se aplicaron migraciones nuevas ni se escribieron operaciones comerciales automatizadas en demostración o en `SecureFinanceERP`.

La regresión UC09 comprobó Q100 por unidad con catálogo Q120, descuentos/IVA, factura, caja, stock, Kardex únicos, reintentos, referencias incompatibles, concurrencia, última unidad, rollback después de insertar factura, permisos HTTP/SQL e históricos normales. La prueba de búsqueda reaplica únicamente su migración de laboratorio para comprobar reproducibilidad.

La prueba visual cubre 1366, 1024, 768, 390 y 320 px; búsqueda por teclado, edición de cantidad/descuento, guardado y conversión SQL, diálogo/Escape y foco, impresión, Centro de seis áreas, enlaces autorizados sin 404 y ausencia de excepciones JavaScript. Los perfiles sin permiso se verifican con pruebas de catálogo, renderizado y HTTP; las capturas usan sesión inyectada explícita en un servidor efímero de pruebas. La instancia pública de demostración no usa esa sesión.

Incidencias corregidas durante validación: ejecución de `npm.ps1` bloqueada por política local (se utiliza `npm.cmd` sin cambiar la política), Chromium aislado sin conexión CDP (se ejecutó con autorización de plataforma), Escape con foco externo y recorte de la etiqueta móvil de Administración. Todas las suites finales indicadas pasaron. Persiste advertencia del driver sobre TLS ServerName con dirección IP; no se modificaron credenciales ni configuración SQL para silenciarla.

Limitaciones: no se ingresaron contraseñas del usuario ni se afirma una sesión manual real; se conserva autenticación normal. No se probó una impresora física. El PDF de cotización es evidencia del motor de impresión Chromium, no de certificación fiscal. Los módulos futuros permanecen sin enlaces disponibles.
