import { catOf, kindOf } from '../data/enemies.js';
import { APPEAR, ITEMS } from '../data/items.js';
import { cheb } from '../util/grid.js';
import { mulberry32, pick, rand, ri, seedOr, setR, shuffle } from '../util/rng.js';
import { allyAct, enemyAct } from './ai.js';
import { heal } from './combat.js';
import { envTick } from './elements.js';
import { computeFOV, distMap } from './fov.js';
import { calcStats, newJewelLook, starterKit, tickWorn } from './gear.js';
import { addItem } from './items.js';
import { genFloor, mkEnemy } from './mapgen.js';
import { META, saveMeta } from './meta.js';
import { emitIntents, emitSlots, snapHud, snapVis } from './snap.js';
import { G, I, TL, emit, entAt, isFoe, log, newSt, seesEnt, standable } from './state.js';
import { endRound, inCombat, tickStones, withCtx } from './stones.js';
import { burnTorch } from './torch.js';

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
  G.stats = { kills: 0, combos: 0, turns: 0, items: 0, stones: 0, chains: 0, best: 0 };
  G.mageOf = ['bolt', pick(['fire', 'frost', 'bolt']), pick(['fire', 'frost']), pick(['frost', 'bolt', 'fire']), 'mix'];
  const kit = starterKit(); G.eq = kit.eq; G.bag = kit.bag; G.heroBase = 30; G.jlook = newJewelLook(); G.jknown = {}; G.ps = calcStats(G.eq);
  G.slots = Array.from({ length: 6 }, () => ({ color: null, stone: null, cd: 0 }));
  G.sbag = []; G.weakKnown = {}; G.ctx = null; G.curSrc = null; G.dropHint = 0; G.zoneFlags = { npc: false, recall: false }; G.perk = null; G.round = 0; G.auras = {}; G.combatDmg = 0; G.glowVision = 0; G.recallArm = false;
  G.torchMax = 100; G.torch = 100;
  genFloor();
}

/* ================= 휴식 · 방랑하는 적 · 처음 보는 적 (docs/설계_던전_확장.md §3.3 · §4.4) ================= */
/** 휴식 한 턴: 횃불을 한 번 더 태우고(모두 1), 3턴마다 HP 1, 가끔 방랑하는 무리가 온다 */
function restTick() {
  const p = G.player; burnTorch(1);
  G.restN = (G.restN || 0) + 1;
  if (G.restN % 3 === 0 && p.hp < p.max && !p.st.poison && !p.st.burn) heal(p, 1);
  if (rand() < ((G.torch ?? 100) < 25 ? 0.04 : 0.02)) wanderers();
}
/** 보이지 않는 먼 방에 무리 하나가 생겨 깨어 다가온다 */
export function wanderers() {
  const p = G.player, rooms = (G.rooms || []).filter((r) => cheb(r.cx, r.cy, p.x, p.y) >= 8 && !G.vis[I(r.cx, r.cy)]);
  if (!rooms.length || !G.theme) return false;
  const r = pick(rooms), [type, cnt] = pick(G.theme.packs.filter(([t]) => t !== 'leech'));
  let n = 0;
  for (let k = 0; k < cnt * 12 && n < cnt; k++) {
    const x = ri(r.x, r.x + r.w - 1), y = ri(r.y, r.y + r.h - 1);
    if (!standable(x, y) || entAt(x, y)) continue;
    const e = mkEnemy(type, x, y, G.theme); e.awake = true; G.ents.push(e); n++;
    emit('spawn', { e: { ...e, st: { ...e.st } }, seen: 0 });
  }
  if (n) log('어디선가 발소리가 다가온다.', 'bad');
  return n > 0;
}
/** 처음 보는 적: 한 번 알리고 기억한다 */
export function noticeFoes() {
  if (!META) return;
  const seen = (META.seenFoes ||= []);
  for (const e of G.ents) {
    if (!e.alive || !isFoe(e) || e.npc || !seesEnt(e)) continue;
    const k = e.boss || kindOf(e); if (seen.includes(k)) continue;
    seen.push(k); (META.foeBook ||= {})[k] = { name: e.name, cat: catOf(e), hp: e.max, atk: e.atk }; saveMeta(); e.firstSeen = true;
    emit('firstSeen', { id: e.id, name: e.name }); log(`처음 보는 적: ${e.name}.`, 'info');
  }
}

/* ================= 턴 ================= */
export function endTurn() {
  const p = G.player;
  burnTorch();
  if (p.st.haste > 0 && !G.hasteFlip) { G.hasteFlip = true; computeFOV(); snapVis(); emitIntents(); snapHud(); return; }
  G.hasteFlip = false;
  worldTick();
}

export function worldTick() {
  G.stats.turns++;
  tickStones(); // 내 턴이 끝났다: 영혼석 쿨타임 1 감소
  tickWorn(); // 입고 지낸 장비의 정체
  if (G.ps && G.ps.regen && G.stats.turns % 2 === 0 && G.player.hp < G.player.max && !inCombat()) heal(G.player, 1); // 재생 목걸이
  computeFOV(); snapVis();
  const p = G.player;
  G.tickMoveEnd = TL.cur + 110;
  const dm = distMap(p.x, p.y);
  for (const a of G.ents.filter((e) => e.alive && e.ally)) if (a.alive && !G.over) allyAct(a, dm);
  const foes = G.ents.filter((e) => e.alive && isFoe(e)).sort((a, b) => cheb(a.x, a.y, p.x, p.y) - cheb(b.x, b.y, p.x, p.y));
  for (const e of foes) {
    if (G.over) break; if (!e.alive) continue;
    if (e.speed === 'slow' && e.awake) { e.slowSkip = !e.slowSkip; if (e.slowSkip) continue; } // 느림: 두 턴에 한 번
    G.curSrc = e; e.didAttack = false; withCtx('enemy', () => enemyAct(e, dm));
    if (e.speed === 'fast' && e.alive && e.awake && !e.didAttack && !G.over) withCtx('enemy', () => enemyAct(e, dm)); // 빠름: 한 번 더(공격은 한 번)
    G.curSrc = null;
  }
  if (!G.over) envTick();
  if (G.resting && !G.over) restTick(); // 쉬기: 켜 둔 동안 턴마다(끄는 것은 입력 쪽)
  if (p.alive && G.stats.turns % 6 === 0 && p.hp < p.max && !p.st.poison && !p.st.burn) { p.hp++; emit('hp', { id: 0, hp: p.hp, max: p.max }); }
  computeFOV(); snapVis(); noticeFoes(); endRound(); emitIntents(); snapHud(); emitSlots();
  // 귀환 두루마리: 빛이 모인 한 턴이 지나면 사라진다
  if (G.recallArm && p.alive && !G.over) { G.recallArm = false; emit('poof', { x: p.x, y: p.y }); log('빛에 싸여 정착지로 돌아간다.', 'syn'); G.pendingReturn = 'recall'; }
}
