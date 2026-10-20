# Validacion real SQL Server — Kenneth, Parte II

Fecha: 2026-10-18. Rama: feature/parte-ii-kenneth. Commit base: ec6899a.
Servidor: localhost,1433. Autenticacion Windows integrada. No se usaron
credenciales de .env para ejecutar SQL.

## Resultado

Base principal: `SecureFinanceERP_ParteII_Test_1792366006342_76351025`.
**28/28 casos principales PASS, 4/4 adicionales PASS y auditoria/historico
heredados PASS.** Migraciones 15–20 aplicadas dos veces; 49 modulos refrescados
mediante sp_refreshsqlmodule. Sin diferencias en el inventario de objetos de
la segunda pasada. No se modificaron los scripts 15–20 durante esta validacion.

## Aislamiento auditado antes de ejecutar

El ejecutor crea una base NUEVA con nombre validado y se niega a reutilizar una
base preexistente. master se utiliza exclusivamente para comprobar el nombre y
crear esa base. El preambulo master del Full se retira EN MEMORIA, no en el
archivo fuente. Sus USE se reemplazan por la base de pruebas. Cada lote posterior
selecciona esa base y comprueba DB_NAME y una propiedad extendida con token unico
de esta ejecucion. La auditoria final preparo 175 bloques sin ejecutar consultas.

Se rechazan cambios de contexto, SQLCMD embebido, referencias de tres/cuatro
partes y operaciones de servidor en los scripts cargados. Los modulos actuales
y sus SQL dinamicos fueron inspeccionados: no escriben en otras bases.
No hay DROP DATABASE ni creacion/cambio de logins. El Full no fue modificado.

Las pruebas activan ConfiguracionInventario.Habilitado solo dentro de sus
transacciones de fixtures; rollback lo restaura. La cuenta Windows requiere
CREATE DATABASE y administracion de la base nueva. El usuario securefinance_app
es local a la base aislada; no se cambian permisos de la base original.

## Ejecuciones y errores reales

1. Base `SecureFinanceERP_ParteII_Test_1792365382576_313642141`: las dos pasadas y el refresco pasaron;
   la suite se detuvo antes de sus casos por error **1046**:
   "Subqueries are not allowed in this context. Only scalar expressions are allowed."
   Causa: subconsulta en PRINT CONCAT del reporte. Se cambio por variable escalar.
2. Base `SecureFinanceERP_ParteII_Test_1792365906886_506275306`: 28 casos y regresion heredada PASS.
3. Base `SecureFinanceERP_ParteII_Test_1792365969648_960956203`: 28 casos PASS y S1 PASS; S2 detecto
   error **3930**: "The current transaction cannot be committed and cannot support
   operations that write to the log file. Roll back the transaction."
   La operacion directa habia sido rechazada, pero REVERT se ejecutaba antes del
   rollback en la limpieza del test. Se corrigio a ROLLBACK y despues REVERT.
4. Base principal: suite completa, complementarias y regresion PASS.
5. Repeticion independiente de los casos desde conexion nueva: error **1934**:
   "INSERT failed because the following SET options have incorrect settings:
   'QUOTED_IDENTIFIER'." El ejecutor completo ya lo heredaba de las migraciones;
   las pruebas independientes no lo declaraban. Se agregaron opciones SET
   explicitas en ambas suites. Nueva repeticion: 28/28 y S1–S4 PASS.

No se redujeron casos ni se flexibilizaron las expectativas. Las correcciones
fueron del ejecutor/reportes/configuracion de las pruebas; no de la aplicacion.
El filtro offline tambien excluyo de sus falsos positivos un rango numerico
8..128 en un comentario del Full.

## Resultados individuales

El codigo de rechazo corresponde a una excepcion esperada y comprobada, no a
un fallo del caso. Los mensajes completos, capturados de ERROR_MESSAGE(), estan
en [ParteIIKennethResultadosSQL.json](ParteIIKennethResultadosSQL.json).

| ID | Descripcion | Resultado | Rechazo esperado |
|---|---|---|---|
| 01 | Proveedor registrado | PASS | — |
| 02 | SKU unico | PASS | 2627 |
| 03 | Costo no negativo | PASS | 54102 |
| 04 | Ingreso compra | PASS | — |
| 05 | Egreso y saldo | PASS | — |
| 06 | Stock negativo | PASS | 54113 |
| 07 | Rollback posterior a stock | PASS | 547 |
| 08 | Reintento identico | PASS | — |
| 09 | Reintento conflictivo | PASS | 54112 |
| 10 | Cambio NIT | PASS | — |
| 11 | NIT duplicado | PASS | 2627 |
| 12 | Inactivacion y factura | PASS | — |
| 13 | Identidad de emision | PASS | — |
| 14 | DML set based y no-op | PASS | — |
| 15 | Permisos minimos | PASS | — |
| 16 | Compatibilidad Parte I | PASS | — |
| 17 | Cliente inactivo no vende | PASS | 52006 |
| 18 | Concurrencia optimista | PASS | 54103 |
| 19 | Fotografia insegura | PASS | 54102 |
| 20 | FK proveedor | PASS | 547 |
| 21 | RBAC actor | PASS | 54101 |
| 22 | Kardex bloqueado antes de apertura | PASS | 54110 |
| 23 | Kardex inmutable | PASS | 54201 |
| 24 | Snapshot inmutable | PASS | 54202 |
| 25 | NIT vacio | PASS | 54102 |
| 26 | Devolucion preparada | PASS | — |
| 27 | Factura anterior sin reconstruccion | PASS | — |
| 28 | Egreso por venta | PASS | — |

