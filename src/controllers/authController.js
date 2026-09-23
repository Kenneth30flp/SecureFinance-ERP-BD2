'use strict';

function createAuthController(authService) {
  const renderLogin = (res, status, error = null, nombreUsuario = '') =>
    res.status(status).render('login', { error, nombreUsuario });

  return {
    showLogin(req, res) {
      return renderLogin(res, 200);
    },
    async login(req, res) {
      const { NombreUsuario, Password } = req.body || {};
      if (typeof NombreUsuario !== 'string' || typeof Password !== 'string') {
        return renderLogin(res, 400, 'Ingresa un usuario y una contraseña válidos.');
      }
      try {
        // SQL valida credenciales y registra el intento; no transformar el password.
        const result = await authService.login(NombreUsuario, Password);
        if (result.codigo !== 0) {
          const message = result.codigo === 2
            ? 'El usuario se encuentra inactivo.' : 'Usuario o contraseña incorrectos.';
          return renderLogin(res, 401, message, NombreUsuario.slice(0, 50));
        }
        // Renovar el identificador evita fijación de sesión. Guardar antes de redirigir.
        await new Promise((resolve, reject) => req.session.regenerate((error) => error ? reject(error) : resolve()));
        req.session.usuario = result.usuario;
        await new Promise((resolve, reject) => req.session.save((error) => error ? reject(error) : resolve()));
        return res.redirect(303, '/dashboard');
      } catch {
        // No exponer errores del driver, parámetros ni credenciales.
        if (req.session) {
          await new Promise((resolve) => req.session.destroy(() => resolve()));
        }
        res.clearCookie('securefinance.sid', { path: '/' });
        return renderLogin(res, 503, 'No fue posible iniciar sesión. Inténtalo nuevamente.');
      }
    },
    dashboard(req, res) {
      return res.render('dashboard', { usuario: req.session.usuario });
    },
    logout(req, res) {
      req.session.destroy((error) => {
        if (error) return res.status(503).type('text').send('No fue posible cerrar sesión. Inténtalo nuevamente.');
        res.clearCookie('securefinance.sid', { path: '/' });
        return res.redirect('/login');
      });
    },
  };
}

module.exports = { createAuthController };
