# Integración real de Compras — 29 de octubre de 2026

Base del código: `main`, `d717615`. Aplicación: carpeta original, `npm.cmd start`, `http://localhost:3000`. Base final: exclusivamente `SecureFinanceERP`, login SQL `securefinance_app`.

## Resultado verificado

- Antes del despliegue no existían objetos `P3_COM_*` ni permisos `COMPRAS_*` en la base original.
- Los cinco módulos previos pasaron operaciones reales antes del cambio y después del despliegue: Cotizaciones, Promociones, Créditos, Multibodega y Auditoría DDL. Las pruebas incluyen venta con promoción, conversión de cotización a crédito, abono, transferencia completa y captura de seis eventos DDL. Todas sus operaciones de prueba se revirtieron.
- Se creó un respaldo completo nuevo `SecureFinanceERP_PreCompras_20261029213655_23983d.bak` con `COPY_ONLY,CHECKSUM`; pasó `RESTORE VERIFYONLY WITH CHECKSUM` y restauración real en `SecureFinanceERP_P3_Rehearsal_20261029213655_23983d`. La copia pasó `CHECKDB` y conciliación de Multibodega. El respaldo y la copia se conservaron.
- Únicamente en la copia se ajustó la propiedad de autorización de Multibodega para enlazarla a su propio nombre. No se reutilizó una base de demostración ni se ejecutó el instalador completo.
- Se instalaron 50, 51, 52, 53, 54 y 55, en ese orden, dentro de una sola transacción, primero en la copia y después en la original. El instalador comparó huellas de cada fila preexistente, incluidas sus multiplicidades, antes de confirmar. Un cambio o pérdida habría impedido el commit.
- Las pruebas reales, ejecutadas con los permisos efectivos de `securefinance_app`, pasaron creación, envío, aprobación independiente, rechazo de autoaprobación aun con permiso de aprobar, cancelación, recepción parcial y completa, reintento idempotente, rechazo de exceso y versión obsoleta, denegación por permisos y protección de tablas.
- Dos recepciones de diez unidades a costos 100 y 120 produjeron stock 20, valor 2200 y promedio 110. Se verificaron dos entradas de Kardex, dos entradas de ledger local, stock central y conciliación global/local sin diferencias.
- Los actores de prueba fueron usuarios existentes; la autorización temporal del aprobador, productos y documentos se revirtieron mediante `ROLLBACK`. No se instalaron usuarios QA en ninguna base. Las secuencias de identidad pueden presentar saltos normales de las transacciones revertidas.
- `CHECKDB`, `CHECKCONSTRAINTS` y conciliación final pasaron. Se compararon dentro de SQL los bytes de hash y salt, fechas de cambio de contraseña, cuentas, roles y membresías contra la copia: sin diferencias. Ningún valor de contraseña, hash o salt se exportó. También se comprobó que las definiciones SQL compartidas permanecieran intactas.
- El usuario ingresó personalmente como `admin` con su contraseña habitual. La verificación inspeccionó únicamente las páginas autenticadas y el resultado exitoso de acceso en SQL; no inspeccionó campos de contraseña, solicitudes de autenticación ni capturas de pantalla.
- Respondieron HTTP 200 con cuenta `admin`: `/cotizaciones`, `/compras`, `/promociones`, `/creditos`, `/multibodega`, `/auditoria/ddl`, además de `/modulos` y `/compras/nueva`. Los seis enlaces estaban presentes en el centro de módulos.
- `npm.cmd test`: 259 pruebas aprobadas. `npm.cmd run check`: aprobado.

## Corrección aplicada

La migración 55 asigna de forma aditiva al rol Administrador existente los cinco permisos `COMPRAS_CONSULTAR`, `COMPRAS_CREAR`, `COMPRAS_APROBAR`, `COMPRAS_CANCELAR` y `COMPRAS_RECIBIR`. No crea cuentas, no modifica contraseñas y no elimina permisos o roles. La regla SQL que impide al creador aprobar su propia orden sigue vigente. Para aprobar una orden creada por `admin`, otro usuario debe contar con el permiso correspondiente.

## Herramientas y evidencias

Los scripts `scripts/deployment/compras-upgrade.cjs`, `compras-operations.cjs`, `verify-compras-browser.cjs` y `compras-final.cjs` separan preparación, ensayo, aplicación y verificaciones. `compras-upgrade.cjs` rechaza instalaciones parciales, repetición implícita, cambios del plan y aplicación sin ensayo satisfactorio. No debe volverse a ejecutar `prepare`, `rehearse` o `apply` sobre este despliegue ya completado.

Las evidencias detalladas y la ruta del respaldo están en `.data/compras-upgrade/`, excluido de Git. Se reutilizan las primitivas SQL del despliegue anterior, sin invocar su instalador. La validación de cinco módulos acepta una copia explícita sin sobrescribir el estado del despliegue anterior.

Verificación de navegador: `2026-10-29T21:43:17Z`. El proceso final informa la carpeta original y `SecureFinanceERP`; no apunta a la copia de ensayo.

## Reanudación después de la interrupción

La revisión de solo lectura confirmó que las seis migraciones ya estaban aplicadas: 50 (órdenes e historial), 51 (operaciones), 52 (recepciones), 53 (valoración), 54 (consulta de catálogos web) y 55 (protecciones y asignación aditiva de permisos). Se encontraron seis tablas, once procedimientos y siete triggers de Compras, todos los permisos esperados y cero diferencias de Multibodega. No se repitió ninguna migración.

`npm.cmd test` había finalizado con código 0, 259 aprobadas y ninguna fallida; no quedó interrumpido. La comprobación final SQL se volvió a ejecutar satisfactoriamente, conservando el respaldo y la copia del ensayo.

El error `CimException HRESULT 0x80041003` de `Get-NetTCPConnection` correspondía a acceso denegado al proveedor CIM bajo el entorno restringido. Se utilizó `netstat -ano -p tcp`, consulta HTTP y el registro `ERP_RUNTIME` para verificar el puerto y la aplicación, sin modificar permisos del sistema, firewall ni controles de seguridad. Tras resolver un proceso previo que ocupaba 3000, se dejó una única ejecución persistente de `npm.cmd start`, iniciada con ventana oculta desde la carpeta original. Los registros privados están en `.data/compras-upgrade/server.stdout.log` y `server.stderr.log`.
