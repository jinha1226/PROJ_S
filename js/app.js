import { B } from './data/balance.js';
import { REGIONS } from './data/terrain.js';
import { ROLES } from './data/roles.js';
import { weekSeed } from './util/math.js';
import { createWorld, rest, explore } from './sim/world.js';
import { newMeta, decode, encode } from './town/meta.js';
import { tickTown, returnFrom } from './town/story.js';
import { validateAdapter } from './render/adapter.js';
import { Diorama } from './render/diorama/index.js';
import { HUD } from './ui/hud.js';
import { bindInput } from './ui/input.js';
import { inventory } from './ui/inventory.js';
import { residents, memory, calendar, succession } from './ui/town.js';
import { Builder } from './ui/build.js';
import { $, button, openPanel, closePanel, html, escape, notice } from './ui/dom.js';
const SAVE_KEY='last-ember.meta.v1';
function readSave(){try{return localStorage.getItem(SAVE_KEY);}catch{return null;}}
class App {
  constructor(){
    this.meta=decode(readSave());this.mode='title';this.world=null;this.held=false;this.buildMode=null;this.selectedItem=null;this.accumulator=0;
    this.renderer=validateAdapter(new Diorama());this.renderer.mount($('viewport'));this.renderer.setTown(this.meta);
    this.hud=new HUD(this);this.builder=new Builder(this);this.release=bindInput(this);
    $('continue').hidden=!readSave();$('continue').onclick=()=>{if(this.meta.ending==='dark')this.ending('dark');else this.showTown();};
    $('new-game').onclick=()=>this.newGame();$('close-panel').onclick=()=>closePanel();
    $('panel').addEventListener('cancel',e=>{if($('close-panel').hidden)e.preventDefault();});
    $('view').onclick=()=>this.renderer.toggleView();$('zoom-in').onclick=()=>this.renderer.magnify(0.88);$('zoom-out').onclick=()=>this.renderer.magnify(1.12);
    $('menu').onclick=()=>this.menu();window.addEventListener('resize',()=>this.renderer.resize());
    this.last=performance.now();this.savedAt=0;requestAnimationFrame(t=>this.frame(t));
  }
  save(){try{localStorage.setItem(SAVE_KEY,encode(this.meta));}catch{notice('기억을 저장할 공간이 모자랍니다');}}
  newGame(){this.meta=newMeta(Math.floor(Math.random()*1000000));this.showTown();this.save();this.start({tutorial:true});}
  showTown(){this.mode='town';this.world=null;this.held=false;this.selectedItem=null;this.accumulator=0;this.renderer.setTown(this.meta);$('title').hidden=true;$('close-panel').hidden=false;this.hud.signature='';this.hud.events(this.meta.events.splice(0));this.hud.frame();}
  start(options={}){
    this.release();closePanel();this.buildMode=null;this.selectedItem=null;this.meta.expedition=[...this.meta.selected];
    const companions=this.meta.residents.filter(r=>this.meta.selected.includes(r.id) && r.injury<=0);
    this.world=createWorld({seed:options.weekly?weekSeed(new Date()):this.meta.seed+this.meta.day*17+this.meta.generation,
      name:this.meta.heroName,trait:this.meta.heroTrait,region:options.region||0,
      tutorial:!this.meta.tutorialDone && !options.raid,role:this.meta.tutorialDone?(this.meta.heroRole||'guardian'):null,
      stored:this.meta.warehouse,companions,...options});
    this.mode='dungeon';this.accumulator=0;this.renderer.setDungeon(this.world);$('title').hidden=true;this.hud.signature='';this.hud.contextSig='';this.hud.log(this.world.tutorial?'작은 불씨를 품고 내려섰다.':'불빛이 돌길을 비췄다.');
  }
  return(){
    if(!this.world)return;
    this.release();const result=returnFrom(this.meta,this.world),wasRaid=this.world.won&&this.world.raid;
    this.showTown();this.save();
    if(result==='succession')succession(this);
    else if(result==='dark')this.ending('dark');
    else if(wasRaid)this.ending('dawn');
  }
  missions(){
    if(!this.meta.tutorialDone){this.start({tutorial:true});return;}
    const body=openPanel('불빛이 닿지 않는 곳');
    const role=html(body,'<div class="row"><div>등불지기의 역할</div></div>').firstChild;
    const select=document.createElement('select');select.setAttribute('aria-label','등불지기 역할');
    for(const [key,def]of Object.entries(ROLES)){const option=new Option(def.name,key);option.disabled=def.unlock>Math.max(1,this.meta.cleared.length);option.selected=(this.meta.heroRole||'guardian')===key;select.add(option);}
    select.onchange=()=>{this.meta.heroRole=select.value;this.save();};role.append(select);
    for(const [region,name]of REGIONS.entries()){
      const unlocked=region===0||this.meta.cleared.includes(region-1),raid=region===REGIONS.length-1;
      const row=html(body,`<div class="row"><div>${escape(name)}<small>${this.meta.cleared.includes(region)?'되찾은 기억':raid?'다섯 개의 등불':'다섯 층의 어둠'}</small></div></div>`).firstChild;
      const full=this.meta.selected.filter(id=>this.meta.residents.some(r=>r.id===id && r.injury<=0)).length===4;
      row.append(button(raid?'레이드':'내려가기',()=>this.start({region,raid}),{disabled:!unlocked||(raid&&!full)}));
    }
    if(this.meta.ending==='dawn')body.append(button('이번 주의 레이드',()=>this.start({region:4,raid:true,weekly:true}),{disabled:this.meta.selected.length!==4}));
    body.append(button('함께 갈 사람들',()=>this.residents()));
  }
  rest(){if(!rest(this.world))notice('지금은 쉴 수 없습니다');}
  explore(){if(!explore(this.world))notice('눈앞에 위험이 있습니다');}
  inventory(){inventory(this);}
  residents(){residents(this);}
  memory(){memory(this);}
  calendar(){calendar(this);}
  build(){this.builder.menu();}
  buildPointer(...args){this.builder.pointer(...args);}
  status(){const u=this.world.units.find(u=>u.ctrl==='player'),body=openPanel(u.name);
    html(body,`<div class="row">${u.level}레벨<small>경험 ${u.xp}/${u.level*B.xpLevel}</small></div><div class="row">방어 ${u.armor}<small>회피 ${(u.evade*100).toFixed(0)}%</small></div>`);
    for(const [key,label]of Object.entries({fire:'불',ice:'냉기',lightning:'번개',poison:'독'}))html(body,`<div class="row">${label}<span>${u.resist[key]<0?'−':''}${'●'.repeat(Math.abs(u.resist[key]||0))}${'○'.repeat(3-Math.abs(u.resist[key]||0))}</span></div>`);
  }
  ending(kind){const body=openPanel(kind==='dawn'?'새벽':'마지막 어둠');html(body,`<div class="ending"><h3>${kind==='dawn'?'새벽이 왔다':'불이 꺼졌다'}</h3><p>${kind==='dawn'?'불가에 모인 이름들이<br>긴 밤을 건넜다.':'마지막 이름마저<br>어둠 속으로 흩어졌다.'}</p></div>`);body.append(button(kind==='dawn'?'불가로':'다시 불씨 품기',()=>{closePanel();if(kind==='dark')this.newGame();}));$('close-panel').hidden=kind==='dark';}
  menu(){const body=openPanel('마지막 불씨');body.append(button('기억 저장',()=>{this.save();notice('기억을 남겼습니다');}),button('처음으로',()=>{closePanel();this.release();this.mode='title';$('title').hidden=false;}));html(body,'<p class="muted">이동 W A S D · 머무르기 Space<br>화면 아래 손끝으로 걷기 · 두 손끝으로 시점 돌리기</p>');}
  frame(now){
    const dt=Math.min(0.15,(now-this.last)/1000);this.last=now;
    const modal=$('panel').open;
    if(this.mode==='dungeon'){
      const w=this.world;
      w.flowing=!modal&&(this.held||w.autoPath.length>0||w.castLeft>0||w.resting||w.command==='auto');
      if(w.flowing){this.accumulator+=dt;let count=0;while(this.accumulator>=B.tick && count<B.maxTicks){if(w.step())tickTown(this.meta,B.tick);this.accumulator-=B.tick;count++;}if(count===B.maxTicks)this.accumulator=Math.min(this.accumulator,B.tick);}
      else this.accumulator=0;
      this.renderer.setFrozen(!w.flowing);const events=w.drainEvents();this.renderer.onEvents(events);this.hud.events(events);
      this.renderer.frame(w,w.flowing?this.accumulator/B.tick:1,dt);
      if(w.lost){this.return();}
    }else{
      if(this.mode==='town'&&!modal)tickTown(this.meta,dt);
      this.renderer.setFrozen(false);this.renderer.frame(this.meta,1,dt);this.hud.events(this.meta.events.splice(0));
    }
    this.hud.frame();
    if(this.mode==='town' && this.meta.time-this.savedAt>5){this.savedAt=this.meta.time;this.save();}
    requestAnimationFrame(t=>this.frame(t));
  }
}
try{
  const app=new App();
  if(new URLSearchParams(location.search).has('test'))window.__game=app;
}catch(error){$('title').innerHTML='<h1>불빛을 기다리는 중</h1><p>화면을 다시 열어 주세요.</p>';console.error(error);}