S1: consultas Kardex/clientes administrativos con saldos e inactivos comprobados.
S2: UPDATE directo de Stock como securefinance_app rechazado con **229**.
S3: actor ACTIVO sin permiso de inventario rechazado con **54101**.
S4: CHECK de costo rechaza DML directo negativo con **547**.
Los cuatro pasaron tambien desde una conexion nueva.

El caso 1 verifica ademas consultas/edicion de proveedor y producto, rowversion
actualizada y stock intacto. El caso 14 incluye INSERT, UPDATE, DELETE y no-op
de Cliente. AuditTests verifica cambios/eliminaciones multilinea de Producto,
JSON, funciones de Parte I e historico.

## Procedimientos y triggers

Se ejecutaron los 11 SP publicos de Parte II: consultar/registrar/actualizar
Proveedor y Producto; consultar clientes, actualizar NIT, inactivar cliente;
consultar Kardex y registrar movimiento. El helper RBAC fue consumido por ellos.
Tambien se ejecuto la venta existente con descuento, IVA, caja y comprobaciones
de factura/stock, y las consultas/funciones de auditoria e historico heredadas.
Los 49 modulos SQL se refrescaron sin error de enlace.

Se comprobaron los 11 triggers instalados: tres por Cliente, tres por Producto,
auditoria e inmutabilidad Kardex, captura/proteccion de identidad de Factura y
el trigger heredado de insercion de Factura.

El fallo forzado de CHECK posterior al UPDATE de stock demuestra rollback del
movimiento, producto y auditoria correlacionada. Los escritores verifican que
no quede transaccion abierta tras rechazo. Reintentos identicos no duplican
stock; payload distinto se rechaza; saldos negativos y referencias invalidas
se rechazan. Las transacciones de tests se revierten tambien en exito.

## Estado final de la base aislada

49 modulos, 11 triggers, 0 proveedores persistidos por pruebas, 0 movimientos
Kardex persistentes y Habilitado=0. Permanece una factura fixture inicial,
creada antes de las migraciones para probar preservacion historica.
No quedaron clientes/usuarios/roles de fixtures; los contadores IDENTITY y
rowversion pueden avanzar aunque las transacciones se reviertan.

## Base original: exclusivamente lectura

ReadOriginalState.sql solo utiliza SELECT, metadatos y SQL dinamico de SELECT.
Se compararon huellas SHA2_256 antes y despues, sin ejecutar SPs de negocio.

| Objeto | Filas antes/despues | Huella |
|---|---|---|
| Producto | 4 / 4 | Identica; incluye Stock |
| Factura | 14 / 14 | Identica |
| DetalleFactura | 19 / 19 | Identica |
| MovimientoCaja | 14 / 14 | Identica |
| Usuario_Rol | 5 / 5 | Identica |
| Rol_Permiso | 5 / 5 | Identica |
| Modulos SQL | 29 / 29 | Identica |

Kardex_Inventario y ConfiguracionInventario NO ESTAN INSTALADOS en la base real,
tanto antes como despues. Por tanto no se activaron ni se insertaron movimientos.
No corresponde afirmar que una fila real Habilitado=0 exista: no existe aun.
Las huellas completas y su comparacion verificable estan en el JSON.

## Archivos y verificaciones finales

Cambiados en esta fase: RunParteIIKennethTests.ps1, ParteIIKennethTests.sql y
documentacion Etapa1. Nuevos: ParteIIKennethSupplementalTests.sql,
ReadOriginalState.sql, este informe y ParteIIKennethResultadosSQL.json.
AuditTests.sql conserva la ampliacion de lista blanca de la etapa anterior.
No se modificaron Full, frontend, venta, devoluciones, garantias ni analitica.

npm.cmd run check PASS; npm.cmd test **43/43 PASS**; git diff --check PASS.
test:ui PASS con Chromium fuera del aislamiento, sin modificar la aplicacion.

Las cuatro bases creadas por esta ejecucion se conservan para inspeccion:
sus nombres exactos figuran en el JSON. No se elimino ni restauro ninguna base.
Cualquier limpieza posterior debe verificar nombre exacto y pertenencia a este
registro; no usar comodines para eliminar bases.

## Paso siguiente y limites

La arquitectura supera esta validacion funcional aislada y puede pasar a
**integracion controlada en pruebas**. Falta ejercitar concurrencia simultanea
entre dos sesiones, revisar planes con datos representativos y aprobar apertura
e integracion atomica con ventas antes de habilitar Kardex o migrar la base real.
No se implementaron los modulos de Edward/Jose ni se realizo corte de inventario.

Sin commit, push ni PR.
