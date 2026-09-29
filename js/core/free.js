import { HEX } from '../data/colors.js';
import { MAGE } from '../data/enemies.js';
import { FREE } from '../data/free.js';
import { S_ICE, S_WATER, T_DOOR } from '../data/terrain.js';
import { enemyMelee } from './ai.js';
import { onEnter, openDoor, playerMelee, playerWait } from './combat.js';
import { applyFire, envTick } from './elements.js';
import { canSee, computeFOV } from './fov.js';
import { allyFree, freeEnemyAct } from './free-ai.js';
import { emitSlots, emitStatus, snapHud, snapVis } from './snap.js';
import { costMap, dist, distXY, meleeReach, moveRange, pathPoints, posOf, setPos, sweep } from './space.js';
import { G, I, TL, emit, isFoe, isP, log } from './state.js';
import { withCtx } from './stones.js';

/* ================= 원형 턴제: 탐험 ↔ 전투, 턴, 이동, 기회 공격 =================
   G.free = 이 모드인가, G.fc = 전투 중 상태(없으면 탐험). 규칙 효과(원소·영혼석·부상)는 격자 모드와 같은 함수를 쓴다. */
export function initFree() {
  for (const e of G.ents) setPos(e, e.px ?? e.x, e.py ?? e.y);
  G.fc = null; G.expT = 0;
}
export const inCombat = () => !!(G.free && G.fc);
export const myTurn = () => !!(G.fc && G.fc.side === 'player');

/* ---------- 탐험 ---------- */
/** 조이스틱·경로 걷기 한 걸음. 칸이 바뀌면 true */
export function exploreMove(dx, dy) {
  const p = G.player, ox = p.x, oy = p.y;
  const r = sweep(p, dx, dy, { onDoor: (tx, ty) => openDoor(tx, ty) });
  setPos(p, r.x, r.y);
  if (Math.abs(dx) + Math.abs(dy) > 1e-4) p.face = [Math.sign(Math.round(dx * 10)), Math.sign(Math.round(dy * 10))];
  if (p.x === ox && p.y === oy) return false;
  onEnter(p); computeFOV(); snapVis(); snapHud();
  return true;
}
/** 탐험 중 시간 흐름(불 번짐·상태·재사용 대기) */
export function exploreTick() {
  const p = G.player;
  envTick();
  for (const k in G.cd) if (G.cd[k] > 0) G.cd[k]--;
  for (const sl of G.slots) if (sl.cd > 0) sl.cd--;
  G.stats.turns++;
  if (p.alive && G.stats.turns % 6 === 0 && p.hp < p.max && !p.st.poison && !p.st.burn) { p.hp++; emit('hp', { id: 0, hp: p.hp, max: p.max }); }
  for (const k of ['frozen', 'stun']) if (p.st[k] > 0) { p.st[k]--; emitStatus(p); }
  computeFOV(); snapVis(); snapHud(); emitSlots();
}
/** 적이 나를 보거나 내가 적을 보면 전투. 'ambush' = 내가 먼저 봤다 */
export function detect() {
  if (G.fc || G.over) return null;
  const p = G.player, foes = G.ents.filter((e) => e.alive && isFoe(e));
  const seenBy = foes.filter((e) => e.awake && !e.st.fear && canSee(e, p));
  if (seenBy.length) return 'caught';
  const iSee = foes.filter((e) => G.vis[I(e.x, e.y)]);
  if (iSee.length && iSee.some((e) => e.awake || dist(e, p) <= 7)) return 'ambush';
  return null;
}

