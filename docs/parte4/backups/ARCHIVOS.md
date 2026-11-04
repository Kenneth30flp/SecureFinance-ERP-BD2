# Archivos de UC13

## Nuevos

- `src/modules/dba/backups/validation.js`: validación de entradas.
- `src/modules/dba/backups/routes.js`: rutas, sesión, permisos y CSRF.
- `src/modules/dba/backups/service.js`: RPC SQL parametrizado de web.
- `src/modules/dba/backups/planner.js`: cadena y comandos RESTORE.
- `src/modules/dba/backups/worker.js`: ejecución, catálogo, agenda, bloqueos y recuperación.
- `src/views/dba/backups/index.ejs`: interfaz de Administración.
- `src/public/css/parte4/backups.css`: diseño oscuro y adaptable.
- `src/public/js/parte4/backups.js`: solicitudes, referencias idempotentes y confirmación del plan.
- `database/parte4/backups/01_backups.sql`: tablas, permisos ERP, cola y procedimiento de BACKUP.
- `database/parte4/backups/02_permissions.sql`: concesiones SQL separadas.
- `scripts/parte4/backups/runner.js`: entrada independiente de HTTP.
- `scripts/parte4/backups/Install-Task.ps1`: instalación explícita de tarea Windows.
- `scripts/parte4/backups/Run-Task.ps1`: lanzamiento y código de salida.
- `scripts/parte4/backups/check.js`: verificación sintáctica de archivos UC13.
- `tests/parte4/backups/audit.test.js`: regresiones de seguridad, PITR, navegador simulado e integración HTTP.
- `docs/parte4/backups/AUDITORIA.md`: hallazgos, correcciones y alcance de la auditoría.
- `tests/parte4/backups/backups.test.js`: pruebas aisladas, sin SQL real.
- `docs/parte4/backups/README.md`: instalación, seguridad, operaciones y discrepancia C#.
- `docs/parte4/backups/VALIDACION.md`: resultados y matriz pendiente.
- `docs/parte4/backups/ARCHIVOS.md`: este inventario.
- `docs/parte4/backups/check-final.txt`, `test-final.txt`: salida real de verificaciones finales.

## Integración compartida mínima

- `server.js`: servicio inyectable y montaje de rutas UC13.
- `src/config/moduleCatalog.js`: entrada en Administración.
- `src/views/partials/navigation.ejs`: título del contexto de respaldos.
- `package.json`: incluye pruebas/check UC13 y comando del worker.
- `.gitignore`: excluye medios LOG/DIFF y certificados/llaves.

No se modificaron módulos de Dylan ni otros módulos de negocio. La entrega se publica mediante un commit exclusivo UC13 en feature/p4-edward-backups; no se agregan credenciales ni medios de respaldo.
