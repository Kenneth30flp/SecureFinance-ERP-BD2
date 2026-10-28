'use strict';
document.querySelectorAll('.nav-area').forEach(area=>{
 area.addEventListener('toggle',()=>{if(area.open)document.querySelectorAll('.nav-area[open]').forEach(other=>{if(other!==area)other.open=false;});});
 area.addEventListener('keydown',event=>{if(event.key==='Escape'){area.open=false;area.querySelector('summary').focus();event.preventDefault();}});
});
document.addEventListener('click',event=>{if(!event.target.closest('.nav-area'))document.querySelectorAll('.nav-area[open]').forEach(area=>{area.open=false;});});
document.addEventListener('keydown',event=>{if(event.key==='Escape')document.querySelectorAll('.nav-area[open]').forEach(area=>{area.open=false;area.querySelector('summary').focus();});});
