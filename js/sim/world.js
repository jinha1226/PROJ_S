import { HERO_NAME } from '../data/lines.js';
import { B } from '../data/balance.js';
import { START_ITEMS } from '../data/items.js';
import { seeded } from '../util/rng.js';
import { cellKey, distance } from '../util/math.js';
import { createUnit } from './unit.js';
import { createGear, recalculate } from './gear.js';
import { generateFloor } from './dungeon/map.js';
import { updateStatus } from './status.js';
import { terrainEffects, updateTerrain } from './elements.js';
import { move, walkToward, path, tileAt } from './space.js';
import { autoAttack, resolveTelegraphs } from './combat.js';
import { updateSight } from './torch.js';
import { enemyThink } from './ai/enemies.js';
import { allyThink } from './ai/allies.js';
import { addCompanion, checkDefeat } from './party.js';
import { raidThink } from './dungeon/raid.js';
export function createWorld(options={}) {
  const w={seed:options.seed??1,rng:seeded(options.seed??1),time:0,flowing:false,
    floor:options.raid?5:1,region:options.region||0,tutorial:!!options.tutorial,
    raid:!!options.raid,weekly:!!options.weekly,raidLeft:B.raidLimit,raidIndex:0,
    nextId:1,revision:0,units:[],events:[],telegraphs:[],loot:[],lamps:[],memories:[],
    torch:B.torch,items:{...START_ITEMS},identified:{},input:{x:0,y:0},
    command:'focus',autoPath:[],exploring:false,castLeft:0,won:false,lost:false,
    stats:{kills:0,distance:0},...options};
  w.emit=(type,data)=>w.events.push({t:w.time,type,...data});
  w.drainEvents=()=>w.events.splice(0);
  const hero=createUnit('hero',{name:options.name||HERO_NAME,role:options.role||null});
  hero.gear.weapon=createGear(w,'sword',{known:true});
  hero.gear.body=createGear(w,'cloth',{known:true});
  hero.inventory=[createGear(w,'spear'),createGear(w,'flail'),createGear(w,'bow'),createGear(w,'leather')];
  if(options.stored)hero.inventory.push(...structuredClone(options.stored));
  if(options.trait==='brave')hero.maxHP+=B.levelHP;
  if(options.trait==='careful')hero.speed*=1.05;
  hero.hp=hero.maxHP;hero.baseSpeed=hero.speed;recalculate(hero);w.units.push(hero);
  for(const resident of options.companions||[])addCompanion(w,resident);
  generateFloor(w);updateSight(w);
  w.step=()=>step(w);return w;
}
export function setInput(w,x,y) {
  const length=Math.hypot(x,y)||1;
  w.input={x:x/Math.max(1,length),y:y/Math.max(1,length)};
  if(x||y){w.autoPath=[];w.exploring=false;}
}
export function selectTarget(w,id) {const hero=w.units.find(u=>u.ctrl==='player');hero.target=id;w.autoPath=[];w.exploring=false;}
export function walkTo(w,point) {const hero=w.units.find(u=>u.ctrl==='player');w.autoPath=path(w,hero,point);w.exploring=false;}
export function explore(w) {
  const hero=w.units.find(u=>u.ctrl==='player');
  if(w.visibleEnemies.length)return false;
  const candidates=Object.values(w.tiles).filter(t=>t.kind!=='wall' && !(t.kind==='door' && !t.open) && !w.explored.has(cellKey(t.x,t.y)));
  const destination=candidates.sort((a,b)=>distance(hero,a)-distance(hero,b)).find(t=>path(w,hero,{x:t.x+0.5,y:t.y+0.5}).length);
  if(!destination)return false;w.autoPath=path(w,hero,{x:destination.x+0.5,y:destination.y+0.5});w.exploring=true;return true;
}
export function openDoor(w,x,y) {
  const hero=w.units.find(u=>u.ctrl==='player'),t=tileAt(w,x,y);
  if(!t || t.kind!=='door' || distance(hero,{x:t.x+0.5,y:t.y+0.5})>1.8)return false;
  t.open=!t.open;w.revision++;updateSight(w);w.emit('opened',{});return true;
}
export function rest(w) {
  if(w.visibleEnemies.length)return false;
  const hero=w.units.find(u=>u.ctrl==='player');
  if(hero.hp>=hero.maxHP)return false;
  w.resting=true;return true;
}
export function step(w) {
  if(!w.flowing || w.lost || w.won)return false;
  const dt=B.tick;w.time+=dt;w.castLeft=Math.max(0,w.castLeft-dt);
  const hero=w.units.find(u=>u.ctrl==='player');
  const previousVisible=[...w.visibleEnemies];
  for(const u of w.units){u.prevX=u.x;u.prevY=u.y;if(u.alive){updateStatus(w,u,dt);terrainEffects(w,u,dt);}}
  if(hero.alive && !hero.statuses.frozen) {
    let travelled=0;
    if(w.resting){
      if(w.visibleEnemies.length || hero.hp>=hero.maxHP)w.resting=false;
      else hero.hp=Math.min(hero.maxHP,hero.hp+dt*2);
    }else if(w.command==='auto'){allyThink(w,hero,dt);}
    else if(w.input.x || w.input.y)travelled=move(w,hero,w.input.x*hero.speed*dt+hero.slide.x,w.input.y*hero.speed*dt+hero.slide.y);
    else if(w.autoPath.length){const point=w.autoPath[0];travelled=walkToward(w,hero,point,dt);if(distance(hero,point)<0.18)w.autoPath.shift();}
    w.torch=Math.max(0,w.torch-travelled*B.torchBurn);w.stats.distance+=travelled;autoAttack(w,hero);
  }
  for(const u of [...w.units])if(u.alive && u.ctrl==='ai'){
    if(u.team==='party')allyThink(w,u,dt);
    else if(u.brain==='raid')raidThink(w,u,dt);
    else enemyThink(w,u,dt);
  }
  resolveTelegraphs(w);updateTerrain(w,dt);updateSight(w);
  if(w.visibleEnemies.some(id=>!previousVisible.includes(id))){w.autoPath=[];w.exploring=false;w.resting=false;w.emit('spotted',{});}
  if(!w.autoPath.length && w.exploring)explore(w);
  checkDefeat(w);return true;
}
