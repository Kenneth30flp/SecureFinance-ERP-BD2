'use strict';

// Prueba optativa real: node database/tests/TransactionIntegrationTests.js ".\SQLEXPRESS"
// Requiere sqlcmd, autenticación Windows y permiso CREATE DATABASE. Crea y elimina
// EXCLUSIVAMENTE su base temporal; no usa .env ni la base de Kenneth.
const { execFile, spawn } = require('node:child_process');
const { promisify } = require('node:util');
const { mkdtemp, readFile, writeFile, rm } = require('node:fs/promises');
const { tmpdir } = require('node:os');
const path = require('node:path');
const { randomBytes } = require('node:crypto');
const assert = require('node:assert/strict');
const execute = promisify(execFile);
const instance = process.argv[2];
const root = path.resolve(__dirname, '../..');

async function main() {
  if (!instance) throw new Error('Indica una instancia SQL Server de pruebas con autenticación Windows.');
  const database = `SecureFinanceERP_EdwardTest_${randomBytes(8).toString('hex')}`;
  const directory = await mkdtemp(path.join(tmpdir(), 'securefinance-sql-'));
  const args = ['-S', instance, '-E', '-C', '-b', '-l', '10', '-t', '30', '-f', '65001'];
  let created = false;
  let sequence = 0;
  async function sql(text, inDatabase = true) {
    const file = path.join(directory, `${sequence++}.sql`);
    await writeFile(file, `${inDatabase ? `USE [${database}];\nGO\n` : ''}${text}`, 'utf8');
    return (await execute('sqlcmd', [...args, '-i', file], { windowsHide: true, timeout: 45000 })).stdout;
  }
  async function install(file) {
    const source = await readFile(path.join(root, file), 'utf8');
    return sql(source.replace('USE [SecureFinanceERP];', `USE [${database}];`));
  }
  try {
    await sql(`CREATE DATABASE [${database}];`, false);
    created = true;
    for (const file of ['database/02_SecurityTables.sql', 'database/03_SecurityStoredProcedures.sql',
      'database/04_SecuritySeedData.sql', 'database/05_BusinessTables.sql',
      'database/05_BusinessSeedData.sql', 'database/06_TransactionProcedures.sql']) await install(file);
    console.log('OK: instalación SQL en base temporal aislada.');
    // Reejecutar scripts repetibles no restablece inventario ni duplica semillas.
    await sql("UPDATE dbo.Producto SET Stock = 49 WHERE Codigo = N'DEMO-TECLADO';");
    await install('database/05_BusinessSeedData.sql');
    await install('database/06_TransactionProcedures.sql');
    await sql(`IF (SELECT COUNT(*) FROM dbo.Cliente) <> 3 OR (SELECT COUNT(*) FROM dbo.Producto) <> 4
      OR (SELECT Stock FROM dbo.Producto WHERE Codigo = N'DEMO-TECLADO') <> 49
      THROW 52200, 'Semillas no idempotentes.', 1;`);
    for (const file of ['database/tests/SecurityTests.sql', 'database/tests/AuthenticationTests.sql',
      'database/tests/TransactionTests.sql']) {
      const output = await install(file);
      assert.match(output, /OK:/);
      console.log(`OK: ${file}`);
    }
    // Principal de prueba limitado a la base temporal; nunca se crea un login.
    await sql('CREATE USER securefinance_app WITHOUT LOGIN;');
    await install('database/07_TransactionPermissions.sql');
    await sql(`
      DECLARE @Cliente INT = (SELECT MIN(ClienteId) FROM dbo.Cliente),
        @Usuario INT = (SELECT MIN(UsuarioId) FROM dbo.Usuario WHERE Activo = 1),
        @Producto INT = (SELECT MIN(ProductoId) FROM dbo.Producto);
      EXECUTE AS USER = 'securefinance_app';
      DECLARE @Detalle dbo.TipoDetalleVenta;
      INSERT @Detalle VALUES (@Producto, 1);
      EXEC dbo.sp_ListarClientes;
      EXEC dbo.sp_ListarProductosDisponibles;
      BEGIN TRANSACTION;
      EXEC dbo.sp_ProcesarVentaTransaccional @Cliente, @Usuario, @Detalle;
      ROLLBACK TRANSACTION;
      BEGIN TRY
        SELECT * FROM dbo.Producto;
        THROW 52201, 'Acceso directo SELECT no debe estar permitido.', 1;
      END TRY BEGIN CATCH
        IF ERROR_NUMBER() <> 229 THROW;
      END CATCH;
      BEGIN TRY
        UPDATE dbo.Producto SET Stock = Stock WHERE ProductoId = @Producto;
        THROW 52202, 'Acceso directo UPDATE no debe estar permitido.', 1;
      END TRY BEGIN CATCH
        IF ERROR_NUMBER() <> 229 THROW;
      END CATCH;
      REVERT;`);
    console.log('OK: EXECUTE/REFERENCES del TVP y SP; SELECT/UPDATE directos denegados.');

    const output = await sql(`SET NOCOUNT ON;
      UPDATE dbo.Producto SET Stock = 1 WHERE Codigo IN (N'DEMO-TECLADO', N'DEMO-MOUSE');
      SELECT CONCAT('IDS:', (SELECT MIN(ClienteId) FROM dbo.Cliente), ':',
        (SELECT MIN(UsuarioId) FROM dbo.Usuario WHERE Activo = 1), ':',
        (SELECT ProductoId FROM dbo.Producto WHERE Codigo = N'DEMO-TECLADO'), ':',
        (SELECT ProductoId FROM dbo.Producto WHERE Codigo = N'DEMO-MOUSE'));`);
    const ids = output.match(/IDS:(\d+):(\d+):(\d+):(\d+)/);
    assert.ok(ids);
    const [, client, user, p1, p2] = ids;
    const sessionA = path.join(directory, 'concurrency-a.sql');
    await writeFile(sessionA, `USE [${database}]; SET NOCOUNT ON; SET XACT_ABORT ON;
      DECLARE @Detalle dbo.TipoDetalleVenta;
      INSERT @Detalle VALUES (${p2}, 1), (${p1}, 1);
      BEGIN TRANSACTION;
      EXEC dbo.sp_ProcesarVentaTransaccional ${client}, ${user}, @Detalle;
      RAISERROR ('STOCK_LOCKED', 10, 1) WITH NOWAIT;
      WAITFOR DELAY '00:00:04';
      COMMIT TRANSACTION;`, 'utf8');
    // Inicia B solo al saber que A ya descontó stock y conserva los bloqueos.
    const processA = spawn('sqlcmd', [...args, '-i', sessionA], { windowsHide: true });
    let stdout = '';
    let stderr = '';
    let startB;
    const locked = new Promise((resolve, reject) => {
      startB = resolve;
      processA.once('error', reject);
      processA.once('close', (code) => { if (!stdout.includes('STOCK_LOCKED')) reject(new Error(`Sesión A no obtuvo bloqueo (${code}): ${stderr}`)); });
    });
    processA.stdout.on('data', (data) => { stdout += data; if (stdout.includes('STOCK_LOCKED')) startB(); });
    processA.stderr.on('data', (data) => { stderr += data; });
    const completedA = new Promise((resolve, reject) => {
      processA.once('error', reject);
      processA.once('close', (code) => code === 0 ? resolve() : reject(new Error(`Sesión A falló: ${stderr}`)));
    });
    // Instalar manejadores antes de esperar evita rechazos no observados.
    completedA.catch(() => {});
    const timeout = setTimeout(() => processA.kill(), 20000);
    try {
      await locked;
      await Promise.all([completedA, sql(`SET NOCOUNT ON;
        DECLARE @Detalle dbo.TipoDetalleVenta;
        INSERT @Detalle VALUES (${p1}, 1), (${p2}, 1);
        BEGIN TRY
          EXEC dbo.sp_ProcesarVentaTransaccional ${client}, ${user}, @Detalle;
          THROW 52203, 'La segunda venta no debe disponer del mismo stock.', 1;
        END TRY BEGIN CATCH
          IF ERROR_NUMBER() <> 52010 THROW;
        END CATCH;`)]);
    } finally {
      clearTimeout(timeout);
      if (processA.exitCode === null) { processA.kill(); await completedA.catch(() => {}); }
    }
    await sql(`IF (SELECT COUNT(*) FROM dbo.Factura) <> 1
      OR (SELECT COUNT(*) FROM dbo.DetalleFactura) <> 2
      OR (SELECT COUNT(*) FROM dbo.MovimientoCaja) <> 1
      OR EXISTS (SELECT 1 FROM dbo.Producto WHERE ProductoId IN (${p1}, ${p2}) AND Stock <> 0)
      THROW 52204, 'Concurrencia: factura parcial, duplicada o stock incorrecto.', 1;`);
    console.log('OK: dos sesiones, productos en orden inverso, una venta completa y otra rechazada por stock.');
  } finally {
    if (created) {
      // Nombre generado aquí, nunca procede del usuario ni señala la base del equipo.
      await sql(`ALTER DATABASE [${database}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [${database}];`, false);
      console.log('OK: base temporal eliminada.');
    }
    const resolvedDirectory = path.resolve(directory);
    if (!resolvedDirectory.startsWith(path.resolve(tmpdir()) + path.sep)
        || !path.basename(resolvedDirectory).startsWith('securefinance-sql-')) {
      throw new Error('Ruta temporal fuera del directorio autorizado.');
    }
    await rm(resolvedDirectory, { recursive: true, force: true });
  }
}

main().catch((error) => { console.error(error.message); process.exitCode = 1; });
