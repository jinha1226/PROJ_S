import { C_STEAM, S_WATER, T_DOOR, T_WALL } from '../data/terrain.js';
import { D4, D8, cheb, sgn } from '../util/grid.js';
import { rand, ri, shuffle } from '../util/rng.js';
import { jo } from '../util/text.js';
import { damage, faceTo, heal, moveEnt, onEnter, openDoor, push, reveal, stepEnt } from './combat.js';
import { fireAt, freezeAt, shock } from './elements.js';
import { canSee, los } from './fov.js';
import { mkEnemy } from './mapgen.js';
import { emitStatus, snapTerrain } from './snap.js';
import { G, I, TL, emit, entAt, inb, isFoe, isP, log, standable } from './state.js';
import { dirFrom, synergy } from './stones.js';

/* ================= 적 AI ================= */
export const plus = (x, y) => [[x, y], ...D4.map(([dx, dy]) => [x + dx, y + dy])].filter(([a, b]) => inb(a, b) && G.tile[I(a, b)] !== T_WALL);

export function atkGate() { if (TL.cur < G.tickMoveEnd) TL.cur = G.tickMoveEnd; }

export function wakeAround(e) { for (const o of G.ents) if (isFoe(o) && o.alive && !o.awake && cheb(o.x, o.y, e.x, e.y) <= 4) { o.awake = true; emit('alert', { id: o.id }); } }

export function enemyAct(e, dm) {
  const P = G.player;
  if (e.st.frozen > 0 || e.st.stun > 0) { if (e.st.frozen > 0) e.st.frozen--; if (e.st.stun > 0) e.st.stun--; emitStatus(e); return; }
  if (e.st.frac > 0) { e.fracSkip = !e.fracSkip; if (e.fracSkip) return; }
  const d = cheb(e.x, e.y, P.x, P.y), sees = canSee(e, P);
  if (!e.awake) { if (sees && G.ps && G.ps.silence && G.waited && rand() < 0.5) return; // 고요 목걸이: 대기하면 지나칠 수 있다
    if (sees) { e.awake = true; emit('alert', { id: e.id }); wakeAround(e); } return; }
  if (e.st.fear > 0) { e.st.fear--; emitStatus(e); flee(e, dm); return; }
  if (e.boss === 'chief') { actChief(e, dm, d, sees); return; }
  if (e.type === 'goblin' || e.type === 'rat') { if (d === 1) return enemyMelee(e, P); stepToward(e, dm); }
  else if (e.type === 'leech') actLeech(e, dm, d);
  else if (e.type === 'shaman') actShaman(e, dm, d);
  else if (e.type === 'archer') actArcher(e, dm, d, sees);
  else if (e.type === 'mage') actMage(e, dm, d, sees);
  else if (e.type === 'charger') actCharger(e, dm, d, sees);
}

export function stepToward(e, dm, bias) {
  const here = dm[I(e.x, e.y)]; let best = null, bs = Infinity;
  for (const [dx, dy] of D8) {
    const nx = e.x + dx, ny = e.y + dy; if (!inb(nx, ny)) continue;
    const j = I(nx, ny); if (G.tile[j] === T_WALL || entAt(nx, ny)) continue;
    let s = dm[j]; if (s > here) continue;
    if (s === here) s += 0.8;
    if (G.fire[j]) s += 6; if (G.cloud[j] === C_STEAM) s += 2;
    if (bias) s += bias(nx, ny);
    s += rand() * 0.3;
    if (s < bs) { bs = s; best = [dx, dy]; }
  }
  if (!best) return false;
  const nx = e.x + best[0], ny = e.y + best[1];
  if (G.tile[I(nx, ny)] === T_DOOR) { openDoor(nx, ny); return true; }
  stepEnt(e, best[0], best[1]); return true;
}

export function flee(e, dm) {
  let best = null, bv = dm[I(e.x, e.y)];
  for (const [dx, dy] of D8) { const nx = e.x + dx, ny = e.y + dy; if (!standable(nx, ny) || entAt(nx, ny)) continue; const v = dm[I(nx, ny)] - (G.fire[I(nx, ny)] ? 5 : 0); if (v > bv) { bv = v; best = [dx, dy]; } }
  if (best) stepEnt(e, best[0], best[1]);
}

