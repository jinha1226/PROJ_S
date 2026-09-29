import { VISIT } from '../data/lines.js';
import { MATS } from '../data/items.js';
import { JOBS } from '../data/town.js';
import { GLOW, LANDS, WANDER_JOBS, WORK_GIFT, residentCap } from '../data/visitors.js';
import { pick, rand } from '../util/rng.js';
import { META, affinity, dominant, initRel, makeNpc, moodAdd } from './meta.js';

/* ================= 모닥불 밝기 · 방문자 =================
   불은 사람으로 탄다: 주민 수·기분·관계·사건·등불 조각이 밝기를 정하고, 밝기가 방문자를 부른다. */
export const shardCount = () => (META.lit || []).filter(Boolean).length;
export const cap = () => residentCap(shardCount());

/** 밝기를 이루는 것들 [설명, 값] */
export function glowParts() {
  const N = META.npcs, parts = [['꺼지지 않는 불씨', GLOW.base]];
  if (N.length) parts.push([`주민 ${N.length}명`, N.length * GLOW.perNpc]);
  const sulky = N.filter((n) => n.mood <= -1).length; if (sulky) parts.push([`기분 나쁜 주민 ${sulky}명`, sulky * GLOW.badMood]);
  let good = 0, bad = 0;
  for (let i = 0; i < N.length; i++) for (let j = i + 1; j < N.length; j++) { const r = N[i].rel[N[j].id] || 0; if (r >= 20) good++; else if (r <= -20) bad++; }
  if (good) parts.push([`사이좋은 짝 ${good}`, good * GLOW.goodPair]);
  if (bad) parts.push([`사이 나쁜 짝 ${bad}`, bad * GLOW.badPair]);
  const sh = shardCount(); if (sh) parts.push([`넣은 등불 조각 ${sh}`, sh * GLOW.shard]);
  if (META.rememberedKeepers?.length) parts.push([`기억한 등불지기 ${META.rememberedKeepers.length}명`, META.rememberedKeepers.length]);
  for (const m of META.glowMods || []) parts.push([m.why, m.v]);
  return parts;
}
export const hearthGlow = () => Math.max(0, Math.min(100, glowParts().reduce((a, [, v]) => a + v, 0)));
export const visitChance = (g) => (g <= GLOW.low ? 0 : Math.min(1, (GLOW.visitBase + g * GLOW.visitPer) / 100));

/** 방문자 직업: 밝아진 땅 출신(정착지에 없는 직업이 조금 더 잘) — 아직 밝은 땅이 없으면 떠돌이 */
function visitorJob() {
  const lit = LANDS.filter((L) => META.lit[L.zone - 1]);
  const pool = lit.length ? lit.flatMap((L) => L.jobs.map((j) => [j, L.id])) : WANDER_JOBS.map((j) => [j, null]);
  const have = new Set(META.npcs.map((n) => n.job)), miss = pool.filter(([j]) => !have.has(j));
  return miss.length && rand() < 0.6 ? pick(miss) : pick(pool);
}

/** 귀환 때 방문자 판정 */
export function rollVisitors() {
  const g = hearthGlow(), out = [];
  if (g <= GLOW.low) return out;
  for (let k = 0; k < GLOW.maxVisitors; k++) {
    if (META.npcs.length + META.visitors.length >= cap()) break;
    if (rand() >= visitChance(g)) continue;
    const [job, land] = visitorJob(), npc = makeNpc(job); npc.from = land;
    const v = { npc, waits: 0, req: dominant(npc) };
    META.visitors.push(v); out.push(v);
  }
  return out;
}

/** 기다려 준 귀환 수를 세고, 두 번 기다리게 한 방문자는 세 번째 귀환에 떠난다 */
export function ageVisitors() {
  const left = [];
  for (const v of META.visitors) v.waits++;
  for (const v of META.visitors.filter((q) => q.waits > 2)) { left.push(v); META.visitors.splice(META.visitors.indexOf(v), 1); }
  return left;
}

const badMatch = (a, b) => affinity(a, b) < -10;
function payMats(n) { // 가장 많은 재료부터(마석 제외)
  const out = {}, pool = { ...META.mats }; delete pool.마석;
  for (let k = 0; k < n; k++) { const m = Object.keys(pool).filter((q) => pool[q] > 0).sort((a, b) => pool[b] - pool[a])[0]; if (!m) return null; pool[m]--; out[m] = (out[m] || 0) + 1; }
  return out;
}

/** 요청 상태: 받아들일 수 있나, 무엇을 치르나 */
export function requestState(v) {
  const N = META.npcs, n = v.npc, V = VISIT[v.req] || VISIT['E-'];
  let ok = true, line = V.line, pay = null, note = '';
  switch (v.req) {
    case 'H+': ok = N.some((m) => m.t.H >= 1); break;
    case 'H-': pay = payMats(3); ok = !!pay; if (pay) note = '건넬 재료: ' + Object.entries(pay).map(([m, k]) => `${MATS[m] || ''}${m} ${k}`).join(' · '); break;
    case 'E+': ok = N.some((m) => m.job === 'hunter') || !!META.buildings.hunter; break;
    case 'X+': ok = N.length >= 4; break;
    case 'X-': ok = N.length <= 6; break;
    case 'A-': { const foes = N.filter((m) => badMatch(n, m)); ok = !foes.length; line = foes.length ? line.replace('{who}', foes.map((m) => m.name).join(', ')) : '싫은 사람만 없으면 돼.'; if (foes.length) note = `궁합 나쁜 주민: ${foes.map((m) => m.name).join(', ')}`; break; }
    case 'O+': {
      const stone = META.hero && META.hero.sbag.length ? META.hero.sbag[0] : null;
      if ((META.mats.마석 || 0) >= 1) pay = { 마석: 1 }; else if (stone) pay = { stone };
      ok = !!pay; if (pay) note = pay.stone ? '건넬 것: 등불지기 가방의 영혼석 하나' : '건넬 것: 🔮마석 1';
      break;
    }
    case 'C+': { const g = WORK_GIFT[JOBS[n.job].b]; if (g) note = '가져온 것: ' + Object.entries(g).map(([m, k]) => `${MATS[m] || ''}${m} ${k}`).join(' · '); break; }
    default:
  }
  return { ok, line, need: V.need, pay, note };
}

/** 받아들이기 → 새 일터가 필요하면 그 건물 id */
export function acceptVisitor(v) {
  const st = requestState(v); if (!st.ok) return null;
  if (st.pay) {
    if (st.pay.stone) META.hero.sbag.splice(META.hero.sbag.indexOf(st.pay.stone), 1);
    else for (const [m, k] of Object.entries(st.pay)) META.mats[m] -= k;
  }
  const n = v.npc;
  META.visitors.splice(META.visitors.indexOf(v), 1);
  META.npcs.push(n); initRel(n);
  if (v.req === 'A+') for (const m of META.npcs) moodAdd(m, 1);
  if (v.req === 'C+') { const g = WORK_GIFT[JOBS[n.job].b]; if (g) for (const [m, k] of Object.entries(g)) META.mats[m] = (META.mats[m] || 0) + k; }
  const b = JOBS[n.job].b; let built = null;
  if (!META.buildings[b]) { META.buildings[b] = { shown: false }; built = b; }
  return { built };
}
export function dismissVisitor(v) { const i = META.visitors.indexOf(v); if (i >= 0) META.visitors.splice(i, 1); }
