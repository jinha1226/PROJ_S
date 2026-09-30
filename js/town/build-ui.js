import { markCut } from '../core/colony.js';
import { META, saveMeta } from '../core/meta.js';
import { furnCells } from '../core/rooms.js';
import { autoPlan, buildHours, canRedo, canUndo, checkBps, clearHistory, clipBps, copyRoom, demolish, fillBps, flipClip, inLight, lineBps, missing, neededRooms, paintZone, placeBps, presetBps, radius, redo, roomBps, rotateClip, stockOf, suggestSpots, sumCost, undo } from '../core/settlement.js';
import { FLOOR_TYPES, FURN, PRESETS, RES_ICON, ROOMS, SIZE_NAME, SW, TERRAIN, WALLS, ZONE_TYPES } from '../data/build.js';
import { MATS } from '../data/items.js';
import { JOBS, MOODS } from '../data/town.js';
import { Sfx } from '../render/sfx.js';
import { View } from '../render/view.js';
import { $, UI } from '../ui/ui.js';
import { jo } from '../util/text.js';
import { Town } from './town.js';

/* ================= 건설 모드 (docs/설계_정착지_건설.md §4 · §8) =================
   한 번에 한 단계만 보인다: 분류 카드 → 물건 한 줄 → 그리기([되돌리기] [그만]만).
   한 손가락 = 그리기(끌기 또는 두 번 탭), 두 손가락 = 화면. 놓으면 재료가 되는 만큼 바로 지어지고, 모자란 것만 청사진(빨강)으로 남는다. */
const CATS = [['room', '🏠', '방'], ['wall', '🧱', '벽·바닥'], ['furn', '🪑', '가구'], ['zone', '🟩', '구역'], ['cut', '🪓', '베기'], ['del', '🗑', '철거']];
const RECT = new Set(['room', 'wall', 'floor', 'zone', 'cut', 'del']);
const LAYERS = [['all', '전체'], ['floor', '바닥만'], ['walls', '벽까지'], ['zones', '구역만']];
const FURN_LIST = Object.keys(FURN).filter((k) => !FURN[k].unique);
const PRESET_KINDS = ['bedroom', 'forge', 'herb', 'hunter', 'library', 'inn', 'storage'];
const I = (x, y) => y * SW + x;
const resText = (cost) => Object.entries(cost).map(([m, n]) => `${RES_ICON[m] || MATS[m] || ''}${n}`).join(' ') || '무료';
const costText = (cost, S) => Object.entries(cost).map(([m, n]) => { const have = stockOf(m, S); return `<span style="color:${have >= n ? '#e8dcc0' : '#ff8a8a'}">${RES_ICON[m] || MATS[m] || ''}${m} ${n}</span>`; }).join(' ') || '<span style="color:#9aa2bd">비용 없음</span>';
const missText = (miss) => Object.entries(miss).map(([m, n]) => `${m} ${n}`).join(', ');
/** 물건 카드 한 줄: [값, 아이콘, 이름, 비용] */
function itemsOf(cat) {
  if (cat === 'room') return [['draw', '▭', '직접 그리기', null], ...PRESET_KINDS.map((k) => [`preset:${k}`, ROOMS[k].icon, ROOMS[k].name, null]), ['copy', '📋', '방 복사', null]];
  if (cat === 'wall') return [['wall:wood', '🪵', WALLS.wood.name, WALLS.wood.cost], ['wall:stone', '🪨', WALLS.stone.name, WALLS.stone.cost], ['door', '🚪', WALLS.door.name, WALLS.door.cost], ...Object.keys(FLOOR_TYPES).map((k) => [`floor:${k}`, '▦', FLOOR_TYPES[k].name, FLOOR_TYPES[k].cost])];
  if (cat === 'furn') return FURN_LIST.map((k) => [`furn:${k}`, FURN[k].icon, FURN[k].name, FURN[k].cost]);
  if (cat === 'zone') return [...Object.keys(ZONE_TYPES).map((k) => [`zone:${k}`, '🟩', ZONE_TYPES[k].name, {}]), ['zone:erase', '⌫', '구역 지우기', {}]];
  return [];
}

