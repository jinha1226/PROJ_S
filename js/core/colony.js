import { CLOCK, CROP_DAYS, DAYS_PER_MONTH, GATHER, MONTHS, NEAR_RES, RATE, REGROW_DAYS, TARGETS, WORK_IDS, WORK_ORDER, foodTarget, mealTarget } from '../data/colony.js';
import { SCX, SCY, SW, TERRAIN, TR, ZONE_TYPES } from '../data/build.js';
import { JOBS } from '../data/town.js';
import { META, moodAdd } from './meta.js';
import { addStock, bpHours, finishBp, inLight, payBp, radius, rooms, stockOf } from './settlement.js';
import { hearthGlow } from './visitors.js';
import { craftStep, orderFor, stationWorker } from './crafting.js';

/* ================= 정착지 2단계: 시간과 일 (docs/설계_정착지_2단계.md §3~§7) =================
   규칙은 한 시간 틱(hourTick) 하나. 정착지에 있으면 실시간으로 10분마다 쌓아 한 시간마다, 원정 뒤에는 한꺼번에 돌린다.
   META.time = { day, hour, min } · META.colony = { targets, orders, stations, piles, sprouts, crops, nid, sum }
   주민 n.task = { kind, …, prog } · n.work = { auto, pri: { build: 0~3 … } } · n.hunger = 거른 끼니 */
const I = (x, y) => y * SW + x;
const S = () => META.settle;

/** 처음 쓸 때 채운다(새 게임·옛 저장) */
export function colony() {
  META.time ||= { day: 1, hour: 8, min: 0 };
  const C = (META.colony ||= {});
  C.targets ||= { ...TARGETS }; C.marks ||= []; C.orders ||= []; C.stations ||= {}; C.piles ||= []; C.sprouts ||= []; C.crops ||= {}; C.nid ||= 1; C.sum ||= newSum();
  for (const n of META.npcs) { n.work ||= { auto: true, pri: {} }; n.hunger ||= 0; }
  return C;
}
const newSum = () => ({ got: {}, built: 0, made: [], meals: 0, hungry: 0, hours: 0 });

/* ---------- 시간 ---------- */
export const clockText = () => { const t = META.time, m = Math.floor((t.day - 1) / DAYS_PER_MONTH) % MONTHS.length, d = ((t.day - 1) % DAYS_PER_MONTH) + 1; return `${MONTHS[m]} ${d}일 · ${t.hour < 12 ? '오전' : '오후'} ${((t.hour + 11) % 12) + 1}시`; };
export const isNight = (h = META.time.hour) => h >= CLOCK.night || h < CLOCK.dayStart;
/** 실시간: dt초 × 배속만큼 흘린다. 흐른 시간 틱 수를 돌려준다 */
export function tickReal(dt, speed) {
  if (!speed) return 0;
  const t = META.time; t.min += dt * CLOCK.minPerSec * speed; let n = 0;
  while (t.min >= 60) { t.min -= 60; hourTick(); n++; }
  return n;
}
/** 원정에서 돌아와 한꺼번에(최대 3일). 그동안의 요약을 돌려준다 */
export function passHours(h) {
  colony(); META.colony.sum = newSum();
  const n = Math.min(CLOCK.maxAwayHours, Math.max(0, Math.round(h)));
  for (let k = 0; k < n; k++) hourTick();
  return { ...META.colony.sum, hours: n };
}

/** 한 시간 */
export function hourTick() {
  const C = colony(), t = META.time;
  t.hour++; if (t.hour >= 24) { t.hour = 0; t.day++; newDay(); }
  C.sum.hours++;
  if (CLOCK.meals.includes(t.hour)) meals();
  if (isNight()) { for (const n of META.npcs) n.doing = 'sleep'; return; }
  for (const n of META.npcs) work(n);
}

