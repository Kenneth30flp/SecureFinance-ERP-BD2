'use strict';
const express = require('express');
const { randomBytes, randomUUID, timingSafeEqual } = require('node:crypto');
const { requireAuth } = require('../../../middleware/authMiddleware');
const { operation } = require('./service');
const errors = {
  59010: [503, 'Panel no disponible para este destino. El DBA debe revisar la instalación y la identidad autorizada.'],
  59011: [409, 'El respaldo requiere una conexión sin transacción abierta.'],
  59012: [400, 'Referencia de operación requerida.'],
  59013: [409, 'Hay otro respaldo en curso. Actualiza el historial antes de reintentar con la misma referencia.'],
  59014: [409, 'Esta referencia corresponde a otra solicitud.'],
  59019: [503, 'El servicio administrativo de respaldo no está configurado.'],
  54101: [403, 'Tu cuenta no tiene el permiso vigente para esta operación.'],
  229: [403, 'Permisos SQL insuficientes. El DBA debe verificar las firmas y permisos del módulo.'],
  297: [403, 'La identidad SQL no puede consultar las métricas requeridas.'],
};
function problem(error) {
  const [status, message] = errors[error.number] || (error.status === 400 ? [400, error.message]
    : [503, 'No se pudo confirmar la respuesta de SQL Server. Conserva la referencia y consulta el historial antes de reintentar.']);
  return { status, message };
}
function createLdfRoutes(service) {
  const router = express.Router();
  const permit = permission => (req, res, next) => req.session.usuario.permisos?.includes(permission)
    ? next() : res.status(403).type('text').send('No tienes permiso para esta operación.');
  router.use('/dba/ldf', requireAuth, permit('DBA_LDF_CONSULTAR'), (req, res, next) => {
    res.set('Cache-Control', 'no-store');
    req.session.ldfCsrf ||= randomBytes(32).toString('hex'); next();
  });
  const locals = req => ({ usuario: req.session.usuario, csrf: req.session.ldfCsrf, operationId: randomUUID(),
    canBackup: req.session.usuario.permisos.includes('DBA_LDF_RESPALDAR_LOG'), data: null, error: null,
    mb: n => Number(n).toLocaleString('es-GT', { maximumFractionDigits: 2 }),
    utc: n => n ? new Date(n).toISOString().replace('T', ' ').replace('Z', ' UTC') : '—' });
  router.get('/dba/ldf', async (req, res) => {
    try {
      const data = await service.read(req.session.usuario.usuarioId);
      return res.render('dba/ldf/index', { ...locals(req), data });
    } catch (error) {
      const p = problem(error);
      return res.status(p.status).render('dba/ldf/index', { ...locals(req), error: p.message });
    }
  });
  router.get('/dba/ldf/metrics', async (req, res) => {
    try { return res.json(await service.read(req.session.usuario.usuarioId)); }
    catch (error) { const p = problem(error); return res.status(p.status).json({ error: p.message }); }
  });
  router.post('/dba/ldf/backup', permit('DBA_LDF_RESPALDAR_LOG'), async (req, res) => {
    const token = req.get('X-CSRF-Token') || req.body?.csrf, expected = req.session.ldfCsrf;
    if (typeof token !== 'string' || !/^[a-f0-9]{64}$/.test(token) || !timingSafeEqual(Buffer.from(token), Buffer.from(expected))) {
      return res.status(403).json({ error: 'Token de seguridad inválido. Actualiza el panel.' });
    }
    try {
      const id = operation(req.body), result = await service.backup(req.session.usuario.usuarioId, id);
      return res.status(result.Estado === 'CONFIRMADO' ? 200 : result.Estado === 'FALLIDO' ? 409 : 202)
        .json({ operation: result, url: '/dba/ldf' });
    } catch (error) {
      const p = problem(error); return res.status(p.status).json({ error: p.message, uncertain: p.status === 503 });
    }
  });
  return router;
}
module.exports = { createLdfRoutes, problem };
