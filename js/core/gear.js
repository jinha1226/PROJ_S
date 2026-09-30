import { BASE } from '../data/classes.js';
import { DROP_RATE } from '../data/colony.js';
import { kindOf } from '../data/enemies.js';
import { AMULETS, ART_A, ART_B, BAG_MAX, BASE_EVA, BRANDS, CAPS, EGOS, ELEM, GEAR_BASES, GEAR_DROP, JEWEL_LOOK, QUALITY, RANDART_COSTS, RANDART_PROPS, RINGS, SLOTS, SLOT_NAME, UNRANDS, clampRes, dropTable, fitsSlot, hasQuality, isJewel, isWeapon, newBase, plusMax, twoHanded, weaponOf } from '../data/gear.js';
import { T_FLOOR, T_STAIRS, ZONE_FLOORS } from '../data/terrain.js';
import { DARK, torchTier } from '../data/torch.js';
import { WEAPONS, WEAPON_IDS, WPN } from '../data/weapons.js';
import { pick, rand, ri, shuffle, wpick } from '../util/rng.js';
import { jo } from '../util/text.js';
import { addLoot } from './combat.js';
import { addItem } from './items.js';
import { META, saveMeta } from './meta.js';
import { G, Game, I, emit, inb, log, standable } from './state.js';

/* ================= 장비 (DCSS식 — docs/설계_아이템_장비.md) =================
   장비 = { uid, base, plus, q(품질 1~4), brand, ego, jt(장신구 종류), jv(반지 수치), je(저항 원소), art(랜다트), un(픽다트),
           idP(강화치 앎), idX(속성 앎), worn(입은 턴), hits(무기 적중) }
   데드셀안(docs/설계_아이템_장비_데드셀안.md): 무기 12종의 색 · 보조손(오브) · 품질. 무기 세트·교체는 없다 */
const uid = () => 'g' + Math.floor(rand() * 2e9).toString(36);
const ELEMS = ['fire', 'frost', 'bolt', 'poison'];
const sign = (v) => (v >= 0 ? `+${v}` : `${v}`);

/** 장신구 모양·정체를 아는지: 던전에서는 G, 정착지에서는 등불지기 */
function jewelBook() {
  const h = META && META.hero;
  const src = Game.mode === 'town' && h ? h : G;
  if (!src.jlook) src.jlook = newJewelLook();
  if (!src.jknown) src.jknown = {};
  return src;
}
export function newJewelLook() {
  const out = {};
  for (const [kind, T] of [['ring', RINGS], ['neck', AMULETS]]) { const looks = shuffle(JEWEL_LOOK[kind].slice()); Object.keys(T).forEach((k, j) => { out[kind + ':' + k] = looks[j % looks.length]; }); }
  return out;
}
const jkey = (it) => `${GEAR_BASES[it.base].slot === 'neck' ? 'neck' : 'ring'}:${it.jt}`;
export const jewelKnown = (it) => !!(it.un || jewelBook().jknown[jkey(it)]);
function knowJewel(it) { if (isJewel(it) && it.jt) jewelBook().jknown[jkey(it)] = true; }
/** 다 아는 장비인가 */
export function fullyKnown(it) {
  if (!it) return true;
  if (it.un) return true;
  if (isJewel(it)) return it.art ? it.art.props.every((p) => p.known) : jewelKnown(it);
  if (it.art) return it.idP && it.art.props.every((p) => p.known);
  return it.idP && it.idX;
}

/* ================= 이름 ================= */
export function gearName(it, reveal = false) {
  const B = GEAR_BASES[it.base];
  if (it.un) return UNRANDS[it.un].name;
  if (it.art) return it.art.name;
  if (B.jewel) {
    const T = (B.slot === 'neck' ? AMULETS : RINGS)[it.jt];
    if (!(reveal || jewelKnown(it)) || !T) return `${jewelBook().jlook[jkey(it)] || '낡은'} ${B.name}`;
    return `${T.name}의 ${B.name}${RINGS[it.jt] && B.slot === 'ring' && RINGS[it.jt].ench ? ' ' + sign(it.jv) : ''}${it.je ? ` (${ELEM[it.je].name})` : ''}`;
  }
  const kp = reveal || it.idP, kx = reveal || it.idX, prop = it.brand ? BRANDS[it.brand].name : it.ego ? EGOS[it.ego].name : '', Q = QUALITY[it.q];
  return `${kp ? sign(it.plus) + ' ' : ''}${Q ? Q.name + ' ' : ''}${prop ? (kx ? prop + ' ' : '빛나는 ') : ''}${B.name}${kp ? '' : ' ?'}`;
}
/** 목록에 쓰는 색: 평범은 흰색, 속성은 그 원소 색, 랜다트는 보랏빛, 픽다트는 금빛, 모르는 속성은 연하게 */
export function gearCss(it) {
  if (!it) return 'rgba(255,255,255,.2)';
  if (it.un) return '#ffcf4a';
  if (it.art) return '#d0a0ff';
  const B = GEAR_BASES[it.base];
  if (B.jewel) return jewelKnown(it) ? '#9fd8ff' : '#c8ccd8';
  const p = it.brand ? BRANDS[it.brand] : it.ego ? EGOS[it.ego] : null;
  if (!p) return it.idP && it.plus < 0 ? '#ff9a9a' : '#e8e8ee';
  if (!it.idX) return '#bcd4ff';
  return p.css || (p.elem ? ELEM[p.elem].css : p.res ? ELEM[p.res].css : '#e8e8ee');
}
export const gearHex = (it) => parseInt(gearCss(it).slice(1, 7), 16) || 0xe8e8ee;
export const gearTier = (it) => (!it ? 'plain' : it.un ? 'unrand' : it.art ? 'randart' : it.brand || it.ego ? 'prop' : 'plain');

