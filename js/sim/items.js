import { B } from '../data/balance.js';
import { ITEMS } from '../data/items.js';
import { distance } from '../util/math.js';
import { applyStatus } from './status.js';
import { element, changeTile } from './elements.js';
import { identify, enhance } from './gear.js';
import { canStand, visible } from './space.js';
export function useItem(w,u,key,point=u,gear=null) {
  const item=ITEMS[key];
  if(!item || !u.alive || !(w.items[key]>0))return false;
  if(item.kind==='gear'){
    const chosen=gear || u.gear.weapon;
    if(!chosen)return false;
    if(key==='identify')identify(w,chosen);else enhance(w,u,chosen);
  } else if(key==='heal')u.hp=Math.min(u.maxHP,u.hp+B.heal);
  else if(key==='antidote'){delete u.statuses.poison;}
  else if(key==='haste')applyStatus(w,u,'haste');
  else if(key==='teleport'){
    const choices=Object.values(w.tiles).filter(t=>canStand(w,u,t.x+0.5,t.y+0.5));
    const tile=w.rng.pick(choices);if(!tile)return false;u.x=tile.x+0.5;u.y=tile.y+0.5;
  }else if(key==='fear'){
    for(const v of w.units)if(v.alive && v.team!==u.team && distance(u,v)<B.sight && visible(w,u,v))applyStatus(w,v,'fear');
  }else{
    if(distance(u,point)>B.sight || !visible(w,u,point))return false;
    if(['water','oil','smoke'].includes(key))changeTile(w,point.x,point.y,key);
    for(const v of w.units)if(v.alive && distance(v,point)<B.burstRadius && item.element)element(w,v,item.element,u);
  }
  w.items[key]--;w.identified[key]=true;w.castLeft=B.tick;
  w.emit('used',{unit:u.id,item:key,x:point.x,y:point.y});return true;
}
export function pickLoot(w,u) {
  const items=w.loot.filter(i=>distance(u,i)<=1.5);
  for(const item of items){u.inventory.push(item.gear);if(item.gear.owner && !w.memories.includes(item.gear.owner))w.memories.push(item.gear.owner);w.emit('picked',{gear:item.gear.id});}
  w.loot=w.loot.filter(i=>!items.includes(i));return items.length;
}
