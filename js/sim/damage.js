import { B } from '../data/balance.js';
import { rollGear } from './gear.js';
export function hurt(w,u,amount,source=null,element=null) {
  if(!u.alive)return 0;
  const mitigation=element ? 1-(u.resist[element]||0)*B.resistanceStep : 1;
  const dealt=Math.max(1,Math.round(amount*mitigation-(element?0:u.armor*0.45)));
  u.hp=Math.max(0,u.hp-dealt);
  if(source)u.threat[source.id]=(u.threat[source.id]||0)+dealt;
  w.emit('hit',{unit:u.id,source:source?.id,amount:dealt,element,x:u.x,y:u.y});
  if(u.hp===0){
    u.alive=false;u.windup=null;
    w.emit(u.ctrl==='player'?'heroDied':'killed',{unit:u.id,kind:u.kind,x:u.x,y:u.y});
    if(u.team==='foe') {
      w.stats.kills++;
      const hero=w.units.find(p=>p.ctrl==='player');
      if(hero){hero.xp+=B.xpKill;while(hero.xp>=hero.level*B.xpLevel){hero.xp-=hero.level*B.xpLevel;hero.level++;hero.maxHP+=B.levelHP;hero.hp=Math.min(hero.maxHP,hero.hp+B.levelHP);w.emit('leveled',{unit:hero.id,level:hero.level});}}
      if(w.rng()<B.dropChance || ['chief','keeper'].includes(u.kind))w.loot.push({x:u.x,y:u.y,gear:rollGear(w)});
      if(['chief','keeper'].includes(u.kind)){w.won=true;w.emit('cleared',{region:w.region,raid:w.raid});}
    }
  }
  return dealt;
}
