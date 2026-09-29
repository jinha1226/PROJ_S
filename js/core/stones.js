import { CATS, DROPS, catOf, kindOf } from '../data/enemies.js';
import { COLORS, STONE } from '../data/stones.js';
import { S_ASH, S_GRASS, S_NONE, S_WATER } from '../data/terrain.js';
import { HIDDEN_BY_ELEM } from '../data/visitors.js';
import { FORMS } from '../data/weapons.js';
import { D8, cheb, sgn } from '../util/grid.js';
import { pick, rand, shuffle } from '../util/rng.js';
import { cancelIntent, damage, freeDropSpot, heal, push, weaponHit } from './combat.js';
import { dotBonus, fireAt, shock } from './elements.js';
import { blockAt, openHidden } from './hidden.js';
import { adjFoes, areaTiles, arrowPath, castBolt, castFire, castFrost, castPush, castVenom, sdmg, wetTarget } from './skills.js';
import { emitSlots, emitStatus, snapTerrain } from './snap.js';
import { G, I, TL, emit, entAt, isFoe, log, newSt, standable } from './state.js';

export function synergy(text, elem) { G.stats.combos++; emit('banner', { text, elem }); log(text, 'syn'); if (G.ctx && (G.ctx.stones > 0 || G.ctx.origin !== 'enemy')) bumpStage(G.ctx); }

export function dropStone(e, f) {
  let color = f ? FORMS[f].color : null;
  if (!color) {
    if (rand() < 0.4) color = pick(['red', 'purple', 'green']);
    else { if (G.dropHint++ < 2) log('영혼이 흩어졌다 — 무기로 막타를 쳐야 영혼석이 확실히 남는다', 'info'); return; }
  }
  const id = DROPS[kindOf(e)][color], spot = freeDropSpot(e.x, e.y); if (!spot) return;
  G.stones.set(I(spot[0], spot[1]), id);
  emit('stoneDrop', { from: [e.x, e.y], to: spot, id, part: f ? FORMS[f].part : '잔해' });
}

/* ---------- 연쇄 단계: 스킬 발동과 원소 반응이 단계를 올린다 ---------- */
export function withCtx(origin, fn) {
  const prev = G.ctx, ctx = { origin, stage: 0, stones: 0, fired: new Set(), slow: false };
  G.ctx = ctx;
  try { fn(ctx); } finally { G.ctx = prev; }
  if (ctx.stage > 0) emit('chainEnd', { stage: ctx.stage });
  if (ctx.stage > G.stats.best) G.stats.best = ctx.stage;
  return ctx;
}

export function bumpStage(ctx) {
  ctx.stage++;
  emit('chainStage', { stage: ctx.stage });
  if (ctx.stage >= 3 && !ctx.slow) { ctx.slow = true; G.stats.chains++; emit('slowmo', { stage: ctx.stage }); }
}

/* ---------- 영혼석 스킬: 쿨타임 + 색 감소 (docs/설계_영혼석_스킬.md §2) ---------- */
/** 전투 중인가: 보이는 깨어 있는 적이 있다 */
export const inCombat = () => G.ents.some((e) => e.alive && isFoe(e) && e.awake && G.vis[I(e.x, e.y)]);
export const stoneCd = (id) => Math.max(1, STONE[id].cd - ((G.ps && G.ps.skillCd[id]) || 0));

/** 색 감소: 그 색의 모든 영혼석이 1 준다. 영혼석마다 한 라운드 한 번, 방금 쓴 것은 제외 */
export function reduceColor(color) {
  if (!G.slots || !inCombat()) return;
  const hit = [], ps = G.ps;
  for (let k = 0; k < G.slots.length; k++) {
    const sl = G.slots[k]; if (!sl.stone || sl.color !== color || sl.cd <= 0 || sl.redRound === G.round || sl.usedRound === G.round) continue;
    let n = 1;
    if (ps && color === 'red' && ps.redTwice && rand() * 100 < ps.redTwice) n++;
    if (ps && color === 'green' && ps.legend.has('thornPlate')) n++;
    sl.cd = Math.max(0, sl.cd - n); sl.redRound = G.round; hit.push([k, n]);
  }
  if (hit.length) { emit('cdReduce', { color, slots: hit }); emitSlots(); }
}

