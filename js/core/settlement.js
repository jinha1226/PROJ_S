import { FLOOR_BY_ID, FLOOR_TYPES, FURN, PRESETS, ROOMS, SCX, SCY, SH, START_STOCK, SW, TERRAIN, TR, UNDO_MAX, WALLS, WALL_BY_ID, ZONE_TYPES, lightRadius } from '../data/build.js';
import { JOBS } from '../data/town.js';
import { mulberry32 } from '../util/rng.js';
import { ensureNearResources } from './colony.js';
import { META, saveMeta } from './meta.js';
import { detectRooms, furnCells, furnSize } from './rooms.js';
import { hearthGlow, shardCount } from './visitors.js';

/* ================= 정착지 땅과 건설 (docs/설계_정착지_건설.md 1단계) =================
   META.settle = { W, H, cx, cy, terr[], floor[], wall[], zone[], furn[{id,k,x,y,rot}], bp[{id,L,k,x,y,rot}], stock{나무,돌}, nid }
   모든 것은 먼저 청사진(bp)으로 놓이고 [짓기]로 실체가 된다(1단계는 즉시 완료, 주민 작업 없음). */
const I = (x, y) => y * SW + x;
export const inMap = (x, y) => x >= 0 && y >= 0 && x < SW && y < SH;
const st = () => META.settle;
const LAYER = { floor: 0, wall: 1, furn: 2 };

/** 지을 수 있는 반경: 6 + 모닥불 밝기 ÷ 10 */
export const radius = () => (META && META.npcs ? lightRadius(hearthGlow(), shardCount()) : lightRadius(0)); // + 등불 조각마다 3칸
export const inLight = (x, y, R = radius()) => (x - SCX) ** 2 + (y - SCY) ** 2 <= R * R + R;
/** 모닥불 곁 한 칸은 비워 둔다 */
const nearFire = (x, y) => Math.abs(x - SCX) <= 1 && Math.abs(y - SCY) <= 1;

/* ---------- 새 땅 ---------- */
export function newSettle(seed = Date.now()) {
  const r = mulberry32(seed >>> 0), N = SW * SH, ri = (a, b) => a + Math.floor(r() * (b - a + 1));
  const S = { v: 1, W: SW, H: SH, cx: SCX, cy: SCY, terr: new Array(N).fill(TR.grass), floor: new Array(N).fill(0), wall: new Array(N).fill(0), zone: new Array(N).fill(0), furn: [], bp: [], stock: { ...START_STOCK }, nid: 1 };
  const far = (x, y, d) => (x - SCX) ** 2 + (y - SCY) ** 2 >= d * d;
  const blob = (t, n, rMin, rMax, avoid, dens, only = [TR.grass, TR.dirt]) => {
    for (let k = 0, made = 0; k < n * 20 && made < n; k++) {
      const x = ri(1, SW - 2), y = ri(1, SH - 2), rad = ri(rMin, rMax); if (!far(x, y, avoid + rad)) continue; made++;
      for (let dy = -rad; dy <= rad; dy++) for (let dx = -rad; dx <= rad; dx++) { const X = x + dx, Y = y + dy; if (!inMap(X, Y) || dx * dx + dy * dy > rad * rad + 1 || r() > dens) continue; if (only.includes(S.terr[I(X, Y)])) S.terr[I(X, Y)] = t; }
    }
  };
  blob(TR.dirt, 14, 1, 3, 0, 0.8);
  blob(TR.water, 2, 2, 3, 11, 1);
  blob(TR.ruin, 4, 1, 2, 6, 0.75);
  blob(TR.tree, 26, 1, 3, 8, 0.55); // 처음 빛(반경 7) 안은 대체로 비워 둔다
  blob(TR.rock, 9, 1, 2, 8, 0.8);
  for (let k = 0, made = 0; k < 200 && made < 7; k++) { const a = r() * 6.28, d = 4.5 + r() * 2.5, x = Math.round(SCX + Math.cos(a) * d), y = Math.round(SCY + Math.sin(a) * d), i = I(x, y); if (S.terr[i] === TR.grass) { S.terr[i] = made < 5 ? TR.tree : TR.rock; made++; } } // 가까이에 벨 나무 몇 그루
  for (let k = 0, made = 0; k < 400 && made < 6; k++) { const i = ri(0, N - 1); if (S.terr[i] === TR.rock && r() < 0.5) { S.terr[i] = TR.ore; made++; } } // 광맥은 바위 사이에 드물게
  for (let y = SCY - 3; y <= SCY + 3; y++) for (let x = SCX - 3; x <= SCX + 3; x++) S.terr[I(x, y)] = Math.abs(x - SCX) + Math.abs(y - SCY) <= 2 ? TR.dirt : TR.grass;
  S.furn.push({ id: 'f' + S.nid++, k: 'gate', x: SCX, y: SCY - 5, rot: 0 }, { id: 'f' + S.nid++, k: 'heap', x: SCX + 2, y: SCY + 1, rot: 0 });
  S.terr[I(SCX, SCY - 5)] = TR.dirt; S.terr[I(SCX + 2, SCY + 1)] = TR.dirt;
  const alt = edgeSpot('altar', S, 7); if (alt) buildFree(alt.bps, S);
  ensureNearResources(S, seed); // 근처 자원을 넉넉히(docs/설계_정착지_2단계.md §5)
  return S;
}

