# Parte II: Kenneth, etapa tecnica 1

Estado: **validado en SQL Server exclusivamente en bases aisladas**.
Resultado: 28/28 casos, 4 comprobaciones adicionales y regresion de auditoria PASS.
Ver [informe de validacion real](ParteIIKennethValidacionSQL.md) y
[resultados verificables](ParteIIKennethResultadosSQL.json).
No se aplicaron migraciones ni se habilito inventario en SecureFinanceERP.
Validacion local: npm check PASS, npm test 43/43 PASS, git diff --check PASS.
Parser ScriptDom de SSMS: sintaxis T-SQL validada offline, incluidos los cuerpos
dinamicos. Parser PowerShell: PASS. Esto no valida enlaces ni comportamiento en BD.
Stack: Node.js, Express, EJS, CSS, JavaScript y SQL Server. Sin C#.
No cambia frontend, procedimientos de venta, funciones analiticas ni instaladores de Parte I.

## Aplicacion y orden

No aplicar a la base real hasta revisar los scripts, respaldar y validar una copia aislada.
Seleccionar la base destino explicitamente: los incrementales no contienen `USE`.
Ejecutar con administrador autorizado, detener ante el primer error (`sqlcmd -b` o
`:ON ERROR EXIT`). No continuar lotes ni usar el Full sobre una base existente.

1. `database/15_ParteII_Preflight.sql`: dependencias, version SQL, datos y NIT equivalentes.
2. `database/16_ParteII_Catalogos.sql`: esquema, snapshots vacios, indices.
3. `database/17_ParteII_Kardex.sql`: estructura y configuracion DESHABILITADA.
4. `database/18_ParteII_Procedimientos.sql`: operaciones autorizadas.
5. `database/19_ParteII_Auditoria.sql`: triggers y captura de identidad futura.
6. `database/20_ParteII_Permisos.sql`: codigos RBAC y permisos SQL.

Cada archivo de escritura utiliza una transaccion y rollback. Los modulos se
instalan mediante `sp_executesql` dentro de esa transaccion para permitir CREATE OR
ALTER atomico y evitar errores de compilacion por columnas recien agregadas.
Esto es SQL de despliegue, nunca SQL concatenado desde Node.
Los scripts verifican existencia y varias caracteristicas de columnas, FK y checks;
no son un reconciliador universal de esquemas modificados manualmente. Comparar
el catalogo completo de la copia antes de aplicar a una instalacion divergente.
No reejecutar 08, 12_SalesDiscounts, 13 ni Full despues de estos incrementales:
pueden restablecer definiciones antiguas. El Full permanece como instalador de
Parte I y debe ir seguido de 15 a 20 en una instalacion nueva.

SQL Server 2017 o posterior: el dashboard actual utiliza STRING_AGG. Las fechas
persistidas son UTC. Lecturas nuevas paginadas (maximo 500), Kardex con intervalo
`[Desde, Hasta)`. No se agregan datos de demostracion a las migraciones.

## Modelo

- `Proveedor`: PK interna; NIT con unicidad por su forma normalizada, nombre, correo, telefono,
  direccion, fotografia, Activo, FechaCreacion UTC y Version rowversion.
- `Producto`: conserva Codigo como SKU, Precio como precio de venta, Stock y
  FechaCreacion. Agrega ProveedorId FK (proveedor principal), PrecioCosto,
  Fotografia, StockMinimo, PuntoReorden, GarantiaMeses y Version.
  Los datos antiguos mantienen proveedor/costo/garantia NULL: son desconocidos,
  no se inventan costos ni cobertura. StockMinimo y PuntoReorden empiezan en 5,
  conservando la interpretacion del dashboard actual. Reorden >= minimo >= 0.
  Altas nuevas por SP exigen proveedor activo, costo y cobertura explicitos.
- `Cliente`: conserva IDs, NIT y Activo. Agrega NITNormalizado, Version,
  FechaInactivacion y MotivoInactivacion. No elimina clientes ni sus referencias.
- `Factura`: ClienteNITEmision y ClienteNombreEmision inicialmente NULL. Un
  AFTER INSERT obtiene la identidad del cliente para facturas FUTURAS. Otro
  trigger impide cambiar cliente/identidad posteriormente. No cambia importes,
  detalles ni el SP de venta. Requiere triggers habilitados y nested triggers
  habilitado (configuracion normal de SQL Server); verificar en prevalidacion.
