# Evidencia Y Validacion Mod5

Fecha: 2026-10-28 (ampliada 2026-10-29). Rama `feature/p3-dylan-multibodega`, HEAD/base `1bca099`. Entrega local sin commit ni despliegue. Este documento registra salidas observadas; no son resultados SQL simulados presentados como reales.

## ADICION 2026-10-29: Integracion E2E multibodega ejecutada EN EL LAB (6/6 PASS)

El ciclo completo de integracion se ejecuto REAL contra `SecureFinanceERP_Lab_Dylan`
con `database/tests/P3_BOD_Integraciones.ps1` (ADO.NET, dos contextos de sesion,
actor sintetico `P3_DYLAN_QA_ADMIN`, queries relativas antes/despues para que la
suite sea re-ejecutable). Resultado: 6/6 fases PASS.

- F1 transferencia completa Central->Z10 (8 uds): RECIBIDA, stock local destino +8, global invariante.
- F2 venta con ubicacion (PRUEBA 19): P3_COT_Crear -> P3_BOD_ConvertirCotizacion con contexto de bodega -> factura y salida Kardex/Ledger en Z10 (local -2, global -2); verificado que el motor de Kenneth asigna su PROPIO OperacionId al Kardex de venta (la resta se deriva via P3_BOD_Ledger, no se asumo el GUID del wrapper).
- F3 devolucion APTA con reingreso en Z10 (PRUEBA 20, proc de Edward 24 usado tal cual): Kardex DEVOLUCION + Ledger vinculados via DevolucionKardex, nota de credito, +1 local y +1 global.
- F4 devolucion DEFECTUOSA sin reingreso (PRUEBA 21): Reingresar=false, 0 filas Kardex/0 Ledger, stock intacto, nota de credito emitida y evento DML auditado.
- F5 consistencia Ledger<->Kardex: mismatches=0, duplicados=0.
- F6 conciliacion integral 0 diferencia tras el ciclo completo, con eventos DML cruzados por cada operacion (transferencia/cotizacion/devoluciones).

Evidencia con numeros exactos: `docs/parte3/multibodega/EVIDENCIA_SQL_BOD_INTEGRACIONES.txt`
(JSON crudo en `%TEMP%\opencode\P3_BOD_Integraciones.json`). No se modifico ninguna
migracion del modulo (80-89) ni procs de Kenneth/Edward; los convertidores y el
wrapper se ejecutaron tal cual.

## Ejecutado Localmente

| Comando | Resultado observado |
| --- | --- |
| `npm.cmd run check` | PASS, salida 0. Check original del repositorio. |
| `node scripts/checkMultibodega.js` | PASS, salida 0. Cinco archivos propios con `node --check`, sin SQL. |
| `node --test tests/multibodega.test.js` | PASS, 26 pruebas, 0 fallidas, 0 omitidas. Revision cruzada helper/locks/costo incluida. |
| `npm.cmd test` | PASS, 141 pruebas, 0 fallidas, 0 canceladas, 0 omitidas. Incluye las 26 propias. |
| `git diff --check` | PASS. Solo advertencias informativas LF/CRLF en archivos existentes modificados. |

Entorno de pruebas: `NODE_PATH` hacia `SecureFinance-ERP-BD2/node_modules` del repositorio original, sin instalar dependencias ni escribir alli. TEMP y TMP apuntaron a `C:\Users\ALBRYGTH\AppData\Local\Temp\opencode`, cuya existencia se verifico. No se ejecuto start, check:db, test:sql, migraciones ni SQL via MCP. No se configuro ni intento una conexion SQL y no se altero confianza TLS.

Las pruebas HTTP levantan servidores Express efimeros locales con sesiones y servicios mock inyectados. No son una conexion SQL exitosa. Las pruebas JS ejecutan el archivo real en un DOM minimo mediante `node:vm`; no son Chromium, Edge ni capturas visuales.

Cobertura propia realmente ejecutada:

