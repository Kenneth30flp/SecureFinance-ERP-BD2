# Despliegue local seguro de SKU automático — 21/10/2026

**Completado:** migración incremental 38 instalada en `SecureFinanceERP`, backend compatible funcionando y guardado automático validado exclusivamente en laboratorio. Se conserva `feature/estabilizacion-funcional-erp`; no se fusiona el PR #11.

## Estado inicial comprobado

- Árbol limpio en `a54f00b4d8a9e9d8458a7621f513bbe07e010ae5`.
- Node `v24.14.0`, ejecutable `C:\Program Files\nodejs\node.exe`, proceso ERP 29864 escuchando en `127.0.0.1:3000`.
- El proceso conservaba el arranque anterior a la mejora de SKU. El log de arranque identificaba carpeta, principal y cuenta. Una conexión real con la configuración existente confirmó `SecureFinanceERP` / `securefinance_app`.
- La inspección administrativa confirmó que faltaban tanto `sp_ERP_RegistrarProducto` como `SeqProductoSKU`: 38 no estaba instalada. No se asumió que la copia de laboratorio fuera la principal.

## Respaldo, restauración y compatibilidad

Se creó un respaldo completo **actual**, `COPY_ONLY WITH CHECKSUM`, de `SecureFinanceERP`; pasó `RESTORE VERIFYONLY WITH CHECKSUM` y restauración con archivos separados en `SecureFinanceERP_SKU_20261021230106`. La ruta exacta del respaldo y las evidencias se conservan en `.data/sku38-deployment.json`, fuera de Git.

La copia pasó `DBCC CHECKDB` y `DBCC CHECKCONSTRAINTS`. Se compararon cantidad y SHA-256 del contenido completo, ordenado por clave primaria, de las **29 tablas dbo**, incluyendo productos, facturas y detalles, Kardex, créditos, proveedores, relaciones, garantías, usuarios, permisos y auditoría. Se cotejó antes del respaldo, después de restaurar y contra la principal. No se guardaron datos sensibles en el informe: solo nombres, cantidades y hashes.

Se aplicó exclusivamente `38_ERP_ProductoSKUAutomatico.sql` en la copia actual. El procedimiento se cotejó con la definición revisada; la secuencia se comprobó por tipo, incremento y ausencia de ciclos. Las 29 tablas permanecieron idénticas y CHECKDB siguió correcto. Se verificó EXECUTE efectivo para la cuenta de aplicación y ausencia de INSERT directo o consumo directo de la secuencia.

Después de esa conciliación, las pruebas de escritura se limitaron a la copia:

- `ProductSKUIntegration.js`: alta automática, código manual, colisiones PRD, duplicados, concurrencia automática y manual, RBAC, privilegios mínimos, conservación de productos anteriores, repetibilidad y códigos de siete dígitos: PASS.
- `productSku.browser.js`: modo automático predeterminado, alta y código persistido visible; modo manual, duplicado sin perder campos y alta manual: PASS con SQL real.
- La sesión del navegador es una fixture QA identificada, no una comprobación del login legítimo. No se cambiaron credenciales.

## Ventana sin escrituras y aplicación principal

Se preparó una copia privada del código compatible anterior `1c57874` para recuperación, sin activarla. Se comprobó la identidad del proceso ERP, ausencia de solicitudes SQL activas y de transacciones de escritura, y se detuvo únicamente el PID 29864. El ejecutor rechazaba continuar si encontraba sesiones activas contra la principal.

La principal pasó a `RESTRICTED_USER WITH NO_WAIT` durante el despliegue. Antes de aplicar 38 se repitió la comparación de las 29 tablas contra el respaldo recuperado. Solo se ejecutó el archivo incremental 38, sin otros instaladores. Después se verificaron nuevamente CHECKDB, restricciones y los mismos hashes: **ninguna fila histórica cambió**.

Terminadas las actualizaciones se restauró `MULTI_USER` y se comprobó por impersonación el permiso efectivo `EXECUTE` de `securefinance_app` sobre `dbo.sp_ERP_RegistrarProducto`. No se alteraron logins ni contraseñas. El ejecutor comprueba si 38 ya coincide con la versión revisada y, en ese caso, la omite sin reaplicarla ni reiniciar la secuencia.

## Backend y verificación final

Se arrancó `node server.js` desde la carpeta y configuración originales, con el código compatible `a54f00b` de la mejora. Nuevo PID **15372**, Node **v24.14.0**, escucha `127.0.0.1:3000`; `/health` respondió `status: ok`. El log de arranque registró `SecureFinanceERP` y `securefinance_app`, y `sys.dm_exec_sessions` confirmó esa base para el PID 15372. Los commits posteriores de esta entrega contienen únicamente el ejecutor y documentación.

`VerifyERPReadOnly.js --main` pasó con servicios SQL reales y sesión Express QA: Inventario, Productos y Proveedores cargaron productos, existencias, Kardex, fichas de edición, directorio y fotografías. También pasaron las restantes rutas existentes, sin mensajes de fallo de carga. La comprobación de datos se hizo por lectura; no se enviaron altas, compras, ventas ni otras operaciones comerciales a la principal.

Estado final: principal **ONLINE / MULTI_USER**, 4 productos y 220 unidades, sin cambios respecto al respaldo actual. La secuencia principal quedó inicializada en 5; las pruebas de siete dígitos solo alteraron la secuencia de laboratorio. No se ejecutó una alta de prueba para consumir el primer SKU principal.

## Herramienta y alcance

`database/tests/DeployProductSKU38.ps1` permite Inspect, Prepare, Laboratory y Deploy. Protege el archivo por SHA-256 entre preparación y despliegue, rechaza instalaciones parciales o definiciones incompatibles, exige conciliación y prueba de guardado en la copia, y no ejecuta 33–37 ni Full. Las etapas de escritura requieren acceso DBA integrado; las verificaciones de aplicación utilizan la cuenta real limitada.

No se repitió la regresión general de 88 pruebas porque no cambió el código funcional validado. Se ejecutaron las comprobaciones dirigidas del respaldo, integridad, migración, permisos, guardado aislado, concurrencia, navegador, arranque y lectura de módulos, además de `git diff --check`.
