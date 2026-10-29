# Auditoria DDL: captura exacta y laboratorio

Responsable: Dylan Albrygth Caal Caal. Rama exclusiva:
`feature/p3-dylan-auditoria-ddl`. Se conservan los 12 archivos nuevos y los
5 modificados de la primera entrega. No hay commit, push ni ejecucion SQL.

## Requisito y autorizacion

Dylan confirmo el requisito de T-SQL exacto de las paginas 1-2 de
`Especificacion_Proyecto_BD2_Parte_III.pdf`. El archivo no se encontro en la
carpeta inspeccionada: se registra su confirmacion, no una lectura independiente.

Tambien autorizo expresamente preparar captura literal **solo en laboratorio
sin secretos reales**, con aceptacion explicita del riesgo al instalar y acceso
para Administrador/Auditor. No se autorizo despliegue en la base principal.

El texto exacto puede incluir comentarios, literales, datos personales o secretos
dentro de un procedimiento. No existe una regex que los elimine garantizando a
la vez exactitud. Por eso no se redacta ni se trunca: los objetos del laboratorio
no deben contener secretos reales, las consultas requieren permiso vigente y
no se deben difundir capturas o exportaciones del contenido. Backups y archivos
del laboratorio tambien necesitan proteccion administrativa. Este diseno no es
una autorizacion para capturar datos sensibles en produccion.

## Archivos agregados en esta ampliacion

| Archivo | Proposito |
| --- | --- |
| `database/93_P3_DDL_TextoExacto.sql` | Evolucion de restricciones para comandos exactos |
| `database/94_P3_DDL_Captura.sql` | Principal interno limitado y trigger DATABASE |
| `database/tests/InstallAuditoriaDdlLab.ps1` | Instalacion atomica con confirmaciones y destino verificado |
| `database/tests/AuditoriaDdlLabTests.sql` | Seis eventos reales y comparacion binaria del texto; pendiente de ejecutar |
| `docs/parte3/auditoria-ddl/CAPTURA_Y_LABORATORIO.md` | Guia vigente y evidencia |

Se actualizaron servicio DDL, vistas DDL, parcial de encabezado, CSS local,
descripcion del catalogo, pruebas DDL y README del modulo. No se eliminaron
archivos anteriores. **90-92 permanecen sin cambios**. Sus procedimientos ya
permiten listado sin comandos y detalle con `ComandoTSql`: no se duplican.

## SQL y compatibilidad

Orden nuevo: 90 -> 91 -> 92 -> 93 -> 94. Solo 93-94 para una copia con 90-92
instalados. No volver a aplicar 90 tras evolucionar las restricciones; valida
el estado antiguo deliberadamente. 93 reconoce el estado nuevo al reaplicarse
y no modifica filas historicas. 94 usa un unico CREATE OR ALTER de su trigger.
La repetibilidad y compilacion reales siguen pendientes de laboratorio.

93 reemplaza solo los CHECK propios del modulo, dentro de la transaccion:

- `PENDIENTE_RUBRICA` conserva NULL en filas anteriores, sin inventar comandos.
- `EXACTO_EVENTDATA` exige comando no nulo y no vacio en NVARCHAR(MAX).

94 instala `P3_DDL_CapturarEstructura ON DATABASE` para CREATE_TABLE,
ALTER_TABLE, DROP_TABLE, CREATE_PROCEDURE, ALTER_PROCEDURE y DROP_PROCEDURE.
Lee EVENTDATA una sola vez y obtiene
`(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]` como NVARCHAR(MAX). No aplica
trim, reemplazos, resumen, redaccion o truncado. Se conserva el valor Unicode
decodificado que SQL Server entrega en CommandText, no los bytes originales
de la conexion ni una reconstruccion desde sys.sql_modules.

Cada evento genera una insercion con UTC, objeto, esquema, tipo, base, usuario
del evento, login original, host, aplicacion y sesion. No guardar el XML completo.
El escritor `P3_DDL_Escritor WITHOUT LOGIN` tiene INSERT sobre esa tabla, no
SELECT/UPDATE/DELETE ni roles/propiedad. No se usa EXECUTE AS OWNER. Se deniega
su impersonacion a `securefinance_app`, que conserva solo las dos consultas.

Los seis eventos no incluyen comandos de seguridad de servidor. Esto reduce
alcance pero no evita secretos embebidos en CREATE/ALTER TABLE o PROCEDURE.
No se modifica ningun trigger DML ni el contexto ParteII.*.

## Transacciones y limites

Un fallo del trigger puede bloquear el cambio estructural: se propaga y no se
oculta. Un rollback revierte tambien el evento. No prometer registro persistente
de intentos fallidos ni cambios revertidos. Dos ALTER realmente ejecutados son
dos eventos; no deduplicar por texto. Un lote puede producir varios eventos.

La captura empieza al activar el trigger, no retroactivamente. Un DBA puede
alterar el mecanismo; no hay inmutabilidad absoluta frente a CONTROL/sysadmin.
No se agregaron privilegios administrativos a la cuenta web.

## Backend e interfaz

Las rutas GET `/auditoria/ddl` y `/auditoria/ddl/:id` mantienen autenticacion,
cambio obligatorio de password y `AUDITORIA_DDL_CONSULTAR`. Los dos SP validan
permiso SQL vigente con actor de sesion; el filtro usuario no cambia ese actor.
Administrador y Auditor reciben el permiso explicitamente en 92.

