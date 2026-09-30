import { onEnter } from '../core/combat.js';
import { envTick, statusTick } from '../core/elements.js';
import { emitIntents, emitStatus, snapTerrain, snapVis } from '../core/snap.js';
import { G, I, emit, entsAt, isFoe, isP, standable } from '../core/state.js';
import { addShield } from '../core/stones.js';
import { COMBAT } from '../data/realtime.js';
import { S_ASH, S_NONE, S_WATER } from '../data/terrain.js';
import { tickAct } from './action.js';
import { initBody, walk } from './body.js';
import { BOSS_BRAINS, bossTimers } from './boss.js';
import { leechBrain, meleeBrain, npcBrain, shamanBrain } from './foes.js';
import { tickProjs } from './projectile.js';
import { archerBrain, chargerBrain, mageBrain } from './ranged.js';
import { steerAway } from './steer.js';
import { heroAttack } from './weapon.js';

/* ================= 한 틱(1/20초): 두뇌 → 이동 → 행동 → 등불지기 공격 → 투사체 → 상태이상·환경(1초마다) (docs/설계_전투_코어.md §2) =================
   등불지기의 걸음은 clock.js가 먼저 옮긴다. 이 함수는 시간이 흐를 때만 불린다 */
const BRAINS = { goblin: meleeBrain, rat: meleeBrain, leech: leechBrain, shaman: shamanBrain, archer: archerBrain, mage: mageBrain, charger: chargerBrain };

/** 이 유닛이 이번 틱에 걸을 방향(길이 ≤ 1) 또는 null. 행동 중에는 서 있다 */
function think(e) {
  if (e.act || e.st.frozen > 0 || e.st.stun > 0) return null; // 기절·빙결: 생각도 멈춘다
  if (e.npc) return npcBrain(e);
  if (!isFoe(e)) return e.ally ? meleeBrain(e) : null;
  if (!e.awake) return null;
  if (e.st.fear > 0) { const p = G.player; return p ? steerAway(e, p.px, p.py) : null; }
  return (BRAINS_OF(e))(e);
}
const BRAINS_OF = (e) => (e.boss && BOSS_BRAINS[e.boss]) || BRAINS[e.type] || meleeBrain;

export function simTick(dt) {
  G.tickN = (G.tickN || 0) + 1;
  for (const e of G.ents) if (e.alive) initBody(e);
  const units = G.ents.filter((e) => e.alive && !isP(e));
  for (const e of units) {
    e.ppx = e.px; e.ppy = e.py; // 화면이 틱 사이를 보간할 이전 자리
    e.cd = (e.cd || 0) - dt; bossTimers(e, dt);
  }
  for (const e of units) {
    if (!e.alive || G.over) continue;
    const dir = think(e);
    if (dir && !e.act) { const r = walk(e, dir[0], dir[1], dt); if (r.cell) { G.visDirty = true; onEnter(e); } }
  }
  for (const e of G.ents) if (e.alive && e.act) tickAct(e, dt);
  heroAttack(dt);
  tickProjs(dt);
  for (const e of G.ents) if (e.alive) statusTick(e, dt);
  holdTick(dt);
  G.envAcc = (G.envAcc || 0) + dt;
  while (G.envAcc >= COMBAT.env - 1e-9 && !G.over) { G.envAcc -= COMBAT.env; envTick(); }
  if (G.visDirty) { G.visDirty = false; snapVis(); }
  if (G.intentsDirty || G.ents.some((e) => e.alive && e.act && e.act.tele && !e.act.done)) { G.intentsDirty = false; emitIntents(); }
}

/* ---------- 제자리에서 시간을 흘릴 때(⏳·Space): 예전 "대기" 장비가 1초마다 (docs/설계_전투_코어.md §4) ---------- */
export function holdTick(dt) {
  const still = !!(G.intent && G.intent.hold && !G.intent.dir && !G.walk);
  if (!still) { G.stillT = 0; G.holdAcc = 0; return; }
  G.stillT = (G.stillT || 0) + dt; // 고요 목걸이: 제자리에 서 있는 동안 적이 절반은 알아채지 못한다
  G.holdAcc = (G.holdAcc || 0) + dt;
  if (G.holdAcc < 1) return;
  G.holdAcc -= 1;
  const p = G.player;
  if (G.ps && G.ps.patience) addShield(G.ps.patience); // 기다림 망토
  if (G.ps && G.ps.legend.has('mistCloak')) { // 물안개 망토: 둘레 1칸이 젖는다
    for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
      if (!dx && !dy) continue; const x = p.x + dx, y = p.y + dy; if (!standable(x, y)) continue; const i = I(x, y);
      if (G.surf[i] === S_NONE || G.surf[i] === S_ASH) G.surf[i] = S_WATER;
      for (const c of entsAt(x, y)) if (isFoe(c)) { c.st.wet = Math.max(c.st.wet, 3); c.st.burn = 0; emitStatus(c); }
    }
    snapTerrain(); emit('splash', { x: p.x, y: p.y });
  }
}
