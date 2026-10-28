'use strict';
(() => {
  const button=document.getElementById('print-invoice');
  button?.addEventListener('click',()=>window.print());
  if(button&&document.body.dataset.autoPrint==='1') {
    Promise.resolve(document.fonts?.ready).then(()=>window.print());
  }
})();
