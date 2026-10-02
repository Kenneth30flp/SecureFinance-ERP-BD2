'use strict';
const { randomBytes, timingSafeEqual } = require('node:crypto');
const errors = new Map([
  [53001, 'El usuario no existe.'],
  [53002, 'Los roles deben ser únicos, existir y estar activos.'],
  [53003, 'No se puede quitar el rol Administrador al último administrador activo.'],
  [53004, 'No tienes permiso para administrar usuarios.'],
]);
function entero(value) {
  if (typeof value !== 'number' && (typeof value !== 'string' || !/^[1-9]\d{0,9}$/.test(value))) return null;
  const n = Number(value);
  return Number.isInteger(n) && n > 0 && n <= 2147483647 ? n : null;
}
function fail(res, error) {
  const message = errors.get(error.number);
  return res.status(message ? (error.number === 53004 ? 403 : error.number === 53003 ? 409 : 400) : 503)
    .json({ error: message || 'No fue posible confirmar los cambios. Actualiza la página antes de volver a intentarlo.' });
}
function createUsuarioController(service) {
  return {
    async mostrar(req, res) {
      try {
        const [usuarios, roles] = await Promise.all([service.listarUsuarios(), service.listarRolesActivos()]);
        req.session.usuarioRolesCsrf ||= randomBytes(32).toString('hex');
        res.render('usuarios', { usuario: req.session.usuario, usuarios, roles, csrf: req.session.usuarioRolesCsrf });
      } catch { res.status(503).type('text').send('No fue posible cargar Usuarios y Roles. Inténtalo nuevamente.'); }
    },
    async obtener(req, res) {
      const id = entero(req.params.id);
      if (!id) return res.status(400).json({ error: 'UsuarioId debe ser un entero positivo.' });
      try { return res.json({ roles: await service.obtenerRolesUsuario(id) }); }
      catch (error) { return fail(res, error); }
    },
    async actualizar(req, res) {
      const token = req.get('X-CSRF-Token');
      const expected = req.session.usuarioRolesCsrf;
      if (typeof token !== 'string' || typeof expected !== 'string'
        || !/^[a-f0-9]{64}$/.test(token) || !/^[a-f0-9]{64}$/.test(expected)
        || !timingSafeEqual(Buffer.from(token), Buffer.from(expected))) {
        return res.status(403).json({ error: 'Token CSRF inválido. Actualiza la página.' });
      }
      const id = entero(req.params.id);
      const actor = entero(req.session.usuario.usuarioId);
      const roles = req.body?.Roles;
      if (!id || !actor || !Array.isArray(roles) || roles.length > 1000
        || roles.some(rol => !entero(rol)) || new Set(roles.map(entero)).size !== roles.length) {
        return res.status(400).json({ error: 'Envía un usuario válido y un arreglo de roles enteros positivos sin repetidos.' });
      }
      try {
        await service.actualizarRoles(id, roles.map(entero), actor);
        return res.json({ mensaje: 'Roles actualizados correctamente.' });
      } catch (error) { return fail(res, error); }
    },
  };
}
module.exports = { createUsuarioController };
