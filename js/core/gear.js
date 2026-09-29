import { kindOf } from '../data/enemies.js';
import { AFFIXES, BAG_MAX, BASE_EVA, CAPS, GEAR_BASES, GEAR_DROP, LEGENDS, RARE_A, RARE_B, RARITY, RARITY_ORDER, SLOTS, SLOT_NAME, WEAPON_TRAIT, affixLine, fitsSlot, isWeapon, rarityTable, weaponOf } from '../data/gear.js';
import { T_FLOOR, T_STAIRS } from '../data/terrain.js';
import { WPN } from '../data/weapons.js';
import { pick, rand, ri, wpick } from '../util/rng.js';
import { addLoot } from './combat.js';
import { addItem } from './items.js';
import { META } from './meta.js';
import { G, Game, I, emit, inb, log, standable } from './state.js';

/* ================= 장비: 만들기 ================= */
export function gearName(it, reveal = false) {
  const B = GEAR_BASES[it.base];
  if (!it.known && !reveal) return '미확인 ' + B.name;
  if (it.legend) return LEGENDS[it.legend].name;
  if (it.craftName) return it.craftName;
  if (it.rarity === 'rare') return it.rareName;
  if (it.rarity === 'magic' && it.affixes.length) {
    const a = AFFIXES[it.affixes[0].id], b = it.affixes[1] && AFFIXES[it.affixes[1].id];
    return b ? `${b.suf} ${a.pre} ${B.name}` : it.sufFirst ? `${a.suf} ${B.name}` : `${a.pre} ${B.name}`;
  }
  return B.name;
}
function affixPool(base, slot) {
  const B = GEAR_BASES[base], kind = B.slot, form = B.weapon ? WPN(B.weapon).form : null;
  return Object.entries(AFFIXES).filter(([, A]) => A.cat !== 'craft' && A.slots.includes(kind) && (!A.form || A.form === form)).map(([id]) => id);
}
function rollAffix(id, tier) {
  const A = AFFIXES[id], a = { id, v: A.flag ? 1 : ri(...(tier === 2 ? A.t2 : A.t1)), known: true };
  if (A.skill) a.skill = pick(['push', 'fire', 'bolt', 'frost', 'venom']);
  return a;
}
export function makeGear(base, rarity = 'common', tier = 1, legend = null) {
  const it = { uid: 'g' + Math.floor(rand() * 2e9).toString(36), base, rarity, affixes: [], legend, known: rarity === 'common' || rarity === 'magic' };
  const [lo, hi] = RARITY[rarity].n, n = ri(lo, hi), pool = affixPool(base);
  const isW = !!GEAR_BASES[base].weapon;
  let basic = 0;
  for (let k = 0; k < 40 && it.affixes.length < n && pool.length; k++) {
    const id = pick(pool);
    if (it.affixes.some((a) => a.id === id)) continue;
    if (isW && AFFIXES[id].cat === 'basic') { if (basic) continue; basic++; }
    it.affixes.push(rollAffix(id, tier));
  }
  if (!it.known) for (const a of it.affixes) a.known = false;
  if (rarity === 'rare') it.rareName = `${pick(RARE_A)} ${pick(RARE_B)}`;
  if (rarity === 'magic') it.sufFirst = rand() < 0.4;
  return it;
}
/** 층(depth 1~12 또는 'boss')에 맞는 무작위 장비 */
export function rollGear(depth) {
  const d = depth === 'boss' ? G.floor : depth, tier = d >= 7 ? 2 : 1;
  const [c, m, r, l] = rarityTable(depth);
  let rarity = wpick([['common', c], ['magic', m], ['rare', r], ['legend', l]]);
  if (rarity === 'legend') {
    const left = Object.keys(LEGENDS).filter((k) => !G.legendsDropped.has(k));
    if (!left.length) rarity = 'rare';
    else { const lg = pick(left); G.legendsDropped.add(lg); const it = makeGear(LEGENDS[lg].base, 'legend', tier, lg); return it; }
  }
  const kind = wpick([['weapon', 22], ['armor', 46], ['off', 8], ['neck', 10], ['ring', 14]]);
  let base;
  if (kind === 'weapon') base = pick(d >= 2 ? ['sword', 'axe', 'mace', 'hammer', 'dagger', 'spear'] : ['sword', 'mace', 'dagger']);
  else if (kind === 'armor') {
    const mat = wpick(d <= 3 ? [['cloth', 40], ['leather', 40], ['chain', 18], ['plate', 2]] : d <= 8 ? [['cloth', 20], ['leather', 35], ['chain', 30], ['plate', 15]] : [['cloth', 15], ['leather', 25], ['chain', 30], ['plate', 30]]);
    base = `${pick(['body', 'head', 'hands', 'feet'])}_${mat}`;
  } else if (kind === 'off') base = pick(['shield', 'shield', 'torch']);
  else base = kind;
  return makeGear(base, rarity, tier);
}

