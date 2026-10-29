'use strict';
const express = require('express');
const { randomBytes, randomUUID, timingSafeEqual } = require('node:crypto');
const { requireAuth } = require('../../middleware/authMiddleware');
const v = require('./validation');
const { money } = require('../cotizaciones/format');
const messages = {
  54101: 'No tienes autorización vigente para esta operación.',
  57102: 'Revisa el código, el tipo, las condiciones, la vigencia y el motivo indicados.',
  57104: 'La promoción ya fue aplicada en facturas: sus condiciones no cambian.',
  57105: 'La referencia corresponde a otra operación o las reglas están ocupadas. Consulta la promoción antes de reenviar.',
  57106: 'Ya existe un registro con ese código o nombre.',
  57107: 'La promoción cambió desde que la consultaste. Actualiza la página.',
  57108: 'La promoción, su vigencia o su configuración no permiten esta operación.',
  57109: 'Existe otra promoción activa del mismo tipo para los mismos productos o categorías en una vigencia superpuesta.',
  57110: 'La promoción, producto o categoría no existe.',
};
function status(e) {
  if (e instanceof v.ValidationError || e.number === 57102) return 400;
  if (e.number === 54101) return 403;
  if (e.number === 57110) return 404;
  if ([57104, 57105, 57106, 57107, 57108, 57109].includes(e.number)) return 409;
  return 503;
}
// Mensajes fijos, nunca e.message de SQL: evita que un texto inesperado llegue al navegador.
function message(e) {
  if (e instanceof v.ValidationError) return e.message;
  if (Object.hasOwn(messages, e.number)) return messages[e.number];
  return 'No fue posible confirmar el resultado. Conserva la referencia y consulta la promoción antes de reenviar.';
}
function fail(res, e) {
  const code = status(e);
  if (code === 503) console.error('P3_PRO_FAILURE', JSON.stringify({ number: e.number, code: e.code, name: e.name }));
  return res.status(code).json({ error: message(e), incierto: code === 503 });
}
function failPage(res, e) {
  const code = status(e);
  if (code === 503) console.error('P3_PRO_FAILURE', JSON.stringify({ number: e.number, code: e.code, name: e.name }));
  return res.status(code).type('text').send(code === 503 ? 'No fue posible cargar promociones. Inténtalo nuevamente.' : message(e));
}
function createPromocionRoutes(service) {
  const r = express.Router();
  const has = (req, p) => req.session.usuario.permisos?.includes(p);
  const permit = (p, json = true) => (req, res, next) => has(req, p) ? next()
    : json ? res.status(403).json({ error: 'No tienes permiso para esta operación.' }) : res.status(403).type('text').send('No tienes permiso para esta sección.');
  const csrf = (req, res, next) => {
    const token = req.get('X-CSRF-Token'), expected = req.session.promocionCsrf;
    if (typeof token !== 'string' || !/^[a-f0-9]{64}$/.test(token) || typeof expected !== 'string' || !timingSafeEqual(Buffer.from(token), Buffer.from(expected))) {
      return res.status(403).json({ error: 'Actualiza la página e inténtalo nuevamente.' });
    }
    return next();
  };
  const render = (req, res, view, data) => res.render(view, { usuario: req.session.usuario, csrf: req.session.promocionCsrf, proMoney: money, ...data });
  r.use('/promociones', requireAuth, (req, res, next) => {
    res.set('Cache-Control', 'no-store');
    req.session.promocionCsrf ||= randomBytes(32).toString('hex');
    next();
  });
  // Vista previa de Facturación: solo lectura, misma regla SQL que la venta; no requiere CSRF.
  r.get('/promociones/vista-previa', permit('VENTAS_REGISTRAR'), async (req, res) => {
    try { return res.json(await service.preview(req.session.usuario.usuarioId, v.previewLines(req.query.detalle))); }
    catch (e) { return fail(res, e); }
  });
  r.get('/promociones/buscar/productos', permit('PROMOCIONES_CONSULTAR'), async (req, res) => {
    try {
      const categoria = req.query.categoria ? v.integer(req.query.categoria) : null;
      return res.json(await service.searchProducts(req.session.usuario.usuarioId, v.text(req.query.q ?? '', 150), categoria));
    } catch (e) { return fail(res, e); }
  });
  r.get('/promociones', permit('PROMOCIONES_CONSULTAR', false), async (req, res) => {
    try {
      const f = v.filters(req.query), actor = req.session.usuario.usuarioId;
      const [rows, form] = await Promise.all([service.list(actor, f), service.form(actor)]);
      return render(req, res, 'promociones/list', { f, rows: rows.slice(0, 20), next: rows.length > 20, tipos: form.tipos });
    } catch (e) { return failPage(res, e); }
  });
  r.get('/promociones/nueva', permit('PROMOCIONES_CREAR', false), async (req, res) => {
    try {
      const form = await service.form(req.session.usuario.usuarioId);
      return render(req, res, 'promociones/form', { ...form, promocion: null, productos: [], seleccion: [], operacionId: randomUUID() });
    } catch (e) { return failPage(res, e); }
  });
  r.post('/promociones', permit('PROMOCIONES_CREAR'), csrf, async (req, res) => {
    try {
      const d = v.rule(req.body), promocion = await service.create(req.session.usuario.usuarioId, d);
      return res.status(201).json({ promocion, url: '/promociones/' + promocion.PromocionId });
    } catch (e) { return fail(res, e); }
  });
  r.get('/promociones/categorias', permit('PROMOCIONES_CONSULTAR', false), async (req, res) => {
    try {
      const form = await service.form(req.session.usuario.usuarioId);
      return render(req, res, 'promociones/categorias', { ...form, operacionId: randomUUID(), asignacionId: randomUUID() });
    } catch (e) { return failPage(res, e); }
  });
  r.post('/promociones/categorias', permit('PROMOCIONES_MODIFICAR'), csrf, async (req, res) => {
    try {
      const Nombre = v.text(req.body?.Nombre ?? '', 80).trim(), Motivo = v.text(req.body?.Motivo ?? '', 250).trim();
      if (!Nombre || !Motivo) throw new v.ValidationError('Indica el nombre de la categoría y el motivo.');
      return res.status(201).json({ categoria: await service.createCategory(req.session.usuario.usuarioId, { Nombre, Motivo, OperacionId: v.uuid(req.body?.OperacionId) }) });
    } catch (e) { return fail(res, e); }
  });
  r.post('/promociones/categorias/asignar', permit('PROMOCIONES_MODIFICAR'), csrf, async (req, res) => {
    try {
      const Motivo = v.text(req.body?.Motivo ?? '', 250).trim();
      if (!Motivo) throw new v.ValidationError('Indica el motivo de la asignación.');
      const CategoriaId = req.body?.CategoriaId === null || req.body?.CategoriaId === '' ? null : v.integer(req.body?.CategoriaId);
      return res.json({ asignacion: await service.assignCategory(req.session.usuario.usuarioId, { ProductoId: v.integer(req.body?.ProductoId), CategoriaId, Motivo, OperacionId: v.uuid(req.body?.OperacionId) }) });
    } catch (e) { return fail(res, e); }
  });
  r.get('/promociones/:id', permit('PROMOCIONES_CONSULTAR', false), async (req, res) => {
    try {
      const data = await service.detail(req.session.usuario.usuarioId, v.integer(req.params.id));
      if (!data.promocion) return res.status(404).type('text').send('Promoción no encontrada.');
      return render(req, res, 'promociones/detail', { ...data, operacionId: randomUUID() });
    } catch (e) { return failPage(res, e); }
  });
  r.get('/promociones/:id/editar', permit('PROMOCIONES_MODIFICAR', false), async (req, res) => {
    try {
      const actor = req.session.usuario.usuarioId, id = v.integer(req.params.id);
      const [data, form] = await Promise.all([service.detail(actor, id), service.form(actor)]);
      if (!data.promocion) return res.status(404).type('text').send('Promoción no encontrada.');
      if (data.promocion.Estado === 'VENCIDA') return res.status(409).type('text').send('Las promociones vencidas se conservan como historial y no se editan.');
      return render(req, res, 'promociones/form', { ...form, promocion: data.promocion, seleccion: data.productos, categoriasSeleccion: data.categorias, operacionId: randomUUID() });
    } catch (e) { return failPage(res, e); }
  });
  r.post('/promociones/:id', permit('PROMOCIONES_MODIFICAR'), csrf, async (req, res) => {
    try {
      const id = v.integer(req.params.id), promocion = await service.update(req.session.usuario.usuarioId, id, v.rule(req.body, { edit: true }));
      return res.json({ promocion, url: '/promociones/' + id });
    } catch (e) { return fail(res, e); }
  });
  r.post('/promociones/:id/estado', permit('PROMOCIONES_ACTIVAR'), csrf, async (req, res) => {
    try {
      const id = v.integer(req.params.id), promocion = await service.setState(req.session.usuario.usuarioId, id, v.state(req.body));
      return res.json({ promocion, url: '/promociones/' + id });
    } catch (e) { return fail(res, e); }
  });
  return r;
}
module.exports = { createPromocionRoutes };
