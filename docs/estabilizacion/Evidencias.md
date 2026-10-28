# Evidencias de estabilización

Todas las operaciones SQL se ejecutaron en la copia restaurada `SecureFinanceERP_Estabilizacion_20261021`. Los documentos QA son identificados como laboratorio y conservan las identidades DEMO existentes.

Las capturas usan servicios SQL reales y una sesión Express de prueba. **La autenticación fue sustituida por un fixture**; estas imágenes no acreditan login SQL con contraseña existente. El detalle está en [navegador.json](evidencias/navegador.json).

| Flujo | Evidencia |
| --- | --- |
| Acción separada para recibir desde producto | [Producto](evidencias/01-producto-ingresar.png) |
| Confirmación de proveedor, cantidad y documento | [Confirmación](evidencias/02-confirmacion-entrada.png) |
| Stock y Kardex tras recepción real | [Inventario](evidencias/03-kardex-compra.png) |
| Venta real con comprobante | [Factura](evidencias/04-venta-comprobante.png) |
| Crédito recién emitido | [Pendiente](evidencias/05-credito-pendiente.png) |
| Crédito con una aplicación | [Parcial](evidencias/06-credito-parcial.png) |
| Crédito sin saldo disponible | [Liquidado](evidencias/07-credito-liquidado.png) |
| Impresión de nota e historial | [Comprobante PDF](evidencias/08-comprobante-credito.pdf) |
| Garantía vinculada a factura QA y seguimiento | [Historial](evidencias/09-garantia-historial.png) |
| Documento de crédito a 390 px | [Móvil](evidencias/10-credito-movil.png) |
| Caso exacto HDMI 90 + 10 = 100 y A–O | [Asersiones SQL](evidencias/sql-resultados.txt) |
| Compras, créditos y venta concurrentes | [Concurrencia](evidencias/concurrencia.txt) |
| Checks y límites finales | [Resumen](evidencias/verificacion-final.json) |

El stock de las capturas es posterior a otros escenarios QA. El caso exacto 90→100 se ejecutó primero y se comprobó mediante aserciones de stock y conteo Kardex; no se cambiaron datos para recrearlo en las imágenes.

Los logs extensos originales y los archivos de consultas concurrentes permanecen localmente en `.data/`, fuera del repositorio. No se incluyen credenciales ni perfiles de Chromium.
