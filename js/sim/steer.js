import { C_STEAM, T_WALL } from '../data/terrain.js';
import { distMap } from '../core/fov.js';
import { posOf, rad, segClear } from '../core/space.js';
import { G, I, inb } from '../core/state.js';

/* ================= 길 찾아 걷기: 트였으면 곧장, 막혔으면 칸 거리 지도를 따라 (docs/설계_전투_코어.md §2) ================= */
const N8 = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]];
const open = (x, y) => inb(x, y) && G.tile[I(x, y)] !== T_WALL;

/** 목표 칸까지의 거리 지도. 한 틱 안에서는 같은 목표를 다시 계산하지 않는다 */
export function flowMap(tx, ty) {
  const k = I(tx, ty);
  if (!G.flowCache || G.flowCache.tick !== G.tickN) G.flowCache = { tick: G.tickN, maps: new Map() };
  let m = G.flowCache.maps.get(k);
  if (!m) { m = distMap(tx, ty); G.flowCache.maps.set(k, m); }
  return m;
}

/** 거리 지도를 따라 이웃 칸 하나를 고른다. sign = −1이면 멀어지는 쪽 */
function nextCell(e, dm, sign) {
  const here = dm[I(e.x, e.y)]; let best = null, bs = sign < 0 ? here : -here;
  for (const [dx, dy] of N8) {
    const nx = e.x + dx, ny = e.y + dy; if (!open(nx, ny)) continue;
    if (dx && dy && (!open(e.x + dx, e.y) || !open(e.x, e.y + dy))) continue; // 모서리를 비스듬히 못 자른다
    const j = I(nx, ny); let s = sign < 0 ? dm[j] : -dm[j];
    if (G.fire[j]) s -= 6; if (G.cloud[j] === C_STEAM) s -= 2;
    if (s > bs) { bs = s; best = [nx, ny]; }
  }
  return best;
}
const unit = (dx, dy) => { const d = Math.hypot(dx, dy); return d < 1e-6 ? null : [dx / d, dy / d]; };

/** (tx, ty)를 향해 걸을 방향(길이 1) */
export function steerTo(e, tx, ty) {
  const [x, y] = posOf(e);
  if (segClear(x, y, tx, ty, rad(e) * 0.9)) return unit(tx - x, ty - y);
  const c = nextCell(e, flowMap(Math.round(tx), Math.round(ty)), 1);
  return c ? unit(c[0] - x, c[1] - y) : unit(tx - x, ty - y);
}

/** (fx, fy)에서 멀어지는 방향: 거리 지도에서 더 먼 칸 쪽 */
export function steerAway(e, fx, fy) {
  const [x, y] = posOf(e), c = nextCell(e, flowMap(Math.round(fx), Math.round(fy)), -1);
  return c ? unit(c[0] - x, c[1] - y) : unit(x - fx, y - fy);
}

/** 같은 편끼리 겹쳐 뭉치지 않게 옆으로 벌린다: 에워싸는 모양이 저절로 생긴다 */
export function spread(e, dir, w = 0.7) {
  if (!dir) return dir;
  const [x, y] = posOf(e); let sx = 0, sy = 0;
  for (const o of G.ents) {
    if (o === e || !o.alive || o.team !== e.team || o.px == null) continue;
    const dx = x - o.px, dy = y - o.py, d = Math.hypot(dx, dy);
    if (d > 1.1 || d < 1e-4) continue;
    sx += (dx / d) * (1.1 - d); sy += (dy / d) * (1.1 - d);
  }
  return unit(dir[0] + sx * w, dir[1] + sy * w) || dir;
}
