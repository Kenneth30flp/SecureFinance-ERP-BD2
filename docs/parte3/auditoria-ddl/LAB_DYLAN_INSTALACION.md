# Laboratorio Dylan: preparacion e instalacion

## Estado y alcance

Destino unico: **SecureFinanceERP_Lab_Dylan**, en **localhost**. Este documento
reemplaza los ejemplos de nombres `SecureFinanceERP_P3_DDL_<sufijo>` y servidores
arbitrarios de las guias anteriores para este laboratorio. El runner DDL ahora
solo admite el nombre exacto autorizado; la guia de captura enlaza este destino.

Autorizacion recibida: preparar la creacion de una base nueva **solo si no
existe**, sin datos reales. No autoriza reconstruir una base existente, restaurar
copias, habilitar inventario ni modificar otras bases. La autorizacion no elimina
las confirmaciones explicitas exigidas al ejecutar.

Bloqueo observado en una comprobacion integrada independiente:

> La conexion SQL a localhost esta bloqueada por la validacion del certificado TLS.

Se intento `sqlcmd` contra localhost con autenticacion integrada y cifrado,
pero la cadena del certificado no es confiable. **No se obtuvo una conexion
funcional, no se creo la base ni se ejecutaron migraciones o pruebas SQL.**
Este preparador solo se verifico mediante parser y PLAN local; no se ejecuto
su modo de escritura ni se utilizo un bypass de certificado.

Solo se agregan estos archivos:

- `database/tests/PrepareSecureFinanceLabDylan.ps1`.
- `database/tests/LabDylanSecurityCatalog.sql`.
- `docs/parte3/auditoria-ddl/LAB_DYLAN_INSTALACION.md`.

En `database/tests/InstallAuditoriaDdlLab.ps1` solo se restringe el destino mediante
`ValidateSet('SecureFinanceERP_Lab_Dylan')` y se usa un constructor de conexion
explicito. Su comportamiento de instalacion/pruebas no se ejecuta en esta tarea.
Se conservan los cambios previos de la rama, `src`, las pruebas JS/SQL existentes,
SQL 90-94 y las ramas master/main. No hay commit ni cambio de rama.

## PLAN sin conexion

Ejecutar desde la raiz de **este** repositorio:

```powershell
.\database\tests\PrepareSecureFinanceLabDylan.ps1
```

Para validar tambien los cinco archivos DDL, sin instalarlos:

```powershell
.\database\tests\PrepareSecureFinanceLabDylan.ps1 -IncluirAuditoriaDdl
```

Sin `-Ejecutar`, el script carga y valida solamente el manifiesto local, muestra
nombres y cantidades de lotes, y hace `return` **antes de construir la conexion,
abrirla o hacer preflight**. No necesita `InstanciaEsperada` ni las confirmaciones.
Los switches de confirmacion por si solos no cambian PLAN a ejecucion.

PLAN no prueba existencia/ausencia del destino, permisos, version, TLS, validez
T-SQL ni funcionamiento del trigger. Sus cantidades incluyen los segmentos vacios
que dejan los GO finales; los segmentos vacios no se ejecutan.

## Requisitos privados

El DBA debe resolver la confianza TLS de forma administrativa valida: cadena,
certificado y nombre `localhost` deben poder verificarse. El preparador usa
autenticacion integrada Windows, `Encrypt=True`, `TrustServerCertificate=False`,
sin pooling ni persistencia de informacion sensible. No ofrece `-C`, TLS apagado,
TrustServerCertificate alternativo ni autenticacion por password.

No carga `.env`, no recibe credenciales, no lee hashes ni crea logins de servidor.
El login **existente** `securefinance_app` debe estar habilitado y limitado. El
preflight es conservador: admite un login SQL de tipo `S`, no grupos Windows ni
tipos de principal cuya membresia efectiva no pueda garantizar con estas reglas.
No modifica ese login ni sus roles/permisos de servidor. Si falta o no cumple,
el DBA debe resolverlo privadamente fuera de este instalador y de esta tarea.

La cuenta integrada instaladora necesita visibilidad completa de metadatos de
servidor/bases, permiso para crear bases y administrar el esquema/permisos del
laboratorio nuevo. La cuenta web no debe usarse como instaladora.

Antes de una futura ejecucion, el DBA debe obtener y revisar privadamente la
identidad real de la instancia con una consulta **de solo lectura** en una conexion
integrada con TLS validado, por ejemplo:

