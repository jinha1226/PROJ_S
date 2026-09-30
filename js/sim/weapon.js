import { RAPIER_BEAT, WSHAPE } from '../data/realtime.js';
import { curW, push, weaponHit } from '../core/combat.js';
import { los } from '../core/fov.js';
import { posOf } from '../core/space.js';
import { G, emit, isFoe, seesEnt } from '../core/state.js';
import { angTo, dist, faceAng, walk } from './body.js';
import { spawnProj } from './projectile.js';
import { inArc, inLine } from './shapes.js';

/* ================= 등불지기 자동 공격: 무기 박자마다, 닿는 범위의 보이는 적을 무기 모양대로 (docs/설계_실시간_전환.md §4) ================= */
const sgn8 = (v) => (Math.abs(v) < 0.38 ? 0 : Math.sign(v)); // 각도 → 옛 8방향(밀치기·연출)

/** 지금 무기의 모양 */
export const shapeOf = (w = curW()) => WSHAPE[w.shape] || WSHAPE.front;
export const beatOfWeapon = (w = curW()) => (w.retreat ? RAPIER_BEAT : shapeOf(w).beat);

/** 이 적을 지금 무기로 노릴 수 있는가: 근접은 닿는 거리, 원거리는 사거리 안의 트인 적 */
export function canReach(t, w = curW()) {
  if (!t || !t.alive || !isFoe(t) || t.npc || !seesEnt(t)) return false;
  const p = G.player, sh = shapeOf(w), d = dist(p, t);
  if (sh.kind === 'proj') return d <= sh.range && los(p.x, p.y, t.x, t.y);
  return d <= sh.reach + 0.15;
}

/** 칠 적: 노린 적이 닿으면 그 적, 아니면 가장 가까운 적 */
export function swingTarget() {
  const p = G.player, near = G.ents.filter((e) => canReach(e)).sort((a, b) => dist(a, p) - dist(b, p));
  return near.find((e) => e.id === G.target) || near[0] || null;
}

/** 한 틱: 박자가 돌아오고 칠 적이 있으면 친다. 쌍단검 두 번째 찌르기도 여기서 */
export function heroAttack(dt) {
  const p = G.player;
  if (G.twin) { G.twin.t -= dt; if (G.twin.t <= 0) { const t = G.ents.find((e) => e.id === G.twin.id); G.twin = null; if (t && t.alive && dist(p, t) <= shapeOf().reach + 0.3) weaponHit(t, null, { extra: true }); } }
  G.swingT = Math.max(0, (G.swingT || 0) - dt);
  if (G.swingT > 0 || !p.alive || G.over || p.st.frozen > 0 || p.st.stun > 0) return;
  const t = swingTarget(); if (!t) return;
  swing(t);
  G.swingT = beatOfWeapon();
}

/** 무기 한 번: 모양 안의 적을 친다 */
export function swing(t) {
  const p = G.player, w = curW(), sh = shapeOf(w), [px, py] = posOf(p), ang = angTo(p, t), dx = sgn8(Math.cos(ang)), dy = sgn8(Math.sin(ang));
  faceAng(p, ang);
  emit('face', { id: 0, dx: Math.cos(ang), dy: Math.sin(ang) });
  const foes = () => G.ents.filter((e) => e.alive && isFoe(e) && !e.npc && !e.hidden);
  if (sh.kind === 'proj') {
    const near = dist(p, t) < 1.3;
    emit('swing', { id: 0, dx, dy, form: w.form, tx: t.x, ty: t.y, ranged: true });
    spawnProj({ owner: 0, team: 'party', x: px, y: py, ang, speed: sh.speed, range: sh.range, pierce: !!sh.pierce, back: !!sh.back, look: sh.look,
      onHit: (e, pr) => { weaponHit(e, null, { near, noPush: !!sh.knock, back: pr.returning }); if (sh.knock && e.alive) push(e, sgn8(Math.cos(pr.ang)), sgn8(Math.sin(pr.ang)), sh.knock); } });
    return;
  }
  if (sh.kind === 'line') {
    emit('swing', { id: 0, dx, dy, form: w.form, tx: t.x, ty: t.y, shape: 'line' });
    for (const e of foes()) if (inLine(px, py, ang, sh.reach, sh.width, e)) weaponHit(e, null, {});
    return;
  }
  const hits = sh.one ? [t] : foes().filter((e) => inArc(px, py, ang, sh.half, sh.reach, e));
  emit('swing', { id: 0, dx, dy, form: w.form, tx: t.x, ty: t.y, shape: sh.half >= 90 ? 'sweep' : sh.half >= 60 ? 'fan' : undefined });
  if (sh.half >= 90) emit('ring', { x: p.x, y: p.y, elem: 'push' });
  for (const e of hits) weaponHit(e, null, { noPush: !!sh.knock });
  if (sh.twice && t.alive) G.twin = { id: t.id, t: sh.twice };
  if (sh.knock && t.alive) { emit('shove', { x: t.x, y: t.y, dx, dy }); push(t, dx, dy, sh.knock + (G.ps.fracPush ? 1 : 0)); }
  if (w.retreat && t.alive) walk(p, -Math.cos(ang), -Math.sin(ang), 0.1, { keepFace: true }); // 레이피어: 치고 반 걸음 물러난다
}
