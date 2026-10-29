'use strict';
const express = require('express');
const { randomBytes, randomUUID, timingSafeEqual } = require('node:crypto');
const { requireAuth } = require('../../middleware/authMiddleware');
const dates = require('../../public/js/operationalDates');
const v = require('./validation');
const permissions = { bodega: ['BODEGAS_ADMINISTRAR'], preparar: ['TRANSFERENCIAS_CREAR'], despachar: ['TRANSFERENCIAS_DESPACHAR'], recibir: ['TRANSFERENCIAS_RECIBIR'], compra: ['INVENTARIO_REGISTRAR'], cotizacion: ['COTIZACIONES_CONVERTIR', 'VENTAS_REGISTRAR'] };
function fail(res, error) {
  const n = error.number;
  const status = error instanceof v.ValidationError ? 400 : n === 54101 ? 403 : [58003, 58005, 52010, 54113, 54903, 54910, 54803].includes(n) ? 409 : n === 58004 ? 404 : [58002, 58008].includes(n) ? 400 : 503;
  const messages = { 58003: 'La referencia, version o estado cambio. Consulta la evidencia antes de reenviar.', 58005: 'Existencia local insuficiente, fuera de rango o bodega con pendientes.', 58004: 'Producto, transferencia o bodega inexistente o inactiva.', 58002: 'Revisa los datos de la solicitud.', 58008: 'No se puede valorar la compra: falta el costo previo o el costo resultante esta fuera de rango. Requiere revision autorizada.', 54101: 'No tienes autorizacion vigente.', 58007: 'Credito no esta instalado. No se ha convertido el documento.' };
  return res.status(status).json({ error: error instanceof v.ValidationError ? error.message : messages[n] || 'No fue posible confirmar el resultado. Conserva la referencia y consulta su estado.', incierto: status === 503 });
}
function createMultibodegaRoutes(service) {
  const r = express.Router();
  const permit = (...required) => async (req, res, next) => {
    try {
      for (const p of required) {
        if (!req.session.usuario.permisos?.includes(p)) return res.status(403).json({ error: 'No tienes permiso para esta operacion.' });
        await service.authorize(req.session.usuario.usuarioId, p);
      }
      return next();
    } catch (e) { return fail(res, e); }
  };
  const csrf = (req, res, next) => {
    const actual = req.get('X-CSRF-Token'), expected = req.session.multibodegaCsrf;
    if (typeof actual !== 'string' || !/^[a-f0-9]{64}$/.test(actual) || typeof expected !== 'string' || expected.length !== actual.length || !timingSafeEqual(Buffer.from(actual), Buffer.from(expected))) return res.status(403).json({ error: 'CSRF invalido. Actualiza la pagina.' });
    return next();
  };
  r.use('/multibodega', requireAuth, (req, res, next) => {
    res.set('Cache-Control', 'no-store');
    req.session.multibodegaCsrf ||= randomBytes(32).toString('hex');
    Object.assign(res.locals, { usuario: req.session.usuario, csrf: req.session.multibodegaCsrf, newOperation: randomUUID, dates });
    next();
  }, permit('BODEGAS_CONSULTAR'));
  r.get('/multibodega', async (req, res) => {
    try {
      const section = req.query.seccion ?? 'inventario';
      if (!['inventario', 'bodegas', 'transferencias', 'kardex', 'integraciones'].includes(section)) throw new v.ValidationError('Seccion invalida.');
      const f = v.filters(req.query), actor = req.session.usuario.usuarioId;
      const data = section === 'integraciones' ? { rows: [], next: false, evidence: [] } : await service.list(actor, section, f);
      return res.render('multibodega/index', { section, f, ...data });
    } catch (e) { return fail(res, e); }
  });
  r.get('/multibodega/transferencias/:id', async (req, res) => {
    try {
      const data = await service.list(req.session.usuario.usuarioId, 'detalle', {}, v.integer(req.params.id));
      if (!data.rows.length) return res.status(404).send('Transferencia no encontrada.');
      return res.render('multibodega/detail', { row: data.rows[0], evidence: data.evidence });
    } catch (e) { return fail(res, e); }
  });
  r.get('/multibodega/operaciones/:id', async (req, res) => {
    try {
      const id = v.uuid(req.params.id), operation = await service.operation(req.session.usuario.usuarioId, id);
      return res.status(operation ? 200 : 404).render('multibodega/operation', { id, operation });
    } catch (e) { return fail(res, e); }
  });
  for (const [path, action] of [
    ['/bodegas', 'bodega'], ['/bodegas/:id', 'bodega'], ['/transferencias', 'preparar'],
    ['/transferencias/:id/despachar', 'despachar'], ['/transferencias/:id/recibir', 'recibir'],
    ['/compras', 'compra'], ['/cotizaciones/convertir', 'cotizacion'],
  ]) r.post('/multibodega' + path, csrf, permit(...permissions[action]), async (req, res) => {
    try {
      const data = v.mutation(req.body, action, req.params.id);
      const documento = await service.mutate(req.session.usuario.usuarioId, action, data);
      return res.json({ documento, url: '/multibodega/operaciones/' + data.OperacionId });
    } catch (e) { return fail(res, e); }
  });
  return r;
}
module.exports = { createMultibodegaRoutes, fail };
