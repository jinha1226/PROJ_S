import { RT } from '../data/realtime.js';
import { S_WATER, T_DOOR, T_WALL } from '../data/terrain.js';
import { G, I, inb } from './state.js';

/* ================= 공간: 소수 위치 · 원형 충돌 · 길찾기 (docs/설계_실시간_전환.md §3) =================
   px, py = 실제 위치(칸 중심이 정수). x, y = 늘 그 반올림(발밑 칸). 칸으로 판정하는 규칙은 x, y를 그대로 쓴다. */
export const posOf = (e) => [e.px ?? e.x, e.py ?? e.y];
export const rad = (e) => (e.boss ? RT.bossRadius : RT.radius[e.type] ?? 0.3);
export const distXY = (ax, ay, bx, by) => Math.hypot(ax - bx, ay - by);
export function setPos(e, x, y) { e.px = x; e.py = y; e.x = Math.round(x); e.y = Math.round(y); }
export const solid = (tx, ty) => { if (!inb(tx, ty)) return true; const t = G.tile[I(tx, ty)]; return t === T_WALL || t === T_DOOR; };
const hardWall = (tx, ty) => !inb(tx, ty) || G.tile[I(tx, ty)] === T_WALL;

/** 원(x,y,r)이 벽 칸과 겹치면 밀어낸다. 닫힌 문에 닿으면 onDoor(tx,ty) */
function pushOutWalls(x, y, r, onDoor) {
  for (let it = 0; it < 3; it++) {
    let moved = false;
    for (let ty = Math.floor(y - r - 0.5); ty <= Math.ceil(y + r + 0.5); ty++) for (let tx = Math.floor(x - r - 0.5); tx <= Math.ceil(x + r + 0.5); tx++) {
      if (!solid(tx, ty)) continue;
      const cx = Math.max(tx - 0.5, Math.min(x, tx + 0.5)), cy = Math.max(ty - 0.5, Math.min(y, ty + 0.5));
      const dx = x - cx, dy = y - cy, d = Math.hypot(dx, dy);
      if (d >= r) continue;
      if (onDoor && inb(tx, ty) && G.tile[I(tx, ty)] === T_DOOR) onDoor(tx, ty);
      if (d > 1e-6) { x = cx + (dx / d) * r; y = cy + (dy / d) * r; } else { x += 0.01; }
      moved = true;
    }
    if (!moved) break;
  }
  return [x, y];
}
/** 다른 몸과 겹치지 않게(움직이는 쪽만 밀린다). ghost면 동료·구한 사람은 지나간다 */
function pushOutBodies(e, x, y, ghost) {
  let hit = null; const r = rad(e);
  for (const o of G.ents) {
    if (o === e || !o.alive || (ghost && (o.ally || (o.npc && o.freed)))) continue;
    const [ox, oy] = posOf(o), dx = x - ox, dy = y - oy, d = Math.hypot(dx, dy), m = r + rad(o);
    if (d >= m) continue;
    hit = o; if (d > 1e-6) { x = ox + (dx / d) * m; y = oy + (dy / d) * m; } else x += 0.01;
  }
  return [x, y, hit];
}
/** e를 (dx,dy)만큼 움직인다: 벽을 따라 미끄러지고 몸끼리는 막힌다. 새 위치와 부딪힌 것을 돌려준다(e는 바꾸지 않는다) */
export function sweep(e, dx, dy, o = {}) {
  let [x, y] = posOf(e); const r = rad(e), n = Math.max(1, Math.ceil(Math.hypot(dx, dy) / 0.1));
  let wall = false, body = null;
  for (let k = 0; k < n; k++) {
    const tx = x + dx / n, ty = y + dy / n;
    let [nx, ny] = pushOutWalls(tx, ty, r, o.onDoor);
    if (Math.hypot(nx - tx, ny - ty) > 0.02) wall = true;
    let hit; [nx, ny, hit] = pushOutBodies(e, nx, ny, o.ghost);
    if (hit) body = hit;
    x = nx; y = ny;
  }
  return { x, y, wall, body };
}
/** 두 점 사이를 반지름 r 원이 벽에 걸리지 않고 지나가는가 */
function segClear(ax, ay, bx, by, r) {
  const n = Math.max(1, Math.ceil(Math.hypot(bx - ax, by - ay) / 0.15));
  for (let k = 0; k <= n; k++) { const x = ax + ((bx - ax) * k) / n, y = ay + ((by - ay) * k) / n, [px, py] = pushOutWalls(x, y, r); if (Math.hypot(px - x, py - y) > 0.01) return false; }
  return true;
}

/* ---------- 길: 칸 Dijkstra(물 ×RT.waterCost) → 줄 당기기 ---------- */
const D8 = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]];
/** e에서 갈 수 있는 칸까지의 비용. seenOnly = 본 칸·불 없는 칸만(자동 걷기). 보이는 몸이 선 칸은 못 지나간다(allow 칸은 예외) */
export function costMap(e, budget = 400, o = {}) {
  const N = G.W * G.H, cost = new Float32Array(N).fill(Infinity), prev = new Int32Array(N).fill(-1);
  const occ = new Set(); for (const q of G.ents) if (q !== e && q.alive && !(o.passAllies && (q.ally || q.npc)) && (!o.seenOnly || G.vis[I(q.x, q.y)])) occ.add(I(q.x, q.y));
  const [sx, sy] = posOf(e), s = I(Math.round(sx), Math.round(sy));
  cost[s] = 0; const open = [s];
  while (open.length) {
    let bi = 0; for (let k = 1; k < open.length; k++) if (cost[open[k]] < cost[open[bi]]) bi = k;
    const i = open.splice(bi, 1)[0], x = i % G.W, y = (i / G.W) | 0;
    for (const [dx, dy] of D8) {
      const nx = x + dx, ny = y + dy; if (hardWall(nx, ny)) continue;
      if (dx && dy && (hardWall(x + dx, y) || hardWall(x, y + dy))) continue; // 모서리를 비스듬히 못 자른다
      const j = I(nx, ny); if (occ.has(j) && j !== o.allow) continue;
      if (o.seenOnly && (!G.seen[j] || G.fire[j])) continue;
      const c = cost[i] + (dx && dy ? Math.SQRT2 : 1) * (G.surf[j] === S_WATER ? RT.waterCost : 1);
      if (c >= cost[j] || c > budget) continue;
      cost[j] = c; prev[j] = i; open.push(j);
    }
  }
  return { cost, prev, start: s };
}
/** 칸 경로 → 실제로 걸을 점들(줄 당기기). 첫 점은 지금 위치, 끝점은 (tx,ty) */
export function pathPoints(e, cm, tx, ty) {
  const ti = I(Math.round(tx), Math.round(ty)); if (!isFinite(cm.cost[ti])) return null;
  const tiles = []; for (let i = ti; i !== cm.start && i >= 0; i = cm.prev[i]) tiles.push(i);
  tiles.reverse();
  const pts = [posOf(e), ...tiles.slice(0, -1).map((i) => [i % G.W, (i / G.W) | 0]), [tx, ty]], r = rad(e) * 0.9, out = [pts[0]];
  let a = 0;
  while (a < pts.length - 1) { let b = pts.length - 1; while (b > a + 1 && !segClear(pts[a][0], pts[a][1], pts[b][0], pts[b][1], r)) b--; out.push(pts[b]); a = b; }
  return { pts: out, cost: cm.cost[ti] };
}