/* ---------- 칸 판정 ---------- */
/** 칸마다 무엇이 있는지(지어진 것 + 청사진) */
function ctxOf(S, R = radius()) {
  const occ = new Map(), bpWall = new Map(), bpFloor = new Map(), bpFurn = new Map();
  for (const f of S.furn) for (const [x, y] of furnCells(f)) occ.set(I(x, y), f);
  for (const b of S.bp) {
    if (b.L === 'wall') bpWall.set(I(b.x, b.y), b); else if (b.L === 'floor') bpFloor.set(I(b.x, b.y), b);
    else for (const [x, y] of furnCells(b)) bpFurn.set(I(x, y), b);
  }
  return { S, R, occ, bpWall, bpFloor, bpFurn };
}
/** 이 칸에 이 층을 놓을 수 없는 까닭(없으면 null). 이미 같은 것이 있으면 'same' */
function cellWhy(c, x, y, L, k) {
  const S = c.S; if (!inMap(x, y)) return '지도 밖이다';
  const i = I(x, y);
  if (!inLight(x, y, c.R)) return '빛이 닿지 않는 곳이다';
  if (nearFire(x, y)) return '모닥불 곁은 비워 둔다';
  const T = TERRAIN[S.terr[i]]; if (!T.build) return T.why;
  if (L === 'wall') {
    if (c.occ.has(i) || c.bpFurn.has(i)) return '가구가 있다';
    const w = S.wall[i], bw = c.bpWall.get(i);
    if (k === 'door') { if (w === WALLS.door.id || (bw && bw.k === 'door')) return 'same'; return null; } // 문은 벽을 바꿔 단다
    if (w || bw) return 'same';
  } else if (L === 'floor') {
    if (S.floor[i] === FLOOR_TYPES[k].id || c.bpFloor.has(i)) return 'same';
  } else {
    if (S.wall[i] || c.bpWall.has(i)) return '벽이 있다';
    if (c.occ.has(i) || c.bpFurn.has(i)) return '다른 가구가 있다';
  }
  return null;
}
const bpCells = (b) => (b.L === 'furn' ? furnCells(b) : [[b.x, b.y]]);
export const costOf = (b) => (b.L === 'wall' ? WALLS[b.k].cost : b.L === 'floor' ? FLOOR_TYPES[b.k].cost : FURN[b.k].cost);
export function sumCost(list) { const out = {}; for (const b of list) for (const [m, n] of Object.entries(costOf(b))) out[m] = (out[m] || 0) + n; return out; }
export const stockOf = (m, S = st()) => (m in START_STOCK ? S.stock[m] || 0 : (META.mats && META.mats[m]) || 0);
/** 모자란 재료 { 나무: 3 } */
export function missing(cost, S = st()) { const out = {}; for (const [m, n] of Object.entries(cost)) { const d = n - stockOf(m, S); if (d > 0) out[m] = d; } return out; }
function pay(cost, S, sign = -1) { for (const [m, n] of Object.entries(cost)) { if (m in START_STOCK) S.stock[m] = (S.stock[m] || 0) + sign * n; else META.mats[m] = (META.mats[m] || 0) + sign * n; } }
/** 재고에 더하기(나무·돌·식량·식사는 정착지, 나머지는 재료 창고) */
export function addStock(m, n, S = st()) { pay({ [m]: n }, S, 1); }
/** 청사진 하나를 실체로(비용은 이미 치렀다): 주민의 짓기가 끝났을 때 */
export function finishBp(b, S = st()) { apply(b, S); S.bp = S.bp.filter((q) => q !== b); changed(); }
/** 청사진 비용을 치른다(짓기 시작할 때). 모자라면 false */
export function payBp(b, S = st()) { const c = costOf(b); if (Object.keys(missing(c, S)).length) return false; pay(c, S); b.paid = true; return true; }
export const bpHours = (b) => (b.L === 'wall' ? WALLS[b.k].t : b.L === 'floor' ? FLOOR_TYPES[b.k].t : FURN[b.k].t);
/** 작업방 등급: 1 + 그 방 등급 가구(FURN.tier) */
export function roomTier(r) { if (!r || !r.kind) return 0; let t = 1; for (const k of Object.keys(r.furn)) { const T = FURN[k].tier; if (T && T[0] === r.kind) t = Math.max(t, T[1]); } return t; }
export const buildHours = (list) => list.reduce((a, b) => a + (b.L === 'wall' ? WALLS[b.k].t : b.L === 'floor' ? FLOOR_TYPES[b.k].t : FURN[b.k].t), 0);

