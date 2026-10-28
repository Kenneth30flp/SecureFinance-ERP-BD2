# Cierre visual de Cotizaciones y navegación modular

Incluye pulido del módulo 1, Centro de módulos y navegación por seis áreas. No se modificaron procedimientos de Facturación, Kardex, caja ni migraciones históricas.

## Demostración

URL: **http://localhost:3105/modulos**. Se conserva la instancia anterior del puerto 3104. La autenticación es normal; no se crean credenciales ni se habilitan sesiones QA en la demostración.

Base comprobada mediante `DB_NAME()`: `SecureFinanceERP_P3_COT_DEMO_20261027231053_ca62df75`. COT-6 y factura #7011 se preservan. `demostracion-preservada.json` registra comparación SHA256 de cotizaciones, facturas y productos antes/después; las pruebas de escritura usan otras bases.

PowerShell:

```powershell
Set-Location 'C:\Users\kenne\OneDrive\Desktop\CLASES\SEMESTRE 2 2026\Base de Datos 2\proyecto SecureFinance-ERP-BD2\SecureFinance-ERP-BD2'
git branch --show-current
npm.cmd run start:demo:cotizaciones -- --port 3105
Start-Process chrome 'http://localhost:3105/modulos'
```

La rama debe ser `feature/p3-kenneth-cotizaciones`. Si 3105 ya está ocupado por esta demostración, abrir la URL sin iniciar otra instancia. El iniciador rechaza otra rama/base, comprueba identidad SQL, permisos de Administrador y contrato UC09; imprime el PID, commit y base reales. No cambia `.env`. Después del inicio de sesión, `/laboratorio/estado` consulta `DB_NAME()` de nuevo y muestra la identidad del proceso. No confundir el puerto 3104 con 3105.

Rutas conservadas: `/dashboard`, `/cotizaciones`, `/cotizaciones/nueva`, `/cotizaciones/6`, `/facturacion/facturas/7011`, `/inventario`. La cuenta requiere permisos propios de cada módulo; Cotizaciones requiere CONSULTAR/CREAR/CONVERTIR según acción y VENTAS_REGISTRAR para conversión. Si falta un enlace, revisar los permisos del usuario real y recargar la sesión; no desactivar RBAC.

## Presentación

Importes con `Q 11,289.60`, usando el formateador decimal existente también para comprobantes. Vigencia comercial inclusiva cuando el límite UTC corresponde a medianoche de Guatemala; límites a otras horas mantienen fecha/hora precisa. No se modifica el límite SQL. Los identificadores DEMOCOT se etiquetan como demostración únicamente con entorno demo explícito. Se conservaron búsquedas, UUID, CSRF, edición de líneas y conversión.

Impresión con márgenes de 12 mm, tablas y totales sin cortes internos, tamaños adaptables a A4 y carta. Chrome puede agregar sus propios encabezados/pies: desactivar **Más opciones → Encabezados y pies de página** en el diálogo de impresión. CSS no controla totalmente esa opción del navegador. Cotización y comprobante siguen identificados como documentos internos, sin certificación SAT/FEL.

## Evidencias y alcance de las pruebas

`evidencias/00-*`: Centro de módulos y paneles de Ventas, Inventario, Compras, Finanzas y Administración en escritorio y móvil. `01` historial; `02` buscador; `03` formulario y cinco resoluciones; `04` historial responsive; `05` detalle; `06` confirmación; `07` impresión/PDF; `08` conversión procesada; `09` factura; `10` inventario/Kardex; `11` estado vacío. Son capturas auténticas de Chromium en una copia VISUAL, con sesión de prueba explícita, no prueba de inicio de sesión real. `resultados.json` identifica base, factura y stock. No se sustituyeron los archivos de evidencia anteriores.

Regresiones independientes se guardan en `regresiones/`. Los resultados SQL y Node se detallan en `VALIDACION.md`. Las pruebas con usuarios sin acceso al Centro se cubren por renderizado/HTTP y catálogo; no se afirma una prueba manual con credenciales de otros compañeros.
