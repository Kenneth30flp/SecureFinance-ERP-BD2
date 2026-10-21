'use strict';
(() => {
 const message=document.getElementById('posventa-message');
 const dialog=document.getElementById('posventa-confirm');
 let pending=null;
 let returnFocus=null;
 function show(text){message.textContent=text;message.dataset.tone='error';message.focus();}
 async function send(form,body){
  const button=form.querySelector('button[type="submit"],button');button.disabled=true;
  form.setAttribute('aria-busy','true');
  try{
   const response=await fetch(form.action,{method:'POST',headers:{'Content-Type':'application/json','X-CSRF-Token':document.querySelector('meta[name="csrf-token"]').content},body:JSON.stringify(body)});
   const result=await response.json();
   if(!response.ok){show(result.error||'No fue posible guardar.');return;}
   window.location.assign(result.url);
  }catch{show('No fue posible confirmar el resultado. Conserva este formulario y reintenta con la misma referencia.');}
  finally{button.disabled=false;form.removeAttribute('aria-busy');}
 }
 document.querySelectorAll('[data-posventa-form]').forEach(form=>form.addEventListener('submit',event=>{
  event.preventDefault();
  if(form.getAttribute('aria-busy')==='true')return;
  const body=Object.fromEntries(new FormData(form));
  if(form.dataset.kind==='devoluciones'){
   body.Detalles=[...form.querySelectorAll('[data-line]')].map(row=>({DetalleFacturaId:Number(row.dataset.line),Cantidad:Number(row.querySelector('[data-quantity]').value),Reingresar:row.querySelector('[data-condition]').value==='true'})).filter(row=>row.Cantidad>0);
   if(!body.Detalles.length){show('Indica al menos una cantidad a devolver.');return;}
   pending={form,body};returnFocus=form.querySelector('button[type="submit"]');document.getElementById('posventa-summary').textContent=body.Detalles.reduce((n,r)=>n+r.Cantidad,0)+' unidades de la factura #'+body.FacturaId+'. Motivo: '+body.Motivo;
   dialog.showModal();return;
  }
  send(form,body);
 }));
 document.getElementById('posventa-accept').addEventListener('click',()=>{dialog.close();if(pending){const {form,body}=pending;pending=null;send(form,body);}});
 document.getElementById('posventa-cancel').addEventListener('click',()=>{pending=null;dialog.close();});
 dialog.addEventListener('cancel',()=>{pending=null;});
 dialog.addEventListener('close',()=>{returnFocus?.focus();});
 document.querySelectorAll('[data-print]').forEach(button=>button.addEventListener('click',()=>window.print()));
})();