/* ---------- 전투 ---------- */
export function startCombat(kind) {
  const p = G.player, ambush = kind === 'ambush';
  G.fc = { round: 0, side: null, move: 0, actions: 0, ambush, reacted: new Set(), pReact: true };
  if (!ambush) for (const e of G.ents) if (e.alive && isFoe(e) && (G.vis[I(e.x, e.y)] || dist(e, p) <= FREE.joinRange) && canSee(e, p)) e.awake = true;
  emit('combat', { start: true, ambush }); TL.wait(650);
  log(ambush ? '기습! 먼저 움직인다 — 첫 공격 피해 +50%' : '들켰다 — 전투 시작!', ambush ? 'syn' : 'bad');
  if (ambush) beginPlayerTurn(); else enemyPhase();
}
export function beginPlayerTurn() {
  const fc = G.fc, p = G.player; if (!fc || G.over) return;
  fc.side = 'player'; fc.round++; fc.move = moveRange(p); fc.actions = p.st.haste > 0 ? 2 : 1; fc.reacted = new Set();
  if (p.st.frozen > 0 || p.st.stun > 0) {
    const fz = p.st.frozen > 0; if (p.st.frozen > 0) p.st.frozen--; if (p.st.stun > 0) p.st.stun--; emitStatus(p);
    log(fz ? '얼어붙어 이번 턴을 넘긴다…' : '기절해서 이번 턴을 넘긴다…', 'bad'); fc.move = 0; fc.actions = 0;
    endPlayerTurn(); return;
  }
  emit('myTurn', { move: fc.move, actions: fc.actions });
}
export function endPlayerTurn() {
  if (!G.fc || G.over) return;
  for (const a of G.ents.filter((e) => e.alive && e.ally)) if (a.alive && !G.over) allyFree(a);
  enemyPhase();
}
function enemyPhase() {
  const fc = G.fc, p = G.player; fc.side = 'enemy'; fc.pReact = true; G.tickMoveEnd = TL.cur;
  const foes = G.ents.filter((e) => e.alive && isFoe(e)).sort((a, b) => dist(a, p) - dist(b, p));
  for (const e of foes) { if (G.over) break; if (e.alive) { G.curSrc = e; withCtx('enemy', () => freeEnemyAct(e)); G.curSrc = null; } }
  emit('focusEnd');
  roundEnd();
  if (G.over) return;
  const active = G.ents.some((e) => e.alive && isFoe(e) && e.awake && (G.vis[I(e.x, e.y)] || dist(e, p) <= 8));
  if (!active) endCombat(); else beginPlayerTurn();
}
function roundEnd() {
  const p = G.player;
  if (!G.over) envTick();
  for (const k in G.cd) if (G.cd[k] > 0) G.cd[k]--;
  for (const sl of G.slots) if (sl.cd > 0) sl.cd--;
  G.stats.turns++;
  if (p.alive && G.stats.turns % 6 === 0 && p.hp < p.max && !p.st.poison && !p.st.burn) { p.hp++; emit('hp', { id: 0, hp: p.hp, max: p.max }); }
  computeFOV(); snapVis(); emitFreeIntents(); snapHud(); emitSlots();
}
export function endCombat() {
  G.fc = null; emit('combat', { start: false }); log('전투 끝 — 다시 자유롭게 걷는다', 'good');
  emitFreeIntents(); snapHud();
}
/** 전투 중 행동 하나를 썼다. 다 쓰고 걸을 거리도 없으면 턴을 넘긴다 */
export function spendAction() {
  const fc = G.fc; if (!fc) return;
  fc.actions--;
  if (fc.actions <= 0 && fc.move < 0.3 && !G.over) endPlayerTurn();
}
/** 대기: 행동 없이 턴을 끝낸다(보라 발동) */
export function freeWait() { playerWait(); if (G.fc) { G.fc.actions = 0; endPlayerTurn(); } return true; }

