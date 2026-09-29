import { META, saveMeta } from '../core/meta.js';
import { furnCells } from '../core/rooms.js';
import { autoPlan, canRedo, canUndo, checkBps, clearHistory, clipBps, commit, copyRoom, cutArea, demolish, fillBps, flipClip, inLight, lineBps, missing, neededRooms, paintZone, placeBps, presetBps, radius, redo, roomBps, rotateClip, stockOf, suggestSpots, sumCost, buildHours, undo } from '../core/settlement.js';
import { FLOOR_TYPES, FURN, PRESETS, RES_ICON, ROOMS, SIZE_NAME, SW, TERRAIN, WALLS, ZONE_TYPES } from '../data/build.js';
import { MATS } from '../data/items.js';
import { JOBS, MOODS } from '../data/town.js';
import { Sfx } from '../render/sfx.js';
import { View } from '../render/view.js';
import { $, UI } from '../ui/ui.js';
import { Town } from './town.js';

/* ================= 건설 모드 (docs/설계_정착지_건설.md §4 · §8) =================
   한 손가락 = 그리기(끌기 또는 두 번 탭), 두 손가락 = 화면. 모든 것은 청사진으로 놓이고 [짓기]로 실체가 된다. */
const TABS = [['room', '🏠', '방'], ['wall', '🧱', '벽·바닥'], ['furn', '🪑', '가구'], ['zone', '🟩', '구역'], ['cut', '🪓', '베기'], ['del', '🗑', '철거']];
const RECT = new Set(['room', 'wline', 'wbox', 'floor', 'zone', 'cut', 'del']);
const LAYERS = [['all', '전체'], ['floor', '바닥만'], ['walls', '벽까지'], ['zones', '구역만']];
const FURN_LIST = Object.keys(FURN).filter((k) => !FURN[k].unique);
const PRESET_KINDS = ['bedroom', 'forge', 'herb', 'hunter', 'library', 'inn', 'storage'];
const I = (x, y) => y * SW + x;
const costText = (cost, S) => Object.entries(cost).map(([m, n]) => { const have = stockOf(m, S); return `<span style="color:${have >= n ? '#e8dcc0' : '#ff8a8a'}">${RES_ICON[m] || MATS[m] || ''}${m} ${n}</span>`; }).join(' ') || '<span style="color:#9aa2bd">비용 없음</span>';
const missText = (miss) => Object.entries(miss).map(([m, n]) => `${m} ${n}`).join(', ');

