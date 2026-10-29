'use strict';
const areas = [
  ['inicio','Inicio','dashboard'],['ventas','Ventas','receipt'],['inventario','Inventario','box'],
  ['compras','Compras','users'],['finanzas','Finanzas','activity'],['administracion','Administración','shield'],
].map(([id,name,icon])=>({id,name,icon}));
const modules = [
  ['dashboard','inicio','Centro de operaciones','/dashboard','dashboard','Tu panorama operativo.',[]],
  ['analitica','inicio','Analítica ejecutiva','/analitica','activity','Indicadores para decidir.',['ANALITICA_CONSULTAR']],
  ['facturacion','ventas','Facturación','/facturacion','receipt','Registrar ventas y consultar comprobantes.',['VENTAS_REGISTRAR','FACTURAS_CONSULTAR']],
  ['cotizaciones','ventas','Cotizaciones','/cotizaciones','receipt','Preparar propuestas y convertirlas a factura.',['COTIZACIONES_CONSULTAR','COTIZACIONES_CREAR']],
  ['promociones','ventas','Promociones y descuentos','/promociones','activity','Reglas comerciales, vigencias e historial.',['PROMOCIONES_CONSULTAR']],
  ['clientes','ventas','Clientes','/clientes','user','Información y relaciones comerciales.',['CLIENTES_CONSULTAR']],
  ['devoluciones','ventas','Devoluciones','/devoluciones','receipt','Gestionar la posventa.',['DEVOLUCIONES_CONSULTAR']],
  ['garantias','ventas','Garantías','/garantias','shield','Seguimiento de garantías.',['GARANTIAS_CONSULTAR']],
  ['inventario','inventario','Existencias y Kardex','/inventario','box','Consultar stock y movimientos por producto.',['INVENTARIO_CONSULTAR']],
  ['productos','inventario','Productos','/productos','box','Administrar el catálogo comercial.',['PRODUCTOS_CONSULTAR']],
  ['proveedores','compras','Proveedores','/proveedores','users','Directorio de abastecimiento.',['PROVEEDORES_CONSULTAR']],
  ['notas-credito','finanzas','Notas de crédito','/notas-credito','receipt','Documentos comerciales de devolución.',['DEVOLUCIONES_CONSULTAR']],
  ['creditos','finanzas','Cuentas por cobrar y créditos','/creditos','activity','Autorizar crédito, consultar cuotas y registrar abonos.',['CREDITOS_CONSULTAR']],
  ['auditoria','administracion','Auditoría','/auditoria','shield','Consultar trazabilidad operativa.',['AUDITORIA_CONSULTAR']],
  ['auditoria-ddl','administracion','Auditoría DDL','/auditoria/ddl','shield','Consultar eventos y comandos estructurales.',['AUDITORIA_DDL_CONSULTAR']],
  ['usuarios','administracion','Usuarios y Roles','/usuarios','users','Administrar cuentas y accesos.',['USUARIOS_ADMINISTRAR']],
  ['password','administracion','Seguridad de cuenta','/cambiar-password','key','Cambiar tu contraseña.',[]],
].map(([id,area,name,route,icon,description,permissions],order)=>Object.freeze({id,area,name,route,icon,description,permissions:Object.freeze(permissions),permissionMode:'any',available:true,order}));
const planned = [ ['compras-p3','compras','Órdenes de compra'],['multibodega','inventario','Gestión multibodega'] ].map(([id,area,name],order)=>Object.freeze({id,area,name,route:null,available:false,order:100+order,permissions:[]}));
function visibleAreas(user){
 const permissions=user?.permisos||[];
 return areas.map(area=>({...area,modules:modules.filter(m=>m.area===area.id && (!m.permissions.length||m.permissions.some(p=>permissions.includes(p)))).map(m=>({...m,route:m.id==='cotizaciones'&&!permissions.includes('COTIZACIONES_CONSULTAR')?'/cotizaciones/nueva':m.route}))}));
}
module.exports={areas:Object.freeze(areas),modules:Object.freeze([...modules,...planned]),visibleAreas};
