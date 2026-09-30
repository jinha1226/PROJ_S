import { COMBAT, RT } from '../data/realtime.js';
import { openDoor } from '../core/combat.js';
import { posOf, rad, setPos, sweep } from '../core/space.js';
import { G, isFoe, isP, log } from '../core/state.js';
import { rand } from '../util/rng.js';

/* ================= 몸: 모든 유닛(등불지기·동료·적)이 같은 모양이다 (docs/설계_전투_코어.md §2) =================
   px, py = 소수 위치, x, y = 발밑 칸(반올림). ang = 바라보는 각도(라디안, 지도 기준 x → y). act = 진행 중인 행동, cd = 다음 행동까지(초) */

/** 처음 보는 유닛에 몸을 붙인다(층 생성·소환·구한 주민 모두) */
export function initBody(e) {
  if (e.px == null) setPos(e, e.x, e.y);
  if (e.ang == null) e.ang = Math.atan2(e.face ? e.face[1] : 1, e.face ? e.face[0] : 0);
  if (e.team == null) e.team = isP(e) || e.ally ? 'party' : 'foe';
  if (e.ctrl == null) e.ctrl = isP(e) ? 'player' : 'ai';
  if (e.act === undefined) e.act = null;
  if (!isP(e) && e.cdInit !== true) { e.cd = rand() * beatOf(e); e.cdInit = true; } // 처음 박자를 흩어 둔다: 모두 한꺼번에 치지 않는다
}

/** 공격 간격(초): 골절이면 1.5배 */
export function beatOf(e) { return (COMBAT.beat[e.boss] ?? COMBAT.beat[e.type] ?? 1) * (e.st && e.st.frac > 0 ? 1.5 : 1); }

/** 걷는 속도(칸/초): 빙결·기절이면 0, 골절 절반, 가속 1.5배 */
export function speedOf(e) {
  if (!e.st) return 0;
  if (e.st.frozen > 0 || e.st.stun > 0 || (e.fx && e.fx.root)) return 0;
  let v = isP(e) ? RT.heroSpeed : e.boss ? COMBAT.bossSpeed : COMBAT.foeSpeed[e.npc ? 'npc' : e.type] ?? 3.3;
  if (e.st.frac > 0) v *= 0.5;
  if (e.st.haste > 0) v *= 1.5;
  if (e.fx && e.fx.haste) v *= 1 + e.fx.haste.v;
  if (isP(e) && G.ps && G.ps.speed) v *= 1 + G.ps.speed / 100; // Class 이동(%)
  return v;
}

export const dist = (a, b) => { const [ax, ay] = posOf(a), [bx, by] = posOf(b); return Math.hypot(ax - bx, ay - by); };
export const angTo = (a, b) => { const [ax, ay] = posOf(a), [bx, by] = posOf(b); return Math.atan2(by - ay, bx - ax); };
/** 두 각도의 차(0~π) */
export const angDiff = (a, b) => { let d = Math.abs(a - b) % (Math.PI * 2); return d > Math.PI ? Math.PI * 2 - d : d; };

/** 바라보는 방향: 각도와 옛 코드가 쓰는 8방향 face를 함께 맞춘다 */
export function faceAng(e, ang) {
  e.ang = ang;
  const f = [Math.round(Math.cos(ang)), Math.round(Math.sin(ang))];
  if (f[0] || f[1]) e.face = f;
}

/** (vx, vy) 방향(길이 ≤ 1)으로 dt초 걷는다: 벽을 따라 미끄러지고 몸끼리 막힌다. 발밑 칸이 바뀌면 true */
export function walk(e, vx, vy, dt, o = {}) {
  const s = (o.speed ?? speedOf(e)) * dt; if (s <= 0) return { moved: 0 };
  const [px, py] = posOf(e), ox = e.x, oy = e.y;
  const r = sweep(e, vx * s, vy * s, { ghost: e.team === 'party', onDoor: isFoe(e) || e.npc ? (x, y) => { openDoor(x, y); if (G.vis[y * G.W + x]) log('문이 열렸다.', 'info'); } : null });
  setPos(e, r.x, r.y);
  const moved = Math.hypot(r.x - px, r.y - py);
  if (moved > 1e-4) e.movedAt = G.clock;
  if (moved > 1e-4 && !o.keepFace) faceAng(e, Math.atan2(r.y - py, r.x - px));
  return { moved, body: r.body, wall: r.wall, cell: e.x !== ox || e.y !== oy };
}

/** 반지름 합으로 잰 틈(0이면 닿아 있다) */
export const gap = (a, b) => dist(a, b) - rad(a) - rad(b);
