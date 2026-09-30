import { HEX } from '../data/colors.js';
import { CATS, catOf } from '../data/enemies.js';
import { weaponOf } from '../data/gear.js';
import { ITEMS, ITEM_COL } from '../data/items.js';
import { STONE } from '../data/stones.js';
import { S_GRASS, S_ICE, S_OIL, S_WATER, T_DOOR, T_WALL } from '../data/terrain.js';
import { HIDDEN, HIDDEN_BY_ELEM } from '../data/visitors.js';
import { D4, D8, cheb, sgn } from '../util/grid.js';
import { jo } from '../util/text.js';
import { damage, push } from './combat.js';
import { conductSet, fireAt, frostCast, oilSet, shock, venomAt } from './elements.js';
import { lineTiles, los } from './fov.js';
import { blockAt } from './hidden.js';
import { G, I, XY, emit, entAt, inb, isFoe, isP, standable } from './state.js';

/* ================= 스킬 효과 · 조준 · 미리보기 =================
   옛 스킬 5개(밀치기·불씨·번개·냉기·독침)의 효과·조준·연출을 영혼석 스킬이 이어받는다.
   core/stones.js의 useStone이 이 함수들을 부른다. */
export const sdmg = () => (G.ps ? G.ps.skillDmg : 0);

export function castPush(tx, ty, n) {
  const p = G.player, dx = sgn(tx - p.x), dy = sgn(ty - p.y), e = entAt(tx, ty); if (!e) return false;
  emit('lunge', { id: 0, dx, dy }); emit('shove', { x: tx, y: ty, dx, dy });
  damage(e, 1, 'hit', { dx, dy }); if (e.alive) push(e, dx, dy, n);
  return true;
}
export function castFire(tx, ty, dmg) { const p = G.player, dur = 90 + cheb(p.x, p.y, tx, ty) * 45; emit('proj', { kind: 'fire', from: [p.x, p.y], to: [tx, ty], dur }); fireAt(tx, ty, dmg); }
export function castBolt(tx, ty, dmg) {
  const p = G.player; emit('bolt', { from: [p.x, p.y], to: [tx, ty] }); 
  const c = entAt(tx, ty);
  if (G.surf[I(tx, ty)] === S_WATER || (c && c.st.wet && !c.st.frozen)) shock(tx, ty, dmg); else if (c) damage(c, dmg, 'shock'); else emit('zap', { x: tx, y: ty });
}
export function castFrost(tx, ty, dmg) { const p = G.player, dur = 90 + cheb(p.x, p.y, tx, ty) * 40; emit('proj', { kind: 'frost', from: [p.x, p.y], to: [tx, ty], dur }); frostCast(tx, ty, dmg); }
export function castVenom(tx, ty) { const p = G.player, dur = 70 + cheb(p.x, p.y, tx, ty) * 35; emit('proj', { kind: 'dart', from: [p.x, p.y], to: [tx, ty], dur }); venomAt(tx, ty); }

/** 뼈 화살이 지나갈 칸: 나 → (tx,ty) 방향으로 n칸, 벽에서 멈춘다 */
export function arrowPath(tx, ty, n) {
  const p = G.player, d = Math.max(1, cheb(p.x, p.y, tx, ty)), fx = p.x + Math.round(((tx - p.x) / d) * n), fy = p.y + Math.round(((ty - p.y) / d) * n), out = [];
  for (const [x, y] of [...lineTiles(p.x, p.y, fx, fy), [fx, fy]]) { if (!inb(x, y) || !standable(x, y)) break; out.push([x, y]); if (out.length >= n) break; }
  return out;
}
/** 물벼락·불길 범위 */
export function areaTiles(x, y, rad) {
  const out = [];
  for (let dy = -rad; dy <= rad; dy++) for (let dx = -rad; dx <= rad; dx++) { const tx = x + dx, ty = y + dy; if (!inb(tx, ty) || G.tile[I(tx, ty)] === T_WALL || dx * dx + dy * dy > rad * rad + rad) continue; out.push([tx, ty]); }
  return out;
}
export const adjFoes = () => { const p = G.player, out = []; for (const [dx, dy] of D8) { const e = entAt(p.x + dx, p.y + dy); if (e && isFoe(e) && e.alive) out.push(e); } return out; };
export const wetTarget = (e) => e.st.wet > 0 || G.surf[I(e.x, e.y)] === S_WATER;

