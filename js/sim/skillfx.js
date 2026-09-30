import { cancelIntent, damage, dir8, push, resistOk, weaponHit } from '../core/combat.js';
import { applyFire, igniteTile, oilBlast, shock } from '../core/elements.js';
import { los } from '../core/fov.js';
import { emitStatus, snapTerrain } from '../core/snap.js';
import { posOf, rad, sweep } from '../core/space.js';
import { G, I, emit, entsAt, inb, isP, log, newSt, standable } from '../core/state.js';
import { CSKILLS } from '../data/class-skills.js';
import { S_ASH, S_GRASS, S_ICE, S_NONE, S_OIL, S_WATER, T_WALL } from '../data/terrain.js';
import { startAct } from './action.js';
import { ACTS, HOOKS } from './acts.js';
import { angTo, dist, faceAng, initBody } from './body.js';
import { loadoutOf, skillParams } from './classes.js';
import { addFx, addZone, cleanse, enemyOf, fogAt, fxOf, healBy, interrupt, root, shieldTo, stun, taunt, teleport, unitsNear } from './effects.js';
import { spawnProj } from './projectile.js';
import { cellsAlong, plus, square3 } from './shapes.js';

/* ================= Class 스킬 실행 (docs/설계_직업.md §4) =================
   useSkill(u, id, x, y): 시전(힘 모으기) → RUN[id](u, P, T). 등불지기·동료가 같은 함수를 쓴다. 쿨타임은 흐른 시간으로만 준다 */

/** 무기 한 번(등불지기는 무기, 그 밖은 공격력) */
export function strike(u, t, mul, o = {}) {
  if (!t || !t.alive) return 0;
  if (isP(u)) { const h0 = t.hp; weaponHit(t, null, { ...o, mul }); return h0 - Math.max(0, t.hp); }
  return damage(t, Math.max(1, Math.round((u.atk || 2) * mul) + (o.bonus || 0)), 'hit', { src: u });
}
HOOKS.counter = (e, src, mul) => strike(e, src, mul, { counter: true });

/** 원소 한 번(칸 기준, 원소 규칙 그대로) */
export function elemAt(u, x, y, elem, dmg, eo = {}) {
  const prev = G.curSrc; G.curSrc = u;
  try {
    // 스킬은 적만 친다. 스킬이 남긴 지형(불붙은 풀·기름 폭발·물을 타는 번개)은 누구에게나 위험하다
    const i = I(x, y), here = entsAt(x, y).filter((e) => enemyOf(u, e));
    if (!inb(x, y) || G.tile[i] === T_WALL) return;
    if (elem === 'fire') { if (G.surf[i] === S_OIL) { oilBlast(x, y); return; } for (const e of here) applyFire(e, dmg); igniteTile(x, y, { noFlash: here.length > 0 }); }
    else if (elem === 'frost') {
      const wasWater = G.surf[i] === S_WATER; let ch = false;
      if (wasWater) { G.surf[i] = S_ICE; ch = true; } if (G.fire[i]) { G.fire[i] = 0; ch = true; }
      emit('freeze', { x, y, water: wasWater, center: true });
      for (const e of here) { const wet = e.st.wet > 0 || wasWater; damage(e, dmg, 'frost', { src: u }); if (e.alive && wet && !eo.noFreeze && resistOk(e, 'frost')) { e.st.frozen = Math.max(e.st.frozen, 4); e.st.wet = 0; e.st.burn = 0; emitStatus(e); cancelIntent(e); } }
      if (ch) snapTerrain();
    } else { if (G.surf[i] === S_WATER || here.some((e) => e.st.wet)) shock(x, y, dmg); else for (const e of here) damage(e, dmg, 'shock', { src: u }); emit('zap', { x, y }); }
  } finally { G.curSrc = prev; }
}
const CYCLE = ['fire', 'frost', 'bolt'];

