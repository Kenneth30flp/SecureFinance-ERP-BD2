# Despliegue y recuperación

> Actualización del 21/10/2026: el despliegue local 33–37 ya se completó en la principal con respaldo actual restaurado y conciliado. Véase [Reparación e integración](ReparacionIntegracion.md). Las afirmaciones siguientes de que aún no se aplicó describen la entrega anterior.

## Antes de producción

1. Revisar el PR; no fusionar automáticamente. Confirmar que la base seleccionada es la correcta y que contiene las migraciones 01–32 aplicables. Comparar objetos con el respaldo; no ejecutar Full ni semillas.
2. Detener escrituras web y jobs que invoquen procedimientos de movimiento. Crear un backup completo COPY_ONLY con CHECKSUM, verificarlo y restaurarlo en otro nombre con archivos separados; ejecutar CHECKDB y conciliar. El respaldo de octubre usado en QA demuestra recuperación, pero **no sustituye un backup actual al desplegar**.
3. Conservar métricas anteriores: stock por ProductoId, cantidad de Kardex, facturas/caja, NC-1 y notas históricas, relaciones principales, tickets, permisos de la cuenta SQL y sus concesiones EXECUTE.
4. Aplicar por orden `33_ERP_ProductoProveedor.sql`, `34_ERP_RecepcionesCompra.sql`, `35_ERP_AplicacionesNotaCredito.sql`, `36_ERP_PermisosIntegracion.sql`, `37_ERP_VentaIdempotente.sql`, con un DBA autorizado y `sqlcmd -b -f 65001 -d <destino> -i <archivo>`. Revisar cada código de salida antes de continuar. No contienen USE, Full, borrado de datos ni habilitación automática del Kardex.
5. Asignar `NOTAS_CREDITO_APLICAR` exclusivamente al rol aprobado para registrar reembolsos. Ejemplo parametrizable ejecutado por DBA dentro de una transacción: buscar RolId activo por nombre y PermisoId por Codigo, verificar que ambos existen e insertar en Rol_Permiso solo si falta. No conceder db_owner ni DML. Revalidar todos los permisos efectivos, incluyendo posibles concesiones de columna preexistentes.
6. Desplegar código y SQL juntos. Reiniciar Node para renovar sesiones en MemoryStore y que cada operador inicie sesión obteniendo sus nuevos permisos. El nuevo código requiere 33–37; no admite desplegar solo los botones.
7. Con escrituras todavía suspendidas, comprobar consultas, permisos, integridad, que los totales y stock conservan sus valores previos, y que las asociaciones principales se mantienen. La única normalización de notas es Total=0 → LIQUIDADA y queda auditada.
8. Habilitar operación tras revisión. No ejecutar fixtures A–O en producción. La primera recepción real se concilia contra su documento, un único Kardex y el cambio de stock; la primera aplicación real contra su comprobante externo y saldo. Reintentar con la misma OperacionId cuando corresponda.

No se aplicaron estas migraciones en `SecureFinanceERP` desde esta rama. Ninguna escritura QA se ejecutó allí. Las consultas iniciales a la instancia y msdb fueron de lectura.

## Recuperación de despliegue fallido

- Mantener la aplicación fuera de escritura y guardar el error sin exponer SQL al usuario. Identificar qué archivo/lote terminó. Los bloques de creación de tablas manejan rollback; CREATE OR ALTER es atómico por objeto. Con `-b` no continuar después del primer fallo. Resolver precondiciones sin destruir objetos existentes y repetir únicamente el archivo necesario.
- Las migraciones son repetibles respecto de los datos. No recrean relaciones existentes, no reinician stock y no borran aplicaciones. Un conflicto de esquema debe resolverse comparando tipos/FK/índices y reconciliando información, nunca con DROP de tablas para “hacer pasar” la instalación.
- Antes de nuevas operaciones puede volverse al binario anterior **solo si** se revisan y restauran sus concesiones EXECUTE previas (37 deniega venta directa y 36 Kardex directo). Documentar esa reversión; dejar las tablas y libros nuevos intactos. No ejecutar una reversión automática de permisos.
- Tras registrar nuevas operaciones, preferir corregir hacia adelante. No eliminar recepciones, aplicaciones ni solicitudes para reusar UUID. La anulación/reversión documental requiere un procedimiento empresarial revisado, no una edición manual del libro.
- Si se requiere recuperación completa, restaurar el backup validado en un nombre nuevo, aplicar logs disponibles según el plan DBA y conciliar operaciones posteriores. Cambiar el destino de la aplicación solo después de revisión y aceptación de la pérdida potencial. Conservar la base anterior y las evidencias; este documento no autoriza sobrescribirla.

## Laboratorio reproducible

El laboratorio existente se conserva para inspección. `StabilizationTests.sql` exige el stock inicial 90 y no debe repetirse sobre la copia ya usada. Para repetir A–O, restaurar otra copia y adaptar de forma explícita y revisada las guardas de nombre de los scripts; no resetear datos del laboratorio ni los de producción. `ApplyStabilizationLab.ps1` acepta exclusivamente nombres de laboratorio y comprueba que los scripts no cambien contexto.

Las capturas QA reflejan stock posterior a varios escenarios; el caso 90→100 está demostrado por las aserciones SQL anteriores a las demás ventas/devoluciones. No se retocaron capturas para fingir ese saldo.
