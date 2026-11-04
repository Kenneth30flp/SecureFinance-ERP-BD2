'use strict';
const { runSql, lit } = require('./sqlcmd.cjs');
async function configure(o) {
  const warning=Number(o.warning),critical=Number(o.critical);
  if(!o.authorized || !o.database || !o.expectedServer || !Number.isFinite(warning) || !Number.isFinite(critical)
    || warning<=0 || warning>=critical || critical>100) throw Error('Destino, autorizacion y umbrales 0 < aviso < critico <= 100 requeridos.');
  return runSql(`IF NOT EXISTS(SELECT 1 FROM dbo.P4_LDF_Configuracion c JOIN sys.database_recovery_status r ON r.database_id=DB_ID() AND r.database_guid=c.DatabaseGuid WHERE c.Id=1 AND c.BaseDatos=DB_NAME() AND c.Servidor=${lit(o.expectedServer)}) THROW 59010,'Destino LDF no autorizado',1;
UPDATE dbo.P4_LDF_Configuracion SET Advertencia=${warning.toFixed(2)},Critico=${critical.toFixed(2)} WHERE Id=1;
PRINT 'Umbrales actualizados. No se ejecutaron operaciones sobre el LOG.';`,o);
}
module.exports={configure};
if(require.main===module){const e=process.env;configure({authorized:process.argv.includes('--authorize-config'),database:e.LDF_INSTALL_DATABASE,server:e.LDF_INSTALL_SERVER||'localhost',expectedServer:e.LDF_EXPECTED_SERVER,warning:e.LDF_WARNING_PERCENT,critical:e.LDF_CRITICAL_PERCENT}).then(console.log).catch(error=>{console.error(error.message);process.exitCode=1;});}
