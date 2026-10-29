# Modulo 3: Creditos y Cuentas por Cobrar

Entrega exclusiva del worktree `SecureFinance-ERP-BD2-creditos`, rama
`feature/p3-dylan-creditos`, base `1bca0992ad94d154cc19bb4fab44e15ffa611dbf`.
No implementa los otros cinco modulos ni modifica sus worktrees. No se dispone
del PDF academico P3 ni del prompt maestro de Kenneth: el alcance procede de
los requisitos explicitos del usuario y del contrato comun versionado.

## Estado Real

Codigo SQL, Express/EJS, pruebas aisladas y documentacion preparados.
**SQL REAL NO EJECUTADO, NI COMPILACION SQL VERIFICADA.** No hubo conexiones,
migraciones, cambios de TLS, credenciales, commits, push, merge o rebase.
El bloqueo comunicado es cadena de certificado no confiable en localhost;
no se intento eludirlo. No se utiliza el seed 04 ni se reproducen credenciales
en los archivos de esta entrega.

**76 es PROPOSED, pendiente de revision escrita de Kenneth antes de integrar
o ejecutar.** No es una autorizacion externa ni un despliegue completado.
Ver [contrato compartido propuesto](PROPUESTA_INTEGRACION.md).

## Archivos

| Archivo | Responsabilidad |
| --- | --- |
| `database/70_P3_CRE_Estructura.sql` | Tablas, guardia de entorno, historial/auditoria interna |
| `71_P3_CRE_Perfiles.sql` | Alta, edicion y desactivacion logica con version/UUID/motivo |
| `72_P3_CRE_Financiacion.sql` | Bloqueo de credito, disponible derivado, cuenta y cuotas |
| `73_P3_CRE_Abonos.sql` | Abono, FIFO, recibo, idempotencia y auditoria atomicos |
| `74_P3_CRE_Consultas.sql` | Estados derivados, cartera, estado de cuenta, recibos y caja unificada propia |
| `75_P3_CRE_Seguridad.sql` | RBAC inicial, privilegios SQL e inmutabilidad |
| `76_P3_CRE_Ventas_PROPUESTA.sql` | Extension compatible propuesta de los tres procedimientos de 43 |
| `77_P3_CRE_ConversionPublica.sql` | Fachada publica de credito/cotizacion y contexto BOD |
| `78_P3_CRE_Verificacion.sql` | Verificacion posterior de conciliacion, solo lectura |
| `79_P3_CRE_PruebasSinteticas.sql` | Escenarios SQL sinteticos preparados; rollback por escenario |
| `src/modules/creditos/{validation,service,routes}.js` | Validacion, RPC tipado, rutas inyectables |
| `src/views/creditos/{head,index,receipt,cash}.ejs` | Cartera, perfil, cuotas, conversion, recibo y caja propia |
| `src/public/{css/creditos.css,js/creditos.js}` | Estilo local responsive y envios recuperables |
| `scripts/creditosMigrationPlan.js` | Plan y ejecutor sin conexion propia, solo transaccion externa inyectada |
| `tests/creditos*.test.js` | HTTP/pool mocks, validacion, contratos fuente y navegador VM |

Se mantienen intactos `43`, `39`, `21`, el TVP, Kardex, Full, la configuracion
de conexion y los servicios/rutas de ventas y cotizaciones. Los cambios
compartidos de aplicacion se limitan a `server.js` (inyeccion, montaje y
resolucion del asset Bootstrap instalado via NODE_PATH, sin copiarlo),
`moduleCatalog.js` (entrada real con permiso), `navigation.ejs` (titulo del
modulo) y `package.json` (dos comandos propios).

## Uso Web

`GET /creditos` consulta facturas a credito. Filtros `clienteId`, `facturaId`,
`estado`, `desde`, `hasta`, `pagina`. Paginas de 20 con fila de adelanto;
limite de pagina 100001. Las fechas usan `operationalDates.localDayBoundary`,
Guatemala UTC-6 e intervalo UTC `[Desde,Hasta)`. No hay escrituras persistentes
en GET; caja materializa solo una variable de tabla para resumen y pagina.

Consultar un Cliente ID carga perfil, limite, deuda y disponible. Con permiso
administrativo permite crear el perfil (version vacia), actualizarlo o
desactivarlo (version vigente). No se ofrece DELETE: la baja es logica y
conserva deuda, recibos e historia. Los perfiles inactivos todavia pueden
recibir abonos; no pueden originar nuevas ventas financiadas.

