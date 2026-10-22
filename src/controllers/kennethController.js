'use strict';
const { randomBytes, randomUUID, timingSafeEqual, createHash } = require('node:crypto');
const v = require('./kennethValidation');
const can = (req, permission) => req.session.usuario.permisos?.includes(permission);
const messages = new Map([[54114, 'El NIT ya esta registrado.'], [54101, 'Tu usuario no tiene autorización vigente.'], [54102, 'Revisa los datos ingresados.'], [54103, 'El registro cambió. Actualiza la página antes de guardar.'], [54104, 'La referencia no existe o está inactiva.'], [54110, 'Kardex está deshabilitado; solicita la activación al responsable.'], [54112, 'La referencia del movimiento ya se utilizó con otros datos.'], [54113, 'Stock insuficiente o cantidad fuera de rango.'], [54407, 'El inventario necesita conciliación. Comunícate con el responsable.'], [2601, 'El SKU o NIT ya está registrado.'], [2627, 'El SKU o NIT ya está registrado.'], [547, 'Los datos incumplen una restricción o relación vigente.']]);
function failure(res, error) {
  if ([54802,54803,54804,54805].includes(error.number)) return res.status(error.number===54803?409:400).json({error:error.number===54804?'El monto supera el saldo disponible. Actualiza la nota antes de continuar.':error.number===54803?'La referencia ya se utilizó con otros datos o la operación está ocupada. Reintenta con la misma referencia.':'Revisa los datos y el documento de respaldo.'});
  const status = error.status || (error.number === 54101 ? 403 : [54103,54112,54113,54407].includes(error.number) ? 409 : messages.has(error.number) ? 400 : 503);
  return res.status(status).json({ error: error.status ? error.message : messages.get(error.number) || 'No fue posible confirmar el resultado. Consulta el registro antes de volver a enviarlo.' });
}
function csrf(req, res, next) {
  const token = req.get('X-CSRF-Token'), expected = req.session.kennethCsrf;
  if (typeof token !== 'string' || !/^[a-f0-9]{64}$/.test(token) || typeof expected !== 'string' || !timingSafeEqual(Buffer.from(token), Buffer.from(expected))) return res.status(403).json({ error: 'Actualiza la página e inténtalo nuevamente.' });
  return next();
}
function createKennethController(services) {
  return {
    async show(req, res) {
      const module = req.baseUrl.slice(1), actor = req.session.usuario.usuarioId;
      try {
        const f = v.filters(req.query);
        f.nuevo = req.query.nuevo === '1';
        f.editar = req.query.editar === '1';
        f.vista = req.query.vista === 'tabla' ? 'tabla' : 'galeria';
        f.estado = ['activo','inactivo'].includes(req.query.estado) ? req.query.estado : '';
        const inventory = module === 'inventario';
        const service = inventory ? services.productos : services[module];
        const params = { ...f, id: null, inventario: inventory, costo: !inventory && module === 'productos' && can(req, 'PRODUCTOS_ADMINISTRAR') };
        const list = await service.list(actor, params);
        let selected = f.id ? (await service.list(actor, { ...params, buscar: '', offset: 0, id: f.id }))[0] : null;
        if (f.id && !selected) return res.status(404).type('text').send('El registro no está disponible.');
        if (!selected && !f.nuevo && module !== 'productos') { selected = list[0] || null; f.id = selected?.[module === 'clientes' ? 'ClienteId' : module === 'proveedores' ? 'ProveedorId' : 'ProductoId'] || null; }
        let suppliers = [];
        const relations = selected && ['productos','proveedores'].includes(module) ? await services.productos.relations(actor,module==='productos'?{productoId:selected.ProductoId}:{proveedorId:selected.ProveedorId}) : [];
        // El selector busca proveedores por nombre; no depende de cargar todos los registros.
        if ((module === 'productos' || inventory) && can(req, 'PROVEEDORES_CONSULTAR')) suppliers = await services.proveedores.list(actor, { buscar: '', offset: 0 });
        const state = inventory ? (await services.inventario.state(actor))[0] : null;
        if (inventory && !state) throw new Error('Estado de inventario ausente');
        const history = inventory && selected ? await services.inventario.history(actor, f) : [];
        req.session.kennethCsrf ||= randomBytes(32).toString('hex');
        const operation = randomUUID();
        if (inventory && selected) {
          req.session.inventoryOps ||= {};
          const keys = Object.keys(req.session.inventoryOps);
          if (keys.length >= 30) delete req.session.inventoryOps[keys[0]];
          req.session.inventoryOps[operation] = null;
        }
        return res.render(module, { usuario: req.session.usuario, csrf: req.session.kennethCsrf, f, rows: list.slice(0,50), next: list.length > 50, selected, suppliers, relations, state, history: history.slice(0,50), historyNext: history.length > 50, operation });
      } catch (error) {
        if (error.status) return res.status(error.status).type('text').send(error.message);
        req.session.kennethCsrf ||= randomBytes(32).toString('hex');
        return res.status(error.number === 54101 ? 403 : 503).render('kenneth-unavailable',{usuario:req.session.usuario,csrf:req.session.kennethCsrf,actual:module,error:error.number===54101?messages.get(54101):'El módulo no está disponible. Contacta al responsable e inténtalo nuevamente.'});
      }
    },
    async associate(req,res) {
      try {const d={id:v.integer(req.params.id),ProveedorId:v.integer(req.body?.ProveedorId),Activo:v.active(req.body?.Activo)};await services.productos.associate(req.session.usuario.usuarioId,d);return res.json({id:d.id});}catch(e){return failure(res,e);}
    },
    async suppliers(req, res) {
      try { return res.json({ rows: await services.proveedores.list(req.session.usuario.usuarioId, { buscar: v.text(req.query.buscar ?? '',150,false) || '' }) }); } catch (e) { return failure(res,e); }
    },
    async save(req, res) {
      const module = req.baseUrl.slice(1), actor = req.session.usuario.usuarioId;
      try {
        const b = req.body || {}, id = req.params.id ? v.integer(req.params.id) : null;
        let d = { id };
        if (id) d.Version = v.version(b.Version);
        if (module === 'productos') {
          if (!id && b.ModoCodigo !== undefined && !['AUTOMATICO','MANUAL'].includes(b.ModoCodigo)) throw new v.ValidationError('Selecciona SKU automático o manual.');
          const automatic = !id && b.ModoCodigo !== 'MANUAL';
          d = { ...d, CodigoAutomatico: automatic, Codigo: automatic ? null : v.text(b.Codigo,40), Descripcion: v.text(b.Descripcion,200), Precio: v.money(b.Precio), PrecioCosto: v.money(b.PrecioCosto), ProveedorId: v.integer(b.ProveedorId), StockMinimo: v.integer(b.StockMinimo,0), PuntoReorden: v.integer(b.PuntoReorden,0), GarantiaMeses: v.integer(b.GarantiaMeses,0,32767), Activo: id ? v.active(b.Activo) : true };
          if (d.PuntoReorden < d.StockMinimo) throw new v.ValidationError('El punto de reorden debe ser igual o mayor al stock mínimo.');
          const current = id ? (await services.productos.list(actor, { id, costo:true }))[0] : null;
          if (id && !current) throw new v.ValidationError('Producto no disponible.');
          d.Fotografia = current?.Fotografia || null;
          if (b.QuitarFotografia === true) d.Fotografia = null;
          if (b.UploadToken) {
            if (typeof b.UploadToken !== 'string' || !Object.hasOwn(req.session.pendingPhotos||{},b.UploadToken)) throw new v.ValidationError('Carga no disponible.');
            const pending = req.session.pendingPhotos[b.UploadToken];
            if (!pending || pending.expires < Date.now()) throw new v.ValidationError('La carga expiró. Selecciona nuevamente la fotografía.');
            d.Fotografia = pending.ref;
            // Finalizar antes de SQL evita que una cancelacion concurrente borre una foto asociada.
            if(!pending.retained){await services.photos.retain(pending.ref);pending.retained=true;await new Promise((resolve,reject)=>req.session.save(e=>e?reject(e):resolve()));}
          }
        } else if (module === 'proveedores') {
          d = { ...d, NIT: v.nit(b.NIT), Nombre: v.text(b.Nombre,150), Correo: v.text(b.Correo,254,false), Telefono: v.text(b.Telefono,25,false), Direccion: v.text(b.Direccion,300,false), Activo: id ? v.active(b.Activo) : true };
          if (d.Correo && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(d.Correo)) throw new v.ValidationError('Ingresa un correo válido.');
          d.Fotografia = id ? (await services.proveedores.list(actor,{ id }))[0]?.Fotografia || null : null;
        } else if (module === 'clientes') {
          d = { ...d, ...v.contact(b) };
          if (!id) d.NIT = v.nit(b.NIT);
        } else throw new v.ValidationError('Operación inválida.');
        const result = await services[module].save(actor,d);
        if (!result[0]) throw new Error('Respuesta ausente');
        if (module === 'productos' && b.UploadToken) delete req.session.pendingPhotos[b.UploadToken];
        return res.status(id ? 200 : 201).json({ id: result[0][module === 'productos' ? 'ProductoId' : module === 'clientes' ? 'ClienteId' : 'ProveedorId'], ...(module === 'productos' ? { codigo: result[0].Codigo } : {}) });
      } catch (e) { return failure(res,e); }
    },
    async client(req,res) {
      try {
        const d = { id:v.integer(req.params.id),Version:v.version(req.body?.Version),Motivo:v.text(req.body?.Motivo,250) };
        if (req.params.action === 'nit') d.NIT = v.nit(req.body?.NIT);
        await services.clientes.update(req.session.usuario.usuarioId,d,req.params.action === 'inactivar');
        return res.json({ id:d.id });
      } catch(e) { return failure(res,e); }
    },
    async move(req,res) {
      try {
        const b = req.body || {}, type = b.TipoMovimiento;
        if (!['COMPRA','AJUSTE_INGRESO','AJUSTE_EGRESO'].includes(type)) throw new v.ValidationError('Selecciona un ingreso por compra o un ajuste autorizado.');
        if (!can(req,type === 'COMPRA' ? 'INVENTARIO_REGISTRAR' : 'INVENTARIO_AJUSTAR')) return res.status(403).json({error:'No tienes permiso para este movimiento.'});
        const d = { id:v.integer(b.ProductoId),Version:v.version(b.Version),TipoMovimiento:type,Cantidad:v.integer(b.Cantidad),DocumentoRespaldo:v.text(b.DocumentoRespaldo,100),Motivo:v.text(b.Motivo,250),OperacionId:b.OperacionId };
        if (typeof d.OperacionId !== 'string' || !Object.hasOwn(req.session.inventoryOps || {},d.OperacionId)) throw new v.ValidationError('Actualiza la página para obtener una referencia de operación.');
        if (type === 'COMPRA') {
          d.ProveedorId = v.integer(b.ProveedorId);
          d.CostoUnitario = b.CostoUnitario ? v.money(b.CostoUnitario) : null;
        }
        const fingerprint = createHash('sha256').update(JSON.stringify(d)).digest('hex');
        if (req.session.inventoryOps[d.OperacionId] && req.session.inventoryOps[d.OperacionId] !== fingerprint) return res.status(409).json({error:'Esta referencia ya se utilizó con otros datos. Consulta el historial.'});
        req.session.inventoryOps[d.OperacionId] = fingerprint;
        await new Promise((resolve,reject)=>req.session.save(e=>e?reject(e):resolve()));
        const result = type === 'COMPRA' ? await services.inventario.receive(req.session.usuario.usuarioId,d) : await services.inventario.move(req.session.usuario.usuarioId,d);
        return res.status(201).json({ id:d.id,movimiento:result[0]?.KardexId });
      } catch(e) { return failure(res,e); }
    },
  };
}
module.exports = { createKennethController, csrf, failure };
