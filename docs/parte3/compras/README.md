# Compras: entrega del módulo 2, Parte III

Estado de la entrega: implementación de código y pruebas sin SQL terminadas;
validación real de SQL Server pendiente. No declarar el módulo desplegado ni
completamente funcional hasta superar el laboratorio descrito abajo.

## Funciones y recorrido

Órdenes con numeración `OC-<IDENTITY>`, proveedor y productos activos vinculados
por `ProductoProveedor`, costos pactados, cantidades enteras, aprobación
independiente, cancelación, historial, recepciones parciales/completas y libro
auxiliar de valoración. La interfaz incluye búsqueda paginada, alta, documento
imprimible, pendientes por producto, entregas documentadas e historial.
Reutiliza el módulo Proveedores; no crea otro catálogo ni administra pagos.

1. Un comprador prepara 1–100 productos del proveedor. SQL conserva nombre,
   NIT, SKU, descripción, cantidades y costos al crear la orden.
2. Envía el BORRADOR a PENDIENTE_APROBACION con motivo.
3. Otra persona con autorización vigente aprueba. Tener permiso de creación
   no concede aprobación; el creador no puede aprobarse aunque tenga ambos.
4. Una orden APROBADA admite entregas de productos pendientes. Pasa a
   PARCIALMENTE_RECIBIDA mientras queden unidades y a RECIBIDA al completarse.
5. CANCELADA solo es alcanzable desde BORRADOR, PENDIENTE_APROBACION o APROBADA.
   No se cancela ni modifica una orden con entregas. Las líneas son inmutables:
   una corrección comercial antes de recibir exige cancelar y emitir otra.

La numeración es única, no fiscal y puede tener huecos por rollback. Dos UUID
distintos representan dos órdenes distintas, aunque sus importes coincidan.
El documento de entrega no es una clave única universal: puede respaldar
varios productos o entregas. La deduplicación técnica utiliza el UUID, el hash
de contenido y la versión; no intenta adivinar duplicados comerciales.

## Migraciones y objetos propios

Aplicar **50–55 completas y en orden**, por lotes `GO` dentro de una única
transacción en una conexión del instalador. No ejecutar únicamente 50/51
sobre una instalación final: sus definiciones de etapa inicial serían
sustituidas posteriormente por 52/54. Los scripts exigen transacción externa.

| Archivo | Responsabilidad |
| --- | --- |
| `50_P3_COM_EstructuraOrdenesCompra.sql` | Cabecera, detalle, historial, restricciones, auditoría y permisos iniciales |
| `51_P3_COM_OperacionesOrdenesCompra.sql` | Crear, consultar, enviar, aprobar, cancelar e historial |
| `52_P3_COM_RecepcionesOrden.sql` | Entregas de orden, enlaces a recepción/Kardex, estados de recepción |
| `53_P3_COM_Valoracion.sql` | Libro derivado inmutable de promedio móvil y consultas |
| `54_P3_COM_ConsultasWeb.sql` | Listados, detalle con pendientes/entregas y selección comercial |
| `55_P3_COM_PermisosFinales.sql` | Denegaciones de tabla, columna y alteración de objetos propios |

Tablas, todas bajo `dbo`:

- `P3_COM_OrdenCompra`: `OrdenCompraId`, `Numero` calculado único,
  `ProveedorId`, snapshots `ProveedorNombre/ProveedorNIT`, `CreadorUsuarioId`,
  `FechaCreacion`, `Observaciones`, `Total DECIMAL(32,4)`, `Estado`, `Version`.
- `P3_COM_DetalleOrdenCompra`: PK `(OrdenCompraId,ProductoId)`, `SKU`,
  `Descripcion`, `Cantidad INT`, `CostoUnitario DECIMAL(19,4)` y
  `Subtotal DECIMAL(32,4)` calculado/persistido.
- `P3_COM_HistorialEstado`: identidad, orden, `OperacionId` único global,
  hash SHA-256, acción, estado anterior/nuevo, actor, fecha UTC, motivo,
  `VersionResultado`. Cada evento agrega auditoría a `Bitacora_Transacciones`.
- `P3_COM_RecepcionOrden`: UUID de entrega, orden, actor, fecha, documento y motivo.
- `P3_COM_AplicacionRecepcion`: orden/producto, entrega, cantidad, costo real
  de cuatro decimales, `RecepcionId`, `KardexId` único y UUID hijo único.
  FK compuestas vinculan la línea de orden, su cabecera de entrega y el detalle
  de recepción compartido. UPDATE/DELETE están bloqueados.
