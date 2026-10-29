# Actualización real de SecureFinanceERP — 29/10/2026

## Resultado

La aplicación original permanece en `main@b5cca8d`, ejecutada con **`npm.cmd start`** en **http://localhost:3000**, conectada mediante el `.env` existente a **`SecureFinanceERP`**. La sesión real de `admin` se verificó en Chrome y el último acceso SQL resultó EXITOSO. No se leyó la contraseña del formulario ni se restableció ninguna contraseña. Las seis páginas `/modulos`, `/cotizaciones`, `/promociones`, `/creditos`, `/multibodega` y `/auditoria/ddl` respondieron HTTP 200 con esa sesión, y los cinco enlaces aparecen en el Centro de módulos.

La rama de herramientas es `fix/p3-original-upgrade`, creada desde `main@b5cca8d`. La actualización SQL ya fue aplicada; integrar estas herramientas a main no es necesario para que los módulos funcionen. No se cambió la configuración hacia una base de prueba ni se lanzó un servidor alternativo. La copia restaurada se utilizó exclusivamente para ensayar la actualización.

## Inspección y protección de datos

La base original no tenía objetos Parte III. Kardex ya estaba habilitado con IntegracionVersion=2. Se detectaron las dependencias históricas requeridas al ejecutar las guardas de cada migración. La copia de seguridad se hizo antes de cualquier cambio de esquema con **BACKUP DATABASE ... WITH COPY_ONLY,CHECKSUM** y un archivo nuevo: `SecureFinanceERP_PreP3_20261029085805_8bd677.bak`.

Se ejecutó RESTORE VERIFYONLY WITH CHECKSUM y una restauración real con MOVE a archivos nuevos, sin REPLACE, en `SecureFinanceERP_P3_Rehearsal_20261029085805_8bd677`. CHECKDB pasó en la copia. El archivo completo está en el directorio de respaldo de la instancia SQL Server. Su ruta exacta y los resultados privados están en `.data/original-p3-upgrade/state.json`; no publicar ese directorio ni la copia de seguridad.

Antes de cada actualización se tomaron hashes SHA-256 de cada fila de **todas** las tablas preexistentes, incluyendo salts/hashes de usuarios, asignaciones de roles, caja, productos, inventario y registros históricos. Se repitió la comparación dentro de la misma transacción antes del COMMIT. Cualquier modificación o pérdida de una fila original aborta el grupo entero. Se permiten únicamente filas nuevas de permisos y registros de auditoría de instalación. No se exportaron valores de hashes de contraseñas ni datos personales.

La asignación inicial local conserva todo el stock global existente en Bodega Central; no reconstruye movimientos históricos ni vuelve a abrir Kardex. Las otras ubicaciones iniciales del módulo no reciben stock. La conciliación final no tiene diferencias.

## Plan aplicado

`scripts/deployment/original-manifest.json` lista las 33 migraciones y hashes de origen/adaptación. Orden exacto:

1. Cotizaciones: 41, 42, 43, 44.
2. Promociones: 60, 61, 62, 63.
3. Créditos: 70–77 y **78_AjustesConsultas**; 76 es el motor integrado con Promociones y Cotizaciones.
4. Multibodega: 80–88 y **89_Complementos**.
5. Auditoría DDL: 90–95.

No se ejecutaron verificaciones numeradas como migraciones ni seeds de usuarios o datos. No se modificaron los archivos históricos ni las migraciones 41–44/60–63; el instalador adapta en memoria únicamente las guardas de las nuevas migraciones DDL que rechazaban la base principal.

La protección de laboratorio se sustituyó por una autorización explícita del despliegue: `P3.Despliegue.Autorizacion` liga el nombre exacto de servidor/base. `P3_INT_Destino()` devuelve el destino solo con esa coincidencia y con DB_ID>4. Las claves de confirmación de DDL se convierten a claves de despliegue; se conservan transacción externa, XACT_ABORT, visibilidad de metadatos, validación de privilegios y prohibición de bases de sistema. El trigger 95 falla con error fuera del destino autorizado; no omite eventos silenciosamente.

