'use strict';

const MODOS = new Set(['DIARIO', 'SEMANAL', 'MENSUAL', 'RANGO']);

class AnalyticsValidationError extends Error {
  constructor(message) {
    super(message);
    this.name = 'AnalyticsValidationError';
    this.status = 400;
  }
}

function validDate(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const [year, month, day] = value.split('-').map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
}

function filters(query = {}) {
  const modo = String(query.modo || 'MENSUAL').toUpperCase();
  const fechaDesde = query.fechaDesde || null;
  const fechaHasta = query.fechaHasta || null;
  if (!MODOS.has(modo)) throw new AnalyticsValidationError('Selecciona un período válido.');
  if (fechaDesde && !validDate(fechaDesde) || fechaHasta && !validDate(fechaHasta)) {
    throw new AnalyticsValidationError('Las fechas deben tener formato YYYY-MM-DD y ser válidas.');
  }
  if (modo === 'RANGO' && (!fechaDesde || !fechaHasta || fechaDesde > fechaHasta)) {
    throw new AnalyticsValidationError('El rango personalizado es obligatorio y no puede estar invertido.');
  }
  const pagina = Math.max(1, Math.min(100, Number.parseInt(query.pagina || '1', 10) || 1));
  return { modo, fechaDesde, fechaHasta, pagina, desplazamiento: (pagina - 1) * 10, limite: 10 };
}

module.exports = { AnalyticsValidationError, filters, validDate };
