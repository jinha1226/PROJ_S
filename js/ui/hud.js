import { B } from '../data/balance.js';
import { ITEMS } from '../data/items.js';
import { FLOORS, REGIONS, TERRAIN } from '../data/terrain.js';
import { ROLES, SKILLS, COMMANDS } from '../data/roles.js';
import { distance, cellKey } from '../util/math.js';
import { jo } from '../util/text.js';
import { setCommand } from '../sim/party.js';
import { cast } from '../sim/roles.js';
import { useItem, pickLoot } from '../sim/items.js';
import { lightLamp } from '../sim/torch.js';
import { descend } from '../sim/dungeon/map.js';
import { openDoor } from '../sim/world.js';
import { $, button, escape, notice } from './dom.js';
const icons={heal:'♥',antidote:'✚',haste:'➟',teleport:'✧',fear:'◉',flame:'♨',water:'◈',oil:'◆',smoke:'☁',frost:'❄',spark:'ϟ',poison:'☘',identify:'▤',enhance:'⚒'};
const statuses={wet:'젖음',frozen:'빙결',burn:'화상',poison:'중독',bleed:'출혈',fracture:'골절',mark:'급소',haste:'가속',guarded:'보호',fear:'공포'};
export class HUD {
  constructor(app){this.app=app;this.logs=[];this.signature='';}
  log(line){if(!line)return;this.logs.push(line);this.logs=this.logs.slice(-3);$('log').innerHTML=this.logs.map(l=>`<div>${escape(l)}</div>`).join('');}
  events(events){
    const w=this.app.world;
    for(const e of events){
      const u=w?.units.find(u=>u.id===e.unit);
      const lines={lit:`${e.name}의 불씨를 이었다.`,entered:`${e.floor}층에 내려섰다.`,picked:'장비를 주웠다.',leveled:`${e.level}레벨이 되었다.`,killed:u?`${jo(u.name)} 쓰러졌다.`:null,heroDied:'등불이 땅에 떨어졌다.',used:ITEMS[e.item]?`${ITEMS[e.item].name}을 썼다.`:null,
        whiff:u?.team==='foe'?'칼끝이 허공을 갈랐다.':null,cleared:'등불 조각을 되찾았다.',arrived:`${jo(e.name||'사람')} 찾아왔다.`,buried:`${e.name}의 이름을 새겼다.`,remembered:`${e.name}을 기억했다.`,built:'청사진이 집이 되었다.',offered:'불빛이 어둠을 밀어냈다.',dawn:'먼 하늘이 밝아졌다.',visited:`${jo(e.name||'방문자')} 불가에 섰다.`,birthday:`${e.name}의 생일이다.`,bonded:`${e.name}과 ${e.other}가 웃었다.`,argued:`${e.name}과 ${e.other}가 다퉜다.`,mechanic:{spread:'발밑에 어둠이 고인다.',stack:'한 사람에게 빛이 모인다.',slam:'파수꾼이 팔을 들었다.',adds:'벽 틈이 빛난다.',shift:'파수꾼의 빛이 바뀐다.'}[e.kind]};
      if(lines[e.type])this.log(lines[e.type]);
      if(e.type==='hit' && e.x!==undefined){const p=this.app.renderer.project(e.x,e.y);const el=document.createElement('span');el.className='damage-number';el.textContent=e.amount;el.style.cssText=`left:${p.x}px;top:${p.y}px`;if(e.element)el.style.color='#bcdffa';$('floaters').append(el);el.addEventListener('animationend',()=>el.remove());}
    }
  }
  frame(){
    const app=this.app,w=app.world,m=app.meta,hero=w?.units.find(u=>u.ctrl==='player');
    if(app.mode==='dungeon'){
      $('location').innerHTML=`${w.tutorial?'첫 불빛':escape(REGIONS[w.region])} · ${w.floor}층<small>${escape(FLOORS[w.floor-1].name)} / ${Math.floor(w.time)}초 · 적 ${w.visibleEnemies.length}</small>`;
      $('torch').innerHTML=`♨ ${Math.ceil(w.torch)}<div class="torchbar"><i style="width:${w.torch/B.torch*100}%"></i></div>`;
      $('health').innerHTML=`<span>♥ ${Math.ceil(hero.hp)} / ${hero.maxHP}</span><div class="hp"><i style="width:${hero.hp/hero.maxHP*100}%"></i></div><span class="states">${Object.keys(hero.statuses).map(k=>statuses[k]).join(' · ')}</span>`;
      $('party').innerHTML=w.units.filter(u=>u.team==='party' && u.ctrl==='ai').map(u=>`<div class="portrait" style="border-color:${ROLES[u.role].color}"><strong>${escape(u.name)}</strong>${ROLES[u.role].name} ${u.alive?'':'· 쓰러짐'}<div class="hp"><i style="width:${u.hp/u.maxHP*100}%"></i></div></div>`).join('');
      const boss=w.units.find(u=>['chief','keeper'].includes(u.kind));
      $('boss').innerHTML=boss?`${escape(boss.name)} · ${boss.phase||1}단계 ${w.raid?`/ ${Math.ceil(w.raidLeft)}초`:''}<div class="hp"><i style="width:${boss.hp/boss.maxHP*100}%"></i></div>`:'';
      this.minimap(w,hero);
      this.dungeonButtons(w,hero);
    }else{
      $('location').innerHTML=`불가 · ${m.generation}대<small>${Math.floor((m.day-1)/B.monthDays)+1}월 ${(m.day-1)%B.monthDays+1}일 · 주민 ${m.residents.length}명</small>`;
      $('torch').textContent=`✦ ${m.light.toFixed(1)}`;
      $('health').innerHTML=`<span>나무 ${m.resources.wood} · 돌 ${m.resources.stone} · 식량 ${m.resources.food} · 조각 ${m.resources.material}</span>`;
      $('party').replaceChildren();$('boss').replaceChildren();$('items').replaceChildren();$('skills').replaceChildren();if(!app.buildMode)$('context').replaceChildren();
      const sig=`town:${app.buildMode||''}`;if(sig!==this.signature){this.signature=sig;$('actions').replaceChildren(button('주민',()=>app.residents()),button('건설',()=>app.build()),button('기억',()=>app.memory()),button('달력',()=>app.calendar()),button('원정',()=>app.missions(),{className:'primary'}));}
      const ctx=$('minimap').getContext('2d');ctx.clearRect(0,0,80,80);ctx.fillStyle='#d8b478';ctx.beginPath();ctx.arc(40,40,m.light*3,0,Math.PI*2);ctx.strokeStyle='#dfc58b';ctx.stroke();ctx.fillRect(38,38,4,4);for(const b of m.buildings){ctx.fillStyle='#a6be9f';ctx.fillRect(b.x*3+9,b.y*3+9,2,2);}
    }
  }
  dungeonButtons(w,hero){
    const sig=`dungeon:${JSON.stringify(w.items)}:${JSON.stringify(Object.fromEntries(Object.entries(hero.cooldowns).map(([k,v])=>[k,Math.ceil(v)])))}:${hero.role}:${w.units.filter(u=>u.team==='party').length}:${this.app.selectedItem}:${w.command}`;
    if(sig!==this.signature){this.signature=sig;
      $('items').replaceChildren(...Object.entries(w.items).filter(([,n])=>n>0).map(([key,n])=>{
        const item=ITEMS[key],b=button('',()=>{
          if(['throw','scroll'].includes(item.kind) && !['teleport','fear'].includes(key)){this.app.selectedItem=this.app.selectedItem===key?null:key;notice(w.identified[key]?item.name:item.appearance);}
          else useItem(w,hero,key,hero);
        });b.innerHTML=`${icons[key]}<b>${n}</b>`;b.title=w.identified[key]?item.name:item.appearance;b.setAttribute('aria-label',b.title);if(this.app.selectedItem===key)b.classList.add('active');return b;
      }));
      $('skills').replaceChildren(...(ROLES[hero.role]?.skills||[]).map(key=>button(`${SKILLS[key].name}${hero.cooldowns[key]>0?' '+Math.ceil(hero.cooldowns[key])+'초':''}`,()=>cast(w,hero,key),{disabled:hero.cooldowns[key]>0})));
      $('actions').replaceChildren(button('무기',()=>this.app.inventory()),button('쉬기',()=>this.app.rest()),button('탐험',()=>this.app.explore()),button('상태',()=>this.app.status()),button('가방',()=>this.app.inventory()),button('귀환',()=>this.app.return()));
      if(w.units.filter(u=>u.team==='party').length>1){const row=document.createElement('div');row.id='commands';for(const [key,label]of Object.entries(COMMANDS))row.append(button(label,()=>setCommand(w,key),{className:w.command===key?'active':''}));$('skills').append(row);}
    }
    const nearby=w.lamps.find(l=>!l.used && distance(hero,l)<1.5),door=Object.values(w.tiles).find(t=>t.kind==='door' && !t.open && distance(hero,{x:t.x+0.5,y:t.y+0.5})<1.8);
    const key=[nearby?.name,door?.x,door?.y,distance(hero,w.exit)<1.5,w.loot.some(i=>distance(hero,i)<1.5),w.won].join(':');
    if(key===this.contextSig)return;this.contextSig=key;const buttons=[];
    if(nearby)buttons.push(button('불씨 잇기',()=>lightLamp(w,nearby)));
    if(door)buttons.push(button('문 열기',()=>openDoor(w,door.x,door.y)));
    if(w.loot.some(i=>distance(hero,i)<1.5))buttons.push(button('줍기',()=>pickLoot(w,hero)));
    if(distance(hero,w.exit)<1.5){if(w.tutorial)buttons.push(button('구하기',()=>{w.won=true;this.app.return();}));else if(w.floor<B.floorCount)buttons.push(button('내려가기',()=>descend(w)));}
    if(w.won)buttons.push(button('불가로',()=>this.app.return()));$('context').replaceChildren(...buttons);
  }
  minimap(w,hero){const ctx=$('minimap').getContext('2d');ctx.clearRect(0,0,80,80);for(const t of Object.values(w.tiles)){if(!w.explored.has(cellKey(t.x,t.y)))continue;ctx.fillStyle=TERRAIN[t.kind].color;ctx.fillRect(t.x*3+5,t.y*3+5,2.7,2.7);}ctx.fillStyle='#ffe7a3';ctx.fillRect(hero.x*3+4,hero.y*3+4,3,3);}
}
