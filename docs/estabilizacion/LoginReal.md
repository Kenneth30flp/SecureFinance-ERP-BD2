# Comprobación acotada del login real

Resultado: **login real pendiente: venció el plazo de ingreso manual sin confirmar una sesión autenticada**. El PR #11 permanece en borrador; no se acreditó acceso autenticado a los cinco módulos en esta comprobación.

Se trabajó en `feature/estabilizacion-funcional-erp` con árbol inicialmente limpio. Se revisaron únicamente las fuentes locales previstas: el archivo ignorado `.data/qa-login.local.json`, las claves del entorno de la aplicación y la variable `WEB_ADMIN_PASSWORD` mencionada por el verificador local existente. El archivo no existe y la variable no está definida en los ámbitos de proceso, usuario o máquina. `.env` conserva las credenciales de conexión a SQL Server; estas no constituyen credenciales web de un usuario del ERP.

No se mostraron ni modificaron valores de credenciales. No se adivinaron contraseñas ni se utilizó autenticación simulada. Tampoco se repitió el intento con la contraseña académica que ya había fallado en la revisión anterior. En este seguimiento se preparó el mecanismo manual automáticamente, sin pedir al operador crear carpetas, archivos ni JSON.

El intento comenzó el 22 de octubre de 2026 a las 00:11:13 UTC (21 de octubre a las 18:11:13 en Guatemala). Se abrió una ventana privada visible con el formulario original conectado a la base aislada. Tras quince minutos no se confirmó el dashboard autenticado: el resultado fue `MANUAL_LOGIN_TIMEOUT`. Esto identifica una comprobación inconclusa; no demuestra que SQL haya rechazado una contraseña correcta ni que haya un fallo funcional en los módulos.

La ventana se cerró y el verificador confirmó `temporaryProfileRemoved: true`. No se crearon archivos de contraseña ni se copiaron secretos a la evidencia. Solo queda pendiente la intervención indispensable del operador para completar el login en un nuevo intento manual.

## Comprobaciones realizadas

- Conexión SQL real de la cuenta de aplicación: `DB_NAME()` confirma `SecureFinanceERP_Estabilizacion_20261021`.
- Inventario, Productos, Facturación, Notas de crédito y Garantías: sin sesión, los cinco endpoints redirigen a `/login` con HTTP 302 conforme al middleware existente. Esto demuestra protección anónima, **no acceso autenticado**.
- Sintaxis del nuevo verificador: `node --check tests/browser/loginAccess.browser.js`.
- Mecanismo manual real ejecutado con Chromium visible: espera acotada de quince minutos, sin autenticación sustituida, sin captura del formulario/tráfico de login y con eliminación verificada del perfil temporal al terminar.
- No se ejecutaron operaciones de compra, venta, crédito ni garantía. No se repitieron las 79 pruebas ni las baterías SQL. No se modificó código funcional de la aplicación ni se detectó un fallo de integración atribuible al ERP.

[Resultado estructurado](evidencias/login-acceso.json).

## Autenticación manual segura

El verificador `node tests/browser/loginAccess.browser.js --manual` prepara `.data` automáticamente y abre una ventana privada visible con un perfil temporal independiente. El operador introduce sus credenciales directamente en el formulario original. Se usan todos los servicios originales, incluido el login SQL, y se comprueban cookie HttpOnly, dashboard y renderizado autenticado con HTTP 200 de los cinco módulos. No escribe operaciones de negocio ni permite un modo de autenticación sustituida.

Primero comprueba las fuentes locales existentes (`ERP_QA_LOGIN_FILE`, `.data/qa-login.local.json` o `WEB_ADMIN_PASSWORD`). Si no existen, activa automáticamente el acceso manual. No pide crear archivos ni guardar contraseñas. `--manual` permite elegir siempre el navegador aunque haya una fuente local disponible. La base está fijada a la copia aislada y se verifica la conexión antes de empezar.

Durante el ingreso manual no se lee el campo de contraseña ni se habilita la captura de tráfico de autenticación. No se realizan capturas de pantalla ni se imprimen credenciales o cookies. El seguimiento de respuestas HTTP empieza después del login. Al finalizar, se cierra exclusivamente el navegador creado para la prueba y se elimina su perfil temporal con una guarda que verifica que la ruta pertenece a la carpeta temporal y tiene el prefijo generado por este verificador. La evidencia contiene únicamente estados y rutas de módulos, sin secretos. Un fallo de limpieza impide declarar PASS.

El operador dispone de quince minutos para ingresar. Si la cuenta exige cambio de contraseña, la prueba se detiene sin cambiarla. Solo se marca el PR listo cuando login, cinco accesos y limpieza pasan. No corresponde fusionar ni desplegar migraciones en `SecureFinanceERP`.