/** 청사진 미리보기: 놓을 수 있는 것(ok)과 없는 것(bad, 까닭). 이미 있는 것은 빠진다 */
export function checkBps(list, S = st(), c = ctxOf(S)) {
  const ok = [], bad = [];
  for (const b of list) {
    let why = null;
    for (const [x, y] of bpCells(b)) { const w = cellWhy(c, x, y, b.L, b.k); if (w) { why = w; break; } }
    if (why === 'same') continue;
    if (why) { bad.push({ ...b, why }); continue; }
    ok.push(b);
    if (b.L === 'wall') c.bpWall.set(I(b.x, b.y), b); else if (b.L === 'floor') c.bpFloor.set(I(b.x, b.y), b); else for (const [x, y] of furnCells(b)) c.bpFurn.set(I(x, y), b);
  }
  return { ok, bad, cost: sumCost(ok) };
}

/* ---------- 되돌리기 (건설 모드 안, 20단계) ---------- */
const hist = { undo: [], redo: [] };
const snap = () => JSON.stringify({ s: META.settle, m: META.mats });
function restore(js) { const o = JSON.parse(js); META.settle = o.s; META.mats = o.m; changed(); }
/** 바꾸기 전에 부른다 */
export function record() { hist.undo.push(snap()); if (hist.undo.length > UNDO_MAX) hist.undo.shift(); hist.redo = []; }
export function undo() { if (!hist.undo.length) return false; hist.redo.push(snap()); restore(hist.undo.pop()); return true; }
export function redo() { if (!hist.redo.length) return false; hist.undo.push(snap()); restore(hist.redo.pop()); return true; }
export const canUndo = () => hist.undo.length > 0, canRedo = () => hist.redo.length > 0;
export function clearHistory() { hist.undo = []; hist.redo = []; }

