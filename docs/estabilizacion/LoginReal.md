# Comprobación acotada del login real

Resultado: **pendiente por ausencia de credenciales web locales utilizables**. El PR #11 permanece en borrador; no se acreditó un nuevo login SQL ni acceso autenticado a los cinco módulos en esta comprobación.

Se trabajó en `feature/estabilizacion-funcional-erp` con árbol inicialmente limpio. Se revisaron únicamente las fuentes locales previstas: el archivo ignorado `.data/qa-login.local.json`, las claves del entorno de la aplicación y la variable `WEB_ADMIN_PASSWORD` mencionada por el verificador local existente. El archivo no existe y la variable no está definida en los ámbitos de proceso, usuario o máquina. `.env` conserva las credenciales de conexión a SQL Server; estas no constituyen credenciales web de un usuario del ERP.

No se mostraron ni modificaron valores de credenciales. No se adivinaron contraseñas ni se utilizó autenticación simulada. Tampoco se repitió el intento con la contraseña académica que ya había fallado en la revisión anterior. Se solicitó únicamente la ubicación de una credencial local existente.

## Comprobaciones realizadas

- Conexión SQL real de la cuenta de aplicación: `DB_NAME()` confirma `SecureFinanceERP_Estabilizacion_20261021`.
- Inventario, Productos, Facturación, Notas de crédito y Garantías: sin sesión, los cinco endpoints redirigen a `/login` con HTTP 302 conforme al middleware existente. Esto demuestra protección anónima, **no acceso autenticado**.
- Sintaxis del nuevo verificador: `node --check tests/browser/loginAccess.browser.js`.
- No se ejecutaron operaciones de compra, venta, crédito ni garantía. No se repitieron las 79 pruebas ni las baterías SQL. No se modificó código funcional de la aplicación ni se detectó un fallo de integración atribuible al ERP.

[Resultado estructurado](evidencias/login-acceso.json).

## Reanudación

El verificador `node tests/browser/loginAccess.browser.js` usa todos los servicios originales, incluido el login SQL, y comprueba cookie HttpOnly, dashboard y renderizado autenticado con HTTP 200 de los cinco módulos. No escribe operaciones de negocio ni permite un modo de autenticación sustituida.

Acepta un archivo local existente mediante `ERP_QA_LOGIN_FILE`, o el archivo ignorado `.data/qa-login.local.json` con claves `usuario` y `password`. Como alternativa admite una variable existente `WEB_ADMIN_PASSWORD` y `WEB_ADMIN_USER` (usuario predeterminado admin). No imprime sus valores. La base está fijada a la copia aislada y se verifica la conexión antes de empezar.

Cuando se identifique la fuente local existente, ejecutar solo este verificador con Chromium, actualizar la evidencia y marcar el PR listo únicamente si el login y los cinco accesos pasan. No corresponde fusionar ni desplegar migraciones en `SecureFinanceERP`.
