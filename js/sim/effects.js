import { enterCell } from '../core/clock.js';
import { cancelIntent, damage, heal } from '../core/combat.js';
import { addCloud } from '../core/elements.js';
import { los } from '../core/fov.js';
import { emitStatus, snapTerrain } from '../core/snap.js';
import { posOf, rad, setPos } from '../core/space.js';
import { G, I, emit, inb, isP, log } from '../core/state.js';
import { C_SMOKE, T_WALL } from '../data/terrain.js';
import { HOOKS } from './acts.js';
import { angDiff, angTo, dist } from './body.js';
import { traitVal } from './classes.js';

/* ================= 스킬 효과 부품 (docs/설계_직업.md §1-7) =================
   u.fx = { 이름: { t: 남은 초, … } } — 막기·되치기·죽음 유예·묶기·도발·강화·약화·다음 공격 강화·연결 …
   G.zones = [{ kind, x, y, r, t, team, p, hit }] — 덫·경계선·치유 구역·조명탄 */

export const enemyOf = (a, b) => a.team !== b.team && a.team !== 'neutral' && b.team !== 'neutral';
/** (x, y) 반경 r 안에서 u와 같은 편(same) 또는 반대편 유닛 */
export function unitsNear(u, x, y, r, same, o2 = {}) {
  const cx = Math.round(x), cy = Math.round(y);
  return G.ents.filter((o) => o.alive && o.px != null && !o.npc && (o2.hidden || !o.hidden) && (same ? o.team === u.team : enemyOf(u, o)) && Math.hypot(o.px - x, o.py - y) <= r + rad(o) * 0.5 && (Math.hypot(o.px - x, o.py - y) < 1 || los(cx, cy, o.x, o.y))); // 벽 너머는 닿지 않는다
}

export function addFx(u, k, t, data = {}) {
  const old = u.fx && u.fx[k];
  if (old) for (const q of ['v', 'half', 'mul', 'n']) if (typeof old[q] === 'number' && typeof data[q] === 'number' && old[q] > data[q]) data[q] = old[q]; // 약한 효과가 강한 효과를 덮지 않는다
  (u.fx ||= {})[k] = { ...(old || {}), ...data, t: Math.max(t, old ? old.t : 0) }; G.intentsDirty = true;
}
export const fxOf = (u, k) => (u.fx && u.fx[k] && u.fx[k].t > 0 ? u.fx[k] : null);

/** 준비 동작 끊기. 보스는 끊기지 않고 힘 모으기가 늘어난다 */
export function interrupt(t, delay = 0.5) {
  if (!t.act || t.act.done) return false;
  if (t.boss) { t.act.wind += delay; emit('interrupt', { id: t.id, boss: true }); return true; }
  cancelIntent(t); emit('interrupt', { id: t.id }); G.intentsDirty = true; return true;
}
export function stun(t, s) { t.st.stun = Math.max(t.st.stun, s); emitStatus(t); if (!isP(t)) cancelIntent(t); }
export const root = (t, s) => { addFx(t, 'root', s); emit('rooted', { id: t.id }); };
export const taunt = (t, by, s) => { if (!t.boss || s >= 1) addFx(t, 'taunt', s, { id: by.id }); };

/** 치유: 시전자의 특성 "생명의 권능"을 더한다 */
export function healBy(u, t, amt) { if (t.alive) heal(t, amt + traitVal(u, 'life')); }
export function shieldTo(t, amt) {
  t.shield = (t.shield || 0) + amt;
  if (isP(t)) emit('shield', { v: t.shield, add: amt }); else emit('pshield', { id: t.id, add: amt });
}
const BAD = ['poison', 'burn', 'bleed', 'frozen', 'stun', 'frac', 'fear'];
export function cleanse(t) { for (const k of BAD) t.st[k] = 0; if (t.fx) { delete t.fx.root; delete t.fx.weak; delete t.fx.silence; delete t.fx.vuln; } emitStatus(t); emit('cleanse', { id: t.id }); }