- `Bitacora_Transacciones`: se reutiliza, con ActorUsuarioId FK, OperacionId y
  Motivo opcionales. No se crea una segunda bitacora.
- `ConfiguracionInventario`: singleton interno, Habilitado=0. Ningun SP publico
  habilita Kardex. No modificar esta fila en la base real en esta etapa.
- `Kardex_Inventario`: PK BIGINT, producto/actor con FK, cantidad positiva,
  tipo que determina signo, fecha UTC, documento, motivo, saldos y clave
  idempotente. FK compuesta a detalle/producto cuando es VENTA. Esa FK requiere
  indice unico adicional `(DetalleFacturaId,ProductoId)`: el indice existente
  de factura/producto no sirve como clave referenciada para esta relacion.

Fotografia es una clave de 40 caracteres: UUID canonico en minusculas + `.jpg`
o `.png`. Ejemplo de formato: `00000000-0000-4000-8000-000000000001.jpg`.
SQL rechaza rutas, URLs y base64; no recibe bytes de imagen. El futuro backend
generara la clave, validara bytes/MIME/tamano, recodificara la imagen y guardara
en almacenamiento controlado. La referencia SQL no demuestra que el archivo
exista ni que su contenido sea seguro. No hay carga de archivos en esta etapa.

NIT: trim, mayusculas y retiro de guiones en los SP; solo caracteres ASCII
alfanumericos y longitud 1..25. `CF` es un identificador unico compartido, no una
excepcion para duplicados. Es validacion local, no verificacion ante SAT. La
prevalidacion detecta colisiones antes del indice normalizado y no fusiona ni
reescribe clientes. Sigue existiendo UQ_Cliente_NIT. Administradores SQL deben
usar el mismo contrato; no se concede DML directo a la aplicacion.

## Contratos de procedimientos

Todos los escritores usan XACT_ABORT, TRY/CATCH, BEGIN TRANSACTION, COMMIT y
ROLLBACK. Como la venta de Parte I, si fallan revierten tambien una transaccion
exterior: un llamador transaccional debe abortar la operacion completa. No hacer
reintentos automaticos tras timeout salvo con la MISMA clave idempotente Kardex.
Errores 54101 permiso; 54102 datos; 54103 version; 54104 referencia; 54110 gate;
54111 bloqueo; 54112 idempotencia conflictiva; 54113 stock/rango. Los errores
2601/2627 de unicidad se conservan para mapearlos a conflicto en el backend.

| Procedimiento | Parametros principales / resultado |
|---|---|
| sp_ConsultarProveedores | ActorUsuarioId, Desplazamiento=0, Limite=100; incluye inactivos y Version |
| sp_RegistrarProveedor | ActorUsuarioId, NIT, Nombre; Correo/Telefono/Direccion/Fotografia opcionales; ProveedorId OUTPUT |
| sp_ActualizarProveedor | Mismos datos, ProveedorId, VersionEsperada BINARY(8), Activo; reemplaza ficha completa |
| sp_ConsultarProductos | ActorUsuarioId, Desplazamiento, Limite, IncluirCosto=0; costo requiere ademas PRODUCTOS_ADMINISTRAR |
| sp_RegistrarProducto | ActorUsuarioId, Codigo, Descripcion, Precio, PrecioCosto, ProveedorId; StockMinimo=5, PuntoReorden=5, GarantiaMeses=0, Fotografia=NULL; ProductoId OUTPUT |
| sp_ActualizarProducto | Misma ficha, ProductoId, VersionEsperada, Activo; nunca acepta ni modifica Stock |
| sp_ConsultarClientesAdministracion | ActorUsuarioId, Desplazamiento, Limite; incluye clientes inactivos |
| sp_ActualizarNitCliente | ClienteId, NIT, ActorUsuarioId, VersionEsperada, Motivo; retorna NIT/Version |
| sp_InactivarCliente | ClienteId, ActorUsuarioId, VersionEsperada, Motivo; Activo=0, conserva factura |
| sp_ConsultarKardex | ActorUsuarioId, Desplazamiento, Limite, ProductoId/Desde/Hasta opcionales |
| sp_RegistrarMovimientoKardex | Contrato detallado a continuacion |
| sp_ParteII_ValidarPermiso | Helper interno; sin EXECUTE directo para securefinance_app |

