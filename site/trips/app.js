const $=id=>document.getElementById(id);
const airports={LAX:'Los Angeles',SFO:'San Francisco',JFK:'New York',KIX:'Osaka / Kyoto',LIS:'Lisbon',KEF:'Keflavík',LHR:'London',HND:'Tokyo'};
const destinations=[['KIX','Kyoto','Japan','kyoto'],['LIS','Lisbon','Portugal','lisbon'],['KEF','Reykjavík','Iceland','iceland']];
let user='',plans=[];
function node(tag,text){const e=document.createElement(tag);if(text)e.textContent=text;return e;}
function button(text,action){const b=node('button',text);b.type='button';b.onclick=action;return b;}
function localDate(offset){const d=new Date();d.setDate(d.getDate()+offset);return [d.getFullYear(),String(d.getMonth()+1).padStart(2,'0'),String(d.getDate()).padStart(2,'0')].join('-');}
for(const id of ['origin','dest'])for(const [code,city] of Object.entries(airports))$(id).add(new Option(city+' · '+code,code));
$('dest').value='KIX';$('depart').min=localDate(0);$('depart').value=localDate(14);$('back').value=localDate(21);
function dates(){const round=$('planner').elements.mode.value==='round';$('returnLabel').hidden=!round;$('back').disabled=!round;$('back').min=$('depart').value;if($('back').value<$('depart').value)$('back').value=$('depart').value;}
$('planner').onchange=dates;dates();
$('swap').onclick=()=>{const from=$('origin').value;$('origin').value=$('dest').value;$('dest').value=from;};
function flightUrl(p){const q='Flights from '+p.from+' to '+p.to+' on '+p.depart+(p.back?' returning '+p.back:' one way');return 'https://www.google.com/travel/flights?q='+encodeURIComponent(q);}
function current(){if(!$('planner').reportValidity())return;if($('origin').value===$('dest').value){$('feedback').textContent='Choose two different airports.';return;}return {from:$('origin').value,to:$('dest').value,depart:$('depart').value,back:$('back').disabled?'':$('back').value};}
$('planner').onsubmit=e=>{e.preventDefault();const p=current();if(p)location.assign(flightUrl(p));};
for(const [code,city,country,photo] of destinations){
 const b=button('',()=>{$('dest').value=code;if($('origin').value===code)$('origin').value='LAX';$('planner').scrollIntoView({block:'center'});$('depart').focus();});b.className='card';
 const img=node('img');img.src=photo+'.jpg';img.alt='';const caption=node('span');caption.className='caption';const title=node('span');title.append(node('strong',city),node('small',country));caption.append(title,node('span',code+' ↗'));b.append(img,caption);$('cards').append(b);
}
async function api(path,body){const res=await fetch('/api/'+path,body===undefined?{}:{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});if(!res.ok)throw new Error(String(res.status));return res.json();}
function openLogin(){if(!$('signin').open)$('signin').showModal();}
function render(){
 const saved=location.hash==='#saved';$('saved').hidden=!saved;$('explore').hidden=saved;
 for(const link of document.querySelectorAll('nav a')){if(link.hash===(saved?'#saved':'#explore'))link.setAttribute('aria-current','page');else link.removeAttribute('aria-current');}
 $('account').textContent=user?'Sign out · '+user:'Sign in';
 $('plans').replaceChildren();
 if(!user){$('plans').append(button('Sign in to see your trips',openLogin));return;}
 if(!plans.length)$('plans').append(node('p','Your saved routes will appear here.'));
 plans.forEach((plan,i)=>{const row=node('div');row.className='ticket';const flights=node('a','Find flights ↗');flights.href=flightUrl(plan);row.append(node('strong',plan.from+' → '+plan.to),node('span',plan.depart+(plan.back?' — '+plan.back:'')),flights,button('Remove',()=>persist(plans.filter((_,j)=>j!==i))));$('plans').append(row);});
}
let busy=false;
async function persist(next){if(busy)return;busy=true;try{await api('trip',{plans:next});plans=next;render();$('feedback').textContent='Saved trips updated.';}catch{$('feedback').textContent='Could not save this change. Check your login and retry.';}finally{busy=false;}}
let awaitingSave=false;
$('save').onclick=async()=>{const p=current();if(!p)return;if(!user){awaitingSave=true;openLogin();return;}if(plans.some(existing=>JSON.stringify(existing)===JSON.stringify(p))){$('feedback').textContent='This trip is already saved.';return;}await persist([...plans,p]);};
$('signin').onclose=()=>{awaitingSave=false;$('authError').textContent='';$('pw').value='';};
$('cancel').onclick=()=>$('signin').close();
$('account').onclick=async()=>{if(!user){openLogin();return;}try{await api('logout',{});user='';plans=[];render();$('feedback').textContent='Signed out.';}catch{$('feedback').textContent='Could not sign out. Please retry.';}};
function session(s){user=s.username;plans=s.trip?.plans||[];render();}
$('auth').onsubmit=async e=>{e.preventDefault();try{session(await api('login',{login:$('name').value.trim(),password:$('pw').value}));const save=awaitingSave;$('signin').close();$('feedback').textContent='Signed in.';if(save)$('save').click();}catch{$('authError').textContent='Sign-in failed. Check your login and try again.';}};
window.onhashchange=()=>{render();$('feedback').textContent='';};
render();api('me').then(session).catch(error=>{if(error.message!=='401')$('feedback').textContent='Account service unavailable.';});
