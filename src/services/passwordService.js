'use strict';

const { randomBytes, createHash } = require('node:crypto');
const { sql, getPool } = require('../config/database');

function tokenHash(token) {
  if (typeof token !== 'string' || !/^[a-f0-9]{64}$/.test(token)) return null;
  return createHash('sha512').update(token, 'utf8').digest();
}

function createPasswordService(poolProvider = getPool) {
  async function execute(procedure, inputs) {
    const request = (await poolProvider()).request();
    for (const [name, type, value] of inputs) request.input(name, type, value);
    const result = (await request.execute(procedure)).recordset?.[0];
    if (!result) throw new Error('Respuesta de contraseña no válida.');
    return result;
  }
  return {
    async solicitar(identificador) {
      const token = randomBytes(32).toString('hex');
      const result = await execute('dbo.sp_SolicitarRecuperacionPassword', [
        ['UsuarioOCorreo', sql.NVarChar(sql.MAX), identificador],
        ['TokenHash', sql.VarBinary(sql.MAX), tokenHash(token)],
      ]);
      if (typeof result.Generado !== 'boolean') throw new Error('Respuesta no válida.');
      return result.Generado ? token : null;
    },
    async validar(token) {
      const hash = tokenHash(token);
      if (!hash) return false;
      const result = await execute('dbo.sp_ValidarTokenRecuperacion', [['TokenHash', sql.VarBinary(sql.MAX), hash]]);
      if (typeof result.Valido !== 'boolean') throw new Error('Respuesta no válida.');
      return result.Valido;
    },
    async restablecer(token, password) {
      const hash = tokenHash(token);
      if (!hash) throw Object.assign(new Error('Token inválido.'), { number: 54001 });
      const result = await execute('dbo.sp_RestablecerPassword', [
        ['TokenHash', sql.VarBinary(sql.MAX), hash], ['Password', sql.NVarChar(sql.MAX), password],
      ]);
      if (result.Actualizado !== true) throw new Error('Respuesta no válida.');
    },
    async cambiar(usuarioId, actual, password) {
      const result = await execute('dbo.sp_CambiarPassword', [
        ['UsuarioId', sql.Int, usuarioId], ['PasswordActual', sql.NVarChar(sql.MAX), actual],
        ['Password', sql.NVarChar(sql.MAX), password],
      ]);
      if (result.Actualizado !== true) throw new Error('Respuesta no válida.');
    },
  };
}

module.exports = { createPasswordService };
