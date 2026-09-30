import { AMT_KEYS, CSKILLS, DUR_KEYS } from '../data/class-skills.js';
import { BASE, BASE_IDS, BRANCHES, CLASS_RULE, MASTERY, PAIRS, ROLES, TRAITS, pairKey, potencyOf } from '../data/classes.js';

/* ================= 교차 성장: 레벨 분배 → Class · 수식어 · Role · 열린 스킬 · 위력 · 특성 (docs/설계_직업.md §3.4) =================
   build = { levels: { fighter: 7, cleric: 3 }, main: 'tank'(균형형만), branch: { fighter: 'A' }, loadout: ['f_block', …] } */

const R = CLASS_RULE;

/** 레벨 분배가 규칙에 맞는가: 총 10 이하, Class 둘 이하, 각 1~10 */
export function validLevels(levels) {
  const ks = Object.keys(levels || {}).filter((k) => levels[k] > 0);
  if (ks.length > 2 || ks.some((k) => !BASE[k])) return false;
  const tot = ks.reduce((a, k) => a + levels[k], 0);
  return tot <= R.cap && ks.every((k) => Number.isInteger(levels[k]) && levels[k] >= 1 && levels[k] <= R.cap);
}

/** 레벨 분배 → Class 정보 */
export function classOf(build) {
  const levels = build.levels || {}, ks = BASE_IDS.filter((k) => levels[k] > 0).sort((a, b) => levels[b] - levels[a] || BASE_IDS.indexOf(a) - BASE_IDS.indexOf(b));
  if (!ks.length) return { kind: 'none', name: '없음', title: '없음', role: null, sub: null, skills: [], traits: [], levels };
  const [a, b] = ks, la = levels[a], lb = b ? levels[b] : 0;
  const skills = [], traits = [];
  const baseSkills = (k, lv, upgraded) => BASE[k].skills.forEach((id, i) => { if (lv >= R.unlock[i]) skills.push({ id, cls: k, lv, upgraded: !!upgraded }); });
  let kind, name, title, role, sub = null, key = null, lean = null;
  if (!b && la >= R.cap) { // 한 우물
    const M = MASTERY[a]; kind = 'mastery'; key = a; name = title = M.name; role = M.role; sub = M.sub || null;
    baseSkills(a, la, true); M.skills.forEach((id) => skills.push({ id, cls: a, lv: la, sig: true }));
    traits.push({ id: BASE[a].trait, tier: 2 });
  } else if (!b || lb < R.pairMin) { // 기본(+ 곁가지)
    kind = b ? 'dip' : 'base'; key = a; name = BASE[a].name; role = BASE[a].role;
    title = b ? `${BASE[a].name} · ${BASE[b].name} ${lb}` : BASE[a].name;
    baseSkills(a, la); if (b) baseSkills(b, lb);
    traits.push({ id: BASE[a].trait, tier: 1 });
  } else { // 두 우물
    key = pairKey(a, b); const P = PAIRS[key]; kind = 'pair'; name = P.name;
    lean = la - lb >= R.leanGap ? a : null;
    title = lean ? `${BASE[lean].epi} ${P.name}` : P.name;
    const ra = BASE[a].role, rb = BASE[b].role;
    if (lean) { role = ra; sub = rb === ra ? null : rb; } else { role = build.main === rb ? rb : ra; sub = role === ra ? (rb === ra ? null : rb) : ra; }
    baseSkills(a, la); baseSkills(b, lb);
    P.skills.forEach((id) => { const aff = CSKILLS[id].aff; skills.push({ id, cls: aff, lv: levels[aff], sig: true, lean: lean ? (lean === aff ? 'self' : 'other') : null }); });
    traits.push({ id: BASE[a].trait, tier: 0 }, { id: BASE[b].trait, tier: 0 });
  }
  return { kind, key, name, title, role, sub, lean, skills, traits, levels: { ...levels }, roleName: ROLES[role].name };
}

/** 스킬의 최종 수치: 기본값 → 갈래 → 기울기 → 위력 → 한 우물 강화판 */
export function skillParams(info, build) {
  const S = CSKILLS[info.id], p = { ...S.p };
  let cd = S.cd, cast = S.cast;
  const br = build && build.branch && build.branch[info.cls];
  if (!info.sig && br && info.lv >= R.branchAt) { const m = BRANCHES[info.cls][br].mod[info.id]; if (m) for (const [k, v] of Object.entries(m)) { if (k === 'cdAdd') cd += v; else p[k] = v; } }
  if (info.lean && S[info.lean]) for (const [k, v] of Object.entries(S[info.lean])) { if (k === 'cd') cd = v; else p[k] = v; }
  const pot = potencyOf(info.lv);
  for (const k of AMT_KEYS) if (typeof p[k] === 'number' && p[k]) p[k] = k === 'mul' ? +(p[k] * pot).toFixed(3) : Math.max(1, Math.round(p[k] * pot));
  for (const k of DUR_KEYS) if (typeof p[k] === 'number' && p[k]) p[k] = +(p[k] * (0.75 + 0.25 * pot)).toFixed(2);
  cd = cd / (0.8 + 0.2 * pot);
  if (info.upgraded) { cd *= R.mastery.cd; for (const k of AMT_KEYS) if (typeof p[k] === 'number' && p[k]) p[k] = k === 'mul' ? +(p[k] * R.mastery.amt).toFixed(3) : Math.round(p[k] * R.mastery.amt); }
  return { p, cd: +cd.toFixed(2), cast, tgt: S.tgt, r: S.r };
}

/** 특성 값 */
export const traitVal = (u, id) => { const t = u && u.klass && u.klass.traits.find((q) => q.id === id); return t ? TRAITS[id].v[t.tier] : 0; };

/** 유닛에 Class를 입힌다: 열린 스킬 · 장착 3칸(없거나 잘못되면 앞에서부터) · 쿨타임 · 최대 HP 보너스 */
export function setClass(u, build) {
  const b = build && validLevels(build.levels) ? build : { levels: {} };
  const k = classOf(b), open = [...k.skills.filter((s) => s.sig), ...k.skills.filter((s) => !s.sig)].map((s) => s.id); // 기본 장착: 전용 스킬부터
  const load = (b.loadout || []).filter((id) => open.includes(id)).slice(0, R.slots);
  for (const id of open) if (load.length < R.slots && !load.includes(id)) load.push(id);
  u.build = { ...b, loadout: load };
  u.klass = k;
  u.skillInfo = Object.fromEntries(k.skills.map((s) => [s.id, s]));
  u.scd = u.scd || {};
  u.classHp = Math.round(Object.entries(b.levels || {}).reduce((a, [c, lv]) => a + (BASE[c] ? BASE[c].hpLv * lv : 0), 0));
  return k;
}

/** 장착한 스킬 셋의 최종 수치 */
export const loadoutOf = (u) => (u.build ? u.build.loadout : []).map((id) => ({ id, ...skillParams(u.skillInfo[id], u.build) }));
