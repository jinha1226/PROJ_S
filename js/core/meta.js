import { ROOMS } from '../data/build.js';
import { CLASS_RULE } from '../data/classes.js';
import { CLOCK } from '../data/colony.js';
import { APPEAR, ITEMS } from '../data/items.js';
import { LEVEL_XP } from '../data/stones.js';
import { CRAFT_B, HAIRS, HERO_NAMES, JOBS, JOB_CLOTH, JOB_IDS, NAMES, ORIGINS, SKINS, TRAITS, adj } from '../data/town.js';
import { validLevels } from '../sim/classes.js';
import { pick, rand, ri, shuffle } from '../util/rng.js';
import { jo } from '../util/text.js';
import { passHours } from './colony.js';
import { calcStats, craftArmor, craftWeapon, fullyKnown, gearName, makeGear, migrateGear, migrateSets, newJewelLook, revealAll, starterKit } from './gear.js';
import { newProg, spentOf } from './progress.js';
import { hasRoom, migrateTown } from './settlement.js';
import { ageVisitors, rollVisitors } from './visitors.js';

export let META = null;

export function defaultMeta() {
  META = { v: 11, gen: 0, visits: 0, cleared: [false, false, false, false], npcs: [], newNpcs: [], buildings: { plaza: { shown: true }, gate: { shown: true }, altar: { shown: true }, storage: { shown: true }, forge: { shown: true } },
    mats: { 약초: 2, 가죽: 1, 광석: 2, 마석: 5 }, items: { heal: 1, ember_jar: 1 }, gear: [], recipes: {}, hero: null, fallen: [], closed: {}, buff: null, ending: null,
    lit: [false, false, false, false], visitors: [], lore: [], glowMods: [], rememberedKeepers: [], needSuccessor: false, watcher: null, unrandsSeen: [], relics: [] };
  const k = makeNpc('keeper'), b = makeNpc('blacksmith'); META.npcs.push(k); initRel(k); META.npcs.push(b); initRel(b); // 제단지기 출신 학자 · 대장장이
  migrateTown(META); // 모닥불 · 출발문 · 재료 더미 · 제단 + 대장간
  return META;
}

