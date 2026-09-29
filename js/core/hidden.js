import { STONE } from '../data/stones.js';
import { S_ASH, S_ICE, S_WATER, T_FLOOR, T_WALL } from '../data/terrain.js';
import { HIDDEN } from '../data/visitors.js';
import { makeNpc } from './meta.js';
import { pick, rand } from '../util/rng.js';
import { computeFOV } from './fov.js';
import { snapTerrain, snapVis } from './snap.js';
import { G, I, emit, inb, log, newSt } from './state.js';
import { jo } from '../util/text.js';

/* ================= 스킬로 여는 숨은 방 =================
   층마다 0~1개. 방 벽 너머에 3×3 골방을 파고, 입구 한 칸을 막는다(core에서는 벽).
   G.block: 입구 칸 → 종류. 맞는 스킬이 닿으면 열린다. */
export function placeHidden(rooms, tile, room, surf) {
  G.block = new Map(); G.hidden = null;
  if (G.bossFloor || rand() >= 0.6) return;
  const W = G.W, H = G.H, isWall = (x, y) => x >= 1 && y >= 1 && x < W - 1 && y < H - 1 && tile[I(x, y)] === T_WALL;
  const cand = [];
  rooms.forEach((r, k) => {
    if (k === 0) return;
    const sides = [];
    for (let x = r.x + 1; x < r.x + r.w - 1; x++) { sides.push([x, r.y - 1, 0, -1]); sides.push([x, r.y + r.h, 0, 1]); }
    for (let y = r.y + 1; y < r.y + r.h - 1; y++) { sides.push([r.x - 1, y, -1, 0]); sides.push([r.x + r.w, y, 1, 0]); }
    for (const [ex, ey, dx, dy] of sides) {
      if (!isWall(ex, ey) || !isWall(ex - dy, ey - dx) || !isWall(ex + dy, ey + dx)) continue;
      const cx = ex + dx * 2, cy = ey + dy * 2; let ok = true;
      for (let yy = cy - 2; yy <= cy + 2 && ok; yy++) for (let xx = cx - 2; xx <= cx + 2 && ok; xx++) if (!isWall(xx, yy)) ok = false;
      if (ok) cand.push({ ex, ey, cx, cy });
    }
  });
  if (!cand.length) return;
  const c = pick(cand), kind = pick(Object.keys(HIDDEN));
  for (let y = c.cy - 1; y <= c.cy + 1; y++) for (let x = c.cx - 1; x <= c.cx + 1; x++) { tile[I(x, y)] = T_FLOOR; room[I(x, y)] = -2; surf[I(x, y)] = 0; }
  const ei = I(c.ex, c.ey); G.block.set(ei, kind);
  if (kind === 'water') surf[ei] = S_WATER;
  G.hidden = { kind, cx: c.cx, cy: c.cy };
}

/** 골방 안의 것(층의 다른 물건을 놓은 뒤에) */
export function stockHidden() {
  const h = G.hidden; if (!h || !G.block.size) return;
  const ci = I(h.cx, h.cy), side = I(h.cx + 1, h.cy);
  if (h.kind === 'thorn') { G.chests.set(ci, { open: false }); G.mats.set(I(h.cx - 1, h.cy), pick(['가죽', '뼈', '약초'])); G.mats.set(side, pick(['광석', '심장'])); }
  else if (h.kind === 'water') {
    G.stones.set(ci, pick(Object.keys(STONE)));
    if (!G.zoneFlags.npc) { const data = makeNpc(null); G.zoneFlags.npc = true; G.ents.push({ id: G.nextId++, type: 'npc', ally: true, npc: true, npcData: data, caged: false, freed: false, name: data.name, x: h.cx - 1, y: h.cy + 1, hp: 12, max: 12, st: newSt(), alive: true, awake: true, face: [0, 1] }); }
  } else if (h.kind === 'gate') G.chests.set(ci, { open: false, rare: true });
  else G.mats.set(ci, '마석');
}

/** 맞는 스킬로 막힌 칸을 연다 */
export function openHidden(x, y, skill) {
  const i = I(x, y), kind = G.block && G.block.get(i); if (!kind || HIDDEN[kind].skill !== skill) return false;
  G.block.delete(i); G.tile[i] = T_FLOOR;
  if (kind === 'water') G.surf[i] = S_ICE; else if (kind === 'thorn') { G.surf[i] = S_ASH; G.fire[i] = 2; }
  emit('hiddenOpen', { x, y, kind });
  log(`${jo(HIDDEN[kind].name, '이가')} 열리고 숨은 방이 드러났다.`, 'syn');
  computeFOV(); snapVis(); snapTerrain();
  return true;
}
export const blockAt = (x, y) => (inb(x, y) && G.block ? G.block.get(I(x, y)) : undefined);
