import { B } from '../data/balance.js';
import { ROLES } from '../data/roles.js';
import { distance } from '../util/math.js';
import { applyStatus } from './status.js';
import { element } from './elements.js';
import { opponents, strike, targetFor } from './combat.js';
import { move } from './space.js';
export function cast(w,u,key) {
  if(!u.alive || u.statuses.frozen || !ROLES[u.role]?.skills.includes(key) || u.cooldowns[key]>0)return false;
  const allies=w.units.filter(v=>v.alive && v.team===u.team);
  const foes=opponents(w,u).filter(v=>distance(u,v)<=B.sight);
  const target=targetFor(w,u);
  if(key==='taunt')for(const v of foes){v.threat[u.id]=100;v.target=u.id;}
  if(key==='guard')applyStatus(w,u,'guarded');
  if(key==='mend'){
    const v=allies.sort((a,b)=>a.hp/a.maxHP-b.hp/b.maxHP)[0];
    if(v){v.hp=Math.min(v.maxHP,v.hp+B.healAlly);w.emit('healed',{unit:v.id});}
  }
  if(key==='cleanse')for(const v of allies){delete v.statuses.poison;delete v.statuses.burn;}
  if(key==='dash'){const a=u.facing+Math.PI;move(w,u,Math.cos(a),Math.sin(a));}
  if(key==='mark' && target)applyStatus(w,target,'mark');
  if(['cleave','slam','volley'].includes(key))for(const v of foes)if(distance(u,v)<(key==='volley'?B.sight:2))strike(w,u,v,1.3);
  if(['rain','storm','frost'].includes(key))for(const v of foes)element(w,v,{rain:'water',storm:'lightning',frost:'ice'}[key],u);
  u.cooldowns[key]=B.skillCooldown;w.castLeft=B.tick;w.emit('cast',{unit:u.id,skill:key});return true;
}
