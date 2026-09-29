import { CATS, DROPS, catOf, kindOf } from '../data/enemies.js';
import { STONE } from '../data/stones.js';
import { S_WATER } from '../data/terrain.js';
import { FORMS } from '../data/weapons.js';
import { D8, cheb, sgn } from '../util/grid.js';
import { pick, rand, shuffle } from '../util/rng.js';
import { cancelIntent, damage, freeDropSpot, heal, push, weaponHit } from './combat.js';
import { dotBonus, fireAt, shock } from './elements.js';
import { emitSlots, emitStatus } from './snap.js';
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

/* ---------- 영혼석: 발동 · 연쇄 단계 ---------- */
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

export function trigger(color, info, ctx) {
  for (let s = 0; s < 6; s++) {
    if (!G.player.alive) return;
    const sl = G.slots[s], id = sl.stone;
    if (!id || STONE[id].color !== color || sl.cd > 0 || ctx.fired.has(s) || !stoneReady(id, info)) continue;
    if (color === 'green' && sl.gTurn === G.stats.turns) continue;
    ctx.fired.add(s); ctx.stones++;
    if (color === 'green') sl.gTurn = G.stats.turns;
    bumpStage(ctx);
    emit('stone', { slot: s, id, stage: ctx.stage });
    TL.wait(120);
    const prev = G.ctx; G.ctx = ctx;
    runStone(id, info, ctx);
    // 장비: 빨강 한 번 더 · 보라 회복 · 초록 보호막 · 가시 판금(초록 두 번)
    const ps = G.ps;
    if (ps && ((color === 'red' && ps.redTwice && rand() * 100 < ps.redTwice) || (color === 'green' && ps.legend.has('thornPlate'))) && stoneReady(id, info)) {
      emit('stone', { slot: s, id, stage: ctx.stage }); TL.wait(100); runStone(id, info, ctx);
    }
    if (ps && color === 'purple' && ps.purpleHeal) heal(G.player, ps.purpleHeal);
    if (ps && color === 'green' && ps.greenShield) addShield(ps.greenShield);
    G.ctx = prev;
    if (color === 'purple') { sl.cd = 2; emitSlots(); }
    TL.wait(50);
  }
}

export const nearFoes = (r) => G.ents.filter((e) => e.alive && isFoe(e) && G.vis[I(e.x, e.y)] && cheb(e.x, e.y, G.player.x, G.player.y) <= r);

export function nearestFoe(except) {
  let best = null, bd = 99;
  for (const e of G.ents) { if (!e.alive || !isFoe(e) || e === except || !G.vis[I(e.x, e.y)]) continue; const d = cheb(e.x, e.y, G.player.x, G.player.y); if (d < bd) { bd = d; best = e; } }
  return best;
}

export const dirFrom = (a, b) => [sgn(b.x - a.x), sgn(b.y - a.y)];

export function stoneReady(id, info) {
  const t = info.target, s = info.src, p = G.player, alive = (u) => !!(u && u.alive);
  switch (id) {
    case 'r_bleed': return alive(t) && !CATS[catOf(t)].noBleed;
    case 'r_extra': return alive(t) && t.st.bleed > 0;
    case 'r_freeze': return alive(t) && t.st.wet > 0;
    case 'r_arrow': return !!nearestFoe(t);
    case 'r_poison': case 'r_push': case 'r_shock': case 'r_fire': return alive(t);
    case 'p_summon': return G.ents.filter((e) => e.alive && e.ally && !e.npc).length < 2 && nearFoes(7).length > 0;
    case 'p_shield': case 'g_shield': return p.shield < 8;
    case 'p_heal': case 'g_heal': return p.hp < p.max;
    case 'p_poison': case 'p_push': return nearFoes(1).length > 0;
    case 'p_wet': return nearFoes(2).length > 0;
    case 'p_shock': return nearFoes(7).some((e) => e.st.wet > 0 || G.surf[I(e.x, e.y)] === S_WATER);
    case 'p_fire': return nearFoes(6).length > 0;
    case 'g_counter': return alive(s) && cheb(s.x, s.y, p.x, p.y) === 1;
    default: return alive(s);
  }
}