Todos los resultados de escritores identifican el registro y devuelven Version
cuando corresponde. Una actualizacion requiere la rowversion leida; una venta
que cambie stock tambien cambia Version del producto y puede invalidar una
edicion administrativa anterior. Releer y resolver; no sobrescribir sin revisar.
Inactivar de nuevo con la version actual es no-op. Reusar una version antigua
se rechaza. Consultas de historia no filtran por Activo; la venta actual ya
rechaza clientes inactivos y se mantiene intacta.

### sp_RegistrarMovimientoKardex

Parametros obligatorios: ProductoId INT, TipoMovimiento VARCHAR(25), Cantidad
INT positiva, ActorUsuarioId INT, DocumentoRespaldo NVARCHAR hasta 100,
OperacionId UNIQUEIDENTIFIER, LineaOperacion INT positiva, Motivo NVARCHAR hasta
250. Opcionales: DetalleFacturaId INT, VersionEsperada BINARY(8).

Tipos: COMPRA (+), VENTA (-), AJUSTE_INGRESO (+), AJUSTE_EGRESO (-), DEVOLUCION (+).
AJUSTE requiere VersionEsperada y INVENTARIO_AJUSTAR; VENTA requiere permiso
VENTAS_REGISTRAR y detalle original compatible; compra/devolucion requieren
INVENTARIO_REGISTRAR. El gate se comprueba en todos los casos.

El SP toma applock transaccional por operacion/linea, bloquea producto por PK
con UPDLOCK/HOLDLOCK, calcula en BIGINT, rechaza saldo negativo/desbordamiento,
actualiza Stock UNA vez e inserta Kardex. Devuelve la fila original en reintento
identico sin repetir stock/auditoria; misma clave con datos distintos se rechaza.
Unicidad por operacion/linea y por detalle de venta refuerza esos bloqueos.
No hay parametro Stock libre ni procedimiento de borrado/correccion de Kardex.
Un trigger impide UPDATE/DELETE; ajustar con movimiento compensatorio.

No es un Kardex valorizado: PrecioCosto del catalogo no representa por si solo
el costo historico de cada entrada ni implementa promedio/FIFO.

## Auditoria y contexto

Se reemplazan por CREATE OR ALTER los triggers existentes de UPDATE/DELETE de
Producto; se agrega INSERT. Cliente tiene INSERT/UPDATE/DELETE. No-op no genera
evento: compara JSON completo de campos relevantes en binario, excluyendo
rowversion. Soporta varias filas y cambios NULL. Inactivacion es un UPDATE,
sin segundo evento artificial. Kardex tiene auditoria propia de INSERT: evento
de documento y cambio de Producto son dos hechos distintos, correlacionados.
El trigger actual de INSERT de Factura permanece intacto.

Los escritores limpian SESSION_CONTEXT al entrar, validan usuario activo y
permiso vigente en BD, establecen actor/operacion/motivo y los limpian en exito
y error. DML administrativo sin ese circuito conserva actor NULL y usuario SQL.
SESSION_CONTEXT no es autenticacion: el futuro backend debe obtener ActorUsuarioId
EXCLUSIVAMENTE de la sesion autenticada; nunca del body/query del navegador.
La cuenta SQL compartida es una frontera de confianza: quien posea esa cuenta
puede invocar procedimientos con IDs autorizados. No dar acceso SQL al navegador.
No usar contexto read_only en conexiones del pool ni operaciones simultaneas
en una misma conexion. Un fallo de auditoria revierte la transaccion de negocio.

## Permisos

Codigos nuevos: INVENTARIO_CONSULTAR, INVENTARIO_REGISTRAR, INVENTARIO_AJUSTAR,
PRODUCTOS_CONSULTAR, PRODUCTOS_ADMINISTRAR, PROVEEDORES_CONSULTAR,
PROVEEDORES_ADMINISTRAR, CLIENTES_CONSULTAR, CLIENTES_ACTUALIZAR_NIT,
CLIENTES_INACTIVAR. No se asignan automaticamente a ningun rol ni se reactivan
permisos existentes. Acordar matriz y asignar por administracion autorizada.

20 requiere usuario securefinance_app existente; concede EXECUTE solo a los
11 procedimientos publicos, no al helper. DENY DML/SELECT de tablas cubiertas;
los modulos estaticos dbo usan cadena de propiedad, conservando Parte I.
Verificar roles heredados, concesiones de columna y privilegios del login real:
sysadmin/propietarios pueden eludir DENY. No usar esas cuentas desde Node.
Hashing, cookies, sesiones, CSRF, login y contrasenas no se modifican.

## Corte pendiente e integracion del equipo

