'use strict';
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawn } = require('node:child_process');
const { randomUUID } = require('node:crypto');
const root = path.resolve(__dirname, '../../..');
const lit = value => "N'" + String(value).replaceAll("'", "''") + "'";
const ident = value => '[' + String(value).replaceAll(']', ']]') + ']';
const prelude = 'SET NOCOUNT ON; SET XACT_ABORT ON; SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON; SET ANSI_PADDING ON; SET ANSI_WARNINGS ON; SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET NUMERIC_ROUNDABORT OFF;\n';
async function runSql(sql, { database, server = 'localhost', expectedServer, timeout = 180000 }) {
  if (!database || !expectedServer) throw Error('Destino y servidor esperado obligatorios.');
  // SQL input may contain provisioning secrets; avoid synchronized workspace folders.
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'securefinance-ldf-'));
  const input = path.join(dir, randomUUID() + '.sql'), output = input + '.out';
  try {
    fs.writeFileSync(input, prelude + `IF DB_NAME()<>${lit(database)} OR CONVERT(nvarchar(128),SERVERPROPERTY('ServerName'))<>${lit(expectedServer)} THROW 59010,'Destino inesperado',1;\n` + sql, { flag: 'wx' });
    const code = await new Promise((resolve, reject) => {
      const child = spawn('sqlcmd', ['-S', server, '-E', '-N', '-C', '-b', '-l', '8', '-r', '0', '-f', 'i:65001', '-u', '-y', '0', '-d', database, '-i', input, '-o', output], { windowsHide: true, stdio: 'ignore' });
      const timer = setTimeout(() => { child.kill(); reject(Error('SQL excedio el tiempo limite. Verifica estado antes de reintentar.')); }, timeout);
      child.on('error', e => { clearTimeout(timer); reject(e); });
      child.on('close', c => { clearTimeout(timer); resolve(c); });
    });
    const text = fs.existsSync(output) ? fs.readFileSync(output).toString('utf16le').replace(/^\uFEFF/, '') : '';
    // Do not echo SQL scripts: they can contain provisioning secrets.
    if (code !== 0) { const e = Error('sqlcmd fallo: ' + text.slice(-3500)); e.sqlcmd = true; throw e; }
    return text;
  } finally {
    fs.rmSync(input, { force: true }); fs.rmSync(output, { force: true });
    fs.rmdirSync(dir);
  }
}
async function queryJson(query, options) {
  const text = await runSql(`PRINT 'LDF_JSON_BEGIN'; SELECT CONVERT(nvarchar(max),(${query} FOR JSON PATH, INCLUDE_NULL_VALUES)); PRINT 'LDF_JSON_END';`, options);
  const body = text.split('LDF_JSON_BEGIN')[1]?.split('LDF_JSON_END')[0]?.replace(/[\r\n]/g, '').trim();
  if (!body) throw Error('Respuesta SQL JSON ausente.');
  // SQL Server can return SQL NULL for an empty nested FOR JSON result.
  if (body === 'NULL') return [];
  return JSON.parse(body);
}
module.exports = { runSql, queryJson, lit, ident, root, prelude };
