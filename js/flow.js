import { armorShield } from './core/combat.js';
import { refreshStats, revealAll } from './core/gear.js';
import { genFloor } from './core/mapgen.js';
import { META, saveMeta } from './core/meta.js';
import { endTurn } from './core/run.js';
import { G, Game, I, TL, newSt } from './core/state.js';
import { hearthGlow } from './core/visitors.js';
import { SLOTS } from './data/gear.js';
import { T_STAIRS } from './data/terrain.js';
import { GLOW } from './data/visitors.js';
import { Sfx } from './render/sfx.js';
import { View } from './render/view.js';
import { Town } from './town/town.js';
import { UI } from './ui/ui.js';
import { cheb } from './util/grid.js';
import { mulberry32, pick, seedOr, setR } from './util/rng.js';
import { jo } from './util/text.js';

/* 한 번의 행동 = 로직 해결 → 연출 재생 */
export function act(fn) {
  if (Anim.active || G.over) return false;
  TL.reset(); G.hurt = false;
  const took = fn();
  if (took) endTurn();
  Anim.start();
  return took;
}

export const Anim = {
  active: false, q: [], i: 0, t: 0, end: 0,
  start() { this.q = TL.q.slice().sort((a, b) => a.t - b.t); TL.q = []; this.i = 0; this.t = 0; this.end = TL.cur + 40; this.active = true; this.step(0); },
  step(ms) {
    if (!this.active) return;
    this.t += ms;
    while (this.i < this.q.length && this.q[this.i].t <= this.t) this.q[this.i++].fn();
    if (this.i >= this.q.length && this.t >= this.end) { this.active = false; UI.afterTurn(); }
  },
};

export function rescueFollowers() {
  for (const e of G.ents) if (e.npc && e.alive && e.freed && cheb(e.x, e.y, G.player.x, G.player.y) <= 2) {
    e.alive = false; META.newNpcs.push(e.npcData); G.loot.npcs.push(e.npcData.name);
    UI.log(`${jo(e.name, '이가')} 정착지로 향한다!`, 'syn');
  }
  saveMeta();
}

export function descend() {
  if (G.over || Anim.active) return;
  if (G.tile[I(G.player.x, G.player.y)] !== T_STAIRS) return;
  if (G.bossFloor) { returnToTown('boss'); return; }
  const p = G.player;
  rescueFollowers();
  G.zf++; p.st = newSt();
  genFloor();
  // 한 층을 내려가면 입은 장비·가방 장비의 정체가 모두 드러난다
  let rv = 0; for (const it of [...SLOTS.map((k) => G.eq[k]), ...G.bag]) if (revealAll(it)) rv++;
  refreshStats(); p.shield = armorShield();
  UI.exitTarget(); UI.travel = null; UI.rest = null; UI.buffered = null;
  View.buildFloor(); UI.floorCard(); UI.syncAll();
  if (rv) UI.log(`장비 ${rv}개의 정체가 드러났다`, 'syn');
  Sfx.play('stairs');
}

export function enterDungeon(zone) {
  const h = META.hero;
  Town.clear(); Game.mode = 'dungeon';
  setR(mulberry32(seedOr(((Date.now() & 0xffffffff) ^ Math.floor(Math.random() * 1e9)) >>> 0)));
  Object.assign(G, { zone, zf: 1, over: false, won: false, nextId: 1, hasteFlip: false, pendingReturn: null, known: h.known, look: h.look, inv: h.inv, eq: h.eq, bag: h.bag, heroBase: h.base, legendsDropped: new Set(h.legends || []), slots: h.slots, sbag: h.sbag, weakKnown: h.weakKnown, ctx: null, curSrc: null, dropHint: 0 });
  G.known.recall = true;
  for (const sl of G.slots) sl.cd = 0;
  G.player = { id: 0, type: 'hero', name: h.name, x: 0, y: 0, hp: h.hp, max: h.max, st: newSt(), alive: true, face: [0, 1], shield: 0 };
  refreshStats();
  G.player.shield = armorShield() + (META.buff === 'feast' ? 6 : 0); META.buff = null;
  G.cd = { push: 0, fire: 0, bolt: 0, frost: 0, venom: 0 };
  G.stats = { kills: 0, combos: 0, turns: 0, items: 0, stones: 0, chains: 0, best: 0 };
  G.mageOf = ['bolt', pick(['fire', 'frost', 'bolt']), pick(['fire', 'frost']), 'mix'];
  G.loot = { mats: {}, npcs: [] };
  G.heroLook = h.npcLook || null; G.zoneFlags = { npc: false, recall: false }; G.perk = h.perk || null; G.sbagMax = h.sbagMax || 3; G.recallArm = false;
  const glow = hearthGlow(); G.glowVision = glow >= GLOW.vision ? 1 : 0;
  if (glow >= GLOW.shield) G.player.shield += 4;
  genFloor();
  UI.toDungeon(); View.buildFloor(); UI.exitTarget(); UI.floorCard(); UI.syncAll();
  saveMeta();
}

export function returnToTown(reason) {
  const h = META.hero, rep = { reason, zone: G.zone, zf: G.zf, loot: {}, npcs: [], hurt: G.player.hp < G.player.max * 0.5, kills: G.stats.kills };
  if (reason === 'death') {
    rep.lost = { ...G.loot.mats }; rep.hero = h.name; rep.npcs = G.loot.npcs.slice();
    META.fallen.push({ name: h.name, gen: h.gen, zone: G.zone, zf: G.zf, kills: G.stats.kills }); META.hero = null;
  } else {
    rescueFollowers(); rep.npcs = G.loot.npcs.slice();
    for (const [m, n] of Object.entries(G.loot.mats)) META.mats[m] = (META.mats[m] || 0) + n;
    rep.loot = { ...G.loot.mats };
    h.hp = Math.max(1, G.player.hp); h.max = G.player.max; h.legends = [...G.legendsDropped];
    if (reason === 'boss') { rep.first = !META.cleared[G.zone - 1]; META.cleared[G.zone - 1] = true; }
  }
  G.over = true; UI.exitTarget(); UI.travel = null; UI.rest = null; UI.buffered = null;
  saveMeta();
  Town.enter(rep);
}
