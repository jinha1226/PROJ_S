import { B } from '../data/balance.js';
import { ROLES } from '../data/roles.js';
import { PERSONALITIES, TRAITS } from '../data/lines.js';
import { ROOM_NAMES } from '../data/build.js';
import { chooseCompanions, setRole, setStance } from '../town/residents.js';
import { acceptVisitor, volunteers, succeed } from '../town/story.js';
import { partyCapacity } from '../sim/party.js';
import { openPanel, html, button, escape, notice, $ } from './dom.js';
export function residents(app) {
  const m=app.meta,body=openPanel('불가의 사람들');
  html(body,`<p class="muted">${m.residents.length}명 · 불빛 ${m.light.toFixed(1)} · 함께 갈 자리 ${partyCapacity(m)-1}</p>`);
  for(const r of m.residents){
    const card=html(body,`<div class="resident-card"><strong>${escape(r.name)}</strong> <span class="muted">${escape(r.personality)} · ${r.injury>0?`${r.injury}일 휴식`:'기분 '+Math.floor(r.mood)}</span><p>“${escape(r.line)}”</p><div class="row"><label><input type="checkbox" ${m.selected.includes(r.id)?'checked':''} ${r.injury>0?'disabled':''}> 함께 가기</label></div><small class="muted">${TRAITS.map((t,i)=>`${t} ${Math.round(r.traits[i]*100)}`).join(' · ')}</small></div>`).firstChild;
    card.querySelector('input').addEventListener('change',e=>{const ids=e.target.checked?[...m.selected,r.id]:m.selected.filter(id=>id!==r.id);if(!chooseCompanions(m,ids)){e.target.checked=!e.target.checked;notice(m.buildings.some(b=>b.kind==='training')?'함께 갈 자리가 부족합니다':'훈련장이 필요합니다');}app.save();});
    const role=document.createElement('select');role.setAttribute('aria-label',r.name+' 역할');
    for(const [key,def]of Object.entries(ROLES)){const opt=new Option(def.name,key);opt.disabled=def.unlock>Math.max(1,m.cleared.length);opt.selected=r.role===key;role.add(opt);}
    role.addEventListener('change',()=>{setRole(m,r.id,role.value);app.save();});
    const stance=document.createElement('select');stance.setAttribute('aria-label',r.name+' 성향');
    for(const [key,label]of Object.entries({aggressive:'공격적',careful:'신중',support:'지원'})){const opt=new Option(label,key);opt.selected=r.stance===key;stance.add(opt);}
    stance.addEventListener('change',()=>{setStance(m,r.id,stance.value);app.save();});card.querySelector('.row').append(role,stance);
  }
  if(m.visitor){const row=html(body,`<div class="resident-card"><strong>${escape(m.visitor.name)}</strong><p>${escape(m.visitor.line)}</p><p class="muted">${m.visitor.request==='food'?'식량':'나무'} ${m.visitor.amount}</p></div>`).firstChild;row.append(button('맞이하기',()=>{if(!acceptVisitor(m,true))notice('나눌 것이 모자랍니다');residents(app);}),button('보내기',()=>{acceptVisitor(m,false);residents(app);}));}
}
export function memory(app) {
  const m=app.meta,body=openPanel('기억할 이름들');
  html(body,`<p class="muted">불빛 아래 ${m.memories.length}개의 이름</p>`);
  for(const name of m.memories)html(body,`<div class="row">✦ ${escape(name)}</div>`);
  html(body,'<div class="section-label">돌에 새긴 이름</div>');
  for(const grave of m.graves)html(body,`<div class="row">${grave.generation}대 ${escape(grave.name)}<small>${grave.day}일</small></div>`);
  html(body,'<div class="section-label">함께 남긴 이야기</div>');
  for(const [key,score]of Object.entries(m.relationships)){const names=key.split(':').map(id=>m.residents.find(r=>r.id===id)?.name||m.graves.find(g=>g.id===id)?.name||'옛 친구');html(body,`<div class="row">${escape(names.join(' · '))}<small>${score>=0?'가까움':'서먹함'} ${Math.abs(score)}</small></div>`);}
  for(const room of m.rooms)html(body,`<div class="row">${ROOM_NAMES[room.kind]}<small>${room.score}점</small></div>`);
}
export function calendar(app) {
  const m=app.meta,body=openPanel(`${Math.floor((m.day-1)/B.monthDays)+1}월`),grid=html(body,'<div class="calendar"></div>').firstChild;
  for(let day=1;day<=B.monthDays;day++){
    const names=m.residents.filter(r=>r.birthday===day).map(r=>r.name+' 생일');
    if(day%B.visitorDays===1)names.push('상인');
    for(const g of m.graves)if((g.day-1)%B.monthDays+1===day)names.push(g.name+' 추모');
    html(grid,`<div class="${day===(m.day-1)%B.monthDays+1?'today':''}">${day}<small>${names.map(escape).join('<br>')}</small></div>`);
  }
}
export function succession(app) {
  const body=openPanel('다시 횃불을 들 사람');
  for(const r of volunteers(app.meta)){const row=html(body,`<div class="row"><div>${escape(r.name)}<small>${escape(r.personality)} · ${r.stance==='aggressive'?'씩씩한 발걸음':'신중한 발걸음'}</small></div></div>`).firstChild;row.append(button('불을 잇기',()=>{succeed(app.meta,r.id);$('panel').close();app.showTown();app.save();}));}
  $('close-panel').hidden=true;
}