/** 내 턴이 끝날 때: 쿨타임 1 감소(방금 쓴 것은 다음 턴부터) */
export function tickStones() {
  if (!G.slots) return;
  let ch = false;
  for (const sl of G.slots) if (sl.cd > 0 && sl.usedRound !== G.round) { sl.cd--; ch = true; }
  if (ch) emitSlots();
}
/** 라운드(내 턴 + 적 턴)가 끝날 때: 지속 효과 감소, 전투가 끝났으면 모두 준비 */
export function endRound() {
  G.round = (G.round || 0) + 1;
  const A = G.auras || (G.auras = {}); let ch = false;
  for (const k of Object.keys(A)) { A[k]--; ch = true; if (A[k] <= 0) delete A[k]; }
  if (ch) emit('aura', { ...A });
  if (!inCombat()) {
    let reset = false; for (const sl of G.slots) if (sl.cd > 0) { sl.cd = 0; reset = true; }
    G.combatDmg = 0;
    if (reset) { emitSlots(); emit('stonesReady'); }
  }
}

/** 영혼석 스킬 사용(행동 한 번). 대상이 필요 없는 스킬은 tx,ty 생략 */
export function useStone(slot, tx, ty) { let r = false; withCtx('skill', (ctx) => { r = useStoneRaw(slot, tx, ty, ctx); }); return r; }
export function useStoneRaw(slot, tx, ty, ctx) {
  const sl = G.slots[slot], id = sl && sl.stone; if (!id || sl.cd > 0) return false;
  const S = STONE[id], p = G.player, sd = sdmg(), t = tx != null ? entAt(tx, ty) : null;
  if (tx != null) { const dx = sgn(tx - p.x), dy = sgn(ty - p.y); if (dx || dy) { p.face = [dx, dy]; emit('face', { id: 0, dx, dy }); } }
  sl.cd = stoneCd(id); sl.usedRound = G.round;
  emit('stone', { slot, id, stage: 1 }); emit('pcast', { color: COLORS[S.color].hex }); TL.wait(110);
  emitSlots();
  // 숨은 방 입구
  if (tx != null && S.elem && blockAt(tx, ty) === HIDDEN_BY_ELEM[S.elem]) {
    if (S.elem === 'push') { emit('lunge', { id: 0, dx: sgn(tx - p.x), dy: sgn(ty - p.y) }); TL.wait(90); }
    else if (S.elem === 'bolt') { emit('bolt', { from: [p.x, p.y], to: [tx, ty] }); TL.wait(70); }
    else { const dur = 90 + cheb(p.x, p.y, tx, ty) * 45; emit('proj', { kind: S.elem === 'fire' ? 'fire' : 'frost', from: [p.x, p.y], to: [tx, ty], dur }); TL.wait(dur); }
    openHidden(tx, ty, S.elem); TL.wait(120); return true;
  }
  switch (id) {
    case 'r_bleed': if (t) { weaponHit(t, ctx); if (t.alive && !CATS[catOf(t)].noBleed) { t.st.bleed += 5; emitStatus(t); } } break;
    case 'r_extra': if (t) { weaponHit(t, ctx); TL.wait(40); if (t.alive) weaponHit(t, ctx, { extra: true, bonus: t.st.bleed > 0 ? 2 : 0 }); } break;
    case 'r_poison': castVenom(tx, ty); break;
    case 'r_push': castPush(tx, ty, 2); break;
    case 'r_arrow': {
      const path = arrowPath(tx, ty, 6), end = path[path.length - 1] || [tx, ty], dur = 60 + path.length * 35;
      emit('proj', { kind: 'bone', from: [p.x, p.y], to: end, dur }); TL.wait(dur * 0.5); let n = 0;
      for (const [x, y] of path) { const e = entAt(x, y); if (e && isFoe(e) && e.alive && n < 2) { n++; damage(e, 4 + sd, 'hit', { label: '뼈 화살', dx: sgn(x - p.x), dy: sgn(y - p.y) }); } }
      break;
    }
    case 'r_shock': castBolt(tx, ty, 5 + sd); break;
    case 'r_fire': castFire(tx, ty, 4 + sd); break;
    case 'r_freeze': castFrost(tx, ty, 2 + sd); break;
    case 'p_summon': summon([tx, ty]); break;
    case 'p_shield': addShield(6, 10); break;
    case 'p_poison': emit('venomCloud', { x: p.x, y: p.y }); for (const e of adjFoes()) poisonOn(e, 4); break;
    case 'p_push': emit('ring', { x: p.x, y: p.y, elem: 'push' }); TL.wait(80); for (const e of adjFoes()) if (e.alive) { emit('shove', { x: e.x, y: e.y, dx: sgn(e.x - p.x), dy: sgn(e.y - p.y) }); push(e, ...dirFrom(p, e), 2); } break;
    case 'p_heal': heal(p, 6); if (p.st.poison || p.st.burn) { p.st.poison = 0; p.st.burn = 0; emitStatus(p); } break;
    case 'p_shock': { const hs = new Set(); for (const e of G.ents.filter((q) => q.alive && isFoe(q) && G.vis[I(q.x, q.y)] && wetTarget(q))) if (e.alive && !hs.has(e.id)) zapOn(e, 4 + sd, hs); break; }
    case 'p_fire': { const dur = 90 + cheb(p.x, p.y, tx, ty) * 45; emit('proj', { kind: 'fire', from: [p.x, p.y], to: [tx, ty], dur }); TL.wait(dur); for (const [x, y] of areaTiles(tx, ty, 1)) fireAt(x, y, 3 + sd); break; }
    case 'p_wet': {
      emit('splash', { x: tx, y: ty, big: true }); TL.wait(80);
      for (const [x, y] of areaTiles(tx, ty, 2)) {
        const i = I(x, y); if (G.surf[i] === S_NONE || G.surf[i] === S_ASH || G.surf[i] === S_GRASS) G.surf[i] = S_WATER; G.fire[i] = 0;
        const e = entAt(x, y); if (e && e.alive && !e.st.frozen) { e.st.wet = Math.max(e.st.wet, 3); e.st.burn = 0; emitStatus(e); if (isFoe(e)) emit('splash', { x, y }); }
      }
      snapTerrain(); log('물벼락 — 번개가 이어진 물을 따라 번진다', 'info'); break;
    }
    case 'g_counter': case 'g_shield': case 'g_poison': case 'g_shock': case 'g_freeze': {
      const A = G.auras || (G.auras = {}); A[S.aura] = S.rounds + 1; // 이번 라운드 끝에 1 줄어 다음 적 턴까지
      if (id === 'g_shield') addShield(3, 10);
      emit('aura', { ...A }); log(`${S.name} — ${S.line}`, 'syn'); break;
    }
    case 'g_push': if (t) { castPush(tx, ty, 3); if (t.alive) { t.st.stun = Math.max(t.st.stun, 1); cancelIntent(t); emitStatus(t); } } break;
    case 'g_heal': { const v = Math.min(8, Math.ceil((G.combatDmg || 0) / 2)); if (v > 0) heal(p, v); else log('아직 봉합할 상처가 없다', 'info'); break; }
    case 'g_fire': emit('ring', { x: p.x, y: p.y, elem: 'fire' }); TL.wait(80); for (const e of adjFoes()) if (e.alive) fireAt(e.x, e.y, 3 + sd); break;
    default: break;
  }
  // 장비: 보라 스킬 → 회복, 초록 스킬 → 보호막
  if (G.ps && S.color === 'purple' && G.ps.purpleHeal) heal(p, G.ps.purpleHeal);
  if (G.ps && S.color === 'green' && G.ps.greenShield) addShield(G.ps.greenShield);
  TL.wait(80);
  return true;
}

