'use strict';
const { ValidationError, integer, uuid, text } = require('../cotizaciones/validation');
const { localDayBoundary } = require('../../public/js/operationalDates');
function amount(value) {
  if (typeof value !== 'string' || !/^(?:0|[1-9]\d{0,16})(?:\.\d{1,2})?$/.test(value)) {
    throw new ValidationError('Importe positivo, sin separadores y con hasta dos decimales.');
  }
  const [whole, fraction = ''] = value.split('.');
  const normalized = whole + '.' + fraction.padEnd(2, '0');
  if (normalized === '0.00') throw new ValidationError('El importe debe ser mayor que cero.');
  return normalized;
}
function bigint(value) {
  if (typeof value !== 'string' || !/^[1-9]\d{0,18}$/.test(value) || BigInt(value) > 9223372036854775807n) {
    throw new ValidationError('Identificador de recibo invalido.');
  }
  return value;
}
function version(value) {
  if (value === '' || value === undefined || value === null) return null;
  if (typeof value !== 'string' || !/^[a-f0-9]{16}$/i.test(value)) throw new ValidationError('Version invalida.');
  return value.toUpperCase();
}
function reason(value, max) {
  const result = text(value, max).trim();
  if (!result) throw new ValidationError('Indica el motivo o referencia documental.');
  return result;
}
function plan(body) {
  const PlazoDias = integer(body.PlazoDias), NumeroCuotas = integer(body.NumeroCuotas ?? '1');
  if (PlazoDias > 3650 || NumeroCuotas > 120 || NumeroCuotas > PlazoDias) throw new ValidationError('Revisa plazo y numero de cuotas.');
  return { PlazoDias, NumeroCuotas };
}
function profile(body = {}) {
  if (!['0', '1', true, false].includes(body.Activo)) throw new ValidationError('Estado de credito invalido.');
  const PlazoDias = integer(body.PlazoDias);
  if (PlazoDias > 3650) throw new ValidationError('Plazo maximo: 3650 dias.');
  return { ClienteId: integer(body.ClienteId), Activo: body.Activo === '1' || body.Activo === true,
    Limite: amount(body.Limite), PlazoDias, VersionEsperada: version(body.VersionEsperada),
    Motivo: reason(body.Motivo, 250), OperacionId: uuid(body.OperacionId) };
}
function payment(body = {}) {
  return { ClienteId: integer(body.ClienteId), FacturaId: integer(body.FacturaId), Monto: amount(body.Monto),
    Referencia: reason(body.Referencia, 100), OperacionId: uuid(body.OperacionId) };
}
function conversion(body = {}) {
  return { CotizacionId: integer(body.CotizacionId), OperacionId: uuid(body.OperacionId), ...plan(body),
    BodegaId: body.BodegaId === '' || body.BodegaId === undefined || body.BodegaId === null ? null : integer(body.BodegaId) };
}
function filters(query = {}) {
  const estado = text(query.estado ?? '', 10);
  if (estado && !['PENDIENTE', 'PARCIAL', 'PAGADA', 'VENCIDA'].includes(estado)) throw new ValidationError('Estado invalido.');
  const pagina = query.pagina === undefined ? 1 : integer(query.pagina);
  if (pagina > 100001) throw new ValidationError('Pagina invalida.');
  let Desde = null, Hasta = null;
  try {
    if (query.desde !== undefined) text(query.desde, 10);
    if (query.hasta !== undefined) text(query.hasta, 10);
    Desde = localDayBoundary(query.desde || ''); Hasta = localDayBoundary(query.hasta || '', true);
  } catch { throw new ValidationError('Fecha invalida.'); }
  if (Desde && Hasta && Desde >= Hasta) throw new ValidationError('Rango de fechas invalido.');
  return { ClienteId: query.clienteId === undefined || query.clienteId === '' ? null : integer(query.clienteId),
    FacturaId: query.facturaId === undefined || query.facturaId === '' ? null : integer(query.facturaId),
    estado, pagina, desde: query.desde || '', hasta: query.hasta || '', Desde, Hasta };
}
module.exports = { ValidationError, integer, uuid, amount, bigint, version, profile, payment, conversion, filters };