/** 화살·창: 투사체 */
function shoot(u, ang, o, onHit) {
  const [x, y] = posOf(u);
  spawnProj({ owner: u.id, team: u.team, x, y, ang, speed: o.speed || 16, range: o.range || 7, pierce: !!o.pierce, look: o.look || 'arrow', onHit });
}
/** 돌진: 몸을 뚫고 지나가며 길 위의 적에게 onPass */
function dashLine(u, ang, d, onPass) {
  const [x0, y0] = posOf(u), r = sweep(u, Math.cos(ang) * d, Math.sin(ang) * d, { noBodies: true });
  const hit = [];
  for (const f of G.ents) {
    if (!f.alive || f.px == null || !enemyOf(u, f) || f.hidden) continue;
    const vx = r.x - x0, vy = r.y - y0, L = Math.hypot(vx, vy) || 1, k = Math.max(0, Math.min(1, ((f.px - x0) * vx + (f.py - y0) * vy) / (L * L)));
    if (Math.hypot(x0 + vx * k - f.px, y0 + vy * k - f.py) <= rad(f) + 0.6) hit.push(f);
  }
  teleport(u, r.x, r.y); const r2 = sweep(u, 0.001, 0); teleport(u, r2.x, r2.y); emit('dash', { id: u.id }); // 몸 속에서 멈추지 않는다
  if (onPass) for (const f of hit) onPass(f);
}
const nearestFoe = (u, r = 99) => G.ents.filter((f) => f.alive && f.px != null && enemyOf(u, f) && !f.hidden && !f.npc && dist(u, f) <= r).sort((a, b) => dist(u, a) - dist(u, b))[0] || null;
function spawnDecoy(u, x, y, P) {
  const d = { id: G.nextId++, type: 'npc', decoy: true, ally: true, npc: false, team: u.team, ctrl: 'ai', name: '미끼', npcData: { name: '미끼', job: 'pilgrim', look: { skin: 0xd8c0a0, hair: 0x2a2a30, cloth: 0x8a6ab0 } }, x: Math.round(x), y: Math.round(y), hp: P.hp, max: P.hp, st: newSt(), alive: true, awake: true, face: [0, 1], lifeT: P.dur, burst: P.burst, owner: u.id };
  G.ents.push(d); initBody(d);
  emit('spawn', { e: { ...d, st: { ...d.st } }, seen: 1 });
  for (const f of unitsNear(u, x, y, P.r, false)) taunt(f, d, P.dur);
}