/* ---------- 이동 실행: 기회 공격 · 불 · 물 · 얼음 ---------- */
export function walkPath(e, pts) {
  const fc = G.fc, isPl = isP(e);
  let [lx, ly] = posOf(e), last = null; const speed = isPl ? 0.16 : 0.2;
  const flush = (x, y, kind = 'step') => { const d = distXY(lx, ly, x, y); if (d < 0.01) return; emitMove(e, x, y, Math.max(90, d * speed * 1000), kind); TL.wait(Math.max(80, d * speed * 1000)); lx = x; ly = y; };
  const burned = new Set();
  for (let k = 1; k < pts.length && e.alive && !G.over; k++) {
    const [ax, ay] = posOf(e), [bx, by] = pts[k], seg = distXY(ax, ay, bx, by), n = Math.max(1, Math.ceil(seg / 0.25));
    for (let s = 1; s <= n && e.alive && !G.over; s++) {
      const x = ax + ((bx - ax) * s) / n, y = ay + ((by - ay) * s) / n, prev = posOf(e);
      const ot = I(e.x, e.y); setPos(e, x, y); last = [bx - ax, by - ay];
      if (fc) for (const o of reactors(e)) if (distXY(prev[0], prev[1], ...posOf(o)) <= reachOf(o) && distXY(x, y, ...posOf(o)) > reachOf(o)) {
        flush(prev[0], prev[1]); react(o, e); if (!e.alive || G.over) return;
      }
      const i = I(e.x, e.y);
      if (i !== ot) {
        if (G.tile[i] === T_DOOR || isPl) { // 문은 지나가며 연다 · 시야는 걸음에 맞춰 갱신
          const save = TL.cur; TL.cur += distXY(lx, ly, x, y) * speed * 1000;
          if (G.tile[i] === T_DOOR) openDoor(e.x, e.y);
          if (isPl) { computeFOV(); snapVis(); }
          TL.cur = save;
        }
        if (G.fire[i] > 0 && !burned.has(i)) { burned.add(i); flush(x, y); applyFire(e, 2); }
        if (G.surf[i] === S_WATER && e.st.wet < 3) { e.st.wet = 3; e.st.burn = 0; emitStatus(e); }
      }
    }
  }
  const [ex, ey] = posOf(e); flush(ex, ey);
  // 얼음: 멈추지 못하고 미끄러진다
  if (e.alive && G.surf[I(e.x, e.y)] === S_ICE && last && !(isPl && G.ps && G.ps.noSlide)) {
    const L = Math.hypot(...last) || 1, ux = last[0] / L, uy = last[1] / L; let slid = 0;
    while (slid < 8 && G.surf[I(e.x, e.y)] === S_ICE) { const r = sweep(e, ux * 0.5, uy * 0.5, { stopOnHit: true }); if (Math.hypot(r.x - e.px, r.y - e.py) < 0.05) break; setPos(e, r.x, r.y); slid += 0.5; }
    if (slid) { const [sx, sy] = posOf(e); emitMove(e, sx, sy, 60 + slid * 70, 'slide'); TL.wait(60 + slid * 70); log(isPl ? '얼음 위에서 미끄러졌다' : `${e.name}이(가) 미끄러진다`, 'info'); }
  }
  if (e.alive) onEnter(e);
}
const reachOf = (o) => meleeReach(o);
/** 벗어날 때 기회 공격을 할 수 있는 쪽 */
function reactors(e) {
  const fc = G.fc;
  if (isP(e)) return G.ents.filter((o) => o.alive && isFoe(o) && o.awake && !o.st.frozen && !o.st.stun && !o.st.fear && !fc.reacted.has(o.id));
  if (isFoe(e) && fc.pReact && !G.player.st.frozen && !G.player.st.stun) return [G.player];
  return [];
}
function react(o, mover) {
  const fc = G.fc;
  if (isP(o)) { fc.pReact = false; emit('opp', { id: 0 }); log('기회 공격!', 'syn'); playerMelee(mover); return; }
  fc.reacted.add(o.id); emit('opp', { id: o.id }); log(`${o.name}의 기회 공격!`, 'bad');
  enemyMelee(o, mover);
}
function emitMove(e, x, y, dur, kind) {
  const [px, py] = [e.px, e.py]; e.px = x; e.py = y;
  emit('move', { id: e.id, x, y, dur, hop: kind === 'step' ? 0.12 : 0.03, kind, seen: isP(e) || G.vis[I(Math.round(x), Math.round(y))] ? 1 : 0 });
  e.px = px; e.py = py;
}
/** 플레이어가 고른 곳으로 걷는다(전투면 이동 거리에서 뺀다) */
export function playerWalk(pts, cost) {
  const fc = G.fc; if (fc && cost > fc.move + 1e-6) return false;
  walkPath(G.player, pts);
  if (fc) { fc.move = Math.max(0, fc.move - cost); if (fc.actions <= 0 && fc.move < 0.3 && !G.over) endPlayerTurn(); }
  return true;
}
/** 붙어 있으면 바로, 아니면 걸어가서 친다 */
export function attackPlan(t) {
  const p = G.player, R = meleeReach(p) - 0.05;
  if (dist(p, t) <= R + 0.05) return { pts: null, cost: 0 };
  const budget = G.fc ? G.fc.move : 30, cm = costMap(p, budget), [tx, ty] = posOf(t);
  let best = null;
  for (let y = t.y - 3; y <= t.y + 3; y++) for (let x = t.x - 3; x <= t.x + 3; x++) {
    if (x < 0 || y < 0 || x >= G.W || y >= G.H) continue; const c = cm.cost[I(x, y)]; if (!isFinite(c)) continue;
    const d = distXY(x, y, tx, ty); if (d > R) continue;
    if (!best || c < best.c) best = { x, y, c };
  }
  if (!best) return null;
  const path = pathPoints(p, cm, best.x, best.y); return path ? { pts: path.pts, cost: path.cost } : null;
}
export function walkAttack(t) {
  const plan = attackPlan(t); if (!plan) return false;
  if (plan.pts) { if (!playerWalk(plan.pts, plan.cost)) return false; }
  if (!G.player.alive || !t.alive || G.over) return true;
  playerMelee(t);
  return true;
}