/* ================= 만들기 ================= */
/** 품질 = 구역(층 1~3 → 1, 4~6 → 2 …, 최대 4) */
export const qualityOf = (depth) => Math.max(1, Math.min(4, Math.ceil(depth / ZONE_FLOORS))); // 품질 = 구역
/** 기본템. o: { plus, q, brand, ego, known, jt } — 정착지 제작품·시작 장비는 known */
export function makeGear(base, o = {}) {
  const it = { uid: uid(), base, plus: o.plus || 0, q: hasQuality(base) ? o.q || 1 : null, brand: o.brand || null, ego: o.ego || null, jt: null, jv: 0, je: null, art: null, un: null, idP: !!o.known, idX: !!o.known, worn: 0, hits: 0 };
  if (GEAR_BASES[base].jewel) rollJewel(it, o.jt);
  return it;
}
function rollJewel(it, jt) {
  const neck = GEAR_BASES[it.base].slot === 'neck', T = neck ? AMULETS : RINGS;
  it.jt = jt || pick(Object.keys(T).filter((k) => !T[k].color && k !== 'chain')); // 영혼석이 꺼져 있는 동안 색 반지·연쇄 목걸이는 나오지 않는다
  const R = !neck && RINGS[it.jt];
  if (R && R.ench) { it.jv = ri(...R.ench); if (it.jv === 0) it.jv = R.ench[1] > 4 ? 5 : 2; }
  if (it.jt === 'res') it.je = pick(ELEMS);
  it.idP = it.idX = true; // 장신구는 '정체(종류)'만 모른다
}
function rollBrand(base) {
  const form = GEAR_BASES[base].weapon && WPN(GEAR_BASES[base].weapon).form;
  return pick(Object.keys(BRANDS).filter((k) => !BRANDS[k].form || BRANDS[k].form === form));
}
/** 오브에는 원소 저항 에고만 붙는다 (§4.1) */
function rollEgo(base) { const B = GEAR_BASES[base], ok = Object.keys(EGOS).filter((k) => EGOS[k].slots.includes(B.slot) && (!B.orb || EGOS[k].res)); return ok.length ? pick(ok) : null; }
/** 무작위 기본템 종류(장신구는 전체의 20%). 무기는 12종 균등 — 1구역에서는 원거리·양손이 절반 가중치 (§6) */
function rollBase(depth) {
  if (rand() < 0.2) return rand() < 0.65 ? 'ring' : 'neck';
  if (rand() < 0.3) return wpick(WEAPON_IDS.map((k) => [k, depth <= ZONE_FLOORS && (WEAPONS[k].range || WEAPONS[k].hands === 2) ? 1 : 2]));
  const slot = wpick([['body', 35], ['head', 15], ['cloak', 10], ['hands', 12], ['feet', 12], ['off', 16]]);
  if (slot === 'body') return 'body_' + wpick(depth <= ZONE_FLOORS ? [['cloth', 35], ['leather', 40], ['chain', 20], ['plate', 5]] : depth <= ZONE_FLOORS * 2.5 ? [['cloth', 20], ['leather', 35], ['chain', 30], ['plate', 15]] : [['cloth', 15], ['leather', 25], ['chain', 30], ['plate', 30]]);
  if (slot === 'head') return pick(['head_cloth', 'head_leather', 'head_chain']);
  if (slot === 'off') return rand() < 0.4 ? pick(['orb_red', 'orb_purple', 'orb_green']) : rand() < 0.55 ? 'buckler' : 'shield'; // 오브 40%
  return { cloak: 'cloak', hands: 'gloves', feet: 'boots' }[slot];
}
export function makeRandart(base) {
  const it = makeGear(base), B = GEAR_BASES[base], n = ri(2, 4), props = [];
  it.plus = B.jewel ? 0 : Math.min(plusMax(it), ri(-1, 3));
  for (const id of shuffle(RANDART_PROPS.slice())) {
    if (props.length >= n) break;
    if (id === 'brand' && !B.weapon) continue;
    if (id === 'ego' && (B.weapon || B.jewel || !rollEgo(base))) continue;
    const p = { id, known: false };
    if (id === 'dmg') p.v = ri(1, 2); else if (id === 'def') p.v = ri(1, 2); else if (id === 'eva') p.v = ri(3, 6); else if (id === 'maxHp') p.v = ri(3, 6);
    else if (id === 'res') p.e = pick(ELEMS); else if (id === 'vision') p.v = 1; else if (id === 'cd') p.c = pick(['red', 'purple', 'green']);
    else if (id === 'brand') p.b = rollBrand(base); else if (id === 'ego') p.g = rollEgo(base);
    props.push(p);
  }
  let cost = null;
  if (rand() < 0.4) { const c = pick(RANDART_COSTS); cost = { id: c }; if (c === 'cdUp') cost.c = pick(['red', 'purple', 'green']); }
  it.art = { name: `${pick(ART_A)} ${pick(ART_B)}`, props, cost };
  if (B.jewel) { it.jt = null; it.jv = 0; it.je = null; }
  it.idP = !!B.jewel; it.idX = false;
  return it;
}
export function makeUnrand(id) {
  const U = UNRANDS[id], it = makeGear(U.base, { plus: U.plus || 0, known: true }); it.un = id; it.jt = null; it.jv = 0; it.je = null;
  return it;
}
/** 층(depth 1~12)에 맞는 무작위 장비. force 'art': 유물 이상(보스·희귀 상자) */
export function rollGear(depth, force) {
  const d = depth === 'boss' ? G.floor : depth;
  let cat = force === 'art' ? (rand() < 0.2 ? 4 : 3) : force === 'special' ? (rand() < 0.75 ? 2 : 3) : wpick(dropTable(d).map((w, k) => [k, w]));
  if (cat === 4) {
    const seen = new Set(META ? META.unrandsSeen || [] : []), left = Object.keys(UNRANDS).filter((k) => !seen.has(k));
    if (left.length) { const u = pick(left); if (META) { META.unrandsSeen = [...seen, u]; saveMeta(); } const un = makeUnrand(u); if (un.q) un.q = qualityOf(d); return un; } // 유품도 구역 품질
    cat = 3;
  }
  const base = rollBase(d);
  if (cat === 3) { const a = makeRandart(base); if (a.q) a.q = qualityOf(d); return a; }
  const it = makeGear(base, { q: qualityOf(d) });
  if (GEAR_BASES[base].jewel) return it;
  if (cat === 1) it.plus = rand() < 0.8 ? Math.min(plusMax(it), ri(1, 3)) : -ri(1, 3);
  if (cat === 2) { if (GEAR_BASES[base].weapon) it.brand = rollBrand(base); else it.ego = rollEgo(base); if (!it.brand && !it.ego) it.plus = ri(1, 2); else if (rand() < 0.4) it.plus = ri(1, 2); }
  return it;
}

