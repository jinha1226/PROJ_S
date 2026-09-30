import { SLOTS } from '../data/gear.js';
import { ITEMS } from '../data/items.js';
import { C_SMOKE, S_ICE, S_OIL, S_WATER, T_DOOR, T_WALL } from '../data/terrain.js';
import { JAR_REFILL } from '../data/torch.js';
import { plus, square3 } from '../sim/shapes.js';
import { D8, cheb, sgn } from '../util/grid.js';
import { pick, ri } from '../util/rng.js';
import { cancelIntent, heal, moveEnt, onEnter } from './combat.js';
import { addCloud, fireAt, oilBlast } from './elements.js';
import { canSee, computeFOV } from './fov.js';
import { canEnchant, enchantItem, fullyKnown, identifyItem } from './gear.js';
import { emitStatus, snapTerrain, snapVis } from './snap.js';
import { G, I, emit, entAt, inb, isFoe, log, standable } from './state.js';
import { refillTorch } from './torch.js';


export function itemName(k) { return G.known[k] ? ITEMS[k].name : G.look[k].name; }

export function addItem(k) { const s = G.inv.find((q) => q.k === k); if (s) s.n++; else G.inv.push({ k, n: 1 }); }

export function takeItem(k) { const s = G.inv.find((q) => q.k === k); if (!s) return false; s.n--; if (!s.n) G.inv.splice(G.inv.indexOf(s), 1); return true; }

export function identify(k) { if (G.known[k]) return; const old = G.look[k].name; G.known[k] = true; log(`${old}, 알고 보니 ${ITEMS[k].name}.`, 'syn'); emit('identify', { text: ITEMS[k].name }); }

export function teleSpot() {
  const p = G.player; let best = null, bs = -1;
  for (let k = 0; k < 60; k++) {
    const r = pick(G.rooms), x = ri(r.x, r.x + r.w - 1), y = ri(r.y, r.y + r.h - 1), i = I(x, y);
    if (!standable(x, y) || entAt(x, y) || G.fire[i] || G.surf[i] === S_OIL) continue;
    let s = Math.min(cheb(x, y, p.x, p.y), 12);
    for (const e of G.ents) if (isFoe(e) && e.alive) s = Math.min(s, cheb(x, y, e.x, e.y) * 1.5);
    if (s > bs) { bs = s; best = [x, y]; }
  }
  return best || [p.x, p.y];
}

export function useItem(k, tx, ty) {
  const p = G.player, cat = ITEMS[k].cat;
  if (k === 'recall' && G.bossFloor) { log('보스의 어둠이 짙어 빛이 모이지 않는다.', 'bad'); return false; }
  if (cat === 'throw') return throwItem(k, tx, ty);
  // 장비를 골라 쓰는 두루마리: tx = 장비 uid
  let target = null;
  if (ITEMS[k].target) {
    target = [...SLOTS.map((s) => G.eq[s]), ...G.bag].find((it) => it && it.uid === tx);
    if (!target) return false;
    if (k === 'ident' && fullyKnown(target)) { log('이미 다 아는 장비다.', 'info'); return false; }
    if (k !== 'ident' && !canEnchant(target, k === 'enchW' ? 'w' : 'a')) { log('이 장비는 더 강화할 수 없다.', 'bad'); return false; }
  }
  if (!takeItem(k)) return false;
  emit(cat === 'potion' ? 'drink' : 'read', { color: G.look[k].color });
  
  identify(k);
  if (k === 'heal') { heal(p, Math.round(15 * (1 + (G.ps ? G.ps.potion : 0) / 100))); if (p.st.burn) { p.st.burn = 0; emitStatus(p); } }
  else if (k === 'ember_jar') { refillTorch(JAR_REFILL); log('모닥불 불씨를 옮겨 담았다.', 'good'); computeFOV(); snapVis(); }
  else if (k === 'ident') identifyItem(target);
  else if (k === 'enchW' || k === 'enchA') enchantItem(target, k === 'enchW' ? 'w' : 'a');
  else if (k === 'cure') { Object.assign(p.st, { poison: 0, burn: 0, wet: 0, immune: 12 }); emitStatus(p); log('몸이 깨끗해졌다. 한동안 독이 듣지 않는다.', 'good'); }
  else if (k === 'haste') { p.st.haste = 8; emitStatus(p); log('몸이 가벼워졌다.', 'good'); }
  else if (k === 'tele') {
    const [x, y] = teleSpot(); emit('poof', { x: p.x, y: p.y }); 
    moveEnt(p, x, y, { dur: 1, hop: 0, kind: 'tele' }); emit('poof', { x, y }); computeFOV(); snapVis(); onEnter(p); log('공간이 뒤틀렸다.', 'info');
  } else if (k === 'fear') {
    let n = 0;
    for (const e of G.ents) if (isFoe(e) && e.alive && G.vis[I(e.x, e.y)]) { e.st.fear = 6; e.awake = true; cancelIntent(e); emitStatus(e); emit('scare', { id: e.id }); n++; }
    log(n ? `적 ${n}명이 겁에 질려 달아난다.` : '공포가 텅 빈 방에 퍼졌다.', n ? 'good' : '');
  } else if (k === 'recall') {
    emit('recallGlow', { x: p.x, y: p.y }); log('두루마리에 빛이 모인다.', 'syn'); G.recallArm = true;
  } else if (k === 'blaze') {
    emit('ring', { x: p.x, y: p.y, elem: 'fire' }); 
    for (const [dx, dy] of D8) { const x = p.x + dx, y = p.y + dy; if (inb(x, y) && G.tile[I(x, y)] !== T_WALL) fireAt(x, y, 4); }
  }
  
  return true;
}

