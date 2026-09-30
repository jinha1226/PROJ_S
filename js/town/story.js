import { B } from '../data/balance.js';
import { VISITORS } from '../data/lines.js';
import { seeded } from '../util/rng.js';
import { tickResidents, recruit } from './residents.js';
export function tickTown(m,dt) {
  if(m.ending==='dark')return;
  m.time+=dt;m.clock+=dt;tickResidents(m,dt);
  while(m.clock>=B.townDay){
    m.clock-=B.townDay;m.day++;
    for(const r of m.residents){r.injury=Math.max(0,r.injury-1);if((m.day-1)%B.monthDays+1===r.birthday)m.events.push({type:'birthday',name:r.name});}
    for(const g of m.graves)if((m.day-g.day)%B.monthDays===0)m.events.push({type:'remembered',name:g.name});
    if(!m.visitor && m.day-m.visitorDay>=B.visitorDays){m.visitor=structuredClone(VISITORS[Math.floor(m.day/B.visitorDays)%VISITORS.length]);m.visitorDay=m.day;m.events.push({type:'visited',name:m.visitor.name});}
  }
  const rooms=m.rooms.filter(r=>r.kind!=='empty').length;
  m.mood=m.residents.length?m.residents.reduce((sum,r)=>sum+r.mood,0)/m.residents.length:60;
  m.light=B.baseLight+m.memories.length*B.memoryLight+rooms*0.35+Math.max(0,m.mood-50)*B.moodLight+m.cleared.length*0.7;
}
export function acceptVisitor(m,accept) {
  if(!m.visitor)return false;
  const v=m.visitor;
  if(accept && m.resources[v.request]<v.amount)return false;
  if(accept){m.resources[v.request]-=v.amount;recruit(m);}
  m.visitor=null;return true;
}
export function remember(m,name) {
  if(!m.memories.includes(name)){m.memories.push(name);m.events.push({type:'remembered',name});}
}
export function returnFrom(m,w) {
  // Town clock is advanced by app on simulation ticks; it never uses wall-clock time.
  for(const name of w.memories)remember(m,name);
  const hero=w.units.find(u=>u.ctrl==='player');
  const allies=w.units.filter(u=>u.team==='party' && u.ctrl==='ai');
  for(const u of allies){
    const r=m.residents.find(r=>r.id===u.residentId);if(!r)continue;
    if(!u.alive)r.injury=B.injuryDays;
    if(w.won){r.mood=Math.min(100,r.mood+5);m.events.push({type:'returned',name:r.name});}
  }
  m.expedition=[];
  if(w.tutorial && w.won && !m.tutorialDone){m.tutorialDone=true;recruit(m,w.rescue.name);}
  if(w.won && !w.tutorial){
    if(!m.cleared.includes(w.region)){m.cleared.push(w.region);if(!w.raid){recruit(m);recruit(m);}}
    m.resources.material+=w.raid?8:3;
    m.events.push({type:'offered'});
    if(w.raid){m.ending='dawn';m.events.push({type:'dawn'});}
  }
  if(hero.alive || (w.won && allies.some(u=>u.alive))){
    m.warehouse=[...hero.inventory,...Object.values(hero.gear)].filter(Boolean);
    if(w.won)m.resources.food+=4;
    return 'town';
  }
  m.warehouse=[];
  m.graves.push({name:m.heroName,generation:m.generation,day:m.day});
  m.events.push({type:'buried',name:m.heroName});
  if(!m.residents.length){m.ending='dark';return 'dark';}
  return 'succession';
}
export function volunteers(m) {
  const rng=seeded(m.seed+m.generation);
  return [...m.residents].sort((a,b)=>(b.mood+b.traits[2]*20)-(a.mood+a.traits[2]*20)).slice(0,rng.int(2,3));
}
export function succeed(m,id) {
  const r=m.residents.find(r=>r.id===id);if(!r)return false;
  m.heroName=r.name;m.heroTrait=r.stance==='aggressive'?'brave':'careful';m.generation++;
  m.residents=m.residents.filter(v=>v!==r);m.selected=m.selected.filter(v=>v!==id);m.events.push({type:'succeeded',name:r.name});return true;
}