/** 지속 효과: 나를 때린 적에게 되갚는다 */
export function auraOnHurt(src) {
  const A = G.auras; if (!A || !src || !src.alive) return;
  const p = G.player;
  if (A.counter && cheb(src.x, src.y, p.x, p.y) === 1) withCtx('hit', (ctx) => weaponHit(src, ctx, { counter: true }));
  if (A.thorn && src.alive) poisonOn(src, 3);
  if (A.storm && src.alive) zapOn(src, 3);
  if (A.frost && src.alive) freezeUnit(src, src.st.wet > 0 ? 3 : 1);
}

export const nearFoes = (r) => G.ents.filter((e) => e.alive && isFoe(e) && G.vis[I(e.x, e.y)] && cheb(e.x, e.y, G.player.x, G.player.y) <= r);

export function nearestFoe(except) {
  let best = null, bd = 99;
  for (const e of G.ents) { if (!e.alive || !isFoe(e) || e === except || !G.vis[I(e.x, e.y)]) continue; const d = cheb(e.x, e.y, G.player.x, G.player.y); if (d < bd) { bd = d; best = e; } }
  return best;
}

export const dirFrom = (a, b) => [sgn(b.x - a.x), sgn(b.y - a.y)];

export function poisonOn(e, n) { if (!e || !e.alive || e.st.immune) return; e.st.poison = Math.max(e.st.poison, n + dotBonus(e)); emitStatus(e); emit('splat', { x: e.x, y: e.y }); }

export function zapOn(e, dmg, hitSet) {
  if (!e || !e.alive) return;
  const p = G.player; emit('bolt', { from: [p.x, p.y], to: [e.x, e.y] }); TL.wait(60);
  if (e.st.wet > 0 || G.surf[I(e.x, e.y)] === S_WATER) shock(e.x, e.y, dmg, { hitSet }); else { hitSet?.add(e.id); damage(e, dmg, 'shock'); }
}