/** 정착지 제작품(품질 2 '평범한') · 옛 저장본: 'axe+' → +1 손도끼 */
export function craftWeapon(id) { const plus = id.endsWith('+'); return makeGear(newBase(plus ? id.slice(0, -1) : id), { plus: plus ? 1 : 0, q: 2, known: true }); }
/** 'leather'(+) → 가죽 갑옷, 'bone'(+) → 보호 사슬 갑옷(층마다 보호막) */
export function craftArmor(id) {
  const plus = id.endsWith('+'), k = plus ? id.slice(0, -1) : id;
  return k === 'bone' ? makeGear('body_chain', { ego: 'protect', plus: plus ? 1 : 0, q: 2, known: true }) : makeGear('body_leather', { plus: plus ? 1 : 0, q: 2, known: true });
}
/** 옛 등급 장비(디아블로식) → 새 형식: 마법 +1, 희귀 +2, 전설 → 같은 이름의 픽다트. 횃불은 사라진다 */
export function convertOld(old) {
  if (!old || !old.affixes) return old;
  const map = { head_plate: 'head_chain', hands_cloth: 'gloves', hands_leather: 'gloves', hands_chain: 'gloves', hands_plate: 'gloves', feet_cloth: 'boots', feet_leather: 'boots', feet_chain: 'boots', feet_plate: 'boots' };
  if (old.base === 'torch') return null;
  if (old.legend && UNRANDS[old.legend]) return makeUnrand(old.legend);
  const base = newBase(map[old.base] || old.base); if (!GEAR_BASES[base]) return null;
  const it = makeGear(base, { plus: GEAR_BASES[base].jewel ? 0 : { magic: 1, rare: 2, legend: 3 }[old.rarity] || 0, known: true });
  return it;
}

