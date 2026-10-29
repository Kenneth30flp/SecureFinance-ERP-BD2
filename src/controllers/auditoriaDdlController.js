'use strict';

const { localDayBoundary } = require('../public/js/operationalDates');
const events = Object.freeze(['CREATE_TABLE', 'ALTER_TABLE', 'DROP_TABLE',
  'CREATE_PROCEDURE', 'ALTER_PROCEDURE', 'DROP_PROCEDURE']);

function invalid() {
  return Object.assign(new Error('Revisa las fechas, filtros y paginacion de la consulta.'), { status: 400 });
}

function identifier(value, zero = false) {
  if (typeof value !== 'string' || !/^(0|[1-9]\d{0,18})$/.test(value)
    || BigInt(value) > 9223372036854775807n || (!zero && value === '0')) throw invalid();
  return value;
}

function filters(query) {
  const f = { desde: '', hasta: '', usuario: '', objeto: '', evento: '', pagina: 1, corteId: null };
  for (const key of ['desde', 'hasta', 'usuario', 'objeto', 'evento']) {
    const value = query[key] ?? '';
    if (typeof value !== 'string' || value.length > (key === 'evento' ? 40 : 128)) throw invalid();
    f[key] = value.trim();
  }
  for (const key of ['desde', 'hasta']) {
    try {
      if (f[key] && (f[key] < '0001-01-01' || f[key] > '9998-12-31')) throw invalid();
      localDayBoundary(f[key]);
    } catch { throw invalid(); }
  }
  if (f.desde && f.hasta && f.desde > f.hasta) throw invalid();
  if (f.evento && !events.includes(f.evento)) throw invalid();
  if (query.pagina !== undefined) {
    if (typeof query.pagina !== 'string' || !/^[1-9]\d{0,6}$/.test(query.pagina)
      || Number(query.pagina) > 1000000) throw invalid();
    f.pagina = Number(query.pagina);
  }
  if (query.corte !== undefined) f.corteId = identifier(query.corte, true);
  return f;
}

function createAuditoriaDdlController(service) {
  function fail(req, res, error, f = filters({})) {
    const status = error.status === 400 || error.number === 54990 ? 400
      : error.number === 54101 ? 403 : 503;
    const message = status === 400 ? 'Revisa las fechas, filtros y paginacion de la consulta.'
      : status === 403 ? 'Tu permiso para consultar Auditoria DDL ya no esta vigente.'
        : 'No fue posible consultar Auditoria DDL. Verifica la instalacion con el responsable de integracion.';
    return res.status(status).render('auditoria-ddl', {
      usuario: req.session.usuario, f, events, rows: [], total: '0', haySiguiente: false, error: message,
    });
  }
  return {
    async list(req, res) {
      let f;
      try {
        f = filters(req.query);
        const result = await service.list(req.session.usuario.usuarioId, f);
        return res.render('auditoria-ddl', {
          usuario: req.session.usuario, events, ...result, f: { ...f, corteId: result.corteId },
          haySiguiente: BigInt(f.pagina) * 20n < BigInt(result.total) && f.pagina < 1000000, error: null,
        });
      } catch (error) { return fail(req, res, error, f); }
    },
    async detail(req, res) {
      try {
        const id = identifier(req.params.id);
        const event = await service.detail(req.session.usuario.usuarioId, id);
        if (!event) {
          return res.status(404).render('auditoria-ddl', {
            usuario: req.session.usuario, f: filters({}), events, rows: [], total: '0', haySiguiente: false,
            error: 'El evento solicitado no existe o no esta disponible.',
          });
        }
        return res.render('auditoria-ddl-detalle', { usuario: req.session.usuario, event });
      } catch (error) { return fail(req, res, error); }
    },
  };
}

module.exports = { createAuditoriaDdlController, filters, identifier, events };
