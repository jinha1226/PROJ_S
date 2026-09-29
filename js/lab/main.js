import { Battle, MODES } from './battle.js';
import { LabView } from './view.js';

const $ = (q) => document.querySelector(q);
const $$ = (q) => [...document.querySelectorAll(q)];
const STORE = 'torch-raid-lab-v1';
const safe = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
let battle, saved = false, lastHp = {}, hurtUntil = {}, hudTime = 0, keys = new Set(), joy = { x: 0, y: 0, pointer: null };
const view = new LabView($('#stage'), (point) => battle.direct(point));
view.onHold = (point) => battle.hold(point);

function records() { try { return JSON.parse(localStorage.getItem(STORE) || '[]'); } catch { return []; } }
function writeRecord(r) { try { localStorage.setItem(STORE, JSON.stringify([...records(), r].slice(-50))); } catch { /* private mode */ } }
function launch(mode) {
  if (!MODES[mode]) mode = 'A';
  if (battle) battle.cancelled = true;
  view.reset(); lastHp = {}; hurtUntil = {};
  battle = new Battle(mode, () => { if (battle) render(); });
  battle.onFx = (type, o) => view.fx(type, o, battle);
  view.setSpeed(mode === 'E' ? 0 : 1, true); // E는 멈춘 채로 시작한다
  saved = false; hudTime = 0; keys.clear(); joy.x = joy.y = 0;
  $('#overlay').hidden = true;
  $$('.modebar button').forEach((b) => b.classList.toggle('on', b.dataset.mode === mode));
  $('#joystick').classList.toggle('on', mode === 'C' || mode === 'E');
  $('#app').classList.remove('frozen');
  $('#wait').hidden = mode !== 'A';
  render();
}
function render() {
  if (!battle) return;
  const b = battle;
  view.show(b);
  const t = performance.now();
  for (const u of b.units) { if (lastHp[u.id] !== undefined && u.hp < lastHp[u.id]) hurtUntil[u.id] = t + 260; lastHp[u.id] = u.hp; }
  $('#bosshp').style.width = $('#bosslag').style.width = `${Math.max(0, b.boss.hp / b.boss.max * 100)}%`;
  $('.bossline').classList.toggle('hit', hurtUntil.boss > t);
  $('#bossnum').textContent = `${b.boss.hp}/${b.boss.max}`;
  $('#phase').textContent = `${b.phase}단계`;
  $('#clock').textContent = b.mode === 'A' ? `${b.round}/30R` : `${Math.ceil(90 - b.elapsed)}초${b.mode === 'E' && $('#app').classList.contains('frozen') ? ' · 멈춤' : ''}`;
  $('#warning').textContent = b.tele ? `${b.tele.type === 'cleave' ? '내려치기' : '흩어져라'} ${b.mode === 'A' ? '다음 턴' : `${Math.max(0, b.tele.remaining).toFixed(1)}초`}` : '';
  $('#party').innerHTML = b.party.map((u) => `<div class="member ${u.hp ? '' : 'dead'} ${hurtUntil[u.id] > t ? 'hurt' : ''}" style="--c:${u.color}"><b>${u.name}</b><div class="life"><i style="width:${u.hp / u.max * 100}%"></i></div><small>${u.hp}/${u.max}</small></div>`).join('');
  $('#log').innerHTML = b.events.map((s) => `<div>${safe(s)}</div>`).join('');
  $('#pause').textContent = b.mode === 'A' ? '턴제' : b.mode === 'E' ? '손 떼면 멈춤' : b.paused ? '▶ 재개' : '⏸ 멈춤';
  $('#pause').disabled = b.mode === 'A' || b.mode === 'E';
  $('#speed').textContent = `${b.speed}×`;
  if (b.mode !== 'E') view.setSpeed(b.mode === 'A' ? b.speed : 1); // 턴제 배속은 연출도 같이 빨리 감는다(E는 매 프레임 따로)
  $('#autopause').textContent = `${b.mode === 'D' ? '첫 기믹 멈춤' : '자동 멈춤'} ${b.autoPause ? '켬' : '끔'}`;
  $('#autopause').classList.toggle('off', b.mode !== 'B' && b.mode !== 'D');
  $('#hint').textContent = b.mode === 'A' ? '칸을 탭해 이동하거나 공격한다.' : b.mode === 'B' ? '칸을 탭하면 다음 행동에 움직인다. 멈춘 채 지시할 수 있다.' : b.mode === 'D' ? '칸을 탭하면 바로 걷는다. 누른 채 끌면 그쪽으로 계속 걷는다.' : b.mode === 'E' ? '조이스틱에 손을 대고 있는 동안만 시간이 흐른다. 닿은 적은 저절로 벤다.' : '왼쪽 원을 밀어 움직인다. 적을 탭하면 공격한다.';
  $$('.skills button').forEach((el) => {
    const k = el.dataset.skill, cd = b.cooldowns[k];
    el.classList.toggle('sel', b.skill === k); el.classList.toggle('cool', cd > 0);
    el.querySelector('small').textContent = cd > 0 ? b.mode === 'A' ? `${Math.ceil(cd)}R` : `${cd.toFixed(1)}초` : '';
  });
  $$('.commands button').forEach((el) => el.classList.toggle('on', b.command === el.dataset.command));
  // 결과 창은 마지막 한 방(파수병이 무너지는 느린 장면)을 본 뒤에 연다
  if (b.finished && !saved) { saved = true; setTimeout(() => { if (battle === b) showResult(); }, b.finished === '승리' ? 1500 : 900); }
}
function panel(html) { $('#overlay').innerHTML = `<div class="panel">${html}</div>`; $('#overlay').hidden = false; }
function showResult() {
  const r = battle.record();
  writeRecord(r);
  panel(`<h2>${safe(r.result)}</h2><p>${MODES[r.mode]} · ${r.mode === 'A' ? `${r.round}라운드` : `${r.seconds}초`} · 입력 ${r.inputs}회</p>
    <p>기믹 회피 ${r.dodged} · 피격 ${r.hit} · 쓰러진 동료 ${r.fallen}<br>멈춤 ${r.pauses}회 / ${Math.round(r.pausedSeconds)}초 · 기다린 시간 ${Math.round(r.waitingSeconds)}초</p>
    <div class="scores"><label>재미<select id="fun">${[1,2,3,4,5].map((n) => `<option ${n === 3 ? 'selected' : ''}>${n}</option>`).join('')}</select></label><label>읽힘<select id="readability">${[1,2,3,4,5].map((n) => `<option ${n === 3 ? 'selected' : ''}>${n}</option>`).join('')}</select></label><label>조작 부담<select id="burden">${[1,2,3,4,5].map((n) => `<option ${n === 3 ? 'selected' : ''}>${n}</option>`).join('')}</select></label></div>
    <label>한 줄 메모<textarea id="memo" placeholder="이 방식으로 싸워보니…"></textarea></label>
    <button id="save">평가 저장</button><button id="again">다시 싸우기</button><button id="compare-now">비교 표</button>`);
  $('#save').onclick = () => {
    const rows = records(); if (!rows.length) return;
    Object.assign(rows[rows.length - 1], { fun: Number($('#fun').value), readability: Number($('#readability').value), burden: Number($('#burden').value), memo: $('#memo').value.trim().slice(0, 300) });
    try { localStorage.setItem(STORE, JSON.stringify(rows)); } catch { /* private mode */ }
    $('#save').textContent = '저장됨';
  };
  $('#again').onclick = () => launch(battle.mode);
  $('#compare-now').onclick = compare;
}
function compare() {
  const byMode = Object.fromEntries(['A', 'B', 'C', 'D', 'E'].map((m) => [m, records().filter((r) => r.mode === m).at(-1)]));
  const cell = (m, fn) => byMode[m] ? safe(fn(byMode[m])) : '—';
  const row = (label, fn) => `<tr><td>${label}</td>${['A','B','C','D','E'].map((m) => `<td>${cell(m, fn)}</td>`).join('')}</tr>`;
  panel(`<h2>세 방식 비교</h2><table><thead><tr><th></th><th>A 턴제</th><th>B 격자</th><th>C 자유</th><th>D 액션</th><th>E 반턴제</th></tr></thead><tbody>
    ${row('결과', (r) => r.result)}${row('걸린 시간', (r) => `${r.seconds}초`)}${row('입력', (r) => r.inputs)}${row('멈춤', (r) => r.pauses)}${row('회피 / 피격', (r) => `${r.dodged}/${r.hit}`)}${row('동료 쓰러짐', (r) => r.fallen)}${row('재미', (r) => r.fun || '—')}${row('읽힘', (r) => r.readability || '—')}${row('조작 부담', (r) => r.burden || '—')}
    </tbody></table><p>각 방식의 마지막 기록을 보여준다.</p><button id="close">닫기</button>`);
  $('#close').onclick = () => { $('#overlay').hidden = true; };
}