/* ================= 최종 수치 ================= */
/** 아는 것만 남긴 장비(비교·미리보기용) */
export function knownView(it) {
  if (!it || fullyKnown(it)) return it;
  const v = { ...it };
  if (!it.idP) v.plus = 0;
  if (!it.idX) { v.brand = null; v.ego = null; }
  if (it.art) v.art = { ...it.art, props: it.art.props.filter((p) => p.known), cost: null };
  if (isJewel(it) && !it.art && !jewelKnown(it)) v.jt = '?';
  return v;
}
export function calcStats(eq, levels = heldLevels()) {
  const s = { maxHp: 0, def: 0, eva: BASE_EVA, block: 0, dmg: 0, crit: 0, critMul: 2, acc: 0, vision: 0, orb: { red: 0, purple: 0, green: 0 },
    res: { fire: 0, frost: 0, bolt: 0, poison: 0 }, brand: null, egos: new Set(), legend: new Set(), colorCd: { red: 0, purple: 0, green: 0 },
    torchSlow: 0, torchCost: 0, lampBonus: 0, floorShield: 0, thorns: 0, patience: 0, vengeance: 0, insight: false, noSlide: false, wetImm: false, wallDmg: 0, throwRange: 0,
    seeing: false, regen: false, chainStart: false, reflect: 0, silence: false, bleed: 0, fracPush: false, fracBonus: 0, vamp: false, reso: false,
    // 예전 옵션 자리(쓰는 곳이 남아 있어 0으로 둔다)
    skillCd: {}, skillDmg: 0, redTwice: 0, purpleHeal: 0, greenShield: 0, wetDmg: 0, weakDmg: 0, dot: 0, waterEva: 0, burnImm: false, potion: 0, autoId: false, throwArea: false, torchFire: 0, elem: { fire: 0, frost: 0, bolt: 0, poison: 0 },
    spell: 0, speed: 0, cdr: 0, healUp: 0, src: { eva: [['기본', BASE_EVA]] }, capped: {} };
  const add = (k, v, lab) => { (s.src[k] ||= []).push([lab, v]); };
  const brand = (b) => { s.brand = b; if (b === 'blood') s.bleed += 2; if (b === 'shatter') { s.fracPush = true; s.fracBonus = 2; } if (b === 'pierce') s.critMul = 3; if (b === 'vamp') s.vamp = true; if (b === 'reso') s.reso = true; };
  const ego = (g, lab) => {
    s.egos.add(g); const E = EGOS[g];
    if (E.res) { s.res[E.res]++; add('res' + E.res, 1, lab); }
    if (g === 'thorns') s.thorns = 2; if (g === 'protect') s.floorShield += 4; if (g === 'patience') s.patience = 2; if (g === 'vengeance') s.vengeance = 2;
    if (g === 'insight') { s.insight = true; s.vision++; add('vision', 1, lab); } if (g === 'waterwalk') { s.noSlide = true; s.wetImm = true; } if (g === 'ember') s.torchSlow += 25; if (g === 'smash') s.wallDmg += 2; if (g === 'throw') s.throwRange += 1;
  };
  for (const slot of SLOTS) {
    const it = eq && eq[slot]; if (!it) continue;
    const B = GEAR_BASES[it.base]; if (!B) continue;
    const lab = `${SLOT_NAME[slot]}: ${gearName(it)}`;
    for (const k of ['def', 'eva', 'block']) if (B[k]) { s[k] += B[k]; add(k, B[k], lab); }
    const Q = QUALITY[it.q];
    if (B.weapon && slot === 'weapon') {
      if (Q && Q.dmg) { s.dmg += Q.dmg; add('dmg', Q.dmg, `${lab} (품질)`); }
      if (it.plus) { s.dmg += it.plus; add('dmg', it.plus, lab); s.acc += it.plus * 2; add('acc', it.plus * 2, lab); }
      const W = WPN(B.weapon); if (W.spell) { const v = W.spell + Math.floor(Math.max(0, it.plus || 0) / 3); s.spell += v; add('spell', v, lab); } // 지팡이
    } else if (B.orb) { const v = 1 + (it.plus || 0); s.spell += v; add('spell', v, lab); } // 오브: 주문력
    else if (!B.jewel && !B.weapon) { if (Q && Q.def) { s.def += Q.def; add('def', Q.def, `${lab} (품질)`); } if (it.plus) { s.def += it.plus; add('def', it.plus, lab); } }
    if (it.brand) brand(it.brand);
    if (it.ego) ego(it.ego, lab);
    if (B.jewel && it.jt && it.jt !== '?') {
      if (B.slot === 'neck') { const k = it.jt; if (k === 'memory') { s.torchSlow += 30; s.lampBonus += 20; } if (k === 'regen') s.regen = true; if (k === 'chain') s.chainStart = true; if (k === 'reflect') s.reflect += 20; if (k === 'silence') s.silence = true; if (k === 'sage') { s.spell += 2; add('spell', 2, lab); s.cdr += 8; add('cdr', 8, lab); } if (k === 'wind') { s.speed += 8; add('speed', 8, lab); } if (k === 'clarity') { s.cdr += 15; add('cdr', 15, lab); } if (k === 'vigor') { s.maxHp += 8; add('maxHp', 8, lab); }; }
      else if (RINGS[it.jt]) {
        const k = it.jt, v = it.jv;
        if (k === 'prot') { s.def += v; add('def', v, lab); } if (k === 'eva') { s.eva += v; add('eva', v, lab); } if (k === 'str') { s.dmg += v; add('dmg', v, lab); }
        if (k === 'vit') { s.maxHp += 5; add('maxHp', 5, lab); } if (k === 'res' && it.je) { s.res[it.je]++; add('res' + it.je, 1, lab); } if (k === 'see') s.seeing = true;
        if (k === 'arcana') { s.spell += v; add('spell', v, lab); } if (k === 'swift') { s.speed += v; add('speed', v, lab); } if (k === 'focus') { s.cdr += v; add('cdr', v, lab); } if (k === 'mend') { s.healUp += v; add('healUp', v, lab); }
        if (RINGS[k].color) s.colorCd[RINGS[k].color]--;
      }
    }
    if (it.art) {
      for (const p of it.art.props) {
        if (p.id === 'dmg') { s.dmg += p.v; add('dmg', p.v, lab); } else if (p.id === 'def') { s.def += p.v; add('def', p.v, lab); } else if (p.id === 'eva') { s.eva += p.v; add('eva', p.v, lab); }
        else if (p.id === 'maxHp') { s.maxHp += p.v; add('maxHp', p.v, lab); } else if (p.id === 'res') { s.res[p.e]++; add('res' + p.e, 1, lab); } else if (p.id === 'vision') { s.vision += p.v; add('vision', p.v, lab); }
        else if (p.id === 'cd') s.colorCd[p.c]--; else if (p.id === 'brand' && !s.brand) brand(p.b); else if (p.id === 'ego') ego(p.g, lab);
      }
      const c = it.art.cost;
      if (c) { if (c.id === 'maxHp') { s.maxHp -= 3; add('maxHp', -3, lab + ' (대가)'); } else if (c.id === 'torch') s.torchCost += 25; else if (c.id === 'vision') { s.vision -= 1; add('vision', -1, lab + ' (대가)'); } else if (c.id === 'eva') { s.eva -= 5; add('eva', -5, lab + ' (대가)'); } else if (c.id === 'cdUp') s.colorCd[c.c]++; }
    }
    if (it.un) s.legend.add(it.un);
  }
  classStats(s, levels, add);
  const cap = (k, max) => { if (s[k] > max) { s[k] = max; s.capped[k] = true; } if (s[k] < 0) s[k] = 0; };
  cap('def', CAPS.def); cap('eva', CAPS.eva); cap('block', CAPS.block); cap('cdr', 40); cap('spell', 10); // 스킬 쿨타임은 40%까지, 주문력은 10까지
  for (const k in s.res) s.res[k] = clampRes(s.res[k]);
  return s;
}
/** Class 레벨만큼 전투 수치(docs/설계_직업.md): 레벨마다 더해 합한 뒤 내림. 출처 목록에 Class 줄이 따로 선다 */
function classStats(s, levels, add) {
  for (const [c, lv] of Object.entries(levels || {})) {
    const B = BASE[c]; if (!B || !(lv > 0)) continue; const lab = `${B.name} ${lv}`;
    for (const [k, per] of Object.entries(B.stat)) { const v = Math.trunc(Math.round(per * lv * 1e6) / 1e6); if (!v) continue; s[k] += v; add(k, v, lab); }
    const r = (B.resAt || []).filter((L) => lv >= L).length; if (r) for (const e of Object.keys(s.res)) { s.res[e] += r; add('res' + e, r, lab); }
  }
}
/** 지금 장비를 입은 사람의 Class 레벨(던전 = 등불지기 유닛, 정착지 = 등불지기 기록) */
function heldLevels() {
  if (Game.mode === 'town' && META && META.hero) return (META.hero.prog && META.hero.prog.build.levels) || {};
  return (G.player && G.player.build && G.player.build.levels) || {};
}
/** 비교용 점수(대략) — 아는 것만 */
export function gearScore(it) {
  if (!it) return 0; const v0 = knownView(it), B = GEAR_BASES[it.base];
  let v = (B.def || 0) * 3 + (B.eva || 0) * 0.3 + (B.block || 0) * 0.15;
  const Q = QUALITY[it.q];
  if (B.weapon) { const w = weaponOf(it); v += (w.dmg[0] + w.dmg[1]) * 0.8 * (w.hands === 2 ? 1.2 : 1) + v0.plus * 2 + (Q ? Q.dmg * 1.6 : 0); } else if (B.orb) v += 4 + v0.plus * 3; else if (!B.jewel) v += v0.plus * 3 + (Q ? Q.def * 3 : 0);
  if (v0.brand || v0.ego) v += 3; if (v0.art) v += v0.art.props.length * 2; if (it.un) v += 8;
  return v;
}

