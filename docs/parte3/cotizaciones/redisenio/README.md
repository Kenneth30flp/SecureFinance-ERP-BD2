# Cotizaciones — rediseño comercial y separación de entornos

Rama: `feature/p3-kenneth-cotizaciones`. PR #12. Tema oscuro corporativo,
composición alineada con el ERP existente, sin sustituir el motor UC09.

## Resultado de UX

- Historial orientado a documento/cliente/vigencia/total/estado, filtros compactos
  y acción Ver cotización. Importes GTQ con agrupación y centavos conservados.
- Nueva cotización en tres secciones: información general, productos y resumen
  comercial. Emisión del reloj SQL, vigencia, observaciones opcionales, total
  destacado y una acción principal clara.
- Selectores cliente/producto sustituidos por combobox de búsqueda remota:
  8 resultados por página, NIT/SKU secundarios, precio y stock visibles,
  estado vacío, paginación y respuestas cancelables al escribir otra búsqueda.
- ArrowUp/ArrowDown/Enter/Escape, nombres accesibles, aria-activedescendant,
  anuncio de resultados y foco visible. Panel con altura limitada y apertura
  hacia arriba cuando el espacio inferior es insuficiente.
- Cantidad y descuento editables en cada línea, sin eliminar/recrear el producto;
  validación y resumen inmediato con centavos enteros. SQL sigue fijando precios,
  descuentos autorizados, importes definitivos y stock al ejecutar la conversión.
- Detalle con encabezado empresarial, documento, totales y actividad. UUID en
  información técnica plegada; cancelación secundaria y conversión protagonista.
- Diálogo nativo modal accesible con importe, contado y consecuencias; Escape,
  retorno de foco y doble envío protegido. CSRF, UUID estable y reintento intactos.
- Impresión limpia como propuesta interna, diferenciada de factura tributaria.
- En móvil, navegación horizontal localizada al módulo y líneas de datos que se
  reorganizan con etiquetas; no se cambia el menú de las demás pantallas del ERP.

## Investigación de contaminación

Auditoría inicial, antes de las nuevas regresiones, en
`SecureFinanceERP_P3_COT_20261027213647_67c25f5a`: 10 clientes y 33 productos QA,
relacionados con 30 facturas, 30 detalles y 61 movimientos Kardex; 139 eventos
de Cotizaciones. Ver `auditoria-datos.json`. Los conteos QA corresponden a los
patrones de generación conocidos y no constituyen una clasificación universal.

No se borraron esos registros ni sus relaciones. El laboratorio conserva sus
pruebas y todas las evidencias publicadas anteriores en `../evidencias/`.
No se añadió ningún filtro QA en consultas de producción. La búsqueda nueva
consulta todos los registros activos autorizados, identificando stock cero.

Se separan tres destinos y archivos de estado:

| Propósito | Base de esta entrega | Estado local ignorado por Git |
| --- | --- | --- |
| Pruebas automatizadas, errores y concurrencia | SecureFinanceERP_P3_COT_20261027213647_67c25f5a | .data/cotizaciones-lab.json |
| Demostración que abre el usuario | SecureFinanceERP_P3_COT_DEMO_20261027231053_ca62df75 | .data/cotizaciones-demo.json |
| Pruebas visuales con datos comerciales | SecureFinanceERP_P3_COT_VISUAL_20261027233530_3fc452ba | .data/cotizaciones-visual.json |

La demostración se restauró del respaldo COPY_ONLY existente de Parte II,
verificado con CHECKSUM, a archivos y nombre nuevos, sin REPLACE. Se instalaron
40 (faltante en respaldo) y 41–44. Se verificó ausencia de los datos QA conocidos;
si un respaldo los contiene, el preparador se detiene sin eliminarlos.

Se reutilizaron Cable HDMI, Monitor 24 pulgadas, Mouse óptico y Teclado USB;
no se duplicaron productos. Cuando fue necesario asegurar stock, se ingresó
mediante recepción autorizada y Kardex, sin UPDATE directo de existencias.
Tres clientes ficticios están rotulados Demostración y usan identificadores
`DEMOCOT001`–`DEMOCOT003`, deliberadamente no presentados como NIT reales.

Se dejaron cinco propuestas comerciales: dos activas, una procesada, una
cancelada y una vencida. La expiración usa el reloj SQL, sin falsear fechas de
documentos existentes. La factura demostrativa se produjo mediante UC09.
La preparación creó además respaldo COPY_ONLY/CHECKSUM de la demostración y
VERIFYONLY; la ruta recuperable permanece en .data, no se publica el respaldo.

Para evitar nuevas contaminaciones, el recorrido automatizado comercial
escribe solamente en VISUAL, restaurada desde ese respaldo de demostración.
La verificación final confirmó que DEMO conserva exactamente cinco propuestas,
cero QA conocido, hash de facturas anteriores intacto y restricciones correctas.

## Cambios de backend estrictamente necesarios

44_P3_COT_BusquedaComercial.sql añade únicamente dos procedimientos de consulta:
P3_COT_PrepararFormulario (política y reloj SQL, sin catálogos) y
P3_COT_BuscarCatalogo (clase, texto NVARCHAR parametrizado y página, límite 8).
RBAC SQL usa el permiso existente COTIZACIONES_CREAR; EXECUTE específico para
la cuenta de aplicación. No concede SELECT directo sobre tablas ni permisos nuevos.

