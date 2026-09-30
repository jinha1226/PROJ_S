import { B } from '../data/balance.js';
import { BUILD, PRESETS } from '../data/build.js';
import { cellKey, distance } from '../util/math.js';
const center=()=>({x:Math.floor(B.townSize/2),y:Math.floor(B.townSize/2)});
export function costOf(plan) {
  return plan.reduce((sum,b)=>({wood:sum.wood+BUILD[b.kind].wood,stone:sum.stone+BUILD[b.kind].stone}),{wood:0,stone:0});
}
export function validatePlan(m,plan) {
  const occupied=new Set([...m.buildings,...m.blueprints].map(b=>cellKey(b.x,b.y)));
  const cost=costOf(plan);
  for(const p of plan){
    if(p.x<0 || p.y<0 || p.x>=B.townSize || p.y>=B.townSize)return {ok:false,reason:'bounds',cost};
    if(distance(center(),p)>m.light)return {ok:false,reason:'darkness',cost};
    if(distance(center(),p)<1.2)return {ok:false,reason:'fire',cost};
    if(occupied.has(cellKey(p.x,p.y)))return {ok:false,reason:'occupied',cost};
    occupied.add(cellKey(p.x,p.y));
  }
  if(cost.wood>m.resources.wood || cost.stone>m.resources.stone)return {ok:false,reason:'cost',cost};
  return {ok:true,cost};
}
export function placePlan(m,plan) {
  const verdict=validatePlan(m,plan);if(!verdict.ok)return verdict;
  m.undo.push({buildings:structuredClone(m.buildings),blueprints:structuredClone(m.blueprints),resources:{...m.resources}});
  m.resources.wood-=verdict.cost.wood;m.resources.stone-=verdict.cost.stone;
  m.blueprints.push(...plan.map(p=>({...p,id:`b${m.nextId++}`,work:0})));
  m.revision++;m.events.push({type:'planned'});return verdict;
}
export function undo(m) {
  const before=m.undo.pop();if(!before)return false;
  Object.assign(m,before);m.revision++;recognizeRooms(m);return true;
}
export function rectangle(a,b,furniture=[]) {
  const plan=[];const loX=Math.min(a.x,b.x),hiX=Math.max(a.x,b.x),loY=Math.min(a.y,b.y),hiY=Math.max(a.y,b.y);
  if(hiX-loX<2 || hiY-loY<2)return plan;
  for(let y=loY;y<=hiY;y++)for(let x=loX;x<=hiX;x++){
    let kind=(x===loX || x===hiX || y===loY || y===hiY)?'wall':'floor';
    if(y===hiY && x===loX+1)kind='door';
    const f=furniture.find(f=>f.x+loX===x && f.y+loY===y);if(f)kind=f.kind;
    plan.push({x,y,kind});
  }
  return plan;
}
export function presetPlan(kind,x,y,rotation=0) {
  let plan=rectangle({x:0,y:0},{x:3,y:3},PRESETS[kind].furniture);
  for(let i=0;i<rotation;i++)plan=plan.map(p=>({...p,x:3-p.y,y:p.x}));
  return plan.map(p=>({...p,x:x+p.x,y:y+p.y}));
}
export function recommend(m,kind) {
  for(let y=0;y<B.townSize-3;y++)for(let x=0;x<B.townSize-3;x++){
    const plan=presetPlan(kind,x,y);if(validatePlan(m,plan).ok)return plan;
  }
  return null;
}
export function autoBuild(m) {
  const needed=!m.buildings.some(b=>b.kind==='bed')?'lodging':!m.buildings.some(b=>b.kind==='anvil')?'smith':'dining';
  const plan=recommend(m,needed);return plan?placePlan(m,plan):{ok:false,reason:'cost'};
}
export function copyRoom(m,room,x,y,rotation=0) {
  const buildings=m.buildings.filter(b=>room.cells.includes(cellKey(b.x,b.y)) || room.boundary.includes(cellKey(b.x,b.y)));
  const loX=Math.min(...buildings.map(b=>b.x)),loY=Math.min(...buildings.map(b=>b.y));
  let plan=buildings.map(b=>({x:b.x-loX,y:b.y-loY,kind:b.kind}));
  const width=Math.max(...plan.map(p=>p.x));
  for(let i=0;i<rotation;i++)plan=plan.map(p=>({...p,x:width-p.y,y:p.x}));
  return plan.map(p=>({...p,x:p.x+x,y:p.y+y}));
}
export function recognizeRooms(m) {
  const byCell=new Map(m.buildings.map(b=>[cellKey(b.x,b.y),b]));
  const seen=new Set(),rooms=[];
  for(const b of m.buildings){
    const key=cellKey(b.x,b.y);if(seen.has(key)||['wall','door','farm','training'].includes(b.kind))continue;
    const queue=[key],cells=[],boundary=new Set();let enclosed=true;
    seen.add(key);
    for(let i=0;i<queue.length;i++){
      const k=queue[i];cells.push(k);const [x,y]=k.split(',').map(Number);
      for(const [dx,dy]of [[1,0],[-1,0],[0,1],[0,-1]]){
        const n=cellKey(x+dx,y+dy),tile=byCell.get(n);
        if(!tile){enclosed=false;continue;}
        if(['wall','door'].includes(tile.kind)){boundary.add(n);continue;}
        if(!seen.has(n)){seen.add(n);queue.push(n);}
      }
    }
    if(enclosed){const kinds=cells.map(k=>byCell.get(k).kind);let kind=kinds.includes('bed')?'lodging':kinds.includes('anvil')?'smith':kinds.includes('stove')&&kinds.includes('table')?'dining':'empty';rooms.push({id:key,cells,boundary:[...boundary],kind,score:cells.length+kinds.filter(k=>k!=='floor').length*2});}
  }
  m.rooms=rooms;return rooms;
}