/* ---------- 방 · 건물 ---------- */
let roomCache = null;
function changed() { roomCache = null; syncBuildings(); saveMeta(); }
/** 땅을 밖에서 바꿨거나 저장을 새로 읽었을 때 */
export function invalidate() { roomCache = null; syncBuildings(); }
export const rooms = () => (roomCache ||= detectRooms(st()));
export const roomAt = (x, y) => rooms().find((r) => r.cells.has(I(x, y))) || null;
export const hasRoom = (kind) => rooms().some((r) => r.kind === kind);
export const roomOf = (kind) => rooms().find((r) => r.kind === kind) || null;
export const furnAt = (x, y, S = st()) => S.furn.find((f) => furnCells(f).some(([a, b]) => a === x && b === y)) || null;
/** 제작·사건이 보는 META.buildings를 방에서 다시 만든다(모닥불·출발문·창고 더미·제단은 늘 있다) */
export function syncBuildings() {
  if (!META || !META.settle) return;
  const b = { plaza: { shown: true }, gate: { shown: true }, storage: { shown: true }, altar: { shown: true } };
  for (const r of rooms()) if (r.kind && !b[r.kind]) b[r.kind] = { shown: true };
  META.buildings = b;
}

/* ---------- 놓기 · 짓기 · 베기 · 철거 ---------- */
/** 청사진을 놓는다. 놓지 못한 것은 까닭과 함께 돌려준다 */
export function placeBps(list, S = st()) {
  const r = checkBps(list, S); if (!r.ok.length) return r;
  if (S === st()) record();
  for (const b of r.ok) S.bp.push({ id: 'b' + S.nid++, L: b.L, k: b.k, x: b.x, y: b.y, rot: b.rot || 0 });
  if (S === st()) changed();
  return r;
}
function apply(b, S) {
  const i = I(b.x, b.y);
  if (b.L === 'floor') S.floor[i] = FLOOR_TYPES[b.k].id;
  else if (b.L === 'wall') S.wall[i] = WALLS[b.k].id;
  else S.furn.push({ id: 'f' + S.nid++, k: b.k, x: b.x, y: b.y, rot: b.rot || 0 });
}
/** 비용 없이 바로 짓는다(새 땅의 제단, 옛 마을 옮기기) */
export function buildFree(list, S = st()) { const r = checkBps(list, S, ctxOf(S, 99)); for (const b of r.ok) apply(b, S); if (S === st()) changed(); return r.ok.length; }
/** 짓기: 청사진을 바닥 → 벽 → 가구 순으로, 재료가 되는 만큼 짓는다. 남은 것과 모자란 재료를 돌려준다.
    rec = false면 바로 앞 조작(놓기·베기)과 한 번의 되돌리기로 묶인다 */
