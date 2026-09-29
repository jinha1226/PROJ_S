import { C_STEAM, S_ASH, S_GRASS, S_ICE, S_OIL, S_WATER, T_WALL } from '../data/terrain.js';
import { D4, D8 } from '../util/grid.js';
import { cancelIntent, damage, resistOk } from './combat.js';
import { emitStatus, snapTerrain } from './snap.js';
import { G, I, TL, XY, emit, entAt, inb, isFoe, isP, log } from './state.js';
import { synergy } from './stones.js';

/* ================= 원소 ================= */
export function addCloud(i, type, ttl) { if (G.tile[i] === T_WALL) return; G.cloud[i] = type; G.cloudT[i] = Math.max(G.cloudT[i], ttl); }

export function steamAround(x, y) { for (const [dx, dy] of [[0, 0], ...D4]) { const nx = x + dx, ny = y + dy; if (inb(nx, ny) && G.tile[I(nx, ny)] !== T_WALL) addCloud(I(nx, ny), C_STEAM, 3); } snapTerrain(); }

/** 내가 건 화상·중독이면 장비의 지속 +턴 */
export const dotBonus = (e) => (isFoe(e) && G.ps && G.ctx && G.ctx.origin !== 'enemy' ? G.ps.dot : 0);

export function applyFire(e, dmg, o = {}) {
  if (!e.alive) return;
  if (isP(e) && G.ps && G.ps.burnImm && (G.surf[I(e.x, e.y)] === S_GRASS || G.fire[I(e.x, e.y)])) { emit('immune', { id: 0 }); return; }
  if (e.st.frozen > 0) {
    e.st.frozen = 0; e.st.wet = 3; emitStatus(e); cancelIntent(e);
    synergy('증기 폭발!', 'steam'); emit('steam', { x: e.x, y: e.y, big: true });
    damage(e, dmg + 4, 'steam', { label: '증기 폭발', big: true });
    steamAround(e.x, e.y); return;
  }
  if (e.st.poison > 0) { poisonBurst(e, o.chain || new Set()); return; }
  if (e.st.wet > 0) { e.st.wet = 0; emitStatus(e); emit('steam', { x: e.x, y: e.y, small: true }); damage(e, Math.ceil(dmg / 2), 'fire', { label: '치익' }); return; }
  damage(e, dmg, 'fire');
  const bt = 3 + dotBonus(e);
  if (e.alive && e.st.burn < bt && resistOk(e, 'fire')) { e.st.burn = bt; emitStatus(e); }
}

export function poisonBurst(e, chain) {
  if (chain.has(e.id) || !e.alive) return;
  chain.add(e.id);
  e.st.poison = 0; emitStatus(e);
  synergy(chain.size > 1 ? `독 폭발 연쇄 ×${chain.size}!` : '독 폭발!', 'poison');
  emit('explosion', { x: e.x, y: e.y, elem: 'poison' });
  damage(e, 7, 'blast', { label: '독 폭발', big: true });
  TL.wait(160);
  const cx = e.x, cy = e.y;
  for (const [dx, dy] of D8) {
    const nx = cx + dx, ny = cy + dy; if (!inb(nx, ny) || G.tile[I(nx, ny)] === T_WALL) continue;
    igniteTile(nx, ny, { chain, noFlash: true });
    const o = entAt(nx, ny);
    if (o && o.alive && !chain.has(o.id)) { if (o.st.poison > 0) poisonBurst(o, chain); else applyFire(o, 3, { chain }); }
  }
}

export function igniteTile(x, y, o = {}) {
  const i = I(x, y); if (G.tile[i] === T_WALL) return;
  const s = G.surf[i];
  if (s === S_OIL) { oilBlast(x, y, o.chain); return; }
  if (s === S_GRASS) { if (!G.fire[i]) { G.fire[i] = 3; emit('ignite', { x, y }); snapTerrain(); } return; }
  if (s === S_ICE) { G.surf[i] = S_WATER; emit('steam', { x, y }); addCloud(i, C_STEAM, 2); snapTerrain(); return; }
  if (s === S_WATER) { emit('steam', { x, y, small: true }); addCloud(i, C_STEAM, 2); snapTerrain(); return; }
  if (!o.noFlash) emit('ignite', { x, y, small: true });
}

export function oilSet(x0, y0) {
  const start = I(x0, y0); if (G.surf[start] !== S_OIL) return { layers: [], all: [] };
  const seen = new Set([start]), layers = []; let layer = [start];
  while (layer.length) {
    layers.push(layer); const next = [];
    for (const i of layer) { const [x, y] = XY(i); for (const [dx, dy] of D8) { const nx = x + dx, ny = y + dy; if (!inb(nx, ny)) continue; const j = I(nx, ny); if (!seen.has(j) && G.surf[j] === S_OIL) { seen.add(j); next.push(j); } } }
    layer = next;
  }
  return { layers, all: [...seen] };
}