export function loadMeta() { try { const s = localStorage.getItem('torch-meta-v3'); if (s) { META = JSON.parse(s); migrateMeta(META); return META; } } catch (_) { /* 저장소 없음 */ } return defaultMeta(); }
/** 저장 형식 v3(무기 두 자루·갑옷) → v4(장비 칸·가방·창고) → v5(모닥불·방문자·등불 조각) */
function migrateMeta(M) {
  if ((M.v || 3) < 4) migrate4(M);
  if (M.v < 5) {
    Object.assign(M, { lit: M.cleared.slice(), visitors: [], lore: [], glowMods: [], needSuccessor: !M.hero && M.fallen.length > 0 && M.npcs.length > 0, watcher: null, ending: M.ending ? 'dawn' : null });
    M.v = 5;
  }
  if (M.v < 6) { migrateGear(M); if (M.hero) { const n = Math.max(1, M.hero.slots.filter((q) => q.stone).length); M.hero.level = n; M.hero.xp = LEVEL_XP[n - 1]; } M.v = 6; }
  if (M.v < 8) { migrateSets(M); M.v = 8; }
  if (M.v < 9 || !M.settle) { migrateTown(M); M.v = 9; } // 고정 건물 → 방 (docs/설계_정착지_건설.md)
  if (M.v < 10) { migrateProg(M); M.v = 10; } // 성장: 레벨 10 · Class 점수 (docs/설계_직업.md)
  if (M.v < 11) { migrateColony(M); M.v = 11; } // 정착지 2단계: 생활 직업 다섯 · 시간 · 마석 경제 (docs/설계_정착지_2단계.md)
  M.rememberedKeepers ||= [];
  if (M.hero) { M.hero.torch ??= 100; M.hero.look ||= {}; if (!M.hero.look.ember_jar) M.hero.look.ember_jar = { name: '불씨 단지', color: 0xffc45c }; M.hero.known ||= {}; M.hero.known.ember_jar = true; }
}
/** v9 → v10: 옛 레벨(1~6) → 새 레벨, 찍지 않은 점수로. 주민에게도 성장 기록 */
function migrateProg(M) {
  const h = M.hero;
  if (h && !h.prog) {
    const lv = Math.max(1, Math.min(CLASS_RULE.cap, h.level || 1)), b = h.cls && validLevels(h.cls.levels) && spentOf(h.cls) <= lv ? h.cls : { levels: {} };
    h.prog = { level: lv, xp: CLASS_RULE.xp[lv - 1], points: lv - spentOf(b), build: b }; delete h.cls;
  }
  for (const n of [...(M.npcs || []), ...(M.newNpcs || []), ...(M.visitors || []).map((v) => v.npc)]) if (n && !n.prog) n.prog = newProg();
}
/** v10 → v11: 옛 직업 → 출신 + 생활 직업, 기름·얼음 → 마석, 식량·시간·일 */
function migrateColony(M) {
  for (const n of [...(M.npcs || []), ...(M.newNpcs || []), ...(M.visitors || []).map((v) => v.npc)]) {
    if (!n) continue;
    if (!JOBS[n.job]) { n.origin = n.job; n.job = (ORIGINS[n.job] || ORIGINS.cook).job; }
    n.origin ||= n.job; n.work ||= { auto: true, pri: {} };
  }
  if (M.hero && M.hero.job && !JOBS[M.hero.job] && ORIGINS[M.hero.job]) { M.hero.origin = M.hero.job; M.hero.job = ORIGINS[M.hero.job].job; }
  const m = M.mats || (M.mats = {});
  for (const k of ['기름', '얼음']) if (m[k]) { m.마석 = (m.마석 || 0) + m[k]; delete m[k]; }
  if (M.settle) { const st = M.settle.stock || (M.settle.stock = {}); st.식량 ??= 20; st.식사 ??= 0; }
}
function migrate4(M) {
  M.gear = [...(M.weapons || []).map(craftWeapon), ...(M.armors || []).map(craftArmor)];
  delete M.weapons; delete M.armors;
  const h = M.hero;
  if (h && !h.eq) {
    h.eq = { weapon: craftWeapon(h.wpn[h.wi || 0]), off: craftWeapon(h.wpn[(h.wi || 0) ^ 1]), head: null, body: h.armor ? craftArmor(h.armor) : makeGear('body_cloth'), hands: null, feet: null, neck: null, ring1: null, ring2: null };
    h.bag = []; delete h.wpn; delete h.wi; delete h.armor;
    h.max = h.base + calcStats(h.eq).maxHp; h.hp = Math.min(h.hp, h.max);
  }
  M.v = 4;
}

export function saveMeta() { try { if (META) localStorage.setItem('torch-meta-v3', JSON.stringify(META)); } catch (_) { /* 저장 실패는 무시 */ } }

/**
 * 새 주민. origin = 출신(옛 직업 — 모습과 사연), job = 생활 직업 다섯 중 하나(docs/설계_정착지_2단계.md §2).
 * 인자는 출신이나 직업 어느 쪽이든 된다. 없으면 마을에 없는 직업 쪽으로 75% 기운다
 */
export function makeNpc(want) {
  const everyone = [...(META?.npcs || []), ...(META?.newNpcs || []), ...(META?.visitors || []).map((v) => v.npc)];
  let origin = ORIGINS[want] ? want : null, job = origin ? ORIGINS[origin].job : JOBS[want] ? want : null;
  if (!job) { const have = new Set(everyone.map((n) => n.job)), miss = JOB_IDS.filter((j) => !have.has(j)); job = miss.length && rand() < 0.75 ? pick(miss) : pick(JOB_IDS); }
  if (!origin) origin = pick(Object.keys(ORIGINS).filter((o) => ORIGINS[o].job === job));
  const used = new Set(everyone.map((n) => n.name)), free = NAMES.filter((x) => !used.has(x));
  const t = {}; for (const [k] of TRAITS) t[k] = ri(-2, 2);
  return { id: 'n' + Math.floor(rand() * 1e9).toString(36), name: free.length ? pick(free) : pick(NAMES), job, origin, t, mood: 0, rel: {}, look: { skin: pick(SKINS), hair: pick(HAIRS), cloth: JOB_CLOTH[origin] ?? JOB_CLOTH[job] }, prog: newProg(), work: { auto: true, pri: {} } };
}

