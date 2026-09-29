import { BOSSES, ENEMY, MAGE } from '../data/enemies.js';
import { ITEM_W } from '../data/items.js';
import { FLOORS, SURF_OF, S_GRASS, S_ICE, S_NONE, S_OIL, S_WATER, T_DOOR, T_FLOOR, T_STAIRS, T_WALL, ZONES, ZONE_FLOORS } from '../data/terrain.js';
import { D4, D8, cheb, sgn } from '../util/grid.js';
import { pick, rand, ri, shuffle, wpick } from '../util/rng.js';
import { bfsDist, computeFOV } from './fov.js';
import { placeChests, placeFloorGear } from './gear.js';
import { placeHidden, stockHidden } from './hidden.js';
import { META, makeNpc } from './meta.js';
import { G, I, entAt, inb, newSt } from './state.js';
import { placeLamps } from './torch.js';

export function genFloor() {
  const Z = ZONES[G.zone - 1], boss = G.zf === ZONE_FLOORS, F = FLOORS[boss && Z.lastTheme != null ? Z.lastTheme : Z.theme], W = G.W, H = G.H, N = W * H;
  const n = (G.zone - 1) * ZONE_FLOORS + G.zf; G.floor = n; G.theme = F; G.bossFloor = boss; G.exitOpen = false; G.bossId = -1;
  let tile, room, rooms, corr;
  for (let attempt = 0; attempt < 30; attempt++) {
    tile = new Uint8Array(N); room = new Int16Array(N).fill(-1); rooms = []; corr = new Uint8Array(N);
    for (let a = 0; a < 1200 && rooms.length < 14; a++) {
      const w = ri(4, 8), h = ri(4, 7), x = ri(1, W - w - 1), y = ri(1, H - h - 1);
      if (rooms.some((r) => x < r.x + r.w + 1 && x + w + 1 > r.x && y < r.y + r.h + 1 && y + h + 1 > r.y)) continue;
      rooms.push({ x, y, w, h, cx: x + (w >> 1), cy: y + (h >> 1) });
    }
    if (rooms.length >= 10) break;
  }
  rooms.forEach((r, k) => { for (let y = r.y; y < r.y + r.h; y++) for (let x = r.x; x < r.x + r.w; x++) { tile[I(x, y)] = T_FLOOR; room[I(x, y)] = k; } });
  // 최소 신장 트리 + 고리 두어 개
  const conn = [0], rest = rooms.map((_, i) => i).slice(1), edges = [];
  while (rest.length) {
    let best = null;
    for (const a of conn) for (const b of rest) { const d = Math.abs(rooms[a].cx - rooms[b].cx) + Math.abs(rooms[a].cy - rooms[b].cy); if (!best || d < best.d) best = { a, b, d }; }
    edges.push([best.a, best.b]); conn.push(best.b); rest.splice(rest.indexOf(best.b), 1);
  }
  for (let k = 0; k < 2; k++) { const a = ri(0, rooms.length - 1), b = ri(0, rooms.length - 1); if (a !== b) edges.push([a, b]); }
  const carve = (x, y) => { const i = I(x, y); if (tile[i] === T_WALL) { tile[i] = T_FLOOR; corr[i] = 1; } };
  for (const [a, b] of edges) {
    const A = rooms[a], B = rooms[b]; let x = A.cx, y = A.cy;
    if (rand() < 0.5) { while (x !== B.cx) { x += sgn(B.cx - x); carve(x, y); } while (y !== B.cy) { y += sgn(B.cy - y); carve(x, y); } }
    else { while (y !== B.cy) { y += sgn(B.cy - y); carve(x, y); } while (x !== B.cx) { x += sgn(B.cx - x); carve(x, y); } }
  }
  // 문: 방과 맞닿은 복도 목
  const isW = (x, y) => !inb(x, y) || tile[I(x, y)] === T_WALL;
  for (let y = 1; y < H - 1; y++) for (let x = 1; x < W - 1; x++) {
    const i = I(x, y); if (!corr[i]) continue;
    const ns = isW(x, y - 1) && isW(x, y + 1) && !isW(x - 1, y) && !isW(x + 1, y);
    const ew = isW(x - 1, y) && isW(x + 1, y) && !isW(x, y - 1) && !isW(x, y + 1);
    if (!(ns || ew)) continue;
    if (!D4.some(([dx, dy]) => room[I(x + dx, y + dy)] >= 0)) continue;
    if (D8.some(([dx, dy]) => tile[I(x + dx, y + dy)] === T_DOOR)) continue;
    if (rand() < 0.55) tile[i] = T_DOOR;
  }
  const start = { x: rooms[0].cx, y: rooms[0].cy };
  const dist = bfsDist(tile, start.x, start.y);
  let far = -1;
  for (let i = 0; i < N; i++) if (room[i] > 0 && tile[i] === T_FLOOR && dist[i] < 9999 && (far < 0 || dist[i] > dist[far])) far = i;
  tile[far] = T_STAIRS;

  // 지형: 방마다 한 가지(가끔 두 가지) 웅덩이·풀밭·기름·얼음
  const surf = new Uint8Array(N);
  const blob = (r, k, s, target) => {
    const sx = ri(r.x, r.x + r.w - 1), sy = ri(r.y, r.y + r.h - 1), front = [[sx, sy]], seen = new Set(); let c = 0;
    while (front.length && c < target) {
      const [x, y] = front.splice(Math.floor(rand() * front.length), 1)[0], i = I(x, y);
      if (seen.has(i) || !inb(x, y)) continue; seen.add(i);
      if (room[i] !== k || tile[i] !== T_FLOOR) continue;
      surf[i] = s; c++; for (const [dx, dy] of D4) front.push([x + dx, y + dy]);
    }
  };
  rooms.forEach((r, k) => {
    if (k === 0) return;
    const roll = rand(); let acc = 0, s = 0;
    for (const [nm, p] of Object.entries(F.surf)) { acc += p; if (roll < acc) { s = SURF_OF[nm]; break; } }
    if (!s) return;
    blob(r, k, s, Math.floor(r.w * r.h * (0.3 + rand() * 0.35)));
    if (rand() < 0.35) blob(r, k, SURF_OF[pick(Object.keys(F.surf))], Math.floor(r.w * r.h * 0.18));
  });
  if (F.corr) for (let i = 0; i < N; i++) if (corr[i] && tile[i] === T_FLOOR && rand() < F.corr[1]) surf[i] = F.corr[0];
  for (let y = start.y - 1; y <= start.y + 1; y++) for (let x = start.x - 1; x <= start.x + 1; x++) if (inb(x, y)) surf[I(x, y)] = S_NONE;
  surf[far] = S_NONE;

  placeHidden(rooms, tile, room, surf);
  Object.assign(G, { tile, surf, room, rooms, fire: new Uint8Array(N), cloud: new Uint8Array(N), cloudT: new Uint8Array(N), vis: new Uint8Array(N), seen: new Uint8Array(N), items: new Map(), stones: new Map(), gear: new Map(), chests: new Map(), stairs: far });
  const p = G.player; p.x = start.x; p.y = start.y; p.face = [0, 1];
  G.ents = [p];
  // 적 무리
  const cand = rooms.map((_, k) => k).filter((k) => k > 0 && dist[I(rooms[k].cx, rooms[k].cy)] >= 7);
  const order = shuffle(cand.length >= 3 ? cand : rooms.map((_, k) => k).filter((k) => k > 0));
  // 넓어진 층: 무리 전부 + 방 네 개마다 무리 하나 더(1구역이 너무 쉬웠다)
  const packs = boss ? F.packs.slice(0, 4) : [...F.packs, ...Array.from({ length: Math.floor(rooms.length / 4) }, () => pick(F.packs))];
  // 무리: [종류, 수, 곁에 붙는 하나(주술사 등)]. 거머리는 물속에
  const water = []; for (let i = 0; i < N; i++) if (surf[i] === S_WATER && tile[i] === T_FLOOR && cheb(i % W, (i / W) | 0, start.x, start.y) >= 6) water.push(i);
  const spawn = (type, r) => {
    if (type === 'leech' && water.length) { for (let t = 0; t < 40; t++) { const i = water[ri(0, water.length - 1)]; if (entAt(i % W, (i / W) | 0)) continue; G.ents.push(mkEnemy(type, i % W, (i / W) | 0, F)); return; } }
    for (let t = 0; t < 40; t++) {
      const x = ri(r.x, r.x + r.w - 1), y = ri(r.y, r.y + r.h - 1);
      if (tile[I(x, y)] !== T_FLOOR || entAt(x, y) || cheb(x, y, start.x, start.y) < 5) continue;
      G.ents.push(mkEnemy(type, x, y, F)); return;
    }
  };
  packs.forEach(([type, cnt, extra], j) => {
    const r = rooms[order[j % order.length]];
    for (let c = 0; c < cnt; c++) spawn(type, r);
    if (extra) spawn(extra, r);
  });
  if (boss) { tile[far] = T_FLOOR; const b = mkBoss(Z.boss, far % W, (far / W) | 0); G.ents.push(b); G.bossId = b.id; }
  // 길 잃은 사람: 구역마다 최대 1명(넉살 좋은 등불지기는 더 잘 만난다)
  if (!boss && !G.zoneFlags.npc && rand() < (G.perk === 'X+' ? 0.6 : 0.35)) {
    for (let t = 0; t < 80; t++) {
      const r = rooms[order[ri(0, order.length - 1)]], x = ri(r.x, r.x + r.w - 1), y = ri(r.y, r.y + r.h - 1);
      if (tile[I(x, y)] !== T_FLOOR || entAt(x, y) || surf[I(x, y)] === S_OIL) continue;
      const data = makeNpc(null), caged = rand() < 0.55;
      G.ents.push({ id: G.nextId++, type: 'npc', ally: true, npc: true, npcData: data, caged, freed: false, name: data.name, x, y, hp: 12, max: 12, st: newSt(), alive: true, awake: true, face: [0, 1] });
      G.zoneFlags.npc = true; break;
    }
  }
  // 재료
  G.mats = new Map();
  for (let k = 0, placed = 0; k < 300 && placed < 6; k++) {
    const r = rooms[ri(1, rooms.length - 1)], x = ri(r.x, r.x + r.w - 1), y = ri(r.y, r.y + r.h - 1), i = I(x, y);
    if (tile[i] !== T_FLOOR || G.mats.has(i)) continue;
    const sf = surf[i], nearWall = D4.some(([dx, dy]) => tile[I(x + dx, y + dy)] === T_WALL);
    const m = sf === S_GRASS ? '약초' : sf === S_OIL ? '기름' : sf === S_ICE ? '얼음' : nearWall ? '광석' : rand() < 0.5 ? '약초' : '광석';
    G.mats.set(i, m); placed++;
  }
  // 소모품
  for (let k = 0, placed = 0; k < 300 && placed < F.items + 2; k++) {
    const r = rooms[ri(0, rooms.length - 1)], x = ri(r.x, r.x + r.w - 1), y = ri(r.y, r.y + r.h - 1), i = I(x, y);
    if (tile[i] !== T_FLOOR || G.items.has(i) || G.mats.has(i) || (x === start.x && y === start.y)) continue;
    G.items.set(i, wpick(ITEM_W)); placed++;
  }
  // 두루마리: 강화(무기용·방어구용 반반)와 확인, 층마다 평균 0.5장씩
  const scroll = (k) => { for (let t = 0; t < 200; t++) { const r = rooms[ri(0, rooms.length - 1)], x = ri(r.x, r.x + r.w - 1), y = ri(r.y, r.y + r.h - 1), i = I(x, y); if (tile[i] !== T_FLOOR || G.items.has(i) || G.mats.has(i)) continue; G.items.set(i, k); return; } };
  if (rand() < 0.5) scroll(rand() < 0.5 ? 'enchW' : 'enchA');
  if (rand() < 0.5) scroll('ident');
  // 장비: 바닥 1~2개(+죽은 등불지기가 남긴 유품)
  placeFloorGear(rooms, tile, start);
  placeChests(rooms, tile, G.perk === 'H-' && G.zf === 1 ? 1 : 0);
  // 옛 등불지기의 기록: 보스 층 첫 방에
  if (boss && !(META?.lore || []).includes(G.zone)) for (let k = 0; k < 60; k++) {
    const r = rooms[0], x = ri(r.x, r.x + r.w - 1), y = ri(r.y, r.y + r.h - 1), i = I(x, y);
    if (tile[i] !== T_FLOOR || (x === start.x && y === start.y) || G.items.has(i) || G.mats.has(i)) continue;
    G.mats.set(i, '기록'); break;
  }
  stockHidden();
  G.intents = { decals: [], tags: {}, casting: [], winding: [] };
  placeLamps();
  computeFOV();
}

