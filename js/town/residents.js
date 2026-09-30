import { B } from '../data/balance.js';
import { ROLES } from '../data/roles.js';
import { NAMES, PERSONALITIES, CHAT } from '../data/lines.js';
import { seeded } from '../util/rng.js';
import { recognizeRooms } from './settlement.js';
export function recruit(m,name=null) {
  const rng=seeded(m.seed+m.nextId),id=`r${m.nextId++}`;
  const traits=Array.from({length:6},()=>rng());
  const r={id,name:name||NAMES[m.residents.length%NAMES.length],traits,
    personality:PERSONALITIES[Math.floor(rng()*PERSONALITIES.length)],
    stance:traits[1]>0.65?'careful':traits[3]>0.6?'support':'aggressive',
    role:Object.keys(ROLES)[m.residents.length%Object.keys(ROLES).length],
    mood:65,injury:0,job:'chat',progress:0,x:9.5,y:9.5,hunger:0,birthday:rng.int(1,B.monthDays),
    line:rng.pick(CHAT)};
  m.residents.push(r);m.events.push({type:'arrived',name:r.name});return r;
}
export function setRole(m,id,role) {
  const r=m.residents.find(r=>r.id===id);
  if(!r || !ROLES[role] || ROLES[role].unlock>Math.max(1,m.cleared.length))return false;
  r.role=role;return true;
}
export function setStance(m,id,stance) {const r=m.residents.find(r=>r.id===id);if(r && ['aggressive','careful','support'].includes(stance))r.stance=stance;}
export function chooseCompanions(m,ids) {
  if(ids.length && !m.buildings.some(b=>b.kind==='training'))return false;
  if(ids.length>Math.min(4,m.cleared.length))return false;
  if(ids.some(id=>!m.residents.some(r=>r.id===id && r.injury<=0)))return false;
  m.selected=[...ids];return true;
}
export function tickResidents(m,dt) {
  const active=m.residents.filter(r=>!m.expedition.includes(r.id) && r.injury<=0);
  for(const r of active){
    r.hunger+=dt;r.progress+=dt*(0.75+r.traits[4]*0.5);
    if(r.hunger>B.hungerTime){r.hunger=0;if(m.resources.food>0){m.resources.food--;r.mood=Math.min(100,r.mood+1);}else r.mood=Math.max(0,r.mood-5);}
    const blueprint=m.blueprints[0];
    r.job=blueprint?'build':m.resources.food<4?'farm':m.resources.wood<50?'wood':m.resources.stone<30?'stone':'chat';
    const goal=blueprint||{x:10+Math.sin(m.time*0.1+Number(r.id.slice(1)))*2,y:10+Math.cos(m.time*0.1+Number(r.id.slice(1)))*2};
    r.x+=(goal.x-r.x)*Math.min(1,dt);r.y+=(goal.y-r.y)*Math.min(1,dt);
    if(r.progress>=B.workTime){
      r.progress=0;
      if(blueprint){m.buildings.push(m.blueprints.shift());m.revision++;recognizeRooms(m);m.events.push({type:'built',kind:blueprint.kind});}
      else if(r.job==='wood')m.resources.wood+=2;
      else if(r.job==='stone')m.resources.stone+=1;
      else if(r.job==='farm')m.resources.food+=1;
      else {
        const other=active.find(v=>v!==r);
        if(other){const key=[r.id,other.id].sort().join(':');const change=r.traits[3]>0.5?1:-1;m.relationships[key]=(m.relationships[key]||0)+change;m.events.push({type:change>0?'bonded':'argued',name:r.name,other:other.name});r.line=CHAT[Math.floor(m.time/B.workTime)%CHAT.length];}
      }
    }
  }
  for(const farm of m.buildings.filter(b=>b.kind==='farm')){
    const dist=Math.hypot(farm.x-10,farm.y-10);
    if(dist<=m.light){farm.growth=(farm.growth||0)+dt*Math.max(0.2,(m.light-dist)/m.light);if(farm.growth>=B.cropTime){farm.growth=0;m.resources.food+=3;m.events.push({type:'harvested'});}}
  }
}