/* ---------- 하루: 나무·밭이 자란다 ---------- */
const glowIdx = () => { const g = hearthGlow(); return g >= 60 ? 0 : g >= 30 ? 1 : 2; };
function newDay() {
  const C = META.colony, s = S(), d = META.time.day;
  C.sprouts = C.sprouts.filter((q) => { if (q.day > d) return true; if (s.terr[q.i] === TR.grass || s.terr[q.i] === TR.dirt) s.terr[q.i] = TR.tree; return false; });
  // 잠자리: 침대 수보다 많은 사람은 바닥에서 잤다
  const beds = s.furn.filter((f) => f.k === 'bed').length;
  META.npcs.slice(beds).forEach((n) => moodAdd(n, -1));
}

/* ---------- 식사 ---------- */
function meals() {
  const C = META.colony;
  for (const n of META.npcs) {
    if (stockOf('식사') > 0) { addStock('식사', -1); n.hunger = 0; C.sum.meals++; if (Math.random() < 0.5) moodAdd(n, 1); }
    else if (stockOf('식량') > 0) { addStock('식량', -1); n.hunger = 0; C.sum.meals++; if (Math.random() < 0.3) moodAdd(n, -1); }
    else { n.hunger++; C.sum.hungry++; moodAdd(n, -1); }
  }
}