/** 조준 가능한 칸. pend.kind: 'stone'(영혼석 스킬) | 'item'(던지기) */
export function targetsFor(pend) {
  const p = G.player, set = new Set(), T = pend.kind === 'stone' ? STONE[pend.id].tgt : { t: 'tile', r: pend.range }, elem = pend.kind === 'stone' ? STONE[pend.id].elem : null;
  if (T.t === 'self' || T.t === 'around' || T.t === 'sight') return set;
  const R = T.t === 'adj' || T.t === 'empty' ? 1 : T.r;
  for (let dy = -R; dy <= R; dy++) for (let dx = -R; dx <= R; dx++) {
    if (!dx && !dy) continue;
    const x = p.x + dx, y = p.y + dy; if (!inb(x, y)) continue; const i = I(x, y);
    if (!G.vis[i]) continue;
    if (elem && blockAt(x, y) === HIDDEN_BY_ELEM[elem] && los(p.x, p.y, x, y)) { set.add(i); continue; } // 숨은 방 입구
    if (G.tile[i] === T_WALL || G.tile[i] === T_DOOR) continue;
    if (T.t === 'adj') { const e = entAt(x, y); if (!e || !isFoe(e)) continue; }
    if (T.t === 'empty' && (!standable(x, y) || entAt(x, y))) continue;
    if (!los(p.x, p.y, x, y)) continue;
    set.add(i);
  }
  return set;
}

/** 무기 한 방 예상 피해 */
function weaponRange(t, bonus = 0) {
  const w = weaponOf(G.eq.weapon), weak = t && CATS[catOf(t)].weak === w.form, k = (weak ? 1.5 : 1) * (t && t.st.frozen ? 1.5 : 1);
  return [Math.ceil((w.dmg[0] + G.ps.dmg + bonus) * k), Math.ceil((w.dmg[1] + G.ps.dmg + bonus) * k)];
}
function pushPreview(x, y, dx, dy, n, add) {
  let cx = x, cy = y, left = n, k = 0, note = ''; const rot = Math.atan2(dx, -dy);
  while (left > 0 && k < 12) {
    const nx = cx + dx, ny = cy + dy;
    if (!standable(nx, ny)) { note = '벽에 충돌해 피해 4, 기절.'; add(cx, cy, HEX.danger, 6, 0.95); break; }
    const o = entAt(nx, ny); if (o) { note = `${jo(o.name, '과와')} 충돌해 둘 다 피해 3.`; add(nx, ny, HEX.danger, 6, 0.95); break; }
    cx = nx; cy = ny; k++; left--; add(cx, cy, 0xf2e6c8, 2, 0.9, rot);
    if (G.surf[I(cx, cy)] === S_ICE && left === 0) left = 1;
  }
  if (!note) note = k > n ? '얼음 위로 끝까지 미끄러진다.' : `${k}칸 밀려난다.`;
  const li = I(cx, cy); if (G.surf[li] === S_WATER) note += ' 물에 빠져 젖는다.'; if (G.fire[li]) note += ' 불 속으로 밀려난다.';
  if (G.ents.some((e) => e.act && e.act.kind === 'cast' && e.act.cells.some(([a, b]) => a === cx && b === cy))) note += ' 마법사의 표식 위에 선다.';
  return note;
}

