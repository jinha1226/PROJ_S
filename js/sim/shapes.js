import { T_WALL } from '../data/terrain.js';
import { G, I, inb, standable } from '../core/state.js';
import { posOf, rad } from '../core/space.js';
import { angDiff } from './body.js';

/* ================= 판정 모양 (docs/설계_실시간_전환.md §4) ================= */

/** 부채꼴: 중심(ox, oy)에서 ang 방향 ±half(도) 안, 중심 거리 reach 안(몸 반지름만큼 너그럽게) */
export function inArc(ox, oy, ang, half, reach, e) {
  const [x, y] = posOf(e), d = Math.hypot(x - ox, y - oy);
  if (d > reach + rad(e) * 0.5) return false;
  if (d < 0.35) return true; // 겹쳐 붙은 몸은 어느 쪽이든 맞는다
  return angDiff(Math.atan2(y - oy, x - ox), ang) <= (half * Math.PI) / 180;
}

/** 직선: ang 방향으로 길이 reach, 폭 width(몸 반지름을 더해서) */
export function inLine(ox, oy, ang, reach, width, e) {
  const [x, y] = posOf(e), dx = x - ox, dy = y - oy, c = Math.cos(ang), s = Math.sin(ang);
  const along = dx * c + dy * s, side = Math.abs(-dx * s + dy * c);
  return along >= -0.2 && along <= reach + rad(e) * 0.5 && side <= width / 2 + rad(e);
}

/** 십자 다섯 칸(마법사 주문) */
export const plus = (x, y) => [[x, y], [x + 1, y], [x - 1, y], [x, y + 1], [x, y - 1]].filter(([a, b]) => inb(a, b) && G.tile[I(a, b)] !== T_WALL);

/** 3×3 아홉 칸(보스 주문·족장 강타) */
export const square3 = (x, y) => { const o = []; for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) { const a = x + dx, b = y + dy; if (inb(a, b) && G.tile[I(a, b)] !== T_WALL) o.push([a, b]); } return o; };

/** (x, y)에서 ang 방향으로 벽에 막힐 때까지 지나가는 칸들(최대 len칸): 돌진 띠·화살 조준선 */
export function cellsAlong(x, y, ang, len) {
  const out = [], seen = new Set(), c = Math.cos(ang), s = Math.sin(ang);
  for (let k = 0.5; k <= len; k += 0.25) {
    const cx = Math.round(x + c * k), cy = Math.round(y + s * k);
    if (!inb(cx, cy) || !standable(cx, cy)) break;
    const i = I(cx, cy); if (seen.has(i)) continue;
    if (cx === Math.round(x) && cy === Math.round(y)) continue;
    seen.add(i); out.push([cx, cy]);
  }
  return out;
}

/** 칸 목록 안에 발밑 칸이 있는가 */
export const onCells = (cells, e) => cells.some(([x, y]) => x === e.x && y === e.y);
