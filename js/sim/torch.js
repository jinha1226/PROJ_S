import { B } from '../data/balance.js';
import { distance, cellKey } from '../util/math.js';
import { visible } from './space.js';
export function sight(w) {
  const hero=w.units.find(u=>u.ctrl==='player');
  const insight=Object.values(hero?.gear||{}).some(g=>g.ego==='insight')?1:0;
  return B.darkSight+(B.sight-B.darkSight)*Math.min(1,w.torch/B.torch)+insight;
}
export function updateSight(w) {
  const hero=w.units.find(u=>u.ctrl==='player');if(!hero)return;
  w.visible=new Set();
  for(const t of Object.values(w.tiles))if(distance(hero,{x:t.x+0.5,y:t.y+0.5})<=sight(w) && visible(w,hero,{x:t.x+0.5,y:t.y+0.5})) {
    const key=cellKey(t.x,t.y);w.visible.add(key);w.explored.add(key);
  }
  w.visibleEnemies=w.units.filter(u=>u.alive && u.team==='foe' && w.visible.has(cellKey(u.x,u.y))).map(u=>u.id);
}
export function lightLamp(w,lamp) {
  const hero=w.units.find(u=>u.ctrl==='player');
  if(lamp.used || !hero?.alive || distance(hero,lamp)>1.5)return false;
  lamp.used=true;w.torch=Math.min(B.torch,w.torch+B.lampFuel);
  if(!w.memories.includes(lamp.name))w.memories.push(lamp.name);
  w.emit('lit',{name:lamp.name,x:lamp.x,y:lamp.y});return true;
}