Rutas nuevas: `GET /cotizaciones/buscar/clientes` y `/productos`, con `q` y
`pagina`, bajo sesión y permiso existente. Se conservan todos los POST y la
autoridad SQL del documento. No se alteraron 41, 42, 43, los procedimientos de
venta/conversión/Kardex, caja, hashes o transacciones. El método de catálogo
anterior se conserva para consumidores y regresiones existentes, pero el
formulario web ya no descarga el catálogo completo.

## Resultados ejecutados

| Comprobación | Resultado |
| --- | --- |
| npm run check | PASS |
| npm test | 109/109 PASS; cero fallidas/omitidas |
| SQL Cotizaciones independiente | 14 grupos PASS |
| SQL UC09 existente | 27 grupos PASS, precio congelado/concurrencia/rollback/regresión |
| SQL búsqueda | 7 grupos PASS, paginación, RBAC, inyección literal, cero efectos de venta |
| Chromium regresión QA | 16 comprobaciones PASS, incluida respuesta incierta después de COMMIT |
| Chromium diseño comercial en VISUAL | 11 comprobaciones PASS, cinco tamaños y flujo completo |
| Verificación DEMO | Cero QA, cinco propuestas, históricos/EXECUTE/integridad PASS |
| git diff --check | PASS |

Anchos: 1366, 1024, 768, 390 y 320 px, sin desborde global. Se probaron también
paneles de búsqueda en móvil, selección por teclado y mouse, edición de líneas,
Tab/Escape, retorno de foco, PDF y estado vacío. Contraste de texto/control del
buscador medido en Chromium: ver `evidencias-comerciales/resultados.json`;
se verificaron umbrales de 4.5:1 y 3:1 respectivamente. Esta medición acotada no
es una certificación de accesibilidad de todo el ERP.

Durante la validación se corrigieron retorno de foco del diálogo, sincronización
del reintento, navegación móvil y alineación de impresión. Una aserción nueva
confundía orden de inserción con orden SQL por ProductoId; se corrigió para
verificar la línea por su ID. La paginación se prueba con nueve clientes creados
en QA para no depender de tamaños accidentales. No se eliminaron pruebas.

Las capturas son de Chromium real con servicios SQL reales, sin montaje ni
datos simulados como producción. La autenticación de esos ejecutores usa una
sesión fixture identificada; no acredita login manual con contraseña. El proceso
que abre el usuario en 3104 utiliza autenticación normal, sin ese fixture.

## Archivos relevantes

- Presentación: `src/views/cotizaciones/{head,new,list,detail}.ejs`,
  `src/public/css/cotizaciones.css`, `src/public/js/cotizaciones.js`.
- Consulta: `src/modules/cotizaciones/{routes,service,format}.js`, migración 44.
- Entornos: `PrepareCotizacionesDemo.ps1`, `PrepareCotizacionesVisual.ps1`,
  `VerifyCotizacionesDemo.ps1`, `InstallCotizacionesBusquedaLab.ps1` en database/tests;
  `scripts/startCotizacionesLab.js` y scripts npm de comprobación/arranque.
- Pruebas: `CotizacionesBusquedaIntegration.js`, `cotizaciones.test.js`,
  `cotizaciones.browser.js`, `cotizacionesDesign.browser.js`.
- Evidencia comercial nueva en `evidencias-comerciales/`; regresiones nuevas en
  `evidencias-pruebas/`. Las evidencias anteriores permanecen en su ruta original.

## Reproducir sin afectar la principal

Pruebas automatizadas: preparar copia con el ejecutor existente; ejecutar SQL
independiente, UC09 y búsqueda (44), luego Chromium QA. Para una presentación
nueva: ejecutar PrepareCotizacionesDemo.ps1; nunca reutilizar la base QA.
Para pruebas visuales: PrepareCotizacionesVisual.ps1 restaura su respaldo en
otra copia; ejecutar `npm.cmd run test:ui:cotizaciones:design` y después
VerifyCotizacionesDemo.ps1 para acreditar que la demostración no cambió.

El preparador conserva copias y respaldos; no incorpora borrado automático.
Al reaplicar 44 se verificó que no cambia definiciones del motor ni filas
financieras. No se instaló ninguna migración en SecureFinanceERP.

## Abrir la demostración en Chrome

```powershell
Set-Location -LiteralPath 'C:\Users\kenne\OneDrive\Desktop\CLASES\SEMESTRE 2 2026\Base de Datos 2\proyecto SecureFinance-ERP-BD2\SecureFinance-ERP-BD2'
git branch --show-current
npm.cmd run start:demo:cotizaciones -- --port 3104
```

Abrir **http://localhost:3104/cotizaciones**. Si el proceso de entrega ya está
activo, no iniciar otro en el mismo puerto. Se conservan los procesos 3000/3103;
no usarlos para evaluar este rediseño. El indicador Demostración y el puerto
permiten distinguir la instancia; detalles técnicos quedan plegados.

El lanzador fuerza la base del archivo demo en su propio proceso, conserva .env,
verifica DB_NAME, contrato UC09, consultas 44 y EXECUTE, y exige la rama correcta.
Con sesión autenticada, `/laboratorio/estado` consulta de nuevo DB_NAME.
Usar credenciales existentes de la copia; no se inventaron contraseñas. Si falta
el menú, comprobar puerto/rama/base y renovar sesión para refrescar permisos.
Administrador conserva los permisos de Cotizaciones, venta y consulta de factura.
