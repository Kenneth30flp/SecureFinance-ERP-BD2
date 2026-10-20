'use strict';
const {spawn}=require('node:child_process');
const {once}=require('node:events');
const fs=require('node:fs/promises');
const {existsSync}=require('node:fs');
const path=require('node:path');
const net=require('node:net');
const pause=ms=>new Promise(r=>setTimeout(r,ms));
async function withBrowser(directory,fn){
 const binary=['C:/Program Files/Google/Chrome/Application/chrome.exe','C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'].find(existsSync);
 if(!binary)throw new Error('No hay Chromium instalado');
 await fs.mkdir(directory,{recursive:true});
 const reservation=net.createServer().listen(0,'127.0.0.1');await once(reservation,'listening');const port=reservation.address().port;await new Promise(r=>reservation.close(r));
 const browser=spawn(binary,['--headless=new','--disable-gpu','--no-first-run','--no-default-browser-check','--remote-debugging-port='+port,'--user-data-dir='+path.resolve(directory,'profile'),'about:blank'],{windowsHide:true,stdio:'ignore'});
 let socket;
 try{
 let page;for(let i=0;i<100;i++){try{page=(await(await fetch('http://127.0.0.1:'+port+'/json/list')).json()).find(p=>p.type==='page');if(page)break;}catch{}await pause(100);}
 if(!page)throw new Error('Chromium no inicio');
 socket=new WebSocket(page.webSocketDebuggerUrl);await once(socket,'open');let sequence=0;const pending=new Map(),errors=[];
 socket.addEventListener('message',event=>{const m=JSON.parse(event.data);if(m.method==='Runtime.exceptionThrown')errors.push(m.params.exceptionDetails.exception?.description||m.params.exceptionDetails.text);const p=pending.get(m.id);if(p){pending.delete(m.id);clearTimeout(p.timer);m.error?p.reject(new Error(m.error.message)):p.resolve(m.result);}});
 const cdp=(method,params={})=>new Promise((resolve,reject)=>{const id=++sequence;const timer=setTimeout(()=>{pending.delete(id);reject(new Error('CDP timeout '+method));},15000);pending.set(id,{resolve,reject,timer});socket.send(JSON.stringify({id,method,params}));});
 const evaluate=async expression=>{const r=await cdp('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});if(r.exceptionDetails)throw new Error(r.exceptionDetails.exception?.description||'Error navegador');return r.result.value;};
 const wait=async expression=>{for(let i=0;i<100;i++){if(await evaluate(expression))return;await pause(75);}throw new Error('No se encontro estado: '+expression);};
 const navigate=async url=>{await cdp('Page.navigate',{url});await wait('document.readyState==="complete" && location.href==='+JSON.stringify(url));};
 const viewport=(width,height=900)=>cdp('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});
 const capture=async name=>{await pause(150);const modal=await evaluate('!!document.querySelector("dialog[open]")');await fs.writeFile(path.join(directory,name+'.png'),Buffer.from((await cdp('Page.captureScreenshot',{captureBeyondViewport:!modal})).data,'base64'));};
 await cdp('Page.enable');await cdp('Runtime.enable');await fn({cdp,evaluate,wait,navigate,viewport,capture,errors});
 }finally{socket?.close();browser.kill();}
}
module.exports={withBrowser};
