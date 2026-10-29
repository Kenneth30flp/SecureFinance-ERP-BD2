'use strict';
const { localDayBoundary } = require('../../public/js/operationalDates');
class ValidationError extends Error {}
function integer(value, min = 1, max = 2147483647) {
  if (!['string', 'number'].includes(typeof value) || !/^\d+$/.test(String(value))) throw new ValidationError('Usa un entero valido.');
  const result = Number(value);
  if (!Number.isSafeInteger(result) || result < min || result > max) throw new ValidationError('Entero fuera de rango.');
  return result;
}
function text(value, max) {
  if (typeof value !== 'string' || !value.trim() || value.length > max || /[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(value)) throw new ValidationError(`Texto obligatorio de hasta ${max} caracteres.`);
  return value;
}
function uuid(value) {
  if (typeof value !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)) throw new ValidationError('Referencia UUID invalida.');
  return value.toLowerCase();
}
function version(value) {
  if (typeof value !== 'string' || !/^[0-9a-f]{16}$/i.test(value)) throw new ValidationError('Version requerida. Consulta el estado actual.');
  return value.toUpperCase();
}
function bit(value) {
  if (![true, false, '1', '0', 1, 0].includes(value)) throw new ValidationError('Indicador invalido.');
  return value === true || value === '1' || value === 1;
}
function money(value) {
  if (value === '' || value === null || value === undefined) return null;
  if (typeof value !== 'string' || !/^(0|[1-9]\d{0,16})(\.\d{1,2})?$/.test(value)) throw new ValidationError('Costo decimal invalido; usa hasta dos centavos, sin exponente.');
  const [whole, cents = ''] = value.split('.');
  return whole + '.' + cents.padEnd(2, '0');
}
function mutation(body, action, id) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw new ValidationError('Solicitud invalida.');
  // Actor, precios de venta y SQL enviados por el cliente nunca forman parte del contrato.
  const d = { OperacionId: uuid(body.OperacionId) };
  if (action === 'bodega') {
    Object.assign(d, { Nombre: text(body.Nombre, 100), Activo: bit(body.Activo), IsCentral: bit(body.IsCentral), Motivo: text(body.Motivo, 250) });
    for (const [key, max] of [['Codigo', 40], ['Direccion', 250], ['Responsable', 150]]) {
      if (body[key] !== undefined) {
        if (typeof body[key] !== 'string' || body[key].length > max) throw new ValidationError('Metadatos de bodega invalidos.');
        d[key] = body[key].trim() ? text(body[key], max) : '';
      }
    }
    if (d.Codigo && !/^[a-z0-9_-]+$/i.test(d.Codigo)) throw new ValidationError('Codigo de bodega invalido.');
    if (id !== undefined) Object.assign(d, { BodegaId: integer(id), VersionEsperada: version(body.VersionEsperada) });
  } else if (action === 'preparar') {
    Object.assign(d, { ProductoId: integer(body.ProductoId), OrigenId: integer(body.OrigenId), DestinoId: integer(body.DestinoId), Cantidad: integer(body.Cantidad), Motivo: text(body.Motivo, 250) });
    if (d.OrigenId === d.DestinoId) throw new ValidationError('Origen y destino deben ser diferentes.');
  } else if (['despachar', 'recibir'].includes(action)) {
    Object.assign(d, { TransferenciaId: integer(id), Accion: action.toUpperCase(), VersionEsperada: version(body.VersionEsperada), Motivo: text(body.Motivo, 250) });
  } else if (action === 'compra') {
    Object.assign(d, { BodegaId: integer(body.BodegaId), ProductoId: integer(body.ProductoId), ProveedorId: integer(body.ProveedorId), Cantidad: integer(body.Cantidad), DocumentoRespaldo: text(body.DocumentoRespaldo, 100), Motivo: text(body.Motivo, 250), CostoUnitario: money(body.CostoUnitario) });
  } else if (action === 'cotizacion') {
    Object.assign(d, { CotizacionId: integer(body.CotizacionId), BodegaId: integer(body.BodegaId), Credito: bit(body.Credito), PlazoDias: null, NumeroCuotas: 1 });
    if (d.Credito) Object.assign(d, { PlazoDias: integer(body.PlazoDias, 1, 3650), NumeroCuotas: integer(body.NumeroCuotas, 1, 120) });
    else if ((body.PlazoDias !== undefined && body.PlazoDias !== '') || (body.NumeroCuotas !== undefined && String(body.NumeroCuotas) !== '1')) throw new ValidationError('Contado no recibe plazo ni cuotas.');
  } else throw new ValidationError('Accion invalida.');
  return d;
}
function filters(query = {}) {
  const f = { pagina: query.pagina === undefined ? 1 : integer(query.pagina, 1, 100001), BodegaId: null, ProductoId: null, Desde: null, Hasta: null, desde: '', hasta: '' };
  f.Buscar = query.Buscar === undefined || query.Buscar === '' ? '' : text(query.Buscar, 128);
  f.Estado = query.Estado === undefined || query.Estado === '' ? '' : text(query.Estado, 12);
  if (f.Estado && !['PREPARADA', 'DESPACHADA', 'RECIBIDA'].includes(f.Estado)) throw new ValidationError('Estado invalido.');
  for (const k of ['BodegaId', 'ProductoId']) if (query[k] !== undefined && query[k] !== '') f[k] = integer(query[k]);
  try {
    for (const k of ['desde', 'hasta']) if (query[k] !== undefined && query[k] !== '') {
      f[k] = text(query[k], 10);
      f[k === 'desde' ? 'Desde' : 'Hasta'] = localDayBoundary(f[k], k === 'hasta');
    }
  } catch { throw new ValidationError('Fecha invalida.'); }
  if (f.Desde && f.Hasta && f.Desde >= f.Hasta) throw new ValidationError('Periodo invalido.');
  return f;
}
module.exports = { ValidationError, integer, text, uuid, version, bit, money, mutation, filters };
