import { G, I, XY, entAt, inb, isFoe, opaque } from './state.js';
import { T_WALL } from '../data/terrain.js';
import { D8, cheb } from '../util/grid.js';

export function bfsDist(tile, sx, sy) {
  const d = new Int16Array(G.W * G.H).fill(9999), q = [I(sx, sy)]; d[q[0]] = 0;
  for (let h = 0; h < q.length; h++) { const i = q[h], x = i % G.W, y = (i / G.W) | 0; for (const [dx, dy] of D8) { const nx = x + dx, ny = y + dy; if (!inb(nx, ny)) continue; const j = I(nx, ny); if (d[j] !== 9999 || tile[j] === T_WALL) continue; d[j] = d[i] + 1; q.push(j); } }
  return d;
}

/* ================= 시야 ================= */
export function lineClear(x0, y0, x1, y1) {
  let dx = Math.abs(x1 - x0), dy = -Math.abs(y1 - y0), sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1, err = dx + dy, x = x0, y = y0;
  for (;;) {
    if (x === x1 && y === y1) return true;
    const e2 = 2 * err; if (e2 >= dy) { err += dy; x += sx; } if (e2 <= dx) { err += dx; y += sy; }
    if (x === x1 && y === y1) return true;
    if (opaque(I(x, y))) return false;
  }
}

export function lineTiles(x0, y0, x1, y1) {
  const out = []; let dx = Math.abs(x1 - x0), dy = -Math.abs(y1 - y0), sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1, err = dx + dy, x = x0, y = y0;
  for (let k = 0; k < 40; k++) { const e2 = 2 * err; if (e2 >= dy) { err += dy; x += sx; } if (e2 <= dx) { err += dx; y += sy; } if (x === x1 && y === y1) break; out.push([x, y]); }
  return out;
}

export const los = (ax, ay, bx, by) => lineClear(ax, ay, bx, by) || lineClear(bx, by, ax, ay);

export const FOV_R = 7;

export function computeFOV() {
  const p = G.player; G.vis.fill(0);
  for (let dy = -FOV_R; dy <= FOV_R; dy++) for (let dx = -FOV_R; dx <= FOV_R; dx++) {
    if (dx * dx + dy * dy > FOV_R * FOV_R + FOV_R) continue;
    const x = p.x + dx, y = p.y + dy; if (!inb(x, y)) continue;
    if (los(p.x, p.y, x, y)) { const i = I(x, y); G.vis[i] = 1; G.seen[i] = 1; }
  }
}

export function canSee(e, t) {
  const d = cheb(e.x, e.y, t.x, t.y); if (d > 8) return false;
  if (d > 1 && (G.cloud[I(t.x, t.y)] || G.cloud[I(e.x, e.y)])) return false;
  return los(e.x, e.y, t.x, t.y);
}

export function distMap(tx, ty) {
  const dm = new Int16Array(G.W * G.H).fill(999), q = [I(tx, ty)]; dm[q[0]] = 0;
  for (let h = 0; h < q.length; h++) { const i = q[h], x = i % G.W, y = (i / G.W) | 0; for (const [dx, dy] of D8) { const nx = x + dx, ny = y + dy; if (!inb(nx, ny)) continue; const j = I(nx, ny); if (dm[j] !== 999 || G.tile[j] === T_WALL) continue; dm[j] = dm[i] + 1; q.push(j); } }
  return dm;
}

export function visibleFoes() { return G.ents.filter((e) => e.alive && isFoe(e) && G.vis[I(e.x, e.y)]); }

export function findPath(sx, sy, tx, ty) {
  const N = G.W * G.H, prev = new Int32Array(N).fill(-1), start = I(sx, sy), goal = I(tx, ty), q = [start]; prev[start] = start;
  for (let h = 0; h < q.length; h++) {
    const i = q[h]; if (i === goal) break; const [x, y] = XY(i);
    for (const [dx, dy] of D8) {
      const nx = x + dx, ny = y + dy; if (!inb(nx, ny)) continue; const j = I(nx, ny);
      if (prev[j] !== -1 || G.tile[j] === T_WALL || !G.seen[j] || G.fire[j]) continue;
      const e = entAt(nx, ny); if (e && G.vis[j]) continue;
      prev[j] = i; q.push(j);
    }
  }
  if (prev[goal] === -1) return null;
  const path = []; for (let i = goal; i !== start; i = prev[i]) path.push(XY(i));
  return path.reverse();
}
