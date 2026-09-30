import { COMBAT } from '../data/realtime.js';
import { S_WATER } from '../data/terrain.js';
import { damage, push } from '../core/combat.js';
import { fireAt, freezeAt, shock } from '../core/elements.js';
import { canSee } from '../core/fov.js';
import { emitStatus, snapTerrain } from '../core/snap.js';
import { posOf, segClear } from '../core/space.js';
import { G, I, emit, entsAt, isP, log } from '../core/state.js';
import { rand } from '../util/rng.js';
import { jo } from '../util/text.js';
import { ACTS, foeTarget, startAct } from './action.js';
import { angTo, dist, faceAng, walk } from './body.js';
import { keepRange, meleeBrain } from './foes.js';
import { spawnProj } from './projectile.js';
import { cellsAlong, plus, square3 } from './shapes.js';
import { steerAway } from './steer.js';

/* ================= 예고를 거는 적: 조준선 · 바닥 주문 · 돌진 띠 (docs/설계_실시간_전환.md §5) ================= */
const sgn8 = (v) => (Math.abs(v) < 0.38 ? 0 : Math.sign(v));

/** 해골 궁수: 거리를 두고 0.8초 조준(선이 바닥에 뜬다) 뒤 그 방향으로 쏜다. 붙으면 도망 */
export function archerBrain(e) {
  const t = foeTarget(e); if (!t) return null;
  const d = dist(e, t);
  if (d < 2) return steerAway(e, t.px, t.py);
  if (e.cd <= 0 && d <= COMBAT.aimRange && canSee(e, t)) {
    const ang = angTo(e, t); faceAng(e, ang);
    startAct(e, 'aim', { wind: COMBAT.tele.aim, ang, target: t.id, tele: { kind: 'line', cells: cellsAlong(e.px, e.py, ang, COMBAT.arrow.range), mark: [t.x, t.y] }, fx: 'aim' });
    return null;
  }
  return keepRange(e, t);
}
ACTS.aim = {
  resolve(u, a) {
    const [x, y] = posOf(u);
    spawnProj({ owner: u.id, team: u.team, x, y, ang: a.ang, speed: COMBAT.arrow.speed, range: COMBAT.arrow.range, look: 'arrow',
      onHit: (t) => {
        if (isP(t) && G.ps && G.ps.reflect && rand() * 100 < G.ps.reflect) { log('화살을 되돌렸다.', 'syn'); damage(u, u.atk, 'hit', { label: '반사', src: t }); return; } // 반사 목걸이
        damage(t, u.atk, 'hit', { dx: sgn8(Math.cos(a.ang)), dy: sgn8(Math.sin(a.ang)), src: u });
      } });
  },
};

/** 마법사: 거리를 두고, 등불지기 발밑을 중심으로 1.2초 동안 바닥 예고가 차오른 뒤 원소 주문이 떨어진다 */
export function mageBrain(e) {
  const t = foeTarget(e); if (!t) return null;
  const d = dist(e, t);
  if (e.cd <= 0 && d <= COMBAT.castRange && canSee(e, t)) {
    faceAng(e, angTo(e, t));
    const cells = e.boss ? square3(t.x, t.y) : plus(t.x, t.y);
    startAct(e, 'cast', { wind: COMBAT.tele.cast, cells, elem: e.elem, cd: COMBAT.recast * (e.boss ? 0.8 : 1), tele: { kind: 'cells', cells, elem: e.elem }, fx: 'cast' });
    log(`${jo(e.name, '이가')} 주문을 외운다.`, 'bad');
    return null;
  }
  return keepRange(e, t);
}
ACTS.cast = { resolve(u, a) { castLand(u, a.cells); } };

/** 주문이 떨어진다: 원소 규칙 그대로(번개는 물을 타고 번지고, 불은 기름을 터뜨리고, 냉기는 젖은 것을 얼린다) */
export function castLand(e, cells) {
  emit('release', { id: e.id });
  if (e.elem === 'bolt') {
    emit('skybolt', { tiles: cells });
    const hitSet = new Set();
    for (const [x, y] of cells) {
      const i = I(x, y), here = entsAt(x, y);
      if (G.surf[i] === S_WATER || here.some((c) => c.st.wet)) shock(x, y, 4, { hitSet });
      else for (const c of here) if (!hitSet.has(c.id)) { hitSet.add(c.id); damage(c, 4, 'shock'); }
    }
  } else if (e.elem === 'fire') {
    emit('meteor', { tiles: cells });
    for (const [x, y] of cells) fireAt(x, y, 4);
  } else {
    emit('frostfall', { tiles: cells });
    const o = {}; for (const [x, y] of cells) freezeAt(x, y, 2, o); if (o.changed) snapTerrain();
  }
  if (e.boss) e.elem = { bolt: 'fire', fire: 'frost', frost: 'bolt' }[e.elem];
}

/** 철갑 멧돼지: 곧게 트인 곳에서 1초 동안 발을 구르며 돌진 띠를 보인 뒤, 그 방향으로 끝까지 달린다 */
export function chargerBrain(e) {
  const t = foeTarget(e); if (!t) return null;
  const d = dist(e, t), [ex, ey] = posOf(e), [tx, ty] = posOf(t);
  if (e.cd <= 0 && d >= 2 && d <= (e.boss ? 7 : 6) && !(e.st.frac > 0) && canSee(e, t) && segClear(ex, ey, tx, ty, 0.25)) {
    const ang = angTo(e, t); faceAng(e, ang);
    startAct(e, 'charge', { wind: COMBAT.tele.charge, ang, cd: e.boss ? COMBAT.bossChargeCd : COMBAT.chargeCd, tele: { kind: 'band', cells: cellsAlong(ex, ey, ang, COMBAT.dashMax) }, fx: 'windup' });
    log(`${jo(e.name, '이가')} 발을 구른다.`, 'bad');
    return null;
  }
  return meleeBrain(e);
}
ACTS.charge = {
  resolve(u, a) { a.left = COMBAT.dashMax; emit('dash', { id: u.id }); },
  /** 돌진: 몸에 부딪히면 들이받고, 벽에 부딪히면 머리를 박고 기절한다 */
  update(u, a, dt) {
    const r = walk(u, Math.cos(a.ang), Math.sin(a.ang), dt, { speed: COMBAT.dashSpeed, keepFace: true });
    a.left -= r.moved;
    const dx = sgn8(Math.cos(a.ang)), dy = sgn8(Math.sin(a.ang));
    if (r.body && r.body.alive && !r.body.npc) {
      const v = r.body; emit('lunge', { id: u.id, dx: Math.cos(a.ang), dy: Math.sin(a.ang) });
      damage(v, u.boss ? 11 : 8, 'charge', { dx, dy, label: '돌진!', big: true, src: u }); emit('shake', { a: 0.55 });
      if (!isP(v) && G.vis[I(v.x, v.y)]) log(`${jo(u.name, '이가')} ${jo(v.name, '을를')} 들이받았다.`, 'syn');
      if (v.alive) push(v, dx, dy, 1);
      return true;
    }
    if (r.wall && r.moved < COMBAT.dashSpeed * dt * 0.5) {
      emit('bump', { id: u.id, dx, dy });
      damage(u, 5, 'wall', { dx, dy, label: '벽 쾅!', big: true }); emit('shake', { a: 0.6 });
      if (u.alive) { u.st.stun = Math.max(u.st.stun, u.boss ? 3 : 2); emitStatus(u); log('벽에 머리를 박고 기절했다.', 'syn'); }
      return true;
    }
    return a.left <= 0;
  },
};