Consultar Factura ID muestra cuotas y sus vencimientos. El formulario de
abono recibe Cliente ID y Factura ID; SQL valida pertenencia. El formulario de
conversion recibe Cotizacion ID y condiciones, **nunca precios web**.
El enlace de consulta de cotizaciones existente permanece de contado; la
conversion financiada vive en este modulo para no alterar la UI de Kenneth.

| Ruta | Permisos HTTP y SQL |
| --- | --- |
| `GET /creditos` | `CREDITOS_CONSULTAR` |
| `GET /creditos/caja` | `CREDITOS_CONSULTAR` |
| `GET /creditos/recibos/:AbonoId` | `CREDITOS_CONSULTAR` |
| `POST /creditos/perfil` | `CREDITOS_ADMINISTRAR` |
| `POST /creditos/abonos` | `CREDITOS_ABONAR` |
| `POST /creditos/conversiones` | `CREDITOS_FACTURAR`, `COTIZACIONES_CONVERTIR`, `VENTAS_REGISTRAR` |

Actor exclusivamente `req.session.usuario.usuarioId`. RBAC HTTP no sustituye
`sp_ParteII_ValidarPermiso` vigente en cada procedimiento publico SQL. CSRF
propio `creditosCsrf`, comparacion constante y token de cabecera o formulario;
no se deshabilita ni sustituye el CSRF de otros modulos. Errores SQL se
traducen por codigos fijos y nunca se envian mensajes internos al navegador.
SQL no disponible o respuesta incompatible devuelve 503, no datos ficticios.

Asignacion inicial en 75: Administrador recibe los cuatro permisos; Auditor
solo CONSULTAR; Cajero CONSULTAR y ABONAR, **no ADMINISTRAR ni FACTURAR**.
La migracion no retira asignaciones personalizadas previamente existentes.
Recargar sesion despues de la asignacion para actualizar permisos HTTP.

UUID estable por formulario y sesion hasta respuesta confirmada. El navegador
conserva payload/UUID en sessionStorage antes del POST, bloquea doble clic y
congela campos ante incertidumbre. Un rechazo posterior no borra un envio
previamente incierto. Un resultado confirmado habilita consultar el documento;
el servidor solo entonces prepara otro UUID. No hay reenvio automatico. No
cerrar la pestaña/sesion ni limpiar almacenamiento con un envio incierto:
sessionStorage no es una cola durable entre dispositivos. En ese caso se debe
recuperar el UUID desde la historia, no inventar otra referencia.

## Precision y Reglas

Importes de entrada exclusivamente cadenas decimales positivas con hasta 17
digitos enteros y dos decimales; no exponente, coma, signo, espacios, arrays o
floats. Normalizacion textual a dos decimales, sin calculos financieros JS.
RPC usa `sql.NVarChar(21)` para `Monto`/`Limite` y SQL los convierte al
parametro formal `DECIMAL(19,2)`. Esto evita que `mssql`/Tedious convierta
un Decimal de entrada a Number y pierda precision. Salidas SQL monetarias
son VARCHAR y los BIGINT se devuelven como cadenas canonicas, no Number.

Disponible = limite menos SUM de saldo de cuentas, nunca una columna mutable.
El perfil se bloquea `UPDLOCK,HOLDLOCK` antes de productos/factura en credito,
y antes de factura al abonar. SUM de deuda permanece en DECIMAL(38,2) y se
compara primero contra el limite. Solo despues de acreditar que cabe se
convierte a DECIMAL(19,2) para comparar `Total <= Limite - Deuda`; evita tanto
overflow al reducir una suma anomala como perder centavos sumando DECIMAL(38,2).
El total definitivo de la venta se valida antes de insertar factura.

Plazo 1..3650 dias, dentro del autorizado. Cuotas 1..120 y no mayores al
plazo; cada cuota debe tener al menos un centavo. Base de cuota truncada a
centavos y resto en la ultima. Vencimiento i = emision UTC mas
`CEILING(plazo*i/numeroCuotas)` dias. Sin intereses ni comisiones implicitos.
FIFO por vencimiento y numero. Estados se consultan con SYSUTCDATETIME:
PAGADA si saldo cero, VENCIDA si hay saldo y vencio, PARCIAL si hay abono,
PENDIENTE en otro caso. La factura vence si alguna cuota impaga vencio,
no solo al llegar el vencimiento final. No hay estado VENCIDA persistido que
dependa de un job para actualizarse.