export function reposition(e) {
  const P = G.player;
  const score = (x, y) => { const d = cheb(x, y, P.x, P.y); let s = -Math.abs(d - 4) * 2; if (los(x, y, P.x, P.y)) s += 2.5; if (d <= 1) s -= 8; if (G.fire[I(x, y)]) s -= 10; return s; };
  let best = null, bs = score(e.x, e.y) + 0.2;
  for (const [dx, dy] of D8) { const nx = e.x + dx, ny = e.y + dy; if (!standable(nx, ny) || entAt(nx, ny)) continue; const s = score(nx, ny) + rand() * 0.2; if (s > bs) { bs = s; best = [dx, dy]; } }
  if (!best) return false;
  stepEnt(e, best[0], best[1]); return true;
}

export function enemyMelee(e, t) {
  atkGate(); reveal(e); faceTo(e, t); e.didAttack = true;
  const dx = sgn(t.x - e.x), dy = sgn(t.y - e.y);
  emit('lunge', { id: e.id, dx, dy }); TL.wait(150); // 물러났다 내딛는 무거운 동작(entity-view lunge)
  damage(t, Math.max(1, e.atk + ri(-1, e.type === 'goblin' ? 0 : 1)), 'hit', { dx, dy });
  if (e.type === 'leech' && t.alive) { t.st.bleed = Math.max(t.st.bleed || 0, 2); emitStatus(t); } // 피를 빤다
  if (e.poison && t.alive && !t.st.immune && rand() < 0.6) { t.st.poison = Math.max(t.st.poison, 4); emitStatus(t); if (isP(t)) log('독칼에 베였다 — 중독! (불 조심)', 'bad'); }
  TL.wait(110);
}

/** 거머리: 물속으로만 다가가고, 물속에서는 보이지 않는다. 땅 위에서는 그냥 기어 온다 */
export function actLeech(e, dm, d) {
  const P = G.player, wet = (x, y) => G.surf[I(x, y)] === S_WATER;
  if (d === 1) { enemyMelee(e, P); return; }
  if (!wet(e.x, e.y)) { stepToward(e, dm); }
  else {
    let best = null, bs = dm[I(e.x, e.y)];
    for (const [dx, dy] of D8) { const nx = e.x + dx, ny = e.y + dy; if (!inb(nx, ny) || !wet(nx, ny) || entAt(nx, ny)) continue; const v = dm[I(nx, ny)]; if (v < bs) { bs = v; best = [dx, dy]; } }
    if (best) stepEnt(e, best[0], best[1]);
  }
  const hide = wet(e.x, e.y) && cheb(e.x, e.y, P.x, P.y) > 1;
  if (hide && !e.hidden) { e.hidden = true; emit('move', { id: e.id, x: e.x, y: e.y, dur: 1, hop: 0, kind: 'step', seen: 0 }); }
}

/** 고블린 주술사: 두 턴마다 가장 다친 동료(4칸 안)의 HP 4를 채운다. 붙으면 물러나고, 멀면 다가온다 */
export function actShaman(e, dm, d) {
  const P = G.player; e.healCd = (e.healCd || 0) - 1;
  const hurt = G.ents.filter((o) => o.alive && isFoe(o) && o !== e && o.hp < o.max && cheb(o.x, o.y, e.x, e.y) <= 4).sort((a, b) => a.hp / a.max - b.hp / b.max)[0];
  if (hurt && e.healCd <= 0) {
    atkGate(); faceTo(e, hurt); emit('lunge', { id: e.id, dx: 0, dy: 0, amt: 0 }); TL.wait(90);
    heal(hurt, 4); e.healCd = 2;
    if (G.vis[I(e.x, e.y)]) log(`${jo(e.name, '이가')} ${jo(hurt.name, '을를')} 치유한다.`, 'bad');
    return;
  }
  if (d === 1 && rand() < 0.5) { enemyMelee(e, P); return; }
  if (d <= 2) { flee(e, dm); return; }
  if (d > 4) stepToward(e, dm);
}

export function summonFoes(e, type, n) {
  let c = 0;
  for (const [dx, dy] of shuffle(D8.slice())) {
    if (c >= n) break; const x = e.x + dx, y = e.y + dy;
    if (!standable(x, y) || entAt(x, y)) continue;
    const m = mkEnemy(type, x, y, G.theme); m.awake = true; G.ents.push(m); c++;
    emit('spawn', { e: { ...m, st: { ...m.st } }, seen: G.vis[I(x, y)] ? 1 : 0 });
  }
  if (c) log(`${e.name}이(가) 부하를 불렀다!`, 'bad');
}

