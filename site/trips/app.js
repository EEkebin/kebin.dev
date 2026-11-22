const $ = id => document.getElementById(id);
const titles = ['Higashiyama lanes', 'Arashiyama riverside', 'Fushimi & downtown'];
const key = 'waypost-kyoto-v1';
let trip = {days:[['Walk the lanes of Ninenzaka','Visit Kiyomizu-dera'],['Explore the bamboo grove','Picnic by the Katsura River'],['Walk the Fushimi Inari gates','Dinner near Nishiki Market']],packing:[['Passport',false],['Walking shoes',false],['Travel adapter',false],['Rain jacket',false]]};
try { const saved = localStorage.getItem(key); if(saved) trip = JSON.parse(saved); } catch {}
let day = 0;
function save() { localStorage.setItem(key, JSON.stringify(trip)); render(); }
function el(tag,text) { const node=document.createElement(tag); if(text!==undefined) node.textContent=text; return node; }
function button(text, action) { const node=el('button',text); node.onclick=action; return node; }
function check(item) {
  const label=el('label'); label.className='check';
  const input=el('input'); input.type='checkbox'; input.checked=item[1];
  input.onchange=()=>{item[1]=input.checked; save();}; label.append(input,el('span',item[0])); return label;
}
function list(id, nodes) { $(id).replaceChildren(...nodes); }
function render() {
  const route = ['packing','itinerary'].includes(location.hash.slice(1)) ? location.hash.slice(1) : 'overview';
  for(const view of document.querySelectorAll('.view')) view.hidden=view.id!==route;
  $('hero').hidden=route!=='overview';
  for(const link of $('nav').children) {
    if(link.hash==='#'+route) link.setAttribute('aria-current','page'); else link.removeAttribute('aria-current');
  }
  list('days',titles.map((title,i)=>{
    const a=el('a'); a.className='day'; a.href='#itinerary'; a.onclick=()=>{day=i;};
    const info=el('span'); info.append(el('strong',title),el('small',trip.days[i].length+' activities'));
    a.append(el('b','0'+(i+1)),info,el('i','→')); return a;
  }));
  const packed=trip.packing.filter(item=>item[1]).length;
  $('summary').textContent=packed+' of '+trip.packing.length+' items packed';
  $('progress').max=trip.packing.length||1; $('progress').value=packed;
  list('preview',trip.packing.slice(0,3).map(check));
  list('dayTabs',titles.map((_,i)=>{const b=button('Day '+(i+1),()=>{day=i;render();}); b.setAttribute('aria-pressed',i===day); return b;}));
  $('dayTitle').textContent=titles[day];
  function row(tag,content,remove) {const node=el(tag); node.className='item'; node.append(content,button('Remove',()=>{remove();save();})); return node;}
  list('activities',trip.days[day].map((name,i)=>row('li',el('span',name),()=>trip.days[day].splice(i,1))));
  list('items',trip.packing.map((item,i)=>row('div',check(item),()=>trip.packing.splice(i,1))));
}
function closeMenu(){ $('nav').classList.remove('open'); $('menu').setAttribute('aria-expanded','false'); }
$('menu').onclick=()=>$('menu').setAttribute('aria-expanded',$('nav').classList.toggle('open'));
$('nav').onclick=closeMenu;
window.onhashchange=()=>{closeMenu(); render(); window.scrollTo(0,0);};
function edit(packing){
  $('dialogTitle').textContent=packing?'Add a packing item':'Add an activity';
  $('entryLabel').textContent=packing?'Item name':'Day '+(day+1)+' activity';
  $('entry').value=''; $('editor').showModal(); $('entry').focus();
  $('editor').querySelector('form').onsubmit=e=>{
    e.preventDefault(); const value=$('entry').value.trim(); if(!value)return;
    if(packing) trip.packing.push([value,false]); else trip.days[day].push(value);
    save(); $('editor').close();
  };
}
$('addActivity').onclick=()=>edit(false); $('addItem').onclick=()=>edit(true);
$('cancel').onclick=()=>$('editor').close(); render();