/* ================= 장착 · 해제 (던전: G, 정착지: 등불지기) ================= */
export function holder() {
  if (Game.mode === 'town' && META && META.hero) { const h = META.hero; return { eq: h.eq, bag: h.bag, base: h.base, unit: h, town: true }; }
  return { eq: G.eq, bag: G.bag, base: G.heroBase, unit: G.player, town: false };
}
export function refreshStats() {
  const H = holder(); if (!H.eq) return;
  const s = calcStats(H.eq), u = H.unit, mx = H.base + s.maxHp;
  if (!H.town) { G.ps = s; if (s.insight && G.weakKnown) for (const c of ['beast', 'armor', 'bone']) G.weakKnown[c] = true; }
  if (u && u.max !== mx) { u.hp = Math.max(1, Math.min(mx, u.hp + Math.max(0, mx - u.max))); u.max = mx; if (!H.town) emit('hp', { id: 0, hp: u.hp, max: u.max }); }
  return s;
}
const eqSnap = (H) => Object.fromEntries(SLOTS.map((k) => [k, H.eq[k] ? { ...H.eq[k] } : null]));
/** 다 드러낸다(확인 두루마리) */
export function revealAll(it) {
  if (!it || fullyKnown(it)) return false;
  it.idP = it.idX = true; if (it.art) for (const p of it.art.props) p.known = true; knowJewel(it);
  return true;
}
/** 짝 칸: 양손 무기를 들면 보조손을 비운다 */
const PAIR = { weapon: 'off', off: 'weapon' };
export function equip(bagIdx, slot) {
  const H = holder(), it = H.bag[bagIdx]; if (!it || !fitsSlot(it, slot)) return false;
  const mate = PAIR[slot], two = slot === 'weapon' && twoHanded(it);
  if (slot === 'off' && twoHanded(H.eq[mate])) { log('양손 무기를 들면 보조손을 쓸 수 없다.', 'bad'); return false; }
  const old = H.eq[slot], off = two ? H.eq[mate] : null;
  if (H.bag.length - 1 + (old ? 1 : 0) + (off ? 1 : 0) > BAG_MAX) { log('가방이 가득 찼다.', 'bad'); return false; }
  H.bag.splice(bagIdx, 1); if (old) H.bag.push(old);
  if (off) { H.eq[mate] = null; H.bag.push(off); log(`${jo(gearName(off), '은는')} 가방에 넣었다.`, 'info'); }
  H.eq[slot] = it;
  let note = '';
  if (isJewel(it) && !it.art && !jewelKnown(it) && GEAR_BASES[it.base].slot === 'ring' && RINGS[it.jt] && RINGS[it.jt].obvious) { knowJewel(it); note = ' 정체가 드러났다.'; }
  refreshStats();
  emit('equip', { slot, eq: eqSnap(H) });
  log(`${jo(gearName(it), '을를')} 장착했다.${note}`, it.un || it.art ? 'syn' : 'good');
  return true;
}
export function unequip(slot) {
  const H = holder(), it = H.eq[slot]; if (!it) return false;
  if (H.bag.length >= BAG_MAX) { log('가방이 가득 찼다.', 'bad'); return false; }
  H.eq[slot] = null; H.bag.push(it); refreshStats();
  emit('equip', { slot, eq: eqSnap(H) }); log(`${jo(gearName(it), '을를')} 해제했다.`, 'info');
  return true;
}
export function dropGear(bagIdx) {
  const H = holder(), it = H.bag[bagIdx]; if (!it) return false;
  if (H.town) { H.bag.splice(bagIdx, 1); META.gear.push(it); return true; }
  const spot = gearSpot(G.player.x, G.player.y); if (!spot) { log('놓을 자리가 없다.', 'bad'); return false; }
  H.bag.splice(bagIdx, 1); G.gear.set(I(spot[0], spot[1]), it);
  emit('gears', [...G.gear.entries()]); log(`${jo(gearName(it), '을를')} 내려놓았다.`, 'info');
  return true;
}
export function pickGear() {
  const p = G.player, i = I(p.x, p.y), it = G.gear.get(i); if (!it) return false;
  if (G.bag.length >= BAG_MAX) { log('가방이 가득 찼다.', 'bad'); return false; }
  G.gear.delete(i); G.bag.push(it);
  emit('gears', [...G.gear.entries()]); emit('pickup', { x: p.x, y: p.y });
  log(`${jo(gearName(it), '을를')} 주웠다.`, it.un || it.art ? 'syn' : 'good');
  if (it.un) meetRelic(it);
  return true;
}
/** 픽다트: 주인의 이름을 기억한다(기억할 이름들 · 모닥불 밝기 +1). 남겨진 유품이면 목록에서 지운다 */
function meetRelic(it) {
  const U = UNRANDS[it.un], who = it.owner || U.owner;
  emit('relic', { name: U.name, story: U.story, owner: who });
  if (META && who) { META.rememberedKeepers ||= []; if (!META.rememberedKeepers.includes(who)) { META.rememberedKeepers.push(who); log(`${U.name}. ${who}의 유품이다. 기억할 이름이 늘었다.`, 'syn'); } }
  if (META && META.relics) META.relics = META.relics.filter((r) => r.it.uid !== it.uid);
  saveMeta();
}
/** 입고 지낸 시간·적중으로 정체가 드러난다: 무기 10번 적중, 방어구 30턴, 랜다트는 30턴마다 하나 */
export function tickWorn() {
  if (!G.eq) return;
  let changed = false;
  for (const slot of SLOTS) {
    const it = G.eq[slot]; if (!it || fullyKnown(it) || (isJewel(it) && !it.art)) continue;
    it.worn = (it.worn || 0) + 1;
    if (it.art) { if (it.worn % 30 === 0) { const p = it.art.props.find((q) => !q.known); if (p) { p.known = true; it.idP = true; changed = true; log(`${gearName(it)}의 속성 하나를 알아냈다.`, 'syn'); } } continue; }
    if (!isWeapon(it) && it.worn >= 30) { it.idP = it.idX = true; changed = true; log(`입고 지내며 ${gearName(it)}의 정체를 알았다.`, 'syn'); }
  }
  if (changed) { refreshStats(); emit('equip', { slot: 'body', eq: eqSnap(holder()) }); }
}
export function weaponUsed() {
  const it = G.eq && G.eq.weapon; if (!it || fullyKnown(it) || it.art) return;
  it.hits = (it.hits || 0) + 1;
  if (it.hits >= 10) { it.idP = it.idX = true; refreshStats(); log(`${jo(gearName(it), '이가')} 손에 익었다.`, 'syn'); emit('equip', { slot: 'weapon', eq: eqSnap(holder()) }); }
}
/** 두루마리로 하나를 확인 */
export function identifyItem(it) { const r = revealAll(it); if (r) { refreshStats(); log(`${gearName(it)}의 정체를 알아냈다.`, 'syn'); } return r; }
/** 강화 두루마리: kind 'w'(무기) | 'a'(방어구). 랜다트·픽다트·장신구는 안 된다 */
export const canEnchant = (it, kind) => !!it && !it.art && !it.un && !isJewel(it) && (kind === 'w' ? isWeapon(it) : !isWeapon(it)) && it.plus < plusMax(it);
export function enchantItem(it, kind) {
  if (!canEnchant(it, kind)) return false;
  it.plus++; it.idP = true; refreshStats();
  emit('enchant', { uid: it.uid }); log(`${jo(gearName(it), '을를')} 강화했다.`, 'syn');
  return true;
}
/** 모두 드러낸다(한 층 내려갈 때 쓰지 않는다 — 옛 경로 호환) */
export function identifyGear() {
  let n = 0; for (const it of [...SLOTS.map((k) => G.eq[k]), ...G.bag]) if (revealAll(it)) n++;
  refreshStats(); return n;
}

