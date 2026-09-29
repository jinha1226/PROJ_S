import { armorShield } from './core/combat.js';
import { detect, initFree, spendAction, startCombat } from './core/free.js';
import { refreshStats, revealAll } from './core/gear.js';
import { genFloor } from './core/mapgen.js';
import { META, saveMeta } from './core/meta.js';
import { endTurn } from './core/run.js';
import { G, Game, I, SETTINGS, TL, newSt, setFreeSetting, standable } from './core/state.js';
import { SLOTS } from './data/gear.js';
import { T_STAIRS } from './data/terrain.js';
import { Sfx } from './render/sfx.js';
import { View } from './render/view.js';
import { Town } from './town/town.js';
import { UI } from './ui/ui.js';
import { cheb } from './util/grid.js';
import { mulberry32, pick, seedOr, setR } from './util/rng.js';
import { jo } from './util/text.js';

/* 한 번의 행동 = 로직 해결 → 연출 재생 */
/** 원형 턴제: 행동 하나(공격·스킬·소모품)를 해결하고, 탐험이면 발견을 확인한다 */
function freeAct(fn) {
  TL.reset(); G.hurt = false;
  const wasCombat = !!G.fc, took = fn();
  if (took && wasCombat && G.fc && G.fc.side === 'player') spendAction();
  if (!G.fc && !G.over) { const k = detect(); if (k) startCombat(k); }
  Anim.start();
  return took;
}
/** 원형 턴제: 걷기·턴 넘기기처럼 행동을 쓰지 않는 일 */
export function freeRun(fn) {
  if (Anim.active || G.over) return false;
  TL.reset(); G.hurt = false;
  const r = fn();
  if (!G.fc && !G.over) { const k = detect(); if (k) startCombat(k); }
  Anim.start();
  return r;
}
export function act(fn) {
  if (G.free && Game.mode === 'dungeon') { if (Anim.active || G.over) return false; return freeAct(fn); }
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
  if (G.free) initFree();
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
  G.free = SETTINGS.free; G.fc = null;
  genFloor();
  if (G.free) initFree();
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

/** 격자 ↔ 원형 턴제 전환. 던전이면 그 자리에서 바꾼다 */
export function toggleMode() {
  if (Anim.active) return false;
  const v = !SETTINGS.free; setFreeSetting(v);
  if (Game.mode === 'dungeon' && !G.over) {
    G.free = v; G.fc = null;
    if (v) initFree();
    else { // 칸 중심으로 되돌린다(한 칸에 둘이면 가까운 빈 칸으로)
      const taken = new Set();
      for (const e of G.ents) {
        if (!e.alive) continue;
        let x = Math.round(e.px ?? e.x), y = Math.round(e.py ?? e.y);
        if (taken.has(I(x, y)) || !standable(x, y)) { outer: for (let r = 1; r <= 3; r++) for (let dy = -r; dy <= r; dy++) for (let dx = -r; dx <= r; dx++) { const nx = x + dx, ny = y + dy; if (standable(nx, ny) && !taken.has(I(nx, ny))) { x = nx; y = ny; break outer; } } }
        e.px = x; e.py = y; e.x = x; e.y = y; taken.add(I(x, y));
      }
    }
    UI.exitTarget(); View.buildFloor(); UI.syncAll(); UI.freeReset?.();
    if (v) freeRun(() => { const k = detect(); if (k) startCombat(k); });
  }
  return v;
}
