## Parte IV · Dylan · UC14 Administración LDF

### Implementación

- Panel `/dba/ldf`, navegación y diseño oscuro responsive del ERP.
- Métricas reales, archivos, VLF, modelo y diagnóstico de reutilización.
- Acción manual BACKUP LOG autónoma, cuentas separadas y procedimientos firmados.
- Validación de destino/cadena/ruta/permisos; CSRF, UUID, conciliación de respuesta perdida y bloqueo compartido.
- Historial propio + últimos LOG de msdb; alertas configurables y actualización manual.
- Instalador, actualización transaccional de firmas, laboratorio completo, guion para Dylan y capturas para Rubén.

### Validación

Ver `docs/parte4/ldf/PRUEBAS.md` y `evidencias/`. Incluye check, suite completa, SQL real en bases nuevas, Chromium responsive y restauración independiente FULL+LOG.

### Integración

Funciona sin el módulo Backups de Parte IV. Edward conserva el único programador automático; contrato de lock `SecureFinanceERP:BACKUP` (misma base, principal `public`) documentado en `ARQUITECTURA.md`.

Cambios de instalación limitados a objetos `P4_LDF_*`, dos permisos nuevos y certificados. Los tests crean datos exclusivamente sintéticos. No se modifica la base operativa ni procedimientos de módulos históricos; el CommandText DDL sigue en `nvarchar(max)`.

### Pendientes académicos

Confirmar con el ingeniero la implementación web Node/Express/EJS frente a C# y contrastar el PDF de Parte IV y observaciones de Parte III cuando se entreguen.