/** 대상 칸을 골랐을 때 맞을 대상과 예상 효과 */
export function previewFor(pend, x, y) {
  const p = G.player, i = I(x, y), c = entAt(x, y), extra = [], sd = sdmg(); let note = '', warn = '';
  const add = (tx, ty, color, kind = 0, alpha = 0.85, rot = 0) => extra.push({ x: tx, y: ty, kind, color, alpha, rot });
  const id = pend.id, S = pend.kind === 'stone' ? STONE[id] : null;
  const bk = blockAt(x, y);
  if (S && bk && HIDDEN_BY_ELEM[S.elem] === bk) { add(x, y, pend.color, 5, 0.9); return { extra, note: `${jo(HIDDEN[bk].name, '을를')} 연다. 너머에 무언가 있다.` }; }
  if (id === 'r_push' || id === 'g_push') {
    note = pushPreview(x, y, sgn(x - p.x), sgn(y - p.y), id === 'g_push' ? 3 : 2, add) + (id === 'g_push' ? ' 1턴 기절.' : '');
  } else if (id === 'r_bleed' || id === 'r_extra') {
    const [lo, hi] = weaponRange(c); add(x, y, HEX.danger, 5, 0.9);
    note = id === 'r_bleed' ? `무기 피해 ${lo}~${hi}, 출혈 5.${c && CATS[catOf(c)].noBleed ? ' 해골은 피가 없다.' : ''}` : `무기 피해 ${lo}~${hi}로 두 번 벤다.${c && c.st.bleed ? ' 출혈 중이라 두 번째가 2 더 아프다.' : ''}`;
  } else if (id === 'r_arrow') {
    let n = 0; for (const [tx, ty] of arrowPath(x, y, 6)) { const o = entAt(tx, ty); const foe = o && isFoe(o) && n < 2; if (foe) n++; add(tx, ty, foe ? HEX.danger : 0xf2ead8, foe ? 5 : 3, 0.9); }
    note = n ? `적 ${n}명을 꿰뚫는다. 피해 ${4 + sd}.` : '맞을 적이 없다.';
  } else if (id === 'r_fire') {
    add(x, y, HEX.fire, 5, 0.9);
    if (G.surf[i] === S_OIL) { const s = oilSet(x, y).all; s.forEach((j) => add(...XY(j), HEX.fire, 5, 0.9)); note = `기름 ${s.length}칸이 터진다. 닿은 적은 피해 6.`; if (s.some((j) => { const [a, b] = XY(j); return cheb(a, b, p.x, p.y) <= 1; })) warn = ' ⚠ 나도 휘말린다.'; }
    else if (c?.st.frozen) note = '얼음이 녹아 증기 폭발. 피해 4 추가.';
    else if (c?.st.poison) { note = '독 폭발. 주변 8칸에 피해 3, 중독된 적은 연쇄.'; for (const [dx, dy] of D8) add(x + dx, y + dy, HEX.poison, 0, 0.6); if (cheb(x, y, p.x, p.y) <= 1) warn = ' ⚠ 나도 휘말린다.'; }
    else if (c?.st.wet || (c && G.surf[i] === S_WATER)) note = '젖어 있어 증기만 나고 피해는 절반.';
    else if (G.surf[i] === S_GRASS) note = `${c ? `불 ${4 + sd}. ` : ''}풀에 불이 붙어 매 턴 번진다.`;
    else if (G.surf[i] === S_ICE) note = '얼음이 녹아 물과 증기가 된다.';
    else note = c ? `불 ${4 + sd}, 화상 3턴.` : '빈 칸이다.';
  } else if (id === 'r_shock') {
    const cs = conductSet(x, y), direct = !(cs.seen.size > 1 || G.surf[i] === S_WATER || c?.st.wet); let n = 0, me = false;
    for (const j of cs.seen) { const [tx, ty] = XY(j); add(tx, ty, HEX.bolt, 5, 0.9); const o = entAt(tx, ty); if (o) { if (isP(o)) me = true; else n++; } }
    note = !direct ? `번개가 적 ${n}명에게 번진다. 피해 2 추가, 기절.` : c ? `번개 ${5 + sd}.` : '빈 칸이다.';
    if (me) warn = ' ⚠ 나도 감전된다.';
  } else if (id === 'r_freeze') {
    let w = 0;
    for (const [dx, dy] of [[0, 0], ...D4]) { const tx = x + dx, ty = y + dy; if (!inb(tx, ty) || G.tile[I(tx, ty)] === T_WALL) continue; add(tx, ty, HEX.ice, dx || dy ? 0 : 5, dx || dy ? 0.6 : 0.9); if (G.surf[I(tx, ty)] === S_WATER) { w++; if (tx === p.x && ty === p.y) warn = ' ⚠ 내 발밑도 언다.'; } }
    note = c ? (c.st.wet || G.surf[i] === S_WATER ? '젖어 있어 5턴 얼어붙는다.' : `냉기 ${2 + sd}, 2턴 얼린다.`) : '빈 칸이다.';
    if (w) note += ` 물 ${w}칸이 언다.`;
  } else if (id === 'r_poison') {
    add(x, y, HEX.poison, 5, 0.9); note = c ? '6턴 중독. 불이 닿으면 터진다.' : '빈 칸이다.';
  } else if (id === 'p_fire') {
    let n = 0, grass = 0; for (const [tx, ty] of areaTiles(x, y, 1 + (G.ps ? G.ps.orb.purple : 0))) { add(tx, ty, HEX.fire, 5, 0.85); const o = entAt(tx, ty); if (o && isFoe(o)) n++; if (G.surf[I(tx, ty)] === S_GRASS) grass++; if (o && isP(o)) warn = ' ⚠ 나도 불길 안이다.'; }
    note = `불길이 적 ${n}명을 덮친다. 불 ${3 + sd}, 화상.${grass ? ` 풀 ${grass}칸에 번진다.` : ''}`;
  } else if (id === 'p_wet') {
    let n = 0; for (const [tx, ty] of areaTiles(x, y, 2 + (G.ps ? G.ps.orb.purple : 0))) { add(tx, ty, HEX.water, 0, 0.7); const o = entAt(tx, ty); if (o && isFoe(o)) { n++; add(tx, ty, HEX.water, 5, 0.9); } }
    note = `적 ${n}명이 젖고 바닥에 물이 고인다.`;
  } else if (id === 'p_summon') {
    add(x, y, 0xc8a0ff, 5, 0.9); note = '영혼 고블린이 4턴 동안 여기 선다.';
  } else {
    // 던지는 소모품
    const known = G.known[id], sq = id === 'smoke' && known;
    for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
      if (!sq && dx && dy) continue; const tx = x + dx, ty = y + dy; if (!inb(tx, ty) || G.tile[I(tx, ty)] === T_WALL) continue;
      add(tx, ty, known ? ITEM_COL[id] : 0xd0d0e0, dx || dy ? 0 : 5, dx || dy ? 0.6 : 0.9);
    }
    note = known ? ITEMS[id].desc : '무엇이 들었을까…';
  }
  return { extra, note: note + (warn ? `<b style="color:#ff8a8a">${warn}</b>` : '') };
}