/** 정착지 제작품 · 옛 저장본: 'axe+' → 피해 +1 마법 손도끼 */
export function craftWeapon(id) {
  const plus = id.endsWith('+'), it = makeGear(plus ? id.slice(0, -1) : id, 'common');
  if (plus) { it.rarity = 'magic'; it.affixes = [{ id: 'dmg', v: 1, known: true }]; }
  return it;
}
/** 'leather'(+) → 최대 HP 가죽 갑옷, 'bone'(+) → 층마다 보호막 사슬 갑옷 */
export function craftArmor(id) {
  const plus = id.endsWith('+'), k = plus ? id.slice(0, -1) : id;
  const it = makeGear(k === 'bone' ? 'body_chain' : 'body_leather', 'common');
  it.rarity = 'magic'; it.affixes = [k === 'bone' ? { id: 'floorShield', v: plus ? 6 : 4, known: true } : { id: 'hp', v: plus ? 9 : 6, known: true }];
  it.craftName = (k === 'bone' ? '뼈 흉갑' : '가죽 갑옷') + (plus ? '+' : '');
  return it;
}

/* ================= 최종 수치 (상한 · 출처) ================= */
export function calcStats(eq) {
  const s = { maxHp: 0, def: 0, eva: BASE_EVA, block: 0, dmg: 0, crit: 0, acc: 0, reach: 1, wetDmg: 0, weakDmg: 0, bleed: 0, fracPush: false, wallDmg: 0, throwArea: false, potion: 0, autoId: false,
    redTwice: 0, purpleHeal: 0, greenShield: 0, skillCd: {}, skillDmg: 0, dot: 0, waterEva: 0, burnImm: false, noSlide: false, vision: 0, torchFire: 0, floorShield: 0,
    res: { fire: 0, bolt: 0, frost: 0, poison: 0 }, elem: { fire: 0, bolt: 0, frost: 0, poison: 0 }, legend: new Set(), src: { eva: [['기본', BASE_EVA]] }, capped: {} };
  const add = (k, v, lab) => { (s.src[k] ||= []).push([lab, v]); };
  for (const slot of SLOTS) {
    const it = eq && eq[slot]; if (!it) continue;
    const B = GEAR_BASES[it.base], lab = `${SLOT_NAME[slot]}: ${gearName(it)}`;
    if (slot === 'off' && B.weapon) continue; // 등에 멘 두 번째 무기는 효과가 없다
    for (const k of ['def', 'eva', 'block', 'vision', 'torchFire']) if (B[k]) { s[k] += B[k]; add(k, B[k], lab); }
    if (slot === 'weapon' && B.weapon && WEAPON_TRAIT[B.weapon]) { const T = WEAPON_TRAIT[B.weapon]; if (T.acc) { s.acc += T.acc; add('acc', T.acc, lab); } if (T.crit) { s.crit += T.crit; add('crit', T.crit, lab); } if (T.reach) s.reach = T.reach; }
    for (const a of it.affixes) {
      const v = a.v, id = a.id;
      if (id === 'hp') { s.maxHp += v; add('maxHp', v, lab); }
      else if (id.endsWith('Dmg') && s.elem[id.slice(0, -3)] != null) { s.elem[id.slice(0, -3)] += v; add(id, v, lab); }
      else if (id.startsWith('res')) { const k = id.slice(3); s.res[k] += v; add('res' + k, v, lab); }
      else if (id === 'skillCd') { s.skillCd[a.skill] = (s.skillCd[a.skill] || 0) + 1; add('skillCd', a.skill, lab); }
      else if (typeof s[id] === 'boolean') { s[id] = true; add(id, 1, lab); }
      else if (typeof s[id] === 'number') { s[id] += v; add(id, v, lab); }
    }
    if (it.legend) s.legend.add(it.legend);
  }
  const cap = (k, max, min = -Infinity) => { if (s[k] > max) { s[k] = max; s.capped[k] = true; } if (s[k] < min) s[k] = min; };
  cap('def', CAPS.def, 0); cap('eva', CAPS.eva, 0); cap('block', CAPS.block, 0); cap('maxHp', CAPS.maxHp, 0);
  for (const k in s.res) if (s.res[k] > CAPS.res) { s.res[k] = CAPS.res; s.capped['res' + k] = true; }
  return s;
}
/** 비교용 점수(대략): 칸별로 수치를 한 줄로 모은다 */
export function gearScore(it) {
  if (!it) return 0; const B = GEAR_BASES[it.base]; let v = (B.def || 0) * 3 + (B.eva || 0) * 0.3 + (B.block || 0) * 0.15 + (B.vision || 0) * 2;
  if (B.weapon) { const w = weaponOf(it); v += (w.dmg[0] + w.dmg[1]) * 0.8; }
  for (const a of it.affixes) if (a.known) v += a.id === 'hp' ? a.v * 0.6 : a.id === 'def' ? a.v * 3 : AFFIXES[a.id].flag ? 2.5 : a.v >= 5 ? a.v * 0.25 : a.v * 1.5;
  return v + (it.legend ? 6 : 0) + RARITY_ORDER.indexOf(it.rarity) * 0.5;
}

