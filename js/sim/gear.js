import { WEAPONS } from '../data/weapons.js';
import { ARMOR, BRANDS, EGOS, RELICS } from '../data/gear.js';
import { B } from '../data/balance.js';
export function createGear(world, base, options={}) {
  const def=WEAPONS[base] || ARMOR[base];
  return { id: `g${world.nextId++}`, base, slot: WEAPONS[base]?'weapon':def.slot,
    plus:0, brand:null, ego:null, known:false, used:0, artifact:false, properties:[], ...options };
}
export function rollGear(world) {
  const base=world.rng.pick([...Object.keys(WEAPONS), ...Object.keys(ARMOR)]);
  const g=createGear(world,base,{plus:world.rng.int(-1,2)});
  if (world.rng()<0.45) g[g.slot==='weapon'?'brand':'ego']=world.rng.pick(Object.keys(g.slot==='weapon'?BRANDS:EGOS));
  if (world.rng()<B.artifactChance) {
    g.artifact=true;
    g.properties=[world.rng.pick(Object.keys(EGOS)),world.rng.pick(Object.keys(EGOS))];
    g.price=world.rng()<0.5?'slow':null;
  }
  if (world.rng()<B.artifactChance) Object.assign(g,world.rng.pick(RELICS),{known:true});
  return g;
}
export function recalculate(u) {
  u.armor=0; u.evade=0; u.resist={}; u.speed=u.baseSpeed || B.heroSpeed;
  for(const g of Object.values(u.gear)) {
    if(!g)continue;
    const def=ARMOR[g.base];
    if(def){u.armor+=Math.max(0,def.armor+g.plus); u.evade-=def.weight*B.armorPenalty;}
    for(const ego of [g.ego,...g.properties]) {
      if(['fire','ice','lightning','poison'].includes(ego)) u.resist[ego]=Math.min(3,(u.resist[ego]||0)+1);
      if(ego==='guard')u.armor+=2;
    }
    if(g.price==='slow')u.speed*=0.9;
  }
  u.weapon=u.gear.weapon?.base || u.weapon;
  u.damage=WEAPONS[u.weapon].damage+(u.gear.weapon?.plus||0);
}
export function equip(world,u,id,slot) {
  const g=u.inventory.find(g=>g.id===id);
  if(!g)return false;
  const target=slot||g.slot;
  if(target!==g.slot && !(g.base==='ring' && target==='ring2'))return false;
  if(target==='shield' && WEAPONS[u.weapon].hands===2)return false;
  if(target==='weapon' && WEAPONS[g.base].hands===2 && u.gear.shield){u.inventory.push(u.gear.shield);delete u.gear.shield;}
  u.inventory=u.inventory.filter(i=>i!==g);
  if(u.gear[target])u.inventory.push(u.gear[target]);
  u.gear[target]=g; recalculate(u);
  world.emit('equipped',{unit:u.id,gear:g.id}); return true;
}
export function reveal(world,u) {
  for(const g of Object.values(u.gear)) if(g && ++g.used>=3 && !g.known){g.known=true;world.emit('identified',{gear:g.id});}
}
export function identify(world,g) { if(!g)return false;g.known=true;world.emit('identified',{gear:g.id});return true; }
export function enhance(world,u,g) { if(!g)return false;g.plus++;g.known=true;recalculate(u);world.emit('enhanced',{gear:g.id});return true; }
