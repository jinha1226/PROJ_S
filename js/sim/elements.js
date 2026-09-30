import { B } from '../data/balance.js';
import { cellKey, distance } from '../util/math.js';
import { applyStatus } from './status.js';
import { hurt } from './damage.js';
import { tileAt } from './space.js';
export function changeTile(w,x,y,kind,left=B.statusDuration) {
  const t=tileAt(w,x,y);
  if(t && !['wall','door'].includes(t.kind)){t.kind=kind;t.left=left;w.revision++;}
}
export function element(w,u,kind,source=null,visited=new Set()) {
  if(!u.alive || visited.has(u.id))return;
  visited.add(u.id);
  const t=tileAt(w,u.x,u.y);
  if(kind==='water'){applyStatus(w,u,'wet');changeTile(w,u.x,u.y,'water');return;}
  if(kind==='poison'){applyStatus(w,u,'poison');return;}
  if(kind==='ice'){
    applyStatus(w,u,'frozen',u.statuses.wet?B.wetFreeze:B.freeze);
    if(t?.kind==='water')changeTile(w,u.x,u.y,'ice');
  }
  if(kind==='lightning'){
    hurt(w,u,B.chainDamage,source,kind);
    if(u.statuses.wet || t?.kind==='water')for(const other of w.units){
      if(other.alive && !visited.has(other.id) && distance(u,other)<=B.chainRadius && (other.statuses.wet || tileAt(w,other.x,other.y)?.kind==='water')) {
        w.emit('chained',{x:u.x,y:u.y,toX:other.x,toY:other.y,element:kind});element(w,other,kind,source,visited);
      }
    }
  }
  if(kind==='fire'){
    if(u.statuses.frozen){delete u.statuses.frozen;w.emit('burst',{x:u.x,y:u.y,element:'steam'});}
    const explodes=u.statuses.poison || t?.kind==='oil';
    delete u.statuses.poison;
    applyStatus(w,u,'burn');
    if(explodes){
      w.emit('burst',{x:u.x,y:u.y,element:'fire'});changeTile(w,u.x,u.y,'fire');
      for(const other of w.units)if(other.alive && distance(u,other)<=B.burstRadius)hurt(w,other,B.burstDamage,source,'fire');
    }
    if(t?.kind==='grass' || t?.kind==='oil')changeTile(w,u.x,u.y,'fire');
  }
  w.emit('burst',{x:u.x,y:u.y,element:kind});
}
export function terrainEffects(w,u,dt) {
  const t=tileAt(w,u.x,u.y);if(!t)return;
  const waterwalk=Object.values(u.gear).some(g=>g.ego==='waterwalk');
  if(t.kind==='water' && !waterwalk)u.statuses.wet={left:B.statusDuration,pulse:1};
  if(t.kind==='fire' && !u.statuses.burn)applyStatus(w,u,'burn');
  if(t.kind==='ice'){u.slide.x=Math.cos(u.facing)*u.speed*dt*0.35;u.slide.y=Math.sin(u.facing)*u.speed*dt*0.35;}
  else u.slide={x:0,y:0};
}
export function updateTerrain(w,dt) {
  const spread=[];
  for(const t of Object.values(w.tiles)){
    if(t.left!==undefined){t.left-=dt;if(t.left<=0){t.kind=t.kind==='ice'?'water':'floor';delete t.left;w.revision++;}}
    if(t.kind==='fire' && w.rng()<dt)for(const [dx,dy]of [[1,0],[-1,0],[0,1],[0,-1]]){const n=w.tiles[cellKey(t.x+dx,t.y+dy)];if(n?.kind==='grass')spread.push(n);}
  }
  for(const t of spread)changeTile(w,t.x,t.y,'fire');
}
