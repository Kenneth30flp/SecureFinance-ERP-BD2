'use strict';
const { sql, getPool } = require('../../config/database');
function idList(values) {
  const table = new sql.Table('dbo.P3_PRO_TipoListaIds');
  table.columns.add('Id', sql.Int, { nullable: false });
  for (const id of values) table.rows.add(id);
  return table;
}
function saleDetail(lines) {
  const table = new sql.Table('dbo.TipoDetalleVentaDescuento');
  table.columns.add('ProductoId', sql.Int, { nullable: false });
  table.columns.add('Cantidad', sql.Int, { nullable: false });
  table.columns.add('DescuentoPorcentaje', sql.Decimal(5, 2), { nullable: false });
  for (const l of lines) table.rows.add(l.ProductoId, l.Cantidad, l.DescuentoPorcentaje);
  return table;
}
// Decimales validados como texto; DECIMAL(5,2)/(19,2) exactos al convertirlos en el driver.
const amount = (value) => (value === null ? null : Number(value));
function createPromocionService(provider = getPool) {
  async function call(name, actor, params = []) {
    const r = (await provider()).request().input('ActorUsuarioId', sql.Int, actor);
    for (const [key, type, value] of params) {
      if (type instanceof sql.Table) r.input(key, type);
      else r.input(key, type, value ?? null);
    }
    return (await r.execute(name)).recordsets;
  }
  const ruleParams = (d) => [
    ['OperacionId', sql.UniqueIdentifier, d.OperacionId], ['Nombre', sql.NVarChar(120), d.Nombre],
    ['Descripcion', sql.NVarChar(250), d.Descripcion], ['TipoCodigo', sql.VarChar(20), d.TipoCodigo],
    ['Porcentaje', sql.Decimal(5, 2), amount(d.Porcentaje)], ['CantidadMinima', sql.Int, d.CantidadMinima],
    ['TopeDescuento', sql.Decimal(19, 2), amount(d.TopeDescuento)], ['VigenteDesde', sql.DateTime2(3), d.VigenteDesde],
    ['VigenteHasta', sql.DateTime2(3), d.VigenteHasta], ['Productos', idList(d.Productos)],
    ['Categorias', idList(d.Categorias)], ['Motivo', sql.NVarChar(250), d.Motivo],
  ];
  return {
    async form(actor) {
      const [tipos, categorias, reloj] = await call('dbo.P3_PRO_PrepararFormulario', actor);
      return { tipos, categorias, ahora: reloj?.[0]?.Ahora };
    },
    async searchProducts(actor, buscar, categoriaId = null) {
      const rows = (await call('dbo.P3_PRO_BuscarProductos', actor, [['Buscar', sql.NVarChar(150), buscar], ['CategoriaId', sql.Int, categoriaId]]))[0];
      return { rows: rows.slice(0, 8), next: rows.length > 8 };
    },
    async list(actor, f) {
      return (await call('dbo.P3_PRO_Consultar', actor, [['Buscar', sql.NVarChar(150), f.buscar || null], ['Tipo', sql.VarChar(20), f.tipo || null],
        ['Estado', sql.VarChar(10), f.estado || null], ['Desplazamiento', sql.Int, (f.pagina - 1) * 20]]))[0];
    },
    async detail(actor, id) {
      const [rows, productos, categorias, historial, aplicaciones] = await call('dbo.P3_PRO_Consultar', actor, [['Id', sql.Int, id]]);
      return { promocion: rows?.[0] || null, productos: productos || [], categorias: categorias || [], historial: historial || [], aplicaciones: aplicaciones || [] };
    },
    async create(actor, d) {
      return (await call('dbo.P3_PRO_Crear', actor, [['Codigo', sql.NVarChar(30), d.Codigo], ...ruleParams(d)]))[0][0];
    },
    async update(actor, id, d) {
      return (await call('dbo.P3_PRO_Actualizar', actor, [['PromocionId', sql.Int, id], ['VersionEsperada', sql.Binary(8), Buffer.from(d.Version, 'hex')], ...ruleParams(d)]))[0][0];
    },
    async setState(actor, id, d) {
      return (await call('dbo.P3_PRO_CambiarEstado', actor, [['PromocionId', sql.Int, id], ['VersionEsperada', sql.Binary(8), Buffer.from(d.Version, 'hex')],
        ['Activa', sql.Bit, d.Activa], ['OperacionId', sql.UniqueIdentifier, d.OperacionId], ['Motivo', sql.NVarChar(250), d.Motivo]]))[0][0];
    },
    async createCategory(actor, d) {
      return (await call('dbo.P3_PRO_CrearCategoria', actor, [['Nombre', sql.NVarChar(80), d.Nombre], ['OperacionId', sql.UniqueIdentifier, d.OperacionId], ['Motivo', sql.NVarChar(250), d.Motivo]]))[0][0];
    },
    async assignCategory(actor, d) {
      return (await call('dbo.P3_PRO_AsignarCategoria', actor, [['ProductoId', sql.Int, d.ProductoId], ['CategoriaId', sql.Int, d.CategoriaId],
        ['OperacionId', sql.UniqueIdentifier, d.OperacionId], ['Motivo', sql.NVarChar(250), d.Motivo]]))[0][0];
    },
    // Vista previa informativa; la venta repite el cálculo en SQL al confirmar.
    async preview(actor, lines) {
      const [totales, lineas] = await call('dbo.P3_PRO_SimularVenta', actor, [['Detalle', saleDetail(lines)]]);
      return { totales: totales[0], lineas };
    },
    async invoiceApplications(actor, facturaId) {
      try {
        return (await call('dbo.P3_PRO_ConsultarAplicacionesFactura', actor, [['FacturaId', sql.Int, facturaId]]))[0] || [];
      } catch (error) {
        if (error.number === 2812) return [];
        throw error;
      }
    },
  };
}
module.exports = { createPromocionService };