$$('.modebar button').forEach((el) => el.onclick = () => launch(el.dataset.mode));
$$('.commands button').forEach((el) => el.onclick = () => battle.setCommand(el.dataset.command));
$$('.skills button').forEach((el) => {
  el.onclick = () => { if (el.dataset.skipClick) { delete el.dataset.skipClick; return; } const k = el.dataset.skill; if (battle.selectSkill(k) && k === 'counter') battle.direct({ x: battle.hero.x, y: battle.hero.y }); };
  el.addEventListener('pointerdown', (ev) => { if (!battle.free) return; el._drag = { x: ev.clientX, y: ev.clientY, pointer: ev.pointerId }; });
  window.addEventListener('pointerup', (ev) => {
    const d = el._drag; el._drag = null;
    if (!d || d.pointer !== ev.pointerId || Math.hypot(ev.clientX - d.x, ev.clientY - d.y) < 25) return;
    el.dataset.skipClick = '1';
    if (battle.selectSkill(el.dataset.skill)) { const p = view.dio.pickGround(ev.clientX, ev.clientY); if (p) battle.direct(p); }
  });
});
$('#wait').onclick = () => { battle.input(); battle.heroTurn({ type: 'wait' }); };
$('#reset').onclick = () => launch(battle.mode);
$('#compare').onclick = compare;
$('#pause').onclick = () => battle.setPause(!battle.paused);
$('#speed').onclick = () => { battle.speed = battle.speed === 0.5 ? 1 : battle.speed === 1 ? 2 : 0.5; battle.input(); render(); };
$('#autopause').onclick = () => { if (battle.mode !== 'B' && battle.mode !== 'D') return; battle.autoPause = !battle.autoPause; battle.input(); render(); };