export function runStone(id, info, ctx) {
  const t = info.target, s = info.src, p = G.player;
  switch (id) {
    case 'r_bleed': t.st.bleed += 3; emitStatus(t); break;
    case 'r_extra': weaponHit(t, ctx, { extra: true }); break;
    case 'r_poison': poisonOn(t, 3); break;
    case 'r_push': push(t, ...dirFrom(p, t), 1); break;
    case 'r_arrow': boneArrow(nearestFoe(t), 2); break;
    case 'r_shock': zapOn(t, 2); break;
    case 'r_fire': fireAt(t.x, t.y, 2); break;
    case 'r_freeze': freezeUnit(t, 3); break;
    case 'p_summon': summon(); break;
    case 'p_shield': addShield(4); break;
    case 'p_poison': for (const e of nearFoes(1)) poisonOn(e, 3); break;
    case 'p_push': for (const e of nearFoes(1)) if (e.alive) push(e, ...dirFrom(p, e), 1); break;
    case 'p_heal': heal(p, 3); break;
    case 'p_shock': { const hs = new Set(); for (const e of nearFoes(7)) if (e.alive && !hs.has(e.id) && (e.st.wet > 0 || G.surf[I(e.x, e.y)] === S_WATER)) zapOn(e, 3, hs); break; }
    case 'p_fire': { const e = nearestFoe(null); if (e) { const dur = 90 + cheb(p.x, p.y, e.x, e.y) * 45; emit('proj', { kind: 'fire', from: [p.x, p.y], to: [e.x, e.y], dur }); TL.wait(dur); fireAt(e.x, e.y, 3); } break; }
    case 'p_wet': for (const e of nearFoes(2)) { e.st.wet = Math.max(e.st.wet, 3); e.st.burn = 0; emitStatus(e); emit('splash', { x: e.x, y: e.y }); } break;
    case 'g_counter': weaponHit(s, ctx, { counter: true }); break;
    case 'g_shield': addShield(2); break;
    case 'g_poison': poisonOn(s, 3); break;
    case 'g_push': push(s, ...dirFrom(p, s), 2); break;
    case 'g_heal': heal(p, 2); break;
    case 'g_shock': zapOn(s, 3); break;
    case 'g_fire': fireAt(s.x, s.y, 2); break;
    case 'g_freeze': freezeUnit(s, s.st.wet > 0 ? 5 : 2); break;
    default: break;
  }
}

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

export function addShield(n) { const p = G.player; p.shield = Math.min(8, p.shield + n); emit('shield', { v: p.shield, add: n }); }

export function boneArrow(e, dmg) {
  if (!e) return; const p = G.player, dur = 60 + cheb(p.x, p.y, e.x, e.y) * 35;
  emit('proj', { kind: 'bone', from: [p.x, p.y], to: [e.x, e.y], dur }); TL.wait(dur);
  damage(e, dmg, 'hit', { label: '뼈 화살' });
}

export function addStone(id) {
  const sl = G.slots.find((q) => !q.stone);
  if (sl) { sl.stone = id; sl.color = STONE[id].color; G.stats.stones++; log(`영혼석 「${STONE[id].icon} ${STONE[id].name}」 장착 — ${STONE[id].line}`, 'syn'); return true; }
  if (G.sbag.length < 3) { G.sbag.push(id); G.stats.stones++; log(`영혼석 「${STONE[id].icon} ${STONE[id].name}」 → 가방 (같은 색 칸과 교체 가능)`, 'good'); return true; }
  return false;
}

export function summon() {
  const p = G.player; let spot = null;
  for (const [dx, dy] of shuffle(D8.slice())) { const x = p.x + dx, y = p.y + dy; if (standable(x, y) && !entAt(x, y)) { spot = [x, y]; break; } }
  if (!spot) return;
  const a = { id: G.nextId++, type: 'goblin', ally: true, name: '영혼 고블린', x: spot[0], y: spot[1], hp: 5, max: 5, atk: 2, st: newSt(), alive: true, awake: true, face: [...p.face], life: 4 };
  G.ents.push(a);
  emit('spawn', { e: { ...a, st: { ...a.st } } });
  log('영혼 고블린이 곁에 섰다', 'good');
}

export function swapStone(bagIdx, slotIdx) {
  const id = G.sbag[bagIdx], sl = G.slots[slotIdx];
  if (!id || !sl.stone || sl.color !== STONE[id].color) return false;
  G.sbag[bagIdx] = sl.stone; sl.stone = id; sl.cd = 0;
  log(`「${STONE[id].name}」을 끼웠다`, 'good'); emitSlots(); return false;
}