/** 궁합: 원만할수록, 성실성·정직이 비슷할수록 좋다. 외향성은 비슷한 사람끼리 편하다(과묵한 둘도 서로 싫어하지 않는다) */
export const affinity = (a, b) => Math.round((a.t.A + b.t.A) * 6 - Math.abs(a.t.C - b.t.C) * 7 + (a.t.H + b.t.H) * 3 - Math.abs(a.t.H - b.t.H) * 3 - Math.abs(a.t.X - b.t.X) * 2 + 10);

/** 가장 두드러진 성격 하나 — 'H+' 같은 키 */
export function dominant(n) { let best = 'H'; for (const [k] of TRAITS) if (Math.abs(n.t[k]) > Math.abs(n.t[best])) best = k; return best + (n.t[best] >= 0 ? '+' : '-'); }

export function initRel(n) { for (const m of META.npcs) if (m !== n) { const v = affinity(n, m) + ri(-8, 8); n.rel[m.id] = v; m.rel[n.id] = v; } }

export function rel(a, b, d) { const v = Math.max(-100, Math.min(100, (a.rel[b.id] || 0) + d)); a.rel[b.id] = v; b.rel[a.id] = v; }

export const moodAdd = (n, d) => { n.mood = Math.max(-2, Math.min(2, n.mood + d)); };

export function craftNote(n) {
  const o = [];
  if (n.t.C >= 1) o.push('성실해서 가끔 하나 더 만든다'); if (n.t.C <= -1) o.push('대충 해서 품질이 떨어질 때가 있다');
  if (n.t.O >= 1) o.push('호기심이 많아 좋은 품질이 잘 나온다');
  if (n.mood <= -1) o.push('기분이 나빠 손이 굳었다'); if (n.mood >= 1) o.push('기분이 좋아 손끝이 가볍다');
  return o.join(' · ') || '무난한 솜씨';
}

/** 새 등불지기. from = 횃불을 이은 주민(이름·외형·직업·시작 특성) */
export function newHero(from) {
  META.gen++;
  const look = {};
  for (const cat of ['potion', 'scroll', 'throw']) { const looks = shuffle(APPEAR[cat].slice()); Object.keys(ITEMS).filter((k) => ITEMS[k].cat === cat).forEach((k, j) => { look[k] = { name: looks[j][0], color: looks[j][1] }; }); }
  let base = 30 + Math.min(15, Math.max(0, META.npcs.length - 2) * 2); const { eq, bag } = starterKit();
  const prog = from && from.prog ? from.prog : newProg(); base += CLASS_RULE.hpLevel * (prog.level - 1); // 주민이 등불을 이으면 그 사람의 성장이 그대로 온다
  const h = { prog, level: prog.level, xp: prog.xp, name: from ? from.name : pick(HERO_NAMES), gen: META.gen, base, max: base, hp: base, torch: 100, inv: [], eq, bag, jlook: newJewelLook(), jknown: {}, slots: Array.from({ length: 6 }, () => ({ color: null, stone: null, cd: 0 })), sbag: [], sbagMax: 3, weakKnown: {}, known: { recall: true, ember_jar: true }, look, job: from ? from.job : null, npcLook: from ? from.look : null, perk: null };
  const perk = from ? dominant(from) : null;
  if (perk && ['H+', 'H-', 'E+', 'E-', 'X+', 'A+', 'C+', 'O+'].includes(perk)) h.perk = perk;
  if (h.perk === 'H+') h.sbagMax = 4;
  if (h.perk === 'E+') { h.inv.push({ k: 'heal', n: 1 }); base -= 2; }
  if (h.perk === 'E-') { base += 4; h.perkHp = 4; }
  if (h.perk === 'O+') { const un = Object.keys(ITEMS).filter((k) => k !== 'recall' && k !== 'ident'); h.known[pick(un)] = true; }
  h.base = h.max = h.hp = base;
  return h;
}

export const packLimit = () => Math.min(9, 3 + Math.floor(META.npcs.length / 2) + (META.hero && META.hero.perk === 'C+' ? 1 : 0));

export const invCount = (inv) => inv.reduce((a, b) => a + b.n, 0);

export function invAdd(inv, k, n = 1) { const s = inv.find((q) => q.k === k); if (s) s.n += n; else inv.push({ k, n }); }