const joyEl = $('#joystick'), stick = $('#stick');
joyEl.addEventListener('pointerdown', (ev) => { joy.pointer = ev.pointerId; joyEl.setPointerCapture(ev.pointerId); updateJoy(ev); battle.input(); });
joyEl.addEventListener('pointermove', (ev) => { if (ev.pointerId === joy.pointer) updateJoy(ev); });
const releaseJoy = (ev) => { if (ev.pointerId === joy.pointer) { joy.pointer = null; joy.x = joy.y = 0; stick.style.transform = ''; } };
joyEl.addEventListener('pointerup', releaseJoy); joyEl.addEventListener('pointercancel', releaseJoy);
function updateJoy(ev) {
  const r = joyEl.getBoundingClientRect(), dx = ev.clientX - (r.left + r.width / 2), dy = ev.clientY - (r.top + r.height / 2), d = Math.hypot(dx, dy) || 1, mag = Math.min(1, d / 36);
  joy.x = dx / d * mag; joy.y = dy / d * mag;
  stick.style.transform = `translate(${joy.x * 31}px,${joy.y * 31}px)`;
}
addEventListener('keydown', (ev) => {
  if (['INPUT','TEXTAREA','SELECT'].includes(document.activeElement?.tagName)) return;
  const k = ev.key.toLowerCase();
  if (['w','a','s','d','arrowup','arrowdown','arrowleft','arrowright',' '].includes(k)) ev.preventDefault();
  if (k === ' ') battle.setPause(!battle.paused);
  if (['1','2','3'].includes(k)) $$('.skills button')[Number(k) - 1].click();
  if (battle.mode === 'A' && !keys.has(k) && ['w','a','s','d'].includes(k)) {
    const d = { w: [0,-1], a: [-1,0], s: [0,1], d: [1,0] }[k]; battle.input(); battle.heroTurn({ type: 'move', point: { x: battle.hero.x + d[0], y: battle.hero.y + d[1] } });
  }
  keys.add(k);
});
addEventListener('keyup', (ev) => keys.delete(ev.key.toLowerCase()));
addEventListener('blur', () => keys.clear());
const MOVE_KEYS = ['w', 'a', 's', 'd', 'arrowup', 'arrowdown', 'arrowleft', 'arrowright'];
view.onFrame = (dt, real = dt) => {
  if (!battle) return;
  if (battle.mode === 'E') { // 조이스틱에 손을 대고 있거나(가만히 대고만 있어도) 움직이는 키·Space를 누르는 동안만 흐른다
    const flow = battle.flowing(joy.pointer !== null || keys.has(' ') || MOVE_KEYS.some((k) => keys.has(k)));
    view.setSpeed(flow ? 1 : 0);
    if ($('#app').classList.contains('frozen') === flow) { $('#app').classList.toggle('frozen', !flow); render(); }
    if (!flow && !battle.finished) battle.metrics.pausedSeconds += real;
  }
  if (battle.free) {
    let x = joy.x, y = joy.y;
    if (keys.has('w') || keys.has('arrowup')) y--;
    if (keys.has('s') || keys.has('arrowdown')) y++;
    if (keys.has('a') || keys.has('arrowleft')) x--;
    if (keys.has('d') || keys.has('arrowright')) x++;
    const l = Math.hypot(x, y); if (l) battle.continuousMove(x / Math.max(1, l), y / Math.max(1, l), dt);
  }
  if (battle.mode === 'D' && !battle.paused) { // 키보드: 누르고 있는 동안 그 방향으로 한 칸씩
    const d = [keys.has('d') || keys.has('arrowright') ? 1 : 0, keys.has('s') || keys.has('arrowdown') ? 1 : 0];
    if (keys.has('a') || keys.has('arrowleft')) d[0]--; if (keys.has('w') || keys.has('arrowup')) d[1]--;
    if (d[0] || d[1]) battle.order = { type: 'move', point: { x: battle.hero.x + d[0], y: battle.hero.y + d[1] } };
  }
  battle.tick(dt);
  view.show(battle);
  hudTime += real; if (hudTime > 0.12) { render(); hudTime = 0; }
};
launch('A');
window.__raidLab = { get battle() { return battle; }, launch, compare, view };
