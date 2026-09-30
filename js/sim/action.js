import { COMBAT } from '../data/realtime.js';
import { G, emit } from '../core/state.js';
import { beatOf, dist } from './body.js';

/* ================= 행동: 힘 모으기(wind) → 판정 → 경직(recover) (docs/설계_전투_코어.md §2) =================
   모든 유닛의 공격·주문·돌진이 같은 틀을 쓴다. 힘 모으는 동안 act.tele(예고 칸)가 바닥에 차오른다.
   ACTS[kind] = { resolve(u, a) — 판정, update?(u, a, dt) — 판정 뒤 계속되는 움직임(돌진), 끝나면 true } */
export const ACTS = {};

export const unitById = (id) => G.ents.find((e) => e.id === id) || null;

/** 행동을 시작한다. o.wind = 힘 모으기(초), o.cd = 끝난 뒤 다음 행동까지(초, 없으면 공격 간격), o.fx = 시작 사건 */
export function startAct(u, kind, o = {}) {
  u.act = { kind, t: 0, wind: o.wind ?? COMBAT.windup, recover: o.recover ?? COMBAT.recover, done: false, ...o };
  if (o.fx) emit(o.fx, { id: u.id, dur: u.act.wind, elem: o.elem, kind });
  G.intentsDirty = true;
  return u.act;
}

/** 한 틱: 기절·빙결이면 끊기고, 힘을 다 모으면 판정, 경직이 끝나면 비운다 */
export function tickAct(u, dt) {
  const a = u.act; if (!a) return;
  if (u.st.frozen > 0 || u.st.stun > 0 || !u.alive) { u.act = null; G.intentsDirty = true; return; }
  a.t += dt;
  const A = ACTS[a.kind];
  if (!a.done) {
    if (a.t < a.wind) return;
    a.done = true; a.t = a.wind; G.intentsDirty = true;
    u.cd = a.cd ?? beatOf(u);
    A.resolve(u, a);
    if (!u.alive || u.act !== a) return;
  }
  if (A.update) { if (A.update(u, a, dt)) { u.act = null; G.intentsDirty = true; } return; }
  if (a.t >= a.wind + a.recover) { u.act = null; G.intentsDirty = true; }
}

/** 이 유닛이 노릴 상대: 가장 가까운 반대편 유닛(주민·중립은 빼고). 적에게는 등불지기와 동료 */
export function foeTarget(u) {
  let best = null, bd = Infinity;
  for (const o of G.ents) {
    if (!o.alive || o === u || o.npc || o.team === u.team || o.team === 'neutral' || o.hidden) continue;
    const d = dist(u, o); if (d < bd) { bd = d; best = o; }
  }
  return best;
}