/* ---------- 귀환 사건: 성격이 관계와 일에 드러난다 ---------- */
export function genEvents(out, r) {
  const N = META.npcs, ev = [], add = (icon, text) => ev.push({ icon, text });
  if (out.arrived.length) {
    const host = N.filter((m) => !out.arrived.includes(m) && m.t.X >= 1).sort((a, b) => b.t.X - a.t.X)[0];
    const names = out.arrived.map((n) => n.name).join(', '), last = out.arrived[out.arrived.length - 1].name;
    if (host) { for (const n of out.arrived) { rel(host, n, 25); moodAdd(n, 2); } add('🤝', `${adj(host, 'X')} ${jo(host.name, '이가')} 새로 온 ${names.replace(last, jo(last, '을를'))} 데리고 마을을 한 바퀴 돌았다.`); }
    else { for (const n of out.arrived) moodAdd(n, -1); add('😶', `새로 온 ${names.replace(last, jo(last, '은는'))} 아직 마을이 낯설어 말이 없었다.`); }
  }
  if (r.reason === 'death') { for (const n of N) moodAdd(n, n.t.E >= 1 ? -2 : -1); glowMod(-5, '등불지기의 죽음'); add('🕯', `마을이 쓰러진 ${jo(r.hero, '을를')} 기렸다. 비석에 이름을 새겼다.`); }
  // 다툼: 성실성 차이 + 나쁜 관계
  const pairs = []; for (let i = 0; i < N.length; i++) for (let j = i + 1; j < N.length; j++) pairs.push([N[i], N[j]]);
  const fights = pairs.filter(([a, b]) => Math.abs(a.t.C - b.t.C) >= 3 && (a.rel[b.id] || 0) < 20);
  if (fights.length && rand() < 0.6) {
    const [a, b] = pick(fights), dil = a.t.C > b.t.C ? a : b, lazy = dil === a ? b : a, bb = JOBS[dil.job].b;
    rel(a, b, -15); moodAdd(a, -1); moodAdd(b, -1); glowMod(-5, '다툼');
    if (CRAFT_B.includes(bb)) META.closed[bb] = `${jo(dil.name, '과와')} ${lazy.name}의 다툼`;
    add('💢', `${adj(dil, 'C')} ${jo(dil.name, '과와')} ${adj(lazy, 'C')} ${jo(lazy.name, '이가')} 일하는 방식을 두고 다퉜다.${CRAFT_B.includes(bb) ? ` 한동안 ${ROOMS[bb].name} 일이 멈췄다.` : ''}`);
  } else {
    const grumpy = N.filter((n) => n.t.A <= -1), soft = N.filter((n) => n.t.A >= 1);
    if (grumpy.length && soft.length && rand() < 0.4) { const a = pick(grumpy), b = pick(soft); rel(a, b, -8); moodAdd(b, -1); add('😤', `${adj(a, 'A')} ${jo(a.name, '이가')} ${b.name}에게 쏘아붙였다. ${jo(b.name, '은는')} 참고 넘어갔다.`); }
  }
  // 슬쩍
  const thieves = N.filter((n) => n.t.H <= -1), mats = Object.keys(META.mats).filter((m) => META.mats[m] > 0);
  if (thieves.length && mats.length && rand() < 0.4) {
    const t = pick(thieves), honest = N.filter((n) => n !== t && n.t.H >= 1)[0], m = pick(mats);
    if (honest) { rel(honest, t, -20); glowMod(-5, '도둑질 소동'); add('🧐', `${adj(t, 'H')} ${jo(t.name, '이가')} ${jo(m, '을를')} 슬쩍하려다 ${adj(honest, 'H')} ${honest.name}에게 붙잡혀 돌려놓았다.`); }
    else { META.mats[m]--; glowMod(-5, '도둑질'); add('🫳', `${m} 하나가 없어졌다. ${adj(t, 'H')} ${jo(t.name, '이가')} 딴청을 부렸다.`); }
  }
  // 걱정
  if (r.hurt || r.reason === 'death') { const w = N.filter((n) => n.t.E >= 1)[0]; if (w) { META.items.heal = (META.items.heal || 0) + 1; add('💗', `${adj(w, 'E')} ${jo(w.name, '이가')} 걱정하며 회복 물약을 하나 챙겨 두었다.`); } }
  // 발견
  const cur = N.filter((n) => n.t.O >= 1);
  if (cur.length && rand() < 0.5) {
    const c = pick(cur), m = pick(['약초', '광석', '가죽', '마석']); META.mats[m] = (META.mats[m] || 0) + 1; add('🔍', `${adj(c, 'O')} ${jo(c.name, '이가')} 마을 뒤편에서 ${jo(m, '을를')} 찾아왔다.`);
  }
  // 잔치
  const good = pairs.filter(([a, b]) => a.t.A >= 1 && b.t.A >= 1 && (a.rel[b.id] || 0) > 20);
  // 화해: 사이 나쁜 둘 중 하나가 너그러우면
  const sour = pairs.filter(([a, b]) => (a.rel[b.id] || 0) <= -20 && (a.t.A >= 1 || b.t.A >= 1));
  if (sour.length && rand() < 0.35) { const [a, b] = pick(sour), soft = a.t.A >= b.t.A ? a : b, other = soft === a ? b : a; rel(a, b, 25); moodAdd(a, 1); moodAdd(b, 1); glowMod(5, '화해'); add('🤝', `${adj(soft, 'A')} ${jo(soft.name, '이가')} 먼저 ${other.name}에게 말을 걸었다. 둘은 불가에서 화해했다.`); }
  if (good.length && rand() < 0.4) { const [a, b] = pick(good); for (const n of N) moodAdd(n, 1); rel(a, b, 10); glowMod(5, '잔치'); add('🎉', `${jo(a.name, '과와')} ${jo(b.name, '이가')} 모닥불 잔치를 열었다. 모두 기분이 좋아졌다.`); }
  if (!ev.length) { add('🌤', '조용한 하루였다. 다들 제 할 일을 했다.'); for (const n of N) if (n.t.C >= 1) moodAdd(n, 1); }
  return ev.slice(0, 4);
}

