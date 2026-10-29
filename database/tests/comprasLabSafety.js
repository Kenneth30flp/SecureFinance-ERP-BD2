'use strict';
const {randomUUID}=require('node:crypto');
const labPattern=/^SecureFinanceERP_P3_COM_LAB_[a-f0-9]{32}$/;
function plan(env,args){
  if(!args.includes('--execute-new-lab')||env.COMPRAS_SQL_WRITE_AUTHORIZATION!=='LAB_NUEVO_AISLADO')throw Error('Escrituras desactivadas. Requiere activacion explicita del laboratorio nuevo.');
  for(const key of ['COMPRAS_LAB_USER','COMPRAS_LAB_PASSWORD','COMPRAS_LAB_EXPECTED_SERVER'])if(!env[key]?.trim())throw Error('Falta '+key);
  if(env.COMPRAS_LAB_SERVER!=='localhost'||env.COMPRAS_LAB_INSTANCE!=='SQLEXPRESS')throw Error('Solo instancia local SQL Express declarada.');
  if(env.COMPRAS_LAB_DATABASE||env.DB_DATABASE||env.DB_NAME)throw Error('No se admite un destino preexistente ni configuracion DB heredada.');
  if(['sa','securefinance_app'].includes(env.COMPRAS_LAB_USER.toLowerCase()))throw Error('Se requiere login dedicado del laboratorio.');
  if(!/^[\w-]+\\SQLEXPRESS$/i.test(env.COMPRAS_LAB_EXPECTED_SERVER))throw Error('Identidad esperada de servidor invalida.');
  return{database:'SecureFinanceERP_P3_COM_LAB_'+randomUUID().replaceAll('-',''),marker:randomUUID(),instance:env.COMPRAS_LAB_EXPECTED_SERVER,
    config:{server:'localhost',user:env.COMPRAS_LAB_USER,password:env.COMPRAS_LAB_PASSWORD,database:'master',options:{instanceName:'SQLEXPRESS',encrypt:true,trustServerCertificate:true,appName:'SecureFinance-Compras-IsolatedTests'},requestTimeout:180000,pool:{max:8,min:0}}};
}
function assertServer(row,expected,databases,linkedServers,permissions){
  if(row?.DatabaseName!=='master'||row?.ServerName?.toLowerCase()!==expected.toLowerCase()||row.Sysadmin!==0||row.ServerRoleCount!==0||row.EngineEdition!==4)throw Error('Identidad Express o privilegios restringidos no comprobados.');
  const allowed=new Set(['CONNECT SQL','VIEW ANY DATABASE','CREATE ANY DATABASE']);
  if(!permissions.some(p=>p.permission_name==='VIEW ANY DATABASE')||!permissions.some(p=>p.permission_name==='CREATE ANY DATABASE')||permissions.some(p=>!allowed.has(p.permission_name)))throw Error('Privilegios de servidor fuera de la lista minima permitida.');
  // Rechazar incluso acceso de lectura a cualquier base de usuario anterior.
  // NULL/offline tambien es incierto y falla cerrado. No inferir por nombre.
  if(databases.some(d=>d.database_id>4&&(d.Access!==0||d.state!==0))||linkedServers.length)throw Error('No se comprobo aislamiento: base previa accesible/incierta o servidor vinculado.');
  if(row.MasterWrites!==0||row.ModelAccess!==0||row.MsdbWrites!==0)throw Error('Permisos de escritura en bases de sistema o acceso a model no permitidos.');
}
function assertIdentity(actual,expected,marker,expectedMarker){if(!labPattern.test(expected)||actual!==expected||!expectedMarker||marker!==expectedMarker)throw Error('Identidad de laboratorio incorrecta.');}
function batches(source){
  const code=source.replace(/^\s*--.*$/gm,'');
  if(/^\s*USE\s/im.test(code)||/\b(?:CREATE|ALTER|DROP|RESTORE|BACKUP)\s+(?:DATABASE|LOGIN|SERVER)\b/i.test(code)||/\b(?:OPENROWSET|OPENDATASOURCE|OPENQUERY|EXECUTE\s+AS\s+LOGIN)\b/i.test(code))throw Error('Migracion fuera de alcance.');
  return source.split(/^\s*GO\s*\r?$/im).filter(b=>b.trim());
}
function installer(source){return batches(source.replace(/^\s*USE\s+\[SecureFinanceERP\];\s*$/gm,''));}
module.exports={plan,assertServer,assertIdentity,batches,installer,labPattern};
