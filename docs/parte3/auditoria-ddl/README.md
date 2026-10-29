# Modulo 6: Auditoria DDL

**Estado actual:** requisito de texto exacto confirmado por Dylan y riesgo
aceptado exclusivamente para laboratorio sin secretos reales. Se agregaron
93-94, captura EVENTDATA y detalle de comandos escapados. Ningun SQL se ejecuto.
La guia vigente es [CAPTURA_Y_LABORATORIO.md](CAPTURA_Y_LABORATORIO.md).

**El contenido siguiente conserva el historial de la primera entrega parcial.**
Sus referencias a politica pendiente, ausencia de trigger y 132 pruebas describen
esa version anterior, no la ampliacion actual. No aplicar 90 sobre la politica
93 ya instalada: seguir el orden y modos de la guia vigente.

## Historial de la primera entrega

Responsable: Dylan Albrygth Caal Caal. Rama: `feature/p3-dylan-auditoria-ddl`.
Base inspeccionada: `1bca099`. Fecha de verificaciones: 2026-10-28.

## Estado de la entrega

Implementacion parcial autorizada: estructura SQL preparada, consultas,
permisos, backend, vistas y pruebas aisladas. **Ninguna migracion se ha
ejecutado. No existe captura automatica instalada por esta entrega.**

La politica de conservacion del comando original sigue pendiente de la
rubrica. No se considera aprobada ni se intenta sustituirla por una regex.
`ComandoTSql` debe ser NULL por un CHECK confiable; `EstadoComando` solo admite
`PENDIENTE_RUBRICA`. El servicio rechaza respuestas con texto SQL no nulo y
las vistas no lo representan. No se guarda XML original ni datos de ejemplo.
Una futura politica exigira otra migracion aprobada; no editar la 90 aplicada.

## Arquitectura

`GET /auditoria/ddl` -> autenticacion/RBAC -> controlador -> servicio ->
`dbo.P3_DDL_ConsultarBitacora` -> `dbo.Bitacora_DDL`.

`GET /auditoria/ddl/:id` utiliza `dbo.P3_DDL_ConsultarDetalle`.

Los dos procedimientos llaman a `sp_ParteII_ValidarPermiso` antes de leer
eventos. El actor procede de la sesion, nunca del navegador. La comprobacion
de sesion no sustituye la autorizacion SQL vigente. No hay rutas de escritura,
ejecucion SQL, borrado o desactivacion de triggers. Respuestas con `no-store`.

Se reutilizan pool SQL, middleware de autenticacion, fechas operativas y
navegacion. La consulta DDL es independiente: no modifica el controlador,
servicio o `Promise.all` de auditoria DML/accesos. Tampoco modifica el preflight
global de arranque ni convierte el nuevo modulo en una dependencia de ventas.

## Archivos nuevos

| Archivo | Funcion |
| --- | --- |
| `database/90_P3_DDL_Estructura.sql` | Tabla, CHECK, indice y validacion de compatibilidad |
| `database/91_P3_DDL_Consultas.sql` | Listado y detalle parametrizados |
| `database/92_P3_DDL_Permisos.sql` | Permiso ERP y privilegios SQL minimos |
| `src/services/auditoriaDdlService.js` | Pool inyectable y contrato estricto de respuesta |
| `src/controllers/auditoriaDdlController.js` | Filtros, IDs exactos y errores seguros |
| `src/routes/auditoriaDdlRoutes.js` | Dos GET protegidos |
| `src/views/auditoria-ddl.ejs` | Filtros, registros y paginacion |
| `src/views/auditoria-ddl-detalle.ejs` | Metadatos del evento y politica pendiente |
| `src/views/partials/auditoria-ddl-head.ejs` | Encabezado compartido y advertencia de alcance |
| `src/public/css/auditoria-ddl.css` | Estilos locales responsive |
| `tests/auditoria-ddl.test.js` | Pruebas con dobles SQL, HTTP y analisis textual |
| `docs/parte3/auditoria-ddl/README.md` | Instalacion, diseno pendiente y evidencias |

## Archivos compartidos modificados

| Archivo | Cambio limitado |
| --- | --- |
| `server.js` | Inyeccion y montaje del router DDL |
| `src/config/moduleCatalog.js` | Entrada real en Administracion con permiso propio |
| `src/views/partials/navigation.ejs` | Etiqueta contextual del nuevo modulo |
| `package.json` | Scripts adicionales `check:ddl` y `test:ddl` |
| `tests/moduleCatalog.test.js` | Visibilidad independiente de auditoria DML |

Sin cambios a lockfile, .env, credenciales, Full, SQL historico, Facturacion,
Kardex, Posventa, Analitica, Cotizaciones, Creditos o Multibodega.

## Tabla preparada