Object.assign(Town, {
  bm: null,
  /* ---------- 들어가기 · 나가기 ---------- */
  enterBuild() {
    if (this.busy) return;
    this.buildMode = true; clearHistory();
    this.bm ||= { tab: 'room', tool: 'room', wall: 'wood', floor: 'wood', furn: 'bed', rot: 0, zone: 'field', preset: null, spots: [], start: null, cur: null, clip: null, layer: 'all' };
    this.bm.start = null; this.bm.cur = null;
    $('#tbtns').classList.add('hidden'); $('#buildbar').classList.remove('hidden'); $('#sheet').classList.add('hidden');
    this.dragHandler ||= { down: (x, y) => this.dragDown(x, y), move: (x, y) => this.dragMove(x, y), up: (x, y, ok) => this.dragUp(x, y, ok), cancel: () => this.dragCancel() };
    this.setTool(this.bm.tool); Sfx.play('ui');
    try { if (!localStorage.getItem('torch-build-hint')) { UI.toast('한 손가락으로 그리고, 두 손가락으로 화면을 옮긴다.'); localStorage.setItem('torch-build-hint', '1'); } } catch (_) { /* 없음 */ }
  },
  exitBuild() {
    this.buildMode = false; clearHistory();
    const sv = this.sv; sv?.setPreview(); sv?.setMarkers([]); sv?.setSelect(null); sv?.setLayers('all');
    View.dio.rig.drag = null; this.magnify(null);
    $('#buildbar').classList.add('hidden'); $('#tbtns').classList.remove('hidden');
    saveMeta(); this.renderHud();
  },
  /** 도구 고르기: 사각형 도구만 한 손가락 끌기를 그리기로 쓴다(나머지는 끌면 화면 이동) */
  setTool(tool) {
    const bm = this.bm; bm.tool = tool; bm.start = null; bm.cur = null;
    this.sv?.setPreview(); this.sv?.setSelect(null); this.magnify(null);
    if (tool !== 'preset') { bm.spots = []; this.sv?.setMarkers([]); }
    View.dio.rig.drag = RECT.has(tool) ? this.dragHandler : null;
    this.renderBuild();
  },
  cellAt(sx, sy) { const c = View.dio.pickGround(sx, sy); return c && c.x >= 0 && c.y >= 0 && c.x < SW && c.y < SW ? c : null; },
  /* ---------- 끌기 · 두 번 탭 ---------- */
  dragDown(sx, sy) { const c = this.cellAt(sx, sy); if (!c) return; this.bm.start = c; this.bm.cur = c; this.previewRect(); },
  dragMove(sx, sy) { const c = this.cellAt(sx, sy); if (!c || !this.bm.start) return; this.bm.cur = c; this.previewRect(); },
  dragUp(sx, sy, ok) { const bm = this.bm; if (!ok || !bm.start) { this.dragCancel(); return; } const c = this.cellAt(sx, sy) || bm.cur; this.applyRect(bm.start, c); },
  dragCancel() { const bm = this.bm; bm.start = null; bm.cur = null; this.sv?.setPreview(); this.sv?.setSelect(null); this.magnify(null); this.renderBuild(); },
  buildTap(sx, sy) {
    const bm = this.bm, c = this.cellAt(sx, sy); if (!c) return;
    const t = bm.tool;
    if (RECT.has(t)) {
      if (!bm.start) { bm.start = c; bm.cur = c; this.previewRect(); return; } // 첫 탭: 시작 칸 고정
      this.applyRect(bm.start, c); return;
    }
    if (t === 'door') this.place([{ L: 'wall', k: 'door', x: c.x, y: c.y }]);
    else if (t === 'furn') this.place([{ L: 'furn', k: bm.furn, x: c.x, y: c.y, rot: bm.rot }]);
    else if (t === 'preset') {
      const s = bm.spots.find((q) => c.x >= q.x && c.x < q.x + q.w && c.y >= q.y && c.y < q.y + q.h);
      const P = bm.preset; if (!P) return;
      this.place(s ? s.bps : presetBps(P.kind, P.size, c.x, c.y, bm.rot, bm.wall));
    } else if (t === 'copy') {
      const clip = copyRoom(c.x, c.y);
      if (!clip) { UI.toast('벽으로 닫힌 방을 누른다.'); return; }
      bm.clip = clip; UI.toast('방을 떠 왔다. 놓을 곳을 누른다.'); this.setTool('paste');
    } else if (t === 'paste' && bm.clip) this.place(clipBps(bm.clip, c.x, c.y));
  },
  /** 사각형 → 청사진 목록(도구마다) */
  rectBps(a, b) {
    const bm = this.bm;
    if (bm.tool === 'room') return roomBps(a.x, a.y, b.x, b.y, bm.wall, bm.floor);
    if (bm.tool === 'wline') return lineBps(a.x, a.y, b.x, b.y, 'wall', bm.wall);
    if (bm.tool === 'wbox') return fillBps(a.x, a.y, b.x, b.y, 'wall', bm.wall, true);
    if (bm.tool === 'floor') return fillBps(a.x, a.y, b.x, b.y, 'floor', bm.floor);
    return [];
  },
  previewRect() {
    const bm = this.bm, a = bm.start, b = bm.cur; if (!a || !b) return;
    const sel = { x0: Math.min(a.x, b.x), y0: Math.min(a.y, b.y), x1: Math.max(a.x, b.x), y1: Math.max(a.y, b.y) };
    this.sv?.setSelect(sel);
    const list = this.rectBps(a, b);
    if (list.length) { const r = checkBps(list); this.sv?.setPreview(r.ok, r.bad); bm.pv = r; }
    else { this.sv?.setPreview(); bm.pv = null; }
    this.magnify(b); this.renderBuild();
  },
  applyRect(a, b) {
    const bm = this.bm; bm.start = null; bm.cur = null;
    this.sv?.setPreview(); this.sv?.setSelect(null); this.magnify(null);
    if (bm.tool === 'cut') { const r = cutArea(a.x, a.y, b.x, b.y); if (r.n) { UI.toast(`${Object.entries(r.gained).map(([m, n]) => `${m} ${n}`).join(', ')}을 얻었다.`); Sfx.play('blunt'); } else UI.toast('빛 안의 나무·바위·광맥·폐허를 고른다.'); }
    else if (bm.tool === 'del') { const r = demolish(a.x, a.y, b.x, b.y); if (r.n) { const back = Object.entries(r.back).map(([m, n]) => `${m} ${n}`).join(', '); UI.toast(back ? `철거했다. ${back}을 돌려받았다.` : '철거했다.'); Sfx.play('blunt'); } }
    else if (bm.tool === 'zone') { const n = paintZone(a.x, a.y, b.x, b.y, bm.zone === 'erase' ? null : bm.zone); if (!n) UI.toast('빛 안의 빈 땅을 고른다.'); }
    else { this.place(this.rectBps(a, b)); return; }
    this.afterEdit();
  },
  /** 청사진 놓기 + 못 놓은 까닭 한 줄 */
  place(list) {
    if (!list.length) { UI.toast('방은 3×3보다 크게 그린다.'); return; }
    const r = placeBps(list);
    if (r.bad.length && !r.ok.length) UI.toast(r.bad[0].why + '.');
    else if (r.bad.length) UI.toast(`${r.bad.length}칸은 못 놓았다. ${r.bad[0].why}.`);
    if (r.ok.length) Sfx.play('pick');
    this.afterEdit();
  },
  afterEdit() { this.refreshWorld(); if (this.bm.tool === 'preset') this.showSpots(); this.renderBuild(); this.renderHud(); },
  /** 프리셋: 추천 자리 2~3곳을 반짝인다 */
  showSpots() {
    const bm = this.bm, P = bm.preset; if (!P) return;
    bm.spots = suggestSpots(P.kind, P.size, 3); this.sv?.setMarkers(bm.spots.map((s) => ({ x: s.x, y: s.y, w: s.w, h: s.h })));
  },
  /* ---------- 버튼 ---------- */
  buildAct(a, v) {
    const bm = this.bm;
    if (a === 'tab') { bm.tab = v; this.setTool({ room: 'room', wall: 'wline', furn: 'furn', zone: 'zone', cut: 'cut', del: 'del' }[v]); Sfx.play('ui'); return; }
    if (a === 'tool') { this.setTool(v); return; }
    if (a === 'wall') { bm.wall = v; if (bm.tool === 'preset') this.showSpots(); }
    if (a === 'floor') { bm.floor = v; if (bm.tool !== 'room') this.setTool('floor'); }
    if (a === 'furn') { bm.furn = v; this.setTool('furn'); }
    if (a === 'zone') bm.zone = v;
    if (a === 'preset') { const [kind, size] = v.split(':'); bm.preset = { kind, size }; this.setTool('preset'); this.showSpots(); if (!bm.spots.length) UI.toast('빛 안에 놓을 자리가 없다. 나무를 베거나 빛을 넓히자.'); return; }
    if (a === 'rot') { bm.rot = (bm.rot + 1) % 4; if (bm.clip) bm.clip = rotateClip(bm.clip); }
    if (a === 'flip' && bm.clip) bm.clip = flipClip(bm.clip);
    if (a === 'auto') {
      const r = autoPlan();
      if (r.placed.length) UI.toast(`${r.placed.map((k) => ROOMS[k].name).join(', ')} 청사진을 놓았다.`); else if (!r.failed.length) UI.toast('지금은 모자란 방이 없다.');
      if (r.failed.length) UI.toast(`${r.failed.map((k) => ROOMS[k].name).join(', ')}을 놓을 자리가 없다.`);
      this.afterEdit(); return;
    }
    if (a === 'commit') {
      const r = commit();
      if (r.built && !r.left) { UI.toast(`청사진 ${r.built}개를 지었다.`); Sfx.play('blunt'); View.dio.rig.shake(0.2); }
      else if (r.built) UI.toast(`${r.built}개를 지었다. ${missText(r.missing)} 모자라 ${r.left}개가 남았다.`);
      else if (r.left) UI.toast(`${missText(r.missing)} 모자란다.`);
      else UI.toast('지을 청사진이 없다.');
      this.afterEdit(); return;
    }
    if (a === 'undo') { if (undo()) this.afterEdit(); return; }
    if (a === 'redo') { if (redo()) this.afterEdit(); return; }
    if (a === 'layer') { const k = LAYERS.findIndex(([m]) => m === bm.layer); bm.layer = LAYERS[(k + 1) % LAYERS.length][0]; this.sv?.setLayers(bm.layer); }
    if (a === 'exit') { this.exitBuild(); return; }
    this.renderBuild();
  },
  renderBuild() {
    const bm = this.bm, S = META.settle, el = $('#buildbar'); if (!el || !bm) return;
    const chip = (a, v, label, on) => `<button class="bchip ${on ? 'on' : ''}" data-a="${a}" data-v="${v}">${label}</button>`;
    const wallChips = ['wood', 'stone'].map((k) => chip('wall', k, WALLS[k].name, bm.wall === k)).join('');
    let opts = '';
    if (bm.tab === 'room') {
      opts = `${chip('tool', 'room', '▭ 방 그리기', bm.tool === 'room')}${chip('auto', '', '✨ 알아서 짓기', false)}${chip('tool', 'copy', '📋 복사', bm.tool === 'copy')}${bm.clip ? chip('tool', 'paste', '📌 붙이기', bm.tool === 'paste') : ''}${bm.tool === 'paste' ? chip('rot', '', '⟳ 회전', false) + chip('flip', '', '⇋ 반전', false) : ''}${wallChips}`
        + `<div class="brow2">${PRESET_KINDS.map((k) => Object.keys(PRESETS[k]).map((s) => chip('preset', `${k}:${s}`, `${ROOMS[k].icon} ${SIZE_NAME[s]} ${ROOMS[k].name}`, bm.tool === 'preset' && bm.preset && bm.preset.kind === k && bm.preset.size === s)).join('')).join('')}${bm.tool === 'preset' ? chip('rot', '', '⟳', false) : ''}</div>`;
    } else if (bm.tab === 'wall') {
      opts = `${chip('tool', 'wline', '╱ 벽 선', bm.tool === 'wline')}${chip('tool', 'wbox', '▢ 벽 윤곽', bm.tool === 'wbox')}${chip('tool', 'door', '🚪 문', bm.tool === 'door')}${wallChips}<div class="brow2">${Object.keys(FLOOR_TYPES).map((k) => chip('floor', k, `▦ ${FLOOR_TYPES[k].name}`, bm.tool === 'floor' && bm.floor === k)).join('')}</div>`;
    } else if (bm.tab === 'furn') {
      opts = `${FURN_LIST.map((k) => chip('furn', k, `${FURN[k].icon} ${FURN[k].name}`, bm.furn === k)).join('')}${chip('rot', '', `⟳ 회전 ${bm.rot * 90}°`, false)}`;
    } else if (bm.tab === 'zone') {
      opts = `${Object.keys(ZONE_TYPES).map((k) => chip('zone', k, ZONE_TYPES[k].name, bm.zone === k)).join('')}${chip('zone', 'erase', '지우개', bm.zone === 'erase')}`;
    } else if (bm.tab === 'cut') opts = '<span class="bnote">나무·바위·광맥·폐허를 사각형으로 고르면 바로 베고 캔다.</span>';
    else opts = '<span class="bnote">사각형 안의 청사진은 취소, 지은 것은 재료 절반이 돌아온다.</span>';
    // 상태 줄: 그리는 중이면 미리보기 비용, 아니면 쌓인 청사진
    let stat;
    if (bm.start && bm.pv) {
      const miss = missing(bm.pv.cost, S);
      stat = `${bm.pv.ok.length}칸 · ${costText(bm.pv.cost, S)} · ${buildHours(bm.pv.ok)}시간${Object.keys(miss).length ? ` · <b style="color:#ff8a8a">${missText(miss)} 모자란다</b>` : ''}${bm.pv.bad.length ? ` · <b style="color:#ff8a8a">${bm.pv.bad[0].why}</b>` : ''}`;
    } else if (bm.start) stat = '끝 칸을 누르거나 끌어서 사각형을 만든다.';
    else if (bm.tool === 'preset' && bm.preset) { const s = bm.spots[0]; stat = s ? `반짝이는 자리를 누른다 · ${costText(s.cost, S)}` : '놓을 자리가 없다.'; }
    else if (bm.tool === 'copy') stat = '떠 올 방을 누른다.';
    else if (bm.tool === 'paste') stat = '붙일 자리(왼쪽 위)를 누른다.';
    else { const need = neededRooms(); stat = need.length ? `모자란 방: ${need.map(([k]) => ROOMS[k].name).join(', ')}` : '빛 안에 무엇이든 지을 수 있다.'; }
    const bpCost = sumCost(S.bp), miss = missing(bpCost, S);
    el.innerHTML = `<div id="bstat">${stat}</div><div id="bopts">${opts}</div>
      <div id="btabs">${TABS.map(([k, ic, n]) => `<button class="${bm.tab === k ? 'on' : ''}" data-a="tab" data-v="${k}">${ic}<small>${n}</small></button>`).join('')}</div>
      <div id="bacts"><button data-a="undo" ${canUndo() ? '' : 'disabled'}>↶</button><button data-a="redo" ${canRedo() ? '' : 'disabled'}>↷</button><button data-a="layer">👁<small>${LAYERS.find(([m]) => m === bm.layer)[1]}</small></button>
        <button class="pri" data-a="commit" ${S.bp.length ? '' : 'disabled'}>✔ 짓기 ${S.bp.length ? `<small style="color:${Object.keys(miss).length ? '#ff9a9a' : '#e8dcc0'}">${S.bp.length}개 · ${Object.entries(bpCost).map(([m, n]) => `${RES_ICON[m] || MATS[m] || ''}${n}`).join(' ') || '무료'}</small>` : ''}</button><button data-a="exit">완료</button></div>`;
    el.querySelectorAll('[data-a]').forEach((b) => { b.onclick = () => this.buildAct(b.dataset.a, b.dataset.v); });
  },
  /* ---------- 돋보기: 손가락 아래 칸을 화면 위쪽에 크게 ---------- */
  magnify(c) {
    const cv = $('#mag'); if (!cv) return;
    if (!c) { cv.classList.add('hidden'); return; }
    cv.classList.remove('hidden');
    const g = cv.getContext('2d'), S = META.settle, N = 9, px = cv.width / N, R = radius(), bm = this.bm;
    const bpAt = new Map(); for (const b of S.bp) for (const [x, y] of b.L === 'furn' ? furnCells(b) : [[b.x, b.y]]) bpAt.set(I(x, y), b);
    const pv = new Map(); if (bm.pv) { for (const b of bm.pv.ok) for (const [x, y] of b.L === 'furn' ? furnCells(b) : [[b.x, b.y]]) pv.set(I(x, y), 1); for (const b of bm.pv.bad) pv.set(I(b.x, b.y), 2); }
    const fAt = new Map(); for (const f of S.furn) for (const [x, y] of furnCells(f)) fAt.set(I(x, y), f);
    const TC = ['#c9ad7a', '#6fae4e', '#9a9a92', '#2a6ab0', '#2f6a2a', '#7a7a80', '#8a6aa0'];
    g.clearRect(0, 0, cv.width, cv.height);
    for (let dy = 0; dy < N; dy++) for (let dx = 0; dx < N; dx++) {
      const x = c.x + dx - 4, y = c.y + dy - 4, X = dx * px, Y = dy * px;
      if (x < 0 || y < 0 || x >= SW || y >= SW) { g.fillStyle = '#05060a'; g.fillRect(X, Y, px, px); continue; }
      const i = I(x, y); g.fillStyle = TC[S.terr[i]]; g.fillRect(X, Y, px, px);
      if (S.floor[i]) { g.fillStyle = ['', '#b89a6a', '#b07a44', '#a8a8a0', '#a04a4a'][S.floor[i]]; g.fillRect(X + 1, Y + 1, px - 2, px - 2); }
      if (S.wall[i]) { g.fillStyle = S.wall[i] === 3 ? '#e0b060' : S.wall[i] === 2 ? '#7a8088' : '#6a4526'; g.fillRect(X, Y, px, px); }
      const f = fAt.get(i); if (f) { g.font = `${px * 0.7}px sans-serif`; g.textAlign = 'center'; g.textBaseline = 'middle'; g.fillText(FURN[f.k].icon, X + px / 2, Y + px / 2 + 1); }
      if (bpAt.has(i)) { g.fillStyle = 'rgba(120,220,255,.45)'; g.fillRect(X, Y, px, px); }
      if (pv.has(i)) { g.fillStyle = pv.get(i) === 1 ? 'rgba(90,230,120,.55)' : 'rgba(255,80,80,.6)'; g.fillRect(X, Y, px, px); }
      if (!inLight(x, y, R)) { g.fillStyle = 'rgba(5,6,12,.7)'; g.fillRect(X, Y, px, px); }
      g.strokeStyle = 'rgba(0,0,0,.25)'; g.strokeRect(X + 0.5, Y + 0.5, px - 1, px - 1);
    }
    g.strokeStyle = '#fff'; g.lineWidth = 2; g.strokeRect(4 * px + 1, 4 * px + 1, px - 2, px - 2); g.lineWidth = 1;
    const T = TERRAIN[S.terr[I(c.x, c.y)]]; g.fillStyle = 'rgba(0,0,0,.6)'; g.fillRect(0, cv.height - 18, cv.width, 18); g.fillStyle = '#fff'; g.font = '12px sans-serif'; g.textAlign = 'left'; g.fillText(`${c.x},${c.y} ${T.name}`, 5, cv.height - 5);
  },
  /* ---------- 사람 ---------- */
  peopleSheet() {
    const rows = META.npcs.map((n) => { const b = JOBS[n.job].b, has = !ROOMS[b] || META.buildings[b]; return `<button class="prow" data-n="${n.id}" style="width:100%"><span>${MOODS[n.mood + 2]} <b>${n.name}</b> <small style="color:#9aa2bd">${JOBS[n.job].name}</small></span><small style="color:${has ? '#9fe0a0' : '#ff9a9a'}">${ROOMS[b] ? `${ROOMS[b].icon} ${has ? ROOMS[b].name : `${ROOMS[b].name} 없음`}` : ''}</small></button>`; }).join('') || '<p style="color:#9aa2bd">아직 아무도 없다.</p>';
    const beds = META.settle.furn.filter((f) => f.k === 'bed').length;
    const sh = this.sheet(`<h3>👥 사람 <button class="close">닫기</button></h3><div class="gtxt">주민 ${META.npcs.length} · 침대 ${beds}</div>${rows}`);
    sh.querySelectorAll('[data-n]').forEach((b) => { b.onclick = () => { const n = META.npcs.find((q) => q.id === b.dataset.n); if (n) { sh.classList.add('hidden'); this.npcCard(n); } }; });
  },
});
