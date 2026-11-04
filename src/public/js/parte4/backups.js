'use strict';
document.querySelectorAll('[data-backup-form]').forEach(form=>{
 let reference,payload,busy=false,accepted=false;
 form.addEventListener('input',()=>{if(!payload)reference=undefined;});
 form.addEventListener('submit',async e=>{
  e.preventDefault();if(busy||accepted)return;if(form.dataset.confirm&&!window.confirm(form.dataset.confirm))return;
  const button=form.querySelector('button'),message=document.getElementById('backup-message');button.disabled=true;
  busy=true;
  try{
   reference ||= crypto.randomUUID();
   if(!payload){const data=Object.fromEntries(new FormData(form));data.id=reference;if(data.point?.length===16)data.point+=':00';payload=JSON.stringify(data);}
   const response=await fetch('/dba/backups',{method:'POST',headers:{'Content-Type':'application/json','X-CSRF-Token':document.querySelector('[name=csrf-token]').content},body:payload});const body=await response.json();
   if(!response.ok){if(response.status===400||response.status===403){payload=undefined;reference=undefined;}throw new Error(body.error);}
   if(String(body.Id).toLowerCase()!==reference.toLowerCase()||typeof body.Estado!=='string')throw new Error('Respuesta no confirmada');
   message.textContent='Solicitud '+body.Id+' registrada: '+body.Estado+'. Actualice el estado para consultar el resultado.';accepted=true;button.textContent='Solicitud registrada';
  }
  catch(error){message.textContent=error.message+(reference?'. Referencia: '+reference+'. Consulte el historial antes de volver a enviar.':'. Corrija los datos o actualice la página.');}
  finally{busy=false;button.disabled=accepted;}
 });
});
