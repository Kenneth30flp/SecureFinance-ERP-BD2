'use strict';
class ValidationError extends Error {}
function type(value) { if (!['FULL','DIFF','LOG'].includes(value)) throw new ValidationError('Tipo de respaldo inválido.'); return value; }
function target(value) {
  if (typeof value !== 'string' || !/^SF_Recovery_[A-Za-z0-9_]{1,80}$/.test(value)) throw new ValidationError('Use SF_Recovery_ seguido de letras, números o guiones bajos.');
  return value;
}
// SQL Server backup timestamps are local wall-clock values, not UTC instants.
function point(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/.test(value) || value<'1753-01-01T00:00:00' || !Number.isFinite(Date.parse(value+'Z')) || new Date(value+'Z').toISOString().slice(0,19)!==value) throw new ValidationError('Indique fecha y hora válidas, con segundos, en la zona del servidor SQL.');
  return value;
}
function uuid(value) { if (typeof value !== 'string' || !/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i.test(value)) throw new ValidationError('Referencia inválida.'); return value; }
function directory(value) {
  if (typeof value !== 'string' || !/^[A-Za-z]:\\(?:[A-Za-z0-9_-]+\\)+$/.test(value)) throw new ValidationError('Configure una carpeta local absoluta autorizada, terminada en barra inversa.');
  return value;
}
module.exports={ValidationError,type,target,point,uuid,directory};
