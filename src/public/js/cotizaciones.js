'use strict';
const clientIdentity=value=>(document.body.dataset.demo==='true' && /^DEMOCOT\d+$/.test(value)?'Identificador de demostración: ':'NIT ')+value;
(() => {
  const $=id=>document.getElementById(id),message=$('cot-message');
  const show=text=>{message.textContent=text;message.hidden=false;message.focus();};
  const decimal=value=>{const [a,b='']=String(value).split('.');return BigInt(a)*100n+BigInt(b.padEnd(2,'0'));};
  const money=n=>'Q '+(n/100n).toLocaleString('es-GT')+'.'+String(n%100n).padStart(2,'0');
  const node=(tag,className,text)=>{const e=document.createElement(tag);if(className)e.className=className;if(text!==undefined)e.textContent=text;return e;};
  document.querySelectorAll('.cot-ledger').forEach(table=>{const labels=[...table.querySelectorAll('thead th')].map(h=>h.textContent.trim());table.querySelectorAll('tbody tr').forEach(row=>[...row.cells].forEach((cell,i)=>{if(cell.tagName==='TD')cell.dataset.label=labels[i]||'';}));});
  async function post(url,body){
    const r=await fetch(url,{method:'POST',headers:{'Content-Type':'application/json','X-CSRF-Token':document.querySelector('meta[name="csrf-token"]').content},body:JSON.stringify(body)});
    const result=await r.json().catch(()=>({error:'No se pudo confirmar el resultado. Consulta el estado del documento antes de reenviar.'}));
    if(!r.ok)throw Error(result.error);return result;
  }
  async function confirmOperation(form,cancelling=false){
    const dialog=$('cot-confirm');
    if(!dialog)return window.confirm(cancelling?'¿Cancelar esta cotización?':'¿Convertir a factura de contado?');
    const title=$('cot-confirm-title'),text=$('cot-confirm-text'),summary=dialog.querySelector('.cot-dialog-summary'),effects=dialog.querySelector('.cot-dialog-summary + p');
    title.textContent=cancelling?'Cancelar cotización':'Convertir a factura';
    text.textContent=cancelling?'El documento permanecerá en el historial, pero no podrá facturarse.':'Vas a convertir '+form.dataset.number+' con sus precios y descuentos pactados.';
    summary.hidden=cancelling;effects.hidden=cancelling;$('cot-confirm-total').textContent=form.dataset.total||'';
    dialog.querySelector('[value="confirm"]').textContent=cancelling?'Confirmar cancelación':'Confirmar conversión';
    dialog.returnValue='cancel';const opener=form.querySelector('button')||document.activeElement;
    return new Promise(resolve=>{dialog.addEventListener('close',()=>{opener?.focus();resolve(dialog.returnValue==='confirm');},{once:true});dialog.showModal();dialog.querySelector('[value="cancel"]').focus();});
  }
  $('cot-print')?.addEventListener('click',()=>window.print());
  const conversion=$('cot-convert');let converting=false;
  conversion?.addEventListener('submit',async e=>{
    e.preventDefault();if(converting)return;converting=true;
    const button=conversion.querySelector('button');button.setAttribute('aria-busy','true');
    if(!await confirmOperation(conversion)){converting=false;button.removeAttribute('aria-busy');button.focus();return;}
    button.disabled=true;button.textContent='Procesando conversión…';
    try{await post('/cotizaciones/'+conversion.dataset.id+'/convertir',{OperacionId:conversion.dataset.operation});location.assign('/cotizaciones/'+conversion.dataset.id+'?convertida=1');}
    catch(err){show(err.message+' Referencia conservada. Consulta el estado actual o reintenta con la misma operación.');button.disabled=false;button.removeAttribute('aria-busy');button.textContent='Convertir a factura →';converting=false;}
  });
  const cancel=$('cot-cancel');let cancelling=false;
  cancel?.addEventListener('submit',async e=>{
    e.preventDefault();if(cancelling||!cancel.reportValidity())return;cancelling=true;
    if(!await confirmOperation(cancel,true)){cancelling=false;return;}
    const button=cancel.querySelector('button');button.disabled=true;
    try{await post('/cotizaciones/'+cancel.dataset.id+'/cancelar',{OperacionId:cancel.dataset.operation,Motivo:$('cot-reason').value});location.reload();}
    catch(err){show(err.message);button.disabled=false;cancelling=false;}
  });
  const form=$('cot-create');if(!form)return;
  let selectedProduct=null;const lines=new Map();
  function picker(root,onSelect,onClear){
    const input=root.querySelector('[role="combobox"]'),value=root.querySelector('input[type="hidden"]'),panel=root.querySelector('.cot-picker-panel'),list=root.querySelector('[role="listbox"]'),status=root.querySelector('[role="status"]'),pages=root.querySelector('.cot-picker-pages');
    const kind=root.dataset.picker;let results=[],active=-1,page=1,next=false,controller,version=0,timer;
    function close(){panel.hidden=true;input.setAttribute('aria-expanded','false');input.removeAttribute('aria-activedescendant');}
    function highlight(index){
      active=index;for(let i=0;i<list.children.length;i++)list.children[i].setAttribute('aria-selected',String(i===index));
      if(index>=0){input.setAttribute('aria-activedescendant',list.children[index].id);list.children[index].scrollIntoView({block:'nearest'});}else input.removeAttribute('aria-activedescendant');
    }
    function select(row){value.value=String(row.Id);input.value=row.Nombre;close();onSelect(row);}
    async function load(target=1){
      const current=++version;controller?.abort();controller=new AbortController();
      panel.hidden=false;input.setAttribute('aria-expanded','true');input.setAttribute('aria-busy','true');status.textContent='Buscando…';list.replaceChildren();pages.replaceChildren();active=-1;
      const rect=input.getBoundingClientRect(),below=innerHeight-rect.bottom-16,above=rect.top-16,up=below<220&&above>below;
      panel.classList.toggle('cot-picker-up',up);list.style.maxHeight=Math.max(96,Math.min(300,(up?above:below)-75))+'px';
      try{
        const params=new URLSearchParams({q:input.value.trim(),pagina:String(target)});
        const response=await fetch('/cotizaciones/buscar/'+kind+'?'+params,{signal:controller.signal,headers:{Accept:'application/json'}});
        if(!response.ok)throw Error();const data=await response.json();if(current!==version)return;
        results=data.rows;page=data.pagina;next=data.next;input.removeAttribute('aria-activedescendant');
        for(let i=0;i<results.length;i++){
          const row=results[i],option=node('div','cot-option'),label=node('div');option.id=list.id+'-'+i;option.dataset.id=String(row.Id);option.setAttribute('role','option');option.setAttribute('aria-selected','false');
          label.append(node('strong','',row.Nombre),node('small','',(kind==='clientes'?clientIdentity(row.Referencia):'SKU '+row.Referencia)));option.append(label);
          if(kind==='productos'){
            const price=node('div','cot-option-price');price.append(node('strong','',money(decimal(row.Precio))),node('small',row.Stock===0?'cot-out-stock':'',row.Stock===0?'Sin existencias':row.Stock+' disponibles'));option.append(price);
          }
          option.addEventListener('mousedown',e=>e.preventDefault());option.addEventListener('click',()=>select(row));list.append(option);
        }
        status.textContent=results.length?results.length+' resultados · página '+page:'No encontramos '+kind+'. Prueba otro nombre, NIT o SKU.';
        function pageButton(label,target){const button=node('button','',label);button.type='button';button.addEventListener('click',()=>{load(target);input.focus();});pages.append(button);}
        if(page>1)pageButton('← Anteriores',page-1);if(next)pageButton('Ver siguientes →',page+1);
      }catch(err){if(err.name!=='AbortError'&&current===version){status.textContent='No fue posible cargar resultados. Intenta buscar nuevamente.';results=[];}}
      finally{if(current===version)input.removeAttribute('aria-busy');}
    }
    input.addEventListener('focus',()=>{if(panel.hidden){const selected=value.value;if(selected){input.select();}else load();}});
    input.addEventListener('input',()=>{value.value='';onClear();controller?.abort();version++;results=[];active=-1;list.replaceChildren();pages.replaceChildren();input.removeAttribute('aria-activedescendant');clearTimeout(timer);timer=setTimeout(()=>load(),180);});
    input.addEventListener('keydown',async e=>{
      if(['ArrowDown','ArrowUp'].includes(e.key)){e.preventDefault();if(panel.hidden)await load();if(results.length)highlight(active<0?(e.key==='ArrowDown'?0:results.length-1):(active+(e.key==='ArrowDown'?1:-1)+results.length)%results.length);}
      else if(e.key==='Enter'){e.preventDefault();if(!panel.hidden&&active>=0&&results[active])select(results[active]);else if(panel.hidden)load();}
      else if(e.key==='Escape'){e.preventDefault();close();}
      else if(e.key==='Tab')close();
    });
    root.addEventListener('focusout',()=>setTimeout(()=>{if(!root.contains(document.activeElement))close();},0));
    document.addEventListener('pointerdown',e=>{if(!root.contains(e.target))close();});
    return {clear(){value.value='';input.value='';onClear();input.focus();load();}};
  }
  const clientPicker=picker(document.querySelector('[data-picker="clientes"]'),row=>{
    const selected=$('cot-client-selected'),label=node('div');label.append(node('strong','',row.Nombre),node('small','',clientIdentity(row.Referencia)));
    const change=node('button','','Cambiar');change.type='button';change.addEventListener('click',()=>clientPicker.clear());selected.replaceChildren(label,change);selected.hidden=false;
    $('cot-client-help').hidden=true;$('cot-summary-client').textContent=row.Nombre;
  },()=>{$('cot-client-selected').hidden=true;$('cot-client-help').hidden=false;$('cot-summary-client').textContent='Selecciona un cliente';});
  picker(document.querySelector('[data-picker="productos"]'),row=>{selectedProduct=row;$('cot-product-selected').textContent=row.Referencia+' · '+money(decimal(row.Precio))+' · '+(row.Stock===0?'Sin existencias; no podrá facturarse hasta disponer de stock.':row.Stock+' unidades disponibles');},()=>{selectedProduct=null;$('cot-product-selected').textContent='Busca y selecciona un producto.';});
  function recalculate(){
    let gross=0n,saving=0n;
    for(const [id,line] of lines){const bruto=decimal(line.price)*BigInt(line.Cantidad),discount=(bruto*decimal(line.DescuentoPorcentaje)+5000n)/10000n;gross+=bruto;saving+=discount;const target=$('cot-line-net-'+id);if(target)target.textContent=money(bruto-discount);}
    const net=gross-saving,tax=(net*12n+50n)/100n;
    for(const [id,amount] of [['cot-gross',gross],['cot-saving',saving],['cot-net',net],['cot-tax',tax],['cot-total',net+tax]])$(id).textContent=money(amount);
    $('cot-line-count').textContent=lines.size+' producto'+(lines.size===1?'':'s');$('cot-empty').hidden=lines.size>0;
  }
  const validQuantity=value=>/^\d+$/.test(value)&&Number(value)>=1&&Number(value)<=2147483647;
  const validDiscount=value=>/^\d{1,3}(\.\d{1,2})?$/.test(value)&&Number(value)<=Number(form.dataset.maxDiscount);
  function render(){
    const body=$('cot-lines');body.replaceChildren();
    for(const [id,line] of lines){
      const tr=node('tr'),name=node('th');name.scope='row';name.append(node('strong','',line.description),node('small','',line.sku));tr.append(name);
      for(const [label,key,valid,max,step] of [['Cantidad','Cantidad',validQuantity,'2147483647','1'],['Descuento %','DescuentoPorcentaje',validDiscount,form.dataset.maxDiscount,'0.01']]){
        const td=node('td'),input=node('input','form-control cot-line-number'+(key==='DescuentoPorcentaje'?' cot-line-discount':''));td.dataset.label=label;input.type='number';input.min=key==='Cantidad'?'1':'0';input.max=max;input.step=step;input.value=String(line[key]);input.required=true;input.setAttribute('aria-label',label+' de '+line.sku);
        input.addEventListener('input',()=>{const ok=valid(input.value);input.setCustomValidity(ok?'':'Revisa el valor permitido.');if(ok){line[key]=key==='Cantidad'?Number(input.value):input.value;recalculate();}});
        td.append(input);if(key==='Cantidad')tr.append(td);else{
          const price=node('td','cot-money',money(decimal(line.price)));price.dataset.label='Precio unitario';tr.append(price,td);
        }
      }
      const net=node('td','cot-money');net.id='cot-line-net-'+id;net.dataset.label='Importe neto';tr.append(net);
      const action=node('td'),remove=node('button','cot-line-remove','×');remove.type='button';remove.setAttribute('aria-label','Quitar '+line.sku);remove.addEventListener('click',()=>{lines.delete(id);render();$('cot-search').focus();});action.append(remove);tr.append(action);body.append(tr);
    }
    recalculate();
  }
  $('cot-add').addEventListener('click',()=>{
    if(!selectedProduct||!validQuantity($('cot-quantity').value)||!validDiscount($('cot-discount').value))return show('Selecciona un producto, una cantidad positiva y un descuento autorizado.');
    const id=String(selectedProduct.Id);if(lines.has(id))return show('Este producto ya está agregado. Puedes editar su cantidad y descuento directamente en la tabla.');
    if(lines.size>=100)return show('La cotización admite hasta 100 productos.');
    lines.set(id,{ProductoId:selectedProduct.Id,Cantidad:Number($('cot-quantity').value),DescuentoPorcentaje:$('cot-discount').value,price:selectedProduct.Precio,sku:selectedProduct.Referencia,description:selectedProduct.Nombre});message.hidden=true;render();
    $('cot-search').focus();
  });
  form.addEventListener('submit',async e=>{
    e.preventDefault();if(!form.reportValidity())return;if(!$('cot-client').value)return show('Busca y selecciona un cliente activo.');if(!lines.size)return show('Agrega al menos un producto.');
    const save=$('cot-save');if(save.disabled)return;save.disabled=true;save.textContent='Guardando propuesta…';
    try{const result=await post('/cotizaciones',{ClienteId:$('cot-client').value,Vencimiento:$('cot-expiry').value,Observaciones:$('cot-notes').value,OperacionId:form.dataset.operation,Detalle:[...lines.values()].map(({ProductoId,Cantidad,DescuentoPorcentaje})=>({ProductoId,Cantidad,DescuentoPorcentaje}))});location.assign(result.url);}
    catch(err){show(err.message);save.disabled=false;save.textContent='Guardar cotización →';}
  });
})();
