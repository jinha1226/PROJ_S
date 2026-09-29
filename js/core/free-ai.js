import { FREE } from '../data/free.js';
import { ri } from '../util/rng.js';
import { atkGate, castLand, enemyMelee, summonFoes, wakeAround } from './ai.js';
import { damage, faceTo, onEnter, push } from './combat.js';
import { canSee, los } from './fov.js';
import { walkPath } from './free.js';
import { emitStatus } from './snap.js';
import { bandTiles, costMap, dist, distXY, moveRange, pathPoints, posOf, rad, segClear, setPos, sweep, tilesInCircle } from './space.js';
import { G, I, TL, emit, isFoe, log } from './state.js';
import { synergy } from './stones.js';

/* ================= 원형 턴제 적 AI: 이동 범위 안 후보 칸을 평가해서 걷고, 행동 하나 ================= */
function candidates(e, budget) {
  const cm = costMap(e, budget), out = [];
  const [ex, ey] = posOf(e); out.push({ x: ex, y: ey, c: 0, stay: true });
  for (let i = 0; i < cm.cost.length; i++) if (isFinite(cm.cost[i]) && cm.cost[i] > 0) out.push({ x: i % G.W, y: (i / G.W) | 0, c: cm.cost[i] });
  return { cm, list: out };
}
function hazard(x, y) { const i = I(Math.round(x), Math.round(y)); return (G.fire[i] ? 30 : 0) + (G.cloud[i] === 1 ? 6 : 0); }
function goTo(e, cm, spot) {
  if (!spot || spot.stay) return;
  const path = pathPoints(e, cm, spot.x, spot.y); if (!path) return;
  emit('focus', { x: spot.x, y: spot.y });
  walkPath(e, path.pts);
}
const inReach = (e, t) => dist(e, t) <= FREE.reach;

