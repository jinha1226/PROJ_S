import test from 'node:test';import assert from 'node:assert/strict';
import { newMeta, encode, decode } from '../../js/town/meta.js';
import { recruit, chooseCompanions, tickResidents } from '../../js/town/residents.js';
import { returnFrom, succeed, volunteers, tickTown, acceptVisitor } from '../../js/town/story.js';
import { placePlan, presetPlan, recognizeRooms, undo, validatePlan, autoBuild } from '../../js/town/settlement.js';
import { createWorld } from '../../js/sim/world.js';
import { B } from '../../js/data/balance.js';
test('처음 마을의 불빛 안에 숙소 청사진을 자동으로 놓을 수 있다',()=>{
  const m=newMeta();
  const before={...m.resources};
  const result=autoBuild(m);
  assert.equal(result.ok,true);
  assert.ok(m.blueprints.some(b=>b.kind==='bed'));
  assert.ok(m.resources.wood<before.wood);
  for(const b of m.blueprints){
    assert.ok(Math.hypot(b.x-10,b.y-10)<=m.light);
    assert.ok(Math.hypot(b.x-10,b.y-10)>=1.2);
  }
});
test('튜토리얼에서 구한 사람이 첫 주민이 된다',()=>{const m=newMeta(),w=createWorld({tutorial:true});w.won=true;assert.equal(returnFrom(m,w),'town');assert.equal(m.residents.length,1);assert.ok(m.tutorialDone);returnFrom(m,w);assert.equal(m.residents.length,1);});
test('빛 밖 건설과 비용 부족은 자원을 소비하지 않는다',()=>{const m=newMeta(),before={...m.resources};assert.equal(placePlan(m,[{x:0,y:0,kind:'wall'}]).reason,'darkness');assert.deepEqual(m.resources,before);m.resources.wood=0;assert.equal(placePlan(m,[{x:12,y:10,kind:'bed'}]).reason,'cost');});
test('숙소 청사진은 주민이 완성하고 폐쇄된 방으로 인식된다',()=>{const m=newMeta();m.light=20;recruit(m);const plan=presetPlan('lodging',12,7);assert.ok(placePlan(m,plan).ok);for(let i=0;i<200;i++)tickTown(m,0.5);assert.equal(m.blueprints.length,0);assert.ok(m.rooms.some(r=>r.kind==='lodging'));m.buildings=m.buildings.filter(b=>!(b.x===12&&b.y===8));recognizeRooms(m);assert.equal(m.rooms.length,0);});
test('건설 되돌리기는 청사진과 자원을 되돌린다',()=>{const m=newMeta(),before={...m.resources};placePlan(m,[{x:12,y:10,kind:'bed'}]);assert.ok(undo(m));assert.equal(m.blueprints.length,0);assert.deepEqual(m.resources,before);});
test('훈련장과 열린 자리 없이는 동료를 선택할 수 없다',()=>{const m=newMeta(),r=recruit(m);assert.equal(chooseCompanions(m,[r.id]),false);m.buildings.push({kind:'training',x:12,y:10});m.cleared=[0];assert.ok(chooseCompanions(m,[r.id]));r.injury=1;assert.equal(chooseCompanions(m,[r.id]),false);});
test('원정 중인 주민은 마을 일을 하지 않는다',()=>{const m=newMeta(),r=recruit(m);m.expedition=[r.id];const before=r.progress;tickTown(m,4);assert.equal(r.progress,before);});
test('모두 쓰러지면 유품을 잃고 비석과 다음 등불지기가 남는다',()=>{const m=newMeta(),r=recruit(m),w=createWorld();w.units[0].alive=false;assert.equal(returnFrom(m,w),'succession');assert.equal(m.warehouse.length,0);assert.equal(m.graves.length,1);assert.ok(succeed(m,r.id));assert.equal(m.generation,2);assert.equal(m.heroName,r.name);assert.equal(m.residents.length,0);});
test('남은 주민이 없으면 불이 꺼진다',()=>{const m=newMeta(),w=createWorld();w.units[0].alive=false;assert.equal(returnFrom(m,w),'dark');assert.equal(m.ending,'dark');});
test('동료가 이기면 등불지기를 업고 돌아오고 쓰러진 주민은 쉰다',()=>{const m=newMeta(),r=recruit(m),w=createWorld({companions:[r]});w.units[0].alive=false;w.won=true;assert.equal(returnFrom(m,w),'town');assert.equal(m.graves.length,0);w.won=false;w.units[1].alive=false;returnFrom(m,w);assert.equal(r.injury,B.injuryDays);});
test('네 구역 후 다섯 명이 출발할 수 있고 레이드는 새벽을 연다',()=>{const m=newMeta();m.tutorialDone=true;for(let region=0;region<4;region++){const w=createWorld({region});w.won=true;returnFrom(m,w);}m.buildings.push({kind:'training'});assert.ok(chooseCompanions(m,m.residents.slice(0,4).map(r=>r.id)));const w=createWorld({region:4,raid:true,companions:m.residents.slice(0,4)});assert.equal(w.units.filter(u=>u.team==='party').length,5);w.won=true;returnFrom(m,w);assert.equal(m.ending,'dawn');assert.ok(m.resources.material>=8);});
test('저장 왕복은 정착지와 기억만 보존하고 깨진 저장을 복구한다',()=>{const m=newMeta();recruit(m);m.memories=['old'];m.expedition=['r1'];m.events.push({type:'test'});const restored=decode(encode(m));assert.deepEqual(restored.memories,m.memories);assert.equal(restored.residents.length,1);assert.equal(restored.expedition.length,0);assert.equal(restored.events.length,0);assert.equal(decode('{broken').version,1);});
test('농작물은 빛 밖에서 자라지 않으며 방문자는 자원을 받고 합류한다',()=>{const m=newMeta();m.buildings.push({kind:'farm',x:0,y:0,growth:0});tickTown(m,B.cropTime*2);assert.equal(m.buildings[0].growth,0);m.visitor={request:'food',amount:2};assert.ok(acceptVisitor(m,true));assert.equal(m.residents.length,1);});