/** 자기 대상 스킬(나·주변·시야)의 미리보기 */
export function selfPreview(id) {
  const p = G.player, extra = [], sd = sdmg(), add = (x, y, color, kind = 5, alpha = 0.9, rot = 0) => extra.push({ x, y, kind, color, alpha, rot });
  const S = STONE[id], foes = adjFoes(); let note = '';
  switch (id) {
    case 'p_poison': foes.forEach((e) => add(e.x, e.y, HEX.poison)); for (const [dx, dy] of D8) add(p.x + dx, p.y + dy, HEX.poison, 0, 0.5); note = `붙은 적 ${foes.length}명 중독 4, 주변에 독 안개.`; break;
    case 'p_push': { const n = []; for (const e of foes) n.push(pushPreview(e.x, e.y, sgn(e.x - p.x), sgn(e.y - p.y), 2, add)); note = foes.length ? `붙은 적 ${foes.length}명을 2칸 밀친다.${n.some((t) => t.includes('충돌')) ? ' 부딪히는 적이 있다.' : ''}` : '붙은 적이 없다.'; break; }
    case 'g_fire': foes.forEach((e) => add(e.x, e.y, HEX.fire)); note = foes.length ? `붙은 적 ${foes.length}명에게 불 ${3 + sd}, 화상.` : '붙은 적이 없다.'; break;
    case 'p_shock': { const hs = new Set(); let n = 0; for (const e of G.ents) if (e.alive && isFoe(e) && G.vis[I(e.x, e.y)] && wetTarget(e)) { for (const j of conductSet(e.x, e.y).seen) { if (hs.has(j)) continue; hs.add(j); const [tx, ty] = XY(j); add(tx, ty, HEX.bolt, 5, 0.85); const o = entAt(tx, ty); if (o && isFoe(o)) n++; } }
      note = n ? `젖은 적 ${n}명에게 번개 ${4 + sd}.` : '보이는 젖은 적이 없다.'; break; }
    case 'p_shield': note = `보호막 6을 얻는다. 지금 ${p.shield}, 최대 10.`; break;
    case 'p_heal': note = `HP ${Math.min(6, p.max - p.hp)} 회복.${p.st.poison || p.st.burn ? ' 중독과 화상이 풀린다.' : ''}`; break;
    case 'g_heal': note = `이번 전투에서 받은 피해 ${G.combatDmg || 0}의 절반, HP ${Math.min(8, Math.ceil((G.combatDmg || 0) / 2), p.max - p.hp)} 회복.`; break;
    default: note = S.line;
  }
  return { extra, note };
}
