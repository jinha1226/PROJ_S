import { COMBAT } from '../data/realtime.js';
import { damage, moveEnt } from '../core/combat.js';
import { canSee, los } from '../core/fov.js';
import { mkEnemy } from '../core/mapgen.js';
import { G, I, emit, entAt, entsAt, inb, isFoe, log, standable } from '../core/state.js';
import { ri, shuffle } from '../util/rng.js';
import { jo } from '../util/text.js';
import { ACTS, foeTarget, startAct } from './action.js';
import { angTo, dist, faceAng } from './body.js';
import { meleeBrain } from './foes.js';
import { chargerBrain, mageBrain } from './ranged.js';
import { onCells, square3 } from './shapes.js';

/* ================= 보스: 원형 + 고유 기믹 (docs/설계_실시간_전환.md §5) ================= */
const adds = (boss) => G.ents.filter((e) => e.alive && isFoe(e) && e !== boss && e.summoned).length;

/** 부하를 부른다: 둘레의 빈 칸에 */
export function summonFoes(e, type, n) {
  let c = 0;
  const spots = [];
  for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) if (dx || dy) spots.push([e.x + dx, e.y + dy]);
  for (const [x, y] of shuffle(spots)) {
    if (c >= n) break;
    if (!inb(x, y) || !standable(x, y) || entAt(x, y)) continue;
    const m = mkEnemy(type, x, y, G.theme); m.awake = true; m.summoned = true; G.ents.push(m); c++;
    emit('spawn', { e: { ...m, st: { ...m.st } }, seen: G.vis[I(x, y)] ? 1 : 0 });
  }
  if (c) log(`${jo(e.name, '이가')} 부하를 불렀다.`, 'bad');
  return c;
}

/** 고블린 족장: 8초마다 뿔나팔(1.2초 예고)로 고블린 둘, 가까우면 1.2초 예고가 붙는 강타(3×3), 그 밖에는 고블린처럼 */
function chiefBrain(e) {
  const t = foeTarget(e); if (!t) return null;
  e.hornT = (e.hornT ?? COMBAT.hornEvery * 0.5);
  if (e.hornT <= 0 && canSee(e, t) && adds(e) < COMBAT.maxAdds) { e.hornT = COMBAT.hornEvery; startAct(e, 'horn', { wind: COMBAT.tele.horn, cd: 0.6, fx: 'windup' }); log('족장이 뿔나팔을 든다.', 'bad'); return null; }
  if (e.cd <= 0 && (e.slamN = (e.slamN || 0)) >= 3 && dist(e, t) <= 1.8) {
    e.slamN = 0; faceAng(e, angTo(e, t));
    const cells = square3(t.x, t.y);
    startAct(e, 'slam', { wind: COMBAT.tele.slam, cells, cd: 1.2, recover: 0.5, tele: { kind: 'cells', cells, elem: 'push' }, fx: 'windup' });
    return null;
  }
  const busy = !!e.act; const dir = meleeBrain(e);
  if (!busy && e.act && e.act.kind === 'melee') e.slamN++;
  return dir;
}
ACTS.horn = { resolve(u) { emit('horn', { id: u.id }); summonFoes(u, 'goblin', 2); } };
ACTS.slam = {
  resolve(u, a) {
    emit('lunge', { id: u.id, dx: Math.cos(u.ang), dy: Math.sin(u.ang), amt: 0.6 }); emit('shake', { a: 0.5 });
    for (const t of G.ents.filter((o) => o.alive && o.team !== u.team && !o.npc && onCells(a.cells, o))) damage(t, u.atk + 2, 'hit', { label: '강타', big: true, src: u });
  },
};

/** 대마법사·파수꾼: 넓은 주문, 붙으면 순간이동. 파수꾼은 10초마다 해골 궁수 둘 */
function archBrain(e) {
  const t = foeTarget(e); if (!t) return null;
  e.blinkT = e.blinkT ?? 0; e.sumT = e.sumT ?? COMBAT.summonEvery * 0.5;
  if (dist(e, t) <= 1.5 && e.blinkT <= 0 && blink(e, t)) { e.blinkT = COMBAT.blinkEvery; return null; }
  if (e.boss === 'abyss' && e.sumT <= 0 && canSee(e, t) && adds(e) < COMBAT.maxAdds) { e.sumT = COMBAT.summonEvery; summonFoes(e, 'archer', 2); return null; }
  return mageBrain(e);
}
function blink(e, t) {
  let best = null, bd = -1;
  for (let k = 0; k < 40; k++) {
    const x = e.x + ri(-6, 6), y = e.y + ri(-6, 6);
    if (!inb(x, y) || !standable(x, y) || entsAt(x, y).length) continue;
    const dd = Math.max(Math.abs(x - t.x), Math.abs(y - t.y));
    if (dd >= 3 && dd <= 6 && dd > bd && los(x, y, t.x, t.y)) { bd = dd; best = [x, y]; }
  }
  if (!best) return false;
  emit('poof', { x: e.x, y: e.y }); moveEnt(e, best[0], best[1], { dur: 1, hop: 0, kind: 'tele' }); emit('poof', { x: best[0], y: best[1] });
  log(`${jo(e.name, '이가')} 순간이동했다.`, 'info');
  return true;
}

/** 보스 타이머(초) */
export function bossTimers(e, dt) {
  if (e.hornT != null) e.hornT -= dt;
  if (e.blinkT != null) e.blinkT -= dt;
  if (e.sumT != null) e.sumT -= dt;
}

export const BOSS_BRAINS = { chief: chiefBrain, lich: archBrain, abyss: archBrain, boarking: chargerBrain };
