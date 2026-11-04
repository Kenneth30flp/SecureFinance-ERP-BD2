# Guion para el ingeniero y el informe de Rubén

1. Mostrar el estado de integración y distinguir pruebas reales de las pruebas unitarias.
2. Entrar con `admin` y su contraseña habitual. Mostrar ambos módulos dentro de Administración.
3. En LDF, explicar espacio lógico/físico, uso, VLF, modelo FULL e historial SQL. No ejecutar SHRINK ni cambiar el modelo de recuperación.
4. En Respaldos, mostrar FULL/DIFF/LOG, cola, actor, resultados y catálogo. Una solicitud no acredita por sí sola la creación del archivo.
5. Mostrar las evidencias SQL de laboratorio: FULL/DIFF/LOG VERIFICADO, pruebas de exclusión UC13/UC14 e idempotencia.
6. Mostrar el resultado PITR publicado: el registro `BEFORE_STOPAT` existe y `AFTER_STOPAT` no aparece en la base recuperada. Señalar que se utilizó un LOG generado por UC14 y que la original no recibió datos de demostración.
7. Mostrar las ocho rutas y capturas a tres anchos. Enfatizar sesión, CSRF y permisos efectivos SQL.
8. Mostrar el respaldo de protección, restauración independiente y preservación de filas históricas/firmas del despliegue, si figura aprobado en el estado final.
9. Explicar por separado tarea Windows, heartbeat y política SQL. Si la automatización figura deshabilitada, presentar su motivo y no afirmar que los backups programados están activos.
10. Registrar expresamente la discrepancia Node.js/C# y solicitar resolución académica del ingeniero, sin presentarla como ya aceptada.

No introducir ventas, compras, créditos, cotizaciones ni movimientos de inventario en la original para demostrar el sistema. Usar las evidencias y las bases de laboratorio conservadas. No mostrar archivos privados, contraseñas, hashes de usuarios ni la configuración secreta del worker.