export function freezeUnit(e, dur) {
  if (!e || !e.alive) return;
  emit('freeze', { x: e.x, y: e.y, center: true });
  if (e.st.wet > 0) synergy('젖은 채 빙결!', 'ice');
  e.st.frozen = Math.max(e.st.frozen, dur); e.st.wet = 0; e.st.burn = 0; emitStatus(e); cancelIntent(e);
}

export function addShield(n, cap = 8) { const p = G.player; p.shield = Math.min(Math.max(cap, p.shield), p.shield + n); emit('shield', { v: p.shield, add: n }); }

export function boneArrow(e, dmg) {
  if (!e) return; const p = G.player, dur = 60 + cheb(p.x, p.y, e.x, e.y) * 35;
  emit('proj', { kind: 'bone', from: [p.x, p.y], to: [e.x, e.y], dur }); TL.wait(dur);
  damage(e, dmg, 'hit', { label: '뼈 화살' });
}

export function addStone(id) {
  const sl = G.slots.find((q) => !q.stone);
  if (sl) { sl.stone = id; sl.color = STONE[id].color; G.stats.stones++; log(`영혼석 스킬 「${STONE[id].icon} ${STONE[id].name}」 — ${STONE[id].line}`, 'syn'); return true; }
  if (G.sbag.length < (G.sbagMax || 3)) { G.sbag.push(id); G.stats.stones++; log(`영혼석 「${STONE[id].icon} ${STONE[id].name}」 → 가방 (같은 색 칸과 교체 가능)`, 'good'); return true; }
  return false;
}

/** 발밑 영혼석을 거둔다. mode: 'absorb'(칸에 흡수 — slot을 주면 그 칸의 같은 색 영혼석과 바꾸고, 빠진 것은 가방으로) | 'bag' */
export function takeStone(mode, slot) {
  const p = G.player, i = I(p.x, p.y), id = G.stones.get(i); if (!id) return false;
  const S = STONE[id], max = G.sbagMax || 3;
  if (mode === 'bag') {
    if (G.sbag.length >= max) { log('영혼석 가방이 가득 찼다', 'bad'); return false; }
    G.sbag.push(id); log(`영혼석 「${S.icon} ${S.name}」 → 가방`, 'good');
  } else {
    let sl = slot != null ? G.slots[slot] : G.slots.find((q) => !q.stone);
    if (!sl) { log('빈 칸이 없다 — 같은 색 칸을 골라 바꿔 끼워야 한다', 'bad'); return false; }
    if (sl.stone) {
      if (sl.color !== S.color) { log('다른 색 칸에는 흡수할 수 없다', 'bad'); return false; }
      const old = sl.stone; if (G.sbag.length < max) { G.sbag.push(old); log(`「${STONE[old].name}」은 가방으로`, 'info'); } else log(`「${STONE[old].name}」은 흩어졌다`, 'info');
    }
    sl.stone = id; sl.color = S.color; sl.cd = 0;
    log(`영혼석 스킬 「${S.icon} ${S.name}」 — ${S.line}`, 'syn');
  }
  G.stones.delete(i); G.stoneOffer = null; G.stats.stones++;
  emit('stonePick', { x: p.x, y: p.y, id }); emitSlots();
  return true;
}

export function summon(at) {
  const p = G.player; let spot = at && at[0] != null && standable(at[0], at[1]) && !entAt(at[0], at[1]) ? at : null;
  if (!spot) for (const [dx, dy] of shuffle(D8.slice())) { const x = p.x + dx, y = p.y + dy; if (standable(x, y) && !entAt(x, y)) { spot = [x, y]; break; } }
  if (!spot) return;
  const mine = G.ents.filter((e) => e.alive && e.ally && !e.npc); if (mine.length >= 2) { mine[0].life = 0; mine[0].alive = false; emit('vanish', { id: mine[0].id }); } // 동시에 최대 2
  const a = { id: G.nextId++, type: 'goblin', ally: true, name: '영혼 고블린', x: spot[0], y: spot[1], hp: 5, max: 5, atk: 2, st: newSt(), alive: true, awake: true, face: [...p.face], life: 4 + (G.perk === 'A+' ? 1 : 0) };
  G.ents.push(a);
  emit('spawn', { e: { ...a, st: { ...a.st } } });
  log('영혼 고블린이 곁에 섰다', 'good');
}

export function swapStone(bagIdx, slotIdx) {
  const id = G.sbag[bagIdx], sl = G.slots[slotIdx];
  if (!id || !sl.stone || sl.color !== STONE[id].color) return false;
  G.sbag[bagIdx] = sl.stone; sl.stone = id; sl.cd = 0; // 교체는 적이 안 보일 때만 — 쿨타임도 비어 있다
  log(`「${STONE[id].name}」을 끼웠다`, 'good'); emitSlots(); return false;
}