/** 스킬마다: (u, P = 최종 수치, T = { t: 대상 유닛, x, y, ang }) */
const RUN = {
  f_block: (u, P) => addFx(u, 'guard', P.dur, { half: P.half }),
  f_taunt: (u, P) => { for (const f of unitsNear(u, u.px, u.py, P.r, false)) taunt(f, u, P.dur); addFx(u, 'def', P.dur, { v: P.def }); emit('ring', { x: u.x, y: u.y, elem: 'push' }); },
  f_bash: (u, P, T) => { strike(u, T.t, P.mul); if (T.t.alive) { interrupt(T.t); push(T.t, ...dir8(u, T.t), P.n); } },
  r_stab: (u, P, T) => { const t = T.t, w = t.act && !t.act.done, lo = P.low && t.hp * 2 < t.max; strike(u, t, P.mul * (w || lo ? P.x : 1)); if (w) interrupt(t); },
  r_evade: (u, P) => addFx(u, 'parry', P.dur, { mul: P.mul }),
  r_dash: (u, P, T) => dashLine(u, T.ang, P.dist, (f) => strike(u, f, P.mul)),
  ra_pierce: (u, P, T) => shoot(u, T.ang, { range: 7, pierce: true, look: 'quarrel' }, (f) => strike(u, f, P.mul, { bonus: P.bonus })),
  ra_trap: (u, P, T) => addZone({ kind: 'trap', x: T.x, y: T.y, r: 0.7, t: P.dur, team: u.team, owner: u.id, p: { root: P.root, dmg: P.dmg }, n: P.n }),
  ra_leap: (u, P) => { const f = nearestFoe(u, 8); dashLine(u, f ? angTo(f, u) : u.ang + Math.PI, P.dist); const g = nearestFoe(u, 8); if (g) shoot(u, angTo(u, g), { range: 8 }, (h) => strike(u, h, P.mul)); },
  w_fire: (u, P, T) => { const cells = plus(T.x, T.y); emit('meteor', { tiles: cells }); for (const [x, y] of cells) { elemAt(u, x, y, 'fire', P.dmg); if (P.burn) for (const e of entsAt(x, y)) if (enemyOf(u, e) && e.alive) { e.st.burn += P.burn; emitStatus(e); } } },
  w_chain: (u, P, T) => { let cur = T.t; const done = new Set(); elemAt(u, cur.x, cur.y, 'bolt', P.dmg); done.add(cur.id); for (let k = 0; k < P.jumps; k++) { const n = G.ents.filter((f) => f.alive && f.px != null && enemyOf(u, f) && !done.has(f.id) && dist(cur, f) <= 2.5).sort((a, b) => dist(cur, a) - dist(cur, b))[0]; if (!n) break; emit('arc', { a: [cur.x, cur.y], b: [n.x, n.y] }); damage(n, Math.max(1, Math.round(P.dmg * P.ratio)), 'shock', { src: u }); done.add(n.id); cur = n; } },
  w_ray: (u, P, T) => { const cells = cellsAlong(u.px, u.py, T.ang, P.range); emit('frostfall', { tiles: cells }); for (const [x, y] of cells) elemAt(u, x, y, 'frost', P.dmg); },
  c_heal: (u, P, T) => { healBy(u, T.t, P.heal); if (P.cleanse) cleanse(T.t); },
  c_shield: (u, P, T) => shieldTo(T.t, P.shield),
  c_ward: (u, P, T) => addFx(T.t, 'ward', P.ward),
  b_disc: (u, P, T) => { damage(T.t, P.dmg, 'impact', { src: u, label: '불협화음' }); if (T.t.alive) { interrupt(T.t, P.delay); if (P.stun) stun(T.t, P.stun); } },
  b_song: (u, P) => { for (const a of unitsNear(u, u.px, u.py, P.r, true)) { addFx(a, 'up', P.dur, { v: P.up }); addFx(a, 'haste', P.dur, { v: P.haste }); } emit('ring', { x: u.x, y: u.y, elem: 'push' }); },
  b_fog: (u, P, T) => fogAt(T.x, T.y, P.r, P.dur),

  g_wall: (u, P) => { addFx(u, 'guard', P.guard, { half: 180 }); for (const f of unitsNear(u, u.px, u.py, P.r, false)) taunt(f, u, P.taunt); },
  g_charge: (u, P, T) => dashLine(u, T.ang, P.dist, (f) => { strike(u, f, P.mul); if (f.alive) { interrupt(f); push(f, ...dir8(u, f), P.n); } }),
  a_mark: (u, P, T) => addFx(T.t, 'vuln', P.dur, { v: P.vuln }),
  a_step: (u, P, T) => { const t = T.t, a = angTo(u, t); for (const da of [0, 0.8, -0.8, 1.6, -1.6]) { const bx = t.px + Math.cos(a + da) * 0.9, by = t.py + Math.sin(a + da) * 0.9; if (standable(Math.round(bx), Math.round(by)) && !entsAt(Math.round(bx), Math.round(by)).some((e) => e !== t && e !== u)) { teleport(u, bx, by); faceAng(u, angTo(u, t)); break; } } if (dist(u, t) <= 1.9) strike(u, t, P.mul); }, // 뒤(없으면 옆)에 설 자리가 있어야 찌른다
  s_aim: (u, P, T) => shoot(u, T.ang, { range: P.range, pierce: true, look: 'quarrel', speed: 20 }, (f) => strike(u, f, P.mul)),
  s_volley: (u, P, T) => { for (const f of unitsNear(u, T.x, T.y, P.r, false)) { emit('proj', { kind: 'arrow', from: [u.x, u.y], to: [f.x, f.y], dur: 200 }); strike(u, f, P.mul); } },
  am_flood: (u, P, T) => {
    const s = P.size;
    for (let dy = -s; dy <= s; dy++) for (let dx = -s; dx <= s; dx++) { const x = T.x + dx, y = T.y + dy; if (!inb(x, y) || G.tile[I(x, y)] === T_WALL) continue; const i = I(x, y); G.surf[i] = S_WATER; G.fire[i] = 0; for (const e of entsAt(x, y)) { e.st.wet = 3; e.st.burn = 0; emitStatus(e); } }
    snapTerrain(); emit('splash', { x: T.x, y: T.y });
    for (const f of unitsNear(u, T.x, T.y, s + 0.5, false)) push(f, ...dir8({ px: T.x, py: T.y }, f), P.n);
  },
  am_meteor: (u, P, T) => { const cells = square3(T.x, T.y); emit('meteor', { tiles: cells }); emit('shake', { a: 0.5 }); for (const [x, y] of cells) elemAt(u, x, y, 'fire', P.dmg); },
  hp_radiance: (u, P) => { for (const a of unitsNear(u, u.px, u.py, P.r, true)) healBy(u, a, P.heal); emit('ring', { x: u.x, y: u.y, elem: 'push' }); },
  hp_sanct: (u, P, T) => addZone({ kind: 'sanct', x: T.x, y: T.y, r: P.r, t: P.dur, team: u.team, owner: u.id, p: { heal: P.heal } }),
  ma_cresc: (u, P) => RUN.b_song(u, P),
  ma_silence: (u, P) => { for (const f of unitsNear(u, u.px, u.py, P.r, false)) { interrupt(f, 1); stun(f, f.boss ? P.stun / 2 : P.stun); } emit('ring', { x: u.x, y: u.y, elem: 'push' }); },

  sm_riposte: (u, P) => addFx(u, 'parry', P.dur, { mul: P.mul, deflect: 1 }),
  sm_whirl: (u, P) => { emit('ring', { x: u.x, y: u.y, elem: 'push' }); for (const f of unitsNear(u, u.px, u.py, P.r, false)) { strike(u, f, P.mul); if (!f.alive) continue; if (P.bleed) { f.st.bleed += P.bleed; emitStatus(f); } if (P.taunt) taunt(f, u, P.taunt); } },
  wd_line: (u, P, T) => addZone({ kind: 'line', x: T.x, y: T.y, r: P.r, t: P.dur, team: u.team, owner: u.id, p: { root: P.root } }),
  wd_spear: (u, P, T) => shoot(u, T.ang, { range: P.range, pierce: !!P.pierce, look: 'quarrel', speed: 14 }, (f) => { strike(u, f, P.mul); if (!f.alive) return; root(f, P.root); if (P.taunt) taunt(f, u, P.taunt); }),
  rk_ward: (u, P) => { shieldTo(u, P.shield); addFx(u, 'guard', P.guard, { half: 180 }); addFx(u, 'runeWard', 20, { burst: P.burst, br: P.br }); },
  rk_runes: (u, P) => addFx(u, 'runes', P.dur, { dmg: P.dmg, sh: P.sh, i: 0 }),
  pa_oath: (u, P, T) => { if (T.t === u) addFx(u, 'oathSelf', P.dur); else addFx(T.t, 'link', P.dur, { id: u.id, share: P.share }); if (P.shield) shieldTo(T.t, P.shield); },
  pa_smite: (u, P) => addFx(u, 'next', 8, { mul: P.mul, stun: P.stun, heal: P.heal, r: P.r }),
  wl_duel: (u, P, T) => { taunt(T.t, u, P.dur); addFx(T.t, 'vuln', P.dur, { v: P.vuln }); if (P.def) addFx(u, 'def', P.dur, { v: P.def }); },
  wl_rally: (u, P) => { for (const a of unitsNear(u, u.px, u.py, P.r, true)) { shieldTo(a, P.shield); addFx(a, 'up', P.dur, { v: P.up }); } emit('horn', { id: u.id }); },
  st_venom: (u, P) => addFx(u, 'venom', P.dur, { poison: P.poison }),
  st_net: (u, P, T) => shoot(u, T.ang, { range: P.range, look: 'pebble', speed: 12 }, (f) => { const hit = P.area ? unitsNear(u, f.px, f.py, P.area, false) : [f]; for (const h of hit) { root(h, P.root); addFx(h, 'vuln', P.root, { v: P.vuln }); } }),
  nb_edge: (u, P, T) => { const t = T.t, x = t.x, y = t.y; strike(u, t, P.mul); elemAt(u, x, y, 'bolt', P.dmg); },
  nb_blink: (u, P, T) => { const x0 = u.x, y0 = u.y; teleport(u, T.x, T.y); for (const [x, y] of plus(x0, y0)) elemAt(u, x, y, 'frost', P.dmg, { noFreeze: !P.freeze }); if (P.next) addFx(u, 'next', 6, { mul: P.next }); },
  sp_veil: (u, P) => { for (const a of unitsNear(u, u.px, u.py, P.r, true)) addFx(a, 'veil', P.dur, { n: P.n, heal: P.heal }); },
  sp_drain: (u, P, T) => { const got = damage(T.t, P.dmg, 'impact', { src: u, label: '흡수' }), h = Math.max(1, Math.round(got * P.ratio)); healBy(u, u, h); const low = unitsNear(u, u.px, u.py, 6, true).filter((a) => a !== u).sort((a, b) => a.hp / a.max - b.hp / b.max)[0]; if (low) healBy(u, low, h); },
  tr_decoy: (u, P, T) => spawnDecoy(u, T.x, T.y, P),
  tr_swap: (u, P, T) => { const t = T.t, [ux, uy] = posOf(u), [tx, ty] = posOf(t); teleport(u, tx, ty); teleport(t, ux, uy); if (enemyOf(u, t)) { interrupt(t); if (P.stun) stun(t, P.stun); } if (P.next) addFx(u, 'next', 6, { mul: P.next }); },
  aa_storm: (u, P, T) => { const seen = new Set(); for (const f of unitsNear(u, T.x, T.y, P.r, false)) { const k = f.y * G.W + f.x; if (seen.has(k)) continue; seen.add(k); elemAt(u, f.x, f.y, 'bolt', P.dmg); } emit('skybolt', { tiles: [[T.x, T.y]] }); },
  aa_elem: (u, P, T) => { let i = 0; shoot(u, T.ang, { range: P.range, pierce: !!P.pierce }, (f) => { const x = f.x, y = f.y; strike(u, f, P.mul); elemAt(u, x, y, CYCLE[i++ % 3], P.dmg); }); },
  wh_seal: (u, P, T) => shoot(u, T.ang, { range: P.range }, (f) => { strike(u, f, P.mul); if (f.alive) { interrupt(f); addFx(f, 'silence', P.dur); } if (P.heal) healBy(u, u, P.heal); }),
  wh_bless: (u, P, T) => { emit('proj', { kind: 'arrow', from: [u.x, u.y], to: [T.t.x, T.t.y], dur: 200 }); healBy(u, T.t, P.heal); cleanse(T.t); },
  sc_flare: (u, P, T) => { addZone({ kind: 'flare', x: T.x, y: T.y, r: P.r, t: P.dur, team: u.team, owner: u.id, p: { vuln: P.vuln } }); emit('portal', { x: T.x, y: T.y }); },
  sc_mark: (u, P, T) => addFx(T.t, 'vuln', P.dur, { v: P.vuln }),
  dr_vine: (u, P, T) => {
    for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) { const x = T.x + dx, y = T.y + dy; if (inb(x, y) && dx * dx + dy * dy <= P.r * P.r + 0.5 && (G.surf[I(x, y)] === S_NONE || G.surf[I(x, y)] === S_ASH) && G.tile[I(x, y)] !== T_WALL) G.surf[I(x, y)] = S_GRASS; }
    snapTerrain();
    for (const f of unitsNear(u, T.x, T.y, P.r, false)) { root(f, P.root); if (P.dmg) damage(f, P.dmg, 'impact', { src: u, label: '덩굴' }); }
    if (P.heal) for (const a of unitsNear(u, T.x, T.y, P.r, true)) healBy(u, a, P.heal);
  },
  dr_bloom: (u, P, T) => addZone({ kind: 'heal', x: T.x, y: T.y, r: P.r, t: P.dur, team: u.team, owner: u.id, p: { heal: P.heal, poison: P.poison } }),
  en_hex: (u, P, T) => { for (const f of P.r ? unitsNear(u, T.t.px, T.t.py, P.r, false) : [T.t]) { addFx(f, 'weak', P.dur); addFx(f, 'vuln', P.dur, { v: P.vuln }); } },
  en_haste: (u, P, T) => { addFx(T.t, 'haste', P.dur, { v: P.haste }); if (P.elem) addFx(T.t, 'runes', P.dur, { dmg: P.elem, sh: 0, i: 0 }); },
  or_mend: (u, P, T) => { healBy(u, T.t, P.heal); addFx(T.t, 'ward', P.ward); },
  or_foresee: (u, P) => { addFx(u, 'foresee', P.dur, { r: P.r, slow: P.slow }); if (P.shield) for (const a of unitsNear(u, u.px, u.py, P.r, true)) shieldTo(a, P.shield); },
};
export const SKILL_IDS_RUNNABLE = Object.keys(RUN);

