import { PHYS } from '../data/colors.js';
import { CATS, catOf } from '../data/enemies.js';
import { CAPS, weaponOf } from '../data/gear.js';
import { MATS } from '../data/items.js';
import { S_ASH, S_ICE, S_NONE, S_WATER, T_DOOR, T_OPEN, T_STAIRS, T_WALL } from '../data/terrain.js';
import { JOBS } from '../data/town.js';
import { FORMS } from '../data/weapons.js';
import { D8, cheb, sgn } from '../util/grid.js';
import { pick, rand, ri } from '../util/rng.js';
import { jo } from '../util/text.js';
import { applyFire, fireAt } from './elements.js';
import { freePush } from './free.js';
import { dropGearFrom, gearName, openChest } from './gear.js';
import { addItem, identify, itemName } from './items.js';
import { emitSlots, emitStatus, snapTerrain } from './snap.js';
import { dist } from './space.js';
import { G, I, TL, emit, entAt, inb, isFoe, isP, itemSnap, log, standable } from './state.js';
import { addStone, dropStone, trigger, withCtx } from './stones.js';

const ELEM_OF = { fire: 'fire', burn: 'fire', blast: 'fire', shock: 'bolt', frost: 'frost', poison: 'poison' };

export function damage(e, amt, kind = 'hit', o = {}) {
  if (!e.alive || amt <= 0) return 0;
  let label = o.label || '';
  if (e.st.frozen > 0 && PHYS[kind]) { amt = Math.ceil(amt * 1.5); if (!label) label = '빙결 강타'; }
  if (isFoe(e) && !e.awake) e.awake = true;
  const src = o.src || G.curSrc;
  // 장비: 내가 맞을 때 회피·막기·방어·저항, 내가 칠 때 원소 피해
  if (isP(e) && G.ps) {
    const ps = G.ps, el = ELEM_OF[kind];
    if ((kind === 'hit' || kind === 'charge') && src && isFoe(src)) {
      const eva = Math.min(CAPS.eva, ps.eva + (G.surf[I(e.x, e.y)] === S_WATER ? ps.waterEva : 0));
      if (rand() * 100 < eva) { emit('dodge', { id: 0 }); return 0; }
      if (ps.block && rand() * 100 < ps.block) { emit('block', { id: 0 }); amt = 0; }
    }
    if (amt > 0 && PHYS[kind] && ps.def) amt = Math.max(1, amt - ps.def);
    if (amt > 0 && el && ps.res[el]) amt = Math.max(1, Math.round(amt * (1 - ps.res[el] / 100)));
    if (amt > 0 && ps.legend.has('thornPlate')) amt = Math.ceil(amt * 1.2);
  } else if (isFoe(e) && G.ps && G.ctx && G.ctx.origin !== 'enemy' && ELEM_OF[kind] && kind !== 'burn') amt += G.ps.elem[ELEM_OF[kind]];
  if (G.fc && G.fc.ambush && isFoe(e) && G.ctx && G.ctx.origin !== 'enemy') { amt = Math.ceil(amt * 1.5); G.fc.ambush = false; label = label || '기습!'; }
  if (isP(e) && e.shield > 0) { const a = Math.min(e.shield, amt); e.shield -= a; amt -= a; emit('shieldHit', { absorbed: a, left: e.shield }); }
  if (amt > 0) {
    e.hp -= amt;
    emit('hit', { id: e.id, amt, kind, dx: o.dx || 0, dy: o.dy || 0, label, big: !!o.big || amt >= 7, crit: !!o.crit });
    emit('hp', { id: e.id, hp: Math.max(0, e.hp), max: e.max });
  }
  if (o.form) e.lastForm = o.form; else if (kind !== 'bleed') e.lastForm = null;
  if (isP(e)) G.hurt = true;
  if (e.hp <= 0) { kill(e); return amt; }
  if (isP(e) && src && src !== e && isFoe(src)) { if (G.ctx) trigger('green', { src }, G.ctx); else withCtx('hurt', (ctx) => trigger('green', { src }, ctx)); }
  return amt;
}

