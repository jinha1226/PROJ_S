// 전투 측정: 11×11 방에서 층별 표준 무리와 봇이 20번씩 싸워 전투 시간·HP 손실을 잰다 (docs/설계_전투_코어.md §1·§6)
// 사용: node tools/arena.mjs [판 수=20] [무기=sword]   ·   node tools/arena.mjs classes [판 수=10]  (Class별: 봇이 스킬을 AI 힌트대로 쓴다)
// 봇: 예고 칸·힘 모으는 적의 닿는 거리 안에 있으면 빠져나가고, 아니면 가장 가까운 적에게 다가가 무기 박자에 맡긴다(서툰 사람의 손)
import { setIntent, step } from '../js/core/clock.js';
import { rad } from '../js/core/space.js';
import { G, isFoe } from '../js/core/state.js';
import { COMBAT } from '../js/data/realtime.js';
import { shapeOf } from '../js/sim/weapon.js';
import { rand } from '../js/util/rng.js';
import { refreshStats } from '../js/core/gear.js';
import { arena, events } from '../tests/sim/harness.mjs';
import { BASE, BASE_IDS, PAIRS, ROLES } from '../js/data/classes.js';
import { classOf } from '../js/sim/classes.js';
import { aiPick, useSkill } from '../js/sim/skillfx.js';

const CLASSES = process.argv[2] === 'classes', RUNS = +(process.argv[CLASSES ? 3 : 2] || (CLASSES ? 10 : 20)), WEAPON = (!CLASSES && process.argv[3]) || 'sword';
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

function fight(pack, seed, cls) {
  arena(pack.foes.map(([x, y, type, o = {}]) => [x, y, type, { awake: true, ...o }]), { weapon: WEAPON, body: 'body_cloth', seed, size: 5, cls });
  refreshStats(); const p = G.player; p.hp = p.max = 30 + (G.ps.maxHp || 0); G.prog.level = 10; // 싸우는 도중 레벨업 회복이 끼지 않게
  G.hurtLog = { push: (x) => { const k = x.who + (x.kind !== 'hit' ? `·${x.kind}` : ''); BY[k] = (BY[k] || 0) + x.amt; }, length: 0, shift() {}, slice: () => [] }; // 누구에게 얼마나 맞았나
  let t = 0;
  for (; t < 120 / 0.05 && p.alive && foes().length; t++) {
    if (cls && t % 2 === 0) { const k = aiPick(p); if (k) useSkill(p, k.id, k.x, k.y); } // 스킬: AI 힌트대로(0.1초마다 생각)
    const d = botDir(); setIntent(d, !d); step();
  }
  setIntent(null, false);
  const taken = events.filter((e) => e.type === 'hit' && e.id === 0).reduce((a, e) => a + e.amt, 0);
  return { secs: t * 0.05, loss: (Math.min(p.max, taken) / p.max) * 100, died: !p.alive, end: Math.max(0, p.hp) / p.max };
}

const q = (xs, k) => { const s = [...xs].sort((a, b) => a - b); return s[Math.min(s.length - 1, Math.floor(k * s.length))]; };
if (CLASSES) runClasses(); else runPacks();
function runPacks() {
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
}

/** Class별: 한 우물 6 · 두 우물 15 × (7/3, 5/5, 3/7). 무기는 장검으로 고정해 Class만 비교한다 */
function runClasses() {
  const cfgs = [];
  for (const a of BASE_IDS) cfgs.push({ levels: { [a]: 10 } });
  for (const key of Object.keys(PAIRS)) { const [a, b] = key.split('+'); for (const [x, y] of [[7, 3], [5, 5], [3, 7]]) cfgs.push({ levels: { [a]: x, [b]: y }, main: x === y ? BASE[a].role : undefined }); }
  const rows = [];
  for (const b of cfgs) {
    const k = classOf(b); let T = 0, Lx = 0, D = 0, n = 0, E = 0;
    for (const pack of [PACKS[0], PACKS[3]]) for (let r = 0; r < RUNS; r++) { const f = fight(pack, 300 + r, b); T += f.secs / pack.goal[1]; Lx += f.loss; D += f.died ? 1 : 0; E += f.end; n++; }
    rows.push({ title: k.title, role: k.role, kind: k.kind === 'mastery' ? '한 우물' : k.lean ? '기운' : '균형', time: T / n, loss: Lx / n, died: D / n, end: E / n });
  }
  for (const role of Object.keys(ROLES)) {
    const rs = rows.filter((r) => r.role === role).sort((a, b) => a.time + a.loss / 100 - (b.time + b.loss / 100));
    console.log(`\n== ${ROLES[role].name} (시간 = 목표 상한 대비, 손실 = HP %, 사망률) — 둘 다 낮을수록 좋다`);
    for (const r of rs) console.log(`${r.title.padEnd(16)} ${r.kind.padEnd(4)}  시간 ${r.time.toFixed(2)}  받은 피해 ${r.loss.toFixed(0).padStart(3)}%  남은 HP ${(r.end * 100).toFixed(0).padStart(3)}%  사망 ${(r.died * 100).toFixed(0).padStart(3)}%`);
  }
}