/** 무기 적중 뒤: 원소 룬 · 독 칼날 (combat.js weaponHit가 부른다) */
export function afterWeaponHit(u, t) {
  const rn = fxOf(u, 'runes');
  if (rn && t) { elemAt(u, t.x, t.y, CYCLE[rn.i++ % 3], rn.dmg); if (rn.sh) shieldTo(u, rn.sh); }
  const vn = fxOf(u, 'venom');
  if (vn && t && t.alive) { t.st.poison = Math.max(t.st.poison, vn.poison); emitStatus(t); }
}

/* ---------- 시전 ---------- */
/** 스킬을 쓸 수 있는가: 장착했고, 쿨타임이 끝났고, 행동 중이 아니다. 대상 칸(x, y)이 맞는가 */
export function skillTarget(u, id, x, y) {
  const P = skillParams(u.skillInfo[id], u.build), [ux, uy] = posOf(u);
  if (P.tgt === 'self') return { t: u, x: u.x, y: u.y, ang: u.ang };
  if (x == null) return null;
  const d = Math.hypot(x - ux, y - uy), ang = Math.atan2(y - uy, x - ux);
  if (P.tgt === 'dir') return x === u.x && y === u.y ? null : { x, y, ang };
  if (d > P.r + 0.6 || !los(u.x, u.y, x, y)) return null;
  if (P.tgt === 'tile') return standable(x, y) && !(CSKILLS[id].empty && G.ents.some((e) => e.alive && e.x === x && e.y === y)) ? { x, y, ang } : null; // 문·벽은 안 되고, 옮겨 가는 스킬은 빈 칸만
  const want = (e) => e.alive && e.px != null && !e.hidden && (P.tgt === 'foe' ? enemyOf(u, e) && !e.npc : e.team === u.team && !e.decoy);
  const t = entsAt(x, y).find(want) || G.ents.filter((e) => want(e) && Math.hypot(e.px - x, e.py - y) < 0.8).sort((a, b) => Math.hypot(a.px - x, a.py - y) - Math.hypot(b.px - x, b.py - y))[0];
  return t ? { t, x: t.x, y: t.y, ang: angTo(u, t) } : null;
}
export const skillReady = (u, id) => !!(u.build && u.build.loadout.includes(id) && !(u.scd[id] > 1e-6) && !(u.act && !u.act.done) && u.alive && !(u.st.frozen > 0 || u.st.stun > 0));