export function kill(e) {
  const shatter = e.st.frozen > 0;
  e.alive = false; e.cast = e.charge = null; e.aim = false;
  emit('die', { id: e.id, shatter });
  if (isP(e)) { G.over = true; log('쓰러졌다…', 'bad'); emit('gameover'); return; }
  if (e.ally) return;
  if (e.npc) { log(`${jo(e.name, '을를')} 잃었다…`, 'bad'); return; }
  G.stats.kills++;
  const f = e.lastForm;
  if (f) { addLoot(FORMS[f].part, 1); emit('loot', { x: e.x, y: e.y, m: FORMS[f].part }); }
  if (e.boss) {
    G.exitOpen = true; G.tile[G.stairs] = T_STAIRS; snapTerrain();
    addLoot('마석', 1); addLoot(pick(['가죽', '뼈', '심장']), 2);
    emit('portal', { x: G.stairs % G.W, y: (G.stairs / G.W) | 0 }); emit('banner', { text: `${e.name} 격파!`, elem: 'chain' });
    log('귀환의 문이 열렸다 — 올라서서 ⬇ 버튼', 'syn');
  }
  log(`${e.name} 처치${shatter ? ' — 산산조각!' : ''}${f ? ` · ${FORMS[f].name} → ${FORMS[f].part}` : ''}`, 'good');
  if (e.st.bleed > 0 && G.ps && G.ps.legend.has('bloodFang')) {
    emit('bloodBurst', { x: e.x, y: e.y }); log('피의 송곳니 — 피가 터진다!', 'syn');
    for (const [dx, dy] of D8) { const o = entAt(e.x + dx, e.y + dy); if (o && o.alive && isFoe(o) && !CATS[catOf(o)].noBleed) { o.st.bleed += 2; emitStatus(o); } }
  }
  dropStone(e, f);
  dropGearFrom(e);
}

export function addLoot(m, n) { G.loot.mats[m] = (G.loot.mats[m] || 0) + n; }

export function freeDropSpot(x, y) {
  const ok = (a, b) => inb(a, b) && standable(a, b) && G.tile[I(a, b)] !== T_STAIRS && !G.stones.has(I(a, b)) && !G.items.has(I(a, b)) && !G.gear.has(I(a, b));
  if (ok(x, y)) return [x, y];
  for (let r = 1; r <= 2; r++) for (let dy = -r; dy <= r; dy++) for (let dx = -r; dx <= r; dx++) if (ok(x + dx, y + dy)) return [x + dx, y + dy];
  return null;
}

export function heal(e, n) { const v = Math.min(n, e.max - e.hp); if (v <= 0) return; e.hp += v; emit('heal', { id: e.id, amt: v }); emit('hp', { id: e.id, hp: e.hp, max: e.max }); }

export function cancelIntent(e) { e.cast = null; e.charge = null; e.aim = false; }

export function faceTo(e, t) { const dx = sgn(t.x - e.x), dy = sgn(t.y - e.y); if (dx || dy) { e.face = [dx, dy]; emit('face', { id: e.id, dx, dy }); } }

export function moveEnt(e, x, y, o = {}) {
  const fx = e.x, fy = e.y; e.px = x; e.py = y; e.x = Math.round(x); e.y = Math.round(y);
  if (o.face !== false && (x !== fx || y !== fy)) e.face = [sgn(x - fx), sgn(y - fy)];
  emit('move', { id: e.id, x, y, dur: o.dur ?? 115, hop: o.hop ?? 0.16, kind: o.kind || 'step', seen: isP(e) || G.vis[I(x, y)] ? 1 : 0 });
}

export function stepEnt(e, dx, dy) {
  moveEnt(e, e.x + dx, e.y + dy);
  let n = 0;
  while (G.surf[I(e.x, e.y)] === S_ICE && n < 12 && !(isP(e) && G.ps && G.ps.noSlide)) {
    const nx = e.x + dx, ny = e.y + dy;
    if (!standable(nx, ny) || entAt(nx, ny)) break;
    TL.wait(n === 0 ? 100 : 70); moveEnt(e, nx, ny, { dur: 75, hop: 0, kind: 'slide' }); n++;
  }
  if (n) { if (isP(e)) log('얼음 위에서 미끄러졌다', 'info'); else if (G.vis[I(e.x, e.y)]) log(`${e.name}이(가) 미끄러진다`, 'info'); TL.wait(70); }
  onEnter(e);
}

export function onEnter(e) {
  if (!e.alive) return;
  const i = I(e.x, e.y);
  if (G.surf[i] === S_WATER) {
    let ch = false;
    if (e.st.burn) { e.st.burn = 0; ch = true; emit('steam', { x: e.x, y: e.y, small: true }); }
    if (e.st.wet < 3) { e.st.wet = 3; ch = true; }
    if (ch) emitStatus(e);
    emit('splash', { x: e.x, y: e.y, small: true });
  }
  if (G.fire[i] > 0) applyFire(e, 2);
  if (isP(e) && e.alive) {
    if (G.items.has(i)) {
      const k = G.items.get(i); G.items.delete(i); addItem(k); G.stats.items++;
      if (G.ps && G.ps.autoId && !G.known[k]) identify(k);
      emit('items', itemSnap()); emit('pickup', { x: e.x, y: e.y }); log(`${itemName(k)} 획득`, 'good');
    }
    if (G.stones.has(i)) {
      const id = G.stones.get(i);
      if (addStone(id)) { G.stones.delete(i); emit('stonePick', { x: e.x, y: e.y, id }); emitSlots(); }
      else log('영혼석 칸과 가방이 가득 찼다 — 가방에서 하나를 버려야 한다', 'bad');
    }
    if (G.mats.has(i)) { const m = G.mats.get(i); G.mats.delete(i); addLoot(m, 1); emit('matPick', { x: e.x, y: e.y, m }); log(`${MATS[m]} ${m} 채집`, 'good'); }
    if (G.gear.has(i)) log(`${gearName(G.gear.get(i))}이 떨어져 있다 — 줍기 버튼`, 'info');
    if (G.tile[i] === T_STAIRS) log('계단이다. ⬇ 버튼으로 내려간다.', 'info');
  }
}

