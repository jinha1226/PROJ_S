import * as THREE from 'three';
import { WEAPONS } from '../data/weapons.js';
import { ARMOR, BRANDS, EGOS, SLOTS } from '../data/gear.js';
import { createDoll, updateGear, materials } from '../render/diorama/dolls.js';
import { equip } from '../sim/gear.js';
import { useItem } from '../sim/items.js';
import { ITEMS } from '../data/items.js';
import { openPanel, html, button, escape, $ } from './dom.js';
export function gearName(g) {
  if(!g)return '—';
  if(g.name)return g.name;
  const base=WEAPONS[g.base]?.name||ARMOR[g.base]?.name;
  if(!g.known)return `${base}${['ring','amulet'].includes(g.base)?'':' ?'}`;
  return `${g.plus>=0?'+':''}${g.plus} ${BRANDS[g.brand]||EGOS[g.ego]||''} ${base}${g.artifact?' ✦':''}`;
}
function previewDoll(container,u) {
  const renderer=new THREE.WebGLRenderer({alpha:true,antialias:true});renderer.setSize(145,205);renderer.setPixelRatio(Math.min(2,devicePixelRatio));container.append(renderer.domElement);
  const scene=new THREE.Scene(),camera=new THREE.PerspectiveCamera(32,145/205,0.1,10);camera.position.set(1.1,1.3,2.9);camera.lookAt(0,0.65,0);
  scene.add(new THREE.HemisphereLight('#fff2d1','#496171',3));const light=new THREE.DirectionalLight('#ffd392',3);light.position.set(2,4,3);scene.add(light);
  const mat=materials(),model=createDoll(u,mat);updateGear(model,u,mat);scene.add(model.doll);renderer.render(scene,camera);
  $('panel').addEventListener('close',()=>{scene.traverse(o=>{o.geometry?.dispose();if(o.material)o.material.dispose();});renderer.dispose();},{once:true});
  return ()=>{updateGear(model,u,mat);renderer.render(scene,camera);};
}
export function inventory(app,tab='gear',selected=null) {
  const w=app.world,u=w.units.find(u=>u.ctrl==='player'),body=openPanel('가방');
  const tabs=html(body,'<div class="tabs"></div>').firstChild;
  tabs.append(button('장비',()=>inventory(app,'gear'),{className:tab==='gear'?'active':''}),button('소모품',()=>inventory(app,'items'),{className:tab==='items'?'active':''}));
  if(tab==='items'){
    for(const [key,n]of Object.entries(w.items))if(n>0){const def=ITEMS[key],row=html(body,`<div class="row"><div>${escape(w.identified[key]?def.name:def.appearance)} ×${n}<small>${w.identified[key]?escape(def.line):'?'}</small></div></div>`).firstChild;row.append(button('고르기',()=>{app.selectedItem=key;$('panel').close();}));}return;
  }
  const layout=html(body,'<div class="gear-layout"><div class="slots left"></div><div class="doll-card"></div><div class="slots right"></div></div>').firstChild;
  Object.entries(SLOTS).forEach(([slot,label],i)=>{const b=button('',()=>inventory(app,'gear',u.gear[slot]));b.innerHTML=`${label}<small>${escape(gearName(u.gear[slot]))}</small>`;layout.querySelector(i<5?'.left':'.right').append(b);});
  previewDoll(layout.querySelector('.doll-card'),u);
  if(selected){
    const current=u.gear[selected.slot],def=WEAPONS[selected.base]||ARMOR[selected.base],oldDef=current?(WEAPONS[current.base]||ARMOR[current.base]):{};
    const stat=selected.slot==='weapon'?'damage':'armor';
    const value=g=>g?.known?( (WEAPONS[g.base]||ARMOR[g.base])[stat]||0 )+g.plus:null;
    const next=value(selected),before=value(current),delta=next!==null&&before!==null?next-before:null;
    html(body,`<div class="compare"><div>입은 것<br>${escape(gearName(current))}<br>${before??'?'}</div><div>고른 것<br>${escape(gearName(selected))}<br>${next??'?'} <span class="${delta>=0?'up':'down'}">${delta===null?'?':delta>=0?'+'+delta:delta}</span><br>${escape(def.line)}</div></div>`);
    const row=html(body,'<div class="tabs"></div>').firstChild;
    if(u.inventory.includes(selected))row.append(button('입기',()=>{equip(w,u,selected.id);inventory(app,'gear',selected);}));
    if(selected.base==='ring' && u.inventory.includes(selected))row.append(button('두 번째 반지',()=>{equip(w,u,selected.id,'ring2');inventory(app);}));
    row.append(button('확인',()=>{useItem(w,u,'identify',u,selected);inventory(app,'gear',selected);},{disabled:!w.items.identify}),button('강화',()=>{useItem(w,u,'enhance',u,selected);inventory(app,'gear',selected);},{disabled:!w.items.enhance}));
  }
  html(body,'<div class="section-label">가방 속 장비</div>');const bag=html(body,'<div class="bag"></div>').firstChild;
  for(const g of u.inventory)bag.append(button(gearName(g),()=>inventory(app,'gear',g)));
}