/* ---------- 자유 위치 밀치기 ---------- */
export function freePush(e, dx, dy, n) {
  const p = G.player;
  let ux = dx, uy = dy;
  if (!isP(e) && p.alive) { const [ex, ey] = posOf(e), [px, py] = posOf(p), vx = ex - px, vy = ey - py; if (vx * dx + vy * dy > 0 && Math.hypot(vx, vy) > 0.1) { ux = vx; uy = vy; } }
  const L = Math.hypot(ux, uy) || 1; ux /= L; uy /= L;
  let left = n, moved = 0;
  while (left > 0.01 && e.alive && moved < 12) {
    const step = Math.min(left, 0.5), r = sweep(e, ux * step, uy * step, { stopOnHit: true });
    const adv = Math.hypot(r.x - e.px, r.y - e.py);
    if (adv > 0.01) { setPos(e, r.x, r.y); moved += adv; left -= adv; }
    if (r.wall || r.body || adv < 0.01) {
      if (moved > 0.01) { emitMove(e, e.px, e.py, 80 + moved * 60, 'push'); TL.wait(80 + moved * 60); moved = 0.001; }
      return { wall: r.wall && !r.body, body: r.body };
    }
    if (left <= 0.01 && G.surf[I(e.x, e.y)] === S_ICE) left = 0.5; // 얼음 위에서는 계속 미끄러진다
  }
  if (moved > 0.01) { emitMove(e, e.px, e.py, 80 + moved * 60, 'push'); TL.wait(80 + moved * 60); }
  return { wall: false, body: null };
}

/* ---------- 예고: 원 · 띠 · 조준선 ---------- */
export function emitFreeIntents() {
  const decals = [], tags = {}, casting = [], winding = [], p = G.player;
  for (const e of G.ents) {
    if (!e.alive || isP(e)) continue;
    if (e.npc) { tags[e.id] = e.freed ? '🙂' : e.caged ? '🆘' : '❔'; continue; }
    if (e.ally) { tags[e.id] = '✦' + e.life; continue; }
    if (!e.awake) { tags[e.id] = '💤'; continue; }
    if (e.cast) { decals.push({ x: e.cast.cx, y: e.cast.cy, kind: 8, color: HEX.danger, alpha: 0.95, blink: 1, scale: e.cast.r * 2 / 0.9 }); tags[e.id] = MAGE[e.elem].icon + '!'; casting.push(e.id); }
    if (e.charge) {
      const [ex, ey] = posOf(e), L = e.charge.len;
      decals.push({ x: ex + e.charge.ux * L / 2, y: ey + e.charge.uy * L / 2, kind: 9, color: 0xff5a2a, alpha: 0.9, blink: 0.5, sx: 1.0, sz: L, yaw: Math.atan2(e.charge.ux, e.charge.uy) });
      tags[e.id] = '‼'; winding.push(e.id);
    }
    if (e.aim) {
      const [ax, ay] = posOf(e), [bx, by] = posOf(p), d = distXY(ax, ay, bx, by);
      for (let s = 0.7; s < d - 0.4; s += 0.6) decals.push({ x: ax + ((bx - ax) * s) / d, y: ay + ((by - ay) * s) / d, kind: 3, color: HEX.danger, alpha: 0.95, blink: 0.5 });
      decals.push({ x: bx, y: by, kind: 4, color: HEX.danger, alpha: 0.9, blink: 1 });
      tags[e.id] = '🎯';
    }
    if (e.st.fear) tags[e.id] = '😱';
  }
  emit('intents', { decals, tags, casting, winding });
}
