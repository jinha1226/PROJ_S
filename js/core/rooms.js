import { FURN, ROOMS, ROOM_MAX, ROOM_ORDER } from '../data/build.js';

/* ================= 방 인식 (docs/설계_정착지_건설.md §4.2) =================
   지어진 벽·문으로 닫힌 공간 = 방. 가장자리에 닿거나 너무 넓으면 바깥. 방 종류는 안의 가구로 정한다. */

/** 가구 한 점이 차지하는 칸들: 회전이 홀수면 가로·세로가 바뀐다 */
export function furnCells(f) {
  const F = FURN[f.k], odd = (f.rot || 0) % 2 === 1, w = odd ? F.h : F.w, h = odd ? F.w : F.h, out = [];
  for (let dy = 0; dy < h; dy++) for (let dx = 0; dx < w; dx++) out.push([f.x + dx, f.y + dy]);
  return out;
}
export const furnSize = (k, rot = 0) => { const F = FURN[k]; return rot % 2 ? [F.h, F.w] : [F.w, F.h]; };

/** 방 목록: { id, kind, cells(Set of index), x0, y0, x1, y1, cx, cy, furn:{k: n} } */
export function detectRooms(S) {
  const { W, H } = S, seen = new Uint8Array(W * H), rooms = [];
  for (let i = 0; i < W * H; i++) {
    if (seen[i] || S.wall[i]) continue;
    const cells = [], q = [i]; seen[i] = 1; let edge = false;
    while (q.length) {
      const c = q.pop(), x = c % W, y = (c / W) | 0; cells.push(c);
      if (x === 0 || y === 0 || x === W - 1 || y === H - 1) edge = true;
      for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        const nx = x + dx, ny = y + dy; if (nx < 0 || ny < 0 || nx >= W || ny >= H) continue;
        const n = ny * W + nx; if (seen[n] || S.wall[n]) continue; seen[n] = 1; q.push(n);
      }
    }
    if (edge || cells.length > ROOM_MAX) continue;
    const set = new Set(cells), furn = {};
    for (const f of S.furn) if (set.has(f.y * W + f.x)) furn[f.k] = (furn[f.k] || 0) + 1;
    const kind = ROOM_ORDER.find((k) => Object.entries(ROOMS[k].need).every(([fk, n]) => (furn[fk] || 0) >= n)) || null;
    let x0 = W, y0 = H, x1 = 0, y1 = 0; for (const c of cells) { const x = c % W, y = (c / W) | 0; x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y); }
    rooms.push({ id: rooms.length, kind, cells: set, x0, y0, x1, y1, cx: (x0 + x1) / 2, cy: (y0 + y1) / 2, furn });
  }
  return rooms;
}
/** 방 이름: 침대 둘 이상이면 공동 침실 */
export const roomName = (r) => (!r.kind ? '빈 방' : r.kind === 'bedroom' && (r.furn.bed || 0) >= 2 ? '공동 침실' : ROOMS[r.kind].name);