export function commit(S = st(), rec = true) {
  if (!S.bp.length) return { built: 0, left: 0, missing: {} };
  if (rec) record();
  const order = S.bp.map((b, k) => [b, k]).sort((a, b) => LAYER[a[0].L] - LAYER[b[0].L] || a[1] - b[1]).map(([b]) => b), left = [], need = {};
  let built = 0;
  for (const b of order) {
    const cost = costOf(b), miss = missing(cost, S);
    if (Object.keys(miss).length) { left.push(b); for (const [m, n] of Object.entries(cost)) need[m] = (need[m] || 0) + n; continue; }
    pay(cost, S); apply(b, S); built++;
  }
  S.bp = S.bp.filter((b) => left.includes(b));
  changed();
  return { built, left: left.length, missing: missing(need, S) };
}
/** 사각형 안의 나무·바위·광맥·폐허를 바로 베고 캔다(1단계) */
export function cutArea(x0, y0, x1, y1, S = st()) {
  const gained = {}, R = radius(); let n = 0, rec = false;
  for (let y = Math.min(y0, y1); y <= Math.max(y0, y1); y++) for (let x = Math.min(x0, x1); x <= Math.max(x0, x1); x++) {
    if (!inMap(x, y) || !inLight(x, y, R)) continue;
    const i = I(x, y), T = TERRAIN[S.terr[i]]; if (!T.cut || S.wall[i] || S.floor[i]) continue;
    if (!rec) { record(); rec = true; }
    const got = { ...T.cut }; if (T.bonus && Math.random() < T.bonus[1]) got[T.bonus[0]] = (got[T.bonus[0]] || 0) + 1;
    pay(got, S, 1); for (const [m, v] of Object.entries(got)) gained[m] = (gained[m] || 0) + v;
    S.terr[i] = S.terr[i] === TR.tree ? TR.grass : TR.dirt; n++;
  }
  if (n) changed();
  return { n, gained };
}
/** 사각형 안을 철거: 청사진은 바로 취소, 지은 것은 재료 절반이 돌아온다. 하나뿐인 것(제단·출발문·더미)은 남는다 */
export function demolish(x0, y0, x1, y1, S = st()) {
  const X0 = Math.min(x0, x1), X1 = Math.max(x0, x1), Y0 = Math.min(y0, y1), Y1 = Math.max(y0, y1), inR = (x, y) => x >= X0 && x <= X1 && y >= Y0 && y <= Y1;
  const bps = S.bp.filter((b) => bpCells(b).some(([x, y]) => inR(x, y))), fs = S.furn.filter((f) => !FURN[f.k].unique && furnCells(f).some(([x, y]) => inR(x, y)));
  let cells = 0; for (let y = Y0; y <= Y1; y++) for (let x = X0; x <= X1; x++) if (inMap(x, y) && (S.wall[I(x, y)] || S.floor[I(x, y)] || S.zone[I(x, y)])) cells++;
  if (!bps.length && !fs.length && !cells) return { n: 0, back: {} };
  record();
  const back = {}, give = (cost) => { for (const [m, n] of Object.entries(cost)) { const h = Math.floor(n / 2); if (h) back[m] = (back[m] || 0) + h; } };
  S.bp = S.bp.filter((b) => !bps.includes(b));
  for (const f of fs) give(FURN[f.k].cost); S.furn = S.furn.filter((f) => !fs.includes(f));
  for (let y = Y0; y <= Y1; y++) for (let x = X0; x <= X1; x++) {
    if (!inMap(x, y)) continue; const i = I(x, y);
    if (S.wall[i]) { give(WALLS[WALL_BY_ID[S.wall[i]]].cost); S.wall[i] = 0; }
    if (S.floor[i]) { give(FLOOR_TYPES[FLOOR_BY_ID[S.floor[i]]].cost); S.floor[i] = 0; }
    S.zone[i] = 0;
  }
  pay(back, S, 1); changed();
  return { n: bps.length + fs.length + cells, back };
}
/** 구역 칠하기(비용 없음). k = null이면 지운다 */
export function paintZone(x0, y0, x1, y1, k, S = st()) {
  const id = k ? ZONE_TYPES[k].id : 0, R = radius(), cells = [];
  for (let y = Math.min(y0, y1); y <= Math.max(y0, y1); y++) for (let x = Math.min(x0, x1); x <= Math.max(x0, x1); x++) {
    if (!inMap(x, y)) continue; const i = I(x, y);
    if (id && (!inLight(x, y, R) || !TERRAIN[S.terr[i]].build || S.wall[i])) continue;
    if (S.zone[i] !== id) cells.push(i);
  }
  if (!cells.length) return 0;
  record(); for (const i of cells) S.zone[i] = id; changed();
  return cells.length;
}

