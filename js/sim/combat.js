import { B } from '../data/balance.js';
import { ENEMIES } from '../data/enemies.js';
import { distance } from '../util/math.js';
import { weaponOf } from './unit.js';
import { visible, shapeContains, move } from './space.js';
import { hurt } from './damage.js';
import { applyStatus } from './status.js';
import { element } from './elements.js';
import { reveal } from './gear.js';
export function opponents(w,u) {return w.units.filter(v=>v.alive && v.team!==u.team && v.team!=='neutral');}
export function targetFor(w,u) {
  const enemies=opponents(w,u).filter(v=>visible(w,u,v));
  return enemies.find(v=>v.id===u.target)||enemies.sort((a,b)=>distance(u,a)-distance(u,b))[0];
}
export function telegraph(w,u,t,kind='attack') {
  const tell={id:`t${w.nextId++}`,owner:u.id,team:u.team,start:w.time,end:w.time+B.tell,kind,...t};
  w.telegraphs.push(tell);u.windup=tell.id;w.emit('telegraphed',{unit:u.id,kind});return tell;
}
export function attackShape(u,weapon) {
  return {shape:weapon.shape==='projectile'?'line':weapon.shape,x:u.x,y:u.y,angle:u.facing,arc:weapon.angle,reach:weapon.reach,width:weapon.width||0.2};
}
export function strike(w,u,v,multiplier=1) {
  const form=weaponOf(u).form;
  let amount=u.damage*multiplier*(ENEMIES[v.kind]?.weak===form?1.3:1);
  if(v.statuses.mark)amount*=B.critBonus;
  if(u.statuses.fracture)amount*=0.75;
  if(v.statuses.guarded)amount*=0.5;
  if(w.rng()<Math.max(0,v.evade)){w.emit('miss',{unit:v.id});return;}
  const dealt=hurt(w,v,amount,u);
  if(v.alive){applyStatus(w,v,{slash:'bleed',blunt:'fracture',pierce:'mark'}[form]);
    const d=distance(u,v)||1;
    if(!move(w,v,(v.x-u.x)/d*B.knockback,(v.y-u.y)/d*B.knockback))hurt(w,v,B.wallDamage,u);
  }
  const brand=u.gear.weapon?.brand;
  if(['fire','ice','lightning','poison'].includes(brand))element(w,v,brand,u);
  if(brand==='drain')u.hp=Math.min(u.maxHP,u.hp+Math.round(dealt*0.2));
  if(brand==='blood' && v.alive)applyStatus(w,v,'bleed');
  if(brand==='crush' && v.alive)applyStatus(w,v,'fracture');
  if(brand==='pierce' && v.alive)applyStatus(w,v,'mark');
  if(Object.values(v.gear).some(g=>g.ego==='thorns') && u.alive)hurt(w,u,2,v);
  reveal(w,u);
}
export function autoAttack(w,u) {
  if(u.windup || u.cooldowns.attack>0 || u.statuses.frozen)return;
  const target=targetFor(w,u),weapon=weaponOf(u);
  if(!target || distance(u,target)>weapon.reach+target.radius)return;
  u.facing=Math.atan2(target.y-u.y,target.x-u.x);
  const shape=attackShape(u,weapon);
  if(u.team==='foe'){telegraph(w,u,{...shape,target:target.id});return;}
  w.emit('swung',{unit:u.id,...shape});
  for(const v of opponents(w,u))if(shapeContains(shape,v) && visible(w,u,v))strike(w,u,v);
  u.cooldowns.attack=weapon.interval;
}
export function resolveTelegraphs(w) {
  const due=w.telegraphs.filter(t=>t.end<=w.time);
  w.telegraphs=w.telegraphs.filter(t=>t.end>w.time);
  for(const t of due){
    const u=w.units.find(u=>u.id===t.owner);
    if(!u?.alive)continue;
    u.windup=null;u.cooldowns.attack=weaponOf(u).interval;
    const targets=opponents(w,u).filter(v=>shapeContains(t,v));
    if(t.kind==='stack') {
      const damage=u.damage*2/Math.max(1,targets.length);
      targets.forEach(v=>hurt(w,v,damage,u));
    } else if(t.kind==='spread') {
      for(const v of targets){const overlaps=due.filter(other=>other.kind==='spread' && shapeContains(other,v)).length;hurt(w,v,u.damage*(overlaps>1?2:1),u);}
    } else for(const v of targets){strike(w,u,v,t.kind==='slam'?1.5:1);if(t.element)element(w,v,t.element,u);}
    if(!targets.length)w.emit('whiff',{unit:u.id});
    if(t.kind==='charge'){const dx=Math.cos(t.angle)*t.reach,dy=Math.sin(t.angle)*t.reach;for(let i=0;i<20;i++)move(w,u,dx/20,dy/20);}
    w.emit('swung',{unit:u.id,...t});
  }
}