export function push(e, dx, dy, n) {
  const giant = isFoe(e) && G.ps && G.ps.legend.has('giantMace');
  let k = 0, left = n + (giant ? 1 : 0);
  if (G.free) { // 원형 턴제: 실제 거리만큼 밀려나고, 벽이나 몸에 닿으면 충돌
    const r = freePush(e, dx, dy, left);
    if (r.wall) {
      emit('bump', { id: e.id, dx, dy }); TL.wait(30);
      damage(e, 4 + (isFoe(e) && G.ps ? G.ps.wallDmg : 0), 'wall', { dx, dy, label: '벽 쾅!', big: true });
      if (e.alive && !isP(e)) { e.st.stun = Math.max(e.st.stun, 1); emitStatus(e); cancelIntent(e); }
      if (giant) { emit('shake', { a: 0.3 }); for (const o of G.ents) if (o !== e && o.alive && isFoe(o) && dist(o, e) <= 1.5) damage(o, 1, 'impact', { label: '흔들림' }); }
      emit('shake', { a: 0.35 }); if (!isP(e)) G.stats.combos++;
    } else if (r.body) {
      emit('bump', { id: e.id, dx, dy }); TL.wait(30);
      damage(e, 3, 'impact', { dx, dy, label: '충돌!' }); damage(r.body, 3, 'impact', { dx, dy }); emit('shake', { a: 0.3 });
    }
    if (e.alive) onEnter(e);
    return 1;
  }
  while (left > 0 && k < 12 && e.alive) {
    const nx = e.x + dx, ny = e.y + dy;
    if (!standable(nx, ny)) {
      emit('bump', { id: e.id, dx, dy }); TL.wait(30);
      damage(e, 4 + (isFoe(e) && G.ps ? G.ps.wallDmg : 0), 'wall', { dx, dy, label: '벽 쾅!', big: true });
      if (e.alive && !isP(e)) { e.st.stun = Math.max(e.st.stun, 1); emitStatus(e); cancelIntent(e); }
      if (giant) { emit('shake', { a: 0.3 }); for (const [ax, ay] of D8) { const o = entAt(e.x + ax, e.y + ay); if (o && o !== e && o.alive && isFoe(o)) damage(o, 1, 'impact', { label: '흔들림' }); } }
      emit('shake', { a: 0.35 });
      if (!isP(e)) G.stats.combos++;
      break;
    }
    const o = entAt(nx, ny);
    if (o) {
      emit('bump', { id: e.id, dx, dy }); TL.wait(30);
      damage(e, 3, 'impact', { dx, dy, label: '충돌!' }); damage(o, 3, 'impact', { dx, dy });
      emit('shake', { a: 0.3 }); break;
    }
    moveEnt(e, nx, ny, { dur: 85, hop: 0.05, kind: 'push', face: false }); TL.wait(85); k++; left--;
    if (G.surf[I(nx, ny)] === S_ICE && left === 0) left = 1;
  }
  if (e.alive) onEnter(e);
  return k;
}

export function openDoor(x, y) { G.tile[I(x, y)] = T_OPEN; emit('door', { x, y, open: true }); snapTerrain(); }

/* ================= 주인공 행동 ================= */
export function playerMove(dx, dy) {
  const p = G.player, nx = p.x + dx, ny = p.y + dy;
  if (!inb(nx, ny)) return false;
  const t = G.tile[I(nx, ny)];
  if (t === T_WALL) return false;
  const e = entAt(nx, ny);
  if (e) {
    if (e.npc && !e.freed) { e.freed = true; faceTo(p, e); emit('free', { id: e.id }); log(`${e.name}(${JOBS[e.npcData.job].name})을 풀어 주었다 — 곁에 둔 채 계단까지 데려가자`, 'good'); return true; }
    if (e.ally) { moveEnt(e, p.x, p.y); stepEnt(p, dx, dy); return true; }
    playerMelee(e); return true;
  }
  if (G.chests.has(I(nx, ny)) && !G.chests.get(I(nx, ny)).open) { p.face = [dx, dy]; emit('face', { id: 0, dx, dy }); openChest(nx, ny); return true; }
  if (t === T_DOOR) { p.face = [dx, dy]; emit('face', { id: 0, dx, dy }); openDoor(nx, ny); log('문을 열었다', 'info'); return true; }
  stepEnt(p, dx, dy);
  return true;
}