**No habilitar movimientos en produccion con la venta antigua activa.** La
venta actual sigue descontando stock sin Kardex por exigencia de esta etapa.
Antes de activacion: detener escritores, conciliar y registrar apertura real,
aprobar forma de representar saldos iniciales, integrar venta y reanudar.
No se implemento apertura ni se insertaron saldos. Sin apertura, Kardex es un
libro de movimientos posterior a activacion, no una reconstruccion del pasado.

Kenneth/Edward: reemplazar el UPDATE Stock de venta por el mecanismo central,
no agregar otra resta. Conservar orden ascendente de productos, integrar despues
de obtener DetalleFacturaId y mantener factura/detalle/caja/Kardex/auditoria
en la MISMA transaccion. Evitar inversion de orden de bloqueos y probar dos
sesiones reales. La clave Kardex no hace idempotente toda la solicitud HTTP de
venta: hace falta clave comercial estable a nivel de factura.

Edward: documento de devolucion/nota/ticket con IDs y FK reales, cantidades
acumuladas no mayores a la venta, stock solo para unidades aceptadas vendibles,
claves estables por movimiento. DocumentoRespaldo es una referencia comprobable
por operador, no una FK a tablas futuras inexistentes. Antes de habilitar
devoluciones debe agregar el enlace FK concreto de su documento al Kardex.
No se implementan devoluciones, notas de credito ni garantias. MovimientoCaja
actual solo admite un INGRESO por factura: no usarlo para egresos sin diseno
compensatorio aprobado. GarantiaMeses actual tampoco reconstruye cobertura
historica: falta snapshot de cobertura por detalle en la integracion posterior.

Jose: puede consumir ProductoId/Codigo/Descripcion/Stock/minimo/reorden,
ProveedorId, ClienteId, Factura/Detalle y movimientos fechados. Funciones y
dashboard ejecutivo quedan a su cargo, publicados mediante SP autorizados,
sin SELECT directo para Node. Definir metricas netas de devoluciones, IVA y
periodos; evitar multiplicacion de importes por joins de detalle/tickets.
fn_ObtenerHistoricoVentas de Parte I sigue mostrando nombre ACTUAL del cliente;
la identidad de emision ya queda preservada en columnas nuevas para adaptar
reimpresiones/consultas posteriormente. Facturas previas conservan snapshots
NULL; nunca presentar el nombre actual como reconstruccion historica cierta.

## Pruebas SQL y ejecutor aislado

`database/tests/ParteIIKennethTests.sql`: 28 casos con fixtures transaccionales
y rollback; se niega a ejecutarse en SecureFinanceERP y exige prefijo de prueba.
Cubre proveedor, SKU, costo, ingreso/egreso, saldo negativo, fallo posterior a
UPDATE Stock, idempotencia identica/conflictiva, NIT, baja, snapshots, no-op,
auditoria multirregistro, EXECUTE AS, venta con descuento/IVA/caja, cliente
inactivo, version obsoleta, fotografia insegura, FK, RBAC, gate e inmutabilidad.

Ejecutor opcional (requiere autorizacion adicional para crear BD de pruebas):

```powershell
& .\database\tests\RunParteIIKennethTests.ps1 -Server 'INSTANCIA_AUTORIZADA' -Run
```

Autenticacion Windows; `-TrustServerCertificate` solo si corresponde al entorno.
Crea una base NUEVA SecureFinanceERP_ParteII_Test_UUID, instala Parte I alli,
aplica 15..20 dos veces, verifica definiciones de Parte I, stock y facturas,
luego los 28 casos. No usa .env. Conserva la base para inspeccion y no la borra
automaticamente. El archivo SQL temporal se elimina al finalizar. Las capturas
y datos privados no participan. Los IDs/rowversion pueden avanzar aun con rollback.

Tambien prepara la ejecucion de AuditTests.sql heredado en esa base aislada.
Su lista blanca JSON admite los campos nuevos de Producto solo cuando existe
el esquema Parte II; mantiene la prohibicion de secretos y columnas inesperadas.
Este es el unico archivo existente modificado: una prueba SQL, no la aplicacion.

Antes de aplicar en real quedan pendientes permisos del login efectivo,
migracion de copia con datos representativos, concurrencia de
dos sesiones (misma clave/diferente producto, ultima unidad, NIT simultaneo),
planes/indices y aprobacion de corte. Las pruebas Node no compilan T-SQL ni
demuestran que estas migraciones hayan pasado en SQL Server.
