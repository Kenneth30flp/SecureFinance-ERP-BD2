# Instalación y operación

## Requisitos

Node.js 24+ (validado en v25.8.1), SQL Server 2017+ y ERP con seguridad de Parte II instalada (`Usuario`, roles, permisos, `securefinance_app`, `sp_ParteII_ValidarPermiso`). Validado en **SQL Server 17.0.1145.4, Enterprise Developer, Windows**. Otras versiones compatibles por contrato aún requieren verificación en su motor real.

La instalación usa `sqlcmd`, autenticación Windows del operador y verificación explícita de servidor/base. Crea certificados en la base, `master` y `msdb`. La aplicación y el servicio de respaldo no necesitan privilegios del instalador. TLS local: `-N -C`; en Node `encrypt: true`, certificado autofirmado confiable solamente en el entorno local.

## A. Laboratorio completo nuevo (recomendado para desarrollo)

En PowerShell dentro de esta rama:

```powershell
npm.cmd ci
$env:LDF_EXPECTED_SERVER = 'NOMBRE_REAL_DEVUELTO_POR_SERVERPROPERTY'
npm.cmd run lab:ldf
npm.cmd run test:sql:ldf
npm.cmd run start:ldf:lab
```

Consultar primero la identidad con:

```powershell
sqlcmd -S localhost -E -N -C -b -d master -Q "SELECT SERVERPROPERTY('ServerName');"
```

El laboratorio instala el esquema completo oficial en una base **nueva**, genera dos logins SQL de permisos mínimos y un administrador web sintético. No copia datos de otras bases ni lee sus `.env` o credenciales. Estado/secretos en `.data/ldf-lab.json`; acceso web en `.data/ldf-acceso.txt`, ignorados por Git.

URL: **http://localhost:3004/dba/ldf**. Usuario web `admin`; contraseña en `.data/ldf-acceso.txt`. Es distinta de la instalación anterior. La cookie del laboratorio tiene nombre independiente. Deja abierta la terminal mientras lo usas.

La creación inicial deja la base en FULL **sin respaldo inicial**, para verificar el rechazo de LOG. `test:sql:ldf` genera el FULL exclusivamente en esa base, verifica el archivo y ejecuta las pruebas. Los archivos se escriben en el directorio de respaldo predeterminado del motor SQL. Ningún comando inicializa ni respalda las bases originales.

No repetir `lab:ldf` sobre el mismo archivo de estado: se detiene para evitar sobrescribir el laboratorio. Las pruebas se pueden volver a ejecutar y conservan la evidencia del rechazo inicial. Los tests pueden crecer el LOG de laboratorio; no lo reducen al terminar.

## B. Instalar el módulo en otra base autorizada del ERP

Esto es una instalación DBA explícita, no se ejecuta al arrancar Node. Hacerla sobre la base elegida por el equipo después de las pruebas cruzadas.

1. Comprobar servidor, base, versión y directorio en la máquina de SQL Server.
2. El DBA crea un **login SQL dedicado nuevo** para el servicio manual: `CONNECT SQL`, sin roles de servidor, sin acceso a otras bases. Guardar su secreto localmente, nunca en Git. Debe ser distinto de `DB_USER`.
3. Crear previamente el directorio local al motor y dar escritura a la **cuenta del servicio SQL Server**, no al navegador. El instalador admite una ruta absoluta de Windows o Linux, sin UNC ni `..`.
4. Configurar estas variables del proceso:

```powershell
$env:LDF_INSTALL_SERVER = 'localhost'
$env:LDF_EXPECTED_SERVER = 'SERVIDOR_REAL'
$env:LDF_INSTALL_DATABASE = 'BASE_ERP_AUTORIZADA'
$env:LDF_ADMIN_USER = 'LOGIN_SQL_DEDICADO'
$env:LDF_BACKUP_DIRECTORY = 'D:\SQLBackups\ERP'
$env:LDF_WARNING_PERCENT = '70'
$env:LDF_CRITICAL_PERCENT = '85'
# Opcional y explícito: asigna los dos permisos a un rol de aplicación existente.
$env:LDF_GRANT_ROLE = 'Administrador'
node scripts/parte4/ldf/install.cjs --authorize-install
```