/** 연결 없이 그 자리로 옮긴다(순간이동·자리 바꾸기): 화면은 바로 선다 */
export function teleport(e, x, y) {
  const ox = e.x, oy = e.y; setPos(e, x, y); e.ppx = e.px; e.ppy = e.py;
  emit('move', { id: e.id, x: Math.round(x), y: Math.round(y), dur: 1, hop: 0, kind: 'tele', seen: 1 }); G.visDirty = true;
  if (isP(e) && (e.x !== ox || e.y !== oy)) enterCell(e); // 등불지기: 새 칸의 줍기·상자·시야
}

/* ---------- 구역 ---------- */
export function addZone(z) { (G.zones ||= []).push({ acc: 0, hit: new Set(), ...z }); G.intentsDirty = true; }
/** 안개: 칸마다 연기(궁수·마법사는 연기 너머로 겨누지 못한다) */
export function fogAt(x, y, r, dur) {
  for (let dy = -Math.ceil(r); dy <= Math.ceil(r); dy++) for (let dx = -Math.ceil(r); dx <= Math.ceil(r); dx++) {
    const cx = Math.round(x) + dx, cy = Math.round(y) + dy; if (!inb(cx, cy) || dx * dx + dy * dy > r * r + 0.5) continue;
    if (G.tile[I(cx, cy)] !== T_WALL) addCloud(I(cx, cy), C_SMOKE, Math.ceil(dur));
  }
  snapTerrain(); emit('smokeburst', { x: Math.round(x), y: Math.round(y) });
}

/** 한 틱: 효과 시간, 구역 */
export function tickEffects(dt) {
  for (const e of G.ents) {
    if (!e.fx) continue;
    for (const [k, f] of Object.entries(e.fx)) { f.t -= dt; if (f.t <= 1e-6) { delete e.fx[k]; G.intentsDirty = true; } }
  }
  if (!G.zones || !G.zones.length) return;
  for (const z of G.zones) {
    z.t -= dt; z.acc += dt;
    const owner = G.ents.find((e) => e.id === z.owner) || { team: z.team };
    if (z.kind === 'trap' || z.kind === 'line') {
      for (const f of unitsNear(owner, z.x, z.y, z.r, false, { hidden: true })) {
        if (z.hit.has(f.id)) continue; z.hit.add(f.id);
        root(f, z.p.root); if (z.p.dmg) damage(f, z.p.dmg, 'hit', { src: owner, label: '덫' });
        if (z.kind === 'trap' && --z.n <= 0) { z.t = 0; break; }
      }
    }
    if (z.kind === 'flare') for (const f of unitsNear(owner, z.x, z.y, z.r, false)) if (f.hidden) { f.hidden = false; G.visDirty = true; }
    if ((z.kind === 'heal' || z.kind === 'sanct') && z.acc >= 1 - 1e-6) {
      z.acc -= 1;
      for (const a of unitsNear(owner, z.x, z.y, z.r, true)) healBy(owner, a, z.p.heal);
      if (z.p.poison) for (const f of unitsNear(owner, z.x, z.y, z.r, false)) { f.st.poison = Math.max(f.st.poison, z.p.poison); emitStatus(f); }
    }
  }
  const n = G.zones.length; G.zones = G.zones.filter((z) => z.t > 0); if (G.zones.length !== n) G.intentsDirty = true;
}
const zoneAt = (e, kind) => (G.zones || []).find((z) => z.kind === kind && Math.hypot(e.px - z.x, e.py - z.y) <= z.r + rad(e) * 0.5 && (kind === 'flare' ? z.team !== e.team : z.team === e.team));

