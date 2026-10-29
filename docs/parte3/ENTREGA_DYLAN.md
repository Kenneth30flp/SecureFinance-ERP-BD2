# Entrega local de los tres modulos de Dylan

Responsable: Dylan Albrygth Caal Caal. Fecha: 2026-10-28 (actualizada por la sesion
de verificacion nocturna). Estado: codigo y SQL verificados contra el laboratorio
REAL SecureFinanceERP_Lab_Dylan en localhost, suites verdes, listos para commits
locales en las tres ramas. Sin push, sin merge, sin rebase, sin tocar main ni las
cinco bases protegidas.

## Aislamiento y referencias

Repositorio: Kenneth30flp/SecureFinance-ERP-BD2. Las tres ramas parten de
1bca099. En esta sesion se hizo `git fetch origin` (solo lectura) y se confirmo
que `origin/main` y `origin/integracion/parte3` avanzaron a 02d85b5: Kenneth
fusiono el Modulo 4 PROMOCIONES de Jose (#14, #15; 32 archivos). No hay commits
nuevos de Kenneth (ventas) ni de Edward (compras) en el remoto; sus bases de
codigo siguen en 1bca099.

| Modulo | Rama | Directorio hermano de trabajo |
| --- | --- | --- |
| 6 / DDL | feature/p3-dylan-auditoria-ddl | SecureFinance-ERP-BD2 |
| 3 / Creditos | feature/p3-dylan-creditos | SecureFinance-ERP-BD2-creditos |
| 5 / Multibodega | feature/p3-dylan-multibodega | SecureFinance-ERP-BD2-multibodega |

Cada modulo vive en su rama con sus propios cambios de composicion
(server.js, moduleCatalog, navigation, package.json). Ver "Conflictos con
companeros" hacia el final. No crear un unico PR que mezcle los tres.

## Laboratorio real (activo y verificado)

Servidor local: DESKTOP-HBNSH7J (SQL Server 2025). Base autorizada:
SecureFinanceERP_Lab_Dylan (online, ~56 objetos P3_CRE_, ~71 objetos P3_BOD_,
Bitacora_DDL con eventos reales). Protegidas: SecureFinanceERP,
SecureFinanceERP_Validation, FastLogixDB, FastLogixDB_Restaurada y bdFarmacia.

El laboratorio local usa certificado autofirmado: las conexiones de prueba
(sqlcmd y SqlClient) aplican Encrypt + TrustServerCertificate SOLO contra
localhost. Es una decision documentada de laboratorio local, no un cambio de
credenciales ni un blindaje de cliente contra servidores remotos.

Toda instalacion/lectura valida destino con
`DB_NAME() COLLATE Latin1_General_100_BIN2 <> N'SecureFinanceERP_Lab_Dylan'`
y, tras el endurecimiento de esta sesion, tambien `DATALENGTH(DB_NAME())`
contra `/lab/Dylan` (anti colision). Los replicados 82 y 89 exigen trasaccion
externa propia (archivo) o abren/cierran la suya (procedimiento).

## Modulo 6 / DDL

Implementado: Bitacora_DDL, captura exacta de comandos via EVENTDATA, escritor
WITHOUT LOGIN limitado, filtros, detalle escapado y paginacion. Migraciones
90 -> 94 con guardas de laboratorio y riesgo.

EVIDENCIA REAL EN EL LAB: el trigger de DDL capturo 12 eventos reales
(2 ALTER_PROCEDURE de Creditos y los del complemento BOD 89), todos con
EstadoComando EXACTO_EVENTDATA y ComandoTSql persistido solo en el detalle
autorizado. El QA leido consulta el listado y el detalle por BIGINT y el
nuevo chequeo "DDL bitacora real data responds and detail resolves" PASO:
la bitacora ya no se exige vacia (instalar 89 genero eventos reales: la
captura funciona, que era el objetivo del modulo).

Pruebas: tests/auditoria-ddl.test.js 19/19 PASS y la suite general 135/135
PASS del worktree principal. `npm run check:ddl` exit 0.

## Modulo 3 / Creditos

Implementado y ejecutado contra SQL real: cuentas, cuotas, abonos FIFO,
recibos de caja, autorizaciones version/UUID/motivo, sin sobrepago ni deuda
borrada. La extension 76_P3_CRE_Ventas_PROPUESTA.sql SIGUE PENDIENTE de
revision escrita de Kenneth: su runner applyReviewedPlan lo exige y no se
declara integrada.

Fix de accesibilidad verificado: contraste WCAG AA del encabezado y paneles
de /creditos corregido ajustando los tokens del bloque propio de
creditos.css (antes daban ratio ~1.08 sobre panel blanco; ahora usan los
tokens oscuros del shell ERP). El check "Credit panel headings meet WCAG AA
contrast" del QA con navegador real PASA en 1024/1366/768/390/320 px.

Pruebas: test:creditos 63/63 PASS, suite general 178/178 PASS,
`npm run check:creditos` exit 0. El test de contrato se actualizo al plan
vigorizado: 10 archivos 70-78 con guardas laboratorio + trasaccion externa y
`doesNotMatch` de USE.

EVIDENCIA HISTORICA (sesion previa, conservada): docs/parte3/creditos/
EVIDENCIA_SQL_79.txt (prueba sintetica 79 ejecutada en el lab).

## Modulo 5 / Multibodega

Implementado y ejecutado contra SQL real: bodegas, existencias, propuestas,
despacho, transito, recepcion, ledger local, conciliacion con Product.Stock.
84 (espejo Kardex) y 85 (integraciones, costo ponderado) SIGUEN PENDIENTES de
aprobacion escrita de Kenneth; no se declaran integrados.

DEFECTO REAL CORREGIDO ESTA SESION: CONVERT(VARCHAR(16), Version, 2) sobre
una columna rowversion entrega los 8 bytes crudos (no hex) en SQL Server 2025;
el campo Version de los recibos JSON (82 reenvio/avance y 83 bodega) salia
corrupto y el servicio (regex ^[0-9a-f]{16}$ en validation.js) no podia usarlo
para el bloqueo optimista. Fix en 82 (L26/L75) y 83 (L34):
CONVERT(VARCHAR(16), CAST(Version AS varbinary(8)), 2) -> 16 hex sin 0x.
Verificado en vivo: recibo {"...Version":"0000000000000A35"...}. Reinstalado
solo procs 82/83 con database/tests/P3_BOD_ReaplicarTransferencias.sql
(trasaccion externa, sin tocar tablas ni datos).

CONCURRENCIA REAL 4/4 PASS + conciliacion limpia (nueva evidencia):
database/tests/P3_BOD_Concurrencias.ps1, dos sesiones SqlClient reales con
applock exclusivo y UPDLOCK del Producto:
- C1 replay idempotente por mismo OperacionId+carga: B espera ~3.5s, recibe
  el recibo identico, 1 fila de Operacion y 1 de ledger. PASS.
- C2 mismo OperacionId con otra carga: rechazo 58003, sin fila extra. PASS.
- C3 doble recepcion con rowversion obsoleta: rechazo 58003, ledger=0,
  estado final RECIBIDA. PASS.
- C4 dos despachos compiten por el mismo origen: 58005, ledger=0, la otra
  transferencia queda PREPARADA. PASS.
- Conciliacion final: filasTotal=8, filasConDiferencia=0.
Detalle: docs/parte3/multibodega/EVIDENCIA_SQL_CONCURRENCIA.txt.
La advertencia "no se promete ausencia universal de deadlocks sin pruebas
concurrentes reales" se resuelve parcialmente: los 4 casos de la matriz
real pasaron; sigue sin garantizarse deadlocks arbitrarios de carga mixta.

Pruebas: tests/multibodega.test.js 26/26 PASS (contrato actualizado a los
11 SQL propios 80-89 y 11 :r del instalador), suite general 141/141 PASS,
`node scripts/checkMultibodega.js` exit 0. El guard de 89 agrego el chequeo
DATALENGTH y el complemento reaplico con PASS ("catalogo completo, versiones
y filtros SKU/estado").

EVIDENCIA HISTORICA (sesion previa, conservada): EVIDENCIA_SQL_BOD.txt
(suites reales de transferencias/integraciones P3_BOD_RunTests.sql).

## QA leido unico que cubre los tres modulos (REAL, 52/52)

scripts/dylanReadonlyQa.js + dylanReadonlyRpc.ps1: procedimientos de lectura
allowlisteados, browser Chrome real con DOM/CDP, screenshots de rutas
privacidad-seguras (filtros vacios de DDL/Creditos, producto sintetico
P3BOD-QA-100). Ejecutado esta sesion: 52/52 PASS, evidencia en
docs/dylan-readonly-qa-20261028/ (results.json + 20 capturas). Incluye:
HTTP 200 de las 5 secciones de cada modulo, permisos por actor sintetico,
rechazo de actor 0/CSRF faltante, recibo real, detalle de transferencia y
contraste AA. NOTA de trazabilidad: el results.json anterior (51/52 por el
fallo de contraste) fue sobrescrito por la corrida verde; no queda copia
del anterior, el fallo historico esta descrito en el commit del fix.

QA cruzado MOCK (separado, 4 PASS): scripts/dylanIntegration.test.js.

## Campos de la integracion no cubiertos por modulos

Los reportes legacy de ventas y auditoria no fueron modificados. Las
integraciones de 84/85 siguen gated por Kenneth (84 espejo Kardex, 85
ponderado de compras con costo documental de 34). Jose ya integro 63 en el
remoto; la integracion con promociones queda fuera del alcance de estas
tres ramas y sera del integrador.

## Conflictos con companeros (analisis solo lectura, sin merge)

Remoto analizado: 02d85b5. Jose toco 32 archivos; Dylan toca otros
distintos en database y views, PERO comparte archivos de composicion:

| Archivo compartido | Jose (02d85b5) | Dylan DDL | Dylan Cred | Dylan BOD |
| --- | --- | --- | --- | --- |
| server.js | modificado (monta promociones) | modificado | modificado | modificado |
| src/config/moduleCatalog.js | modificado | modificado | modificado | modificado |
| src/views/partials/navigation.ejs | modificado | modificado | modificado | modificado |
| package.json | modificado (nueva test) | modificado | SIN CAMBIO propio* | SIN CAMBIO propio* |
| docs/parte3/CONTRATOS_INTEGRACION.md | modificado | sin cambio | modificado | sin cambio |

*El package.json de creditos/multibodega sin diff local no entra en conflicto;
solo los archivos con cambio propio en ambas partes son riesgo de merge real.

Kenneth y Edward no tienen commits nuevos en el remoto; su riesgo es fututo
en los mismos archivos de composicion y en 34/43 (solo PROPUESTA en 76/85,
nunca reemplazo). El analisis detallado por rama (three-way contra 02d85b5)
se registra en el informe final de la sesion, sin ejecutar merge.

## Matriz honesta de cierre

| Clasificacion | Alcance |
| --- | --- |
| Ejecutado contra SQL real del lab | QA leido 52/52, DDL captura 12 eventos, transferencias fijadas por RunTests historico, concurrencia 4/4 + conciliacion, complemento 89 y procs 82/83 reinstalados |
| Pruebas verdes locales | DDL 19 + 135; Creditos 63 + 178; BOD 26 + 141; cross mock 4; checks exit 0 |
| Pendiente aprobacion | 76 (Kenneth, revision escrita), 84 y 85 (Kenneth), demos academicas del ingeniero |
| Bloqueado | Integracion definitiva (requiere las otras ramas/PRs), ensayo de rollback completo, instalacion reproducible sin el prototipo local |
| No hecho (intencional) | push/merge/PR, cambios a otros modulos, bases protegidas, historial reescrito |

## Pasos para el PR explicados en la explicacion de abajo

Los commits quedan en tres ramas locales. El integrador debe revisar los
diffs por rama, resolver la composicion contra 02d85b5 y abrir tres PR
independientes hacia integracion/parte3 despues de las aprobaciones.

## Explicacion breve para Dylan (para exponer ante el ingeniero)

Mi entrega tiene tres modulos independientes y todos tienen evidencia REAL,
no imaginaria.

1) AUDITORIA DDL: "quien cambio la estructura y con que comando". La base
registra cada CREATE/ALTER/DROP por evento, con Escaped XML de EVENTDATA y
un escritor sin login propio. En el laboratorio ya capturo 12 eventos
reales; la vista publica no muestra el SQL, solo metadatos; el detalle exacto
requiere permiso especial y actor autorizado. Demo: cambio una tabla, la
bitacora la registra, y un actor sin permiso no ve el comando.

2) CREDITOS Y CUENTAS POR COBRAR: "convierte una venta en deuda con plan".
Una factura acredita saldo, cuotas y perfil de financiacion; los abonos
entran FIFO y nunca se paga mas de lo que se debe; el recibo de caja une
movimientos y recibos sin sumar deuda como efectivo. Toda operacion exige
autorizacion, UUID de operacion y version para que un reintento no duplique.
Demo: venta 2000 acredita cuotas, abono 500 baja el saldo, reintento del
abono no duplica entrada.

3) MULTIBODEGA Y TRANSFERENCIAS: "mueve unidades entre ubicaciones". Despachar
descuenta del origen y deja en transito; recibir incrementa destino; el total
del negocio nunca cambia. Cada fase se bloquea con applock y version de fila;
si dos cajas compiten, uno gana y el otro recibe un rechazo claro, y el
inventario concilia siempre (diferencia 0 probada en el lab). Demo: transferir
10 unidades: 100 -> 95+5 en transito -> 95+0 en destino cuando llega -> 100.

Las tres cosas comparten reglas que puedo nombrar sin leer: lab de prueba
por nombre exacto, separacion de permisos por actor, paginacion reales,
contraste AA en la UI, CSRF por modulo y nigun calculo de dinero en
JavaScript.

## Veredicto actual

Los tres modulos estan listos para revision por el integrador y PR — con evidencia
real ejecutada en el laboratorio confirmado — pero NO listos para fusionar a main:
76/84/85 siguen gated, la composicion debe integrarse contra 02d85b5 resolvendo
los archivos compartidos arriba, y las demos del ingeniero quedan por agendar.
