# Revision tecnica de Compras y ampliacion final

Esta revision corrige codigo local. Ninguna correccion se aplico a una base
existente. La comprobacion SQL real permanece pendiente; ver README.md.

## Problemas resueltos

- El laboratorio previo dependia de Docker y un respaldo. Se sustituyo por
  instalacion nueva en Express, login dedicado, permisos efectivos minimos,
  rechazo de acceso a bases anteriores, marcador y prefijo obligatorio. No
  acepta el usuario Windows sysadmin disponible. No restaura ni elimina bases.
- DENY de tabla no cubria GRANT de columna: denegaciones por columna, ALTER y
  TAKE OWNERSHIP en objetos propios; no se asignan permisos de negocio a roles.
- Preflight de etapa 1 debil: verifica tipos/precision, PK/FK/CHECK confiables,
  unicidad y contexto transaccional. No repara esquemas arbitrarios a ciegas.
- Lecturas de catalogo sin orden estable: producto ascendente, locks mantenidos
  hasta commit, cabecera UPDLOCK/HOLDLOCK, UUID serializado. Recepcion alinea
  proveedor/producto/relacion con el SP compartido. Deadlocks entre otros
  modulos siguen siendo posibles: rollback y reintento explicito con UUID.
- Confirmaciones prematuras: comandos propios confirman despues del commit;
  receptor compartido emite resultados intermedios que el servicio descarta.
- Truncamientos/decimales: JSON estricto, enteros INT, costo cadena DECIMAL19,4,
  subtotal/total SQL, calculo visual BigInt, rechazo de respuestas monetarias
  numericas que pudieran perder precision. El cuerpo HTTP de Compras admite
  64 KB para 100 lineas; se conserva el limite anterior en los otros modulos.
- Autoaprobacion y permisos conflados: permiso de aprobacion propio, actor
  de sesion y validacion SQL del creador distinto del aprobador.
- Recepcion duplicada: no se llama Kardex despues de recibir. Se enlaza el
  movimiento ya emitido, PK/UNIQUE evitan doble aplicacion y se comprueba
  pendiente bajo lock de orden. Cualquier error revierte efectos compartidos.
- Costos heredados de dos decimales: no redondear a escondidas; conservar costo
  real cuatro decimales y NULL en campo legacy cuando no es representable.
  La comparacion de representabilidad trunca solo para comparar, evitando el
  overflow de ROUND al procesar el maximo DECIMAL19,4.
- Valoracion: no tomar PrecioCosto ni precio de venta como costo historico.
  Desconocidos permanecen NULL, devoluciones consultan la salida original,
  egresos prorratean saldo con precision interna; no clamp que oculte errores.
- Conflictos entre comandos desde pantalla: capturar UUID/carga antes de
  transmitir, conservar ante respuesta incierta y recarga, no reintentar solo.
  La recuperacion permite reenviar aunque el formulario recargado este vacio.
- Catalogo de navegacion: entrada disponible sin identificadores duplicados,
  ruta de alta para creador sin consulta y contexto compartido de topbar.
- Historiales potencialmente grandes: paginacion de ordenes, busquedas,
  entregas de orden, eventos de estado y valoraciones; 50 + fila testigo
  (catalogos 10 + testigo), sin calcular saldos desde la pagina parcial.

## Riesgos pendientes

- Ejecutar el laboratorio completo de Express con credencial aceptable:
  compilacion T-SQL, permisos efectivos, concurrencia, rollback y precision
  no pueden certificarse con tests de Node o inspeccion de fuentes.
- Administrar asignacion de permisos de roles y apertura/habilitacion de
  inventario fuera del modulo. No activar inventario operativo automaticamente.
- Consumidores antiguos ven costo NULL cuando la recepcion necesita cuatro
  decimales. El libro propio conserva el costo preciso; coordinacion necesaria
  antes de ampliar el contrato compartido.
- Valoracion al corte actualizada explicitamente; no es un cierre contable ni
  un motor de costos por bodega. No corrige retroactivamente datos historicos.
- Idempotencia protege reintentos de un UUID, no detecta todos los duplicados
  comerciales deliberados con UUID distintos.
- Credenciales SQL compartidas del backend deben permanecer privadas; SQL
  recibe el actor conforme al contrato comun y no autentica al humano por login.
- Contrato real de multibodega de Dylan pendiente; no se inventaron bodegas.
- Reserva 56-59 libre en referencias locales; estado remoto no actualizado.