Object.assign(Town, {
  bm: null,
  /* ---------- 들어가기 · 나가기 ---------- */
  enterBuild() {
    if (this.busy) return;
    this.buildMode = true; clearHistory();
    this.bm = { stage: 'cats', cat: null, tool: null, wall: 'wood', floor: 'wood', furn: 'bed', rot: 0, zone: 'field', shape: 'line', preset: null, size: 'M', spots: [], start: null, cur: null, clip: null, layer: 'all', more: false, pv: null };
    this.dragHandler ||= { down: (x, y) => this.dragDown(x, y), move: (x, y) => this.dragMove(x, y), up: (x, y, ok) => this.dragUp(x, y, ok), cancel: () => this.dragCancel() };
    $('#tbtns').classList.add('hidden'); $('#buildbar').classList.remove('hidden'); $('#sheet').classList.add('hidden');
    this.setTool(null); Sfx.play('ui');
    try { if (!localStorage.getItem('torch-build-hint')) { UI.toast('한 손가락으로 그리고, 두 손가락으로 화면을 옮긴다.'); localStorage.setItem('torch-build-hint', '1'); } } catch (_) { /* 없음 */ }
  },
  exitBuild() {
    this.buildMode = false; clearHistory();
    const sv = this.sv; sv?.setPreview(); sv?.setMarkers([]); sv?.setSelect(null); sv?.setLayers('all');
    View.dio.rig.drag = null; this.magnify(null);
    $('#buildbar').classList.add('hidden'); $('#tbtns').classList.remove('hidden');
    saveMeta(); this.renderHud();
  },
  /** 도구: 사각형 도구만 한 손가락 끌기를 그리기로 쓴다(나머지는 끌면 화면 이동) */
  setTool(tool) {
    const bm = this.bm; bm.tool = tool; bm.start = null; bm.cur = null; bm.pv = null; bm.more = false;
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
  dragCancel() { const bm = this.bm; bm.start = null; bm.cur = null; bm.pv = null; this.sv?.setPreview(); this.sv?.setSelect(null); this.magnify(null); this.renderBuild(); },
  buildTap(sx, sy) {
    const bm = this.bm, c = this.cellAt(sx, sy); if (!c || bm.stage !== 'draw') return;
    const t = bm.tool;
    if (RECT.has(t)) {
      if (!bm.start) { bm.start = c; bm.cur = c; this.previewRect(); return; } // 첫 탭: 시작 칸 고정
      this.applyRect(bm.start, c); return;
    }
    if (t === 'door') this.place([{ L: 'wall', k: 'door', x: c.x, y: c.y }]);
    else if (t === 'furn') this.place([{ L: 'furn', k: bm.furn, x: c.x, y: c.y, rot: bm.rot }]);
    else if (t === 'preset') {
      const s = bm.spots.find((q) => c.x >= q.x && c.x < q.x + q.w && c.y >= q.y && c.y < q.y + q.h), P = bm.preset;
      this.place(s ? presetBps(P, bm.size, s.x, s.y, s.rot, bm.wall) : presetBps(P, bm.size, c.x, c.y, 0, bm.wall));
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
    if (bm.tool === 'wall') return bm.shape === 'box' ? fillBps(a.x, a.y, b.x, b.y, 'wall', bm.wall, true) : lineBps(a.x, a.y, b.x, b.y, 'wall', bm.wall);
    if (bm.tool === 'floor') return fillBps(a.x, a.y, b.x, b.y, 'floor', bm.floor);
    return [];
  },
  previewRect() {
    const bm = this.bm, a = bm.start, b = bm.cur; if (!a || !b) return;
    this.sv?.setSelect({ x0: Math.min(a.x, b.x), y0: Math.min(a.y, b.y), x1: Math.max(a.x, b.x), y1: Math.max(a.y, b.y) });
    const list = this.rectBps(a, b);
    if (list.length) { const r = checkBps(list); this.sv?.setPreview(r.ok, r.bad); bm.pv = r; }
    else { this.sv?.setPreview(); bm.pv = null; }
    this.magnify(b); this.renderBuild();
  },
  applyRect(a, b) {
    const bm = this.bm; bm.start = null; bm.cur = null; bm.pv = null;
    this.sv?.setPreview(); this.sv?.setSelect(null); this.magnify(null);
    if (bm.tool === 'cut') {
      const n = markCut(a.x, a.y, b.x, b.y); // 베기 표시: 주민이 목표 재고와 상관없이 먼저 벤다
      if (n) { UI.toast(`${n}곳을 베기로 표시했다. 손이 비는 주민이 먼저 한다.`); Sfx.play('pick'); }
      else UI.toast('빛 안의 나무·바위·광맥·폐허를 고른다.');
    } else if (bm.tool === 'del') { const r = demolish(a.x, a.y, b.x, b.y); if (r.n) { const back = Object.entries(r.back).map(([m, n]) => `${m} ${n}`).join(', '); UI.toast(back ? `철거했다. 돌려받은 재료: ${back}.` : '철거했다.'); Sfx.play('blunt'); } }
    else if (bm.tool === 'zone') { const n = paintZone(a.x, a.y, b.x, b.y, bm.zone === 'erase' ? null : bm.zone); if (!n) UI.toast('빛 안의 빈 땅을 고른다.'); }
    else { this.place(this.rectBps(a, b)); return; }
    this.afterEdit();
  },
  /** 청사진을 놓는다. 주민이 재료를 가져다 시간을 들여 짓는다(docs/설계_정착지_2단계.md §4) */
  place(list) {
    if (!list.length) { UI.toast('방은 가로세로 세 칸보다 크게 그린다.'); return; }
    const r = placeBps(list);
    if (!r.ok.length) { if (r.bad.length) UI.toast(r.bad[0].why + '.'); this.afterEdit(); return; }
    const miss = missing(r.cost), hours = Math.ceil(buildHours(r.ok));
    UI.toast(`청사진 ${r.ok.length}개 · 약 ${hours}시간 일.${Object.keys(miss).length ? ` ${missText(miss)} 모자라 재료가 들어오면 짓는다.` : ''}${r.bad.length ? ` ${r.bad.length}칸은 못 놓았다(${r.bad[0].why}).` : ''}`);
    Sfx.play('pick');
    this.afterEdit();
  },
  afterEdit() { this.refreshWorld(); if (this.bm.tool === 'preset') this.showSpots(); this.renderBuild(); this.renderHud(); },
  /** 프리셋: 추천 자리 2~3곳을 반짝인다 */
  showSpots() {
    const bm = this.bm; if (!bm.preset) return;
    bm.spots = suggestSpots(bm.preset, bm.size, 3); this.sv?.setMarkers(bm.spots.map((s) => ({ x: s.x, y: s.y, w: s.w, h: s.h })));
  },
  /* ---------- 버튼 ---------- */
  buildAct(a, v) {
    const bm = this.bm; Sfx.play('ui');
    if (a === 'cat') { bm.cat = v; if (v === 'cut' || v === 'del') { bm.stage = 'draw'; this.setTool(v); } else { bm.stage = 'items'; this.setTool(null); } return; }
    if (a === 'back') { bm.stage = 'cats'; bm.cat = null; this.setTool(null); return; }
    if (a === 'stop') { bm.stage = bm.cat === 'cut' || bm.cat === 'del' ? 'cats' : 'items'; this.setTool(null); return; }
    if (a === 'item') {
      const [k, x] = v.split(':'); bm.stage = 'draw';
      if (k === 'draw') this.setTool('room');
      else if (k === 'copy') this.setTool('copy');
      else if (k === 'preset') { bm.preset = x; if (!PRESETS[x][bm.size]) bm.size = 'S'; this.setTool('preset'); this.showSpots(); if (!bm.spots.length) UI.toast('빛 안에 놓을 자리가 없다.'); this.renderBuild(); }
      else if (k === 'wall') { bm.wall = x; this.setTool('wall'); }
      else if (k === 'door') this.setTool('door');
      else if (k === 'floor') { bm.floor = x; this.setTool('floor'); }
      else if (k === 'furn') { bm.furn = x; this.setTool('furn'); }
      else if (k === 'zone') { bm.zone = x; this.setTool('zone'); }
      return;
    }
    if (a === 'size') { bm.size = v; this.showSpots(); }
    if (a === 'mat') { bm.wall = v; if (bm.tool === 'preset') this.showSpots(); }
    if (a === 'shape') bm.shape = v;
    if (a === 'rot') { bm.rot = (bm.rot + 1) % 4; if (bm.tool === 'paste' && bm.clip) bm.clip = rotateClip(bm.clip); if (bm.tool === 'preset') this.showSpots(); }
    if (a === 'flip' && bm.clip) bm.clip = flipClip(bm.clip);
    if (a === 'more') bm.more = !bm.more;
    if (a === 'auto') {
      const r = autoPlan();
      if (r.placed.length) UI.toast(`${jo(r.placed.map((k) => ROOMS[k].name).join(', '), '을를')} 청사진으로 놓았다. 주민이 짓는다.`); else if (!r.failed.length) UI.toast('지금은 모자란 방이 없다.');
      if (r.failed.length) UI.toast(`${jo(r.failed.map((k) => ROOMS[k].name).join(', '), '을를')} 놓을 자리가 없다.`);
      this.afterEdit(); return;
    }
    if (a === 'undo') { if (undo()) this.afterEdit(); return; }
    if (a === 'redo') { if (redo()) this.afterEdit(); return; }
    if (a === 'layer') { const k = LAYERS.findIndex(([m]) => m === bm.layer); bm.layer = LAYERS[(k + 1) % LAYERS.length][0]; this.sv?.setLayers(bm.layer); }
    if (a === 'exit') { this.exitBuild(); return; }
    this.renderBuild();
  },
  /** 지금 단계의 상태 줄 */
  buildStat() {
    const bm = this.bm, S = META.settle, stock = `🪵 ${S.stock.나무 || 0} · 🪨 ${S.stock.돌 || 0}`;
    if (bm.stage === 'cats') {
      const need = neededRooms(), left = S.bp.length, miss = missing(sumCost(S.bp), S);
      return `${stock}${left ? ` · <b style="color:#ff9a9a">청사진 ${left}개: ${missText(miss) || '재료'} 모자란다</b>` : need.length ? ` · 모자란 방: ${need.map(([k]) => ROOMS[k].name).join(', ')}` : ''}`;
    }
    if (bm.stage === 'items') return `${stock} · 무엇을 지을까`;
    if (bm.start && bm.pv) {
      const m = missing(bm.pv.cost, S);
      return `${bm.pv.ok.length}칸 · ${costText(bm.pv.cost, S)} · ${buildHours(bm.pv.ok)}시간${Object.keys(m).length ? ` · <b style="color:#ff8a8a">${missText(m)} 모자란다</b>` : ''}${bm.pv.bad.length ? ` · <b style="color:#ff8a8a">${bm.pv.bad[0].why}</b>` : ''}`;
    }
    if (bm.start) return '끝 칸을 누르거나 끌어서 사각형을 만든다.';
    const T = bm.tool;
    if (T === 'preset') { const s = bm.spots[0]; return s ? `${ROOMS[bm.preset].icon} ${SIZE_NAME[bm.size]} ${ROOMS[bm.preset].name} · 반짝이는 자리를 누른다 · ${costText(s.cost, S)}` : '놓을 자리가 없다. 나무를 베거나 크기를 줄이면 자리가 난다.'; }
    if (T === 'copy') return '떠 올 방을 누른다.';
    if (T === 'paste') return '붙일 자리(왼쪽 위)를 누른다.';
    if (T === 'furn') return `${FURN[bm.furn].icon} ${FURN[bm.furn].name} · 놓을 칸을 누른다 · ${costText(FURN[bm.furn].cost, S)}`;
    if (T === 'door') return '🚪 벽이나 빈칸을 누른다.';
    if (T === 'cut') return `${stock} · 나무·바위·광맥·폐허를 끌어서 고른다.`;
    if (T === 'del') return '끌어서 고른 곳을 철거한다. 재료 절반이 돌아온다.';
    if (T === 'zone') return `${bm.zone === 'erase' ? '구역 지우기' : ZONE_TYPES[bm.zone].name} · 끌어서 칠한다.`;
    return `${stock} · 끌거나 두 번 눌러 사각형을 그린다.`;
  },
  renderBuild() {
    const bm = this.bm, el = $('#buildbar'); if (!el || !bm) return;
    const btn = (a, v, label, cls = '') => `<button class="${cls}" data-a="${a}" data-v="${v ?? ''}">${label}</button>`;
    let body = '';
    if (bm.stage === 'cats') {
      body = `<div class="bcards">${CATS.map(([k, ic, n]) => btn('cat', k, `${ic}<small>${n}</small>`, 'bcard')).join('')}${btn('auto', '', '✨<small>알아서 짓기</small>', 'bcard')}${btn('exit', '', '✔<small>완료</small>', 'bcard done')}</div>`;
    } else if (bm.stage === 'items') {
      const S = META.settle, items = itemsOf(bm.cat).map(([v, ic, n, cost]) => btn('item', v, `<b>${ic}</b><small>${n}</small>${cost ? `<i style="color:${Object.keys(missing(cost, S)).length ? '#ff9a9a' : '#c8bca0'}">${resText(cost)}</i>` : ''}`, 'bitem')).join('');
      body = `<div class="bitems">${items}</div><div class="bdraw">${btn('back', '', '‹ 뒤로', 'wide')}</div>`;
    } else {
      const T = bm.tool, ctx = [];
      if (T === 'preset') { ctx.push(...Object.keys(PRESETS[bm.preset]).map((s) => btn('size', s, SIZE_NAME[s], bm.size === s ? 'on' : ''))); ctx.push(btn('mat', bm.wall === 'wood' ? 'stone' : 'wood', bm.wall === 'wood' ? '🪵 나무' : '🪨 돌')); }
      if (T === 'room') ctx.push(btn('mat', bm.wall === 'wood' ? 'stone' : 'wood', bm.wall === 'wood' ? '🪵 나무 벽' : '🪨 돌 벽'));
      if (T === 'wall') ctx.push(btn('shape', bm.shape === 'line' ? 'box' : 'line', bm.shape === 'line' ? '╱ 선' : '▢ 윤곽'));
      if (T === 'furn' || T === 'paste') ctx.push(btn('rot', '', `⟳ ${T === 'furn' ? `${bm.rot * 90}°` : '회전'}`));
      const more = bm.more ? `<div class="bdraw bmore">${btn('redo', '', '↷ 다시 하기', canRedo() ? '' : 'off')}${btn('layer', '', `👁 ${LAYERS.find(([m]) => m === bm.layer)[1]}`)}${T === 'paste' ? btn('flip', '', '⇋ 반전') : ''}</div>` : '';
      body = `${more}<div class="bdraw">${btn('undo', '', '↶', canUndo() ? 'sq' : 'sq off')}${ctx.join('')}<span style="flex:1"></span>${btn('more', '', '⋯', 'sq')}${btn('stop', '', '✕ 그만', 'stop')}</div>`;
    }
    el.innerHTML = `<div id="bstat">${this.buildStat()}</div>${body}`;
    el.querySelectorAll('[data-a]').forEach((b) => { b.onclick = () => { if (!b.classList.contains('off')) this.buildAct(b.dataset.a, b.dataset.v); }; });
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
