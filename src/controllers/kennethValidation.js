'use strict';
class ValidationError extends Error { constructor(message) { super(message); this.status = 400; } }
function text(value, max, required = true) {
  if (value == null && !required) return null;
  if (typeof value !== 'string' || value.length > max || /[\x00-\x08\x0b\x0c\x0e-\x1f]/.test(value) || (required && !value.trim())) throw new ValidationError('Completa los campos con valores válidos y dentro de su longitud máxima.');
  return value.trim() || null;
}
function integer(value, min = 1, max = 2147483647) {
  if (!['string', 'number'].includes(typeof value) || !/^\d{1,10}$/.test(String(value)) || Number(value) < min || Number(value) > max) throw new ValidationError('Usa cantidades e identificadores enteros válidos.');
  return Number(value);
}
function version(value) { if (typeof value !== 'string' || !/^[a-f0-9]{16}$/.test(value)) throw new ValidationError('Actualiza la página para obtener la versión vigente.'); return value; }
function nit(value) { const result = text(value, 25).replaceAll('-', '').toUpperCase(); if (!/^[A-Z0-9]{1,25}$/.test(result)) throw new ValidationError('El NIT debe contener letras y números, sin espacios.'); return result; }
function money(value) { if (typeof value !== 'string' || !/^\d{1,10}(?:\.\d{1,2})?$/.test(value)) throw new ValidationError('Usa precios no negativos, con hasta dos decimales.'); return value; }
function active(value) { if (![true, false, '1', '0'].includes(value)) throw new ValidationError('Selecciona un estado válido.'); return value === true || value === '1'; }
function contact(b) {
  const result = { Nombre:text(b.Nombre,150), Correo:text(b.Correo,254,false), Telefono:text(b.Telefono,25,false) };
  if (/[\x00-\x1f\x7f]/.test(result.Nombre) || (result.Correo && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(result.Correo)) || (result.Telefono && (!/^[0-9+(). /-]+$/.test(result.Telefono) || !/[0-9]/.test(result.Telefono)))) throw new ValidationError('Revisa el nombre, el correo y el teléfono.');
  return result;
}
function date(value) { if (!value) return ''; const s = text(value, 10); if (!/^\d{4}-\d{2}-\d{2}$/.test(s) || !Number.isFinite(Date.parse(s)) || new Date(s).toISOString().slice(0,10) !== s || s < '1753-01-01' || s > '9998-12-31') throw new ValidationError('Selecciona una fecha válida.'); return s; }
function filters(q) {
  const result = { buscar: q.buscar === undefined ? '' : text(q.buscar, 150, false) || '', id: q.id ? integer(q.id) : null, offset: q.offset ? integer(q.offset, 0, 1000000) : 0, histOffset: q.histOffset ? integer(q.histOffset, 0, 1000000) : 0, desde: date(q.desde), hasta: date(q.hasta) };
  if (result.desde && result.hasta && result.desde > result.hasta) throw new ValidationError('La fecha final debe ser posterior o igual a la inicial.');
  return result;
}
module.exports = { ValidationError, text, integer, version, nit, money, active, contact, filters };