/* ---------- 방 그리기 · 선 · 채우기 ---------- */
const rectOf = (x0, y0, x1, y1) => [Math.min(x0, x1), Math.min(y0, y1), Math.max(x0, x1), Math.max(y0, y1)];
/** 문 자리: 모닥불 쪽 벽 가운데 */
function doorOf(X0, Y0, X1, Y1) {
  const mx = (X0 + X1) / 2, my = (Y0 + Y1) / 2, dx = SCX - mx, dy = SCY - my;
  if (Math.abs(dx) > Math.abs(dy)) return [dx > 0 ? X1 : X0, Math.floor(my)];
  return [Math.floor(mx), dy > 0 ? Y1 : Y0];
}
/** 방 그리기: 사각 윤곽 벽 + 안쪽 바닥 + 문 하나 (3×3 이상) */
export function roomBps(x0, y0, x1, y1, wall = 'wood', floor = 'wood') {
  const [X0, Y0, X1, Y1] = rectOf(x0, y0, x1, y1); if (X1 - X0 < 2 || Y1 - Y0 < 2) return [];
  const [dx, dy] = doorOf(X0, Y0, X1, Y1), out = [];
  for (let y = Y0; y <= Y1; y++) for (let x = X0; x <= X1; x++) {
    const edge = x === X0 || x === X1 || y === Y0 || y === Y1;
    if (!edge) out.push({ L: 'floor', k: floor, x, y });
    else out.push({ L: 'wall', k: x === dx && y === dy ? 'door' : wall, x, y });
  }
  return out;
}
/** 선: 가로 또는 세로로 곧게(더 긴 쪽) */
export function lineBps(x0, y0, x1, y1, L, k) {
  const out = [], hor = Math.abs(x1 - x0) >= Math.abs(y1 - y0);
  if (hor) for (let x = Math.min(x0, x1); x <= Math.max(x0, x1); x++) out.push({ L, k, x, y: y0 });
  else for (let y = Math.min(y0, y1); y <= Math.max(y0, y1); y++) out.push({ L, k, x: x0, y });
  return out;
}
/** 채우기(바닥) · 윤곽(벽) */
export function fillBps(x0, y0, x1, y1, L, k, outline = false) {
  const [X0, Y0, X1, Y1] = rectOf(x0, y0, x1, y1), out = [];
  for (let y = Y0; y <= Y1; y++) for (let x = X0; x <= X1; x++) if (!outline || x === X0 || x === X1 || y === Y0 || y === Y1) out.push({ L, k, x, y });
  return out;
}