export function oilBlast(x0, y0, chain = new Set()) {
  const { layers, all } = oilSet(x0, y0); if (!all.length) return;
  synergy(all.length > 1 ? `기름 연쇄 폭발 ×${all.length}!` : '기름 폭발!', 'fire');
  const hit = new Set();
  for (const L of layers) {
    for (const i of L) { G.surf[i] = S_ASH; G.fire[i] = 2; const [x, y] = XY(i); emit('explosion', { x, y, elem: 'fire', small: L.length > 2 }); }
    snapTerrain();
    for (const i of L) {
      const [x, y] = XY(i), c = entAt(x, y);
      if (c && !hit.has(c.id)) { hit.add(c.id); applyFire(c, 6, { chain }); }
      for (const [dx, dy] of D8) {
        const nx = x + dx, ny = y + dy; if (!inb(nx, ny)) continue; const j = I(nx, ny);
        if (G.surf[j] === S_GRASS && !G.fire[j]) { G.fire[j] = 3; emit('ignite', { x: nx, y: ny, small: true }); }
        const o = entAt(nx, ny); if (o && !hit.has(o.id) && G.surf[j] !== S_OIL) { hit.add(o.id); applyFire(o, 3, { chain }); }
      }
    }
    emit('shake', { a: 0.4 }); TL.wait(110);
  }
  snapTerrain();
}

export function conductSet(x0, y0) {
  const start = I(x0, y0);
  const cond = (i) => { if (G.surf[i] === S_WATER) return true; const [x, y] = XY(i), c = entAt(x, y); return !!(c && c.st.wet > 0 && !c.st.frozen); };
  const layers = [[start]], edges = [], seen = new Set([start]);
  if (!cond(start)) return { layers, edges, seen };
  let layer = [start];
  while (layer.length && seen.size < 48) {
    const next = [];
    for (const i of layer) {
      const [x, y] = XY(i);
      for (const [dx, dy] of D8) { const nx = x + dx, ny = y + dy; if (!inb(nx, ny)) continue; const j = I(nx, ny); if (seen.has(j) || G.tile[j] === T_WALL || !cond(j)) continue; seen.add(j); next.push(j); edges.push([i, j, layers.length]); }
    }
    if (next.length) layers.push(next);
    layer = next;
  }
  // 번개 감긴 반지: 번질 때 1칸 더
  if (seen.size > 1 && G.ps && G.ps.legend.has('stormRing') && G.ctx && G.ctx.origin !== 'enemy') {
    const next = [];
    for (const i of [...seen]) { const [x, y] = XY(i); for (const [dx, dy] of D8) { const nx = x + dx, ny = y + dy; if (!inb(nx, ny)) continue; const j = I(nx, ny); if (seen.has(j) || G.tile[j] === T_WALL) continue; seen.add(j); next.push(j); edges.push([i, j, layers.length]); } }
    if (next.length) layers.push(next);
  }
  return { layers, edges, seen };
}

export function shock(x0, y0, dmg, o = {}) {
  const hitSet = o.hitSet || new Set();
  const { layers, edges, seen } = conductSet(x0, y0);
  const who = [...seen].map((i) => entAt(...XY(i))).filter(Boolean);
  if (seen.size > 1 && who.length > 1) synergy(`감전 확산 ×${who.length}!`, 'bolt');
  else if (seen.size > 1) emit('banner', { text: '물을 타고 번진다!', elem: 'bolt' });
  for (let L = 0; L < layers.length; L++) {
    for (const [a, b, l] of edges) if (l === L) emit('arc', { a: XY(a), b: XY(b) });
    for (const i of layers[L]) {
      const [x, y] = XY(i), c = entAt(x, y);
      if (G.surf[i] === S_WATER) emit('zap', { x, y });
      if (!c || hitSet.has(c.id)) continue; hitSet.add(c.id);
      const wet = c.st.wet > 0 || G.surf[i] === S_WATER;
      damage(c, wet ? dmg + 2 : dmg, 'shock', { label: wet && seen.size > 1 ? '감전' : '' });
      if (c.alive && wet && resistOk(c, 'bolt')) { c.st.stun = Math.max(c.st.stun, 1); emitStatus(c); if (!isP(c)) cancelIntent(c); }
    }
    TL.wait(L === 0 ? 90 : 80);
  }
}