- Enteros positivos/rango INT, UUID, version hexadecimal, origen distinto y textos limitados.
- Costos exactos como cadenas, rechazo de exponente/numero flotante financiero, campos de actor/precios de venta descartados.
- Altas/ediciones/bajas logicas y modalidad contado/credito con plazo/cuotas.
- Fechas calendario y UTC Guatemala, filtros repetidos rechazados, paginacion y adelanto de fila.
- Sesion requerida, cambio obligatorio de password, RBAC HTTP y autorizacion SQL mock vigente para sesiones revocadas.
- CSRF independiente, todas las rutas de escritura, actor de sesion, UUID y carga identicos al reintentar.
- Render de todas las pantallas, escape EJS, comprobante imprimible de solo lectura, Auditor sin formularios y ningun mutador por GET.
- Catalogo de navegacion real y assets CSS/JS/Bootstrap disponibles con NODE_PATH.
- Parametros RPC tipados, version BINARY(8), costo VARCHAR convertido en SQL, recibo final y referencia coherente.
- Errores seguros sin internos SQL, 503 incierto y consulta 404 que no afirma fracaso definitivo.
- Script JS real: doble clic bloqueado, carga persistida antes de POST, restauracion tras recarga, reintento manual con los mismos bytes de payload, sin reenvio automatico, bloqueo si storage falla e impresion sin POST.
- Inspeccion ESTATICA de los diez SQL: guards, transaccion externa, rango reservado, no reemplazo de motores compartidos y multirow ordenado. No se permite UPDATE Producto excepto UNA sentencia de 85 que cambia SOLO PrecioCosto; no escribe Stock.
- Contrato del helper interno P3_BOD_ValidarBodegaVenta: firma exacta de dos INT, BODEGAS_CONSULTAR vigente, ID/activo, sin recordsets, prelocks de Producto/locales ni DML; sin GRANT app y con DENY directo.
- Contrato del converter: sin consultas/prelocks de Producto, stock local o detalle de cotizacion; replay BOD antes del helper, y ambos converters centrales reciben su contrato original sin checks locales prematuros.
- Contrato del wrapper compra: lectura del stock/costo bajo UPDLOCK/HOLDLOCK antes de UNA llamada a 34 con el costo unitario original; exigir el ingreso nuevo esperado antes de UPDATE solo PrecioCosto (evita valorar un replay nativo concurrente), captura/restauracion de contexto de auditoria en ambas rutas, null/overflow y respuesta monetaria como cadenas.
- Oraculo matematico BigInt de centavos: 100@20+25@30, stock cero, mitad exacta y valores a ambos lados de medio centavo incluso con denominador INT_MAX. Es matematica de referencia en pruebas, NO ejecucion de expresiones SQL ni una segunda implementacion productiva.
- Servicio y HTTP/EJS: costo documental y promedio separados, respuesta SQL/mock conservada sin recalculo financiero JS, costo desconocido como null/no calculado, errores 58008 seguros y escape del recibo.

La revision anterior tuvo 20 pruebas propias / 135 totales. Estos nuevos conteos corresponden a la ejecucion posterior a los cambios del helper, orden de conversion y ponderado; no se trasladan resultados antiguos como validacion del SQL nuevo.

## SQL Preparado, No Ejecutado

| Archivo | Proposito | Estado |
| --- | --- | --- |
| `database/80_P3_BOD_Estructura.sql` a `89_P3_BOD_Verificacion.sql` | Implementacion SQL real del modulo | Preparados, NO compilados/instalados |
| `database/tests/P3_BOD_InstallLab.sql` | Una conexion, transaccion externa para todos los GO, SQLCMD aborta al primer error | NO ejecutado |
| `database/tests/P3_BOD_Fixture100.sql` | Un proveedor y dos productos sinteticos: 100@20 y stock cero/costo NULL, antes del snapshot; no claves ni apertura | NO ejecutado |
| `database/tests/P3_BOD_Transferencias.sql` | 100 inicial, propuesta, 95+0+5 tras despacho, 95+5+0 tras recibo; replay y ocho rechazos | NO ejecutado |
| `database/tests/P3_BOD_Integraciones.sql` | Ponderado 100@20+25@30=125@22, replay, costo documental/auditoria, siete casos de valoracion y rollback por stock local/contexto | NO ejecutado |

El script de transferencias comprueba que no se inserten movimientos globales por transferir y que se creen solo dos entradas locales. Los ocho rechazos preparados son cantidad cero, origen=destino, stock insuficiente, recepcion sin despacho, UUID con carga diferente, version obsoleta, doble recepcion y stock consumido despues de preparar. Cada fallo revierte la transaccion y comprueba conciliacion.

