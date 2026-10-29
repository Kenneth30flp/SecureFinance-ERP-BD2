'use strict';
const { sql, getPool } = require('../../config/database');
const v = require('./validation');
function createCreditoService(provider = getPool) {
  async function call(name, actor, params = []) {
    const request = (await provider()).request().input('ActorUsuarioId', sql.Int, v.integer(actor));
    for (const [key, type, value] of params) request.input(key, type, value ?? null);
    const result = await request.execute(name);
    if (!Array.isArray(result.recordsets)) throw new Error('Respuesta SQL incompatible.');
    return result.recordsets;
  }
  function confirmed(row, operation) {
    if (!row || String(row.OperacionId).toLowerCase() !== operation.toLowerCase()) throw new Error('Resultado no confirmado.');
    return row;
  }
  return {
    async cash(actor, f) {
      const sets = await call('dbo.P3_CRE_ConsultarCaja', actor, [
        ['Desde', sql.DateTime2(3), f.Desde], ['Hasta', sql.DateTime2(3), f.Hasta],
        ['Desplazamiento', sql.Int, (f.pagina - 1) * 20],
      ]);
      if (sets.length !== 2 || sets.some(set => !Array.isArray(set)) || sets[0].length !== 1) throw new Error('Caja SQL incompatible.');
      const resumen = sets[0][0], rows = sets[1];
      for (const key of ['EfectivoContado', 'EfectivoAbonos', 'EfectivoTotal']) {
        if (typeof resumen[key] !== 'string' || !/^(?:0|[1-9]\d{0,35})\.\d{2}$/.test(resumen[key])) throw new Error('Importe de caja SQL incompatible.');
      }
      for (const row of rows) {
        try {
          v.bigint(row.DocumentoId);
          if (row.Origen === 'ABONO') v.bigint(row.AbonoId);
        } catch { throw new Error('Documento de caja SQL incompatible.'); }
        if (!['CONTADO', 'ABONO'].includes(row.Origen) || (row.Origen === 'CONTADO' && row.AbonoId !== null)
          || typeof row.Monto !== 'string' || !/^(?:0|[1-9]\d{0,16})\.\d{2}$/.test(row.Monto)) throw new Error('Movimiento de caja SQL incompatible.');
      }
      return { resumen, movimientos: rows.slice(0, 20), next: rows.length > 20 };
    },
    async list(actor, f) {
      const sets = await call('dbo.P3_CRE_Consultar', actor, [
        ['ClienteId', sql.Int, f.ClienteId], ['FacturaId', sql.Int, f.FacturaId], ['Estado', sql.VarChar(10), f.estado || null],
        ['Desde', sql.DateTime2(3), f.Desde], ['Hasta', sql.DateTime2(3), f.Hasta], ['Desplazamiento', sql.Int, (f.pagina - 1) * 20],
      ]);
      if (sets.length !== 5 || sets.some(set => !Array.isArray(set))) throw new Error('Consulta SQL incompatible.');
      const [cuentas, perfiles, cuotas, abonos, historial] = sets;
      return { cuentas: cuentas.slice(0, 20), next: cuentas.length > 20, perfil: perfiles[0] || null, cuotas, abonos, historial };
    },
    async profile(actor, body) {
      const d = v.profile(body);
      const sets = await call('dbo.P3_CRE_AdministrarCredito', actor, [
        ['ClienteId', sql.Int, d.ClienteId], ['Activo', sql.Bit, d.Activo],
        // RPC sends a string; SQL converts to the procedure's DECIMAL(19,2). No driver Number coercion.
        ['Limite', sql.NVarChar(21), d.Limite], ['PlazoDias', sql.Int, d.PlazoDias],
        ['VersionEsperada', sql.Binary(8), d.VersionEsperada ? Buffer.from(d.VersionEsperada, 'hex') : null],
        ['Motivo', sql.NVarChar(250), d.Motivo], ['OperacionId', sql.UniqueIdentifier, d.OperacionId],
      ]);
      const row = confirmed(sets[0]?.[0], d.OperacionId);
      if (row.ClienteId !== d.ClienteId || row.Activo !== d.Activo || row.Limite !== d.Limite || row.PlazoDias !== d.PlazoDias
        || typeof row.Version !== 'string' || !/^[a-f0-9]{16}$/i.test(row.Version)) throw new Error('Perfil SQL incompatible.');
      return row;
    },
    async payment(actor, body) {
      const d = v.payment(body);
      const sets = await call('dbo.sp_RegistrarAbonoCliente', actor, [
        ['ClienteId', sql.Int, d.ClienteId], ['FacturaId', sql.Int, d.FacturaId], ['Monto', sql.NVarChar(21), d.Monto],
        ['Referencia', sql.NVarChar(100), d.Referencia], ['OperacionId', sql.UniqueIdentifier, d.OperacionId],
      ]);
      const row = confirmed(sets[0]?.[0], d.OperacionId);
      try { v.bigint(row.AbonoId); v.bigint(row.ReciboId); } catch { throw new Error('Identidad SQL incompatible.'); }
      if (row.ClienteId !== d.ClienteId || row.FacturaId !== d.FacturaId || row.Monto !== d.Monto || row.ActorUsuarioId !== v.integer(actor)
        || typeof row.SaldoPosterior !== 'string' || !/^(?:0|[1-9]\d{0,16})\.\d{2}$/.test(row.SaldoPosterior)) throw new Error('Recibo incompatible.');
      return row;
    },
    async convert(actor, body) {
      const d = v.conversion(body);
      const [header, lines, metadata] = await call('dbo.P3_CRE_ConvertirCotizacionCredito', actor, [
        ['CotizacionId', sql.Int, d.CotizacionId], ['OperacionId', sql.UniqueIdentifier, d.OperacionId],
        ['PlazoDias', sql.Int, d.PlazoDias], ['NumeroCuotas', sql.Int, d.NumeroCuotas], ['BodegaId', sql.Int, d.BodegaId],
      ]);
      const documento = confirmed(metadata?.[0], d.OperacionId), factura = header?.[0];
      if (documento.CotizacionId !== d.CotizacionId || documento.Estado !== 'PROCESADA'
        || !Number.isInteger(documento.FacturaId) || documento.FacturaId < 1 || factura?.FacturaId !== documento.FacturaId) throw new Error('Conversion incompatible.');
      return { documento, factura, lineas: lines || [] };
    },
    async receipt(actor, id) {
      const sets = await call('dbo.P3_CRE_ConsultarRecibo', actor, [['AbonoId', sql.BigInt, v.bigint(id)]]);
      if (sets.length !== 2 || sets.some(set => !Array.isArray(set))) throw new Error('Recibo SQL incompatible.');
      const [rows, aplicaciones] = sets;
      if (rows[0]) {
        try { v.bigint(rows[0].AbonoId); v.bigint(rows[0].ReciboId); } catch { throw new Error('Identidad SQL incompatible.'); }
        if (rows[0].AbonoId !== id) throw new Error('Recibo SQL incompatible.');
      }
      return { recibo: rows[0] || null, aplicaciones };
    },
  };
}
module.exports = { createCreditoService };