`dbo.Bitacora_DDL`: `BitacoraDdlId` BIGINT IDENTITY, `FechaHora` DATETIME2(3)
UTC, `TipoEvento`, `NombreObjeto`, `TipoObjeto`, `Esquema`, `UsuarioSQL`,
`LoginOriginal`, `EquipoOrigen`, `AplicacionOrigen`, `BaseDatos`, `SesionId`,
`ComandoTSql` NULL y `EstadoComando`.

Se reservan seis eventos: CREATE/ALTER/DROP de TABLE y PROCEDURE. Esto limita
la estructura, pero **no demuestra captura**. Host y aplicacion son contexto,
no prueba de identidad. No existe FK hacia un objeto que pueda eliminarse.

Las restricciones e indice usan prefijo `P3_DDL_`. La excepcion al prefijo
es el nombre academico solicitado `dbo.Bitacora_DDL`.

## Contratos de consulta

`dbo.P3_DDL_ConsultarBitacora`:

- `@ActorUsuarioId INT`, autenticado por el backend.
- `@Desde`, `@Hasta DATETIME2(3)`; limite superior exclusivo.
- `@Usuario`, `@Objeto NVARCHAR(128)`; substring literal con CHARINDEX.
- `@Evento NVARCHAR(40)`; uno de los seis valores o NULL.
- `@CorteId BIGINT`, NULL inicia un corte; 0 conserva un conjunto vacio.
- `@Desplazamiento INT`, `@Limite INT`; web utiliza 20 filas por pagina.
- Primer recordset: metadatos sin comando. Segundo: una fila `TotalFilas`, `CorteId`.

`dbo.P3_DDL_ConsultarDetalle`: actor e identificador; cero o una fila.
Los IDs y conteos se devuelven como VARCHAR(20), nunca como Number inseguro.
La frontera del driver BigInt se verifica sin conexion mediante su codec.

Orden: `FechaHora DESC, BitacoraDdlId DESC`. La web conserva filtros y corte
entre paginas. El corte limita nuevas identidades pero **no es un snapshot
transaccional**: una identidad reservada antes del corte y confirmada despues
puede cambiar el conjunto. No se promete consistencia de snapshot ni se usa
NOLOCK. Las fechas visibles son Guatemala y las almacenadas son UTC.

Errores: 400 filtros invalidos, 403 permiso ausente/revocado, 404 evento ausente,
503 instalacion incompleta o error tecnico. No exponer mensajes SQL internos.

## Permisos

`AUDITORIA_DDL_CONSULTAR` se asigna explicitamente a Administrador y Auditor
activos. No se hereda del permiso general de auditoria. Un permiso existente
inactivo o asignado a otros roles requiere revision, no se corrige a escondidas.
Despues de instalar, iniciar una nueva sesion para cargar el permiso del menu.

`securefinance_app` debe existir. Solo recibe EXECUTE de los dos procedimientos;
se deniegan SELECT/INSERT/UPDATE/DELETE directos sobre la tabla. No se crean
logins ni se conceden db_owner o privilegios DDL. La migracion rechaza varias
configuraciones privilegiadas, pero la revision DBA de permisos efectivos,
grupos, impersonacion y propiedad sigue siendo obligatoria. Un DBA con CONTROL
puede alterar las protecciones: no se afirma inmutabilidad absoluta.

## Despliegue seguro pendiente

No hay laboratorio confirmado. **No ejecutar todavia estos scripts.**

1. El responsable confirma instancia y nombre exacto de una copia aislada,
   que no contiene informacion de produccion. El nombre por si solo no basta.
2. Verificar version y contratos de seguridad de Parte II; SQL Server 2017+
   corresponde al preflight actual del proyecto. Revisar privilegios del app.
3. Obtener respaldo recuperable y ensayar recuperacion de esa copia con permiso
   especifico. Esta entrega no crea, restaura ni elimina bases de datos.
4. El instalador autorizado debe abortar al primer error, ejecutar cada archivo
   completo (todos sus GO) en transaccion externa y en la misma conexion,
   con XACT_ABORT ON. GO no garantiza atomicidad. Rollback ante cualquier error.
5. Solo despues de confirmar el laboratorio, el DBA establece en esa conexion
   `SESSION_CONTEXT(N'P3_DDL.LaboratorioConfirmado')` al nombre exacto de la BD.
   Los scripts no establecen esa confirmacion por si mismos.
6. Instalar 90 -> 91 -> 92. Se rechazan SecureFinanceERP y bases del sistema.
   No reutilizar runners que restauran bases ni ejecutar el instalador Full.
7. Reaplicar en la copia, comprobar restricciones, permisos reales y consulta.
   La validacion de estructura es conservadora y puede rechazar definiciones
   equivalentes: no desactivar CHECK para forzar la instalacion.
8. Abrir nueva sesion autorizada y acceder a `/auditoria/ddl`. Sin migraciones,
   la consulta devuelve 503 seguro; sin captura, una tabla vacia es esperable.

No existe rollback destructivo automatico. Ante fallo se revierte la transaccion
de instalacion; ante incidencia posterior se preservan registros y se prepara
una correccion incremental o recuperacion aprobada. No hacer DROP de la tabla.