export function useSkill(u, id, x, y) {
  if (!skillReady(u, id)) return false;
  const T = skillTarget(u, id, x, y); if (!T) return false;
  const P = skillParams(u.skillInfo[id], u.build);
  u.scd[id] = P.cd;
  if (T.ang != null && P.tgt !== 'self') faceAng(u, T.ang);
  startAct(u, 'skill', { wind: P.cast, recover: 0, id, T, P: P.p, cd: u.cd, fx: 'skillCast' });
  emit('skillName', { id: u.id, name: CSKILLS[id].name, icon: CSKILLS[id].icon });
  return true;
}
ACTS.skill = {
  resolve(u, a) {
    if (a.T.t && !a.T.t.alive) { u.scd[a.id] = 0; return; } // 시전 중 대상이 쓰러지면 쿨타임을 돌려준다
    if (a.T.t && a.T.t !== u) { a.T.x = a.T.t.x; a.T.y = a.T.t.y; if (CSKILLS[a.id].tgt !== 'ally') a.T.ang = angTo(u, a.T.t); }
    RUN[a.id](u, a.P, a.T);
    if (isP(u)) log(`${CSKILLS[a.id].icon} ${CSKILLS[a.id].name}.`, 'info');
  },
};

/** 쿨타임·미끼(틱마다) */
export function tickSkills(dt) {
  for (const e of G.ents) {
    if (e.scd) for (const k in e.scd) if (e.scd[k] > 0) e.scd[k] = Math.max(0, e.scd[k] - dt);
    if (e.decoy && e.alive && (e.lifeT -= dt) <= 0) {
      e.alive = false; emit('vanish', { id: e.id });
      if (e.burst) { const o = G.ents.find((q) => q.id === e.owner) || e; for (const f of unitsNear(o, e.px, e.py, 1.5, false)) damage(f, e.burst, 'blast', { src: o, label: '미끼' }); emit('explosion', { x: e.x, y: e.y, elem: 'fire', small: true }); }
    }
  }
}