export function freezeAt(x, y, dmg, o) {
  if (!inb(x, y)) return; const i = I(x, y); if (G.tile[i] === T_WALL) return;
  const wasWater = G.surf[i] === S_WATER;
  if (wasWater) { G.surf[i] = S_ICE; o.changed = true; }
  if (G.fire[i]) { G.fire[i] = 0; o.changed = true; }
  emit('freeze', { x, y, water: wasWater, center: dmg > 0 });
  const c = entAt(x, y);
  if (!c || !c.alive || !(dmg > 0 || wasWater)) return;
  const wet = c.st.wet > 0 || wasWater;
  if (dmg) damage(c, dmg, 'frost');
  if (!c.alive || !resistOk(c, 'frost')) return;
  let dur = wet ? 5 : 2; if (isP(c)) dur = Math.min(dur, 2);
  if (wet && !o.said) { o.said = true; synergy(isP(c) ? '젖은 채로 얼었다!' : '젖은 채 빙결 — 5턴!', 'ice'); }
  c.st.frozen = Math.max(c.st.frozen, dur); c.st.wet = 0; c.st.burn = 0; emitStatus(c); if (!isP(c)) cancelIntent(c);
}

export function frostCast(x, y, dmg) { const o = {}; freezeAt(x, y, dmg, o); for (const [dx, dy] of D4) freezeAt(x + dx, y + dy, 0, o); if (o.changed) snapTerrain(); }

export function venomAt(x, y) {
  const c = entAt(x, y); emit('splat', { x, y });
  if (!c) return;
  damage(c, 1, 'poison');
  if (c.alive && !c.st.immune && resistOk(c, 'poison')) { c.st.poison = Math.max(c.st.poison, 6 + dotBonus(c)); emitStatus(c); }
}

export function fireAt(x, y, dmg) {
  const i = I(x, y), c = entAt(x, y);
  if (G.surf[i] === S_OIL) { oilBlast(x, y); return; }
  if (c) applyFire(c, dmg);
  igniteTile(x, y, { noFlash: !!c });
}

/* ================= 환경 틱: 불 번짐 · 구름 · 상태 ================= */
export function envTick() {
  const W = G.W, N = W * G.H, spread = new Set(), oilIgn = [];
  for (let i = 0; i < N; i++) if (G.fire[i] > 0) {
    const [x, y] = XY(i);
    for (const [dx, dy] of D4) { const nx = x + dx, ny = y + dy; if (!inb(nx, ny)) continue; const j = I(nx, ny); if (G.fire[j]) continue; if (G.surf[j] === S_GRASS) spread.add(j); else if (G.surf[j] === S_OIL) oilIgn.push(j); }
  }
  let changed = false;
  for (let i = 0; i < N; i++) if (G.fire[i] > 0) { G.fire[i]--; changed = true; if (!G.fire[i] && G.surf[i] === S_GRASS) G.surf[i] = S_ASH; }
  for (const j of spread) { G.fire[j] = 3; const [x, y] = XY(j); emit('ignite', { x, y, small: true }); }
  if (spread.size && [...spread].some((j) => G.vis[j])) log('불길이 풀밭을 타고 번진다', 'info');
  for (let i = 0; i < N; i++) if (G.cloudT[i] > 0) { G.cloudT[i]--; if (!G.cloudT[i]) G.cloud[i] = 0; changed = true; }
  if (changed || spread.size) snapTerrain();
  for (const j of oilIgn) if (G.surf[j] === S_OIL) oilBlast(...XY(j));
  for (const e of G.ents) {
    if (!e.alive) continue; const i = I(e.x, e.y);
    if (G.fire[i] > 0) applyFire(e, 2);
    if (e.alive && G.cloud[i] === C_STEAM) { damage(e, 1, 'steam'); if (e.alive && e.st.wet < 2) { e.st.wet = 2; emitStatus(e); } }
  }
  for (const e of G.ents) {
    if (!e.alive) continue;
    const st = e.st, i = I(e.x, e.y), before = JSON.stringify(st);
    if (st.burn > 0) { if (G.surf[i] === S_WATER) st.burn = 0; else { damage(e, 1, 'burn'); st.burn--; } }
    if (e.alive && st.poison > 0) { damage(e, 1, 'poison'); st.poison--; }
    if (e.alive && st.bleed > 0) { damage(e, 1, 'bleed'); st.bleed--; }
    if (st.frac > 0) st.frac--;
    if (G.surf[i] === S_WATER) st.wet = 3; else if (st.wet > 0) st.wet--;
    if (st.haste > 0) st.haste--; if (st.immune > 0) st.immune--;
    if (e.alive && JSON.stringify(st) !== before) emitStatus(e);
  }
}