export function playerMelee(t) { withCtx('hit', (ctx) => weaponHit(t, ctx)); }

export function playerWait() {
  emit('lunge', { id: 0, dx: 0, dy: 0, amt: 0 });
  if (G.ps && G.ps.legend.has('mistCloak')) {
    const p = G.player;
    for (const [dx, dy] of D8) {
      const x = p.x + dx, y = p.y + dy; if (!standable(x, y)) continue; const i = I(x, y);
      if (G.surf[i] === S_NONE || G.surf[i] === S_ASH) G.surf[i] = S_WATER;
      const c = entAt(x, y); if (c && isFoe(c)) { c.st.wet = Math.max(c.st.wet, 3); c.st.burn = 0; emitStatus(c); }
    }
    snapTerrain(); emit('splash', { x: p.x, y: p.y });
  }
  withCtx('wait', (ctx) => trigger('purple', {}, ctx)); return true;
}
/** 창: 2칸 떨어진 적을 직선으로 친다(사이가 비어야 함) */
export function canReach(x, y) {
  const p = G.player; if (!G.ps || G.ps.reach < 2) return false;
  const dx = x - p.x, dy = y - p.y; if (Math.max(Math.abs(dx), Math.abs(dy)) !== 2 || !(dx === 0 || dy === 0 || Math.abs(dx) === Math.abs(dy))) return false;
  const mx = p.x + sgn(dx), my = p.y + sgn(dy); return standable(mx, my) && !entAt(mx, my);
}

/* ---------- 무기 공격: 형태 → 부상, 약점, 빨강 발동 ---------- */
export function weaponHit(t, ctx, o = {}) {
  if (!t || !t.alive) return;
  const p = G.player, w = weaponOf(G.eq.weapon), f = w.form, dx = sgn(t.x - p.x), dy = sgn(t.y - p.y), ps = G.ps;
  if (dx || dy) p.face = [dx, dy];
  emit('swing', { id: 0, dx, dy, form: f, tx: t.x, ty: t.y, extra: !!o.extra, counter: !!o.counter });
  TL.wait(o.extra ? 60 : 80);
  if (ps.acc < 0 && rand() * 100 < -ps.acc) { emit('miss', { x: t.x, y: t.y }); log('빗나갔다', 'info'); TL.wait(90); return; }
  const cat = catOf(t), C = CATS[cat], weak = C.weak === f;
  let dmg = ri(w.dmg[0], w.dmg[1]) + ps.dmg + (t.st.wet > 0 ? ps.wetDmg : 0), label = o.counter ? '반격' : o.extra ? '추가 타격' : '', crit = false;
  if (weak) {
    dmg = Math.ceil(dmg * 1.5) + ps.weakDmg;
    if (!G.weakKnown[cat]) { G.weakKnown[cat] = true; emit('weakReveal', { id: t.id, form: f }); log(`약점 발견 — ${C.name}은(는) ${FORMS[f].name}에 약하다!`, 'syn'); }
    label = label || '약점!';
  }
  if (f === 'pierce' && t.st.vital > 0) { crit = true; dmg = Math.ceil(dmg * (weak ? 2.5 : 2)); t.st.vital = 0; label = '급소!'; }
  else if (f === 'pierce' && ps.crit && rand() * 100 < ps.crit) { crit = true; dmg = Math.ceil(dmg * (weak ? 2.5 : 2)); label = '급소!'; }
  damage(t, dmg, 'hit', { dx, dy, label, big: crit || weak, form: f, crit });
  if (t.alive) {
    if (f === 'slash' && !C.noBleed) t.st.bleed += (weak ? 5 : 3) + ps.bleed;
    if (f === 'blunt') { t.st.frac = Math.max(t.st.frac, weak ? 5 : 3); if (t.charge) { t.charge = null; log(`${t.name}의 다리가 부러져 돌진이 끊겼다`, 'good'); } }
    if (f === 'pierce' && !crit) t.st.vital = 1;
    emitStatus(t);
    if (f === 'blunt' && ps.fracPush) push(t, dx, dy, 1);
    if (ps.torchFire && t.alive && cheb(p.x, p.y, t.x, t.y) === 1) fireAt(t.x, t.y, ps.torchFire);
  }
  trigger('red', { target: t }, ctx);
  TL.wait(90);
}

export function closeDoor(x, y) { G.tile[I(x, y)] = T_DOOR; emit('door', { x, y, open: false }); snapTerrain(); log('문을 닫았다 — 시야가 끊긴다', 'info'); return true; }

/** 층을 시작할 때 보호막(뼈 흉갑 같은 장비) */
export const armorShield = () => (G.ps ? G.ps.floorShield : 0);
