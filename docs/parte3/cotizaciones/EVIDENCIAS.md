# Guía de evidencias para Rubén

Todas las capturas proceden de Chromium real contra una base aislada restaurada.
La sesión `QA_COT_SESSION_FIXTURE` sustituye únicamente autenticación: no acredita
inicio de sesión con contraseña real. Las operaciones comerciales consultan y
escriben SQL Server real. Cliente/producto mostrados se crearon para QA en copia.
No son documentos operativos ni datos inventados presentados como producción.

| Evidencia en evidencias/ | Propósito |
| --- | --- |
| 01-nueva-cotizacion-desktop.png | Menú, cliente QA, productos, vigencia, descuento y resumen preliminar a 1366 px |
| 02-detalle-cotizacion-desktop.png | Documento emitido y valores persistidos por SQL |
| 03-comprobante-interno.pdf | Impresión interna diferenciada de factura tributaria |
| 04-historial-filtrado-desktop.png | Consulta por número después de guardar |
| 05-detalle-768.png | Detalle real a 768 px |
| 05-detalle-390.png | Detalle real a 390 px |
| 05-detalle-320.png | Detalle real a 320 px |
| 06-cancelacion-movil.png | Cancelación confirmada y estado SQL resultante |
| navegador.json | Comprobaciones ejecutadas, sesión fixture y conversión pendiente |
| sql-resultados.json | Aserciones SQL reales y límite explícito de conversión |
| 07-conversion-precio-pactado-100.png | Documento y botón real UC09 con precio pactado Q100 |
| 08-respuesta-incierta-referencia-conservada.png | HTTP 503 inyectado después del COMMIT; UUID conservado |
| 09-cotizacion-procesada.png | Estado PROCESADA y vínculo a la factura |
| 10-factura-precio-historico.png | Factura a Q100 con descuento e IVA, catálogo actualizado a Q120 |
| 11-kardex-salida-unica.png | Consulta real del egreso de inventario por la conversión |
| 12-procesada-390.png / 12-procesada-320.png | Documento procesado en móvil |
| 13-factura-390.png / 13-factura-320.png | Comprobante de factura en móvil |
| uc09-sql-resultados.json | Precio 100→120, inventario, caja y 27 grupos SQL reales |

Procedimientos reproducibles: archivos 41–42 y ejecutores de laboratorio,
sin capturas simuladas del editor de SQL. La comprobación de ausencia de cambios
en Factura/DetalleFactura/caja/Kardex está en VerifyCotizacionesLab.ps1.

La versión actual incluye UC09 real de contado, autorizado por Kenneth.
`RESULTADOS_UC09.md` y `UC09_IMPLEMENTACION.md` sustituyen los límites de la
entrega inicial. Los JSON independientes distinguen pruebas de snapshot de las
pruebas de factura; estas últimas acreditan precio histórico, stock 10→8 y caja
Q201.60. No se usaron facturas anteriores para simular una conversión.