El escritor DDL sigue siendo interno, sin login ni roles, con INSERT restringido a su tabla y EXECUTE del helper de autorización. El usuario SQL web no puede leer/modificar directamente Bitacora_DDL; las consultas pasan por procedimientos y por el permiso AUDITORIA_DDL_CONSULTAR. Admin conserva sus roles previos y obtiene los permisos de los cinco módulos mediante las asignaciones de las migraciones. El texto SQL exacto queda restringido a Administrador/Auditor; no compartirlo, ya que puede contener información sensible. La captura se revierte junto con el DDL si su transacción se revierte.

La instalación obtiene un bloqueo exclusivo de despliegue, rechaza sesiones de aplicación activas, no cambia de base entre lotes y hace un único COMMIT final. Los BEGIN/COMMIT internos de migraciones existentes permanecen anidados dentro del grupo externo. Se verificó el mismo plan y hash en la copia antes de aplicarlo a la original. Una base parcialmente instalada o ya actualizada se rechaza; el script no intenta reinstalar tablas ni snapshots sobre datos existentes.

## Verificación esencial ejecutada

En la copia y después en la base original, con la cuenta SQL original de la aplicación y el UsuarioId real de admin:

- Permisos efectivos de los cinco módulos y estado activo de admin, sin cambio obligatorio de contraseña.
- Promoción aplicada y registrada en una venta sobre cliente/producto existente.
- Cotización convertida al crédito desde bodega conservando el pacto, sin reevaluar la promoción; replay de la misma factura.
- Cuenta por cobrar, abono, saldo cero, recibo y diferencia correcta del efectivo recibido en caja; replay del abono.
- Transferencia PREPARADA → DESPACHADA → RECIBIDA, stock local/global, tránsito y conciliación.
- Captura de CREATE/ALTER/DROP de TABLE y PROCEDURE; acceso SQL directo al texto denegado al login de la aplicación.

**Todas las operaciones de negocio y los objetos DDL de comprobación se revirtieron.** No se crearon usuarios QA, clientes o productos de prueba. Las comprobaciones finales encontraron cero cotizaciones, promociones, cuentas de crédito, abonos y transferencias de validación persistidos, y cero diferencias de conciliación. Por eso las listas nuevas inicialmente están vacías: las nuevas operaciones se registran a partir de ahora y los datos históricos continúan disponibles en sus pantallas originales.

CHECKDB y CHECKCONSTRAINTS pasaron después de la instalación; además se verificó el inicio real desde main y la conexión a SecureFinanceERP. La comprobación de contraseña se completó finalmente por el ingreso real del usuario en Chrome, sin automatizar ni leer el formulario. `resultado.json` contiene evidencia resumida sin secretos; los detalles operativos y el respaldo se conservan localmente fuera de Git.

## Uso y recuperación

Para el uso habitual, desde la carpeta principal en main:

```powershell
npm.cmd start
```

Abrir http://localhost:3000/login e ingresar admin con su contraseña habitual. `.env` conserva DB_NAME=SecureFinanceERP y PORT=3000. No ejecutar startIntegrationLab ni los constructores de laboratorio para esta presentación.

Para una repetición del procedimiento en una base original aún no actualizada, leer y revisar las herramientas antes de ejecutar: `original-upgrade.cjs prepare`, `original-upgrade.cjs rehearse`, `validate-original.cjs` y, solo con el ensayo aprobado, `original-upgrade.cjs apply`. El instalador está ligado al servidor inspeccionado y a un estado privado de respaldo; no es un instalador universal ni debe eliminarse ese estado para forzar una reaplicación.

La posibilidad de recuperación se acreditó restaurando el respaldo real a otra base y verificando su integridad. No se hizo una restauración sobre la original ni se probaron comandos destructivos de recuperación. Ante una incidencia posterior al COMMIT: detener la aplicación, conservar la base actual y sus respaldos/logs, restaurar primero en otra base con MOVE sin REPLACE y validar. Cualquier sustitución posterior de la base original requiere evaluar operaciones registradas desde el respaldo, preservarlas y planificar el corte; nunca sobrescribir automáticamente la original. El respaldo preactualización permanece sin sobrescribir.