export function freeEnemyAct(e) {
  const P = G.player;
  if (e.st.frozen > 0 || e.st.stun > 0) { if (e.st.frozen > 0) e.st.frozen--; if (e.st.stun > 0) e.st.stun--; emitStatus(e); return; }
  const sees = canSee(e, P);
  if (!e.awake) { if (sees) { e.awake = true; emit('alert', { id: e.id }); wakeAround(e); } return; }
  const [ex, ey] = posOf(e); emit('focus', { x: ex, y: ey }); TL.wait(160);
  if (e.st.fear > 0) { e.st.fear--; emitStatus(e); const { cm, list } = candidates(e, moveRange(e)); goTo(e, cm, best(list, (s) => distXY(s.x, s.y, ...posOf(P)) * 3 - hazard(s.x, s.y))); return; }
  // 걸어 둔 예고부터
  if (e.cast) { atkGate(); castLand(e); reposition(e, 3, 5); return; }
  if (e.charge) { atkGate(); freeCharge(e); return; }
  if (e.aim) {
    e.aim = false;
    if (sees && dist(e, P) <= FREE.archerRange) { atkGate(); faceTo(e, P); const d = dist(e, P), dur = 70 + d * 40; emit('proj', { kind: 'arrow', from: posOf(e), to: posOf(P), dur }); TL.wait(dur); damage(P, e.atk, 'hit', { dx: Math.sign(P.x - e.x), dy: Math.sign(P.y - e.y) }); TL.wait(90); reposition(e, 4, 6); return; }
    log('궁수가 과녁을 놓쳤다', 'info');
  }
  if (e.boss === 'chief' && e.hornOn) { e.hornOn = false; e.horn = 6; atkGate(); emit('horn', { id: e.id }); TL.wait(150); summonFoes(e, 'goblin', 2); return; }
  if (e.type === 'archer') { reposition(e, 4, 6); if (canSee(e, P) && dist(e, P) <= FREE.archerRange) { e.aim = true; faceTo(e, P); emit('aim', { id: e.id }); } else if (inReach(e, P)) enemyMelee(e, P); return; }
  if (e.type === 'mage') {
    if (e.boss === 'abyss') { if (e.sum > 0) e.sum--; else if (sees) { e.sum = 7; summonFoes(e, 'archer', 2); return; } }
    reposition(e, 3, 5);
    if (e.cd > 0) e.cd--;
    if (canSee(e, P) && dist(e, P) <= 6 && e.cd <= 0) {
      const [px, py] = posOf(P), r = e.boss ? FREE.circle.square : FREE.circle.plus + 0.3;
      e.cast = { tiles: tilesInCircle(px, py, r), cx: px, cy: py, r }; faceTo(e, P);
      emit('cast', { id: e.id, elem: e.elem }); log(`${e.name}이(가) 주문을 외운다 — 붉은 원에서 벗어나라!`, 'bad');
    } else if (inReach(e, P)) enemyMelee(e, P);
    return;
  }
  if (e.type === 'charger') {
    if (e.cd > 0) e.cd--;
    if (inReach(e, P)) { enemyMelee(e, P); return; }
    const { cm, list } = candidates(e, moveRange(e)), [px, py] = posOf(P);
    const spot = best(list, (s) => { const d = distXY(s.x, s.y, px, py), line = d >= 2 && d <= 7 && segClear(s.x, s.y, px, py, rad(e) * 0.8) && los(Math.round(s.x), Math.round(s.y), P.x, P.y); return (line && e.cd <= 0 ? 60 : 0) - d * 2 - s.c * 0.5 - hazard(s.x, s.y); });
    goTo(e, cm, spot);
    const [cx, cy] = posOf(e), d = distXY(cx, cy, px, py);
    if (e.cd <= 0 && !e.st.frac && d >= 2 && d <= 7 && canSee(e, P) && segClear(cx, cy, px, py, rad(e) * 0.8)) {
      const ux = (px - cx) / d, uy = (py - cy) / d, band = bandTiles(cx, cy, ux, uy, FREE.chargeMax);
      e.charge = { dx: Math.sign(Math.round(ux)), dy: Math.sign(Math.round(uy)), ux, uy, len: band.len }; faceTo(e, P);
      emit('windup', { id: e.id }); log(`${e.name}이(가) 발을 구른다 — 붉은 띠에서 비켜라!`, 'bad');
    } else if (inReach(e, P)) enemyMelee(e, P);
    return;
  }
  // 무리(고블린·족장): 둘러싸서 친다
  if (e.boss === 'chief') { if (e.horn > 0) e.horn--; if (sees && e.horn <= 0) { e.hornOn = true; emit('windup', { id: e.id }); log('족장이 뿔나팔을 든다 — 다음 턴에 부하가 온다!', 'bad'); return; } }
  melee(e);
}
function best(list, score) { let b = null, bs = -Infinity; for (const s of list) { const v = score(s) + Math.random() * 0.01; if (v > bs) { bs = v; b = s; } } return b; }
/** 근접형: 공격 가능한 자리 중 동료와 겹치지 않게(둘러싸기), 안 되면 다가간다 */
function melee(e) {
  const P = G.player, [px, py] = posOf(P);
  if (!inReach(e, P)) {
    const { cm, list } = candidates(e, moveRange(e));
    const mates = G.ents.filter((o) => o !== e && o.alive && isFoe(o) && dist(o, P) <= FREE.reach + 0.3).map((o) => Math.atan2(o.py - py, o.px - px));
    const spot = best(list, (s) => {
      const d = distXY(s.x, s.y, px, py); let v = d <= FREE.reach - 0.1 ? 100 : -d * 6;
      const a = Math.atan2(s.y - py, s.x - px); for (const m of mates) { let da = Math.abs(a - m); if (da > Math.PI) da = 2 * Math.PI - da; v += Math.min(da, 1.6) * 6; }
      return v - s.c - hazard(s.x, s.y);
    });
    goTo(e, cm, spot);
  }
  if (e.alive && inReach(e, P)) enemyMelee(e, P);
}
/** 거리 유지형(궁수·마법사): lo~hi m, 시야가 트인 곳 */
function reposition(e, lo, hi) {
  const P = G.player, [px, py] = posOf(P), { cm, list } = candidates(e, moveRange(e));
  const spot = best(list, (s) => { const d = distXY(s.x, s.y, px, py); let v = -Math.max(0, lo - d) * 12 - Math.max(0, d - hi) * 6; if (los(Math.round(s.x), Math.round(s.y), P.x, P.y)) v += 20; if (d <= FREE.reach) v -= 30; return v - s.c * 0.3 - hazard(s.x, s.y); });
  goTo(e, cm, spot);
}
/** 돌진: 예고한 방향으로 끝까지. 몸에 닿으면 들이받고, 벽이면 기절 */
function freeCharge(e) {
  const c = e.charge; e.charge = null; e.cd = e.boss ? 1 : 3;
  emit('dash', { id: e.id });
  const r = sweep(e, c.ux * FREE.chargeMax, c.uy * FREE.chargeMax, { stopOnHit: true });
  const [sx, sy] = posOf(e), d = distXY(sx, sy, r.x, r.y);
  setPos(e, r.x, r.y); e.px = sx; e.py = sy; emit('move', { id: e.id, x: r.x, y: r.y, dur: 60 + d * 55, hop: 0.03, kind: 'dash', seen: G.vis[I(e.x, e.y)] ? 1 : 0 }); setPos(e, r.x, r.y); TL.wait(60 + d * 55);
  if (r.body) {
    const v = r.body; emit('lunge', { id: e.id, dx: c.dx, dy: c.dy }); TL.wait(40);
    damage(v, e.boss ? 11 : 8, 'charge', { dx: c.dx, dy: c.dy, label: '돌진!', big: true }); emit('shake', { a: 0.55 });
    if (isFoe(v)) synergy(`${v.name}을(를) 들이받았다!`, 'push');
    if (v.alive) push(v, c.ux, c.uy, 1);
  } else if (r.wall) {
    emit('bump', { id: e.id, dx: c.dx, dy: c.dy });
    damage(e, 5, 'wall', { dx: c.dx, dy: c.dy, label: '쾅! 벽 충돌', big: true }); emit('shake', { a: 0.6 });
    if (e.alive) { e.st.stun = Math.max(e.st.stun, e.boss ? 3 : 2); emitStatus(e); synergy('벽에 머리를 박았다 — 기절!', 'push'); }
  }
  onEnter(e); TL.wait(80);
}
/** 소환수: 내 턴이 끝난 뒤 가장 가까운 적에게 / NPC: 나를 따라온다 */
export function allyFree(a) {
  const P = G.player;
  if (a.npc) { if (!a.freed || dist(a, P) <= 1.6) return; const { cm, list } = candidates(a, 5); goTo(a, cm, best(list, (s) => -Math.abs(distXY(s.x, s.y, ...posOf(P)) - 1.2) * 5 - s.c * 0.2)); return; }
  a.life--;
  if (a.life <= 0) { a.alive = false; emit('vanish', { id: a.id }); return; }
  let tgt = null, bd = 99; for (const e of G.ents) if (e.alive && isFoe(e) && G.vis[I(e.x, e.y)]) { const d = dist(a, e); if (d < bd) { bd = d; tgt = e; } }
  if (!tgt) return;
  if (bd > FREE.reach) { const { cm, list } = candidates(a, 4), [tx, ty] = posOf(tgt); goTo(a, cm, best(list, (s) => -distXY(s.x, s.y, tx, ty) * 5 - s.c * 0.3)); }
  if (dist(a, tgt) <= FREE.reach) { atkGate(); faceTo(a, tgt); emit('lunge', { id: a.id, dx: Math.sign(tgt.x - a.x), dy: Math.sign(tgt.y - a.y) }); TL.wait(70); damage(tgt, a.atk + ri(0, 1), 'hit', { src: a }); TL.wait(80); }
}
