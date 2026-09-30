import { advance } from './core/clock.js';
import { armorShield } from './core/combat.js';
import { computeFOV } from './core/fov.js';
import { leaveRelics, newJewelLook, refreshStats } from './core/gear.js';
import { genFloor } from './core/mapgen.js';
import { META, saveMeta } from './core/meta.js';
import { emitSlots, snapHud, snapVis } from './core/snap.js';
import { G, Game, I, TL, newSt } from './core/state.js';
import { leaveStone } from './core/stones.js';
import { startTorch } from './core/torch.js';
import { hearthGlow } from './core/visitors.js';
import { ALWAYS_KNOWN } from './data/items.js';
import { T_STAIRS } from './data/terrain.js';
import { GLOW } from './data/visitors.js';
import { Sfx } from './render/sfx.js';
import { View } from './render/view.js';
import { Town } from './town/town.js';
import { UI } from './ui/ui.js';
import { cheb } from './util/grid.js';
import { mulberry32, pick, seedOr, setR } from './util/rng.js';
import { jo } from './util/text.js';

/* 행동 하나: 규칙은 즉시, 연출은 대기열로. 실시간이라 턴을 넘기지 않고 입력도 막지 않는다 */
export function act(fn) {
  if (G.over || Game.mode !== 'dungeon') return false;
  TL.reset();
  if (G.stoneOffer != null) leaveStone(); // 고르지 않고 움직이면 발밑 영혼석은 흩어진다
  const took = fn();
  computeFOV(); snapVis(); snapHud(); emitSlots(); // 턴을 넘기지 않으니 화면은 여기서 맞춘다(문·구하기·소모품)
  Anim.take();
  return took;
}

/** 연출 대기열: 사건을 적힌 지연(ms)대로 화면에 보낸다. active = 남은 연출이 있다(입력은 막지 않는다) */
export const Anim = {
  q: [], t: 0,
  get active() { return this.q.length > 0; },
  take() { for (const e of TL.q) this.q.push({ t: this.t + e.t, fn: e.fn }); TL.reset(); this.q.sort((a, b) => a.t - b.t); },
  step(ms) { this.t += ms; while (this.q.length && this.q[0].t <= this.t) this.q.shift().fn(); if (!this.q.length) this.t = 0; },
  clear() { this.q = []; this.t = 0; },
};

/** 화면 한 프레임(초): 입력 → 시간 → 연출 → 자동 걷기·멈춤 표시 */
export const Loop = {
  frame(dt) {
    if (Game.mode === 'dungeon' && !G.over) {
      UI.feedIntent();
      TL.reset(); const n = advance(dt); Anim.take();
      Anim.step(dt * 1000);
      UI.afterTick(n);
    } else { Anim.step(dt * 1000); document.body.classList.remove('frozen'); }
  },
};

export function rescueFollowers() {
  for (const e of G.ents) if (e.npc && e.alive && e.freed && cheb(e.x, e.y, G.player.x, G.player.y) <= 2) {
    e.alive = false; META.newNpcs.push(e.npcData); G.loot.npcs.push(e.npcData.name);
    UI.log(`${jo(e.name, '이가')} 정착지로 향한다.`, 'syn');
  }
  saveMeta();
}

export function descend() {
  if (G.over) return;
  if (G.tile[I(G.player.x, G.player.y)] !== T_STAIRS) return;
  if (G.bossFloor) { returnToTown('boss'); return; }
  Anim.clear(); // 옛 층의 연출(시야·지형 스냅샷)을 새 층에 그리지 않는다
  const p = G.player;
  rescueFollowers();
  G.zf++; p.st = newSt();
  genFloor();
  refreshStats(); p.shield = armorShield();
  UI.exitTarget(); UI.stopAuto();
  View.buildFloor(); UI.floorCard(); UI.syncAll();
  Sfx.play('stairs');
}

export function enterDungeon(zone) {
  const h = META.hero;
  Town.clear(); Game.mode = 'dungeon'; Anim.clear(); // 남은 연출은 버린다
  setR(mulberry32(seedOr(((Date.now() & 0xffffffff) ^ Math.floor(Math.random() * 1e9)) >>> 0)));
  Object.assign(G, { zone, zf: 1, over: false, won: false, nextId: 1, hasteFlip: false, pendingReturn: null, known: h.known, look: h.look, inv: h.inv, eq: h.eq, bag: h.bag, heroBase: h.base, jlook: h.jlook || (h.jlook = newJewelLook()), jknown: h.jknown || (h.jknown = {}), reload: null, aimed: false, lastHit: null, riposte: -1, slots: h.slots, level: h.level || 6, xp: h.xp || 0, sbag: h.sbag, weakKnown: h.weakKnown, ctx: null, curSrc: null, dropHint: 0 });
  for (const k of ALWAYS_KNOWN) G.known[k] = true;
  for (const sl of G.slots) sl.cd = 0;
  G.player = { id: 0, type: 'hero', name: h.name, x: 0, y: 0, hp: h.hp, max: h.max, st: newSt(), alive: true, face: [0, 1], shield: 0 };
  refreshStats();
  G.player.shield = armorShield() + (META.buff === 'feast' ? 6 : 0); META.buff = null;
  G.round = 0; G.auras = {}; G.combatDmg = 0;
  for (const sl of G.slots) { sl.cd = 0; sl.usedRound = sl.redRound = -1; }
  G.stats = { kills: 0, combos: 0, turns: 0, items: 0, stones: 0, chains: 0, best: 0 };
  G.mageOf = ['bolt', pick(['fire', 'frost', 'bolt']), pick(['fire', 'frost']), 'mix'];
  G.loot = { mats: {}, npcs: [] };
  G.zoneFlags = { npc: false, recall: false }; G.perk = h.perk || null; G.sbagMax = h.sbagMax || 3; G.recallArm = false;
  const glow = hearthGlow(); G.glowVision = glow >= GLOW.vision ? 1 : 0;
  startTorch();
  if (glow >= GLOW.shield) G.player.shield += 4;
  genFloor();
  UI.toDungeon(); View.buildFloor(); UI.exitTarget(); UI.floorCard(); UI.syncAll();
  saveMeta();
}

export function returnToTown(reason) {
  document.body.classList.remove('frozen'); // 정착지는 멈춤 표시를 쓰지 않는다
  const h = META.hero, rep = { reason, zone: G.zone, zf: G.zf, loot: {}, npcs: [], hurt: G.player.hp < G.player.max * 0.5, kills: G.stats.kills };
  if (reason === 'death') {
    leaveRelics(); // 입고 있던 픽다트는 그 층에 남는다
    rep.lost = { ...G.loot.mats }; rep.hero = h.name; rep.npcs = G.loot.npcs.slice();
    META.fallen.push({ name: h.name, gen: h.gen, zone: G.zone, zf: G.zf, kills: G.stats.kills, by: G.deathBy ? G.deathBy.who : null }); META.hero = null;
  } else {
    rescueFollowers(); rep.npcs = G.loot.npcs.slice();
    for (const [m, n] of Object.entries(G.loot.mats)) META.mats[m] = (META.mats[m] || 0) + n;
    rep.loot = { ...G.loot.mats };
    h.hp = Math.max(1, G.player.hp); h.max = G.player.max; h.level = G.level; h.xp = G.xp; h.base = G.heroBase;
    if (reason === 'boss') { rep.first = !META.cleared[G.zone - 1]; META.cleared[G.zone - 1] = true; }
  }
  G.over = true; UI.exitTarget(); UI.stopAuto(); Anim.clear();
  saveMeta();
  Town.enter(rep);
}