export function actChief(e, dm, d, sees) {
  const P = G.player;
  if (e.hornOn) { e.hornOn = false; e.horn = 6; atkGate(); emit('horn', { id: e.id }); TL.wait(150); summonFoes(e, 'goblin', 2); return; }
  if (e.horn > 0) e.horn--;
  if (sees && e.horn <= 0) { e.hornOn = true; emit('windup', { id: e.id }); log('족장이 뿔나팔을 든다 — 다음 턴에 부하가 온다!', 'bad'); return; }
  if (d === 1) return enemyMelee(e, P);
  stepToward(e, dm);
}

export const square3 = (x, y) => { const o = []; for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) { const a = x + dx, b = y + dy; if (inb(a, b) && G.tile[I(a, b)] !== T_WALL) o.push([a, b]); } return o; };

export function actArcher(e, dm, d, sees) {
  const P = G.player;
  if (e.aim) {
    e.aim = false;
    if (sees) { atkGate(); faceTo(e, P); const dur = 70 + d * 40; emit('proj', { kind: 'arrow', from: [e.x, e.y], to: [P.x, P.y], dur }); TL.wait(dur);
      if (G.ps && G.ps.reflect && rand() * 100 < G.ps.reflect) { emit('proj', { kind: 'arrow', from: [P.x, P.y], to: [e.x, e.y], dur }); TL.wait(dur); log('화살을 되돌렸다!', 'syn'); damage(e, e.atk, 'hit', { label: '반사', src: P }); TL.wait(90); return; } // 반사 목걸이
      damage(P, e.atk, 'hit', { dx: sgn(P.x - e.x), dy: sgn(P.y - e.y) }); TL.wait(90); return; }
    log('궁수가 과녁을 놓쳤다', 'info');
  }
  if (d <= 2 && reposition(e)) return;
  if (d === 1) return enemyMelee(e, P);
  if (sees && d <= 7) { e.aim = true; faceTo(e, P); emit('aim', { id: e.id }); return; }
  stepToward(e, dm);
}

export function actMage(e, dm, d, sees) {
  const P = G.player;
  if (e.cast) { atkGate(); castLand(e); return; }
  if (e.cd > 0) e.cd--;
  if (e.boss) {
    if (e.blink > 0) e.blink--;
    if (d <= 1 && e.blink <= 0) {
      let best = null, bd = -1;
      for (let k = 0; k < 40; k++) { const x = e.x + ri(-6, 6), y = e.y + ri(-6, 6); if (!inb(x, y) || !standable(x, y) || entAt(x, y)) continue; const dd = cheb(x, y, P.x, P.y); if (dd >= 3 && dd <= 6 && dd > bd && los(x, y, P.x, P.y)) { bd = dd; best = [x, y]; } }
      if (best) { e.blink = 3; emit('poof', { x: e.x, y: e.y }); moveEnt(e, best[0], best[1], { dur: 1, hop: 0, kind: 'tele' }); emit('poof', { x: best[0], y: best[1] }); log(`${e.name}이(가) 순간이동했다`, 'info'); return; }
    }
    if (e.boss === 'abyss') { if (e.sum > 0) e.sum--; else if (sees) { e.sum = 7; summonFoes(e, 'archer', 2); return; } }
  }
  if (sees && d <= 6 && e.cd <= 0) {
    e.cast = { tiles: e.boss ? square3(P.x, P.y) : plus(P.x, P.y) }; faceTo(e, P);
    emit('cast', { id: e.id, elem: e.elem }); log(`${e.name}이(가) 주문을 외운다 — 붉은 칸에서 벗어나라!`, 'bad'); return;
  }
  if (d <= 2 && reposition(e)) return;
  if (d === 1) return enemyMelee(e, P);
  if (!sees || d > 6) { stepToward(e, dm); return; }
  reposition(e);
}

export function castLand(e) {
  const tiles = e.cast.tiles; e.cast = null; e.cd = e.boss ? 2 : 3;
  emit('release', { id: e.id }); TL.wait(110);
  if (e.elem === 'bolt') {
    emit('skybolt', { tiles }); TL.wait(70);
    const hitSet = new Set();
    for (const [x, y] of tiles) {
      const i = I(x, y), c = entAt(x, y);
      if (G.surf[i] === S_WATER || (c && c.st.wet)) shock(x, y, 4, { hitSet });
      else if (c && !hitSet.has(c.id)) { hitSet.add(c.id); damage(c, 4, 'shock'); }
    }
  } else if (e.elem === 'fire') {
    emit('meteor', { tiles }); TL.wait(80);
    for (const [x, y] of tiles) fireAt(x, y, 4);
  } else {
    emit('frostfall', { tiles }); TL.wait(80);
    const o = {}; for (const [x, y] of tiles) freezeAt(x, y, 2, o); if (o.changed) snapTerrain();
  }
  if (e.boss) e.elem = { bolt: 'fire', fire: 'frost', frost: 'bolt' }[e.elem];
  TL.wait(120);
}

