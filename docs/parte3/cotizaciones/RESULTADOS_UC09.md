# Resultados de UC09 — 2026-10-27

Entorno SQL real: `SecureFinanceERP_P3_COT_20261027213647_67c25f5a`, copia
nueva desde respaldo existente. Ninguna migración/escritura QA se ejecutó en
SecureFinanceERP. Migración 43 instalada y reaplicada en transacción externa.

| Verificación | Resultado |
| --- | --- |
| npm run check | PASS, incluye archivos UC09 y lanzador |
| npm test | 106/106 PASS, cero fallidas/omitidas |
| Suite SQL independiente | 14 grupos PASS |
| Suite SQL UC09 | 27 grupos PASS |
| Chromium y SQL real | 15 comprobaciones PASS; escritorio 1366 y anchos 768/390/320 |
| Reaplicación 41–43 | PASS, documentos y estados conservados |
| Conciliación de conversiones | PASS: factura, caja y Kardex correspondientes |
| Documentos previos | PASS, SHA256 de Factura/DetalleFactura/caja/Kardex anteriores intactos |
| Hash/comprobante de venta pre-43 | PASS, mismo registro y sin escrituras al reintentar |
| Auditoría, CHECKDB, CHECKCONSTRAINTS | PASS |
| git diff --check | PASS |

Caso de precios: Q100 × 2, descuento 10% = Q20, neto Q180, IVA Q21.60,
total Q201.60. El catálogo se cambió autorizadamente a Q120 antes de convertir.
DetalleFactura conserva Q100; catálogo queda Q120; stock 10→8; un Kardex de
VENTA y un MovimientoCaja por Q201.60. JSON verificable en
`evidencias/uc09-sql-resultados.json`.

La suite probó además: estado PROCESADA, wrapper directo con cierre atómico,
UUID repetido/alterado y colisiones entre caminos, origen inexistente/ajeno y
TVP/cliente/motivo manipulados, vencida/cancelada, cliente/producto inactivo,
stock insuficiente, RBAC, acceso directo al núcleo denegado, dos actores,
misma referencia simultánea, competencia por última unidad y vencimiento
durante espera de bloqueo. La pérdida de autorización de descuento del creador
rechaza la conversión sin recalcular el pacto.

El rollback se provocó mediante un trigger **solo en laboratorio**, después
de insertar Factura y al escribir Kardex. Revirtió factura/detalle/caja/libro,
stock e historial de conversión; cotización permaneció ACTIVA y pudo reintentarse
con el mismo UUID. El trigger de inyección fue retirado y se verificó su ausencia.

Chromium recorrió alta→detalle→conversión→factura→Kardex. Una inyección de HTTP
503 posterior al COMMIT comprobó recuperación con el mismo UUID y una sola salida.
No se simularon los datos ni procedimientos comerciales. Autenticación QA fue
sustituida por fixture identificado, por lo que no acredita login manual real.

No quedan pruebas fallidas de conversión en la ejecución final. El alcance
probado es contado e inventario global; crédito/promociones/multibodega futuros
no se presentan como desarrollados. No se desplegó el módulo sobre la principal.