- `P3_COM_Valoracion`: PK `KardexId`, producto, saldo físico, valor anterior,
  costo aplicado, valor/promedio resultantes, completitud, razón, fecha de
  cálculo y actor. Valores `DECIMAL(36,8)`, costos/promedios `DECIMAL(25,8)`.

Procedimientos públicos con prefijo `dbo.P3_COM_`:
`Crear`, `Consultar`, `EnviarAprobacion`, `Aprobar`, `Cancelar`,
`ConsultarHistorial`, `Recibir`, `BuscarCatalogo`, `ActualizarValoracion`,
`ConsultarValoracion`. `Transicionar` es interno y tiene DENY EXECUTE directo.

Los comandos usan actor INT, UUID y versión BINARY(8), salvo creación que no
requiere versión anterior. El JSON de líneas contiene exactamente
`ProductoId`, `Cantidad`, `CostoUnitario`; este último es una cadena decimal.
`Recibir` añade documento y motivo. La firma detallada está en cada script y
en los parámetros tipados de `src/modules/compras/service.js`.

Rango reservado exclusivamente a Edward: 50–59. Esta entrega utiliza 50–55;
56–59 quedan disponibles según el árbol y las referencias locales revisadas.
No se consultó ni actualizó el remoto durante esta entrega; el integrador debe
confirmar la reserva al revisar el PR. No se utilizaron rangos ajenos.

## Seguridad, permisos y rutas

| Operación HTTP | Permisos empresariales |
| --- | --- |
| GET `/compras`, `/compras/:id` | `COMPRAS_CONSULTAR` |
| GET `/compras/nueva`, POST `/compras` | `COMPRAS_CREAR` |
| POST `/compras/:id/enviar` | `COMPRAS_CREAR` |
| POST `/compras/:id/aprobar` | `COMPRAS_APROBAR`; otro actor, validado en SQL |
| POST `/compras/:id/cancelar` | `COMPRAS_CANCELAR` |
| POST `/compras/:id/recibir` | `COMPRAS_RECIBIR` + `INVENTARIO_REGISTRAR` |
| GET `/compras/buscar/proveedores` | `COMPRAS_CREAR` + `PROVEEDORES_CONSULTAR` en SQL |
| GET `/compras/buscar/productos` | `COMPRAS_CREAR` + `PRODUCTOS_CONSULTAR` en SQL |
| GET `/compras/valoracion/:id`, POST `.../:id/actualizar` | `COMPRAS_CONSULTAR` |

La actualización de valoración es un cálculo derivado, sin ajustes de stock
ni edición de costos. Se permite al consultor y requiere POST con CSRF.
Los responsables de aprobar, cancelar o recibir deben tener también consulta
para usar el detalle web. Los creadores sin consulta entran directamente al
alta; no se les concede lectura implícita. Asignar permisos mediante la
administración de roles existente y renovar sesión después de cambios.
Las migraciones no asignan ningún permiso nuevo automáticamente a roles.

Autenticación existente, CSRF propio de sesión, `Cache-Control: no-store`,
actor exclusivamente desde `req.session.usuario.usuarioId`, identificadores
y JSON estrictos, parámetros `mssql` tipados y escape EJS. Ninguna entrada de
usuario se concatena en SQL. El SQL dinámico de permisos usa exclusivamente
identificadores del catálogo delimitados con `QUOTENAME`.

`securefinance_app` recibe EXECUTE en SP públicos, no DML/SELECT directo en
tablas propias. Hay DENY de columnas para impedir que un GRANT de columna
eluda el DENY de tabla, y DENY ALTER/TAKE OWNERSHIP. No usar db_owner,
db_datareader, db_datawriter, db_ddladmin, db_securityadmin ni sysadmin.
El permiso SQL de ejecución no sustituye `sp_ParteII_ValidarPermiso`: SQL
comprueba cuenta, roles y permisos activos en cada operación.

Como en los demás módulos, el login SQL es una identidad del backend, no del
usuario humano. Sus credenciales deben permanecer solo en el servidor: una
conexión SQL comprometida puede intentar invocar SP con otro actor. Esta
entrega conserva ese contrato compartido; no afirma resolver la suplantación
de actor desde un cliente SQL con credenciales de aplicación.

