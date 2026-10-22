# SKU automático de Productos

El alta de Productos ofrece **Generar SKU automáticamente** como opción predeterminada y **Usar un SKU propio (manual)** como alternativa. Al guardar, la ficha y el mensaje de confirmación muestran el código definitivo devuelto por SQL Server. No se muestra ni reserva un código provisional en JavaScript. La edición conserva el comportamiento existente y nunca regenera automáticamente un código.

## Implementación y unicidad

La migración incremental `38_ERP_ProductoSKUAutomatico.sql` crea `dbo.SeqProductoSKU` y `dbo.sp_ERP_RegistrarProducto`. No modifica los procedimientos anteriores, códigos históricos, identidades, stock ni relaciones.

La secuencia se inicializa una sola vez por encima del mayor ProductoId, dentro de una transacción con bloqueo exclusivo de tabla (`TABLOCKX,HOLDLOCK`) y bloqueo de aplicación. En un catálogo con cuatro productos y último identificador 4, el primer candidato es `PRD-000005`. La asignación durante el alta utiliza `NEXT VALUE FOR`, nunca `MAX + 1`. La migración repetida conserva la posición de la secuencia.

El nuevo procedimiento valida `PRODUCTOS_ADMINISTRAR` antes de consumir la secuencia. Un bloqueo transaccional de aplicación serializa las altas del wrapper; la búsqueda con `UPDLOCK,HOLDLOCK` protege el código candidato frente a otros escritores. Si un código PRD ya existe, se consume el siguiente número. La restricción única existente en `Producto.Codigo` sigue siendo la garantía final, también para códigos manuales y clientes anteriores. La migración verifica ese índice antes de instalarse.

Después de elegir el código, el wrapper llama al alta anterior para conservar validaciones, auditoría y stock inicial cero. Solo se concede EXECUTE sobre el nuevo procedimiento a la cuenta de aplicación; no se concede acceso directo a la secuencia ni DML sobre Producto. Los errores 2601/2627 de duplicados siguen mostrando un mensaje seguro y conservan los campos del formulario.

El formato usa un mínimo de seis dígitos. Después de `PRD-999999` sigue `PRD-1000000`, sin truncar. Las secuencias pueden tener saltos por fallos, rollback o colisiones: un SKU identifica un producto y no representa una numeración fiscal sin huecos.

## Contrato de aplicación

- Alta sin `ModoCodigo`, o con `ModoCodigo=AUTOMATICO`: el backend ignora cualquier `Codigo` enviado y solicita generación en SQL.
- Alta con `ModoCodigo=MANUAL`: exige un `Codigo` válido, con el límite existente de 40 caracteres. Un modo desconocido se rechaza.
- Edición: exige el código y la versión existentes; usa `sp_ActualizarProducto` y no consume la secuencia.
- La respuesta de producto incluye `{ id, codigo }`. El frontend muestra `codigo` usando `textContent` y vuelve a consultar la ficha persistida.

## Migración y despliegue

**La migración 38 se instaló y probó únicamente en laboratorio. No está desplegada en `SecureFinanceERP` y no se reinició el backend principal.** El código de esta entrega requiere instalar 38 antes de arrancarlo; la comprobación de integración exige EXECUTE sobre `sp_ERP_RegistrarProducto` para impedir otro arranque con SQL incompatible.

Se creó la copia dedicada `SecureFinanceERP_SKU_20261021224833` a partir del laboratorio de integración existente, mediante backup COPY_ONLY con CHECKSUM, VERIFYONLY y restauración con archivos separados. Se aplicó solo 38 y se verificaron conservación de productos, facturas y Kardex e integridad CHECKDB. No se ejecutaron instaladores Full ni semillas.

Para un futuro despliegue, seguir el procedimiento coordinado de respaldo actual recuperable, ventana sin escrituras y conciliación; aplicar `38_ERP_ProductoSKUAutomatico.sql` en la base correcta antes del nuevo backend. Conservar las migraciones 33–37. La migración es aditiva y permite que clientes anteriores sigan usando el alta manual existente. No ejecutar `DeployIncrementalERP.ps1` esperando que instale 38: ese ejecutor corresponde al despliegue anterior 33–37.

## Validación ejecutada

- Preparación/restauración y migración 38 en copia aislada: PASS; productos anteriores completos conservados, sin cambios de stock o identidad.
- `node database/tests/ProductSKUIntegration.js`: PASS con la cuenta SQL real de aplicación. Comprueba alta automática, SKU definitivo, manual, colisión con código PRD reservado manualmente, duplicado 2627, dos altas automáticas concurrentes, dos manuales concurrentes del mismo código, RBAC antes de asignación, denegación de acceso directo a secuencia, conservación por hash de productos anteriores y conteos de documentos/relaciones, repetibilidad de 38 y numeración de siete dígitos. CHECKDB final aprobado.
- `node tests/browser/productSku.browser.js`: PASS en Chromium con servicios SQL reales del laboratorio. Comprueba el modo automático inicial, campo manual deshabilitado, alta automática y SKU persistido visible, cambio a manual, rechazo de duplicado sin perder campos y alta manual con código propio. Autenticación sustituida solo por `SESSION_FIXTURE_NOT_REAL_LOGIN`; no acredita login legítimo ni almacena contraseñas.
- `npm.cmd run check`: PASS.
- `npm.cmd test`: **88/88 PASS**, cero fallidas y omitidas. Incluye nuevas pruebas de interfaz HTTP, contrato backend, selección de modo, SKU definitivo y edición sin regeneración.
- `npm.cmd run test:ui`: PASS, regresión visual general con servicios simulados.
- `git diff --check`: PASS.

Los ejecutores guardan configuración y evidencia privada bajo `.data/`, fuera de Git. `PrepareProductSKULab.ps1` solo acepta un laboratorio de estabilización como origen; los ejecutores de escritura verifican el nombre de la copia SKU. El caso de siete dígitos cambia deliberadamente la secuencia de esa copia; no usar esa numeración QA como posición de arranque para la principal.

Las primeras invocaciones del ejecutor de integración se detuvieron antes de escribir por una incompatibilidad de opciones `sqlcmd` (`-h` con `-y 0`), corregida usando una anchura explícita. Los errores 2627 y 54101 posteriores son rechazos esperados y comprobados por las pruebas, no fallos ocultados.
