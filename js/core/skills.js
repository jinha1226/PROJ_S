import { damage, push } from './combat.js';
import { conductSet, fireAt, frostCast, oilSet, shock, venomAt } from './elements.js';
import { los } from './fov.js';
import { G, I, TL, XY, emit, entAt, inb, isFoe, isP, standable } from './state.js';
import { withCtx } from './stones.js';
import { blockAt, openHidden } from './hidden.js';
import { HIDDEN, HIDDEN_BY_SKILL } from '../data/visitors.js';
import { HEX } from '../data/colors.js';
import { ITEMS, ITEM_COL } from '../data/items.js';
import { SK } from '../data/skills.js';
import { S_GRASS, S_ICE, S_OIL, S_WATER, T_DOOR, T_WALL } from '../data/terrain.js';
import { D4, D8, cheb, sgn } from '../util/grid.js';

export function useSkill(id, tx, ty) { let r = false; withCtx('skill', () => { r = useSkillRaw(id, tx, ty); }); return r; }

export function useSkillRaw(id, tx, ty) {
  const p = G.player, sk = SK[id], dx = sgn(tx - p.x), dy = sgn(ty - p.y), d = cheb(p.x, p.y, tx, ty);
  if (dx || dy) { p.face = [dx, dy]; emit('face', { id: 0, dx, dy }); }
  G.cd[id] = sk.cd - ((G.ps && G.ps.skillCd[id]) || 0);
  const sd = G.ps ? G.ps.skillDmg : 0;
  emit('pcast', { elem: id });
  // 숨은 방 입구
  if (blockAt(tx, ty) === HIDDEN_BY_SKILL[id]) {
    if (id === 'push') { emit('lunge', { id: 0, dx, dy }); TL.wait(90); }
    else if (id === 'bolt') { emit('bolt', { from: [p.x, p.y], to: [tx, ty] }); TL.wait(70); }
    else { const dur = 90 + d * 45; emit('proj', { kind: id === 'fire' ? 'fire' : 'frost', from: [p.x, p.y], to: [tx, ty], dur }); TL.wait(dur); }
    openHidden(tx, ty, id); TL.wait(120); return true;
  }
  if (id === 'push') {
    const e = entAt(tx, ty); if (!e) return false;
    emit('lunge', { id: 0, dx, dy }); TL.wait(90); emit('shove', { x: tx, y: ty, dx, dy });
    damage(e, 1, 'hit', { dx, dy }); if (e.alive) push(e, dx, dy, 2);
  } else if (id === 'fire') {
    const dur = 90 + d * 45; emit('proj', { kind: 'fire', from: [p.x, p.y], to: [tx, ty], dur }); TL.wait(dur); fireAt(tx, ty, 4 + sd);
  } else if (id === 'bolt') {
    emit('bolt', { from: [p.x, p.y], to: [tx, ty] }); TL.wait(70);
    const c = entAt(tx, ty);
    if (G.surf[I(tx, ty)] === S_WATER || (c && c.st.wet && !c.st.frozen)) shock(tx, ty, 5 + sd);
    else if (c) damage(c, 5 + sd, 'shock'); else emit('zap', { x: tx, y: ty });
  } else if (id === 'frost') {
    const dur = 90 + d * 40; emit('proj', { kind: 'frost', from: [p.x, p.y], to: [tx, ty], dur }); TL.wait(dur); frostCast(tx, ty, 2 + sd);
  } else if (id === 'venom') {
    const dur = 70 + d * 35; emit('proj', { kind: 'dart', from: [p.x, p.y], to: [tx, ty], dur }); TL.wait(dur); venomAt(tx, ty);
  }
  TL.wait(80);
  return true;
}

export function targetsFor(pend) {
  const p = G.player, set = new Set();
  for (let dy = -pend.range; dy <= pend.range; dy++) for (let dx = -pend.range; dx <= pend.range; dx++) {
    if (!dx && !dy) continue;
    const x = p.x + dx, y = p.y + dy; if (!inb(x, y)) continue; const i = I(x, y);
    if (pend.kind === 'skill' && G.vis[i] && blockAt(x, y) === HIDDEN_BY_SKILL[pend.id] && los(p.x, p.y, x, y)) { set.add(i); continue; }
    if (!G.vis[i] || G.tile[i] === T_WALL || G.tile[i] === T_DOOR) continue;
    if (pend.needsEnemy) { const e = entAt(x, y); if (!e || !isFoe(e)) continue; }
    if (!los(p.x, p.y, x, y)) continue;
    set.add(i);
  }
  return set;
}