Abono positivo <= saldo, con app lock transaccional por UUID, SHA-256 del
actor/cliente/factura/monto/referencia y comparacion antes de modificar deuda.
Reintento identico devuelve el mismo recibo y saldo posterior historico, aun
si existen abonos posteriores. Carga diferente con el mismo UUID se rechaza.
Cuenta, cuotas, aplicaciones, abono, recibo y dos libros de auditoria cambian
en una sola transaccion. Abonos, recibos, aplicaciones, operaciones de perfil
e historial tienen triggers de inmutabilidad y DML denegado al login web.
No se ofrecen anulaciones de pago: se requiere contrato separado, no borrar
o editar el recibo. Las nuevas notas de credito de posventa tampoco se
consumen automaticamente como abonos; son dominios diferentes.

## Caja Propia Unificada

`MovimientoCaja.FacturaId` es UNIQUE y solo acepta INGRESO. Por eso una venta
financiada **no inserta** caja de contado, y cada abono inserta un unico
`P3_CRE_ReciboCaja` ligado por UNIQUE a `Abono_Factura`. No se borran,
revierten o reciclan movimientos anteriores.

**Los reportes y dashboards legacy NO se modificaron.** Ahora existe una
consulta propia de Creditos, preparada en 74 y no ejecutada en SQL:

```sql
dbo.P3_CRE_ConsultarCaja
 @ActorUsuarioId INT, @Desde DATETIME2(3)=NULL,
 @Hasta DATETIME2(3)=NULL, @Desplazamiento INT=0
```

Exige CREDITOS_CONSULTAR vigente en SQL. UNION ALL de MovimientoCaja como
CONTADO y P3_CRE_ReciboCaja como ABONO, unido a Abono_Factura solo para sus
identificadores. Nunca suma Factura.Total, deuda o Abono_Factura otra vez.
Primer recordset: EfectivoContado, EfectivoAbonos, EfectivoTotal, todos strings
VARCHAR(40) desde SUM DECIMAL(38,2); el total global puede superar el maximo de
una factura DECIMAL(19,2). Segundo: Origen, DocumentoId string, FacturaId,
AbonoId string/null, FechaHora y Monto string; paginas 20+1. Fecha de cobro con
limites `[Desde,Hasta)`. Se materializa una lectura en variable de tabla para
que resumen y pagina usen el mismo conjunto, sin DML persistente, grants
SELECT a tablas ni aislamiento nuevo impuesto a informes ajenos.

`GET /creditos/caja` muestra resumen y movimientos. El dashboard de Creditos
muestra su indicador **efectivo recibido por abonos**, calculado por SQL para
todos los clientes y el rango de fechas de cobro. No usa saldo de facturas ni
suma los 20 recibos visibles. Los filtros cliente/factura/estado de cartera
no afectan este indicador y la UI lo indica expresamente. Si falta el proc o
el contrato de resultado es incompatible responde 503, nunca un cero ficticio.

Los dashboards de caja antiguos seguiran omitiendo estos cobros hasta una
integracion separada autorizada. Esta entrega no afirma que esos informes ya
consuman la union. Ventas contables e ingresos de caja siguen siendo metricas
diferentes.

## Instalacion Controlada

**No ejecutar ahora.** Requiere resolver confianza TLS mediante un certificado
valido y aprobacion escrita de Kenneth para 76; nunca desactivar cifrado ni
activar trustServerCertificate como atajo. No hay nuevo instalador de
conexion ni .env en esta entrega.

1. DBA identifica una copia aislada llamada exactamente
   `SecureFinanceERP_Lab_Dylan`, nunca la principal, con respaldo recuperable
   y restauracion ensayada. Revisar que no tenga trafico de usuarios.
2. Verificar Parte II hasta 40, 41-43 vigentes, esquema 39/snapshots, usuario
   securefinance_app, permisos de actor y auditoria DML activa. 44 no es
   dependencia de Creditos. Comparar las tres definiciones actuales con 43;
   reconciliar cualquier cambio paralelo antes de 76. No sobrescribirlo.
3. Deshabilitar escritores externos durante instalacion. Usar una sola
   conexion/transaccion DBA ya abierta, committable (`@@TRANCOUNT=1`). Ejecutar
   secuencialmente 70,71,72,73,74,75,76,77; cada GO conserva esa transaccion.
   `applyReviewedPlan(transaction,{kennethReviewApproved:true})` es un helper
   **sin conexion propia**, sin CLI, sin commit y bloqueado por defecto.
   Verifica DB exacta/transaccion antes de CADA batch; ante el primer error
   aborta el bucle y solicita rollback completo. Esta opcion explicita es un
   resguardo operativo, no prueba automatica de aprobacion humana.