## Recepciones y concurrencia

`P3_COM_Recibir` serializa UUID mediante `sp_getapplock`, bloquea cabecera con
UPDLOCK/HOLDLOCK y compara ROWVERSION. Valida suma recibida con BIGINT y
rechaza productos ajenos, cantidades excesivas y referencias con otro hash.
Proveedor, productos ascendentes y relaciones se bloquean antes de recibir,
siguiendo el orden del receptor compartido. No se afirman cero deadlocks
frente a todos los módulos: los errores se revierten y no se reintentan solos.

Por línea llama **una vez** a `sp_RegistrarRecepcionCompra` de 34. Ese SP llama
al Kardex existente y actualiza stock; Compras solo guarda los enlaces.
No inserta Kardex ni actualiza Producto directamente. Una falla posterior
revierte cabecera de entrega, recepción compartida, Kardex, stock e historial
en la misma transacción. El servicio ignora resultados intermedios del SP
compartido y exige la confirmación final posterior al COMMIT exterior.

El contrato de recepción compartido admite dos decimales. Si el costo real
es representable exactamente, se pasa ese valor; si necesita cuatro, se pasa
NULL al campo heredado y se conserva el valor íntegro en la aplicación de
recepción propia. Nunca se redondea silenciosamente. Los consumidores de 34
seguirán viendo costo desconocido en esos casos; deben consultar el enlace
documentado para obtener cuatro decimales. No se cambia la firma compartida.

La interfaz conserva UUID y contenido en `sessionStorage` por actor/ruta
antes de enviar. Ante respuesta incierta, incluso después de recargar, solo
reenvía esa misma carga. No genera otro UUID ni reintenta automáticamente.
No borrar ese registro para repetir a ciegas; consultar la orden/historial.

## Promedio ponderado sin inventar historia

El libro auxiliar recorre Kardex en orden de ID por producto, desde su último
corte. Bloquea el producto para leer movimientos, recepciones y costos ya
confirmados. PK Kardex + bloqueo de producto impiden valorar dos veces un
movimiento, y no hay UPDATE/DELETE de valoraciones previas.

- Compra: costo real de la aplicación de orden o costo documentado de 34.
- Venta y ajuste de egreso: costo promedio comprobado anterior.
- Devolución: costo aplicado en la salida original mediante
  `DevolucionKardex → DetalleDevolucion → DetalleFactura → Kardex VENTA`.
- Apertura con stock, ingreso sin costo, ajuste de ingreso o devolución sin
  costo de salida: valor y promedio desconocidos; no usar `PrecioCosto` ni
  precio de venta como evidencia histórica.
- Un saldo cero comprobado permite reiniciar valor cero. Un ingreso posterior
  documentado puede volver a producir valoración completa. No se revalora
  retroactivamente una apertura desconocida con costos de compras recientes.

Con saldo previo cero: 10 × Q100 + 10 × Q120 = Q2200 / 20 = Q110. Las entradas
suman valor documentado. Las salidas prorratean el valor remanente usando
12 decimales internos y almacenan 8; no se multiplica un promedio redondeado
por cantidades enormes ni se ocultan valores negativos con un clamp a cero.
Los importes finales de orden se calculan exclusivamente en SQL; la vista
previa de formularios utiliza BigInt a cuatro decimales. No se usan Number
para dinero. El total pactado no agrega IVA, fletes ni pagos no definidos.

La valoración es **por actualización explícita**, no un trigger compartido:
la pantalla distingue corte actualizado de movimientos pendientes. Ventas,
devoluciones y ajustes posteriores se incorporan al pulsar Actualizar.
La ficha muestra saldo físico actual y promedio/valor al corte, no los
confunde. Automatizar ese refresco exige coordinar un punto de integración o
trabajo programado; no se reescribieron procedimientos de otros integrantes.

## Multibodega y otras dependencias

Actualmente se opera sobre Producto.Stock global. La UI lo declara y no
inventa una bodega. Node rechaza `BodegaId` y modalidad de pago no soportadas.