/* ---------- 방 프리셋 · 추천 자리 · 알아서 짓기 ---------- */
/** 방 안에 가구를 놓는다: 문에서 먼 칸부터, 문 앞 한 칸은 비운다 */
function layoutFurn(X0, Y0, X1, Y1, door, list) {
  const [ddx, ddy] = door, taken = new Set(), out = [];
  const front = [ddx === X0 ? ddx + 1 : ddx === X1 ? ddx - 1 : ddx, ddy === Y0 ? ddy + 1 : ddy === Y1 ? ddy - 1 : ddy];
  taken.add(I(...front));
  const spots = []; for (let y = Y0 + 1; y < Y1; y++) for (let x = X0 + 1; x < X1; x++) spots.push([x, y]);
  spots.sort((a, b) => (b[0] - ddx) ** 2 + (b[1] - ddy) ** 2 - ((a[0] - ddx) ** 2 + (a[1] - ddy) ** 2));
  for (const k of list) {
    let put = null;
    for (const rot of [0, 1]) {
      const [w, h] = furnSize(k, rot);
      for (const [x, y] of spots) {
        if (x + w - 1 >= X1 || y + h - 1 >= Y1) continue;
        let ok = true; for (let dy = 0; dy < h && ok; dy++) for (let dx = 0; dx < w; dx++) if (taken.has(I(x + dx, y + dy))) { ok = false; break; }
        if (ok) { put = { L: 'furn', k, x, y, rot }; break; }
      }
      if (put) break;
    }
    if (!put) return null;
    for (const [x, y] of furnCells(put)) taken.add(I(x, y)); out.push(put);
  }
  return out;
}
/** 프리셋 방 하나의 청사진(x, y = 왼쪽 위, rot 1이면 가로·세로 바꿈) */
export function presetBps(kind, size, x, y, rot = 0, wall = 'wood') {
  const P = PRESETS[kind][size]; if (!P) return [];
  const [w, h] = rot % 2 ? [P[1], P[0]] : [P[0], P[1]], X1 = x + w - 1, Y1 = y + h - 1;
  const base = roomBps(x, y, X1, Y1, wall, 'wood'), door = base.find((b) => b.k === 'door'), fs = layoutFurn(x, y, X1, Y1, [door.x, door.y], P[2]);
  return fs ? [...base, ...fs] : [];
}
/** 추천 자리 n곳: 빛 안의 빈 곳 중 모닥불과 가깝고 기존 벽을 많이 나눠 쓰는 곳 */
export function suggestSpots(kind, size, n = 3, S = st(), R = radius()) {
  const P = PRESETS[kind] && PRESETS[kind][size]; if (!P) return [];
  const c = ctxOf(S, R), cand = [];
  for (const rot of P[0] === P[1] ? [0] : [0, 1]) {
    const [w, h] = rot ? [P[1], P[0]] : [P[0], P[1]];
    for (let y = 1; y + h <= SH - 1; y++) for (let x = 1; x + w <= SW - 1; x++) {
      const mx = x + w / 2 - 0.5, my = y + h / 2 - 0.5, d = Math.hypot(mx - SCX, my - SCY); if (d > R) continue;
      let ok = true, shared = 0;
      for (let yy = y; yy < y + h && ok; yy++) for (let xx = x; xx < x + w; xx++) {
        const edge = xx === x || xx === x + w - 1 || yy === y || yy === y + h - 1, i = I(xx, yy);
        const why = cellWhy(c, xx, yy, edge ? 'wall' : 'furn', 'wood');
        if (edge && why === 'same') { if (S.wall[i]) shared++; continue; }
        if (why || (!edge && (S.floor[i] || c.bpFloor.has(i)))) { ok = false; break; }
      }
      if (!ok) continue;
      cand.push({ x, y, w, h, rot, score: d - shared * 0.6 });
    }
  }
  cand.sort((a, b) => a.score - b.score);
  const out = [];
  for (const q of cand) {
    if (out.some((o) => q.x < o.x + o.w + 1 && o.x < q.x + q.w + 1 && q.y < o.y + o.h + 1 && o.y < q.y + q.h + 1)) continue;
    const bps = presetBps(kind, size, q.x, q.y, q.rot); if (!bps.length) continue;
    const chk = checkBps(bps, S, ctxOf(S, R)); if (chk.bad.length) continue;
    out.push({ ...q, bps, cost: chk.cost }); if (out.length >= n) break;
  }
  return out;
}
/** 가구 수(지은 것 + 청사진) */
function furnCount(S = st()) { const c = {}; for (const f of [...S.furn, ...S.bp.filter((b) => b.L === 'furn')]) c[f.k] = (c[f.k] || 0) + 1; return c; }
/** 지금 모자란 방: 주민 수만큼 침대, 주민 직업의 작업방 */
export function neededRooms(S = st()) {
  const c = furnCount(S), out = [], beds = META.npcs.length - (c.bed || 0);
  if (beds > 0) out.push(['bedroom', beds >= 4 ? 'L' : beds >= 2 ? 'M' : 'S']);
  for (const b of new Set(META.npcs.map((n) => JOBS[n.job].b).filter(Boolean))) {
    const R = ROOMS[b]; if (!R || b === 'bedroom') continue;
    if (Object.keys(R.need).some((k) => !c[k])) out.push([b, 'M']);
  }
  return out;
}
/** [알아서 짓기]: 모자란 방을 추천 자리에 한 번에 청사진으로 */
export function autoPlan(S = st()) {
  const need = neededRooms(S), placed = [], failed = [];
  if (!need.length) return { placed, failed };
  record(); const h = hist.undo.pop();
  for (const [kind, size] of need) {
    const spot = suggestSpots(kind, size, 1, S)[0] || (size !== 'S' && suggestSpots(kind, 'S', 1, S)[0]);
    if (!spot) { failed.push(kind); continue; }
    for (const b of checkBps(spot.bps, S).ok) S.bp.push({ id: 'b' + S.nid++, L: b.L, k: b.k, x: b.x, y: b.y, rot: b.rot || 0 });
    placed.push(kind);
  }
  if (placed.length) { hist.undo.push(h); hist.redo = []; changed(); }
  return { placed, failed };
}

