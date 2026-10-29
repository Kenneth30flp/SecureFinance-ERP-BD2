# Patrones visuales aplicados en Compras

Se inspeccionaron navigation.ejs, kenneth-head/field/confirm, operational-date,
proveedores.ejs, vistas de cotizaciones, moduleCatalog, styles.css,
navigation.css, kenneth.css, cotizaciones.css y sus scripts de navegacion.

Compras reutiliza Bootstrap local, tokens oscuros de styles.css, tipografia
Segoe UI, sidebar/topbar y marca existentes. Su CSS esta limitado a clases
com- y su JavaScript a sus propios formularios. No se cambia el tema global.

Pantallas: listado con filtros/estados y vacios, alta con pasos y resumen,
documento con acciones por permisos, recepcion con limites pendientes,
entregas, linea temporal y valoracion. El documento incluye proveedor/NIT,
fecha de Guatemala, responsable, lineas, costos de cuatro decimales y total.
La impresion oculta navegacion, formularios e historiales auxiliares.

En moviles las tablas se transforman en filas etiquetadas, columnas de
formulario se apilan y el resumen deja de ser fijo. Botones y controles
mantienen altura util. No hay bodega ficticia; se indica Inventario global.

Accesibilidad: skip link, main enfocable, labels, captions, encabezados de
fila, mensajes role=alert, aria-live en resultados, foco visible, dialogo
nativo con titulo, Tab contenido y Escape sin enviar. EJS escapa los datos y
el JavaScript inserta texto mediante textContent. La vista previa monetaria
usa BigInt; al confirmar se muestran los resultados definitivos de SQL.

Se verificaron las cuatro pantallas en Chromium real a 1440, 1024, 768 y 390 px
con servicios simulados; sin desbordamiento horizontal ni errores JavaScript.
Se generaron capturas y PDF en .data/compras-ui (ignorado por Git). Se reviso
visualmente detalle de escritorio y alta movil. Esta evidencia es sintetica,
no una demostracion contra datos SQL operativos. Ver RESULTADOS.md.