Dylan debe entregar catálogo real y permisos de bodegas, contrato de stock
por producto/bodega, apertura inicial, firmas de recepción/Kardex y política
de traslados/devoluciones. Acordar luego bodega por entrega, saldos pendientes,
hash/versionado de nuevos comandos y ámbito de valoración. Las entregas
históricas globales deben seguir globales; no asignarles una bodega ficticia.
No basta añadir un selector antes de que el receptor compartido soporte ese
contrato. Integrar posteriormente dentro de 56–59 o reservar una ampliación.

## Laboratorio SQL Express: preparación y bloqueo real

No se ejecutó ninguna escritura SQL, migración, restauración ni creación de
base durante esta entrega. La consulta de diagnóstico de solo lectura mostró
SQL Express y una identidad Windows con sysadmin. Esa identidad **no cumple**
el aislamiento de credenciales solicitado. No se utilizó para instalar.

Se reemplazó el ejecutor Docker de etapa 1 por un instalador para SQL Express:

1. Solo login SQL dedicado con CONNECT SQL, VIEW ANY DATABASE y CREATE ANY
   DATABASE; sin roles de servidor, permisos administrativos ni acceso a
   ninguna base de usuario anterior. Debe estar previamente provisionado por
   el administrador. No se crea ese login ni se cambia autenticación aquí.
2. Preflight de solo lectura: identidad de instancia, Express, permisos
   efectivos, bases visibles/estado/acceso, permisos en master/msdb y objetos
   personalizados, ausencia de servidores vinculados. Duda o permiso extra
   aborta. También rechaza acceso a bases antiguas Edward; el nombre no exime.
3. Genera nombre nuevo `SecureFinanceERP_P3_COM_LAB_<UUID>` y comprueba que no
   existe. No acepta un nombre de destino proporcionado por el operador.
4. CREATE DATABASE, marcador aleatorio e identidad comprobada antes de cada
   instalación; TRUSTWORTHY y DB_CHAINING deben estar desactivados.
5. Instala fuentes locales en esa base vacía: Full sin su bloque de creación
   de la base original, 15–26, 30–44 y 50–55. Se elimina únicamente el USE
   conocido en memoria, se rechazan instrucciones de servidor y no se usan
   respaldos ni semillas académicas. Usuario app WITHOUT LOGIN y fixtures
   sintéticos exclusivamente en la nueva base. Repite 50–55 para comprobar
   repetibilidad y verifica definiciones compartidas antes/después.
6. Ejecuta escenarios con `EXECUTE AS USER='securefinance_app'`, revierte el
   contexto aun ante error y conserva la base nueva para inspección. No DROP
   DATABASE, no RESTORE, no WITH REPLACE, no limpieza destructiva de bases.

Comando propuesto, **no ejecutado**, desde la raíz, una vez disponible la
credencial restringida y habilitada su conexión TCP a la instancia local:

```powershell
powershell.exe -NoProfile -File .\scripts\prepareComprasLab.ps1 -AuthorizeSqlWrites -ExpectedServer "$env:COMPUTERNAME\SQLEXPRESS"
```

Solicita la credencial sin mostrarla ni ponerla en argumentos o archivos.
El password solo existe temporalmente en el entorno del proceso hijo y se
restaura el entorno anterior al terminar. No carga `.env`, no usa autenticación
Windows ni la cuenta operativa. Requiere SQL Authentication y resolución de
SQLEXPRESS (SQL Browser/TCP); el script no cambia servicios ni red.
Si se ejecuta sin `-AuthorizeSqlWrites`, solo muestra las instrucciones y sale.
`npm run test:sql:compras` sin las guardas también aborta antes de conectar.

Una ejecución posterior necesita otra credencial sin acceso al laboratorio
anterior, o revisión administrativa de sus accesos: el ejecutor rechaza
cualquier base previa accesible, incluso un laboratorio conservado.
El ensayo completo, incluido el instalador nuevo, sigue sin ejecución real.

## Verificación y entrega

Ver [RESULTADOS.md](RESULTADOS.md) para comandos y resultados efectivamente
ejecutados; [REVISION_ETAPA1.md](REVISION_ETAPA1.md) para defectos corregidos;
[PATRONES_INTERFAZ.md](PATRONES_INTERFAZ.md) para diseño y accesibilidad;
[ENTREGA_GITHUB.md](ENTREGA_GITHUB.md) para mensaje de commit y PR preparados.
Las capturas y PDF locales son sintéticos y quedan en `.data/compras-ui`,
fuera de Git. No contienen datos de bases operativas.