/* ================= 드롭 ================= */
export function gearSpot(x, y) {
  const ok = (a, b) => inb(a, b) && standable(a, b) && G.tile[I(a, b)] !== T_STAIRS && !G.gear.has(I(a, b)) && !G.chests.has(I(a, b));
  if (ok(x, y)) return [x, y];
  for (let r = 1; r <= 2; r++) for (let dy = -r; dy <= r; dy++) for (let dx = -r; dx <= r; dx++) if (ok(x + dx, y + dy)) return [x + dx, y + dy];
  return null;
}
export function placeGear(it, x, y, from) {
  const s = gearSpot(x, y); if (!s) return;
  G.gear.set(I(s[0], s[1]), it);
  emit('gearDrop', { x: s[0], y: s[1], from: from || [x, y], it: { ...it } });
  if (it.un) log('금빛이 번진다. 옛 등불지기의 유품이다!', 'legend'); else if (it.art) log('무지갯빛이 번진다.', 'syn');
}
/** 몬스터 5%(갑옷 고블린·돌진형 15%), 보스 1개 확정(유물 이상 30%) */
export function dropGearFrom(e) {
  if (e.boss) { placeGear(rollGear(G.floor, rand() < 0.3 ? 'art' : 'special'), e.x, e.y); return; } // 보스는 속성 장비 확정
  const chance = (GEAR_DROP[kindOf(e)] ?? GEAR_DROP.default) * DARK[torchTier(G.torch ?? 100)].drop; // 어두울수록 더 남긴다
  if (rand() * 100 < chance) placeGear(rollDrop(G.floor), e.x, e.y);
}
/** 바닥의 장비 1~2개 + 죽은 등불지기가 남긴 유품 */
/** 던전에서 떨어지는 장비: 드물고, 떨어지면 절반 넘게 속성 장비 */
export const rollDrop = (d) => rollGear(d, rand() < DROP_RATE.special ? 'special' : null);
export function placeFloorGear(rooms, tile, start) {
  const n = rand() < DROP_RATE.floor ? 1 : 0;
  for (let k = 0, placed = 0; k < 200 && placed < n; k++) {
    const r = rooms[ri(0, rooms.length - 1)], x = ri(r.x, r.x + r.w - 1), y = ri(r.y, r.y + r.h - 1), i = I(x, y);
    if (tile[i] !== T_FLOOR || G.items.has(i) || G.mats.has(i) || G.gear.has(i) || Math.max(Math.abs(x - start.x), Math.abs(y - start.y)) < 3) continue;
    G.gear.set(i, rollDrop(G.floor)); placed++;
  }
  for (const rel of (META && META.relics) || []) {
    if (rel.zone !== G.zone || rel.zf !== G.zf) continue;
    for (let k = 0; k < 200; k++) { const r = rooms[ri(1, rooms.length - 1)], x = ri(r.x, r.x + r.w - 1), y = ri(r.y, r.y + r.h - 1), i = I(x, y); if (tile[i] !== T_FLOOR || G.gear.has(i)) continue; G.gear.set(i, rel.it); break; }
  }
}
export function openChest(x, y) {
  const i = I(x, y), c = G.chests.get(i); if (!c || c.open) return false;
  c.open = true; emit('chest', { x, y });
  G.chests.delete(i);
  let it = rollGear(G.floor + (c.rare ? ZONE_FLOORS : 0)); if (c.rare && gearTier(it) === 'plain') it = rollGear(G.floor + ZONE_FLOORS * 2, rand() < 0.3 ? 'art' : null); // 희귀 상자: 한 구역 더 깊은 것
  placeGear(it, x, y); G.chests.set(i, c);
  log('상자를 열었다.', 'good');
  // 귀환 두루마리: 구역마다 최대 1개, 상자에서만 10%
  if (G.zoneFlags && !G.zoneFlags.recall && rand() < 0.1) { G.zoneFlags.recall = true; addItem('recall'); log('상자 바닥에 귀환 두루마리가 있었다.', 'syn'); }
  if (rand() < 0.08) { addLoot('마석', 1); emit('loot', { x, y, m: '마석' }); log('마석 한 조각을 찾았다.', 'good'); }
  return true;
}
/** 층마다 상자 0~1개(+extra), 장비 확정 */
export function placeChests(rooms, tile, extra = 0) {
  G.chests = new Map();
  const n = (rand() < DROP_RATE.chest ? 1 : 0) + extra;
  for (let k = 0, placed = 0; k < 200 && placed < n; k++) {
    const r = rooms[ri(1, rooms.length - 1)], x = ri(r.x, r.x + r.w - 1), y = ri(r.y, r.y + r.h - 1), i = I(x, y);
    if (tile[i] !== T_FLOOR || G.items.has(i) || G.mats.has(i) || G.gear.has(i) || G.chests.has(i)) continue;
    G.chests.set(i, { open: false }); placed++;
  }
}
/** 죽을 때: 입고 있던 픽다트는 그 층에 남는다 */
export function leaveRelics() {
  if (!META || !G.eq) return;
  META.relics ||= [];
  for (const slot of SLOTS) { const it = G.eq[slot]; if (it && it.un) META.relics.push({ zone: G.zone, zf: G.zf, it }); }
}

