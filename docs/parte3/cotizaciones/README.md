# Cotizaciones — Kenneth

**Estado actual: UC09 implementado y validado en laboratorio.** La orden posterior
de Kenneth autorizó el contrato y sustituyó la espera de aprobaciones externas.
La documentación vigente está en [UC09_IMPLEMENTACION.md](UC09_IMPLEMENTACION.md),
[RESULTADOS_UC09.md](RESULTADOS_UC09.md) y [EJECUCION_CHROME.md](EJECUCION_CHROME.md).
Se utilizan 41, 42 y 43; 106 pruebas Node, 27 grupos SQL UC09 y Chromium PASS.
El contenido siguiente documenta la entrega independiente anterior a UC09 y
sus limitaciones históricas; sus menciones de bloqueo no rigen la versión actual.

Rama: `feature/p3-kenneth-cotizaciones`, desde `integracion/parte3` en
`a8afeb2e0c485f8cc4448b47a306001309ce5119`.

## Estado real de la entrega

Implementado y probado contra SQL Server real en laboratorio: emisión de
cotizaciones, precios históricos, múltiples productos, descuentos autorizados,
IVA 12%, UUID idempotente, historial, detalle, filtros, paginación, comprobante
interno, TVF de vigencia y cancelación auditada e idempotente. Crear no reserva
stock ni crea Factura, MovimientoCaja o Kardex.

**UC09 NO está implementado ni habilitado.** No existe todavía
`sp_ConvertirCotizacionAFactura` ni un endpoint de conversión. La propuesta
[PROPUESTA_PRECIOS_CONGELADOS.md](PROPUESTA_PRECIOS_CONGELADOS.md) requiere
aprobación escrita del integrador y coordinación con José y Dylan antes de
modificar los procedimientos compartidos. No se presenta esta entrega como
módulo completo. El PR debe permanecer en borrador hasta resolverlo.

No se modificaron procedimientos, TVP, tablas ni triggers compartidos de
Facturación/Kardex. Los únicos puntos web compartidos editados son la
composición de rutas en server.js, menú navigation.ejs y scripts de package.json.

## Objetos y seguridad

- Tablas: `P3_COT_Cotizacion`, `P3_COT_Detalle`, `P3_COT_HistorialEstado`.
- TVF: `P3_COT_Vigencias()`. Proyecta VENCIDA mediante SYSUTCDATETIME sin UPDATE;
  los estados persistidos son ACTIVA, CANCELADA y PROCESADA (reservado para UC09).
- Procedimientos: `P3_COT_Crear`, `P3_COT_Consultar`, `P3_COT_Catalogos`,
  `P3_COT_Cancelar`.
- Triggers propios impiden editar condiciones/detalles históricos o borrar
  documentos y estados. Los CHECK relacionan totales y factura con el estado.
- Permisos: COTIZACIONES_CONSULTAR, COTIZACIONES_CREAR,
  COTIZACIONES_CONVERTIR (reservado, aún sin operación), COTIZACIONES_CANCELAR.
  Asignación inicial solo Administrador; otros roles requieren revisión explícita.
- `securefinance_app` recibe EXECUTE solo sobre cuatro procedimientos nuevos;
  se deniega DML/SELECT directo sobre tablas y SELECT directo sobre TVF.
- Actor procede de sesión HTTP. RBAC HTTP y SQL, token CSRF exclusivo del módulo,
  tipos SQL, mensajes seguros y escape EJS. Creación ignora precios e importes
  web y usa Producto.Precio bajo HOLDLOCK. Se congela también nombre/NIT del cliente.
- El hash de emisión incluye actor, cliente, vencimiento, observaciones y líneas
  ordenadas. Misma referencia/carga devuelve el documento original, aunque el
  catálogo haya cambiado. Referencia alterada produce conflicto. Cancelación
  compara referencia, documento, actor y motivo exacto.
- Emisión/cancelación e inserción de historial y Bitacora_Transacciones son
  atómicas. No se simula un login real en pruebas automatizadas del navegador.

## Migraciones, instalación y recuperación

Orden: Parte II hasta 40 → `41_P3_COT_EstructuraCotizaciones.sql` →
`42_P3_COT_Operaciones.sql`. Resto del rango 43–49 permanece libre para el módulo.
No editar migraciones antiguas ni ejecutar Full sobre una base existente.

Preflight: respaldo COPY_ONLY con CHECKSUM recuperable, esquema real hasta 40,
cuenta de aplicación y Administrador activos, permisos de instalación del DBA,
ausencia de objetos P3_COT incompatibles, reserva de números vigente y revisión
del diff. Los scripts no llevan USE ni cambian la configuración activa.

Laboratorio reproducible en Windows con SQL Server local y acceso Windows DBA:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File database/tests/PrepareCotizacionesLab.ps1
npm.cmd run test:sql:cotizaciones
npm.cmd run test:ui:cotizaciones
powershell -NoProfile -ExecutionPolicy Bypass -File database/tests/VerifyCotizacionesLab.ps1
npm.cmd run check
npm.cmd test
git diff --check
```

Prepare usa el último respaldo COPY_ONLY **existente**, VERIFYONLY y restauración
en un nombre nuevo con patrón `SecureFinanceERP_P3_COT_<fecha>_<sufijo>` y MOVE
a archivos separados, sin REPLACE. Si falta respaldo, falla sin crearlo. No crea
ni restaura encima de SecureFinanceERP. Aplica 40 únicamente en la copia si
el respaldo la precede, luego 41 y 42; ejecuta CHECKDB/CHECKCONSTRAINTS.
Registra el nombre del laboratorio y baseline en `.data/cotizaciones-lab.json`
(ignorado). Los ejecutores Node fuerzan ese destino antes de abrir el pool y
comprueban DB_NAME; conservan .env y la configuración de la aplicación.

Las pruebas requieren que la cuenta existente de aplicación pueda acceder a
la copia restaurada. No conceder db_owner ni modificar contraseñas para resolver
un fallo. Cada preparación crea un laboratorio nuevo y lo conserva para revisión;
no incluye limpieza destructiva automática.

El ejecutor instala cada archivo en una transacción externa a través de sus
batches GO. Una falla revierte el archivo completo y detiene el proceso. La
reaplicación en copia validó que no duplica permisos ni borra documentos.
Ante un objeto incompatible, detenerse e inspeccionar; no eliminarlo para
forzar la instalación. Recuperación: volver a la versión de aplicación anterior
y conservar tablas/documentos; restaurar el respaldo solo en otra copia para
comparar. No se proporciona un down destructivo. Esta entrega no despliega
la base principal; cualquier despliegue posterior exige su ventana autorizada.

## Pruebas y límites

Consultar [RESULTADOS.md](RESULTADOS.md) y [EVIDENCIAS.md](EVIDENCIAS.md).
La suite Node incluye mocks identificados. Los ejecutores de laboratorio usan
el driver y procedimientos reales. La prueba de precio 100→120 acredita el
snapshot de cotización, **no** una factura congelada.

Pendientes por aprobación: extensión de venta, conversión atómica, factura,
stock/Kardex/caja de conversión, reintento y concurrencia de conversiones,
competencia por stock y fallo después de insertar Factura. No se afirman
pruebas satisfactorias de esas funciones ausentes.

Con José queda acordar promociones congeladas al emitir, referencias y evitar
doble descuento. Con Dylan: modalidad de crédito y efectos financieros (no
efectivo ficticio) y bodega de salida futura. Actualmente ni crédito ni bodega
se exponen en el documento; no se inventan ubicaciones ni documentos históricos.
