'use strict';
const express = require('express');
const { randomBytes, randomUUID, timingSafeEqual } = require('node:crypto');
const { requireAuth } = require('../../middleware/authMiddleware');
const v = require('./validation');
const { money } = require('../cotizaciones/format');
function failure(res, error) {
  const messages = {
    57000: [503, 'Credito no disponible en este entorno. Conserva la referencia y consulta el resultado.'],
    57002: [400, 'Revisa los datos, plazo y cuotas.'],
    57003: [409, 'La version o referencia ya cambio. Consulta el historial antes de reenviar.'],
    57004: [404, 'Cliente o factura no disponibles para esta operacion.'],
    57005: [409, 'Credito inactivo, plazo no autorizado o disponible insuficiente.'],
    57006: [409, 'El abono excede el saldo pendiente.'],
    57008: [409, 'La bodega solicitada no tiene la integracion requerida. No se uso stock global.'],
    57009: [409, 'Contexto de bodega ocupado por otro flujo. No se modifico ni se uso stock global.'],
    54101: [403, 'No tienes permiso vigente para esta operacion.'],
    52013: [403, 'No tienes permiso vigente para registrar ventas.'],
    54803: [409, 'Referencia utilizada con otros datos. Consulta el documento.'],
    54903: [409, 'Cotizacion procesada o cancelada. Consulta el documento.'],
    54904: [404, 'Cotizacion no encontrada.'],
    54910: [409, 'La cotizacion esta vencida.'],
    54912: [409, 'El pacto de la cotizacion no coincide. No se completo la venta.'],
    52010: [409, 'Stock insuficiente.'], 54113: [409, 'Stock insuficiente.'],
    52006: [409, 'Cliente inactivo.'], 52009: [409, 'Producto inactivo.'],
    52012: [403, 'El descuento pactado supera tu autorizacion vigente.'],
  };
  const [status, message] = error instanceof v.ValidationError ? [400, error.message]
    : messages[error.number] || [503, 'No fue posible confirmar el resultado. Conserva UUID y datos; consulta el historial antes de reenviar.'];
  return res.status(status).json({ error: message, incierto: status === 503 });
}
function createCreditoRoutes(service) {
  const router = express.Router();
  const permit = code => (req, res, next) => req.session.usuario.permisos?.includes(code) ? next()
    : res.status(403).json({ error: 'No tienes permiso para esta operacion.' });
  const csrf = (req, res, next) => {
    const token = req.get('X-CSRF-Token') || req.body?.csrf, expected = req.session.creditosCsrf;
    if (typeof token !== 'string' || !/^[a-f0-9]{64}$/.test(token) || typeof expected !== 'string'
      || expected.length !== 64 || !timingSafeEqual(Buffer.from(token), Buffer.from(expected))) {
      return res.status(403).json({ error: 'Token de seguridad invalido. Actualiza la pagina.' });
    }
    return next();
  };
  router.use('/creditos', requireAuth, (req, res, next) => {
    res.set('Cache-Control', 'no-store');
    req.session.creditosCsrf ||= randomBytes(32).toString('hex');
    req.session.creditosOps ||= { perfil: randomUUID(), abono: randomUUID(), conversion: randomUUID() };
    res.locals.creMoney = money;
    next();
  });
  router.get('/creditos', permit('CREDITOS_CONSULTAR'), async (req, res) => {
    try {
      const f = v.filters(req.query), data = await service.list(req.session.usuario.usuarioId, f);
      const caja = await service.cash(req.session.usuario.usuarioId, f);
      return res.render('creditos/index', { usuario: req.session.usuario, csrf: req.session.creditosCsrf,
        ops: req.session.creditosOps, f, caja, ...data });
    } catch (error) { return failure(res, error); }
  });
  router.get('/creditos/caja', permit('CREDITOS_CONSULTAR'), async (req, res) => {
    try {
      const f = v.filters(req.query), caja = await service.cash(req.session.usuario.usuarioId, f);
      return res.render('creditos/cash', { usuario: req.session.usuario, csrf: req.session.creditosCsrf, f, caja });
    } catch (error) { return failure(res, error); }
  });
  router.get('/creditos/recibos/:id', permit('CREDITOS_CONSULTAR'), async (req, res) => {
    try {
      const data = await service.receipt(req.session.usuario.usuarioId, v.bigint(req.params.id));
      if (!data.recibo) return res.status(404).type('text').send('Recibo no encontrado.');
      return res.render('creditos/receipt', { usuario: req.session.usuario, csrf: req.session.creditosCsrf, ...data });
    } catch (error) { return failure(res, error); }
  });
  router.post('/creditos/perfil', permit('CREDITOS_ADMINISTRAR'), csrf, async (req, res) => {
    try {
      const d = v.profile(req.body), documento = await service.profile(req.session.usuario.usuarioId, d);
      req.session.creditosOps.perfil = randomUUID();
      return res.json({ documento, url: '/creditos?clienteId=' + d.ClienteId, mensaje: 'Autorizacion de credito confirmada.' });
    } catch (error) { return failure(res, error); }
  });
  router.post('/creditos/abonos', permit('CREDITOS_ABONAR'), csrf, async (req, res) => {
    try {
      const d = v.payment(req.body), recibo = await service.payment(req.session.usuario.usuarioId, d);
      req.session.creditosOps.abono = randomUUID();
      return res.json({ recibo, url: '/creditos/recibos/' + v.bigint(recibo.AbonoId), mensaje: 'Abono confirmado. Recibo ' + v.bigint(recibo.ReciboId) + '.' });
    } catch (error) { return failure(res, error); }
  });
  router.post('/creditos/conversiones', permit('CREDITOS_FACTURAR'), permit('COTIZACIONES_CONVERTIR'), permit('VENTAS_REGISTRAR'), csrf, async (req, res) => {
    try {
      const d = v.conversion(req.body), result = await service.convert(req.session.usuario.usuarioId, d);
      req.session.creditosOps.conversion = randomUUID();
      return res.json({ ...result, url: '/creditos?facturaId=' + v.integer(result.documento.FacturaId), mensaje: 'Cotizacion facturada a credito con precios pactados.' });
    } catch (error) { return failure(res, error); }
  });
  return router;
}
module.exports = { createCreditoRoutes };
