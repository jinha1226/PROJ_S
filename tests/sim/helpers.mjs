import { createWorld } from '../../js/sim/world.js';
import { createUnit } from '../../js/sim/unit.js';
import { cellKey } from '../../js/util/math.js';
export function arena(seed=1,options={}) {
  const w=createWorld({seed,...options});w.units=w.units.filter(u=>u.team==='party');w.tiles={};
  for(let y=0;y<15;y++)for(let x=0;x<15;x++)w.tiles[cellKey(x,y)]={x,y,kind:x===0||y===0||x===14||y===14?'wall':'floor'};
  const h=w.units[0];h.x=h.prevX=5.5;h.y=h.prevY=5.5;w.flowing=true;w.events=[];w.telegraphs=[];w.visibleEnemies=[];return w;
}
export function enemy(w,kind='goblin',x=6.4,y=5.5){const u=createUnit(`enemy${w.nextId++}`,{kind,x,y});w.units.push(u);return u;}
export function advance(w,seconds){for(let i=0;i<seconds/0.05;i++)w.step();}
export function snapshot(w){return JSON.stringify(w,(key,value)=>typeof value==='function'?undefined:value instanceof Set?[...value]:value);}
