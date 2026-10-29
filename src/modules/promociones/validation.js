'use strict';
const { localDayBoundary } = require('../../public/js/operationalDates');
class ValidationError extends Error {}
const TIPOS = ['PORCENTAJE', 'CATEGORIA', 'DOS_POR_UNO', 'VOLUMEN'];
const ESTADOS = ['VIGENTE', 'PROGRAMADA', 'INACTIVA', 'VENCIDA'];
function integer(value) {
  if (!['string','number'].includes(typeof value) || !/^[1-9]\d{0,9}$/.test(String(value)) || Number(value) > 2147483647) throw new ValidationError('Usa identificadores y cantidades enteras positivas.');
  return Number(value);
}
function uuid(value) {
  if (typeof value !== 'string' || !/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i.test(value)) throw new ValidationError('Referencia de operación inválida.');
  return value;
}
function text(value, max) {
  if (typeof value !== 'string' || value.length > max) throw new ValidationError('Texto inválido o demasiado extenso.');
  return value;
}
function version(value) {
  if (typeof value !== 'string' || !/^[A-F0-9]{16}$/i.test(value)) throw new ValidationError('Versión inválida. Actualiza la página.');
  return value.toUpperCase();
}
function day(value, end = false) {
  if (typeof value !== 'string') throw new ValidationError('Fecha inválida.');
  try { return localDayBoundary(value, end); } catch { throw new ValidationError('Fecha inválida.'); }
}
// Importes como texto decimal; nunca Number para el valor que define el beneficio.
function decimal(value, { max, scale = 2, label }) {
  if (!['string','number'].includes(typeof value) || !new RegExp(`^\\d{1,9}(\\.\\d{1,${scale}})?$`).test(String(value)) || Number(value) <= 0 || Number(value) > max) {
    throw new ValidationError(`${label} inválido.`);
  }
  return String(value);
}
function ids(value, max, label) {
  if (value === undefined || value === null || value === '') return [];
  const list = Array.isArray(value) ? value : [value];
  if (list.length > max) throw new ValidationError(`Selecciona como máximo ${max} ${label}.`);
  const set = new Set(list.map(integer));
  if (set.size !== list.length) throw new ValidationError(`No repitas ${label}.`);
  return [...set];
}
// Vigencia por días operativos de Guatemala: inicio inclusivo y fin inclusivo (límite UTC exclusivo).
function rule(b = {}, { edit = false } = {}) {
  const TipoCodigo = text(b.TipoCodigo ?? '', 20);
  if (!TIPOS.includes(TipoCodigo)) throw new ValidationError('Selecciona un tipo de promoción válido.');
  const Nombre = text(b.Nombre ?? '', 120).trim();
  if (!Nombre) throw new ValidationError('Indica el nombre de la promoción.');
  const Descripcion = text(b.Descripcion ?? '', 250).trim() || null;
  const Motivo = text(b.Motivo ?? '', 250).trim();
  if (!Motivo) throw new ValidationError('Indica el motivo del cambio.');
  if (!b.Desde || !b.Hasta) throw new ValidationError('Indica las fechas de inicio y fin.');
  const VigenteDesde = day(b.Desde), VigenteHasta = day(b.Hasta, true);
  if (VigenteHasta <= VigenteDesde) throw new ValidationError('La fecha final debe ser igual o posterior a la inicial.');
  if (TipoCodigo === 'DOS_POR_UNO' && b.Porcentaje !== undefined && b.Porcentaje !== null && b.Porcentaje !== '') throw new ValidationError('La promoción 2x1 no admite porcentaje.');
  const Porcentaje = TipoCodigo === 'DOS_POR_UNO' ? null : decimal(b.Porcentaje, { max: 90, label: 'Porcentaje (0.01 a 90.00)' });
  let CantidadMinima = b.CantidadMinima === undefined || b.CantidadMinima === null || b.CantidadMinima === '' ? null : integer(b.CantidadMinima);
  if (TipoCodigo === 'DOS_POR_UNO') CantidadMinima = 2;
  if (TipoCodigo === 'VOLUMEN' && (!CantidadMinima || CantidadMinima < 2)) throw new ValidationError('El descuento por volumen requiere una cantidad mínima de 2 o más.');
  if (CantidadMinima !== null && CantidadMinima > 100000) throw new ValidationError('Cantidad mínima demasiado alta.');
  const TopeDescuento = b.TopeDescuento === undefined || b.TopeDescuento === null || b.TopeDescuento === '' ? null : decimal(b.TopeDescuento, { max: 9999999.99, label: 'Tope de descuento' });
  const Productos = ids(b.Productos, 200, 'productos'), Categorias = ids(b.Categorias, 50, 'categorías');
  if (TipoCodigo === 'CATEGORIA' ? (!Categorias.length || Productos.length) : (!Productos.length || Categorias.length)) {
    throw new ValidationError(TipoCodigo === 'CATEGORIA' ? 'Selecciona al menos una categoría elegible.' : 'Selecciona al menos un producto elegible.');
  }
  const data = { TipoCodigo, Nombre, Descripcion, Porcentaje, CantidadMinima, TopeDescuento, VigenteDesde, VigenteHasta, Productos, Categorias, Motivo, OperacionId: uuid(b.OperacionId) };
  if (edit) data.Version = version(b.Version);
  else {
    data.Codigo = text(b.Codigo ?? '', 30).trim().toUpperCase();
    if (!/^[A-Z0-9_-]{1,30}$/.test(data.Codigo)) throw new ValidationError('El código admite letras A-Z, números, guion y guion bajo (máximo 30).');
  }
  return data;
}
function state(b = {}) {
  if (typeof b.Activa !== 'boolean') throw new ValidationError('Estado solicitado inválido.');
  const Motivo = text(b.Motivo ?? '', 250).trim();
  if (!Motivo) throw new ValidationError('Indica el motivo del cambio de estado.');
  return { Activa: b.Activa, Motivo, Version: version(b.Version), OperacionId: uuid(b.OperacionId) };
}
function filters(q = {}) {
  const buscar = text(q.buscar ?? '', 150).trim(), tipo = text(q.tipo ?? '', 20), estado = text(q.estado ?? '', 10);
  if (tipo && !TIPOS.includes(tipo)) throw new ValidationError('Tipo inválido.');
  if (estado && !ESTADOS.includes(estado)) throw new ValidationError('Estado inválido.');
  const pagina = q.pagina === undefined ? 1 : integer(q.pagina);
  if (pagina > 100001) throw new ValidationError('Página inválida.');
  return { buscar, tipo, estado, pagina };
}
// Vista previa de Facturación: mismas reglas de líneas que el controlador de venta.
function previewLines(value) {
  let list;
  try { list = typeof value === 'string' ? JSON.parse(value) : value; } catch { throw new ValidationError('Detalle inválido.'); }
  if (!Array.isArray(list) || list.length < 1 || list.length > 100) throw new ValidationError('Entre 1 y 100 productos.');
  const seen = new Set();
  return list.map((l) => {
    const ProductoId = integer(l?.ProductoId), Cantidad = integer(l?.Cantidad), d = l?.DescuentoPorcentaje ?? '0';
    if (!['string','number'].includes(typeof d) || !/^\d{1,3}(\.\d{1,2})?$/.test(String(d)) || Number(d) > 100 || seen.has(ProductoId)) throw new ValidationError('Revisa productos repetidos y descuentos entre 0 y 100.');
    seen.add(ProductoId);
    return { ProductoId, Cantidad, DescuentoPorcentaje: Number(d) };
  });
}
module.exports = { ValidationError, TIPOS, ESTADOS, integer, uuid, text, version, rule, state, filters, previewLines };
