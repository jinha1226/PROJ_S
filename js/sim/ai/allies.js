import { B } from '../../data/balance.js';
import { ROLES } from '../../data/roles.js';
import { distance } from '../../util/math.js';
import { walkToward, shapeContains } from '../space.js';
import { autoAttack, targetFor } from '../combat.js';
import { cast } from '../roles.js';
export function allyThink(w,u,dt) {
  if(u.statuses.frozen)return;
  const hero=w.units.find(v=>v.ctrl==='player');
  const allies=w.units.filter(v=>v.alive && v.team==='party');
  const slot=allies.indexOf(u);
  const dangers=w.telegraphs.filter(t=>t.team!=='party' && t.kind!=='stack' && shapeContains(t,u));
  if(dangers.length && w.command!=='gather'){
    const t=dangers[0];
    const dx=u.x-t.x,dy=u.y-t.y,d=Math.hypot(dx,dy)||1;
    walkToward(w,u,{x:u.x+(dy||1)/d*2,y:u.y-dx/d*2},dt);return;
  }
  if(w.command==='focus')u.target=hero.target;
  const stack=w.telegraphs.find(t=>t.kind==='stack');
  if(w.command==='gather'){
    const p=stack||hero;
    if(distance(u,p)>0.65)walkToward(w,u,{x:p.x+Math.cos(slot*2.4)*0.65,y:p.y+Math.sin(slot*2.4)*0.65},dt);
  }else if(w.command==='retreat')walkToward(w,u,hero,dt);
  else if(w.command==='spread' && allies.some(v=>v!==u && distance(u,v)<B.raidRadius*2)) {
    const a=slot*2.4;walkToward(w,u,{x:hero.x+Math.cos(a)*3,y:hero.y+Math.sin(a)*3},dt);
  }else{
    const target=targetFor(w,u);
    if(target && distance(hero,target)<B.sight){
      const ranged=['archer','healer','shaman'].includes(u.role);
      if(distance(u,target)>(ranged?4:1))walkToward(w,u,target,dt);
      if(ranged && distance(u,target)<2)walkToward(w,u,target,dt,true);
    }else if(distance(u,hero)>1.5)walkToward(w,u,hero,dt);
  }
  const role=ROLES[u.role];
  if(role){
    const target=targetFor(w,u);
    if(u.role==='healer' && allies.some(v=>v.hp<v.maxHP*0.75))cast(w,u,'mend');
    else if(target && distance(u,target)<B.sight){
      if(u.role==='shaman'){const key=target.statuses.wet?'storm':'rain';cast(w,u,key);}
      else cast(w,u,role.skills[0]);
    }
  }
  autoAttack(w,u);
}
