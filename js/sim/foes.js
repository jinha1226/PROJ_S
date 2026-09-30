import { COMBAT } from '../data/realtime.js';
import { S_WATER } from '../data/terrain.js';
import { damage, heal, reveal } from '../core/combat.js';
import { canSee } from '../core/fov.js';
import { emitStatus } from '../core/snap.js';
import { G, I, emit, isFoe, isP, log } from '../core/state.js';
import { rand, ri } from '../util/rng.js';
import { jo } from '../util/text.js';
import { foeTarget, startAct, unitById } from './action.js';
import { ACTS } from './acts.js';
import { angTo, dist, faceAng } from './body.js';
import { spread, steerAway, steerTo } from './steer.js';

/* ================= 가까이 싸우는 적: 쫓아와 에워싸고, 힘을 모았다가 친다 (docs/설계_실시간_전환.md §5) ================= */

/** 근접: 닿으면 힘 모으기(0.35초)를 시작하고, 아니면 다가간다. 이미 닿아 있으면 박자를 기다리며 선다 */
export function meleeBrain(e) {
  const t = foeTarget(e); if (!t) return null;
  const d = dist(e, t);
  if (d <= COMBAT.reach) {
    faceAng(e, angTo(e, t));
    if (e.cd <= 0) startAct(e, 'melee', { target: t.id, wind: e.boss ? COMBAT.bossWindup : COMBAT.windup, fx: 'ready' });
    return d > COMBAT.reach * 0.8 ? steerTo(e, t.px, t.py) : null;
  }
  return spread(e, steerTo(e, t.px, t.py));
}

/** 근접 한 방: 힘 모으는 사이 닿는 거리 + 0.3 밖으로 빠졌으면 헛친다 */
ACTS.melee = {
  resolve(u, a) {
    const t = unitById(a.target); if (!t || !t.alive) return;
    const ang = angTo(u, t), dx = Math.cos(ang), dy = Math.sin(ang);
    faceAng(u, ang); emit('lunge', { id: u.id, dx, dy });
    if (dist(u, t) > COMBAT.reach + COMBAT.whiff) { u.whiffT = G.clock + 2; emit('whiff', { id: u.id, x: t.x, y: t.y }); return; } // 헛친 적은 2초 동안 빈틈(로그 특성)
    reveal(u);
    damage(t, Math.max(1, u.atk + ri(-1, u.type === 'goblin' ? 0 : 1)), 'hit', { dx: Math.sign(Math.round(dx)), dy: Math.sign(Math.round(dy)), src: u });
    if (u.type === 'leech' && t.alive) { t.st.bleed = Math.max(t.st.bleed || 0, 2); emitStatus(t); } // 피를 빤다
    if (u.poison && t.alive && !t.st.immune && rand() < 0.6) { t.st.poison = Math.max(t.st.poison, 4); emitStatus(t); if (isP(t)) log('독칼에 베여 중독됐다.', 'bad'); }
  },
};

/** 거머리: 느리게 기어 오고, 물속에 서 있으면 보이지 않는다 */
export function leechBrain(e) {
  const t = foeTarget(e), inWater = G.surf[I(e.x, e.y)] === S_WATER;
  const hide = inWater && (!t || dist(e, t) > 1.5) && !e.act;
  if (hide !== !!e.hidden) { e.hidden = hide; if (!hide) e.revealed = true; G.visDirty = true; }
  return meleeBrain(e);
}

/** 고블린 주술사: 거리를 두고, 2.5초마다 가장 다친 동료(4칸 안)의 HP 4를 채운다 */
export function shamanBrain(e) {
  const t = foeTarget(e);
  if (e.cd <= 0) {
    const hurt = G.ents.filter((o) => o.alive && isFoe(o) && o !== e && !o.npc && o.hp < o.max && dist(o, e) <= 4).sort((a, b) => a.hp / a.max - b.hp / b.max)[0];
    if (hurt) { faceAng(e, angTo(e, hurt)); startAct(e, 'heal', { wind: COMBAT.tele.heal, target: hurt.id, cd: COMBAT.healEvery, fx: 'ready' }); return null; }
  }
  return keepRange(e, t);
}
ACTS.heal = {
  resolve(u, a) {
    const t = unitById(a.target); if (!t || !t.alive) return;
    emit('lunge', { id: u.id, dx: 0, dy: 0, amt: 0 }); heal(t, 4);
    if (G.vis[I(u.x, u.y)]) log(`${jo(u.name, '이가')} ${jo(t.name, '을를')} 치유한다.`, 'bad');
  },
};

/** 거리 두기: 너무 가까우면 물러나고, 멀거나 안 보이면 다가간다 */
export function keepRange(e, t, [lo, hi] = COMBAT.keepAway) {
  if (!t) return null;
  const d = dist(e, t);
  if (d < lo) return steerAway(e, t.px, t.py);
  if (d > hi || !canSee(e, t)) return spread(e, steerTo(e, t.px, t.py));
  faceAng(e, angTo(e, t));
  return null;
}

/** 구한 주민: 등불지기를 따라온다. 갇힌 동안은 제자리 */
export function npcBrain(e) {
  if (!e.freed) return null;
  const p = G.player; if (!p || dist(e, p) <= 1.6) return null;
  return steerTo(e, p.px, p.py);
}

/** 깨어남: 잠든 적이 등불지기를 보면 깨어나 둘레 4칸을 깨운다. 고요 목걸이를 차고 제자리에 서 있으면 절반은 지나친다 */
export function wakeFoes() {
  const P = G.player; if (!P) return;
  for (const e of G.ents) {
    if (!e.alive || e.awake || !isFoe(e) || e.npc) continue;
    if (!canSee(e, P)) continue;
    if (G.ps && G.ps.silence && G.stillT > 0 && rand() < 0.5) continue;
    wake(e);
  }
}
export function wake(e) {
  if (e.awake) return;
  e.awake = true; emit('alert', { id: e.id }); G.intentsDirty = true;
  for (const o of G.ents) if (isFoe(o) && o.alive && !o.awake && !o.npc && Math.max(Math.abs(o.x - e.x), Math.abs(o.y - e.y)) <= COMBAT.wake) { o.awake = true; emit('alert', { id: o.id }); }
}