El listado sigue sin enviar comandos: filtros, paginacion de 20 y BigInt exacto
se conservan. El servicio solo admite texto completo en el detalle individual
autorizado y rechaza respuestas incompatibles. No imprime comandos en logs.
El detalle usa `<%= event.ComandoTSql %>` dentro de pre/code: escape HTML sin
ejecucion. El scroll y ajuste de lineas no recortan la cadena. No hay endpoints
de ejecucion, borrado ni desactivacion. Las respuestas conservan `no-store`.

El corte de identidad no es un snapshot transaccional. La interfaz no inventa
que un servidor tiene captura activa: ese estado se comprueba al desplegar.

## Instalacion en laboratorio, no ejecutada

Requisitos: instancia y copia ya existentes/autorizadas, sin datos reales,
seguridad Parte II, usuario SQL de aplicacion limitado, roles activos y respaldo
recuperable. El runner **no crea ni restaura bases**, usuarios comerciales,
credenciales ni archivos .env. Utiliza autenticacion integrada y TLS con
validacion de certificado. Si el certificado no es valido, corregir la confianza
con el DBA; no desactivar TLS para forzar el despliegue.

El destino autorizado actual es exactamente `SecureFinanceERP_Lab_Dylan`.
Reemplaza el prefijo de ejemplos anteriores, no prueba aislamiento: el
responsable debe confirmarlo externamente. `InstanciaEsperada`
debe coincidir con el resultado real de SERVERPROPERTY('ServerName').

Ejemplo ilustrativo, **no ejecutado ni destino autorizado por este documento**:

```powershell
.\database\tests\InstallAuditoriaDdlLab.ps1 `
  -Servidor "SERVIDOR\INSTANCIA" `
  -InstanciaEsperada "SERVIDOR\INSTANCIA" `
  -BaseLaboratorio "SecureFinanceERP_Lab_Dylan" `
  -Modo Inicial `
  -ConfirmarLaboratorioSinDatosReales `
  -AceptarTextoSqlCompleto `
  -Probar
```

Usar `-Modo Completar` para 90-92 ya instalados. Se aborta al primer error y
todos los lotes GO de la instalacion comparten conexion/transaccion. Las dos
marcas SESSION_CONTEXT incluyen el nombre exacto de la BD: confirmacion de
laboratorio y aceptacion del riesgo del texto. Los SQL no se autoconfirman.

Las pruebas opcionales van en una **segunda** transaccion y siempre revierten.
Si fallan, las migraciones ya confirmadas permanecen instaladas: no hay un
rollback destructivo de tablas. El error del runner no imprime SQL completo.
No usar clientes que continuen despues de errores ni ejecutar Full.

## Pruebas SQL preparadas, pendientes

`AuditoriaDdlLabTests.sql` rechaza principal/sistema, destino no confirmado,
transaccion no exclusiva y colisiones de fixtures. Solo crea/modifica/elimina
sus objetos nuevos `P3_DDL_QA_Tabla` y `P3_DDL_QA_Proc`, nunca tablas previas.
En un laboratorio sin despliegues concurrentes comprueba:

- Seis eventos, uno por CREATE/ALTER/DROP de tabla y procedimiento.
- Igualdad binaria y DATALENGTH del comando respecto al ejecutado.
- Unicode y procedimiento de mas de 4000 caracteres.
- Esquema, base, login original y sesion.
- Ausencia de objetos fixture tras sus DROP; rollback final de filas de prueba.

Requieren pruebas adicionales en ese laboratorio: permisos efectivos desde
conexion limitada, usuario ERP sin permiso y revocacion, filtros/paginacion
contra datos reales de prueba, captura con un ejecutor DDL limitado, repeticion
de migraciones, rollback/fallo de captura y compatibilidad DML/accesos real.
No deshabilitar mecanismos de seguridad para hacerlas pasar. No se ejecutaron.

## Evidencias locales

Las pruebas Node/HTTP usan fixtures sinteticos sin secretos reales; el analisis
de SQL es textual, no compilacion/ejecucion del motor. Resultados ejecutados:

| Verificacion | Resultado real |
| --- | --- |
| `npm.cmd run test:ddl` | 19 PASS, 0 fallos, 0 omitidas |
| `npm.cmd test` | 135 PASS, 0 fallos, 0 omitidas |
| `npm.cmd run check` | PASS |
| `npm.cmd run check:ddl` | PASS |
| Parser PowerShell de InstallAuditoriaDdlLab.ps1 | PASS; instalador no ejecutado |
| `git diff --check` | PASS; avisos LF/CRLF no bloqueantes |
| Migraciones, trigger y fixtures en SQL Server | NO ejecutados: laboratorio no confirmado |
| Revision visual en navegador | Pendiente; render EJS si cubierto por tests HTTP |

El instalador PowerShell solo se analiza sintacticamente; no se abre una
conexion SQL. No hay capturas de navegador fabricadas. Estos resultados no
certifican compilacion del trigger, permisos efectivos ni exactitud EVENTDATA
contra una instancia real; las pruebas SQL preparadas deben comprobarlos.

## Exposicion

DML cambia datos; DDL cambia estructura. Crear una tabla o redefinir un SP
dispara el trigger, que guarda metadatos y el CommandText del evento. El listado
pagina metadatos; el detalle autorizado muestra el texto completo escapado.
El modulo observa cambios, no restaura objetos ni sustituye respaldos.

Para demostrarlo: instalar en una copia confirmada, ejecutar `-Probar`, explicar
que los fixtures revierten y no quedan en el historial; despues crear un objeto
nuevo y sintetico autorizado, consultarlo en la web y comprobar acceso denegado
con otro perfil. Ese segundo ejercicio persiste eventos: requiere autorizacion
del laboratorio y no se ha ejecutado en esta entrega.