export function previewFor(pend, x, y) {
  const p = G.player, i = I(x, y), c = entAt(x, y), extra = [], id = pend.id; let note = '', warn = '';
  const add = (tx, ty, color, kind = 0, alpha = 0.85, rot = 0) => extra.push({ x: tx, y: ty, kind, color, alpha, rot });
  const bk = blockAt(x, y);
  if (bk && HIDDEN_BY_SKILL[id] === bk) { add(x, y, pend.color, 5, 0.9); return { extra, note: `→ ${HIDDEN[bk].name}을(를) 연다 — 너머에 무언가 있다` }; }
  if (id === 'push') {
    const dx = sgn(x - p.x), dy = sgn(y - p.y), rot = Math.atan2(dx, -dy); let cx = x, cy = y, left = 2, n = 0;
    while (left > 0 && n < 12) {
      const nx = cx + dx, ny = cy + dy;
      if (!standable(nx, ny)) { note = '→ 벽 충돌: 4 피해 + 기절'; add(cx, cy, HEX.danger, 6, 0.95); break; }
      const o = entAt(nx, ny); if (o) { note = `→ ${o.name}와 충돌: 둘 다 3 피해`; add(nx, ny, HEX.danger, 6, 0.95); break; }
      cx = nx; cy = ny; n++; left--; add(cx, cy, 0xf2e6c8, 2, 0.9, rot);
      if (G.surf[I(cx, cy)] === S_ICE && left === 0) left = 1;
    }
    if (!note) note = n > 2 ? '→ 얼음 위로 끝까지 미끄러진다!' : `→ ${n}칸 밀려난다`;
    const li = I(cx, cy); if (G.surf[li] === S_WATER) note += ' · 물에 빠져 젖는다'; if (G.fire[li]) note += ' · 불 속으로!';
    if (G.ents.some((e) => e.cast && e.cast.tiles.some(([a, b]) => a === cx && b === cy))) note += ' · 마법사의 표식 위로!';
  } else if (id === 'fire') {
    add(x, y, HEX.fire, 5, 0.9);
    if (G.surf[i] === S_OIL) { const s = oilSet(x, y).all; s.forEach((j) => add(...XY(j), HEX.fire, 5, 0.9)); note = `→ 기름 연쇄 폭발 ×${s.length} (닿은 적 6)`; if (s.some((j) => { const [a, b] = XY(j); return cheb(a, b, p.x, p.y) <= 1; })) warn = ' ⚠ 나도 휘말린다!'; }
    else if (c?.st.frozen) note = '→ 빙결을 녹여 증기 폭발 (+4)';
    else if (c?.st.poison) { note = '→ 독 폭발! 주변 8칸 3 피해, 중독된 적은 연쇄'; for (const [dx, dy] of D8) add(x + dx, y + dy, HEX.poison, 0, 0.6); if (cheb(x, y, p.x, p.y) <= 1) warn = ' ⚠ 나도 휘말린다!'; }
    else if (c?.st.wet || (c && G.surf[i] === S_WATER)) note = '→ 젖어 있다: 증기만 나고 절반 피해';
    else if (G.surf[i] === S_GRASS) note = `→ ${c ? '4 화염 + ' : ''}풀에 불이 붙어 매 턴 번진다`;
    else if (G.surf[i] === S_ICE) note = '→ 얼음이 녹아 물 + 증기';
    else note = c ? '→ 4 화염 + 화상 3턴' : '→ 빈 칸';
  } else if (id === 'bolt') {
    const cs = conductSet(x, y), direct = !(cs.seen.size > 1 || G.surf[i] === S_WATER || c?.st.wet); let n = 0, me = false;
    for (const j of cs.seen) { const [tx, ty] = XY(j); add(tx, ty, HEX.bolt, 5, 0.9); const o = entAt(tx, ty); if (o) { if (isP(o)) me = true; else n++; } }
    note = !direct ? `→ 감전 확산: 적 ${n} (+2, 기절)` : c ? '→ 5 번개 피해' : '→ 빈 칸';
    if (me) warn = ' ⚠ 나도 감전된다!';
  } else if (id === 'frost') {
    let w = 0;
    for (const [dx, dy] of [[0, 0], ...D4]) { const tx = x + dx, ty = y + dy; if (!inb(tx, ty) || G.tile[I(tx, ty)] === T_WALL) continue; add(tx, ty, HEX.ice, dx || dy ? 0 : 5, dx || dy ? 0.6 : 0.9); if (G.surf[I(tx, ty)] === S_WATER) { w++; if (tx === p.x && ty === p.y) warn = ' ⚠ 내 발밑도 언다!'; } }
    note = c ? (c.st.wet || G.surf[i] === S_WATER ? '→ 젖어 있다: 5턴 빙결!' : '→ 2 피해 + 빙결 2턴') : '→ 빈 칸';
    if (w) note += ` · 물 ${w}칸이 얼음으로`;
  } else if (id === 'venom') {
    add(x, y, HEX.poison, 5, 0.9); note = c ? '→ 중독 6턴 — 이후 불이 닿으면 독 폭발' : '→ 빈 칸';
  } else {
    const known = G.known[id], sq = id === 'smoke' && known;
    for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
      if (!sq && dx && dy) continue; const tx = x + dx, ty = y + dy; if (!inb(tx, ty) || G.tile[I(tx, ty)] === T_WALL) continue;
      add(tx, ty, known ? ITEM_COL[id] : 0xd0d0e0, dx || dy ? 0 : 5, dx || dy ? 0.6 : 0.9);
    }
    note = known ? '→ ' + ITEMS[id].desc : '→ 무엇이 들었을까…';
  }
  return { extra, note: note + (warn ? `<b style="color:#ff8a8a">${warn}</b>` : '') };
}