export function mkBoss(kind, x, y) {
  const B = BOSSES[kind], hp = Math.round(B.hp * (1 + 0.025 * (G.floor - ZONE_FLOORS))); // 구역이 5층이라 층당 오름을 줄였다
  return { id: G.nextId++, type: B.type, boss: kind, x, y, hp, max: hp, atk: B.atk, st: newSt(), alive: true, awake: false, face: [0, 1], cd: 1, cast: null, charge: null, aim: false, name: B.name, elem: B.elem, horn: 3, blink: 0, sum: 4 };
}

export function mkEnemy(type, x, y, F) {
  const B = ENEMY[type], hp = Math.round(B.hp * (1 + 0.05 * (G.floor - 1))); // 층마다 +5%(20층 ≈ ×2)
  const e = { id: G.nextId++, type, x, y, hp, max: hp, atk: B.atk + (G.zone - 1), // 구역마다 공격 +1(기준안)
    speed: B.speed || null, hidden: type === 'leech' && !!G.surf && G.surf[I(x, y)] === S_WATER, // 거머리는 물속에 숨는다
    st: newSt(), alive: true, awake: type === 'leech', face: [0, 1], cd: ri(0, 1), cast: null, charge: null, aim: false, name: B.name };
  if (type === 'mage') { const m = G.mageOf[G.zone - 1]; e.elem = m === 'mix' ? pick(['bolt', 'fire', 'frost']) : m; e.name = '해골 ' + MAGE[e.elem].name; }
  if (type === 'goblin' && F.poison && rand() < 0.5) { e.poison = true; e.name = '독칼 고블린'; }
  else if (type === 'goblin' && G.floor >= 2 && rand() < 0.4) { e.armor = true; e.name = '갑옷 고블린'; e.hp += 2; e.max += 2; }
  if (G.surf && G.surf[I(x, y)] === S_WATER) e.st.wet = 3;
  return e;
}
