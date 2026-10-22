'use strict';
(() => {
  let navigation=0, saving=false, opener=null;
  async function navigate(url,{replace=false,feedback=''}={}) {
    const ticket=++navigation;
    const main=document.getElementById('workspace');
    main.setAttribute('aria-busy','true');
    try {
      const response=await fetch(url,{credentials:'same-origin',headers:{Accept:'text/html'},cache:'no-store'});
      if(response.redirected){location.assign(response.url);return;}
      const page=new DOMParser().parseFromString(await response.text(),'text/html');
      const next=page.getElementById('workspace');
      if(ticket!==navigation)return;
      if(!response.ok||!next)throw new Error('No fue posible actualizar la vista. Conservamos tus datos; consulta el registro antes de reenviar.');
      main.replaceWith(next);document.title=page.title;
      if(replace)history.replaceState(null,'',url);else history.pushState(null,'',url);
      init();
      if(feedback)announce(feedback,true);
      else if(!document.querySelector('.master-drawer[open]')){
        const target=opener&&[...next.querySelectorAll('a')].find(a=>a.href===opener);
        (target||next).focus();opener=null;
      }
    }finally{document.getElementById('workspace')?.removeAttribute('aria-busy');}
  }
  function announce(text,success=false,target=document.getElementById('module-message')){
    if(!target)return;target.textContent=text;target.classList.toggle('success',success);target.hidden=false;target.focus();
  }
  document.addEventListener('click',event=>{
    const row=event.target.closest('#workspace tr[data-record-id]');
    const anchor=event.target.closest('#workspace a[href]')||(!event.target.closest('button,input,select,textarea,summary')&&row?.querySelector('a[href]'));
    if(!anchor||event.defaultPrevented||event.button!==0||event.ctrlKey||event.metaKey||event.shiftKey||event.altKey||anchor.target||anchor.hasAttribute('download'))return;
    const url=new URL(anchor.href);
    if(url.origin!==location.origin||url.pathname!==location.pathname||url.hash)return;
    event.preventDefault();if(saving)return;
    if(url.searchParams.has('editar')||url.searchParams.has('nuevo'))opener=anchor.href;
    navigate(url).catch(e=>announce(e.message));
  });
  document.addEventListener('keydown',event=>{
    if(event.key!==' '||event.repeat||event.ctrlKey||event.metaKey||event.altKey)return;
    const anchor=event.target.closest('#workspace tr[data-record-id] a,.supplier-entry,.stock-entry,.catalog-media');
    if(anchor){event.preventDefault();anchor.click();}
  });
  window.addEventListener('popstate',()=>{if(saving){location.reload();return;}navigate(location.href,{replace:true}).catch(e=>announce(e.message));});
  function init(){
    const root=document.getElementById('workspace');if(!root)return;
    const csrf=document.querySelector('meta[name="csrf-token"]')?.content;
    // El token pertenece a la sesión y se conserva al reemplazar el contenido.
    const request=async(url,options={})=>{
      const response=await fetch(url,{credentials:'same-origin',redirect:'error',...options,headers:{'X-CSRF-Token':csrf,...options.headers}});
      let result={};if(response.status!==204)result=await response.json().catch(()=>({error:'La sesión o respuesta no estan disponibles. Actualiza la página.'}));
      if(!response.ok)throw Object.assign(new Error(result.error||'No fue posible completar la operación.'),{status:response.status});return result;
    };
    const drawer=root.querySelector('.master-drawer[data-auto-open]');
    if(drawer){drawer.showModal();drawer.addEventListener('cancel',event=>{event.preventDefault();if(!saving)navigate(drawer.dataset.closeUrl).catch(e=>announce(e.message));});}
    root.querySelectorAll('input[name=NIT]').forEach(input=>{input.pattern='[A-Za-z0-9\\-]+';input.title='Letras y números, con guiones opcionales.';});
    root.querySelectorAll('input[name=Telefono]').forEach(input=>{input.pattern='[0-9\\+\\(\\)\\. \\/\\-]*';input.title='Usa números y separadores telefonicos.';});
    const state=root.querySelector('#directory-state');
    if(state){const filter=()=>{let visible=0;root.querySelectorAll('[data-record-state]').forEach(row=>{row.hidden=!!state.value&&row.dataset.recordState!==state.value;if(!row.hidden)visible++;});root.querySelector('[data-state-empty]').hidden=visible>0||!state.value;const url=new URL(location.href);state.value?url.searchParams.set('estado',state.value):url.searchParams.delete('estado');history.replaceState(null,'',url);root.querySelectorAll('a').forEach(a=>{const u=new URL(a.href);if(u.pathname===location.pathname&&!u.hash){state.value?u.searchParams.set('estado',state.value):u.searchParams.delete('estado');a.href=u;}});};const reconcile=()=>{filter();const selected=root.querySelector('[data-record-state].is-selected');if(selected?.hidden){const first=root.querySelector('[data-record-state]:not([hidden])');if(first){const anchor=first.matches('a')?first:first.querySelector('a');navigate(anchor.href,{replace:true}).catch(e=>announce(e.message));}else{root.querySelector('.customer-identity')?.setAttribute('hidden','');announce('No hay registros con este estado en esta página. Cambia el filtro para consultar el directorio.');}}else root.querySelector('.customer-identity')?.removeAttribute('hidden');};state.addEventListener('change',reconcile);reconcile();}
    root.querySelectorAll('form[method=get]').forEach(form=>form.addEventListener('submit',event=>{event.preventDefault();if(saving)return;const url=new URL(location.pathname,location.origin);url.search=new URLSearchParams(new FormData(form));navigate(url).catch(e=>announce(e.message));}));
    let photoBusy=false;
    const skuMode=root.querySelector('#ModoCodigo'),skuInput=root.querySelector('#Codigo');
    if(skuMode&&skuInput){const updateSkuMode=()=>{const manual=skuMode.value==='MANUAL';skuInput.disabled=!manual;skuInput.required=manual;root.querySelector('#manual-sku-field').hidden=!manual;};skuMode.addEventListener('change',updateSkuMode);updateSkuMode();}
    const photo=root.querySelector('#product-photo'),preview=root.querySelector('#photo-preview'),cancel=root.querySelector('#cancel-photo');
    const original=preview?.getAttribute('src'),token=photo?.form.querySelector('[name=UploadToken]'),photoStatus=root.querySelector('#photo-status');
    cancel?.addEventListener('click',async()=>{if(photoBusy||saving)return;try{if(token.value)await request('/productos/fotografias/'+encodeURIComponent(token.value),{method:'DELETE'});token.value='';photo.value='';cancel.hidden=true;if(original){preview.src=original;preview.hidden=false;}else{preview.removeAttribute('src');preview.hidden=true;}photoStatus.textContent='Carga cancelada. La fotografía registrada se conserva.';}catch(e){announce(e.message);}});
    photo?.addEventListener('change',async()=>{
      const file=photo.files[0];if(!file||photoBusy||saving)return;
      if(file.size>3*1024*1024||!['image/png','image/jpeg'].includes(file.type)){photo.value='';announce('Selecciona una fotografía PNG o JPEG de hasta 3 MB.');return;}
      photoBusy=true;photo.disabled=true;cancel.disabled=true;photoStatus.textContent='Validando y cargando fotografía...';
      try{if(token.value)await request('/productos/fotografias/'+encodeURIComponent(token.value),{method:'DELETE'});token.value='';const uploaded=await request('/productos/fotografias',{method:'POST',headers:{'Content-Type':file.type,'X-File-Name':'photo.'+(file.type==='image/png'?'png':'jpg')},body:file});token.value=uploaded.token;preview.src=uploaded.url;preview.hidden=false;cancel.hidden=false;photoStatus.textContent='Fotografía validada. Guarda el producto para asociarla.';}catch(e){photoStatus.textContent='La carga no se completo.';announce(e.message);}finally{photoBusy=false;photo.disabled=false;cancel.disabled=false;}
    });
    const confirmation=async(form,submitter)=>{
      const state=form.querySelector('[data-original-state]');
      const purchase=form.elements.TipoMovimiento?.value==='COMPRA';
      const text=purchase?`Confirmar entrada: ${form.elements.Cantidad.value} unidades del proveedor ${form.elements.ProveedorId.selectedOptions[0]?.textContent}. Documento: ${form.elements.DocumentoRespaldo.value}.`:form.dataset.confirm||(state?.dataset.originalState==='1'&&state.value==='0'?'Inactivar este proveedor conserva sus relaciones históricas e impide nuevas asociaciones.':null);
      if(!text)return true;
      const dialog=root.querySelector('#master-confirm');root.querySelector('#confirm-description').textContent=text;
      dialog.querySelector('[value="confirm"]').textContent=purchase?'Confirmar entrada':'Confirmar operación';
      return new Promise(resolve=>{dialog.returnValue='cancel';dialog.addEventListener('close',()=>{submitter?.focus();resolve(dialog.returnValue==='confirm');},{once:true});dialog.showModal();});
    };
    for(const form of root.querySelectorAll('[data-master-form]')){
      let busy=false;form.addEventListener('submit',async event=>{
        event.preventDefault();if(busy||saving)return;
        const errorTarget=form.querySelector('.form-feedback')||document.getElementById('module-message');
        if(photoBusy){announce('Espera a que termine la carga de la fotografía.',false,errorTarget);return;}
        if(!form.reportValidity())return;
        const phone=form.elements.Telefono;if(phone?.value&&!/[0-9]/.test(phone.value)){announce('El telefono debe contener al menos un número.',false,errorTarget);phone.focus();return;}
        const data=Object.fromEntries(new FormData(form));if(form.querySelector('[name=QuitarFotografia]'))data.QuitarFotografia=form.querySelector('[name=QuitarFotografia]').checked;
        busy=true;saving=true;
        try{
          if(!await confirmation(form,event.submitter))return;
          form.setAttribute('aria-busy','true');if(event.submitter){event.submitter.disabled=true;event.submitter.dataset.label=event.submitter.textContent;event.submitter.textContent='Guardando...';}
          const result=await request(form.getAttribute('action'),{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});
          const url=new URL(location.href);url.searchParams.delete('nuevo');url.searchParams.delete('editar');url.searchParams.set('id',String(result.id));
          if(result.activo===true)url.searchParams.delete('estado');
          await navigate(url,{replace:true,feedback:result.codigo?'Producto guardado correctamente. SKU: '+result.codigo:result.mensaje||'Operación confirmada correctamente.'});
        }catch(e){announce(e.message,false,errorTarget);if(e.status===409){const hint=document.createElement('p');hint.textContent='Tus campos se conservan. Copia los cambios pendientes y consulta la versión vigente antes de volver a guardar.';const link=document.createElement('a');link.href=location.href;link.textContent=' Consultar versión vigente';hint.append(link);errorTarget.append(hint);}else if(!e.status||e.status===503){form.dataset.uncertain='1';announce('No fue posible confirmar el resultado. Consulta el registro antes de volver a enviarlo.',false,errorTarget);}}
        finally{busy=false;saving=false;form.removeAttribute('aria-busy');if(event.submitter?.dataset.label){event.submitter.disabled=form.dataset.uncertain==='1';event.submitter.textContent=event.submitter.dataset.label;}}
      });
    }
    const supplier=root.querySelector('#ProveedorId');const supplierReady=()=>{const button=root.querySelector('[data-requires-supplier]');if(button)button.disabled=!supplier?.value||supplier.selectedOptions[0]?.dataset.inactive==='true';};supplier?.addEventListener('change',supplierReady);if(supplier)supplierReady();
    root.querySelector('#supplier-find')?.addEventListener('click',async event=>{
      const button=event.currentTarget;button.disabled=true;
      try{const result=await request((location.pathname==='/inventario'?'/inventario':'/productos')+'/proveedores?buscar='+encodeURIComponent(root.querySelector('#supplier-search').value));const chosen=supplier.selectedOptions[0]?.cloneNode(true);supplier.replaceChildren(new Option('Selecciona un proveedor',''));if(chosen?.value)supplier.append(chosen);for(const s of result.rows.filter(s=>s.Activo))if(String(s.ProveedorId)!==chosen?.value)supplier.add(new Option(s.Nombre,String(s.ProveedorId)));const alternative=root.querySelector('#alternative-supplier');if(alternative){for(const s of result.rows.filter(s=>s.Activo))if(![...alternative.options].some(o=>o.value===String(s.ProveedorId)))alternative.add(new Option(s.Nombre,String(s.ProveedorId)));}if(chosen?.value)supplier.value=chosen.value;supplierReady();announce(result.rows.some(s=>s.Activo)?'Consulta de proveedores completada.':'No hay proveedores activos coincidentes.',true);}catch(e){announce(e.message);}finally{button.disabled=false;}
    });
    const movement=root.querySelector('#TipoMovimiento');
    if(movement){const purchase=root.querySelector('[data-purchase-supplier]');const updatePurchase=()=>{if(!purchase)return;const buying=movement.value==='COMPRA';purchase.hidden=!buying;purchase.querySelectorAll('input,select,button').forEach(el=>{el.disabled=!buying||movement.disabled;});const choice=purchase.querySelector('select');if(choice)choice.required=buying;};movement.addEventListener('change',updatePurchase);updatePurchase();const preview=root.querySelector('[data-stock-preview]');const quantity=movement.form.elements.Cantidad;const updateStock=()=>{if(preview){const previous=Number(preview.dataset.stockPreview),amount=Number(quantity.value);preview.textContent=quantity.validity.valid&&amount>0?`Stock anterior: ${previous}. Cantidad: ${amount}. Stock previsto: ${previous+(movement.value==='AJUSTE_EGRESO'?-amount:amount)}. El saldo definitivo se confirma en Kardex.`:`Stock anterior: ${previous}. Indica una cantidad válida.`;}};movement.addEventListener('change',updateStock);quantity.addEventListener('input',updateStock);updateStock();}
    if(movement){const help=document.createElement('p');help.className='movement-help';help.id='movement-help';movement.setAttribute('aria-describedby',help.id);movement.closest('.master-field').append(help);const update=()=>{help.textContent=movement.value==='COMPRA'?'Suma unidades por una compra respaldada por documento.':movement.value==='AJUSTE_INGRESO'?'Suma unidades para corregir una diferencia documentada.':'Resta unidades para corregir una diferencia; no permite saldo negativo.';};movement.addEventListener('change',update);update();}
  }
  init();
})();
