import { APPEAR, ITEMS } from '../data/items.js';
import { cheb } from '../util/grid.js';
import { mulberry32, pick, seedOr, setR, shuffle } from '../util/rng.js';
import { allyAct, enemyAct } from './ai.js';
import { envTick } from './elements.js';
import { computeFOV, distMap } from './fov.js';
import { calcStats, makeGear } from './gear.js';
import { addItem } from './items.js';
import { genFloor } from './mapgen.js';
import { emitIntents, emitSlots, snapHud, snapVis } from './snap.js';
import { G, TL, emit, isFoe, log, newSt } from './state.js';
import { withCtx } from './stones.js';

/* ================= 새 게임 · 층 생성 ================= */
export function newRun() {
  setR(mulberry32(seedOr(((Date.now() & 0xffffffff) ^ Math.floor(Math.random() * 1e9)) >>> 0)));
  Object.assign(G, { floor: 1, over: false, won: false, nextId: 1, hasteFlip: false, known: {}, look: {} });
  for (const cat of ['potion', 'scroll', 'throw']) {
    const looks = shuffle(APPEAR[cat].slice());
    Object.keys(ITEMS).filter((k) => ITEMS[k].cat === cat).forEach((k, j) => { G.look[k] = { name: looks[j][0], color: looks[j][1] }; });
  }
  G.player = { id: 0, type: 'hero', name: '나', x: 0, y: 0, hp: 30, max: 30, st: newSt(), alive: true, face: [0, 1], shield: 0 };
  G.zone = 1; G.zf = 1; G.loot = { mats: {}, npcs: [] };
  G.inv = [];
  addItem(pick(['heal', 'heal', 'cure', 'haste'])); addItem(pick(['oil', 'water', 'smoke'])); addItem(pick(['oil', 'water'])); addItem(pick(['tele', 'fear', 'blaze']));
  G.cd = { push: 0, fire: 0, bolt: 0, frost: 0, venom: 0 };
  G.stats = { kills: 0, combos: 0, turns: 0, items: 0, stones: 0, chains: 0, best: 0 };
  G.mageOf = ['bolt', pick(['fire', 'frost', 'bolt']), pick(['fire', 'frost']), pick(['frost', 'bolt', 'fire']), 'mix'];
  const starts = shuffle(['sword', 'mace', 'dagger']);
  G.eq = { weapon: makeGear(starts[0]), off: makeGear(starts[1]), head: null, body: makeGear('body_cloth'), hands: null, feet: null, neck: null, ring1: null, ring2: null };
  G.bag = []; G.heroBase = 30; G.legendsDropped = new Set(); G.ps = calcStats(G.eq);
  G.slots = Array.from({ length: 6 }, () => ({ color: null, stone: null, cd: 0 }));
  G.sbag = []; G.weakKnown = {}; G.ctx = null; G.curSrc = null; G.dropHint = 0; G.zoneFlags = { npc: false, recall: false }; G.perk = null; G.glowVision = 0; G.recallArm = false;
  genFloor();
}

/* ================= 턴 ================= */
export function endTurn() {
  const p = G.player;
  if (p.st.haste > 0 && !G.hasteFlip) { G.hasteFlip = true; computeFOV(); snapVis(); emitIntents(); snapHud(); return; }
  G.hasteFlip = false;
  worldTick();
}

export function worldTick() {
  G.stats.turns++;
  computeFOV(); snapVis();
  const p = G.player;
  G.tickMoveEnd = TL.cur + 110;
  const dm = distMap(p.x, p.y);
  for (const a of G.ents.filter((e) => e.alive && e.ally)) if (a.alive && !G.over) allyAct(a, dm);
  const foes = G.ents.filter((e) => e.alive && isFoe(e)).sort((a, b) => cheb(a.x, a.y, p.x, p.y) - cheb(b.x, b.y, p.x, p.y));
  for (const e of foes) { if (G.over) break; if (e.alive) { G.curSrc = e; withCtx('enemy', () => enemyAct(e, dm)); G.curSrc = null; } }
  if (!G.over) envTick();
  for (const k in G.cd) if (G.cd[k] > 0) G.cd[k]--;
  for (const sl of G.slots) if (sl.cd > 0) sl.cd--;
  if (p.alive && G.stats.turns % 6 === 0 && p.hp < p.max && !p.st.poison && !p.st.burn) { p.hp++; emit('hp', { id: 0, hp: p.hp, max: p.max }); }
  computeFOV(); snapVis(); emitIntents(); snapHud(); emitSlots();
  // 귀환 두루마리: 빛이 모인 한 턴이 지나면 사라진다
  if (G.recallArm && p.alive && !G.over) { G.recallArm = false; emit('poof', { x: p.x, y: p.y }); log('빛에 싸여 사라졌다 — 정착지로', 'syn'); G.pendingReturn = 'recall'; }
}
