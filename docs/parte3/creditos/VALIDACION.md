# Evidencia de Validacion

Fecha: 2026-10-28. Entorno: Node 25.8.1, Windows, worktree de Creditos sobre
`1bca099`, dependencias existentes via NODE_PATH. No install, SQL ni servidor
publico. Los fixtures HTTP escuchan temporalmente solo en `127.0.0.1` y se
cierran al terminar. No se modifican credenciales o configuracion TLS.

## Ejecutado

| Comando | Resultado |
| --- | --- |
| `npm.cmd run check` | PASS, sintaxis de la suite existente |
| `npm.cmd run check:creditos` | PASS, sintaxis de los ocho archivos JS propios de modulo/ejecutor/tests |
| `npm.cmd run test:creditos` | Revision: 63 PASS, 0 FAIL, 0 omitidas |
| `npm.cmd test` | Revision: 178 PASS, 0 FAIL, 0 omitidas |
| `git diff --check` | PASS; advertencias LF/CRLF de Git, no errores de whitespace |

Las pruebas HTTP pasan por `createApp`, autenticacion fixture y servicio real
de creditos con pool inyectado simulado. Se inspeccionan los parametros SQL,
no solo mocks de un controlador. No se abre ningun pool real. El login es una
respuesta fixture, no un usuario/password creado en SQL.

Tests de navegador son VM con DOM/fetch/storage simulados. Prueban doble clic,
referencia recuperada tras red caida, bloqueo de campos, 503 y almacenamiento
no disponible. Un rechazo posterior de CSRF/permisos no resuelve un envio
previamente incierto. No son evidencia de screenshot, layout ni navegador real.
Las peticiones HTTP verifican tambien 200 para CSS/JS propios, estilos del
shell y Bootstrap resuelto desde las dependencias de NODE_PATH.

Los tests de contrato inspeccionan texto SQL: guardias, expresiones historicas
de hash, motor unico, firma BOD y orden declarado de bloqueos. Ahora comparan
todos los tokens de los tres procedimientos default de 76 proyectados a
contado con 43, incluyendo tipos, recordsets, snapshots, politica, contextos
y cierre UC09. La proyeccion elimina solo los sitios nuevos de financiacion;
no es un interprete SQL ni acredita ejecucion de los caminos de credito.
No ejecutan ni compilan SQL. El ejecutor de migraciones se prueba con transaccion simulada:
base principal rechazada, revisiones requeridas, cada GO revalidado, primer
fallo interrumpe todos los batches y rollback solicitado, nunca auto commit.

Caja propia: HTTP real con pool simulado verifica GET /creditos/caja, permiso,
actor de sesion, fechas exclusivas de Guatemala, paginacion, discriminadores,
identificadores y montos string. Prueba cero verdadero, SUM superior al rango
de una factura y 503 cuando falta contrato o el resultado es incompatible,
sin presentar deuda de Factura como efectivo. Ningun informe legacy se edito.
El contexto ajeno y los bloqueos SQL solo se verifican en fuente y en script
preparado: su comportamiento real bajo SQL todavia no esta acreditado.

## No Ejecutado

Migraciones 70-77, verificacion SQL 78, escenarios sinteticos 79 y ningun
procedimiento de negocio real. Tampoco concurrencia SQL, permisos bajo login
SQL efectivo, planes/locks, TLS corregido, integracion real BOD, reportes de
caja, aprobacion de Kenneth, recuperacion desde backup o navegador visual.
La aplicacion desplegada no se declara operativa contra SQL hasta completar
esas verificaciones en el laboratorio exacto.

## Cierre

Se repitieron los chequeos y suites despues de las correcciones de reintentos
y contratos de respuesta. No interpretar los 24 escenarios SQL sinteticos
preparados como pruebas ejecutadas. Esta entrega cubre codigo de Mod3, no los
seis modulos ni el 100% del proyecto academico.

Revision detallada y matriz de permisos/replay/inactividad:
[REVISION_COMPATIBILIDAD.md](REVISION_COMPATIBILIDAD.md).

## ADICION 2026-10-29: Concurrencia REAL de abonos ejecutada EN EL LAB (3/3 PASS)

Se ejecuto `database/tests/P3_CRE_Concurrencias.ps1` (ADO.NET, DOS sesiones
SqlClient simultaneas contra `SecureFinanceERP_Lab_Dylan`, actor sintetico
`P3_DYLAN_QA_ADMIN` con CREDITOS_ABONAR/FACTURAR/ADMINISTRAR verificados).
La cuenta por cobrar nace EXCLUSIVAMENTE del motor compartido:
`P3_COT_Crear` -> `P3_CRE_ConvertirCotizacionCredito` (extension 76 instalada
en lab); NUNCA se inserta Factura directamente. Fixture persistente sin
rollback final: Cliente 32, Producto 36 (stock solo via Kardex), COT 40
(total 2000.00), Factura 25, 2 cuotas x 1000.00.

- C1 replay del mismo OperacionId con los mismos datos en ambas sesiones: 1 abono, 1 recibo, saldo 1700.00 (descuentado exactamente una vez). PASS.
- C2 mismo OperacionId con otra carga (monto 300.01): rechazo 57003 'Referencia de abono reutilizada con otros datos.', saldo invariante. PASS.
- C3 dos OperacionId distintos compiten por el mismo saldo (1000+1000 sobre 1700, arranque asincronico 50 ms): exactamente uno confirma, el otro 57006 'El abono excede el saldo pendiente.'; saldo final 700.00 == conciliacion de cuotas (SUM Importe-Abonado), 2 abonos totales. Los intentos rechazados no dejaron filas (rollback atomico). PASS.

Evidencia con numeros exactos: `docs/parte3/creditos/EVIDENCIA_SQL_CRE_CONCURRENCIA.txt`
(JSON crudo en `%TEMP%\opencode\P3_CRE_Concurrencias.json`). No se modifico
`sp_RegistrarAbonoCliente`, el schema P3_CRE_* ni el engine 43; el defecto
detectado durante la corrida fue del PROPIO script de prueba (pasaje de monto
posicional `[decimal]` en argument mode de PowerShell 5.1), corregido en el
script, no en el SQL del modulo. La extension 76 SIGUE PROPOSED pendiente de
revision escrita de Kenneth.