/* ---------- AI: 봇·파티가 쓰는 때 (data/class-skills.js ai) ---------- */
export function aiPick(u) {
  if (!u.build || (u.act && !u.act.done)) return null;
  const foes = G.ents.filter((f) => f.alive && f.px != null && enemyOf(u, f) && !f.hidden && !f.npc && f.awake !== false);
  if (!foes.length) return null;
  const allies = G.ents.filter((a) => a.alive && a.px != null && a.team === u.team && !a.decoy && !a.npc);
  for (const L of loadoutOf(u)) {
    if (!skillReady(u, L.id)) continue;
    const S = CSKILLS[L.id], P = L.p, reach = L.tgt === 'self' ? (P.r || 2.5) : L.r || 6;
    const near = foes.filter((f) => dist(u, f) <= reach + 0.4).sort((a, b) => dist(u, a) - dist(u, b));
    const at = (t) => (L.tgt === 'self' ? [u.x, u.y] : [t.x, t.y]);
    let t = null;
    switch (S.ai) {
      case 'foe': t = near[0]; break;
      case 'close': t = foes.find((f) => dist(u, f) <= 1.8) && (L.tgt === 'self' ? u : near[0] || foes[0]); if (t && L.tgt === 'tile') { const a = angTo(foes.find((f) => dist(u, f) <= 1.8), u); return { id: L.id, x: Math.round(u.px + Math.cos(a) * 4), y: Math.round(u.py + Math.sin(a) * 4) }; } break;
      case 'winding': t = near.find((f) => f.act && !f.act.done); break;
      case 'aiming': t = near.find((f) => f.act && !f.act.done && (f.act.kind === 'aim' || f.act.kind === 'cast')); break;
      case 'incoming': t = foes.some((f) => f.act && !f.act.done && ((f.act.target === u.id && dist(u, f) <= 2) || (f.act.tele && f.act.tele.cells.some(([x, y]) => x === u.x && y === u.y)))) ? u : null; break;
      case 'crowd': { const c = near.find((f) => foes.filter((g) => dist(f, g) <= 1.8).length >= 2); t = c && (L.tgt === 'self' ? (near.length >= 2 ? u : null) : c); break; }
      case 'hurt': t = allies.filter((a) => a.hp < a.max * 0.65 && dist(u, a) <= (L.tgt === 'self' ? P.r || 5 : L.r) + 0.4).sort((a, b) => a.hp / a.max - b.hp / b.max)[0]; if (t && L.tgt === 'self') t = u; break;
      case 'low': t = allies.find((a) => a.hp < a.max * 0.4 && dist(u, a) <= L.r + 0.4); break;
      case 'fight': t = foes.some((f) => dist(u, f) <= 6) ? (L.tgt === 'ally' ? u : L.tgt === 'self' ? u : near[0] || null) : null; break;
    }
    if (!t) continue;
    if (L.tgt === 'ally' && t.team !== u.team) t = u;
    const [x, y] = at(t);
    if (skillTarget(u, L.id, x, y)) return { id: L.id, x, y };
  }
  return null;
}
