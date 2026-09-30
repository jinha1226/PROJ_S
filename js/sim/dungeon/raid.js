import { B } from '../../data/balance.js';
import { distance } from '../../util/math.js';
import { telegraph } from '../combat.js';
import { createUnit } from '../unit.js';
import { hurt } from '../damage.js';
export const MECHANICS=['slam','spread','stack','adds','shift'];
export function raidThink(w,boss,dt) {
  if(!boss.alive)return;
  w.raidLeft-=dt;
  if(w.raidLeft<=0){for(const u of w.units.filter(u=>u.alive && u.team==='party'))hurt(w,u,u.maxHP*2,boss);return;}
  boss.phase=boss.hp<boss.maxHP/3?3:boss.hp<boss.maxHP*2/3?2:1;
  if(boss.cooldowns.mechanic>0 || boss.windup)return;
  boss.cooldowns.mechanic=B.raidInterval;
  const party=w.units.filter(u=>u.alive && u.team==='party');
  const target=party.sort((a,b)=>(boss.threat[b.id]||0)-(boss.threat[a.id]||0)||distance(boss,a)-distance(boss,b))[0];
  if(!target)return;
  boss.target=target.id;
  const index=(w.raidIndex++ + (w.weekly?w.seed%MECHANICS.length:0))%MECHANICS.length;
  const kind=MECHANICS[index];
  const queue=(shape,k)=>telegraph(w,boss,{end:w.time+B.raidTell,...shape},k);
  if(kind==='slam')queue({shape:'fan',x:boss.x,y:boss.y,angle:Math.atan2(target.y-boss.y,target.x-boss.x),arc:Math.PI,reach:4},kind);
  if(kind==='spread')for(const u of party)queue({shape:'circle',x:u.x,y:u.y,radius:B.raidRadius},kind);
  if(kind==='stack')queue({shape:'circle',x:target.x,y:target.y,radius:B.stackRadius},kind);
  if(kind==='adds'){
    const x=boss.x+1,y=boss.y-1;
    queue({shape:'circle',x,y,radius:0.5},'portal');
    w.units.push(createUnit(`u${w.nextId++}`,{kind:'rat',x,y}));
    w.emit('summoned',{x,y});
  }
  if(kind==='shift'){
    boss.weakElement=w.rng.pick(['fire','ice','lightning','poison']);
    boss.resist=Object.fromEntries(['fire','ice','lightning','poison'].map(k=>[k,k===boss.weakElement?-3:2]));
    w.emit('shifted',{unit:boss.id,element:boss.weakElement});
  }
  w.emit('mechanic',{kind,phase:boss.phase});
}