export function chargePath(e, dx, dy) {
  const path = []; let x = e.x, y = e.y;
  for (let k = 0; k < 8; k++) { x += dx; y += dy; if (!standable(x, y)) break; path.push([x, y]); }
  return path;
}

export function clearLine(ax, ay, bx, by) { const dx = sgn(bx - ax), dy = sgn(by - ay); let x = ax + dx, y = ay + dy; while (x !== bx || y !== by) { if (!standable(x, y)) return false; x += dx; y += dy; } return true; }

export function actCharger(e, dm, d, sees) {
  const P = G.player;
  if (e.charge) { atkGate(); doCharge(e); return; }
  if (e.cd > 0) e.cd--;
  const dx = P.x - e.x, dy = P.y - e.y, aligned = dx === 0 || dy === 0 || Math.abs(dx) === Math.abs(dy);
  if (sees && aligned && d >= 2 && d <= (e.boss ? 7 : 6) && e.cd <= 0 && !e.st.frac && clearLine(e.x, e.y, P.x, P.y)) {
    e.charge = { dx: sgn(dx), dy: sgn(dy) }; faceTo(e, P);
    emit('windup', { id: e.id }); log(`${e.name}이(가) 발을 구른다 — 화살표 경로에서 비켜라!`, 'bad'); return;
  }
  if (d === 1) return enemyMelee(e, P);
  stepToward(e, dm, (x, y) => { const ax = P.x - x, ay = P.y - y; return ax === 0 || ay === 0 || Math.abs(ax) === Math.abs(ay) ? -0.6 : 0; });
}

export function doCharge(e) {
  const { dx, dy } = e.charge; e.charge = null; e.cd = e.boss ? 1 : 3;
  let steps = 0, victim = null, wall = false;
  emit('dash', { id: e.id });
  while (steps < 8) {
    const nx = e.x + dx, ny = e.y + dy;
    if (!standable(nx, ny)) { wall = true; break; }
    const o = entAt(nx, ny); if (o) { victim = o; break; }
    moveEnt(e, nx, ny, { dur: 55, hop: 0.03, kind: 'dash' }); TL.wait(50); steps++;
  }
  if (victim) {
    emit('lunge', { id: e.id, dx, dy }); TL.wait(40);
    damage(victim, e.boss ? 11 : 8, 'charge', { dx, dy, label: '돌진!', big: true }); emit('shake', { a: 0.55 });
    if (!isP(victim)) synergy(`${victim.name}을(를) 들이받았다!`, 'push');
    if (victim.alive) push(victim, dx, dy, 1);
  } else if (wall) {
    emit('bump', { id: e.id, dx, dy });
    damage(e, 5, 'wall', { dx, dy, label: '쾅! 벽 충돌', big: true }); emit('shake', { a: 0.6 });
    if (e.alive) { e.st.stun = Math.max(e.st.stun, e.boss ? 3 : 2); emitStatus(e); synergy('벽에 머리를 박았다 — 기절!', 'push'); }
  }
  onEnter(e);
  TL.wait(80);
}

export function allyAct(a, dm) {
  if (a.npc) {
    if (!a.freed || cheb(a.x, a.y, G.player.x, G.player.y) <= 1) return;
    stepToward(a, dm); return;
  }
  a.life--;
  if (a.life <= 0) { a.alive = false; emit('vanish', { id: a.id }); return; }
  let best = null, bd = 99;
  for (const e of G.ents) if (e.alive && isFoe(e) && G.vis[I(e.x, e.y)]) { const d = cheb(a.x, a.y, e.x, e.y); if (d < bd) { bd = d; best = e; } }
  if (!best) return;
  if (bd === 1) { atkGate(); faceTo(a, best); const [dx, dy] = dirFrom(a, best); emit('lunge', { id: a.id, dx, dy }); TL.wait(70); damage(best, a.atk + ri(0, 1), 'hit', { src: a, dx, dy }); TL.wait(80); return; }
  let mv = null, md = bd;
  for (const [dx, dy] of D8) { const x = a.x + dx, y = a.y + dy; if (!standable(x, y) || entAt(x, y)) continue; const d = cheb(x, y, best.x, best.y); if (d < md) { md = d; mv = [dx, dy]; } }
  if (mv) stepEnt(a, mv[0], mv[1]);
}
