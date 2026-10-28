# Propuesta de extensión de Facturación para UC09

**Estado vigente:** contrato autorizado por Kenneth e implementado mediante 43.
Ver [UC09_IMPLEMENTACION.md](UC09_IMPLEMENTACION.md). La espera de aprobación
externa descrita abajo corresponde a la propuesta histórica y quedó dispensada
por instrucción posterior del coordinador; no constituye bloqueo actual.

Estado: **APROBACIÓN CONDICIONADA DEL INTEGRADOR; PENDIENTES JOSÉ Y DYLAN**.
La revisión final propuesta para aprobación es
[REVISION_TECNICA_UC09.md](REVISION_TECNICA_UC09.md), que precisa y prevalece
sobre este planteamiento inicial. Aún no autoriza implementar el cambio.
Responsable: Kenneth. Revisores afectados:
integrador, José (Promociones) y Dylan (Créditos y Multibodega).
No autoriza modificar el motor compartido. Base: a8afeb2.

## Cambio propuesto

Agregar al final de las firmas de `sp_ERP_ProcesarVenta` y
`sp_ProcesarVentaTransaccional` el parámetro opcional
`@P3CotizacionId INT=NULL`. Con NULL se conserva exactamente la venta normal.
No cambiar `TipoDetalleVentaDescuento`, Factura, DetalleFactura ni triggers.
El wrapper incorpora el origen cotización en el hash solo cuando no es NULL;
las huellas de ventas normales anteriores siguen siendo válidas.

El consumidor nuevo será `sp_ConvertirCotizacionAFactura`:
`@CotizacionId INT, @ActorUsuarioId INT, @OperacionId UNIQUEIDENTIFIER`.
Obtiene líneas exclusivamente del documento SQL, construye el TVP y llama
al wrapper dentro de la misma transacción. Bloquea cabecera y exige permiso
COTIZACIONES_CONVERTIR además de VENTAS_REGISTRAR; valida cliente, vigencia y
estado. Toda llamada con P3CotizacionId, incluso una directa al wrapper, debe
validar este mismo origen, permiso y correspondencia completa de líneas.

En el núcleo se sustituye la fuente del precio:
para origen válido se usa el snapshot de `P3_COT_Detalle`, no Producto.Precio.
El SKU y la descripción de la factura seguirán capturándose al facturar como
establece el trigger 39; la cotización conserva su propia identidad histórica.
Esta decisión explícita requiere aprobación y evita cambiar ese trigger.
No aceptar precios vía parámetros ni SESSION_CONTEXT como autorización.
El núcleo mantiene validaciones de existencia, actividad, stock, orden de
bloqueos, Factura/DetalleFactura, caja y Kardex existentes. Debe cotejar los
totales resultantes con el documento antes de confirmar. No corregir después.

## Precios, descuentos y promociones

Creación toma Producto.Precio en SQL y congela SKU, descripción, precio,
porcentaje autorizado y montos. IVA actual 12%, descuento redondeado por
línea y luego IVA sobre neto global. SQL exige la política vigente de venta
al crear y al convertir: si el actor no puede autorizar el descuento pactado,
rechazar sin recalcular. No implementar promociones de José en esta etapa.
Propuesta para José: promoción incorporada una vez al emitir, con referencia
y snapshot futuros; no reevaluarla ni aplicarla dos veces al convertir.
Esta política promocional requiere su acuerdo, no se considera implementada.

## Finanzas y bodega

Primera versión solo contado: el motor actual inserta MovimientoCaja por el
total. No admitir crédito hasta integrar el contrato de Dylan; jamás cobrar
en caja una venta al crédito. Inventario global, sin BodegaId ficticio.
La futura modalidad/bodega debe formar parte de la huella y de los bloqueos
del motor único; requiere otro contrato antes de habilitarse.

## Idempotencia, transacciones y concurrencia

La conversión conserva UUID y actor; mismo UUID/cotización/actor devuelve la
misma factura. Otro UUID sobre documento procesado se rechaza. UUID usado por
otra cotización falla. Bloquear documento UPDLOCK/HOLDLOCK; luego wrapper
ERP y productos por PK ascendente; no adquirir locks en orden inverso.
El wrapper debe marcar PROCESADA y vincular FacturaId dentro de la misma
transacción, incluso en llamadas directas autorizadas; UC09 no repite esa
actualización. Así se impide facturar sin cerrar la cotización. El
wrapper no confirma la transacción externa por sí solo; cualquier error del
núcleo o Kardex puede revertirla íntegra. No capturar errores para confirmar
parcialmente. El comprobante idempotente sigue en SolicitudVentaERP.

## Pruebas exigidas antes de aprobar integración

- Precio 100 × 2, catálogo cambia a 120: factura a 100, catálogo a 120.
- Totales, IVA y descuentos idénticos; creación no cambia stock/caja.
- Venta normal y reintentos anteriores conservan comportamiento y hash.
- Mismo documento con dos actores, mismo UUID y UUID distintos; solo una factura.
- Dos cotizaciones por último stock: una sola salida, nunca saldo negativo.
- Fallo tras Factura y antes de Kardex revierte documento, factura, caja y stock.
- Llamada manual al wrapper con origen inventado, ajeno o líneas alteradas falla.
- Permisos revocados, cliente/producto inactivo, vencimiento, descuento no autorizado.

Hasta aprobación escrita no se crean migraciones que alteren estos objetos.
La creación, TVF, consultas, historial, seguridad y web del módulo pueden
validarse de forma independiente. La conversión permanecerá explícitamente
no disponible; no se simulará una factura ni una congelación no implementada.
