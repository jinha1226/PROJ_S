import { B } from '../data/balance.js';
import { hurt } from './damage.js';
export function applyStatus(w,u,kind,duration=B.statusDuration) {
  u.statuses[kind]={left:Math.max(duration,u.statuses[kind]?.left||0),pulse:1};
  w.emit('afflicted',{unit:u.id,status:kind});
}
export function updateStatus(w,u,dt) {
  for(const [kind,s] of Object.entries(u.statuses)) {
    s.left-=dt;s.pulse-=dt;
    if(s.pulse<=0){s.pulse+=1;const damage={bleed:B.bleedDamage,poison:B.poisonDamage,burn:B.fireDamage}[kind];if(damage)hurt(w,u,damage,null,kind==='burn'?'fire':kind==='poison'?'poison':null);}
    if(s.left<=0)delete u.statuses[kind];
  }
  for(const key of Object.keys(u.cooldowns))u.cooldowns[key]=Math.max(0,u.cooldowns[key]-dt);
}
