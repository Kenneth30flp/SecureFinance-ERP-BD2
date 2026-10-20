'use strict';
const fs = require('node:fs/promises');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const sharp = require('sharp');
const { ValidationError } = require('../controllers/kennethValidation');
const reference = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\.(jpg|png)$/;
function createFotografiaService(directory = path.resolve(__dirname, '../../.data/product-photos')) {
  const target = (name, staging = false) => { if (!reference.test(name)) throw new ValidationError('Referencia de fotografía inválida.'); return path.join(directory, ...(staging ? ['staging',name] : [name])); };
  return {
    async upload(buffer, name, contentType) {
      if (!Buffer.isBuffer(buffer) || buffer.length < 12 || buffer.length > 3 * 1024 * 1024) throw new ValidationError('La fotografía debe pesar como máximo 3 MB.');
      const extension = typeof name === 'string' ? path.extname(name).toLowerCase() : '';
      const png = buffer.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]));
      const jpeg = buffer[0] === 255 && buffer[1] === 216 && buffer[2] === 255;
      if ((!png && !jpeg) || (png && (extension !== '.png' || contentType !== 'image/png')) || (jpeg && (!['.jpg','.jpeg'].includes(extension) || contentType !== 'image/jpeg'))) throw new ValidationError('Solo se permiten fotografías PNG o JPEG cuyo contenido coincida con el formato.');
      let output;
      try {
        const image = sharp(buffer, { limitInputPixels: 25000000, failOn: 'warning' });
        const metadata = await image.metadata();
        if (metadata.pages > 1 || !['png','jpeg'].includes(metadata.format)) throw new Error('Formato no admitido');
        const resized = image.rotate().resize({ width: 2400, height: 2400, fit: 'inside', withoutEnlargement: true });
        output = await (png ? resized.png() : resized.jpeg({ quality: 85 })).toBuffer();
      } catch { throw new ValidationError('No fue posible decodificar la fotografía. Selecciona una imagen válida.'); }
      await fs.mkdir(directory, { recursive: true, mode: 0o700 });
      if ((await fs.lstat(directory)).isSymbolicLink()) throw new Error('Directorio no permitido');
      const ref = randomUUID() + (png ? '.png' : '.jpg');
      await fs.mkdir(path.join(directory,'staging'),{recursive:true,mode:0o700});
      if ((await fs.lstat(path.join(directory,'staging'))).isSymbolicLink()) throw new Error('Directorio no permitido');
      // Una referencia SQL nunca apunta a staging. Solo se purgan cargas vencidas,
      // sin recorrer subdirectorios ni tocar fotografias definitivas.
      for(const old of (await fs.readdir(path.join(directory,'staging'))).filter(n=>reference.test(n)).slice(0,100)){
        const file=target(old,true),stat=await fs.lstat(file).catch(()=>null);
        if(stat?.isFile()&&!stat.isSymbolicLink()&&Date.now()-stat.mtimeMs>86400000)await fs.unlink(file).catch(()=>{});
      }
      await fs.writeFile(target(ref,true), output, { flag: 'wx', mode: 0o600 });
      return ref;
    },
    async read(name) { let file=target(name); try{await fs.access(file);}catch{file=target(name,true);} if (!(await fs.lstat(file)).isFile() || (await fs.lstat(file)).isSymbolicLink()) throw new Error('No disponible'); return fs.readFile(file); },
    async retain(name) { await fs.rename(target(name,true),target(name)); },
    // Cancelar nunca elimina una imagen que ya paso a almacenamiento definitivo.
    async remove(name) { await fs.unlink(target(name,true)).catch(error => { if (error.code !== 'ENOENT') throw error; }); },
  };
}
module.exports = { createFotografiaService, reference };
