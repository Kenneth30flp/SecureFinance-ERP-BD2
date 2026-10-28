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

Procedimientos reproducibles: archivos 41–42 y ejecutores de laboratorio,
sin capturas simuladas del editor de SQL. La comprobación de ausencia de cambios
en Factura/DetalleFactura/caja/Kardex está en VerifyCotizacionesLab.ps1.

No hay capturas de conversión, factura generada por cotización, salida Kardex
o stock antes/después de convertir, porque UC09 está pendiente. No sustituirlas
por capturas de facturas anteriores. Tampoco afirmar que la prueba de snapshot
100→120 demuestra precio histórico en una factura aún no creada.
