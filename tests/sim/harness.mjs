// 전투 코어 테스트 도우미: 브라우저 없이 Node에서 G에 9×9 아레나를 만들고 틱 단위로 돌린다.
import { initClock, setIntent, step } from '../../js/core/clock.js';
import { makeGear, refreshStats } from '../../js/core/gear.js';
import { mkBoss, mkEnemy } from '../../js/core/mapgen.js';
import { BOSSES } from '../../js/data/enemies.js';
import { newRun } from '../../js/core/run.js';
import { setPos } from '../../js/core/space.js';
import { G, newSt, setListener } from '../../js/core/state.js';
import { S_NONE, T_FLOOR, T_WALL } from '../../js/data/terrain.js';
import { mulberry32, setR } from '../../js/util/rng.js';
import { setClass } from '../../js/sim/classes.js';
import { newProg } from '../../js/core/progress.js';

export const events = [];
setListener((type, data) => events.push({ type, ...data }));
newRun();

export const CX = 15, CY = 15;

/**
 * 9×9 방(가운데 15, 15) + 적들. foes = [[dx, dy, type, 덮어쓸 값], …]
 * o.weapon = 등불지기 무기, o.seed = 난수 씨앗, o.size = 방 반지름
 */
export function arena(foes = [], o = {}) {
  setR(mulberry32(o.seed ?? 7));
  const R = o.size ?? 4, p = G.player;
  for (let y = 0; y < G.H; y++) for (let x = 0; x < G.W; x++) {
    const i = y * G.W + x;
    G.tile[i] = Math.abs(x - CX) <= R && Math.abs(y - CY) <= R ? T_FLOOR : T_WALL;
    G.surf[i] = S_NONE; G.fire[i] = 0; G.cloud[i] = 0; G.cloudT[i] = 0; G.seen[i] = 1; G.vis[i] = 1;
  }
  G.gear.clear(); G.chests.clear(); G.items.clear(); G.stones.clear(); G.mats.clear(); if (G.lamps) G.lamps.clear();
  G.over = false; G.torch = 100; G.theme = G.theme || { packs: [] };
  for (const k of Object.keys(G.eq)) G.eq[k] = null;
  if (o.body) G.eq.body = makeGear(o.body, { known: true });
  G.xp = 0; G.level = 1; G.prog = newProg(); G.heroBase = 30; G.vengeance = 0; G.auras = {}; G.darkAmbushUsed = false;
  Object.assign(p, { fx: {}, scd: {}, classHp: 0 }); setClass(p, o.cls || { levels: {} });
  G.eq.weapon = makeGear(o.weapon ?? 'sword'); refreshStats();
  G.ps.eva = 0; G.ps.block = 0; G.ps.def = 0; G.ps.acc = 0; G.ps.crit = 0; G.ps.vamp = 0; G.ps.torchSlow = 0; G.ps.torchCost = 0;
  Object.assign(p, { x: CX, y: CY, hp: 40, max: 40, shield: 0, alive: true, st: newSt(), face: [1, 0], ang: 0, act: null });
  setPos(p, CX, CY);
  G.ents = [p]; G.nextId = 1; G.clock = 0; G.stats.turns = 0; G.tickN = 0;
  for (const [dx, dy, type = 'goblin', over = {}] of foes) {
    const e = BOSSES[type] ? Object.assign(mkBoss(type, CX + dx, CY + dy), { hp: BOSSES[type].hp, max: BOSSES[type].hp }) : mkEnemy(type, CX + dx, CY + dy, G.theme);
    Object.assign(e, { awake: true, hidden: false }, over);
    if (over.hp != null && over.max == null) e.max = over.hp;
    e.st = newSt(); G.ents.push(e);
  }
  G.hurt = false; G.hurtTurn = -9; G.target = null; G.paused = false;
  G.zones = []; initClock();
  events.length = 0;
  return G;
}

/** n틱 동안 hold(제자리 흘리기) 또는 주어진 방향으로 */
export function run(n, dir = null) {
  for (let k = 0; k < n; k++) { if (G.over) break; setIntent(dir, !dir); step(); }
  setIntent(null, false);
}

export const foe = (k = 1) => G.ents[k];
export const secs = (s) => Math.round(s / 0.05);
