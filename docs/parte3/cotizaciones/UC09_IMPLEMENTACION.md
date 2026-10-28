# UC09 — contrato autorizado e implementación

Kenneth, responsable de Cotizaciones y coordinador de integración, autorizó
expresamente la implementación completa en esta rama y la extensión compatible
de Facturación propuesta en REVISION_TECNICA_UC09.md. Esta instrucción posterior
sustituye la condición de obtener aprobación de cuentas de José y Dylan.
No se atribuye a esos responsables una aprobación que no emitieron.

Alcance operativo: **cotización → factura de contado → caja → stock → Kardex**.
Promociones, crédito y multibodega mantienen contratos de integración futuros;
sus ramas y módulos no se modificaron.

## Objetos y migraciones

Se conserva 41–42 sin editarlas. La migración incremental
`43_P3_COT_ConversionFactura.sql` instala:

- `sp_ConvertirCotizacionAFactura(@CotizacionId INT,@ActorUsuarioId INT,@OperacionId UNIQUEIDENTIFIER)`.
- Extensión de `sp_ERP_ProcesarVenta` y `sp_ProcesarVentaTransaccional`, agregando
  **al final** `@P3CotizacionId INT=NULL`.
- `P3_COT_ValidarOrigen`: validación privada compartida de documento, permisos,
  acceso, líneas, motivo, estado y vigencia. Sin EXECUTE directo a la aplicación.
- `P3_COT_EstadoConversion`: comprobación de firmas, instalación, permisos
  efectivos de la cuenta de aplicación y autorización del actor/documento.
- EXECUTE específico de UC09 y estado; se conserva DENY de ejecución directa
  del núcleo y ventas antiguas. Sin DML directo sobre tablas nuevas.

No cambia el TVP, SolicitudVentaERP, Factura, DetalleFactura, MovimientoCaja,
el procedimiento Kardex ni los triggers de factura. No se editan 21/37/41/42.
No se consumen números fuera de 41–49. Quedan libres 44–49.

43 debe instalarse como un conjunto de batches GO en **una transacción externa**.
El instalador de laboratorio lo hace así. Requisitos: esquema real hasta 40,
41–42, snapshots de factura 39, cuenta de aplicación y permisos vigentes.
La reaplicación se probó preservando documentos y comprobantes.

## Motor único, importes y descripciones

NULL conserva llamadas nominales/posicionales, política y precio de catálogo
de la venta normal. La construcción del hash normal se mantiene literalmente
como en 37; se probó con una venta emitida en laboratorio **antes de instalar 43**.

Con origen cotización, SQL verifica TVP/cliente contra todas las líneas del
documento y toma PrecioUnitario de P3_COT_Detalle. No recibe precios HTTP ni
cambia Producto.Precio. Usa el mismo cálculo DECIMAL, inserción Factura/detalle,
MovimientoCaja y llamada Kardex del núcleo existente. Compara importes de cada
línea y totales con la cotización antes de insertar Factura. Si hay diferencia,
revierte; nunca corrige importes después de emitir.

Descuentos actuales: manuales pactados, sin aplicar promociones adicionales.
Motivo determinista Ajuste comercial cuando hay descuento, NULL en caso contrario.
Se exige la política vigente del actor al convertir; si pierde autorización
para el porcentaje pactado se rechaza, sin recalcular el documento.

La cotización conserva SKU/descripción y nombre/NIT de emisión. La factura usa
la política previa de snapshot de identidad **al facturar** mediante el trigger
39. El comprobante y JSON de venta coinciden con esa identidad, aunque la
descripción del catálogo cambie desde que se cotizó. Los importes permanecen
pactados. Esta distinción evita alterar los triggers o documentos históricos.

## ACID, idempotencia y acceso

UC09 abre transacción externa; el wrapper equilibra su nivel y el núcleo solo
confirma si la transacción es propia. Cualquier error revierte todo el conjunto.
El CATCH del núcleo limpia además contexto de auditoría para no dejarlo en el pool.

El wrapper cierra PROCESADA/FacturaId, historial y auditoría dentro de la misma
transacción que el libro idempotente y la venta. Esto se cumple también si se
invoca directamente con un origen válido. UC09 no vuelve a cerrar ni descontar.

Orden: permisos → cotización UPDLOCK/HOLDLOCK → UUID ERP.Venta → corte compartido
→ cliente/política → productos por PK ascendente → Kardex → cierre. Se revalida
vigencia con SYSUTCDATETIME después de esperar inventario y antes de Factura.

La huella de cotización tiene prefijo P3COT:v1 e incluye documento, actor,
cliente, motivo y líneas históricas canónicas. No puede confundirse con una
venta normal. Reintento exige coincidencia de actor, UUID, huella, factura e
historial; devuelve el comprobante persistido aun después de vencer o agotar
stock. Otro UUID sobre PROCESADA o UUID con otra carga produce conflicto.