## Diseno del trigger pendiente, no ejecutable

No se entrega migracion 93 ni CREATE/ENABLE TRIGGER. Se reserva su diseno para
la siguiente aprobacion. No se ha aprobado persistir comandos originales.

Flujo previsto, sujeto a rubrica:

1. Trigger ON DATABASE para los seis eventos aprobados.
2. Leer EVENTDATA una sola vez y extraer metadatos necesarios.
3. Conservar identidad del evento y login original, separados del principal
   interno limitado que eventualmente inserte en la tabla.
4. Aplicar solamente la politica de texto que se apruebe; no conservar XML,
   cuerpos, comentarios o literales indiscriminadamente.
5. Insertar una fila por evento del motor, sin un segundo registrador Node.
6. Propagar error de registro: puede impedir el DDL original. Sin SQL dinamico
   ni recordsets adicionales dentro del trigger.

Dos ALTER iguales realmente ejecutados son dos eventos; no deduplicar por hash
o texto. Un lote puede producir varios eventos. La fila del trigger participa
en la transaccion: si esta revierte, tambien puede revertir su auditoria.
No se garantizan intentos fallidos ni operaciones revertidas. Si fueran requisito,
evaluar un mecanismo externo antes de implementar. No inventar historia previa.

Pendiente decidir contexto interno sin privilegios amplios, politica de fallo
definitiva, proteccion del mecanismo y mantenimiento. No reutilizar ni modificar
el contexto ParteII.* ni los triggers DML existentes.

## Evidencias de verificaciones locales

Entorno: Windows, Node v25.8.1. Dependencias instaladas desde el lock existente
con `npm.cmd ci --ignore-scripts --no-audit --no-fund`; 153 paquetes, sin cambios
en package-lock ni paquetes nuevos declarados. Inicialmente la suite no pudo
arrancar por falta de Express; no fue una prueba SQL fallida.

| Verificacion | Resultado real |
| --- | --- |
| `npm.cmd run check` | PASS sintaxis de la aplicacion |
| `npm.cmd run check:ddl` | PASS sintaxis del modulo y sus tests |
| `npm.cmd run test:ddl` | PASS: 16 pruebas, 0 fallos, 0 omitidas |
| `npm.cmd test` | PASS: 132 pruebas, 0 fallos, 0 omitidas; incluye regresiones existentes |
| `git diff --check` | PASS; avisos de conversion LF/CRLF, sin errores de whitespace |
| SQL 90-92 contra servidor | NO ejecutado; laboratorio no confirmado |
| Trigger / CREATE, ALTER, DROP reales | NO ejecutado; captura fuera de esta entrega |
| Navegador y capturas responsive | NO ejecutado; no se fabricaron evidencias |

Los tests HTTP utilizan servidores efimeros 127.0.0.1, servicios simulados y
datos fixture identificados como pruebas. Las pruebas SQL de este archivo son
solo inspeccion textual, no compilacion ni ejecucion SQL Server. La suite general
usa dobles y temporales para pruebas locales, no ejecuta las suites `test:sql:*`.

No hay evidencia de restricciones o privilegios efectivos hasta probarlos en
laboratorio. No se modifico la BD principal ni se realizo commit, push o merge.

## Explicacion para exposicion

DML cambia datos: modificar un telefono. DDL cambia estructura: agregar una
columna o redefinir un procedimiento. La bitacora DDL permite investigar que
estructura cambio, cuando y bajo que identidad SQL; no reemplaza respaldos.

La tabla preparada guarda metadatos; el procedimiento de listado filtra y pagina;
el de detalle recupera un evento. Ambos validan al usuario antes de devolver
informacion. La pantalla muestra esos datos escapados, sin ejecutar instrucciones.
La auditoria DML y de accesos siguen funcionando por separado.

Demostracion posible hoy: ejecutar `npm.cmd run test:ddl` y explicar que usa
mocks. No presentar sus registros como eventos reales. Despues de confirmar
laboratorio e instalar 90-92, demostrar permisos y consultas; la tabla puede
estar vacia. La demostracion de CREATE/ALTER/DROP requiere una nueva entrega
de captura aprobada y objetos exclusivos de prueba. Nunca usar tablas de negocio.

## Pendientes para Kenneth

- Revisar rubrica: comando completo, eventos, nombres obligatorios y retencion.
- Confirmar laboratorio, respaldo e instalador atomico antes de cualquier SQL.
- Revisar estos cambios compartidos y permisos; no fusionar automaticamente.
- Verificar instalacion nueva/repetida, rechazo de comandos y denegacion directa.
- Aprobar y desarrollar captura en una entrega posterior; no prometer modulo
  de captura completo mientras falten trigger y pruebas SQL reales.
- Comprobar responsive en navegador. Las pruebas de render no miden layout.
- Mantener Creditos y Multibodega fuera de esta rama.
