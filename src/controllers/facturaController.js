'use strict';
const { localDayBoundary } = require('../public/js/operationalDates');
function positive(value) {
  if(typeof value!=='string'||!/^[1-9]\d{0,9}$/.test(value)||Number(value)>2147483647) throw Object.assign(Error('Usa un número entero positivo válido.'),{status:400});
  return Number(value);
}
function filters(q) {
  const f={numero:q.numero?positive(q.numero):null,pagina:q.pagina?positive(q.pagina):1,
    cliente:q.cliente??'',desde:q.desde??'',hasta:q.hasta??''};
  if(typeof f.cliente!=='string'||f.cliente.length>150||f.pagina>1000000) throw Object.assign(Error('Revisa los filtros de búsqueda.'),{status:400});
  for(const key of ['desde','hasta']) { try{
    localDayBoundary(f[key]);
    if(f[key]&&(f[key]<'0001-01-01'||f[key]>'9998-12-31'))throw new RangeError();
  }catch{throw Object.assign(Error('Selecciona fechas válidas.'),{status:400});} }
  if(f.desde&&f.hasta&&f.desde>f.hasta) throw Object.assign(Error('La fecha final debe ser igual o posterior a la inicial.'),{status:400});
  f.cliente=f.cliente.trim();return f;
}
function createFacturaController(service) {
  function fail(req,res,error,f={numero:null,cliente:'',desde:'',hasta:'',pagina:1}) {
    console.error('ERP_INVOICE_QUERY_FAILURE',JSON.stringify({code:error.code,number:error.number,name:error.name}));
    const status=error.status|| (error.number===54101?403:503);
    return res.status(status).render('facturas',{usuario:req.session.usuario,f,rows:[],total:0,
      error:error.status?error.message:status===403?'Tu permiso de consulta ya no está vigente.':'No fue posible cargar las facturas. Inténtalo nuevamente.'});
  }
  return {
    async list(req,res){let f;try{f=filters(req.query);const rows=await service.list(req.session.usuario.usuarioId,f);
      return res.render('facturas',{usuario:req.session.usuario,f,rows,total:Number(rows[0]?.TotalFilas||0),error:null});
    }catch(error){return fail(req,res,error,f);}},
    async detail(req,res){try{const id=positive(req.params.id);const result=await service.detail(req.session.usuario.usuarioId,id);
      if(!result.factura)return res.status(404).render('facturas',{usuario:req.session.usuario,f:filters({}),rows:[],total:0,error:'La factura solicitada no existe.'});
      return res.render('factura-comprobante',{usuario:req.session.usuario,...result,autoPrint:req.query.imprimir==='1'});
    }catch(error){return fail(req,res,error);}},
  };
}
module.exports={createFacturaController,filters};