Se exige COTIZACIONES_CONVERTIR y VENTAS_REGISTRAR, y ser creador o Administrador
activo. Consulta no implica conversión. Dos administradores pueden competir;
solo uno factura. La aplicación conserva autenticación de sesión, CSRF y actor
del servidor. SQL no interpreta SESSION_CONTEXT como autorización del precio.

## Interfaz y contrato HTTP

`POST /cotizaciones/:id/convertir`, JSON `{OperacionId: UUID}`, con CSRF.
Actor de sesión; cualquier precio, cliente o líneas HTTP carecen de efecto.
Modalidad de crédito o bodega se rechazan explícitamente: solo contado/global.

El botón solo aparece para ACTIVA cuando SQL confirma instalación, firma
opcional en ambos procedimientos, EXECUTE y autorización, además de RBAC HTTP.
Una instancia sin 43 permite consultar cotizaciones pero no simula conversión.

UUID por documento conservado en sesión entre cargas y al reintentar; no cambia
en errores de red/503. Confirmación de contado, bloqueo de doble clic, mensajes
de expiración, permisos y stock, consulta del estado y enlace a factura. Cuando
la transacción ya fue confirmada, PROCESADA impide presentar otra conversión.

Servicio espera los resultados completos: dos recordsets de comprobante y un
tercero de metadatos de conversión; verifica IDs/estado/UUID antes de responder.
Un resultado incierto no se anuncia como éxito. El navegador probó un 503
inyectado **después** del COMMIT y recuperó la misma factura sin otra salida.

## Laboratorio y recuperación

Nunca ejecutar estas pruebas sobre SecureFinanceERP. Los ejecutores validan
patrón de laboratorio y DB_NAME, no ofrecen destino principal ni reescriben .env.

Para reproducir toda la regresión desde una copia nueva (Windows DBA local):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File database/tests/PrepareCotizacionesLab.ps1
npm.cmd run test:sql:cotizaciones
npm.cmd run test:sql:uc09
npm.cmd run test:ui:cotizaciones
powershell -NoProfile -ExecutionPolicy Bypass -File database/tests/VerifyCotizacionesLab.ps1
npm.cmd run check
npm.cmd test
git diff --check
```

UC09Integration primero crea una venta de regresión con el wrapper anterior,
guarda sus hashes/JSON y luego instala 43 atómicamente. Por eso la preparación
de esta secuencia va **sin** IncludeConversion. Reruns en la misma copia usan
la evidencia pre-43 conservada en .data y no inventan esa antigüedad.

Para una copia solo destinada a probar manualmente, se puede preparar con
`-IncludeConversion`. Para instalar 43 en una copia previa 41–42, usar
`database/tests/InstallCotizaciones43Lab.ps1`. Esos scripts solo restauran o
modifican la copia validada, sin REPLACE ni limpieza destructiva.

Respaldo previo: COPY_ONLY/CHECKSUM existente, VERIFYONLY y restauración con
MOVE a archivos nuevos. Si falta un respaldo recuperable, detener sin resetear.
Si una instalación falla, rollback del conjunto; conservar copia y evidencias
para diagnóstico. No borrar tablas para forzar reaplicación.

Si hubo documentos emitidos con 43, no bajar el código a un wrapper que ignore
el origen. Detener el proceso de laboratorio y conservar datos; ensayar la
recuperación desde respaldo en otra copia, sin borrar o reescribir historia.
No se autoriza despliegue en principal con esta entrega.

## Contratos para José y Dylan

- José: el origen cotización ya tiene descuento manual pactado; no aplicarlo
  de nuevo. Una promoción futura requiere snapshot/procedencia al emitir y
  ampliar su huella de forma versionada, sin invalidar documentos anteriores.
- Dylan/Crédito: la venta actual registra contado en caja; una modalidad nueva
  necesita contrato explícito y efectos distintos. No basta añadir un campo
  HTTP e ignorarlo. No se compensan notas de crédito ni se simulan cobros.
- Dylan/Multibodega: inventario global actual. Definir bodega de salida, locks,
  autorizaciones y huella antes de habilitarla; no reconstruir bodega histórica.
- Mantener parámetro opcional, rama NULL y huellas anteriores al extender;
  futuras migraciones deben partir de la definición 43, no copiar de nuevo 21/37.

Ver [RESULTADOS_UC09.md](RESULTADOS_UC09.md), [EVIDENCIAS.md](EVIDENCIAS.md) y
[EJECUCION_CHROME.md](EJECUCION_CHROME.md).