La instalación es transaccional, falla si ya está instalada y no reinicia contraseñas, no toca saldos ni reemplaza procedimientos históricos. Sin `LDF_GRANT_ROLE` solo crea los permisos; asignarlos mediante administración de roles. Volver a iniciar sesión web para obtener permisos nuevos.

5. Agregar a la configuración local del **proceso web** (además de sus `DB_*` habituales):

```text
LDF_DATABASE=BASE_ERP_AUTORIZADA
LDF_EXPECTED_SERVER=SERVIDOR_REAL
LDF_ADMIN_USER=LOGIN_SQL_DEDICADO
LDF_ADMIN_PASSWORD=secreto_local_del_login_dedicado
```

`LDF_DATABASE` debe coincidir exactamente con `DB_NAME`. El usuario de la web jamás selecciona base o ruta. El módulo comprueba identidad también dentro de SQL, incluida `database_guid`; restaurar una copia no la autoriza automáticamente.

6. Reiniciar Node y entrar a `/dba/ldf` con `DBA_LDF_CONSULTAR`. Respaldar exige también `DBA_LDF_RESPALDAR_LOG`.

Si no existe FULL/diferencial vigente, el botón queda inhabilitado: el DBA debe establecer la cadena según la política del equipo. El módulo LDF no crea FULL ni cambia a FULL automáticamente.

## Actualizar código SQL y firmas

Después de validar una nueva versión, con las mismas variables y destino:

```powershell
node scripts/parte4/ldf/install.cjs --authorize-install --upgrade
```

La actualización preserva configuración y auditoría, actualiza los dos procedimientos de operación y **rota los certificados/firmas del módulo** en una transacción. Las claves privadas se eliminan tras firmar. No ejecutar `ALTER PROCEDURE` suelto: invalidaría su firma. El servicio debe conservar el login que se autorizó en la instalación.

## Configurar alertas

```powershell
$env:LDF_WARNING_PERCENT = '70'
$env:LDF_CRITICAL_PERCENT = '85'
node scripts/parte4/ldf/configure.cjs --authorize-config
```

Reutiliza `LDF_INSTALL_DATABASE`, `LDF_INSTALL_SERVER` y `LDF_EXPECTED_SERVER`. Valores: `0 < advertencia < crítico <= 100`, con dos decimales. Solo cambia indicadores; no respalda, reduce ni modifica archivos. Actualizar el panel para ver los nuevos límites.

## Errores y recuperación de una solicitud

- **Modelo SIMPLE:** BACKUP LOG incompatible; revisar política con el DBA.
- **Cadena no inicializada:** falta FULL/diferencial vigente; el panel no lo inventa.
- **Directorio ausente:** se verifica en SQL con `sys.dm_os_file_exists`; corregir destino autorizado.
- **Acceso denegado al archivo:** el motor verifica el permiso efectivo de escritura al hacer BACKUP; comprobar cuenta del servicio SQL y volumen.
- **Permiso DMV o BACKUP insuficiente:** revisar firmas y certificados. No dar `sysadmin` a la web.
- **Otra operación:** bloqueo lógico ocupado; actualizar/reintentar con la misma referencia.
- **Respuesta perdida:** la misma UUID se conserva en `sessionStorage`. Revisar historial y reintentar esa referencia; SQL concilia con `msdb` y nunca repite el BACKUP de una UUID existente.
- **INCIERTO sin evidencia en msdb:** revisión DBA del archivo/registro del motor antes de solicitar otro respaldo. No se proclama éxito ni se reenvía automáticamente.

El historial mostrado tiene límites (30 solicitudes/20 respaldos). SQL conserva todas las ejecuciones. Si una operación pendiente salió de ese listado, su misma UUID sigue siendo reconsultable mediante el punto de respaldo idempotente.

## Pruebas y evidencias

```powershell
npm.cmd run check
npm.cmd test
npm.cmd run test:sql:ldf
npm.cmd run test:ui:ldf
npm.cmd run test:restore:ldf
```

`test:ui:ldf` requiere Chrome/Edge; crea un perfil aislado, comprueba cuatro tamaños y realiza respaldos reales en el laboratorio. `test:restore:ldf` restaura FULL+LOG a otra base nueva, sin `REPLACE`, y ejecuta CHECKDB. Esta copia queda intencionalmente fuera de la identidad autorizada del módulo.