/* ---------- 피해에 붙는 것: damage()가 부른다 ---------- */
const ATTACK = { hit: 1, charge: 1 }, ELEM = { fire: 1, shock: 1, frost: 1, blast: 1 };
/** 들어오는 공격: 막기·되치기·장막(0) · 약점 표식·조명탄(+) · 버팀·방어·성역·맹세(−) · 연결(나눠 받기). 0이면 막힌 것 */
export function incoming(e, amt, kind, src) {
  if (!src || src === e || !enemyOf(src, e) || !(ATTACK[kind] || ELEM[kind])) return amt; // 쏜 궁수가 쓰러져도 날아온 화살은 막는다
  const veil = fxOf(e, 'veil');
  if (veil) { if (--veil.n <= 0) delete e.fx.veil; if (veil.heal) heal(e, veil.heal); emit('block', { id: e.id, what: '장막' }); return 0; }
  if (ATTACK[kind]) {
    const par = fxOf(e, 'parry');
    if (par && dist(e, src) <= 2.2) { emit('parry', { id: e.id }); if (src.alive) counter(e, src, par.mul); return 0; }
    if (par && par.deflect) { emit('block', { id: e.id, what: '튕김' }); return 0; } // 반격 태세: 먼 곳의 화살은 튕긴다
    const gd = fxOf(e, 'guard');
    if (gd && (gd.half >= 180 || angDiff(angTo(e, src), e.ang) <= (gd.half * Math.PI) / 180)) { emit('block', { id: e.id, what: '막기' }); return 0; }
  }
  const vu = fxOf(e, 'vuln'); if (vu) amt += vu.v;
  const fz = zoneAt(e, 'flare'); if (fz) amt += fz.p.vuln || 1;
  let red = 0;
  const df = fxOf(e, 'def'); if (df) red += df.v;
  const sz = zoneAt(e, 'sanct'); if (sz) red += sz.p.def || 1;
  const still = traitVal(e, 'stand'); if (still && (G.clock || 0) - (e.movedAt ?? -9) > 0.25) red += still;
  amt = Math.max(0, amt - red);
  if (fxOf(e, 'oathSelf')) amt = Math.round(amt * 0.7);
  const ln = fxOf(e, 'link'), by = ln && G.ents.find((q) => q.id === ln.id);
  if (by && by.alive && by !== e && amt > 0) { const part = Math.round(amt * ln.share); if (part > 0) { amt -= part; damage(by, part, kind, { src, label: '맹세', raw: true }); } } // 나눠 받는 몫은 수정 없이 그대로(맹세끼리 되풀이하지 않는다)
  return amt;
}
/** 나가는 공격: 약화(절반) · 강화(+) · 특성(기습·원거리·원소 친화) */
export function outgoing(src, e, amt, kind) {
  if (!src || !e || src === e || !(ATTACK[kind] || ELEM[kind])) return amt;
  if (fxOf(src, 'weak')) amt = Math.ceil(amt / 2);
  const up = fxOf(src, 'up'); if (up && ATTACK[kind]) amt += up.v;
  if (ATTACK[kind]) {
    const am = traitVal(src, 'ambush'); if (am && (e.act || (e.whiffT ?? -9) > (G.clock || 0))) amt += am;
    const rg = traitVal(src, 'range'); if (rg && dist(src, e) >= 4) amt += rg;
  }
  const el = traitVal(src, 'elem'); if (el && ELEM[kind]) amt = Math.ceil(amt * el);
  return amt;
}
/** 마지막 버티기(죽음 유예) */
export function lastStand(e, amt) {
  const w = fxOf(e, 'ward');
  if (w && amt >= e.hp) { delete e.fx.ward; emit('ward', { id: e.id }); log('죽음이 한 걸음 비껴갔다.', 'syn'); return Math.max(0, e.hp - 1); }
  return amt;
}
/** 되치기: 등불지기는 무기로, 그 밖은 공격력으로 (sim/skillfx.js가 HOOKS.counter를 채운다) */
function counter(e, src, mul) { if (HOOKS.counter) HOOKS.counter(e, src, mul); }

/** 보호막이 다 깨졌을 때(룬 방벽) */
export function shieldBroke(e) {
  const rw = fxOf(e, 'runeWard'); if (!rw) return;
  delete e.fx.runeWard; const [x, y] = posOf(e);
  emit('freeze', { x: Math.round(x), y: Math.round(y), center: true });
  for (const f of unitsNear(e, x, y, rw.br, false)) damage(f, rw.burst, 'frost', { src: e, label: '룬' });
}