4. No pegar los scripts en un editor que continue tras THROW: las definiciones
   CREATE requieren primer statement de batch, por eso el ejecutor constituye
   parte obligatoria de la guardia. No ejecutar batches aislados despues de
   un fallo, ni usar una conexion/transaccion distinta entre GO.
5. Antes de commit, ejecutar 78 en esa misma transaccion, inspeccionar firmas,
   permisos efectivos y triggers. El llamador decide commit expresamente.
   Cualquier error requiere rollback de toda la instalacion, no continuar.
6. 70 es de una sola instalacion: si existe Credito_Cliente aborta sin borrar
   datos. Los CREATE OR ALTER posteriores no autorizan reinstalacion ciega.
   Si hubo fallo antes de commit, el rollback elimina tambien DDL/grants y
   recupera las definiciones previas. Si ya hubo commit, recuperar el respaldo
   en una copia y ensayar reconciliacion; no hay down destructivo automatico.
7. Solo despues, en laboratorio preparado con apertura Kardex aprobada,
   ejecutar 79 por separado, sin transaccion externa. Cada escenario abre su
   propia transaccion y revierte todos sus fixtures. Usa actor Administrador
   existente, no passwords ni datos reales. No instala/habilita inventario.
   Una secuencia identity puede dejar huecos tras rollback: es normal.

Los procedimientos propios tambien comprueban el nombre exacto de base en
runtime. No ampliar la guardia a un patron LIKE para probar en otra base;
cualquier habilitacion futura fuera del laboratorio requiere otro cambio
revisado, no esta propuesta.

## Verificacion y Limites

Comandos sin SQL (NODE_PATH apunta a dependencias ya disponibles, sin install):

```powershell
$env:NODE_PATH='D:\Universidad 2026\Semestre 2\BASE DE DATOS II\Proyecto de Laboratorio\SecureFinanceERP Proyecto en grupo\SecureFinance-ERP-BD2\node_modules'
$env:TEMP='C:\Users\ALBRYGTH\AppData\Local\Temp\opencode'
$env:TMP=$env:TEMP
npm.cmd run check
npm.cmd run check:creditos
npm.cmd run test:creditos
npm.cmd test
git diff --check
```

Resultados y alcance: ver [VALIDACION.md](VALIDACION.md). Los tests Node
comprueban validacion, parametrizacion, actor, CSRF, RBAC, escape EJS,
precision textual, referencias estables y contratos fuente. Las respuestas
SQL se simulan: **no prueban saldos, bloqueo, FIFO ni atomicidad SQL reales**.

79 prepara la secuencia 5000 -> venta 2000 -> abono 500 -> saldo 1500 -> abono
1500 -> saldo 0/disponible 5000, reintentos sin duplicados y rechazos por
sobrepago, cero, negativo, otra factura/cliente, UUID divergente, cupo,
cancelacion, vencimiento, version, inmutabilidad, terminos y falta de stock.
79 tiene 24 escenarios preparados, no ejecutados. Incluye perfil/cliente
inactivos, cobro y replay posterior a inactivacion, limite menor que deuda,
plazo no autorizado, contexto BOD ajeno conservado, credito de total cero
rechazado y contado de total cero compatible con 43. Los clientes y productos
son fixtures sinteticos; cotizacion y factura se crean por P3_COT_Crear y
conversores reales, nunca insertando Factura/DetalleFactura/Cuenta a mano.
Ver [revision y matriz](REVISION_COMPATIBILIDAD.md).

Pendientes SQL reales: concurrencia en dos
sesiones (ventas del mismo cliente y UUID de abono iguales/distintos), fallo
inducido de trigger/recibo, colision credito/contado y reproduccion UC09 de
contado antes/despues de 76. Ejecutar tambien los casos preparados de
inactividad, centavos extremos, vencimientos y permisos bajo el login
web efectivo. No se declara cobertura de estos casos sin evidencia SQL.

La CSS es responsive local y usa el shell existente. Se renderizo EJS mediante
HTTP fixture y se probo JS en VM, pero no se ejecuto navegador visual real,
impresion real ni SQL con usuarios reales. Falta revision de accesibilidad
visual en movil/desktop y evidencia academica. Multibodega solo tiene contrato
de enlace opcional: no se afirma que el modulo BOD este instalado o probado.
