import { CRAFT_BY_ID, CRYSTALS, QUAL } from '../data/colony.js';
import { GEAR_BASES, plusMax } from '../data/gear.js';
import { JOBS } from '../data/town.js';
import { rand } from '../util/rng.js';
import { makeGear } from './gear.js';
import { META } from './meta.js';
import { addStock, missing, roomTier, rooms } from './settlement.js';

/* ================= 제작 (docs/설계_정착지_2단계.md §9) =================
   META.colony.orders = [{ id, rid, n(남은 개수), prog, paid, target(장비 uid), crystal }] · stations = { 방: 주민 id } (없으면 그 방 직업 주민) */

export const roomOfKind = (k) => rooms().find((r) => r.kind === k) || null;
export const tierOf = (k) => roomTier(roomOfKind(k));
/** 이 작업방에 서는 사람: 정해 둔 사람, 없으면 그 방 직업 주민 중 첫째 */
export function stationWorker(k) {
  const C = META.colony; if (!C || !roomOfKind(k)) return null;
  const id = C.stations[k]; if (id === 'none') return null;
  const set = id && META.npcs.find((n) => n.id === id);
  return set || META.npcs.find((n) => JOBS[n.job].b === k && !Object.values(C.stations).includes(n.id)) || null;
}
/** 찾을 장비(창고 · 등불지기 장착 · 가방) */
export function findGear(uid) {
  const h = META.hero, pools = [META.gear || [], h ? Object.values(h.eq || {}).filter(Boolean) : [], h ? h.bag || [] : []];
  for (const p of pools) { const it = p.find((q) => q && q.uid === uid); if (it) return it; }
  return null;
}
/** 주문 한 개의 비용 */
export function orderCost(o) {
  const R = CRAFT_BY_ID[o.rid], c = { ...R.in };
  if (R.out.enhance) { const it = findGear(o.target); c.마석 = 2 * ((it ? it.plus || 0 : 0) + 1); }
  if (R.crystal && o.crystal) c[o.crystal] = (c[o.crystal] || 0) + R.crystal;
  return c;
}
/** 주문이 지금 될 수 있는가: 등급 · 재료 · 대상 */
export function orderWhy(o) {
  const R = CRAFT_BY_ID[o.rid], t = tierOf(R.room);
  if (!t) return '작업방이 없다';
  if (META.closed && META.closed[R.room]) return `${META.closed[R.room]}으로 멈췄다(다음 귀환까지)`;
  if (R.out.buff && META.buff) return '이미 다음 원정 준비가 되어 있다';
  if (t < R.tier) return `${R.tier}등급 작업방이 필요하다`;
  if (R.crystal && !o.crystal) return '원소 결정을 고른다';
  if ((R.out.enhance || R.out.quality || R.out.brand || R.out.ego) && !findGear(o.target)) return '장비를 고른다';
  if (R.out.enhance) { const it = findGear(o.target); if ((it.plus || 0) >= plusMax(it)) return '더 강화할 수 없다'; }
  if (R.out.quality) { const it = findGear(o.target); if (!it.q || it.q >= Math.min(QUAL.max, t + 1)) return '이 작업방에서는 더 올릴 수 없다'; }
  if (!o.paid && Object.keys(missing(orderCost(o))).length) return '재료가 모자란다';
  return null;
}
export function addOrder(rid, o = {}) { const C = META.colony; const ord = { id: C.nid++, rid, n: o.n || 1, prog: 0, paid: false, target: o.target || null, crystal: o.crystal || null }; C.orders.push(ord); return ord; }
/** 이 방에서 지금 할 주문 */
export const orderFor = (k) => META.colony.orders.find((o) => CRAFT_BY_ID[o.rid].room === k && !orderWhy(o)) || null;

/** 품질: 등급 → 특기 · 성격 · 기분 */
export function rollQuality(n, tier, room) {
  let q = Math.max(1, Math.min(3, tier));
  if (n && JOBS[n.job].b === room && rand() < QUAL.spec) q++; // 특기: 제 방에서 일할 때만
  if (n && n.t.O >= 1 && rand() < QUAL.open) q++;
  if (n && n.t.C <= -1 && rand() < QUAL.sloppy) q--;
  if (n && n.mood >= 1 && rand() < QUAL.moodUp) q++;
  if (n && n.mood <= -1 && rand() < QUAL.moodDown) q--;
  return Math.max(1, Math.min(QUAL.max, q));
}

/** 한 시간 제작. 주문 하나가 끝나면(남은 개수 0) true */
export function craftStep(n, t, r) {
  const C = META.colony, o = C.orders.find((q) => q.id === t.oid); if (!o) return true;
  if (!o.paid) { if (orderWhy(o)) return true; for (const [m, k] of Object.entries(orderCost(o))) addStock(m, -k); o.paid = true; }
  o.prog += r;
  const R = CRAFT_BY_ID[o.rid]; if (o.prog < R.h - 1e-6) return false;
  const made = produce(R, o, n);
  if (made) C.sum.made.push(made);
  o.prog = 0; o.paid = false; o.n--;
  if (n && n.t.C >= 1 && R.out.item && rand() < 0.2) META.items[R.out.item] = (META.items[R.out.item] || 0) + 1; // 성실: 가끔 하나 더
  if (o.n <= 0) { C.orders = C.orders.filter((q) => q !== o); return true; }
  return false;
}
function produce(R, o, n) {
  const out = R.out, tier = tierOf(R.room);
  if (out.pick) {
    const base = out.pick[Math.floor(rand() * out.pick.length)], q = GEAR_BASES[base].jewel ? null : rollQuality(n, tier, R.room);
    const it = makeGear(base, { q, known: true });
    if (out.brandFromCrystal && o.crystal) it.brand = CRYSTALS[o.crystal].brand;
    (META.gear ||= []).push(it);
    return `${it.q && q >= 3 ? '좋은 ' : ''}${GEAR_BASES[base].name}`;
  }
  if (out.item) { META.items[out.item] = (META.items[out.item] || 0) + out.n; return R.name; }
  if (out.convert) { const spec = n && n.job === 'alchemist' ? 1.5 : 1; for (const [m, k] of Object.entries(out.convert)) addStock(m, Math.round(k * spec)); return R.name; }
  if (out.meal) { addStock('식사', out.meal * (n && JOBS[n.job].spec.includes('cook') ? 2 : 1)); return null; }
  if (out.buff) { META.buff = out.buff; return R.name; }
  const it = findGear(o.target); if (!it) return null;
  if (out.enhance) { it.plus = (it.plus || 0) + 1; return `${R.name}`; }
  if (out.quality) { it.q = Math.min(QUAL.max, (it.q || 1) + 1); return R.name; }
  if (out.brand) { it.brand = CRYSTALS[o.crystal].brand; it.idX = true; return R.name; }
  if (out.ego) { it.ego = CRYSTALS[o.crystal].ego; it.idX = true; return R.name; }
  return null;
}
