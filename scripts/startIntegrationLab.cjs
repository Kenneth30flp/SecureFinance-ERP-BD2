'use strict';
const {randomBytes}=require('crypto');const lab=require('../database/tests/promocionesLab');const s=lab.useLab();
process.env.SESSION_SECRET=process.env.SESSION_SECRET||randomBytes(48).toString('base64url');
const {createApp}=require('../server');const app=createApp({production:false});app.locals.laboratorio={port:3107,database:s.lab,demo:true};
app.listen(3107,'127.0.0.1',()=>console.log('SecureFinance integration: http://127.0.0.1:3107 / '+s.lab)).on('error',e=>{console.error(e.code);process.exitCode=1;});