/* ================= 장착 · 해제 (던전: G, 정착지: 모험가) ================= */
/** 지금 장비를 가진 쪽: 던전에서는 G, 정착지에서는 META.hero */
export function holder() {
  if (Game.mode === 'town' && META && META.hero) { const h = META.hero; return { eq: h.eq, bag: h.bag, base: h.base, unit: h, town: true }; }
  return { eq: G.eq, bag: G.bag, base: G.heroBase, unit: G.player, town: false };
}
export function refreshStats() {
  const H = holder(); if (!H.eq) return;
  const s = calcStats(H.eq), mx = H.base + s.maxHp, u = H.unit;
  if (!H.town) G.ps = s;
  if (u && u.max !== mx) { u.hp = Math.max(1, Math.min(mx, u.hp + Math.max(0, mx - u.max))); u.max = mx; if (!H.town) emit('hp', { id: 0, hp: u.hp, max: u.max }); }
  return s;
}
const eqSnap = (H) => Object.fromEntries(SLOTS.map((k) => [k, H.eq[k] ? { ...H.eq[k] } : null]));
function revealOne(it) {
  if (it.known) return null;
  const a = it.affixes.find((q) => !q.known); if (a) a.known = true;
  if (it.affixes.every((q) => q.known)) it.known = true;
  return a;
}
export function revealAll(it) { if (!it || it.known) return false; for (const a of it.affixes) a.known = true; it.known = true; return true; }
export function equip(bagIdx, slot) {
  const H = holder(), it = H.bag[bagIdx]; if (!it || !fitsSlot(it, slot)) return false;
  const old = H.eq[slot]; H.bag.splice(bagIdx, 1); if (old) H.bag.push(old);
  H.eq[slot] = it;
  const r = revealOne(it);
  refreshStats();
  emit('equip', { slot, eq: eqSnap(H) });
  log(`${gearName(it)} 장착${r ? ` — 옵션 하나가 드러났다: ${affixLine(r)}` : ''}`, it.legend ? 'syn' : 'good');
  return true;
}
export function unequip(slot) {
  const H = holder(), it = H.eq[slot]; if (!it) return false;
  if (H.bag.length >= BAG_MAX) { log('가방이 가득 찼다', 'bad'); return false; }
  H.eq[slot] = null; H.bag.push(it); refreshStats();
  emit('equip', { slot, eq: eqSnap(H) }); log(`${gearName(it)} 해제`, 'info');
  return true;
}
/** 무기와 보조(두 번째 무기)를 맞바꾼다 — 턴을 쓰지 않는다 */
export function swapHands() {
  const H = holder(); if (!isWeapon(H.eq.off)) return false;
  [H.eq.weapon, H.eq.off] = [H.eq.off, H.eq.weapon]; refreshStats();
  emit('equip', { slot: 'weapon', eq: eqSnap(H) });
  return true;
}
export function dropGear(bagIdx) {
  const H = holder(), it = H.bag[bagIdx]; if (!it) return false;
  if (H.town) { H.bag.splice(bagIdx, 1); META.gear.push(it); return true; }
  const spot = gearSpot(G.player.x, G.player.y); if (!spot) { log('놓을 자리가 없다', 'bad'); return false; }
  H.bag.splice(bagIdx, 1); G.gear.set(I(spot[0], spot[1]), it);
  emit('gears', [...G.gear.entries()]); log(`${gearName(it)}을 내려놓았다`, 'info');
  return true;
}
export function pickGear() {
  const p = G.player, i = I(p.x, p.y), it = G.gear.get(i); if (!it) return false;
  if (G.bag.length >= BAG_MAX) { log('가방이 가득 찼다', 'bad'); return false; }
  G.gear.delete(i); G.bag.push(it);
  emit('gears', [...G.gear.entries()]); emit('pickup', { x: p.x, y: p.y });
  log(`${gearName(it)} 획득 — 🛡 장비 창에서 비교`, it.legend ? 'syn' : 'good');
  return true;
}
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
  if (it.legend) log(`전설 장비가 떨어졌다!`, 'legend');
}
export function dropGearFrom(e) {
  if (e.boss) { for (let k = 0; k < 2; k++) placeGear(rollGear('boss'), e.x, e.y); return; }
  const chance = GEAR_DROP[kindOf(e)] ?? GEAR_DROP.default;
  if (rand() * 100 < chance) placeGear(rollGear(G.floor), e.x, e.y);
}
export function openChest(x, y) {
  const i = I(x, y), c = G.chests.get(i); if (!c || c.open) return false;
  c.open = true; emit('chest', { x, y });
  G.chests.delete(i);
  let it = rollGear(G.floor + (c.rare ? 3 : 0)); if (c.rare && it.rarity === 'common') it = rollGear(G.floor + 6);
  placeGear(it, x, y); G.chests.set(i, c);
  log('상자를 열었다!', 'good');
  // 귀환 두루마리: 구역마다 최대 1개, 상자에서만 10%
  if (G.zoneFlags && !G.zoneFlags.recall && rand() < 0.1) { G.zoneFlags.recall = true; addItem('recall'); log('상자 바닥에 귀환 두루마리가 있었다!', 'syn'); }
  if (rand() < 0.08) { addLoot('마석', 1); emit('loot', { x, y, m: '마석' }); log('🔮 마석 한 조각', 'good'); }
  return true;
}
/** 층마다 상자 1~2개(+extra) */
export function placeChests(rooms, tile, extra = 0) {
  G.chests = new Map();
  const n = ri(1, 2) + extra;
  for (let k = 0, placed = 0; k < 200 && placed < n; k++) {
    const r = rooms[ri(1, rooms.length - 1)], x = ri(r.x, r.x + r.w - 1), y = ri(r.y, r.y + r.h - 1), i = I(x, y);
    if (tile[i] !== T_FLOOR || G.items.has(i) || G.mats.has(i) || G.gear.has(i) || G.chests.has(i)) continue;
    G.chests.set(i, { open: false }); placed++;
  }
}
