'use strict';

const { randomBytes, timingSafeEqual } = require('node:crypto');

const solicitudMensaje = 'Si la cuenta existe, se generó una solicitud de recuperación.';
const tokenError = 'El enlace de recuperación no es válido o ha expirado.';
const errores = new Map([
  [54001, tokenError],
  [54002, 'La contraseña debe tener entre 8 y 128 caracteres.'],
  [54003, 'La contraseña actual no es correcta.'],
]);

function passwordValida(value) {
  return typeof value === 'string' && value.length >= 8 && value.length <= 128 && value.trim().length > 0;
}

function createPasswordController(service, { production = true } = {}) {
  function render(req, res, modo, status = 200, data = {}) {
    const key = 'passwordCsrf_' + modo;
    req.session[key] ||= randomBytes(32).toString('hex');
    return res.status(status).render('password', {
      modo, csrf: req.session[key], error: null, mensaje: null, demoUrl: null,
      token: '', valido: true, completado: false, obligatorio: !!req.session.usuario?.debeCambiarPassword,
      ...data,
    });
  }
  function csrf(req, res, modo) {
    const received = req.body?._csrf;
    const expected = req.session['passwordCsrf_' + modo];
    if (typeof received === 'string' && typeof expected === 'string'
        && /^[a-f0-9]{64}$/.test(received) && /^[a-f0-9]{64}$/.test(expected)
        && timingSafeEqual(Buffer.from(received), Buffer.from(expected))) return true;
    res.status(403).type('text').send('Token CSRF inválido. Actualiza la página e inténtalo nuevamente.');
    return false;
  }
  function validarPassword(req, res, modo, token = '') {
    if (!passwordValida(req.body?.Password)) {
      render(req, res, modo, 400, { token, error: errores.get(54002) });
      return false;
    }
    if (req.body.Password !== req.body.ConfirmarPassword) {
      render(req, res, modo, 400, { token, error: 'Las contraseñas no coinciden.' });
      return false;
    }
    return true;
  }
  return {
    mostrarRecuperacion(req, res) { return render(req, res, 'recuperar'); },
    async solicitar(req, res) {
      if (!csrf(req, res, 'recuperar')) return;
      let token = null;
      const identificador = req.body?.UsuarioOCorreo;
      try {
        if (typeof identificador === 'string' && identificador.trim().length > 0 && identificador.trim().length <= 254)
          token = await service.solicitar(identificador.trim());
      } catch {
        // Misma respuesta, incluso ante errores: no exponer existencia ni detalles SQL.
        // No registrar parámetros, tokens ni contraseñas.
      }
      // DEMOSTRACIÓN ACADÉMICA EXCLUSIVA DE DESARROLLO.
      // En producción un proveedor de correo enviaría esta URL al destinatario verificado;
      // no devolverla ni imprimirla. No usar Host del navegador para construir enlaces.
      const demoUrl = !production && process.env.NODE_ENV !== 'production' && token
        ? '/restablecer-password?token=' + encodeURIComponent(token) : null;
      return render(req, res, 'recuperar', 200, { mensaje: solicitudMensaje, demoUrl });
    },
    async mostrarRestablecimiento(req, res) {
      try {
        const valido = await service.validar(req.query.token);
        return render(req, res, 'restablecer', valido ? 200 : 400, {
          valido, token: valido ? req.query.token : '', error: valido ? null : tokenError,
        });
      } catch {
        return render(req, res, 'restablecer', 503, { valido: false, error: 'No fue posible verificar el enlace. Inténtalo nuevamente.' });
      }
    },
    async restablecer(req, res) {
      if (!csrf(req, res, 'restablecer')) return;
      const token = typeof req.body?.token === 'string' && /^[a-f0-9]{64}$/.test(req.body.token) ? req.body.token : '';
      if (!token) return render(req, res, 'restablecer', 400, { valido: false, error: tokenError });
      if (!validarPassword(req, res, 'restablecer', token)) return;
      try {
        // La validación definitiva y el consumo suceden juntos en SQL; el GET no consume el token.
        await service.restablecer(token, req.body.Password);
        delete req.session.passwordCsrf_restablecer;
        return render(req, res, 'restablecer', 200, {
          completado: true, mensaje: 'Contraseña actualizada. Inicia sesión con tu nueva contraseña.',
        });
      } catch (error) {
        const conocido = errores.get(error.number);
        return render(req, res, 'restablecer', conocido ? 400 : 503, {
          token: error.number === 54002 ? token : '', valido: error.number === 54002,
          error: conocido || 'No fue posible confirmar el cambio. Intenta iniciar sesión antes de volver a solicitar recuperación.',
        });
      }
    },
    mostrarCambio(req, res) { return render(req, res, 'cambiar'); },
    async cambiar(req, res) {
      if (!csrf(req, res, 'cambiar')) return;
      if (!validarPassword(req, res, 'cambiar')) return;
      const actual = req.body?.PasswordActual;
      if (typeof actual !== 'string' || actual.length < 1 || actual.length > 128)
        return render(req, res, 'cambiar', 400, { error: 'Ingresa una contraseña actual válida.' });
      try {
        await service.cambiar(req.session.usuario.usuarioId, actual, req.body.Password);
      } catch (error) {
        return render(req, res, 'cambiar', errores.has(error.number) ? 400 : 503, {
          error: errores.get(error.number) || 'No fue posible confirmar el cambio. Intenta iniciar sesión antes de repetirlo.',
        });
      }
      const usuario = { ...req.session.usuario, debeCambiarPassword: false };
      try {
        // Renovar la sesión y sus tokens CSRF después del cambio de credenciales.
        await new Promise((resolve, reject) => req.session.regenerate(error => error ? reject(error) : resolve()));
        req.session.usuario = usuario;
        await new Promise((resolve, reject) => req.session.save(error => error ? reject(error) : resolve()));
        return res.redirect(303, '/dashboard');
      } catch {
        if (req.session) await new Promise(resolve => req.session.destroy(() => resolve()));
        res.clearCookie('securefinance.sid', { path: '/' });
        return res.status(503).type('text').send('La contraseña cambió. Inicia sesión nuevamente para continuar.');
      }
    },
  };
}

module.exports = { createPasswordController };
