## Cierre final: Cotizaciones y navegación modular

- Pulido de importes, vigencias comerciales, identificadores de demostración e impresión.
- Centro `/modulos` y seis áreas mediante catálogo central, permisos efectivos y paneles accesibles.
- Se conservan rutas y contratos financieros. Sin nuevas migraciones ni cambios en Facturación/Kardex.
- 115 pruebas Node; 48 grupos SQL reales; 16 + 12 grupos Chromium aprobados.
- Demostración en localhost:3105, base DEMO verificada, COT-6/factura 7011 preservadas por hashes.
- Evidencias y comandos: `docs/parte3/cierre-final/README.md`. Contrato para compañeros: `docs/parte3/NAVEGACION_MODULAR.md`.
- Pruebas visuales con sesión fixture solo en copia VISUAL; demostración mantiene login normal. Sin merge automático.

---

Cotizaciones ahora presenta una experiencia comercial coherente con el tema oscuro de SecureFinance: historial compacto, formulario organizado en tres secciones, buscadores accesibles y paginados, edición de cantidades/descuentos, detalle empresarial, confirmación modal e impresión limpia. La demostración tiene una base exclusiva sin los registros generados por QA.

### Experiencia y consultas

- Buscar cliente por nombre/NIT y producto por SKU/descripción: ocho resultados por página, navegación de teclado, selección visible, precio/stock y estado vacío. El formulario no carga el catálogo completo.
- Líneas editables y resumen exacto; precios definitivos y conversión siguen bajo autoridad SQL.
- Total destacado, UUID plegados en información técnica, cancelación secundaria y continuidad a factura.
- Cinco anchos: 1366/1024/768/390/320; paneles limitados, navegación móvil compacta, foco/Tab/Escape y contraste medido del buscador.
- Migración 44: dos procedimientos de consulta y EXECUTE específico. Motor UC09, ventas, caja, Kardex y migraciones 41–43 intactos.

### Separación de datos

Se conservaron los registros y evidencias de pruebas. La auditoría inicial identificó 10 clientes y 33 productos QA relacionados con 30 facturas y 61 Kardex; no se eliminaron ni se filtraron por prefijo en producción.

DEMO fue restaurada desde respaldo COPY_ONLY verificado, a nombre/archivos nuevos. Reutiliza productos comerciales existentes y tres clientes claramente ficticios con identificadores DEMOCOT. Contiene cinco propuestas en distintos estados, stock suficiente y respaldo propio verificado. Las pruebas visuales escriben en una tercera copia VISUAL, por lo que DEMO permanece intacta.

### Validación

- npm run check; npm test: 109/109 PASS; git diff --check.
- SQL real: 14 grupos independientes, 27 UC09 y 7 búsqueda PASS.
- Chromium: 16 regresiones QA y 11 de diseño comercial PASS. Recorrido real con varias líneas, edición, guardado, conversión, factura, stock y Kardex; recuperación posterior a COMMIT intacta.
- DEMO: DB_NAME, cero QA, cinco documentos, hash de facturas originales, EXECUTE, CHECKDB y restricciones verificados.
- Capturas auténticas de historial, nueva, detalle, diálogo y PDF en cinco tamaños. Los ejecutores usan sesión de autenticación fixture identificada; los datos y operaciones comerciales son SQL real. El lanzador manual conserva login normal.

### Probar en Chrome

`npm.cmd run start:demo:cotizaciones -- --port 3104`

http://localhost:3104/cotizaciones — no confundir con QA en 3103. No se modifica .env ni se detienen procesos existentes. `/laboratorio/estado` verifica de nuevo la base con sesión autenticada.

[Diseño, datos, resultados, capturas y comandos PowerShell](https://github.com/Kenneth30flp/SecureFinance-ERP-BD2/blob/feature/p3-kenneth-cotizaciones/docs/parte3/cotizaciones/redisenio/README.md).

UC09 continúa operativo con la extensión opcional autorizada, precios congelados, idempotencia y transacción única de contado/global. Promociones, crédito y multibodega futuros mantienen sus contratos documentados. No se escribió ni migró SecureFinanceERP, no se modificaron ramas ajenas ni el PR #11, no se publican credenciales/respaldos y no se hace merge automático.