El script de integraciones exige inventario global YA habilitado por un proceso DBA independiente; no lo activa. El fixture limpio debe tener 100 unidades a 20.00 y otro producto en cero/costo NULL; no se adapta un producto existente a escondidas. Compra 25 unidades a 30.00 y exige 125@22, recibo con promedio 22.00, documento con unitario 30.00 y exactamente una auditoria DML del cambio 20->22 con actor/UUID/motivo. Repetir UUID conserva el mismo recibo y no agrega ledger ni recalcula costo.

Siete escenarios adicionales preparados: costo de recepcion desconocido preserva el anterior sin promedio; stock cero adopta 30; 100@20+1@20.50 redondea a 20.00; 100@20+1@20.51 redondea a 20.01; stock previo con costo NULL rechaza conocido sin inventar cero; inicial fuera de DECIMAL(12,2) rechaza; ponderado fuera de rango rechaza. La alteracion a NULL es setup sintetico explicitamente contenido en rollback, no una politica de negocio. Todos los escenarios verifican rollback. No se afirma que esos SQL hayan pasado.

Otro escenario despacha cinco y solicita ajuste global de 96: el global permitiria la salida, pero central solo tiene 95 y el espejo debe revertir toda la transaccion. Tambien prueba que el wrapper rechace sin borrar un contexto ajeno. Los escenarios se revierten; no sirven para crear datos de demostracion persistidos.

La falta de cadena de certificados TLS confiable sigue siendo bloqueo de validacion real. No se uso `trustServerCertificate`, cifrado deshabilitado, cadena nueva ni credenciales alternativas. El bloqueo no se considera un resultado de negocio ni motivo para fabricar evidencia.

## Matriz Concurrente Pendiente

Todos los casos siguientes estan PENDIENTES, no PASS. Requieren laboratorio autorizado, actores reales activos, inventario habilitado solo cuando la integracion global lo exige y clientes/cotizaciones sinteticos preparados por su modulo. No inventar IDs. Guardar salida de ambas sesiones, tiempos, rollback/COMMIT y conciliacion final, sin secretos.

| Caso | Sesion A / Sesion B | Resultado exigido |
| --- | --- | --- |
| Mismo despacho / mismo UUID y carga | A despacha y retiene transaccion; B reintenta | B espera; mismo recibo tras COMMIT de A; una sola salida |
| Mismo UUID / distinta carga o actor | Dos solicitudes autorizadas con UUID identico | Una ejecucion; otra rechazada; no fuga de recibo ajeno |
| Dos despachos compiten por origen | Dos propuestas de 80 con central 100 | Solo una despacha; otra 58005; local 20, transito 80, total 100 |
| Recepcion duplicada / UUID distinto | Dos sesiones reciben la misma transferencia con version original | Una recibe; otra 58003; una sola entrada |
| Despacho y venta del mismo producto | A despacha 5; B intenta vender mas de 95 locales | Venta rechazada y factura/caja/global revertidos |
| Compra y transferencia opuesta | Compras en bodega mientras A->B y B->A | Orden de producto/locales; sin negativos ni suma incorrecta; investigar cualquier deadlock |
| Dos compras ponderadas del mismo producto | Partir 100@20; A compra 25@30 y B 25@40 | Bloqueo serializa lectura del costo previo; resultado 150@25 para estos valores, dos documentos y ninguna compra duplicada |
| Costo con transito | Despachar 5 de 100@20 y luego comprar 25@30 | Calcular con Stock global 100, no 95 locales; total 125, costo 22 y transito aun 5 |
| Inactivacion y despacho | A inactiva; B prepara/despacha hacia esa bodega | No puede quedar inactiva con stock o propuesta/despacho pendiente |
| Cambio central y venta heredada | A cambia central; B opera sin contexto | Una central activa coherente, sin ubicacion por nombres |
| Multirow Kardex | Lote sintetico privilegiado con dos productos en orden inverso | Todos los productos bloqueados primero ascendente; ledger por producto/KardexId, atomico |
| Multirow neto suficiente / prefijo negativo | Egreso antes de ingreso que solo compensaria el saldo final | Rechazo completo; no esconder deficit intermedio |
| Converter directo contra wrapper BOD | Misma cotizacion/UUID y replay despues de consumir stock local | Core conserva orden cotizacion -> credito si aplica -> productos; wrapper sin prelocks ni chequeo de disponibilidad previo al replay; sin doble factura |
| Recepcion heredada contra wrapper nuevo | Llamadas directas de 34 y BOD sobre mismos productos/proveedores/UUID | No doble efecto ni promedio recalculado; documentar esperas/deadlocks pendientes por los ordenes del motor 34 |
| Public Creditos directo contra wrapper BOD | Misma cotizacion/UUID con llamadas directas y anidadas | Helper interno con firma 76/77 presente, una factura de credito, contexto correcto, sin caja contado y sin Product prelock exterior |
| Rollback externo tras exito del SP | A ejecuta dentro de transaccion y revierte | Ningun stock/ledger/libro/auditoria propio queda confirmado |
| Timeout/cancelacion/pool | Interrumpir despues de tomar contexto; reutilizar conexion controladamente | No heredar ubicacion; descartar conexion cancelada si no se puede garantizar limpieza |
| Permisos revocados durante espera | Revocar permiso o desactivar usuario antes/despues de la validacion SQL | Si revocacion confirma primero, rechaza. Si ya valido dentro de la transaccion, HOLDLOCK serializa la revocacion; la siguiente solicitud/replay debe rechazar |

