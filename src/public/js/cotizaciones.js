'use strict';
(() => {
  const $=id=>document.getElementById(id),message=$('cot-message');
  const show=text=>{message.textContent=text;message.hidden=false;message.focus();};
  async function post(url,body) {
    const r=await fetch(url,{method:'POST',headers:{'Content-Type':'application/json','X-CSRF-Token':document.querySelector('meta[name="csrf-token"]').content},body:JSON.stringify(body)});
    const result=await r.json().catch(()=>({error:'No se pudo confirmar el resultado. Consulta el historial y conserva la referencia.'}));
    if(!r.ok)throw Error(result.error);return result;
  }
  $('cot-print')?.addEventListener('click',()=>window.print());
  const conversion=$('cot-convert');
  conversion?.addEventListener('submit',async e=>{
    e.preventDefault();const button=conversion.querySelector('button');if(button.disabled)return;
    if(!window.confirm('¿Convertir esta cotización a factura de contado? Se registrará el cobro y la salida de inventario.'))return;
    button.disabled=true;
    try {
      await post('/cotizaciones/'+conversion.dataset.id+'/convertir',{OperacionId:conversion.dataset.operation});
      location.assign('/cotizaciones/'+conversion.dataset.id+'?convertida=1');
    }catch(err){show(err.message+' Referencia conservada: '+conversion.dataset.operation+'. Puedes consultar el estado actual o reintentar con la misma referencia.');button.disabled=false;}
  });
  const cancel=$('cot-cancel');
  cancel?.addEventListener('submit',async e=>{e.preventDefault();if(!cancel.reportValidity()||!window.confirm('¿Cancelar definitivamente esta cotización?'))return;const button=cancel.querySelector('button');button.disabled=true;try{await post('/cotizaciones/'+cancel.dataset.id+'/cancelar',{OperacionId:cancel.dataset.operation,Motivo:$('cot-reason').value});location.reload();}catch(err){show(err.message);button.disabled=false;}});
  const form=$('cot-create');if(!form)return;
  const lines=new Map(),money=n=>'Q '+(n/100n).toLocaleString('es-GT')+'.'+String(n%100n).padStart(2,'0');
  const decimal=s=>{const [a,b='']=String(s).split('.');return BigInt(a)*100n+BigInt(b.padEnd(2,'0'));};
  function render() {
    const body=$('cot-lines');body.replaceChildren();let gross=0n,saving=0n;
    for(const [id,l] of lines) {
      const bruto=decimal(l.price)*BigInt(l.Cantidad),discount=(bruto*decimal(l.DescuentoPorcentaje)+5000n)/10000n;
      gross+=bruto;saving+=discount;const tr=document.createElement('tr');
      for(const value of [l.sku+' · '+l.description,l.Cantidad,money(decimal(l.price)),l.DescuentoPorcentaje,money(bruto-discount)]){const td=document.createElement('td');td.textContent=value;tr.append(td);}
      const td=document.createElement('td'),button=document.createElement('button');button.type='button';button.className='btn btn-outline-secondary btn-sm';button.textContent='Quitar';button.setAttribute('aria-label','Quitar '+l.sku);button.addEventListener('click',()=>{lines.delete(id);render();});td.append(button);tr.append(td);body.append(tr);
    }
    const net=gross-saving,tax=(net*12n+50n)/100n;
    for(const [id,value] of [['cot-gross',gross],['cot-saving',saving],['cot-net',net],['cot-tax',tax],['cot-total',net+tax]])$(id).textContent=money(value);
    $('cot-empty').hidden=lines.size>0;
  }
  $('cot-search').addEventListener('input',()=>{const q=$('cot-search').value.trim().toLocaleLowerCase('es');for(const o of $('cot-product').options)o.hidden=Boolean(o.value)&&!o.textContent.toLocaleLowerCase('es').includes(q);});
  $('cot-add').addEventListener('click',()=>{
    const option=$('cot-product').selectedOptions[0],qty=$('cot-quantity').value,discount=$('cot-discount').value;
    if(!option?.value||!/^\d+$/.test(qty)||Number(qty)<1||Number(qty)>2147483647||!/^\d{1,3}(\.\d{1,2})?$/.test(discount)||Number(discount)>Number(form.dataset.maxDiscount))return show('Selecciona un producto, cantidad positiva y descuento autorizado.');
    if(lines.has(option.value))return show('El producto ya está agregado. Quítalo para cambiar cantidad o descuento.');
    if(lines.size>=100)return show('Se permiten hasta 100 productos.');
    lines.set(option.value,{ProductoId:Number(option.value),Cantidad:Number(qty),DescuentoPorcentaje:discount,price:option.dataset.price,sku:option.dataset.sku,description:option.dataset.description});message.hidden=true;render();
  });
  form.addEventListener('submit',async e=>{
    e.preventDefault();if(!form.reportValidity())return;if(!lines.size)return show('Agrega al menos un producto.');
    const save=$('cot-save');save.disabled=true;
    try{const result=await post('/cotizaciones',{ClienteId:$('cot-client').value,Vencimiento:$('cot-expiry').value,Observaciones:$('cot-notes').value,OperacionId:form.dataset.operation,Detalle:[...lines.values()].map(({ProductoId,Cantidad,DescuentoPorcentaje})=>({ProductoId,Cantidad,DescuentoPorcentaje}))});location.assign(result.url);}catch(err){show(err.message);save.disabled=false;}
  });
})();
