'use strict';
const { sql, getPool } = require('../config/database');
function createUsuarioService(poolProvider = getPool) {
  async function execute(name, inputs = []) {
    const request = (await poolProvider()).request();
    for (const [key, type, value] of inputs) {
      if (value === undefined) request.input(key, type);
      else request.input(key, type, value);
    }
    return (await request.execute(name)).recordset;
  }
  return {
    permisosActuales: id => execute('dbo.sp_ObtenerPermisosUsuario', [['UsuarioId', sql.Int, id]]),
    listarUsuarios: () => execute('dbo.sp_ListarUsuariosAdministracion'),
    listarRolesActivos: () => execute('dbo.sp_ListarRolesActivos'),
    obtenerRolesUsuario: id => execute('dbo.sp_ObtenerRolesUsuario', [['UsuarioId', sql.Int, id]]),
    async actualizarRoles(id, roles, actor) {
      const tvp = new sql.Table('dbo.TipoRolUsuario');
      tvp.columns.add('RolId', sql.Int, { nullable: false });
      for (const rol of roles) tvp.rows.add(rol);
      return (await execute('dbo.sp_ActualizarRolesUsuario', [
        ['UsuarioId', sql.Int, id], ['Roles', tvp], ['ActorUsuarioId', sql.Int, actor],
      ]))[0];
    },
  };
}
module.exports = { createUsuarioService };
