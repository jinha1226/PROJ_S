import { B } from '../../data/balance.js';
import { distance } from '../../util/math.js';
import { walkToward, visible } from '../space.js';
import { opponents, autoAttack, telegraph } from '../combat.js';
import { createUnit } from '../unit.js';
export function enemyThink(w,u,dt) {
  if(u.windup || u.statuses.frozen)return;
  const foes=opponents(w,u).filter(v=>visible(w,u,v));
  const target=foes.sort((a,b)=>(u.threat[b.id]||0)-(u.threat[a.id]||0) || distance(u,a)-distance(u,b))[0];
  if(!target || distance(u,target)>B.sight+2)return;
  u.target=target.id;
  if(u.statuses.fear){walkToward(w,u,target,dt,true);return;}
  u.facing=Math.atan2(target.y-u.y,target.x-u.x);
  const d=distance(u,target);
  if(u.brain==='healer'){
    const ally=w.units.find(v=>v.alive && v.team===u.team && v.hp<v.maxHP*0.7 && distance(u,v)<B.sight);
    if(ally && !u.cooldowns.heal){ally.hp=Math.min(ally.maxHP,ally.hp+B.healAlly);u.cooldowns.heal=B.skillCooldown;w.emit('healed',{unit:ally.id});return;}
  }
  if(u.brain==='boss' && !u.cooldowns.summon){
    u.cooldowns.summon=B.skillCooldown*2;
    const minion=createUnit(`u${w.nextId++}`,{kind:'goblin',x:u.x+1,y:u.y});
    w.units.push(minion);w.emit('summoned',{unit:minion.id,x:minion.x,y:minion.y});
  }
  if(['ranged','caster','healer'].includes(u.brain)) {
    if(d<2.5)walkToward(w,u,target,dt,true);
    else if(d>5)walkToward(w,u,target,dt);
    if(d<=6 && !u.cooldowns.attack){
      const caster=u.brain==='caster';
      telegraph(w,u,caster?{shape:'circle',x:target.x,y:target.y,radius:1.1,element:'fire'}:{shape:'line',x:u.x,y:u.y,angle:u.facing,reach:6,width:0.18,target:target.id});
    }
  }else if(u.brain==='charger' && d<5 && !u.cooldowns.attack){
    telegraph(w,u,{shape:'line',x:u.x,y:u.y,angle:u.facing,reach:d+1,width:0.4},'charge');
  }else{
    if(d>B.meleeReach)walkToward(w,u,target,dt);
    autoAttack(w,u);
  }
}
