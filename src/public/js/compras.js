'use strict';
(function(root){
  function quantity(value){if(!/^[1-9]\d*$/.test(String(value))||Number(value)>2147483647)throw Error('La cantidad debe ser un entero positivo.');return Number(value);}
  function cost(value){if(typeof value!=='string'||!/^(0|[1-9]\d{0,14})(\.\d{1,4})?$/.test(value))throw Error('Ingresa el costo sin separadores, con hasta cuatro decimales.');const [a,b='']=value.split('.');return a+'.'+b.padEnd(4,'0');}
  function scaled(value){return BigInt(cost(value).replace('.',''));}
  function total(lines){return lines.reduce((sum,line)=>sum+scaled(line.CostoUnitario)*BigInt(quantity(line.Cantidad)),0n);}
  function money(n){return 'Q '+(n/10000n).toString().replace(/\B(?=(\d{3})+(?!\d))/g,',')+'.'+(n%10000n).toString().padStart(4,'0');}
  if(typeof module==='object')module.exports={quantity,cost,scaled,total,money};
  if(!root.document)return;
  const $=s=>document.querySelector(s),message=$('#com-message'),csrf=$('meta[name="csrf-token"]').content;
  const storageKey='compras:pending:'+document.body.dataset.actor+':'+location.pathname;
  let busy=false,pending=null;
  try{pending=JSON.parse(sessionStorage.getItem(storageKey)||'null');if(pending){const allowed=location.pathname==='/compras/nueva'?['/compras']:['enviar','aprobar','cancelar','recibir','actualizar'].map(a=>location.pathname+'/'+a);if(!allowed.includes(pending.url)||!pending.body||typeof pending.body!=='object'||Array.isArray(pending.body))throw Error('Referencia local incompatible');}}catch{pending=null;message.hidden=false;message.textContent='No se puede recuperar la referencia local. Consulta el historial antes de registrar otra operación.';busy=true;}
  function notify(text,success=false){message.hidden=false;message.textContent=text;message.toggleAttribute('data-success',success);message.focus();}
  if(pending)notify('Existe una operación pendiente de confirmación. Referencia '+pending.body.OperacionId+'. Al confirmar se reenviará exactamente esa operación; consulta el detalle antes de iniciar otra.');
  if(pending)document.querySelectorAll('#com-create,[data-state-form],[data-receive-form]').forEach(form=>{form.noValidate=true;});
  try{const done=sessionStorage.getItem('compras:done');if(done){sessionStorage.removeItem('compras:done');notify(done,true);}}catch{}
  async function confirm(text){const dialog=$('#com-confirm');$('#com-confirm-description').textContent=text;dialog.returnValue='';dialog.showModal();return new Promise(resolve=>dialog.addEventListener('close',()=>resolve(dialog.returnValue==='confirm'),{once:true}));}
  async function request(url,options){const r=await fetch(url,{credentials:'same-origin',...options});let data;try{data=await r.json();}catch{throw Error('No se pudo confirmar la respuesta. Consulta la orden antes de reenviar.');}if(!r.ok){const error=Error(data?.error||'No fue posible completar la operación.');error.definite=[400,403,404,409,413].includes(r.status)&&data?.incierto!==true;throw error;}return data;}
  async function send(url,body,form,description){
    if(busy)return;busy=true;const replaying=Boolean(pending);
    try{
      if(pending){url=pending.url;body=pending.body;description='Reintentar la operación pendiente con su referencia original '+(body.OperacionId||'')+'.';}
      if(!await confirm(description))return;
      pending={url,body};sessionStorage.setItem(storageKey,JSON.stringify(pending));form.setAttribute('aria-busy','true');
      const result=await request(url,{method:'POST',headers:{'Content-Type':'application/json','X-CSRF-Token':csrf},body:JSON.stringify(body)});
      sessionStorage.removeItem(storageKey);pending=null;
      const text='Operación confirmada'+(result.documento?.Numero?' · '+result.documento.Numero:'')+'.';
      if(form.dataset.canRead==='false'){notify(text+' Puedes preparar una nueva orden desde la navegación.',true);form.querySelectorAll('input,select,textarea,button').forEach(e=>e.disabled=true);return;}
      sessionStorage.setItem('compras:done',text);location.assign(result.url&&/^\/compras(?:\/|$)/.test(result.url)?result.url:location.pathname);
    }catch(e){if(e.definite&&!replaying){try{sessionStorage.removeItem(storageKey);}catch{}pending=null;}notify(e.message+(pending?' Conserva la referencia '+(pending.body.OperacionId||'')+'. No prepares un duplicado.':''));}
    finally{busy=false;form.removeAttribute('aria-busy');}
  }
  document.querySelectorAll('[data-print]').forEach(b=>b.addEventListener('click',()=>window.print()));
  const create=$('#com-create');
  if(create){
    const lines=[],supplier=$('#com-supplier'),product=$('#com-product');
    const selections={supplier:[],product:[]},tickets={supplier:0,product:0};
    const requests={},timers={};
    let selectedSupplier='';
    function invalidate(kind){clearTimeout(timers[kind]);tickets[kind]++;requests[kind]?.controller.abort();delete requests[kind];}
    function resetProducts(){
      invalidate('product');selections.product=[];
      product.replaceChildren(new Option('Selecciona primero un proveedor',''));
      product.removeAttribute('aria-busy');
      $('#com-product-pages').replaceChildren();
      $('#com-product-query').value='';
      $('#com-product-status').textContent='Selecciona primero un proveedor.';
      const link=$('#com-product-manage');if(link)link.hidden=true;
    }
    function draw(){const tbody=$('#com-lines');tbody.replaceChildren();for(const line of lines){const tr=document.createElement('tr');for(const [label,text] of [['Producto',line.name],['Cantidad',String(line.Cantidad)],['Costo unitario',money(scaled(line.CostoUnitario))],['Subtotal',money(total([line]))]]){const td=document.createElement('td');td.dataset.label=label;td.textContent=text;tr.append(td);}const td=document.createElement('td'),button=document.createElement('button');button.type='button';button.className='btn btn-outline-danger btn-sm';button.textContent='Retirar';button.setAttribute('aria-label','Retirar '+line.name);button.onclick=()=>{lines.splice(lines.indexOf(line),1);draw();};td.append(button);tr.append(td);tbody.append(tr);}supplier.disabled=lines.length>0;$('#com-supplier-search').disabled=lines.length>0;$('#com-supplier-query').disabled=lines.length>0;$('#com-supplier-pages').querySelectorAll('button').forEach(b=>b.disabled=lines.length>0);$('#com-no-lines').hidden=lines.length>0;$('#com-count').textContent=lines.length;$('#com-total').textContent=money(total(lines));$('#com-summary-provider').textContent=supplier.selectedOptions[0]?.textContent||'Selecciona un proveedor';}
    async function search(kind,page=1){
      clearTimeout(timers[kind]);
      if(kind==='supplier'&&lines.length)return;
      if(kind==='product'&&!supplier.value)return;
      const query=$('#com-'+kind+'-query').value.trim(),provider=supplier.value;
      const params=new URLSearchParams({q:query,pagina:String(page)});
      if(kind==='product')params.set('proveedor',provider);
      const key=params.toString();
      if(requests[kind]?.key===key)return;
      invalidate(kind);
      const ticket=tickets[kind],controller=new AbortController();
      requests[kind]={key,controller};
      const select=kind==='supplier'?supplier:product,status=$('#com-'+kind+'-status');
      select.setAttribute('aria-busy','true');status.textContent='Cargando '+(kind==='supplier'?'proveedores':'productos')+'…';
      const current=()=>ticket===tickets[kind]&&(kind!=='product'||provider===supplier.value);
      try{
        const response=await fetch('/compras/buscar/'+(kind==='supplier'?'proveedores':'productos')+'?'+params,{credentials:'same-origin',signal:controller.signal});
        let data;try{data=await response.json();}catch{throw Error('Respuesta no válida (HTTP '+response.status+'). Verifica tu sesión e intenta nuevamente.');}
        if(!response.ok)throw Error('HTTP '+response.status+': '+(typeof data?.error==='string'?data.error:'No se pudo cargar el catálogo.'));
        if(!current()||(kind==='supplier'&&lines.length))return;
        if(!data||!Array.isArray(data.rows)||typeof data.next!=='boolean'||data.pagina!==page||
          !data.rows.every(row=>row&&Number.isInteger(row.Id)&&row.Id>0&&typeof row.Nombre==='string'&&typeof row.Referencia==='string')||
          new Set(data.rows.map(row=>row.Id)).size!==data.rows.length)throw Error('Respuesta de catálogo inesperada. Intenta nuevamente.');
        const previous=select.value,chosen=selections[kind].find(row=>String(row.Id)===previous);
        selections[kind]=data.rows.slice();
        // Keep the current selection when browsing another page or refining the query.
        if(chosen&&!selections[kind].some(row=>row.Id===chosen.Id))selections[kind].unshift(chosen);
        select.replaceChildren(new Option('Selecciona una opción',''));
        for(const row of selections[kind])select.add(new Option(row.Nombre+' · '+row.Referencia,String(row.Id)));
        select.value=previous;
        const pager=$('#com-'+kind+'-pages');pager.replaceChildren();
        status.textContent=data.rows.length?'Página '+page+' · '+data.rows.length+' resultados':
          query?'Sin coincidencias para esta búsqueda.':
          kind==='supplier'?'No hay proveedores activos disponibles.':'No hay productos activos asociados a este proveedor.';
        const link=kind==='product'?$('#com-product-manage'):null;if(link)link.hidden=data.rows.length>0||Boolean(query);
        for(const [label,target,enabled] of [['Anterior',page-1,page>1],['Siguiente',page+1,data.next]]){
          if(!enabled)continue;const b=document.createElement('button');b.type='button';b.textContent=label;
          b.setAttribute('aria-label',label+' página de '+(kind==='supplier'?'proveedores':'productos'));
          b.onclick=()=>search(kind,target);pager.append(b);
        }
        draw();
      }catch(e){
        if(!current()||e.name==='AbortError')return;
        status.textContent='No se pudo cargar el catálogo. '+e.message+' Pulsa Buscar para reintentar.';
      }finally{
        if(current()){delete requests[kind];select.removeAttribute('aria-busy');}
      }
    }
    for(const kind of ['supplier','product']){
      const query=$('#com-'+kind+'-query');
      $('#com-'+kind+'-search').onclick=()=>search(kind);
      query.addEventListener('input',()=>{
        if(kind==='supplier'&&lines.length)return;
        invalidate(kind); // Invalidate immediately, including the debounce interval.
        timers[kind]=setTimeout(()=>search(kind),250);
      });
      query.addEventListener('keydown',e=>{if(e.key==='Enter'){e.preventDefault();search(kind);}});
    }
    supplier.addEventListener('change',()=>{
      if(lines.length){supplier.value=selectedSupplier;return;}
      if(supplier.value===selectedSupplier)return;
      selectedSupplier=supplier.value;resetProducts();draw();
      if(selectedSupplier)search('product');
    });
    draw();search('supplier');
    $('#com-add').onclick=()=>{try{const found=selections.product.find(p=>String(p.Id)===product.value);if(!supplier.value||!found)throw Error('Selecciona proveedor y producto activos.');if(lines.length>=100)throw Error('Una orden admite hasta 100 productos.');if(lines.some(l=>l.ProductoId===found.Id))throw Error('El producto ya está agregado. Retira su línea si necesitas corregirla.');lines.push({ProductoId:found.Id,Cantidad:quantity($('#com-quantity').value),CostoUnitario:cost($('#com-cost').value),name:found.Nombre});draw();}catch(e){notify(e.message);}};
    create.addEventListener('submit',e=>{e.preventDefault();try{if(pending)return void send(pending.url,pending.body,create,'');if(!lines.length)throw Error('Agrega al menos un producto.');send('/compras',{ProveedorId:quantity(supplier.value),OperacionId:create.dataset.operation,Observaciones:$('#com-notes').value,Detalle:lines.map(({name,...line})=>line)},create,'Crear una orden por '+money(total(lines))+'. Revisa los costos y cantidades; las líneas quedarán inmutables.');}catch(error){notify(error.message);}});
  }
  document.querySelectorAll('[data-state-form]').forEach(form=>form.addEventListener('submit',e=>{e.preventDefault();const action=e.submitter?.dataset.action;if(!['enviar','aprobar','cancelar'].includes(action))return;send('/compras/'+form.dataset.id+'/'+action,{OperacionId:form.dataset.operation,Version:form.dataset.version,Motivo:form.elements.Motivo.value},form,'Confirmar: '+e.submitter.textContent+'. Se conservará el responsable y el motivo en el historial.');}));
  document.querySelectorAll('[data-receive-form]').forEach(form=>form.addEventListener('submit',e=>{e.preventDefault();try{if(pending)return void send(pending.url,pending.body,form,'');const Detalle=[];form.querySelectorAll('[data-receive-line]').forEach(row=>{const q=row.querySelector('[data-quantity]');if(!q.value)return;const Cantidad=quantity(q.value);if(Cantidad>Number(q.max))throw Error('La entrega no puede superar lo pendiente.');Detalle.push({ProductoId:quantity(row.dataset.receiveLine),Cantidad,CostoUnitario:cost(row.querySelector('[data-cost]').value)});});if(!Detalle.length)throw Error('Indica al menos una cantidad recibida.');send('/compras/'+form.dataset.id+'/recibir',{OperacionId:form.dataset.operation,Version:form.dataset.version,Motivo:form.elements.Motivo.value,DocumentoRespaldo:form.elements.DocumentoRespaldo.value,Detalle},form,'Registrar '+Detalle.length+' productos por '+money(total(Detalle))+'. Confirma que recibiste físicamente las cantidades y que los costos coinciden con el comprobante.');}catch(error){notify(error.message);}}));
  document.querySelectorAll('[data-refresh-form]').forEach(form=>form.addEventListener('submit',e=>{e.preventDefault();send(form.getAttribute('action'),{},form,'Actualizar la valoración con los movimientos pendientes. Los costos históricos desconocidos permanecerán sin valorar.');}));
})(typeof window==='undefined'?globalThis:window);
