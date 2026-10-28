La rama incorpora la parte independiente del módulo de Cotizaciones: emisión con precios históricos calculados en SQL, historial, filtros y paginación, detalle imprimible, vigencia con TVF y cancelación auditada. Crear un documento no afecta existencias ni genera facturas.

**PR EN BORRADOR: UC09 está bloqueado por aprobación del contrato compartido.** No se implementó sp_ConvertirCotizacionAFactura ni se modificó el motor de Facturación/Kardex. No aprobar como módulo académico completo.

### SQL y seguridad

- Migraciones 41 (tres tablas propias, restricciones, índices, TVF, triggers de inmutabilidad y permisos) y 42 (crear, consultar, catálogos y cancelar).
- RBAC HTTP y SQL; sesión y CSRF por módulo; parámetros tipados; UUID y huella idempotente; auditoría dentro de la transacción.
- Precio, SKU y descripción se capturan del catálogo SQL; no se aceptan precios del navegador.
- Cuenta de aplicación con EXECUTE específico y sin acceso directo a tablas nuevas. Permisos iniciales limitados a Administrador; conversión reservada sin endpoint activo.

### Coordinación requerida antes de UC09

Revisar [propuesta de precios congelados](https://github.com/Kenneth30flp/SecureFinance-ERP-BD2/blob/feature/p3-kenneth-cotizaciones/docs/parte3/cotizaciones/PROPUESTA_PRECIOS_CONGELADOS.md): parámetro opcional de origen cotización en el wrapper y núcleo actuales, sin sustituir TVP ni duplicar venta. José debe acordar descuentos/promociones congelados; Dylan, contado/crédito y futura bodega. La propuesta sigue pendiente de aprobación escrita del integrador y coordinación con responsables afectados.

### Validación real

- npm run check y npm test: 102/102 PASS; git diff --check PASS.
- SQL Server en copia aislada: 14 grupos de aserciones, incluidas idempotencia/concurrencia de emisión, snapshot 100→120, TVF, RBAC, cancelación y rollback.
- Chromium con SQL real: alta, detalle, historial, impresión y cancelación; 1366/768/390/320 px. Sesión QA sustituye solo autenticación y no acredita login real.
- Reaplicación 41–42, CHECKDB/CHECKCONSTRAINTS, auditoría e integridad de procedimientos compartidos PASS; sin nuevas filas de Factura/caja/Kardex.

Documentación, resultados, ejecutores reproducibles y evidencias auténticas en `docs/parte3/cotizaciones/`. No se ejecutaron migraciones ni escrituras QA en SecureFinanceERP, no se cambió .env ni el PR #11.

### Pendientes explícitos

Conversión atómica y factura a precio pactado; pruebas de concurrencia de conversión, stock y rollback después de Factura; integración futura de crédito y multibodega. Los resultados actuales no acreditan esas funciones. No hay capturas simuladas de conversión.
