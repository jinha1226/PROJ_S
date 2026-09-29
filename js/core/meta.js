import { GEAR_BASES } from '../data/gear.js';
import { APPEAR, ITEMS } from '../data/items.js';
import { BLD, CRAFT_B, HAIRS, HERO_NAMES, JOBS, JOB_CLOTH, NAMES, RECIPES, SKINS, TRAITS, adj } from '../data/town.js';
import { ARMORS, FORMS, WPN } from '../data/weapons.js';
import { pick, rand, ri, shuffle } from '../util/rng.js';
import { jo } from '../util/text.js';
import { calcStats, craftArmor, craftWeapon, makeGear } from './gear.js';
import { ageVisitors, rollVisitors } from './visitors.js';

export let META = null;

export function defaultMeta() {
  META = { v: 5, gen: 0, visits: 0, cleared: [false, false, false, false], npcs: [], newNpcs: [], buildings: { plaza: { shown: true }, gate: { shown: true }, altar: { shown: true }, storage: { shown: true }, forge: { shown: true } },
    mats: { 약초: 2, 가죽: 1, 광석: 2 }, items: { heal: 1 }, gear: [], recipes: {}, hero: null, fallen: [], closed: {}, buff: null, ending: null,
    lit: [false, false, false, false], visitors: [], lore: [], glowMods: [], needSuccessor: false, watcher: null };
  const k = makeNpc('keeper'), b = makeNpc('blacksmith'); META.npcs.push(k); initRel(k); META.npcs.push(b); initRel(b);
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

export function makeNpc(job) {
  const all = ['blacksmith', 'herbalist', 'hunter', 'scholar', 'cook'], everyone = [...(META?.npcs || []), ...(META?.newNpcs || []), ...(META?.visitors || []).map((v) => v.npc)];
  if (!job) { const have = new Set(everyone.map((n) => n.job)), miss = all.filter((j) => !have.has(j)); job = miss.length && rand() < 0.75 ? pick(miss) : pick(all); }
  const used = new Set(everyone.map((n) => n.name)), free = NAMES.filter((x) => !used.has(x));
  const t = {}; for (const [k] of TRAITS) t[k] = ri(-2, 2);
  return { id: 'n' + Math.floor(rand() * 1e9).toString(36), name: free.length ? pick(free) : pick(NAMES), job, t, mood: 0, rel: {}, look: { skin: pick(SKINS), hair: pick(HAIRS), cloth: JOB_CLOTH[job] } };
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
  if (n.t.C >= 1) o.push('성실해서 가끔 하나 더 만든다'); if (n.t.C <= -1) o.push('대충 해서 명품이 드물다');
  if (n.t.O >= 1) o.push('호기심이 많아 명품(+)이 잘 나온다');
  if (n.t.H <= -1) o.push('재료를 슬쩍할 때가 있다');
  if (n.mood <= -1) o.push('기분이 나빠 손이 굳었다'); if (n.mood >= 1) o.push('기분이 좋아 손끝이 가볍다');
  return o.join(' · ') || '무난한 솜씨';
}

/** 새 등불지기. from = 횃불을 이은 주민(이름·외형·직업·시작 특성) */
export function newHero(from) {
  META.gen++;
  const look = {};
  for (const cat of ['potion', 'scroll', 'throw']) { const looks = shuffle(APPEAR[cat].slice()); Object.keys(ITEMS).filter((k) => ITEMS[k].cat === cat).forEach((k, j) => { look[k] = { name: looks[j][0], color: looks[j][1] }; }); }
  let base = 30 + Math.min(15, Math.max(0, META.npcs.length - 2) * 2); const starts = shuffle(['sword', 'mace', 'dagger']);
  const eq = { weapon: makeGear(starts[0]), off: makeGear(starts[1]), head: null, body: makeGear('body_cloth'), hands: null, feet: null, neck: null, ring1: null, ring2: null };
  const h = { name: from ? from.name : pick(HERO_NAMES), gen: META.gen, base, max: base, hp: base, inv: [], eq, bag: [], slots: Array.from({ length: 6 }, () => ({ color: null, stone: null, cd: 0 })), sbag: [], sbagMax: 3, weakKnown: {}, known: { recall: true }, look, job: from ? from.job : null, npcLook: from ? from.look : null, perk: null };
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
    if (host) { for (const n of out.arrived) { rel(host, n, 25); moodAdd(n, 2); } add('🤝', `${adj(host, 'X')} ${jo(host.name, '이가')} 새로 온 ${names.replace(last, jo(last, '을를'))} 마을 구석구석 데려가 금방 적응시켰다.`); }
    else { for (const n of out.arrived) moodAdd(n, -1); add('😶', `새로 온 ${names.replace(last, jo(last, '은는'))} 아직 마을이 낯설어 말수가 적다. (외향적인 이웃이 있었다면…)`); }
  }
  if (r.reason === 'death') { for (const n of N) moodAdd(n, n.t.E >= 1 ? -2 : -1); glowMod(-5, '등불지기의 죽음'); add('🕯', `마을이 쓰러진 ${jo(r.hero, '을를')} 기렸다. 비석에 이름을 새겼다.`); }
  // 다툼: 성실성 차이 + 나쁜 관계
  const pairs = []; for (let i = 0; i < N.length; i++) for (let j = i + 1; j < N.length; j++) pairs.push([N[i], N[j]]);
  const fights = pairs.filter(([a, b]) => Math.abs(a.t.C - b.t.C) >= 3 && (a.rel[b.id] || 0) < 20);
  if (fights.length && rand() < 0.6) {
    const [a, b] = pick(fights), dil = a.t.C > b.t.C ? a : b, lazy = dil === a ? b : a, bb = JOBS[dil.job].b;
    rel(a, b, -15); moodAdd(a, -1); moodAdd(b, -1); glowMod(-5, '다툼');
    if (CRAFT_B.includes(bb)) META.closed[bb] = `${jo(dil.name, '과와')} ${lazy.name}의 다툼`;
    add('💢', `${adj(dil, 'C')} ${jo(dil.name, '과와')} ${adj(lazy, 'C')} ${jo(lazy.name, '이가')} 일하는 방식을 두고 다퉜다.${CRAFT_B.includes(bb) ? ` — ${BLD[bb].name} 작업이 이번엔 멈췄다.` : ''}`);
  } else {
    const grumpy = N.filter((n) => n.t.A <= -1), soft = N.filter((n) => n.t.A >= 1);
    if (grumpy.length && soft.length && rand() < 0.4) { const a = pick(grumpy), b = pick(soft); rel(a, b, -8); moodAdd(b, -1); add('😤', `${adj(a, 'A')} ${jo(a.name, '이가')} ${b.name}에게 쏘아붙였다. ${jo(b.name, '은는')} 참고 넘어갔다.`); }
  }
  // 슬쩍
  const thieves = N.filter((n) => n.t.H <= -1), mats = Object.keys(META.mats).filter((m) => META.mats[m] > 0);
  if (thieves.length && mats.length && rand() < 0.4) {
    const t = pick(thieves), honest = N.filter((n) => n !== t && n.t.H >= 1)[0], m = pick(mats);
    if (honest) { rel(honest, t, -20); glowMod(-5, '도둑질 소동'); add('🧐', `${adj(t, 'H')} ${jo(t.name, '이가')} ${jo(m, '을를')} 슬쩍하려다 ${adj(honest, 'H')} ${honest.name}에게 붙잡혀 돌려놓았다.`); }
    else { META.mats[m]--; glowMod(-5, '도둑질'); add('🫳', `${m} 하나가 없어졌다. ${adj(t, 'H')} ${jo(t.name, '이가')} 딴청을 부린다…`); }
  }
  // 걱정
  if (r.hurt || r.reason === 'death') { const w = N.filter((n) => n.t.E >= 1)[0]; if (w) { META.items.heal = (META.items.heal || 0) + 1; add('💗', `${adj(w, 'E')} ${jo(w.name, '이가')} 걱정하며 회복 물약을 하나 챙겨 두었다.`); } }
  // 발견
  const cur = N.filter((n) => n.t.O >= 1);
  if (cur.length && rand() < 0.5) {
    const c = pick(cur), hid = RECIPES.filter((q) => q.hidden && !META.recipes[q.id] && META.buildings[q.b]);
    if (hid.length) { const q = pick(hid); META.recipes[q.id] = true; add('💡', `${adj(c, 'O')} ${jo(c.name, '이가')} 전리품을 뜯어보다 새 제작법을 찾았다: ${recipeName(q)}`); }
    else { const m = pick(['약초', '광석', '가죽']); META.mats[m] = (META.mats[m] || 0) + 1; add('🔍', `${adj(c, 'O')} ${jo(c.name, '이가')} 마을 뒤편에서 ${jo(m, '을를')} 찾아왔다.`); }
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

export function recipeName(q) { return q.out ? `${ITEMS[q.out].name}${q.n > 1 ? ' ×' + q.n : ''}` : q.weapon ? `${WPN(q.weapon).name} (${FORMS[WPN(q.weapon).form].name} ${WPN(q.weapon).dmg.join('–')})` : q.armor ? `${ARMORS[q.armor].name} (${ARMORS[q.armor].desc})` : q.gear ? `${GEAR_BASES[q.gear].name} (${q.gear === 'shield' ? '방어 +1, 막기 15%' : '시야 +1, 붙은 적을 칠 때 불 1'})` : '든든한 한 끼 (다음 출발 보호막 +6)'; }

export function processReturn(r) {
  META.visits++; META.closed = {}; META.glowMods = [];
  for (const n of META.npcs) n.mood = Math.trunc(n.mood / 2);
  const out = { reason: r.reason, arrived: [], built: [], events: [], visitors: [], left: [], shard: 0 };
  for (const n of META.newNpcs) {
    META.npcs.push(n); initRel(n); out.arrived.push(n);
    const b = JOBS[n.job].b; if (!META.buildings[b]) { META.buildings[b] = { shown: false }; out.built.push(b); }
  }
  META.newNpcs = [];
  const real = r.reason && r.reason !== 'first' && r.reason !== 'resume';
  if (real) out.events = genEvents(out, r);
  // 등불 조각: 보스를 처음 쓰러뜨린 구역의 기억을 모닥불에 넣는다
  if (r.reason === 'boss' && !META.lit[r.zone - 1]) { META.lit[r.zone - 1] = true; out.shard = r.zone; }
  if (r.reason === 'boss' && r.first) { META.items.recall = (META.items.recall || 0) + 1; out.recallReward = true; }
  if (r.reason === 'boss' && META.hero && META.hero.perkHp) { const h = META.hero; h.base -= h.perkHp; h.max -= h.perkHp; h.hp = Math.min(h.hp, h.max); h.perkHp = 0; }
  if (out.shard === 4 && META.ending !== 'dawn') { META.ending = 'dawn'; out.ending = true; }
  if (real) { out.left = ageVisitors(); out.visitors = rollVisitors(); }
  if (r.reason === 'death') { if (!META.npcs.length) out.dark = true; else META.needSuccessor = true; }
  return out;
}

export function resetMeta() { META = null; }