/* ================= 시작 장비 · 저장 옮기기 ================= */
export const emptyEq = () => Object.fromEntries(SLOTS.map((k) => [k, null]));
/** 새 등불지기: 한손 근접 무기 하나 + 천옷, 모두 아는 +0 */
export function starterKit(start = pick(['sword', 'axe', 'mace', 'spear'])) {
  const eq = emptyEq(); eq.weapon = makeGear(start, { known: true }); eq.body = makeGear('body_cloth', { known: true });
  return { eq, bag: [] };
}
/** 저장 v5 → v6: 디아블로식 장비 → DCSS식. 보조 칸의 무기는 가방으로, 방패는 방패 칸으로, 횃불 장비는 사라진다 */
export function migrateGear(M) {
  const conv = (list) => (list || []).map(convertOld).filter(Boolean);
  M.gear = conv(M.gear);
  M.unrandsSeen = [...new Set([...(M.unrandsSeen || []), ...((M.hero && M.hero.legends) || [])])];
  M.relics ||= [];
  const h = M.hero; if (!h) return;
  const old = h.eq || {}, eq = emptyEq(), bag = conv(h.bag);
  for (const [k, it0] of Object.entries(old)) {
    const it = convertOld(it0); if (!it) continue;
    if (k === 'off') { if (!isWeapon(it) && fitsSlot(it, 'off')) eq.off = it; else bag.push(it); continue; }
    const k2 = SLOTS.includes(k) && fitsSlot(it, k) ? k : SLOTS.find((q) => fitsSlot(it, q) && !eq[q]); // 칸이 바뀐 것(망토 등)은 제 칸으로
    if (k2 && !eq[k2]) eq[k2] = it; else bag.push(it);
  }
  h.eq = eq; h.bag = bag.slice(0, BAG_MAX); delete h.legends;
  h.jlook ||= newJewelLook(); h.jknown ||= {};
  for (const it of [...Object.values(eq), ...bag, ...M.gear]) if (it && isJewel(it) && it.jt && !it.art && !it.un) h.jknown[jkey(it)] = true;
}
/** 저장 → v8: 단검 → 쌍단검, 방패 칸 → 보조손, 품질 없는 장비는 1. v7의 세트 B(weapon2·off2)는 가방으로(차면 창고로) */
export function migrateSets(M) {
  const fix = (it) => { if (!it) return it; it.base = newBase(it.base); if (it.q === undefined) it.q = hasQuality(it.base) ? 1 : null; return it; };
  (M.gear || []).forEach(fix); for (const r of M.relics || []) fix(r.it);
  const h = M.hero; if (!h || !h.eq) return;
  const eq = h.eq; h.bag = (h.bag || []).map(fix);
  if (eq.shield !== undefined) { eq.off = eq.shield || null; delete eq.shield; }
  for (const k of SLOTS) eq[k] = fix(eq[k] || null);
  const out = [eq.weapon2, eq.off2].map(fix).filter(Boolean); delete eq.weapon2; delete eq.off2; delete h.wset;
  if (twoHanded(eq.weapon) && eq.off) { out.push(eq.off); eq.off = null; }
  for (const it of out) (h.bag.length < BAG_MAX ? h.bag : (M.gear ||= [])).push(it);
}
