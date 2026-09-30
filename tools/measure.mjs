import { mkdir, writeFile } from 'node:fs/promises';
import { createWorld, setInput, openDoor } from '../js/sim/world.js';
import { createUnit } from '../js/sim/unit.js';
import { shapeContains } from '../js/sim/space.js';
import { useItem } from '../js/sim/items.js';
import { B } from '../js/data/balance.js';
const rows=[];
for(const kind of ['goblin','boar','chief']){
  for(let seed=1;seed<=12;seed++){
    const w=createWorld({seed}),h=w.units[0];w.units=[h];w.tiles={};
    for(let y=0;y<16;y++)for(let x=0;x<16;x++)w.tiles[`${x},${y}`]={x,y,kind:x===0||y===0||x===15||y===15?'wall':'floor'};
    h.x=7.5;h.y=7.5;const foe=createUnit('foe',{kind,x:8.5,y:7.5});w.units.push(foe);w.flowing=true;
    let damage=0;
    while(h.alive && foe.alive && w.time<90){
      const danger=w.telegraphs.find(t=>t.team==='foe' && shapeContains(t,h));
      if(danger){const dx=h.x-foe.x,dy=h.y-foe.y,d=Math.hypot(dx,dy)||1;setInput(w,dx/d,dy/d);}
      else {const d=Math.hypot(foe.x-h.x,foe.y-h.y);setInput(w,d>1?(foe.x-h.x)/d:0,d>1?(foe.y-h.y)/d:0);}
      if(h.hp<35 && w.items.heal)useItem(w,h,'heal');
      const hp=h.hp;w.step();damage+=Math.max(0,hp-h.hp);w.drainEvents();
    }
    rows.push({seed,kind,seconds:+w.time.toFixed(2),damage,died:!h.alive,killed:!foe.alive});
  }
}
const summary=['goblin','boar','chief'].map(kind=>{const group=rows.filter(r=>r.kind===kind),mean=key=>group.reduce((n,r)=>n+Number(r[key]),0)/group.length;const target=kind==='chief'?B.bossTarget:B.encounterTarget;return {kind,seconds:+mean('seconds').toFixed(2),damage:+mean('damage').toFixed(2),deathRate:mean('died'),killRate:mean('killed'),target,inTarget:mean('seconds')>=target[0]&&mean('seconds')<=target[1]};});
console.table(summary);await mkdir('test-results',{recursive:true});await writeFile('test-results/measure.json',JSON.stringify({policy:'Approach, retreat out of locked telegraphs, use healing below 35 HP; 12 seeds per encounter.',summary,rows},null,2));
if(summary.some(r=>!r.inTarget))console.warn('Balance target drift recorded in measure.json; measurements are advisory.');
