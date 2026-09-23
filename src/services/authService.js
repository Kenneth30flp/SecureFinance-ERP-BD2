'use strict';

const { sql, getPool } = require('../config/database');

function createAuthService(poolProvider = getPool) {
  return {
    async login(nombreUsuario, password) {
      const pool = await poolProvider();
      const result = await pool.request()
        .input('NombreUsuario', sql.NVarChar(sql.MAX), nombreUsuario)
        .input('Password', sql.NVarChar(sql.MAX), password)
        .execute('dbo.sp_Login');
      const row = result.recordset?.[0];
      const outcomes = ['EXITOSO', 'USUARIO_INEXISTENTE', 'USUARIO_INACTIVO', 'PASSWORD_INCORRECTA'];
      if (result.recordset?.length !== 1 || !Number.isInteger(row?.Codigo)
          || !outcomes[row.Codigo] || outcomes[row.Codigo] !== row.Resultado) {
        throw new Error('Respuesta de autenticación no válida.');
      }
      if (row.Codigo !== 0) return { codigo: row.Codigo };
      if (!Number.isInteger(row.UsuarioId) || row.UsuarioId <= 0 || row.Activo !== true
          || typeof row.NombreUsuario !== 'string' || typeof row.Correo !== 'string'
          || typeof row.DebeCambiarPassword !== 'boolean') {
        throw new Error('Datos de usuario no válidos.');
      }
      const permissions = await pool.request()
        .input('UsuarioId', sql.Int, row.UsuarioId)
        .execute('dbo.sp_ObtenerPermisosUsuario');
      if (!Array.isArray(permissions.recordset)
          || permissions.recordset.some((item) => typeof item.Codigo !== 'string')) {
        throw new Error('Respuesta de permisos no válida.');
      }
      return {
        codigo: 0,
        usuario: {
          usuarioId: row.UsuarioId,
          nombreUsuario: row.NombreUsuario,
          correo: row.Correo,
          debeCambiarPassword: row.DebeCambiarPassword,
          permisos: [...new Set(permissions.recordset.map((item) => item.Codigo))],
        },
      };
    },
  };
}

module.exports = { createAuthService };
