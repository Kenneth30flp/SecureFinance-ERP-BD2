UC09 convierte una cotización vigente en factura de contado con precios pactados SQL, caja, inventario y Kardex en una sola transacción. El wrapper también cierra el documento si se invoca directamente. La interfaz confirma la operación, conserva el UUID ante respuesta incierta y permite abrir la factura.

### Motor y seguridad

- Nueva migración 43; 21/37/41/42 intactas. Parámetro final opcional @P3CotizacionId INT=NULL en wrapper y núcleo, sin cambiar TVP ni tablas/triggers de Facturación/Kardex.
- Venta normal y hash histórico conservados; huella P3COT:v1 separada para cotizaciones. Un solo motor de Factura/detalle/caja/Kardex.
- sp_ConvertirCotizacionAFactura, validación SQL de origen/importe/actor, cierre PROCESADA/FacturaId, historial y auditoría atómicos.
- RBAC HTTP/SQL, CSRF, parámetros tipados, sesión, documento propio o Administrador, estado/vigencia/stock, reintentos y bloqueos. Botón condicionado a instalación y EXECUTE efectivos.
- Kenneth autorizó expresamente el contrato en esta rama. No se requiere aprobación externa para esta implementación. Contado e inventario global; contratos futuros documentados para promociones, crédito y multibodega.

### Validación ejecutada

- npm run check; npm test: 106/106 PASS; git diff --check.
- SQL Server restaurado: 27 grupos UC09 y 14 independientes PASS. Precio pactado Q100 ×2, catálogo Q120, descuento 10%, factura Q201.60, stock 10→8, caja y Kardex únicos.
- Concurrencia de dos actores, misma referencia simultánea, competencia por última unidad, vencimiento durante bloqueo, reintentos, origen manipulado/ajeno, RBAC, descuento revocado y colisiones entre venta normal y cotización.
- Falla inyectada después de Factura al escribir Kardex: rollback completo y reintento recuperable. Trigger de prueba retirado.
- Venta normal, firma posicional/NULL y reintento de venta emitida antes de instalar 43 conservan hash/JSON y efectos.
- Reaplicación 41–43, SHA256 de documentos previos, auditoría, CHECKDB/CHECKCONSTRAINTS PASS.
- Chromium con SQL real: 15 comprobaciones, 1366/768/390/320 px. HTTP 503 inyectado después del COMMIT y recuperación con el mismo UUID, sin duplicados. Autenticación QA identificada; no acredita login manual.

### Ejecución local y evidencias

[Instrucciones para Chrome y PowerShell](https://github.com/Kenneth30flp/SecureFinance-ERP-BD2/blob/feature/p3-kenneth-cotizaciones/docs/parte3/cotizaciones/EJECUCION_CHROME.md).
`npm.cmd run start:lab:cotizaciones -- --port 3103` inicia la copia indicada en .data, verifica DB_NAME y EXECUTE, conserva autenticación normal y no modifica .env. URL: http://localhost:3103/cotizaciones.

Resultados, capturas auténticas, comprobante, contratos y recuperación en docs/parte3/cotizaciones/. El SKU/descripción de factura conserva la política de snapshot al facturar; la cotización mantiene su identidad propia.

No se migró ni escribió en SecureFinanceERP, no se cambiaron credenciales ni módulos de José/Dylan, no se modificó el PR #11 y no se hace merge automático. La validación corresponde a laboratorio; desplegar sobre la principal requiere una fase separada autorizada.