/* ---------- 일 ---------- */
/** 이 사람의 일 우선순위 0~3. 알아서면 직업 특기 일 3, 나머지 1 */
export function priOf(n, w) {
  if (!n.work || n.work.auto) return w === 'craft' ? (stationRoomOf(n) ? 3 : 0) : JOBS[n.job].spec.includes(w) ? 3 : 1; // 제작은 작업방에 선 사람만
  return n.work.pri[w] ?? 1;
}
const stationRoomOf = (n) => Object.keys({ forge: 1, herb: 1, library: 1, inn: 1 }).find((k) => stationWorker(k) === n);
/** 한 시간 일의 배율: 기분 · 성실성 · 특기 */
export function rateOf(n, w) {
  let r = RATE.mood[Math.max(-2, Math.min(2, n.mood | 0))] ?? 1;
  if (n.t.C >= 1) r *= RATE.cHigh; else if (n.t.C <= -1) r *= RATE.cLow;
  if (JOBS[n.job].spec.includes(w)) r *= RATE.spec;
  return r;
}
function work(n) {
  if (n.hunger >= 6) { n.doing = 'faint'; n.task = null; return; } // 사흘 굶으면 일을 못 한다
  if (n.task && !valid(n.task)) n.task = null;
  if (!n.task) n.task = pick(n);
  if (!n.task) { n.doing = 'rest'; return; }
  n.doing = n.task.kind;
  if (DO[n.task.kind](n, n.task, rateOf(n, n.task.kind))) n.task = null;
}
/** 할 일 고르기: 우선순위 높은 일부터, 같으면 WORK_ORDER 순 */
function pick(n) {
  const ws = WORK_IDS.map((w) => [w, priOf(n, w)]).filter(([, p]) => p > 0).sort((a, b) => b[1] - a[1] || WORK_ORDER.indexOf(a[0]) - WORK_ORDER.indexOf(b[0]));
  for (const [w] of ws) { const t = FIND[w](n); if (t) return { kind: w, prog: 0, ...t }; }
  return null;
}
const taken = (key) => META.npcs.some((m) => m.task && m.task.key === key);
function valid(t) {
  const s = S();
  if (t.kind === 'build') return s.bp.some((b) => b.id === t.bid);
  if (t.kind === 'gather') return !!TERRAIN[s.terr[t.i]].cut;
  if (t.kind === 'craft') return META.colony.orders.some((o) => o.id === t.oid);
  if (t.kind === 'haul') return META.colony.piles.some((p) => p.id === t.pid);
  return true;
}
const near = (list, x0 = SCX, y0 = SCY) => list.sort((a, b) => Math.hypot(a.x - x0, a.y - y0) - Math.hypot(b.x - x0, b.y - y0))[0] || null;
const LAYER = { floor: 0, wall: 1, furn: 2 };
/** 무엇을 할지 찾는다(없으면 null). key = 두 사람이 같은 것을 잡지 않게 */
const FIND = {
  build: () => {
    const s = S(), bps = s.bp.filter((b) => !taken('bp' + b.id)).sort((a, b) => LAYER[a.L] - LAYER[b.L]);
    for (const b of bps) if (b.paid || payBp(b, s)) return { bid: b.id, key: 'bp' + b.id, x: b.x, y: b.y };
    return null;
  },
  craft: (n) => { const k = stationRoomOf(n); if (!k) return null; const o = orderFor(k); if (!o) return null; const r = rooms().find((q) => q.kind === k); return { oid: o.id, room: k, key: 'or' + o.id, x: r.cx, y: r.cy }; },
  cook: () => {
    const r = rooms().find((q) => q.kind === 'inn'), people = META.npcs.length;
    if (!r || taken('cook') || stockOf('식사') >= mealTarget(people) || stockOf('식량') < 1) return null;
    return { key: 'cook', x: r.cx, y: r.cy };
  },
  farm: () => {
    const s = S(), C = META.colony, d = META.time.day;
    for (let i = 0; i < s.zone.length; i++) if (s.zone[i] === ZONE_TYPES.field.id && !taken('fd' + i)) {
      const c = C.crops[i]; if (!c || c.ready <= d) return { i, key: 'fd' + i, x: i % SW, y: (i / SW) | 0, harvest: !!c };
    }
    return null;
  },
  haul: () => { const p = near(META.colony.piles.filter((q) => !taken('pl' + q.id))); return p ? { pid: p.id, key: 'pl' + p.id, x: p.x, y: p.y, m: p.m } : null; },
  gather: () => {
    const s = S(), C = META.colony;
    C.marks = C.marks.filter((i) => TERRAIN[s.terr[i]].cut); // 표시한 곳은 목표 재고와 상관없이 먼저
    const mk = near(C.marks.filter((i) => !taken('gt' + i)).map((i) => ({ i, x: i % SW, y: (i / SW) | 0 })));
    if (mk) { const k = Object.keys(GATHER).find((q) => TR[q] === s.terr[mk.i]); if (k) return { i: mk.i, key: 'gt' + mk.i, x: mk.x, y: mk.y, what: k, h: GATHER[k].h }; }
    const R = radius(), want = Object.entries(GATHER).filter(([k, g]) => k !== 'ruin' && have(g.m) < target(g.m));
    if (!want.length) return null;
    const kinds = new Set(want.map(([k]) => TR[k])), list = [];
    for (let i = 0; i < s.terr.length; i++) { if (!kinds.has(s.terr[i])) continue; const x = i % SW, y = (i / SW) | 0; if (!inLight(x, y, R) || taken('gt' + i)) continue; list.push({ i, x, y }); }
    const c = near(list); if (!c) return null;
    const k = Object.keys(GATHER).find((q) => TR[q] === s.terr[c.i]);
    return { i: c.i, key: 'gt' + c.i, x: c.x, y: c.y, what: k, h: GATHER[k].h };
  },
};
/** 창고 + 바닥 더미 */
export const have = (m) => stockOf(m) + META.colony.piles.filter((p) => p.m === m).reduce((a, p) => a + p.n, 0);
export const target = (m) => META.colony.targets[m] ?? (m === '식량' ? foodTarget(META.npcs.length) : m === '식사' ? mealTarget(META.npcs.length) : 0);
/** 베기 표시(건설 화면의 베기 도구) */
export function markCut(x0, y0, x1, y1) {
  const s = S(), C = colony(), R = radius(); let n = 0;
  for (let y = Math.min(y0, y1); y <= Math.max(y0, y1); y++) for (let x = Math.min(x0, x1); x <= Math.max(x0, x1); x++) {
    const i = I(x, y); if (x < 0 || y < 0 || x >= SW || y >= SW || !inLight(x, y, R) || !TERRAIN[s.terr[i]].cut || C.marks.includes(i)) continue;
    C.marks.push(i); n++;
  }
  return n;
}
export function dropPile(x, y, m, n) { const C = META.colony; const same = C.piles.find((p) => p.x === x && p.y === y && p.m === m); if (same) same.n += n; else C.piles.push({ id: C.nid++, x, y, m, n }); }

