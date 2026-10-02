'use strict';

const { randomBytes, timingSafeEqual } = require('node:crypto');

const erroresSQL = new Map([
  [52012, 'El descuento máximo autorizado para tu rol es 10%.'],
  [52013, 'No tienes permiso para registrar ventas.'],
  [52014, 'Selecciona un motivo de descuento válido.'],
  [52011, 'El descuento debe estar entre 0.00 y 100.00.'],
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
        const [clientes, productos, politica] = await Promise.all([
          ventaService.listarClientes(), ventaService.listarProductos(),
          ventaService.obtenerPolitica(req.session.usuario.usuarioId),
        ]);
        // Token limitado a facturación, sin modificar autenticación ni sesiones globales.
        req.session.ventaCsrf ||= randomBytes(32).toString('hex');
        return res.render('facturacion', {
          usuario: req.session.usuario, clientes, productos, politica, csrf: req.session.ventaCsrf,
        });
      } catch (error) {
        if (error.number === 52013 || error.number === 52007) return res.status(403).type('text').send('No tienes permiso para registrar ventas.');
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
      const { ClienteId, Detalle, MotivoDescuento = null } = req.body || {};
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
        const descuento = item.DescuentoPorcentaje === undefined ? '0' : item.DescuentoPorcentaje;
        if (!['number', 'string'].includes(typeof descuento)
            || !/^\d{1,3}(?:\.\d{1,2})?$/.test(String(descuento))
            || Number(descuento) > 100) {
          return res.status(400).json({ error: 'El descuento debe estar entre 0.00 y 100.00, con hasta dos decimales.' });
        }
        const DescuentoPorcentaje = Number(descuento);
        ids.add(ProductoId);
        // Lista explícita: ignora UsuarioId, precios e importes enviados por el navegador.
        lineas.push({ ProductoId, Cantidad, DescuentoPorcentaje });
      }
      if (MotivoDescuento !== null && !['Promoción', 'Cliente frecuente', 'Ajuste comercial',
        'Autorización administrativa', 'Otro'].includes(MotivoDescuento)) {
        return res.status(400).json({ error: 'Selecciona un motivo de descuento válido.' });
      }
      try {
        const politica = await ventaService.obtenerPolitica(usuarioId);
        if (lineas.some((linea) => linea.DescuentoPorcentaje > Number(politica.MaxDescuento))) {
          return res.status(400).json({ error: `El descuento máximo autorizado para tu rol es ${Number(politica.MaxDescuento)}%.` });
        }
        const venta = await ventaService.procesarVenta(clienteId, usuarioId, lineas,
          lineas.some((linea) => linea.DescuentoPorcentaje > 0) ? MotivoDescuento : null);
        return res.status(201).json({ venta });
      } catch (error) {
        const message = erroresSQL.get(error.number);
        if (message) return res.status(error.number === 52013 || error.number === 52007 ? 403 : error.number === 52010 ? 409 : 400).json({ error: message });
        // Un timeout puede suceder después del COMMIT: no reintentar automáticamente.
        return res.status(503).json({ error: 'No fue posible confirmar el resultado. Consulta con el responsable antes de volver a enviar la venta.' });
      }
    },
  };
}

module.exports = { createVentaController };
