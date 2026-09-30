// 전투 측정: 11×11 방에서 층별 표준 무리와 봇이 20번씩 싸워 전투 시간·HP 손실을 잰다 (docs/설계_전투_코어.md §1·§6)
// 사용: node tools/arena.mjs [판 수=20] [무기=sword]
// 봇: 예고 칸·힘 모으는 적의 닿는 거리 안에 있으면 빠져나가고, 아니면 가장 가까운 적에게 다가가 무기 박자에 맡긴다(서툰 사람의 손)
import { setIntent, step } from '../js/core/clock.js';
import { rad } from '../js/core/space.js';
import { G, isFoe } from '../js/core/state.js';
import { COMBAT } from '../js/data/realtime.js';
import { shapeOf } from '../js/sim/weapon.js';
import { rand } from '../js/util/rng.js';
import { arena, events } from '../tests/sim/harness.mjs';

const RUNS = +(process.argv[2] || 20), WEAPON = process.argv[3] || 'sword';
const REACT = 0.2, NOTICE = 0.7; // 봇의 반응 시간(초) · 예고를 알아채는 확률
const PACKS = [
  { name: '고블린 3 + 주술사', foes: [[4, -1, 'goblin'], [4, 1, 'goblin'], [5, 0, 'goblin'], [5, 2, 'shaman']], goal: [5, 15], loss: [15, 35] },
  { name: '쥐 떼 3', foes: [[4, -1, 'rat'], [4, 0, 'rat'], [4, 1, 'rat']], goal: [5, 15], loss: [15, 35] },
  { name: '마법사 1 (번개)', foes: [[5, 0, 'mage', { elem: 'bolt' }]], goal: [5, 15], loss: [15, 35] },
  { name: '고블린 족장', foes: [[4, 0, 'chief']], goal: [30, 60], loss: [50, 90] },
];

let BY = {};
const foes = () => G.ents.filter((e) => e.alive && isFoe(e) && !e.npc);
/** (x, y)가 위험한가: 차오르는 예고 칸 안, 또는 힘 모으는 적의 닿는 거리 안 */
function danger(x, y) {
  const cx = Math.round(x), cy = Math.round(y);
  for (const e of foes()) {
    const a = e.act; if (!a || a.done) continue;
    if (a.seen == null) a.seen = rand() < NOTICE; // 사람처럼: 못 보고 지나치는 예고가 있다
    if (!a.seen || a.t < REACT) continue; // 반응 시간
    if (a.tele && a.tele.cells.some(([tx, ty]) => tx === cx && ty === cy)) return true;
    if (a.kind === 'melee' && Math.hypot(e.px - x, e.py - y) <= COMBAT.reach + COMBAT.whiff + 0.1) return true;
  }
  return false;
}
function botDir() {
  const p = G.player, list = foes(); if (!list.length) return null;
  if (danger(p.px, p.py)) { // 빠져나갈 방향: 8방향 중 1칸 앞이 안전하고 벽이 아닌 곳
    let best = null, bs = -Infinity;
    for (let k = 0; k < 8; k++) {
      const a = (k * Math.PI) / 4, nx = p.px + Math.cos(a), ny = p.py + Math.sin(a);
      if (G.tile[Math.round(ny) * G.W + Math.round(nx)] !== 1) continue;
      const s = (danger(nx, ny) ? -10 : 0) + Math.min(...list.map((e) => Math.hypot(e.px - nx, e.py - ny))) * 0.3;
      if (s > bs) { bs = s; best = [Math.cos(a), Math.sin(a)]; }
    }
    return best;
  }
  const t = list.sort((a, b) => Math.hypot(a.px - p.px, a.py - p.py) - Math.hypot(b.px - p.px, b.py - p.py))[0], d = Math.hypot(t.px - p.px, t.py - p.py);
  const sh = shapeOf(), reach = sh.kind === 'proj' ? sh.range - 1 : sh.reach + rad(t) * 0.3;
  if (d <= reach) return null;
  return [(t.px - p.px) / d, (t.py - p.py) / d];
}

function fight(pack, seed) {
  arena(pack.foes.map(([x, y, type, o = {}]) => [x, y, type, { awake: true, ...o }]), { weapon: WEAPON, body: 'body_cloth', seed, size: 5 });
  const p = G.player; p.hp = p.max = 30; G.level = 99; // 싸우는 도중 레벨업 회복이 끼지 않게
  G.hurtLog = { push: (x) => { const k = x.who + (x.kind !== 'hit' ? `·${x.kind}` : ''); BY[k] = (BY[k] || 0) + x.amt; }, length: 0, shift() {}, slice: () => [] }; // 누구에게 얼마나 맞았나
  let t = 0;
  for (; t < 120 / 0.05 && p.alive && foes().length; t++) { const d = botDir(); setIntent(d, !d); step(); }
  setIntent(null, false);
  const taken = events.filter((e) => e.type === 'hit' && e.id === 0).reduce((a, e) => a + e.amt, 0);
  return { secs: t * 0.05, loss: (Math.min(30, taken) / 30) * 100, died: !p.alive };
}

const q = (xs, k) => { const s = [...xs].sort((a, b) => a - b); return s[Math.min(s.length - 1, Math.floor(k * s.length))]; };
console.log(`무기 ${WEAPON} · ${RUNS}판씩 · 등불지기 HP 30`);
console.log('무리                 | 시간 중앙(초) 25~75%   | HP 손실 중앙(%)  | 사망 | 목표');
for (const pack of PACKS) {
  BY = {};
  const rs = Array.from({ length: RUNS }, (_, k) => fight(pack, 100 + k));
  const T = rs.map((r) => r.secs), L = rs.map((r) => r.loss), dead = rs.filter((r) => r.died).length;
  const ok = (v, [a, b]) => (v >= a && v <= b ? '✓' : '✗');
  console.log(`${pack.name.padEnd(18)} | ${q(T, 0.5).toFixed(1).padStart(5)} ${ok(q(T, 0.5), pack.goal)}  (${q(T, 0.25).toFixed(1)}~${q(T, 0.75).toFixed(1)}) | ${q(L, 0.5).toFixed(0).padStart(4)} ${ok(q(L, 0.5), pack.loss)} (${q(L, 0.25).toFixed(0)}~${q(L, 0.75).toFixed(0)}) | ${String(dead).padStart(3)}  | ${pack.goal.join('~')}초 · ${pack.loss.join('~')}%`);
  console.log(`${' '.repeat(20)} 판당 받은 피해: ${Object.entries(BY).map(([k, v]) => `${k} ${(v / RUNS).toFixed(1)}`).join(' · ') || '없음'}`);
}