/** 한 시간 일하기. 끝났으면 true */
const DO = {
  build: (n, t, r) => {
    const s = S(), b = s.bp.find((q) => q.id === t.bid); if (!b) return true;
    b.prog = (b.prog || 0) + r;
    if (b.prog >= bpHours(b) - 1e-6) { finishBp(b, s); META.colony.sum.built++; META.colony.changed = true; return true; }
    return false;
  },
  craft: (n, t, r) => craftStep(n, t, r),
  cook: (n) => { const spec = JOBS[n.job].spec.includes('cook'), k = Math.min(stockOf('식량'), spec ? RATE.cookSpec / RATE.cook : 1); addStock('식량', -k); addStock('식사', k * RATE.cook); return true; }, // 식량 1 → 식사 2(특기면 한 시간에 두 번)
  farm: (n, t, r) => { // 한 시간에 네 칸쯤: 빈 칸은 심고, 다 자란 칸은 거둔다(거둔 식량은 그 자리에 더미로)
    const C = META.colony, s = S(), d = META.time.day; let left = Math.max(1, Math.round(RATE.plant * r / RATE.spec));
    for (let i = t.i; i < s.zone.length && left > 0; i++) {
      if (s.zone[i] !== ZONE_TYPES.field.id) continue; const c = C.crops[i];
      if (c && c.ready <= d) { delete C.crops[i]; dropPile(i % SW, (i / SW) | 0, '식량', RATE.field); got('식량', RATE.field); left--; }
      else if (!c) { C.crops[i] = { planted: d, ready: d + CROP_DAYS[glowIdx()] }; left--; }
    }
    C.changed = true; return true;
  },
  haul: (n, t) => { const C = META.colony, p = C.piles.find((q) => q.id === t.pid); if (!p) return true; C.piles = C.piles.filter((q) => q !== p); addStock(p.m, p.n); n.carry = p.m; META.colony.changed = true; return true; },
  gather: (n, t, r) => {
    t.prog += r; if (t.prog < t.h - 1e-6) return false;
    const s = S(), g = GATHER[t.what]; if (!TERRAIN[s.terr[t.i]].cut) return true;
    s.terr[t.i] = t.what === 'tree' ? TR.grass : TR.dirt;
    if (t.what === 'tree') META.colony.sprouts.push({ i: t.i, day: META.time.day + REGROW_DAYS[glowIdx()] });
    dropPile(t.x, t.y, g.m, g.n); got(g.m, g.n); META.colony.changed = true;
    return true;
  },
};
const got = (m, n) => { const g = META.colony.sum.got; g[m] = (g[m] || 0) + n; };

/* ---------- 새 땅: 근처 자원을 넉넉히 (§5) ---------- */
export function ensureNearResources(s = S(), seed = 1) {
  let r = seed >>> 0; const rnd = () => { r = (r * 1664525 + 1013904223) >>> 0; return r / 4294967296; };
  const pad = (k) => (k === 'ore' ? 0 : NEAR_RES.pad), count = (t, R) => { let c = 0; for (let i = 0; i < s.terr.length; i++) { const x = i % SW, y = (i / SW) | 0; if (s.terr[i] === t && (x - SCX) ** 2 + (y - SCY) ** 2 <= R * R) c++; } return c; }; // 광맥은 처음부터 빛 안에
  for (const [k, want] of [['tree', NEAR_RES.tree], ['rock', NEAR_RES.rock], ['ore', NEAR_RES.ore]]) {
    const R = radius() + pad(k); let need = want - count(TR[k], R);
    for (let tries = 0; need > 0 && tries < 2000; tries++) {
      const a = rnd() * Math.PI * 2, d = 5 + rnd() * (R - 5), x = Math.round(SCX + Math.cos(a) * d), y = Math.round(SCY + Math.sin(a) * d), i = I(x, y);
      if (x < 1 || y < 1 || x >= SW - 1 || y >= SW - 1 || (s.terr[i] !== TR.grass && s.terr[i] !== TR.dirt) || s.wall[i] || s.floor[i] || s.zone[i]) continue;
      if (s.furn.some((f) => Math.abs(f.x - x) <= 1 && Math.abs(f.y - y) <= 1) || Math.hypot(x - SCX, y - SCY) < 4) continue;
      s.terr[i] = TR[k]; need--;
    }
  }
}