export function throwItem(k, tx, ty) {
  if (!takeItem(k)) return false;
  landThrow(k, tx, ty);
  // 연금술사의 장갑: 하나가 더 옆으로 갈라져 날아간다
  if (G.ps && G.ps.legend.has('alchGlove')) {
    const p = G.player, dx = sgn(tx - p.x), dy = sgn(ty - p.y), side = [[-dy, dx], [dy, -dx]].map(([a, b]) => [tx + a * 2, ty + b * 2]).find(([x, y]) => inb(x, y) && G.tile[I(x, y)] !== T_WALL);
    if (side) { log('병이 둘로 갈라졌다.', 'syn'); landThrow(k, side[0], side[1]); }
  }
  
  return true;
}
function landThrow(k, tx, ty) {
  const p = G.player, d = cheb(p.x, p.y, tx, ty), dur = 130 + d * 50, wide = G.ps && G.ps.throwArea;
  const dx = sgn(tx - p.x), dy = sgn(ty - p.y); if (dx || dy) { p.face = [dx, dy]; emit('face', { id: 0, dx, dy }); }
  emit('lunge', { id: 0, dx, dy, amt: 0.2 });
  emit('proj', { kind: 'flask', from: [p.x, p.y], to: [tx, ty], dur, color: G.look[k].color }); 
  emit('shatter', { x: tx, y: ty, color: G.look[k].color });
  identify(k);
  if (k === 'smoke') {
    const r = wide ? 2 : 1;
    for (let yy = -r; yy <= r; yy++) for (let xx = -r; xx <= r; xx++) { const x = tx + xx, y = ty + yy; if (inb(x, y)) addCloud(I(x, y), C_SMOKE, 6); }
    snapTerrain(); emit('smokeburst', { x: tx, y: ty });
    for (const e of G.ents) if (e.act && !e.act.done && (e.act.kind === 'aim' || e.act.kind === 'cast') && !canSee(e, p)) cancelIntent(e); // 연기 너머로는 겨누지 못한다
  } else {
    let ign = null;
    for (const [x, y] of (wide ? square3(tx, ty) : plus(tx, ty))) {
      const i = I(x, y); if (G.tile[i] === T_DOOR) continue;
      if (k === 'oil') { if (G.surf[i] === S_WATER || G.surf[i] === S_ICE) continue; G.surf[i] = S_OIL; if (G.fire[i]) ign = [x, y]; }
      else {
        if (G.surf[i] !== S_ICE) G.surf[i] = S_WATER;
        if (G.fire[i]) { G.fire[i] = 0; emit('steam', { x, y, small: true }); }
        const c = entAt(x, y); if (c) { c.st.wet = 3; c.st.burn = 0; emitStatus(c); }
      }
      emit('splash', { x, y, color: k === 'oil' ? 0x2a2630 : 0x4d97ff });
    }
    snapTerrain();
    if (ign) oilBlast(ign[0], ign[1]);
  }
}
