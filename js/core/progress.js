import { BASE, CLASS_RULE } from '../data/classes.js';
import { validLevels } from '../sim/classes.js';

/* ================= 성장: 등불지기와 주민이 같은 규칙 (docs/설계_직업.md §3.4) =================
   prog = { level 1~10, xp, points(아직 찍지 않은 점수), build: { levels, main, branch, loadout } }. 레벨마다 점수 1 → 기본 Class 하나에 1 */

export const newProg = () => ({ level: 1, xp: 0, points: 1, build: { levels: {} } });
export const progOf = (rec) => (rec.prog ||= newProg());
export const levelOfXp = (xp) => { const T = CLASS_RULE.xp; let l = 1; while (l < T.length && xp >= T[l]) l++; return l; };
export const nextXp = (prog) => CLASS_RULE.xp[prog.level] ?? null;
export const spentOf = (b) => Object.values((b && b.levels) || {}).reduce((a, v) => a + v, 0);

/** 경험을 더한다. 오른 레벨 수를 돌려준다(레벨마다 점수 1) */
export function addXp(prog, n) {
  if (!(n > 0) || prog.level >= CLASS_RULE.cap) return 0;
  prog.xp += n;
  const to = Math.min(CLASS_RULE.cap, levelOfXp(prog.xp)), up = to - prog.level;
  if (up > 0) { prog.level = to; prog.points += up; }
  return Math.max(0, up);
}
/** 이 Class에 점수 하나를 찍을 수 있는가(Class 둘까지, 합은 레벨 이하) */
export function canSpend(build, cls, free) {
  if (!(free > 0) || !BASE[cls]) return false;
  const lv = { ...build.levels, [cls]: (build.levels[cls] || 0) + 1 };
  return validLevels(lv);
}
/** 점수 하나를 찍는다 */
export function spend(prog, cls) {
  if (!canSpend(prog.build, cls, prog.points)) return false;
  prog.build.levels = { ...prog.build.levels, [cls]: (prog.build.levels[cls] || 0) + 1 }; prog.points--;
  return true;
}
