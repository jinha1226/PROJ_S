import { PERKS } from '../data/visitors.js';
import { META, dominant, moodAdd, newHero, saveMeta } from './meta.js';

/* ================= 등불지기 잇기 =================
   쓰러지면 주민이 횃불을 잇는다. 아무도 없으면 불이 꺼진다(나쁜 결말). */

/** 자원 순서: 두려움 없음(감정성 낮음) → 책임감(정직 높음) → 남을 위해(원만성 높음) */
const volScore = (n) => -n.t.E * 100 + n.t.H * 10 + n.t.A;
export function volunteers() {
  const N = META.npcs.slice().sort((a, b) => volScore(b) - volScore(a));
  return N.slice(0, N.length >= 4 ? 3 : 2);
}
export const perkOf = (n) => { const k = dominant(n); return PERKS[k] ? k : null; };

/** 고른 주민이 정착지를 떠나 등불지기가 된다. 일터는 비고, 이웃들의 기분이 관계만큼 내려간다 */
export function takeTorch(n) {
  META.npcs.splice(META.npcs.indexOf(n), 1);
  for (const m of META.npcs) { const r = m.rel[n.id] || 0; delete m.rel[n.id]; moodAdd(m, r >= 20 ? -2 : r >= 0 ? -1 : 0); }
  META.hero = newHero(n); META.needSuccessor = false;
  saveMeta();
  return META.hero;
}

/** 나쁜 결말: 저장을 지운다 */
export function extinguish() {
  META.ending = 'dark';
  try { localStorage.removeItem('torch-meta-v3'); } catch (_) { /* 없음 */ }
}
