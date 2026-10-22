# Historial profesional de facturas

Facturación incorpora **Nueva venta** y **Historial de facturas**, conservando la captura de ventas y su idempotencia. El histórico lee las mismas `Factura` y `DetalleFactura` que Auditoría: no copia ni vuelve a emitir documentos. El histórico de Auditoría conserva su finalidad y sus procedimientos.

## Consulta y comprobantes

- `/facturacion/historial`: búsqueda por número exacto, cliente o NIT de emisión y días de Guatemala. Paginación SQL de 20 filas con orden estable por fecha e identificador; conserva filtros entre páginas.
- `/facturacion/facturas/:id`: comprobante existente, con cliente/NIT de emisión, responsable, fecha Guatemala, estado, líneas e importes originales.
- `?imprimir=1` y **Imprimir copia** imprimen ese mismo documento. Solo se utiliza GET; nunca se invoca el procesamiento de ventas, caja, stock ni Kardex.
- Precios, cantidades, descuento porcentual y monetario, subtotales e IVA proceden de los valores persistidos. El IVA se muestra como el importe global registrado; no se inventa un reparto por línea ni se usan precios actuales.
- Cada copia indica **comprobante interno / académico, no factura electrónica certificada SAT/FEL**. CSS de impresión elimina navegación y controles; también se genera PDF mediante Chromium en QA.
- Mensajes explícitos para búsqueda sin resultados, factura inexistente, permiso revocado y errores de carga sin detalles SQL.

### Identidad histórica del producto

Las facturas anteriores no siempre guardaron SKU y descripción de emisión en sus detalles. Para esas líneas se muestra claramente **SKU / nombre de referencia del catálogo**; si el libro idempotente conserva una descripción, se aprovecha esa evidencia. No se presenta el catálogo actual como una captura histórica ni se reconstruyen importes a partir de él.

La migración 39 añade `FacturaProductoEmision` y un trigger de inserción sobre `DetalleFactura` para capturar SKU y descripción de las ventas futuras en la transacción existente. No rellena ni reescribe los detalles anteriores. La captura es inmutable y carece de DML directo para la cuenta de aplicación. Las pruebas alteran precio, SKU y descripción de un producto **nuevo de laboratorio** y verifican que su comprobante conserva los datos de emisión. El procedimiento de venta y la lógica de reintento no se modifican.

## Seguridad

Nuevo permiso empresarial **FACTURAS_CONSULTAR**, independiente de `AUDITORIA_CONSULTAR` y `VENTAS_REGISTRAR`, validado en Express y mediante `sp_ParteII_ValidarPermiso` en cada consulta SQL. Se asigna deliberadamente a los roles activos Administrador y Cajero que ya registran ventas; Auditor no lo hereda.

Una cuenta con solo consulta puede abrir Facturación y se dirige al histórico, pero no procesar ventas. Una cuenta con solo Auditoría o solo registro de ventas no puede consultar el histórico sin el nuevo permiso. Los enlaces respetan esos permisos. Las consultas usan parámetros tipados y los límites locales convertidos a UTC: inicio inclusivo a las 06:00Z, fin exclusivo a las 06:00Z del día posterior. Los procedimientos no conceden SELECT general a tablas.

## Verificación dirigida

Factura **#6010**: cliente **Consumidor final DEMO**, NIT **CF**, tres **Cable HDMI**, precio unitario Q35.90, subtotal Q107.70, descuento 25% / Q26.93, neto Q80.77, IVA Q9.69 y total **Q90.46**. Se verifican esos valores exactos, otras facturas y su correspondencia con Auditoría. La fecha 21/10/2026 16:23:13.410 UTC se presenta como 21/10/2026 10:23:13 Guatemala.

- `npm.cmd run check`: PASS.
- `npm.cmd test`: **92/92 PASS**, cero fallidas u omitidas.
- `tests/facturas.test.js`: acceso anónimo, RBAC independiente, consulta sin venta, parámetros, límites de día, validación, paginación, escape, vacíos, 404, revocación y errores seguros. Pruebas dirigidas repetidas después de los ajustes finales: PASS.
- `InvoiceHistoryIntegration.js`: PASS contra la copia restaurada. Verifica #6010, otras facturas, permisos SQL y ausencia de SELECT directo. Escrituras QA solo en copia para comprobar captura futura, precios persistidos, reintento sin duplicación y paginación real de dos páginas.
- `invoiceHistory.browser.js`: PASS con SQL real; navegación Nueva venta/Historial, filtro #6010, tres HDMI, Q90.46, reimpresión, PDF, vacíos y anchos 1366/768/390/320. Comprueba ausencia de POST a `/facturacion/procesar`.
- `npm.cmd run test:ui` y `npm.cmd run test:ui:edward`: PASS. La primera ejecución visual detectó el desplazamiento del botón de venta al añadir las pestañas; se corrigió el encabezado y la prueba original pasó sin modificarla.
- `git diff --check`: PASS.

Los recorridos SQL de aplicación usan `securefinance_app`. Los navegadores y HTTP usan sesiones QA identificadas y no acreditan un login manual legítimo. No capturan ni cambian contraseñas.

## Integración local

Migración única: **39_ERP_HistorialFacturas.sql**, posterior a 38. Antes de instalarla en la principal se creó un backup completo actual COPY_ONLY/CHECKSUM, se verificó y restauró en `SecureFinanceERP_Facturas_20261021233048`, y se ejecutaron CHECKDB, restricciones y conciliación de las 29 tablas anteriores.

El cotejo excluye únicamente las filas nuevas y esperadas de `FACTURAS_CONSULTAR` en Permiso/Rol_Permiso; comprueba por separado sus dos roles autorizados. Las demás filas se comparan completas por cantidad y SHA-256 ordenado por clave primaria. La nueva tabla de identidades debe estar vacía al migrar: no se permite inventar capturas de documentos antiguos. La comparación de definiciones admite la normalización de SQL Server de CREATE OR ALTER TRIGGER a CREATE TRIGGER.

El ejecutor `DeployInvoiceHistory39.ps1` permite Inspect, Prepare, Laboratory, Deploy y Verify; solo instala 39 y verifica el hash del archivo, objetos, roles y permisos. El arranque del backend exige los dos procedimientos nuevos. Las evidencias privadas, backup y capturas quedan en `.data/`, excluido de Git.

El despliegue coordinado y su verificación final se registran al completar la ventana sin escrituras. No se ejecuta Full, no se eliminan datos y no se fusiona `main`.

## Archivos principales

- SQL: `database/39_ERP_HistorialFacturas.sql`.
- Backend: `src/services/facturaService.js`, `src/controllers/facturaController.js`, `src/routes/ventaRoutes.js`, `server.js`, `src/config/integration.js`.
- Interfaz: `facturas.ejs`, `factura-comprobante.ejs`, pestañas y encabezado parciales; integración en `facturacion.ejs` y navegación; `facturas.css` y `facturas.js`.
- Verificación y despliegue: pruebas unitarias, ejecutor SQL, recorrido Chromium, `DeployInvoiceHistory39.ps1` y comprobación de prearranque.