```sql
SELECT CONVERT(nvarchar(128), SERVERPROPERTY('ServerName')) AS InstanciaReal;
```

Esta consulta es una instruccion futura, **no ejecutada aqui**. Su resultado exacto
se pasa en `-InstanciaEsperada`; `localhost` es el endpoint, no necesariamente el
valor de `ServerName`. El instalador compara el valor real con collation binaria,
sin imprimirlo. No inventar el nombre ni publicar informacion privada del servidor.

## Ejecucion futura

El siguiente comando **NO se ha ejecutado**. Requiere TLS resuelto, revision DBA,
ausencia del destino y todas las confirmaciones. Sustituir el marcador por el
resultado privado del preflight anterior, no por una credencial:

```powershell
.\database\tests\PrepareSecureFinanceLabDylan.ps1 `
  -Servidor localhost `
  -InstanciaEsperada '<ServerName verificado privadamente>' `
  -Ejecutar `
  -CrearBase `
  -ConfirmarLaboratorioSinDatosReales `
  -AceptarTextoSqlCompleto
```

El default instala solamente el baseline completo hasta cotizaciones 44. Para
instalar ademas 90-94 al final de esa misma instalacion nueva, agregar
`-IncluirAuditoriaDdl`. No hay modo de reanudar, reconstruir ni `-UsarBaseVacia`.
Se exigen ambas aceptaciones incluso para el baseline: no son una aprobacion
implicita de captura en otros destinos.

El preparador realiza estas etapas:

1. Valida todos los archivos seleccionados en memoria antes de cualquier conexion
   o creacion. Un archivo ausente o rechazado detiene el proceso.
2. Abre una conexion integrada cifrada a localhost/master y hace preflight de
   solo lectura. Si TLS falla, se detiene antes de crear.
3. Exige instancia real exacta, SQL Server 2017+ y `nested triggers=1`. Si vale 0,
   se detiene; no ejecuta `sp_configure` ni cambia configuraciones del servidor.
4. Exige visibilidad y permiso de creacion, destino ausente, login de aplicacion
   habilitado, sin membresias de servidor ni sysadmin/securityadmin, sin propiedad
   de bases ni grants amplios directos/heredados por public. Solo permite los
   grants basicos de conexion y visibilidad de bases especificados en el codigo.
5. Ejecuta unicamente `CREATE DATABASE [SecureFinanceERP_Lab_Dylan]` fuera de la
   transaccion del esquema. Si existe, aun vacia, aborta sin reutilizarla. Una
   creacion concurrente tambien produce error; no se acepta como propia.
6. Selecciona exclusivamente la base nueva y comprueba ausencia de objetos de
   usuario, triggers, tipos, assemblies, sinonimos, usuarios/roles/esquemas propios
   heredados desde model. Sin visibilidad completa tambien aborta.
7. Abre una transaccion externa unica, misma conexion, `XACT_ABORT ON`, para todos
   los archivos seleccionados y todos sus GO. Verifica `DB_NAME()` exacto,
   `@@TRANCOUNT=1` y `XACT_STATE()=1` antes de cada lote y al finalizar. Respeta las
   transacciones internas balanceadas de las migraciones; no confirma por archivo.
8. Antes de 90, solo cuando se selecciono DDL, establece ambas claves
   `P3_DDL.LaboratorioConfirmado` y `P3_DDL.TextoExactoAutorizado` con el nombre
   exacto del laboratorio. No establece flags de seeds academicos.
9. Comprueba mapeo SID del usuario SQL `securefinance_app`, sin roles/propiedad ni
   grants amplios, y permisos efectivos limitados de base/esquema. Comprueba que
   no se insertaron usuarios ERP, clientes, productos, facturas, Kardex o aperturas
   ni se habilito inventario. Solo entonces confirma la transaccion.

El preflight devuelve codigos numericos privados: 1 instancia, 2 version,
3 nested triggers, 4 visibilidad/creacion, 5 destino existente, 6 login ausente,
deshabilitado o no admitido, 7 privilegios de servidor/propiedad. `-1` significa
que el preflight no termino. Los errores muestran etapa y numero SQL, no comandos,
mensajes completos del motor, valores privados ni cadenas de conexion.

## Manifiesto cerrado

Orden exacto del baseline inicial, **11 archivos**:

```text
02_SecurityTables.sql
03_SecurityStoredProcedures.sql
tests/LabDylanSecurityCatalog.sql
05_BusinessTables.sql
06_TransactionProcedures.sql
07_AuditCore.sql
08_AuditTriggers.sql
11_UserAdministration.sql
12_PasswordRecovery.sql
14_DashboardSummary.sql
10_AppPermissions.sql
```

El catalogo nuevo solo inserta los roles Administrador, Cajero y Auditor, los
permisos USUARIOS_ADMINISTRAR, VENTAS_REGISTRAR y AUDITORIA_CONSULTAR y sus enlaces:
Administrador recibe los tres, Cajero ventas y Auditor auditoria. Exige base
exacta, una transaccion externa activa y tablas de seguridad vacias. No inserta
usuarios, passwords, tokens ni eventos. Las migraciones posteriores agregan sus
propios permisos funcionales. `10_AppPermissions.sql` mapea el login ya existente
a un **usuario de base**, sin crear un login ni una identidad ERP.

Despues se ejecutan exactamente estos **27 archivos**, sin 27-29:

```text
15_ParteII_Preflight.sql
16_ParteII_Catalogos.sql
17_ParteII_Kardex.sql
18_ParteII_Procedimientos.sql
19_ParteII_Auditoria.sql
20_ParteII_Permisos.sql
21_ParteII_IntegracionFacturacionKardex.sql
22_ParteII_ConsultasWeb.sql
23_ParteII_MantenimientoClientes.sql
24_Edward_Devoluciones.sql
25_Edward_Garantias.sql
26_Edward_ConsultasPermisos.sql
30_Jose_FuncionesAnaliticas.sql
31_Jose_DashboardVentas.sql
32_Jose_PermisosConsultas.sql
33_ERP_ProductoProveedor.sql
34_ERP_RecepcionesCompra.sql
35_ERP_AplicacionesNotaCredito.sql
36_ERP_PermisosIntegracion.sql
37_ERP_VentaIdempotente.sql
38_ERP_ProductoSKUAutomatico.sql
39_ERP_HistorialFacturas.sql
40_ERP_ReactivarCliente.sql
41_P3_COT_EstructuraCotizaciones.sql
42_P3_COT_Operaciones.sql
43_P3_COT_ConversionFactura.sql
44_P3_COT_BusquedaComercial.sql
```

Opcionalmente, siempre al final, cinco archivos mas:

```text
90_P3_DDL_Estructura.sql
91_P3_DDL_Consultas.sql
92_P3_DDL_Permisos.sql
93_P3_DDL_TextoExacto.sql
94_P3_DDL_Captura.sql
```

Total: **38 sin DDL / 43 con DDL**. No se usan comodines para descubrir migraciones,
otros repositorios ni worktrees. Los GO de 43 conservan la misma transaccion
externa que el resto. La captura DDL no reconstruye eventos del baseline anterior.

Excluidos deliberadamente: `01_CreateDatabase.sql`, `04_SecuritySeedData.sql`,
`05_BusinessSeedData.sql`, `SecureFinanceERP_Full.sql`,
`07_TransactionPermissions.sql`, `09_AuditPermissions.sql`,
`12_SalesDiscounts.sql` y `13_OperationsDesk.sql`. No se leen ni ejecutan sus
contenidos por el preparador. 05/06 actuales ya contienen descuentos/motivos;
no se aplican migraciones historicas redundantes. No se crean fixtures comerciales.

## Aislamiento y fallos

Todas las bases preexistentes quedan protegidas, incluidas las cinco referidas en
la consigna. No se consulto un inventario SQL ni se presuponen sus nombres. Tambien
se rechazan expresamente SecureFinanceERP y las bases de sistema como destino del
esquema. master solo se usa como contexto de preflight/creacion; no se modifica su
esquema. No se permite escribir en ninguna otra base, de sistema o de usuario. No existe
parametro de base arbitraria, DROP DATABASE, RESTORE, BACKUP, limpieza destructiva
ni ALTER DATABASE sobre bases existentes.

Para los diez SQL base originales se admite solamente el primer
`USE [SecureFinanceERP];` exacto como primer enunciado despues de comentarios.
Se quita en memoria, conservando los GO; la conexion ya apunta al laboratorio.
No se reemplaza globalmente SecureFinanceERP dentro de cuerpos, mensajes ni
recursos de bloqueo, y no se editan originales. El catalogo sintetico y 15..44/DDL
no admiten USE. El analisis distingue comentarios, literales y GO, rechaza USE
adicional, cambios de base, operaciones de servidor/backup/restore/DROP TABLE,
referencias de tres partes y directivas SQLCMD. Inspecciona tambien definiciones
SQL literales completas anidadas. Solo admite GO independiente, sin repeticion.

