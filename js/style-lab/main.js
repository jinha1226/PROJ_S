import { SCENES, sample } from './scenes.js';

/* ================= 스타일 실험실: 같은 장면을 세 스타일로 =================
   A 현재(DioramaKit) · B 절제된 로우폴리(three.js) · C 2D 탑다운(Canvas). 평가는 이 브라우저에 저장한다. */
const $ = (q) => document.querySelector(q);
const $$ = (q) => [...document.querySelectorAll(q)];
const STORE = 'torch-style-lab-v1';
const STYLES = {
  A: { name: 'A 현재', full: 'A 현재 디오라마', load: () => import('./style-a.js').then((m) => m.StyleA) },
  B: { name: 'B 로우폴리', full: 'B 절제된 로우폴리', load: () => import('./style-b.js').then((m) => m.StyleB) },
  C: { name: 'C 2D', full: 'C 2D 탑다운', load: () => import('./style-c.js').then((m) => m.StyleC) },
};
const AXES = [['cute', '귀여움'], ['read', '한눈에 읽힘'], ['tone', '이야기 톤']];
const safe = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

function load() { try { return JSON.parse(localStorage.getItem(STORE) || '{}'); } catch { return {}; } }
function save(d) { try { localStorage.setItem(STORE, JSON.stringify(d)); } catch { /* 저장 안 됨 */ } }

const q = new URLSearchParams(location.search), saved = load();
const S = {
  style: STYLES[q.get('style')] ? q.get('style') : STYLES[saved.last?.style] ? saved.last.style : 'A',
  scene: SCENES[q.get('scene')] ? q.get('scene') : SCENES[saved.last?.scene] ? saved.last.scene : 'dungeon',
  frozen: q.get('freeze') === '1', t: Number(q.get('t')) || 0.9,
  views: {}, active: null, loading: null,
};
const stage = $('#stage');

const pending = {};
function view(id) { return S.views[id] ? Promise.resolve(S.views[id]) : (pending[id] ||= makeView(id)); } // 불러오는 중에 또 눌러도 하나만 만든다
async function makeView(id) {
  const Cls = await STYLES[id].load();
  const host = document.createElement('div'); host.className = 'sl-host'; host.dataset.style = id; stage.appendChild(host);
  const v = new Cls(host); v.host = host; S.views[id] = v;
  if (id !== S.style) { host.hidden = true; v.show(false); } // 불러오는 사이 다른 스타일을 골랐다
  return v;
}
async function apply() {
  const token = S.loading = {};
  hud();
  const v = await view(S.style);
  if (S.loading !== token) return;
  for (const [id, o] of Object.entries(S.views)) { o.host.hidden = id !== S.style; o.show(id === S.style); }
  v.setScene(SCENES[S.scene]); v.setFrozen?.(S.frozen);
  S.active = v;
  const d = load(); d.last = { style: S.style, scene: S.scene }; save(d);
  hud();
  document.body.dataset.ready = S.style + S.scene;
}
function hud() {
  $$('[data-style]').forEach((b) => b.tagName === 'BUTTON' && b.classList.toggle('on', b.dataset.style === S.style));
  $$('[data-scene]').forEach((b) => b.classList.toggle('on', b.dataset.scene === S.scene));
  $('#freeze').classList.toggle('on', S.frozen); $('#freeze').textContent = S.frozen ? '흐름' : '멈춤';
  $('#app').classList.toggle('frozen', S.frozen);
  $('#sname').textContent = STYLES[S.style].full;
  const r = load()[S.style] || {};
  $('#rate').innerHTML = AXES.map(([k, label]) => `<div class="row"><span>${label}</span><div class="dots">${[1, 2, 3, 4, 5].map((n) => `<button data-axis="${k}" data-v="${n}" class="${r[k] >= n ? 'on' : ''}">${n}</button>`).join('')}</div></div>`).join('');
  $('#memo').value = r.memo || '';
}
function rate(axis, v) { const d = load(), r = d[S.style] ||= {}; r[axis] = r[axis] === v ? 0 : v; save(d); hud(); }
function compare() {
  const d = load();
  const cell = (v) => (v ? `<b>${v}</b>` : '·');
  $('#overlay').innerHTML = `<div class="panel"><h2>비교</h2><table><tr><th></th>${AXES.map(([, l]) => `<th>${l}</th>`).join('')}</tr>
    ${Object.entries(STYLES).map(([id, s]) => `<tr class="${id === S.style ? 'cur' : ''}"><td>${s.name}</td>${AXES.map(([k]) => `<td>${cell(d[id]?.[k])}</td>`).join('')}</tr>${d[id]?.memo ? `<tr class="memo"><td colspan="4">${safe(d[id].memo)}</td></tr>` : ''}`).join('')}
  </table><button id="close">닫기</button></div>`;
  $('#overlay').hidden = false;
  $('#close').onclick = () => { $('#overlay').hidden = true; };
}

$$('button[data-style]').forEach((b) => { b.onclick = () => { S.style = b.dataset.style; apply(); }; });
$$('[data-scene]').forEach((b) => { b.onclick = () => { S.scene = b.dataset.scene; apply(); }; });
$('#freeze').onclick = () => { S.frozen = !S.frozen; S.active?.setFrozen?.(S.frozen); hud(); };
$('#rate').onclick = (e) => { const b = e.target.closest('button[data-axis]'); if (b) rate(b.dataset.axis, Number(b.dataset.v)); };
$('#memo').oninput = () => { const d = load(); (d[S.style] ||= {}).memo = $('#memo').value.slice(0, 200); save(d); };
$('#compare').onclick = compare;
$('#overlay').onclick = (e) => { if (e.target.id === 'overlay') $('#overlay').hidden = true; };
new ResizeObserver(() => S.active?.resize()).observe(stage);

let last = performance.now();
function loop(now) {
  requestAnimationFrame(loop);
  const dt = Math.min(0.05, (now - last) / 1000); last = now;
  if (!S.frozen) S.t += dt;
  if (S.active) S.active.render(sample(SCENES[S.scene], S.t));
}
requestAnimationFrame(loop);
apply();
window.__styleLab = S;
window.__sample = () => sample(SCENES[S.scene], S.t);
