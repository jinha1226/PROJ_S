import { RT } from '../data/realtime.js';
import { cheb } from '../util/grid.js';
import { canHit, freeNpc, onEnter, openDoor, playerMelee } from './combat.js';
import { computeFOV, visibleFoes } from './fov.js';
import { openChest } from './gear.js';
import { endTurn, noticeFoes } from './run.js';
import { emitStatus, snapHud, snapVis } from './snap.js';
import { posOf, setPos, sweep } from './space.js';
import { G, I, log } from './state.js';

/* ================= 시간: 움직일 때만 흐른다 (docs/설계_실시간_전환.md §1) =================
   흐르는 동안 고정 틱(RT.tick)으로 나아가고, 걸음 기준(RT.turn)마다 옛 턴(endTurn: 적·횃불·환경)을 한 번 돌린다. */
export function initClock() {
  Object.assign(G, { clock: G.clock || 0, paused: false, stuckAbort: false, acc: 0, turnAcc: 0, swingT: 0, stuckT: 0, intent: { dir: null, hold: false }, walk: null, resting: false, target: null });
  const p = G.player; if (p) { setPos(p, p.x, p.y); p.ppx = p.px; p.ppy = p.py; }
  G.alpha = 1;
}
/** 입력이 매 프레임 알려 준다: dir = 지도 기준 방향(길이 ≤ 1), hold = 제자리에서 흘리기. 방향을 주면 자동 걷기·쉬기는 멈춘다 */
export function setIntent(dir, hold = false) {
  const d = dir && Math.hypot(dir[0], dir[1]) > 0.01 ? dir : null;
  G.intent = { dir: d, hold: !!hold };
  if (d) { G.walk = null; G.resting = false; }
}
export function setWalk(pts) { G.walk = pts && pts.length ? pts.map(([x, y]) => [x, y]) : null; G.stuckT = 0; }
export function setTarget(id) { G.target = id; }
export function setRest(on) { G.resting = !!on; G.restFrom = G.stats.turns; }
/** 가방·정보 창이 열려 있으면 자동 걷기·쉬기도 멈춘다(입력이 매 프레임 알려 준다) */
export function setPaused(on) { G.paused = !!on; }
export const flowing = () => !!(G.player && G.player.alive && !G.over && !G.paused && G.intent && (G.intent.dir || G.intent.hold || G.walk || G.resting));

/** 실시간 dt(초)만큼 흘린다. 흐르지 않으면 0. 돈 틱 수를 돌려준다 */
export function advance(dt) {
  if (!flowing()) { G.acc = 0; return 0; }
  G.acc = Math.min(G.acc + dt, RT.tick * RT.maxTicks);
  let n = 0;
  while (G.acc >= RT.tick - 1e-9 && flowing()) { G.acc -= RT.tick; step(); n++; }
  G.alpha = flowing() ? G.acc / RT.tick : 1; // 화면: 지난 틱과 이번 틱 사이 어디쯤인가(멈추면 이번 틱)
  return n;
}
/** 한 틱: 걸음 → 발밑 칸이 바뀌면 칸 규칙 → 걸음 박자마다 옛 턴 → 닿는 적을 친다 */
export function step() {
  const p = G.player;
  if (p.px == null || Math.round(p.px) !== p.x || Math.round(p.py) !== p.y) setPos(p, p.x, p.y); // 밀치기·순간이동처럼 옛 코드가 칸만 옮기면 칸이 이긴다
  p.ppx = p.px; p.ppy = p.py; // 화면이 틱 사이를 보간할 이전 자리
  G.clock += RT.tick;
  const held = p.st.frozen > 0 || p.st.stun > 0;
  if (!held) moveHero(RT.tick);
  G.turnAcc += RT.tick;
  if (G.turnAcc >= RT.turn - 1e-9) {
    G.turnAcc -= RT.turn;
    if (held) { if (p.st.frozen > 0) p.st.frozen--; if (p.st.stun > 0) p.st.stun--; emitStatus(p); }
    endTurn();
  }
  G.swingT = Math.max(0, G.swingT - RT.tick);
  if (G.swingT <= 0 && p.alive && !G.over && !held) { const t = swingTarget(); if (t) { playerMelee(t); G.swingT = RT.swing; } }
}
/** 1단계 다리: 칠 수 있는 보이는 적. 고른 적이 닿으면 그 적, 아니면 가장 가까운 적 */
function swingTarget() {
  const p = G.player, near = visibleFoes().filter((e) => canHit(e)).sort((a, b) => cheb(a.x, a.y, p.x, p.y) - cheb(b.x, b.y, p.x, p.y));
  return near.find((e) => e.id === G.target) || near[0] || null;
}
function moveHero(dt) {
  const p = G.player, s = RT.heroSpeed * dt, [px, py] = posOf(p);
  let dx = 0, dy = 0;
  if (G.intent.dir) { dx = G.intent.dir[0] * s; dy = G.intent.dir[1] * s; }
  else if (G.walk) {
    const [tx, ty] = G.walk[0], d = Math.hypot(tx - px, ty - py);
    if (d <= s) { dx = tx - px; dy = ty - py; G.walk.shift(); if (!G.walk.length) G.walk = null; }
    else { dx = ((tx - px) / d) * s; dy = ((ty - py) / d) * s; }
  }
  if (Math.abs(dx) + Math.abs(dy) < 1e-6) return;
  const ox = p.x, oy = p.y;
  const r = sweep(p, dx, dy, { ghost: true, cellBlock: true, onDoor: (x, y) => { openDoor(x, y); log('문을 열었다.', 'info'); } });
  if (r.body && r.body.npc && !r.body.freed) freeNpc(r.body);
  const moved = Math.hypot(r.x - px, r.y - py);
  if (G.walk && moved < s * 0.2) { G.stuckT += dt; if (G.stuckT >= RT.stuck) { G.walk = null; G.stuckAbort = true; } } else G.stuckT = 0;
  setPos(p, r.x, r.y);
  if (moved > 1e-4) p.face = [Math.sign(Math.round(dx * 10)), Math.sign(Math.round(dy * 10))];
  if (p.x !== ox || p.y !== oy) enterCell(p);
}
/** 새 칸: 옛 칸 규칙(물·불·줍기), 상자, 시야 */
function enterCell(p) {
  onEnter(p);
  const c = G.chests.get(I(p.x, p.y)); if (c && !c.open) openChest(p.x, p.y);
  computeFOV(); snapVis(); noticeFoes(); snapHud();
}