Es una defensa conservadora del manifiesto revisado, **no un parser T-SQL completo
ni un sandbox para SQL arbitrario/concatenado**. Los cambios futuros requieren
revision privada DBA y nuevo PLAN; nunca se relajan guardas para hacerlos pasar.
Las comprobaciones de metadatos no sustituyen una revision de privilegios
efectivos de servidor, firmas, cadenas de propiedad y despliegues concurrentes.

La creacion de la base **no es atomica con el esquema**. Si falla una migracion,
se aborta al primer error y se intenta revertir toda la transaccion del esquema.
Puede quedar el laboratorio vacio creado previamente o contenido heredado de
model que haya provocado el rechazo inicial. No se elimina la base ni se ejecuta
un segundo intento automatico. Ante perdida de conexion durante COMMIT, el estado
de confirmacion debe determinarlo el DBA privadamente; no se presume rollback.
Una nueva ejecucion abortara si el nombre ya existe. Su eventual recuperacion o
eliminacion necesita autorizacion separada, nunca limpieza automatica.

## Integracion posterior

Para integrar los modulos pendientes de otros responsables, usar el baseline sin
`-IncluirAuditoriaDdl`. Una vez incorporados y revisados en este repositorio,
instalar separadamente **70-79 (credito), luego 80-89 (bodega), finalmente 90-94**.
Este preparador no los busca ni presupone nombres/contenidos desconocidos, y no
puede reejecutarse sobre la base ya creada. La integracion necesita un protocolo
separado revisado, mismo destino exacto y transacciones externas donde corresponda.

Despues de esa revision, este ejemplo futuro instala DDL inicialmente en el
laboratorio ya preparado; **NO se ha ejecutado**:

```powershell
.\database\tests\InstallAuditoriaDdlLab.ps1 `
  -Servidor localhost `
  -InstanciaEsperada '<ServerName verificado privadamente>' `
  -BaseLaboratorio SecureFinanceERP_Lab_Dylan `
  -Modo Inicial `
  -ConfirmarLaboratorioSinDatosReales `
  -AceptarTextoSqlCompleto `
  -Probar
```

No usar `Inicial` si ya se instalaron 90-94 con el preparador. `Completar` conserva
su significado anterior: aplicar 93-94 sobre 90-92 existentes, con revision previa.
El runner DDL requiere conexion y confirmaciones; **no tiene modo PLAN**.
Sus pruebas opcionales existentes se ejecutarian en una segunda transaccion que
revierte fixtures/eventos de prueba; no revierten migraciones ya confirmadas.
No se modifican esas pruebas ni SQL 90-94. No se certifica aqui su compilacion,
repetibilidad, permisos efectivos ni exactitud de EVENTDATA.

El laboratorio queda sin usuario ERP para iniciar sesion. El responsable debera
aprovisionar posteriormente una identidad privada y sus roles mediante un proceso
autorizado separado; no hay administrador falso/automatico. La configuracion
privada del backend para el destino exacto queda tambien fuera de esta tarea:
no se leen ni escriben `.env`/credenciales y no se cambia `src`. No incorporar
secretos reales en definiciones SQL: 94 captura texto literal completo. No se
habilita apertura/Kardex automaticamente; requiere aprobacion posterior separada.

## Evidencia local

Verificaciones efectuadas sin conexion SQL:

| Verificacion | Resultado |
| --- | --- |
| Parser.ParseFile de PrepareSecureFinanceLabDylan.ps1 | PASS, 0 errores |
| Parser.ParseFile de InstallAuditoriaDdlLab.ps1 | PASS, 0 errores |
| PLAN por defecto | PASS, 38 archivos, 27 modulos 15..44, DDL=False |
| PLAN con -IncluirAuditoriaDdl | PASS, 43 archivos, 27 modulos 15..44, DDL=True |
| Creacion / preflight real / migraciones / pruebas SQL | NO ejecutados; TLS bloqueado |
| Pruebas JS, backend y revision visual | No ejecutadas; fuera de este alcance |

Estos resultados solo acreditan sintaxis PowerShell y validacion local del
manifiesto. El laboratorio y la auditoria DDL reales siguen pendientes.