Patron manual para retener bloqueos en la sesion A, despues de obtener IDs/version/UUID REALES del fixture y comprobar DB_NAME exacto:

```sql
-- SOLO bosquejo de prueba: variables proporcionadas por el responsable del laboratorio.
BEGIN TRANSACTION;
EXEC dbo.P3_BOD_AvanzarTransferencia
 @ActorUsuarioId=@Actor, @OperacionId=@Operacion,
 @TransferenciaId=@Transferencia, @Accion='DESPACHAR',
 @VersionEsperada=@Version, @Motivo=N'Ensayo concurrente documentado';
WAITFOR DELAY '00:00:08';
COMMIT TRANSACTION;
```

La sesion B se inicia DURANTE la espera y ejecuta la misma solicitud o la variante del caso. El recibo de A dentro de una transaccion externa no es confirmacion hasta su COMMIT. Si se presenta un error, no continuar ni confirmar la transaccion que el SP pudo haber revertido por completo. No generar UUID nuevo como reintento de una respuesta incierta.

Tras detener escritores o bajo un aislamiento consistente previamente aprobado:

```sql
SELECT ProductoId,Codigo,Stock,StockLocal,Transito,Diferencia
FROM dbo.P3_BOD_Conciliacion
WHERE Diferencia<>0;
-- Resultado exigido: cero filas. NO es un resultado observado en esta entrega.
```

## UI Pendiente

Las vistas y assets responden en HTTP mock y el CSS contempla tablas adaptadas, teclado/foco, print y anchos pequenos. Falta navegador real a 1366, 1024, 768, 390 y 320, zoom 200%, navegacion por teclado, impresion/PDF, cambio de cuenta, reintento tras interrupcion y lectura de pantalla. No se adjuntan capturas inventadas ni se presenta una sesion mock como demostracion SQL.

## Inventario De Cambios

Archivos existentes limitados a `server.js` (factory/ruta y resolucion Bootstrap por dependencias), `src/config/moduleCatalog.js` (publicar id multibodega) y `src/views/partials/navigation.ejs` (texto contextual del modulo). Todo lo demas es nuevo y propio del Mod5: rango 80..89, cuatro scripts SQL preparados, factories/validacion, cinco vistas EJS, CSS/JS, prueba Node, check offline y esta documentacion.

Continuacion por revision cruzada: se ajustaron 81 (helper interno), 85 (orden de conversion y ponderado), 87 (DENY helper), 89 (verificacion de firma), fixtures/integraciones preparados, errores HTTP, textos/recibo EJS y pruebas/documentacion propias. No se editaron 34 ni los converters centrales. Definir una extension que actualizaria SOLO PrecioCosto tras aprobacion no equivale a ejecutar ese UPDATE ahora.

No se modificaron los procedimientos SQL compartidos, Full, seeds, configuracion de conexion, credenciales, archivos .env, rangos 70/90 ni otros worktrees. No se consulto el seed de seguridad con contrasenas como fuente de implementacion. Las pruebas generales existentes pueden leer sus propias fuentes como parte de sus verificaciones, sin exponer contenido sensible en la salida.
