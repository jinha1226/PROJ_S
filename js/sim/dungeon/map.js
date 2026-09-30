import { B } from '../../data/balance.js';
import { FLOORS } from '../../data/terrain.js';
import { NAMES } from '../../data/lines.js';
import { cellKey } from '../../util/math.js';
import { createUnit } from '../unit.js';
export function generateFloor(w) {
  w.tiles={};w.telegraphs=[];w.loot=[];w.lamps=[];w.explored=new Set();w.revision++;
  const size=B.mapSize;
  for(let y=0;y<size;y++)for(let x=0;x<size;x++)w.tiles[cellKey(x,y)]={x,y,kind:'wall'};
  const carve=(x,y,kind='floor')=>{if(x>0 && y>0 && x<size-1 && y<size-1)w.tiles[cellKey(x,y)].kind=kind;};
  const rooms=[{x:1,y:1},{x:9,y:1},{x:9,y:9},{x:1,y:9},{x:9,y:17}];
  for(const r of rooms)for(let y=r.y;y<Math.min(size-1,r.y+B.roomSize);y++)for(let x=r.x;x<r.x+B.roomSize;x++)carve(x,y);
  for(let x=4;x<=12;x++)carve(x,4);
  for(let y=4;y<=20;y++)carve(12,y);
  for(let x=4;x<=12;x++)carve(x,12);
  carve(8,4,'door');carve(12,8,'door');carve(8,12,'door');carve(12,16,'door');
  const def=FLOORS[w.floor-1];
  for(const r of rooms.slice(1))for(let i=0;i<5;i++)carve(r.x+w.rng.int(1,5),Math.min(size-2,r.y+w.rng.int(1,4)),def.terrain);
  if(w.floor===3)for(const [x,y]of [[11,11],[14,11],[11,14],[14,14]])carve(x,y,'wall');
  // Secret alcove, connected through an opaque door.
  for(let y=2;y<6;y++)for(let x=17;x<21;x++)carve(x,y);
  carve(16,4,'door');w.secret={x:19.5,y:3.5};
  w.exit={x:13.5,y:20.5};
  for(const u of w.units.filter(u=>u.team==='party')){u.x=3.5+(u.ctrl==='ai'?w.units.indexOf(u)*0.65:0);u.y=3.5;u.prevX=u.x;u.prevY=u.y;u.windup=null;}
  w.units=w.units.filter(u=>u.team==='party');
  const count=w.tutorial?2:3+w.floor;
  for(let i=0;i<count;i++){
    const r=rooms[1+i%(rooms.length-1)];
    const kind=w.tutorial?'goblin':w.rng.pick(def.types);
    const u=createUnit(`u${w.nextId++}`,{kind,x:r.x+1.5+(i%3),y:Math.min(size-2,r.y+2.5)});
    const scale=1+(w.units.filter(u=>u.team==='party').length-1)*B.partyScale;
    u.hp*=scale;u.maxHP=u.hp;w.units.push(u);
  }
  if(!w.tutorial && w.floor===B.floorCount){
    const kind=w.raid?'keeper':'chief';
    const boss=createUnit(`u${w.nextId++}`,{kind,x:12.5,y:19.5});
    boss.radius=0.5;boss.hp*=w.raid?1:1+(w.units.filter(u=>u.team==='party').length-1)*B.partyScale;boss.maxHP=boss.hp;w.units.push(boss);
  }
  w.lamps=[{x:5.5,y:5.5,name:NAMES[(w.region+w.floor)%NAMES.length],used:false},{x:4.5,y:12.5,name:NAMES[(w.floor+3)%NAMES.length],used:false}];
  if(w.tutorial){w.rescue={x:13.5,y:20.5,name:NAMES[0]};w.exit=w.rescue;}
  w.emit('entered',{floor:w.floor,tutorial:w.tutorial});
}
export function descend(w) {
  if(w.floor>=B.floorCount || w.tutorial)return false;
  w.floor++;w.autoPath=[];w.exploring=false;generateFloor(w);return true;
}
