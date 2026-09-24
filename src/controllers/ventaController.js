'use strict';

const { randomBytes, timingSafeEqual } = require('node:crypto');

const erroresSQL = new Map([
  [52001, 'Agrega al menos un producto.'],
  [52002, 'La venta admite hasta 100 productos.'],
  [52003, 'El producto y la cantidad deben ser enteros positivos.'],
  [52004, 'Cada producto debe aparecer una sola vez.'],
  [52005, 'El cliente no existe.'],
  [52006, 'El cliente está inactivo.'],
  [52007, 'El usuario no existe o está inactivo.'],
  [52008, 'Uno de los productos no existe.'],
  [52009, 'Uno de los productos está inactivo.'],
  [52010, 'Stock insuficiente. Actualiza la página y revisa las cantidades.'],
]);

function enteroPositivo(value) {
  if (typeof value !== 'number' && (typeof value !== 'string' || !/^[1-9]\d{0,9}$/.test(value))) return null;
  const number = Number(value);
  return Number.isInteger(number) && number > 0 && number <= 2147483647 ? number : null;
}

function createVentaController(ventaService) {
  return {
    async mostrar(req, res) {
      try {
        const [clientes, productos] = await Promise.all([
          ventaService.listarClientes(), ventaService.listarProductos(),
        ]);
        // Token limitado a facturación, sin modificar autenticación ni sesiones globales.
        req.session.ventaCsrf ||= randomBytes(32).toString('hex');
        return res.render('facturacion', {
          usuario: req.session.usuario, clientes, productos, csrf: req.session.ventaCsrf,
        });
      } catch {
        return res.status(503).type('text').send('No fue posible cargar facturación. Inténtalo nuevamente.');
      }
    },
    async procesar(req, res) {
      const token = req.get('X-CSRF-Token');
      const expected = req.session.ventaCsrf;
      if (typeof token !== 'string' || typeof expected !== 'string'
          || !/^[a-f0-9]{64}$/.test(token)
          || !timingSafeEqual(Buffer.from(token), Buffer.from(expected))) {
        return res.status(403).json({ error: 'Actualiza la página de facturación e inténtalo nuevamente.' });
      }
      const { ClienteId, Detalle } = req.body || {};
      const clienteId = enteroPositivo(ClienteId);
      const usuarioId = enteroPositivo(req.session.usuario.usuarioId);
      if (!clienteId || !usuarioId || !Array.isArray(Detalle) || Detalle.length < 1 || Detalle.length > 100) {
        return res.status(400).json({ error: 'Selecciona un cliente y entre 1 y 100 productos válidos.' });
      }
      const lineas = [];
      const ids = new Set();
      for (const item of Detalle) {
        const ProductoId = enteroPositivo(item?.ProductoId);
        const Cantidad = enteroPositivo(item?.Cantidad);
        if (!ProductoId || !Cantidad || ids.has(ProductoId)) {
          return res.status(400).json({ error: 'Usa productos únicos y cantidades enteras positivas.' });
        }
        ids.add(ProductoId);
        // Lista explícita: ignora UsuarioId, precios e importes enviados por el navegador.
        lineas.push({ ProductoId, Cantidad });
      }
      try {
        const venta = await ventaService.procesarVenta(clienteId, usuarioId, lineas);
        return res.status(201).json({ venta });
      } catch (error) {
        const message = erroresSQL.get(error.number);
        if (message) return res.status(error.number === 52010 ? 409 : 400).json({ error: message });
        // Un timeout puede suceder después del COMMIT: no reintentar automáticamente.
        return res.status(503).json({ error: 'No fue posible confirmar el resultado. Consulta con el responsable antes de volver a enviar la venta.' });
      }
    },
  };
}

module.exports = { createVentaController };