/* ---------- 복사 · 붙여넣기 · 회전 · 반전 (방 단위) ---------- */
/** 지어진 방 하나(벽 포함)를 떠 온다 */
export function copyRoom(x, y, S = st()) {
  const r = roomAt(x, y); if (!r) return null;
  const X0 = r.x0 - 1, Y0 = r.y0 - 1, w = r.x1 - r.x0 + 3, h = r.y1 - r.y0 + 3, cells = [], furn = [];
  const near = (xx, yy) => { for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) if (r.cells.has(I(xx + dx, yy + dy))) return true; return false; };
  for (let yy = Y0; yy < Y0 + h; yy++) for (let xx = X0; xx < X0 + w; xx++) {
    const i = I(xx, yy);
    if (S.wall[i] && near(xx, yy)) cells.push({ dx: xx - X0, dy: yy - Y0, wall: WALL_BY_ID[S.wall[i]] });
    else if (r.cells.has(i) && S.floor[i]) cells.push({ dx: xx - X0, dy: yy - Y0, floor: FLOOR_BY_ID[S.floor[i]] });
  }
  for (const f of S.furn) if (r.cells.has(I(f.x, f.y)) && !FURN[f.k].unique) furn.push({ k: f.k, dx: f.x - X0, dy: f.y - Y0, rot: f.rot || 0 });
  return { w, h, cells, furn, kind: r.kind };
}
/** 시계 방향 90° */
export function rotateClip(c) {
  return { ...c, w: c.h, h: c.w, cells: c.cells.map((q) => ({ ...q, dx: c.h - 1 - q.dy, dy: q.dx })),
    furn: c.furn.map((f) => { const [, fh] = furnSize(f.k, f.rot); return { ...f, dx: c.h - f.dy - fh, dy: f.dx, rot: (f.rot + 1) % 4 }; }) };
}
/** 좌우 반전 */
export function flipClip(c) {
  return { ...c, cells: c.cells.map((q) => ({ ...q, dx: c.w - 1 - q.dx })), furn: c.furn.map((f) => { const [fw] = furnSize(f.k, f.rot); return { ...f, dx: c.w - f.dx - fw }; }) };
}
/** 붙여넣을 청사진(x, y = 왼쪽 위) */
export function clipBps(c, x, y) {
  return [...c.cells.map((q) => (q.wall ? { L: 'wall', k: q.wall, x: x + q.dx, y: y + q.dy } : { L: 'floor', k: q.floor, x: x + q.dx, y: y + q.dy })), ...c.furn.map((f) => ({ L: 'furn', k: f.k, x: x + f.dx, y: y + f.dy, rot: f.rot }))];
}

/* ---------- 옛 마을 옮기기 (저장 v9) ---------- */
/** 처음부터 있는 방은 빛 가장자리 쪽에 둔다(모닥불 둘레를 비워 두려고) */
function edgeSpot(kind, S, R = radius()) { const all = suggestSpots(kind, 'S', 60, S, R); return all[all.length - 1] || null; }
/** 고정 건물(대장간·약초 공방 …)을 같은 기능의 작은 방 프리셋으로, 비용 없이 지어 둔다 */
export function migrateTown(M) {
  const old = Object.keys(M.buildings || {});
  M.settle = newSettle();
  for (const b of ['forge', 'herb', 'library', 'inn']) { // 창고는 모닥불 옆 재료 더미가 맡는다
    if (!old.includes(b)) continue;
    const spot = edgeSpot(b, M.settle) || suggestSpots(b, 'S', 1, M.settle, 20)[0]; if (spot) buildFree(spot.bps, M.settle);
  }
  if (M === META) invalidate();
}
