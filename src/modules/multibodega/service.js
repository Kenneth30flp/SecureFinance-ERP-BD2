'use strict';
const { sql, getPool } = require('../../config/database');
function createMultibodegaService(provider = getPool) {
  async function call(name, actor, params = []) {
    const request = (await provider()).request().input('ActorUsuarioId', sql.Int, actor);
    for (const [key, type, value] of params) request.input(key, type, value ?? null);
    return (await request.execute(name)).recordsets;
  }
  const types = {
    OperacionId: sql.UniqueIdentifier, ProductoId: sql.Int, BodegaId: sql.Int, OrigenId: sql.Int, DestinoId: sql.Int,
    TransferenciaId: sql.Int, CotizacionId: sql.Int, ProveedorId: sql.Int, Cantidad: sql.Int,
    Nombre: sql.NVarChar(100), Activo: sql.Bit, IsCentral: sql.Bit, Credito: sql.Bit,
    Codigo: sql.NVarChar(40), Direccion: sql.NVarChar(250), Responsable: sql.NVarChar(150),
    Motivo: sql.NVarChar(250), DocumentoRespaldo: sql.NVarChar(100), VersionEsperada: sql.Binary(8),
    Accion: sql.VarChar(10), PlazoDias: sql.Int, NumeroCuotas: sql.Int,
    // RPC string -> SQL DECIMAL(19,2). No JS Number/parseFloat on financial input.
    CostoUnitario: sql.VarChar(21),
  };
  const procedures = { bodega: 'dbo.P3_BOD_GuardarBodega', preparar: 'dbo.sp_TransferirStockBodegas', despachar: 'dbo.P3_BOD_AvanzarTransferencia', recibir: 'dbo.P3_BOD_AvanzarTransferencia', compra: 'dbo.P3_BOD_RegistrarCompra', cotizacion: 'dbo.P3_BOD_ConvertirCotizacion' };
  return {
    async authorize(actor, permiso) {
      await call('dbo.P3_BOD_Autorizar', actor, [['Permiso', sql.NVarChar(100), permiso]]);
    },
    async list(actor, seccion, f = {}, transferenciaId = null) {
      const sets = await call('dbo.P3_BOD_Consultar', actor, [
        ['Seccion', sql.VarChar(15), seccion], ['BodegaId', sql.Int, f.BodegaId], ['ProductoId', sql.Int, f.ProductoId],
        ['TransferenciaId', sql.Int, transferenciaId], ['Desplazamiento', sql.Int, ((f.pagina || 1) - 1) * 20],
        ['Desde', sql.DateTime2(3), f.Desde], ['Hasta', sql.DateTime2(3), f.Hasta],
        ['Buscar', sql.NVarChar(128), f.Buscar || null], ['Estado', sql.VarChar(12), f.Estado || null],
      ]);
      return { rows: (sets[0] || []).slice(0, 20), next: (sets[0] || []).length > 20, evidence: sets[1] || [] };
    },
    async operation(actor, id) {
      return (await call('dbo.P3_BOD_ConsultarOperacion', actor, [['OperacionId', sql.UniqueIdentifier, id]]))[0]?.[0] || null;
    },
    async mutate(actor, action, data) {
      if (!Object.hasOwn(procedures, action)) throw new TypeError('Accion no soportada.');
      const params = Object.entries(data).map(([k, value]) => {
        if (!Object.hasOwn(types, k)) throw new TypeError('Parametro no soportado.');
        return [k, types[k], k === 'VersionEsperada' ? Buffer.from(value, 'hex') : value];
      });
      const sets = await call(procedures[action], actor, params);
      // Los motores existentes pueden emitir varios recordsets. El ultimo es el recibo BOD.
      const raw = sets.at(-1)?.[0]?.Respuesta;
      if (typeof raw !== 'string') throw new Error('Resultado no confirmado.');
      const result = JSON.parse(raw);
      if (String(result.OperacionId).toLowerCase() !== data.OperacionId) throw new Error('Referencia de respuesta incompatible.');
      return result;
    },
  };
}
module.exports = { createMultibodegaService };