/** 다음 귀환까지 유지되는 밝기 증감 */
export function glowMod(v, why) { META.glowMods.push({ v, why }); }


export function processReturn(r) {
  META.visits++; META.closed = {}; META.glowMods = [];
  for (const n of META.npcs) n.mood = Math.trunc(n.mood / 2);
  const out = { reason: r.reason, arrived: [], wants: [], events: [], visitors: [], left: [], shard: 0 };
  for (const n of META.newNpcs) {
    META.npcs.push(n); initRel(n); out.arrived.push(n);
    const b = JOBS[n.job].b; if (ROOMS[b] && !hasRoom(b)) out.wants.push(b); // 작업방은 건설에서 짓는다
  }
  META.newNpcs = [];
  const real = r.reason && r.reason !== 'first' && r.reason !== 'resume';
  if (real) out.colony = passHours((r.zf || 1) * CLOCK.floorHours); // 원정 동안 마을이 굴러간 만큼(최대 3일)
  if (real) out.events = genEvents(out, r);
  // 등불 조각: 보스를 처음 쓰러뜨린 구역의 기억을 모닥불에 넣는다
  if (r.reason === 'boss' && !META.lit[r.zone - 1]) { META.lit[r.zone - 1] = true; out.shard = r.zone; }
  if (r.reason === 'boss' && r.first) { META.items.recall = (META.items.recall || 0) + 1; out.recallReward = true; }
  if (r.reason === 'boss' && META.hero && META.hero.perkHp) { const h = META.hero; h.base -= h.perkHp; h.max -= h.perkHp; h.hp = Math.min(h.hp, h.max); h.perkHp = 0; }
  if (out.shard === 4 && META.ending !== 'dawn') { META.ending = 'dawn'; out.ending = true; }
  if (real) { out.left = ageVisitors(); out.visitors = rollVisitors(); }
  // 학자는 귀환할 때마다 창고의 미확인 장비 하나를 확인해 준다
  const sch = META.npcs.find((n) => n.job === 'scholar'), unk = real && sch && META.gear.find((g) => !fullyKnown(g));
  if (unk) { revealAll(unk); out.events.push({ icon: '📜', text: `${jo(sch.name, '이가')} 창고의 장비를 살펴보았다. ${gearName(unk)}.` }); }
  if (r.reason === 'death') { if (!META.npcs.length) out.dark = true; else META.needSuccessor = true; }
  return out;
}

export function resetMeta() { META = null; }
