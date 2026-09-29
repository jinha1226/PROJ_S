import { HEX } from '../data/colors.js';
import { MAGE } from '../data/enemies.js';
import { T_DOOR, T_OPEN, T_STAIRS } from '../data/terrain.js';
import { D8 } from '../util/grid.js';
import { chargePath } from './ai.js';
import { canSee, lineTiles } from './fov.js';
import { gearCss, gearName } from './gear.js';
import { G, I, emit, entAt, inb, isP, seesEnt } from './state.js';

/* ================= 스냅샷 사건 ================= */
export function snapTerrain() { emit('terrain', { tile: G.tile.slice(), surf: G.surf.slice(), fire: G.fire.slice(), cloud: G.cloud.slice(), cloudT: G.cloudT.slice() }); }

export function snapVis() { emit('vis', { vis: G.vis.slice(), seen: G.seen.slice(), ents: G.ents.filter((e) => e.alive).map((e) => [e.id, seesEnt(e) ? 1 : 0]) }); }

export function emitStatus(e) { emit('status', { id: e.id, st: { ...e.st } }); }

export function snapHud() {
  const p = G.player, i = I(p.x, p.y); let door = null, closedDoor = null, rescue = null;
  for (const [dx, dy] of D8) { const x = p.x + dx, y = p.y + dy; if (inb(x, y) && G.tile[I(x, y)] === T_OPEN && !entAt(x, y) && !G.items.has(I(x, y))) { door = [x, y]; break; } }
  for (const [dx, dy] of D8) { const x = p.x + dx, y = p.y + dy; if (!inb(x, y)) continue; const j = I(x, y); if (!closedDoor && G.tile[j] === T_DOOR) closedDoor = [x, y]; const e = entAt(x, y); if (!rescue && e?.npc && !e.freed) rescue = [x, y]; }
  const enemyCount = G.ents.filter((e) => e.alive && !e.ally && e !== p && seesEnt(e)).length;
  const danger = (G.intents?.decals || []).some((q) => q.x === p.x && q.y === p.y && q.kind !== 1);
  emit('hud', { hp: p.hp, max: p.max, st: { ...p.st }, turn: G.stats.turns, floor: G.floor, torch: G.torch ?? 100, torchMax: G.torchMax ?? 100, enemyCount, danger, stairs: G.tile[i] === T_STAIRS, lamp: G.lamps?.has(i), door, closedDoor, rescue, inv: G.inv.reduce((a, b) => a + b.n, 0), gear: G.gear.has(i) ? { name: gearName(G.gear.get(i)), css: gearCss(G.gear.get(i)) } : null, shield: p.shield || 0, boss: (() => { const b = G.ents.find((e) => e.boss); return b && b.alive && b.awake ? { name: b.name, hp: b.hp, max: b.max } : null; })() });
}

export function emitIntents() {
  const decals = [], tags = {}, casting = [], winding = [];
  for (const e of G.ents) {
    if (!e.alive || isP(e)) continue;
    if (e.npc) { tags[e.id] = e.freed ? '🙂' : e.caged ? '🆘' : '❔'; continue; }
    if (e.ally) { tags[e.id] = '✦' + e.life; continue; }
    if (!e.awake) { tags[e.id] = '💤'; continue; }
    if (e.cast) {
      for (const [x, y] of e.cast.tiles) decals.push({ x, y, kind: 5, color: HEX.danger, alpha: 0.95, blink: 1 });
      tags[e.id] = MAGE[e.elem].icon + '!'; casting.push(e.id);
    }
    if (e.charge) {
      const path = chargePath(e, e.charge.dx, e.charge.dy), rot = Math.atan2(e.charge.dx, -e.charge.dy);
      path.forEach(([x, y], k) => decals.push({ x, y, kind: 2, color: k < path.length - 1 ? 0xff6a2a : 0xff2a2a, alpha: 0.95, rot, blink: 0.4 }));
      tags[e.id] = '‼'; winding.push(e.id);
    }
    if (e.aim) {
      for (const [x, y] of lineTiles(e.x, e.y, G.player.x, G.player.y)) decals.push({ x, y, kind: 3, color: HEX.danger, alpha: 0.95, blink: 0.5 });
      decals.push({ x: G.player.x, y: G.player.y, kind: 4, color: HEX.danger, alpha: 0.9, blink: 1 });
      tags[e.id] = '🎯';
    }
    if (e.st.fear) tags[e.id] = '😱';
    // 이름 없는 투구: 다음 턴에 예고를 걸 적
    if (G.ps && G.ps.legend.has('namelessHelm') && !e.cast && !e.charge && !e.aim && !e.st.fear && G.vis[I(e.x, e.y)] && canSee(e, G.player) && ((e.type === 'mage' && e.cd <= 1) || (e.type === 'charger' && e.cd <= 0) || e.type === 'archer')) tags[e.id] = '⚠';
  }
  emit('intents', { decals, tags, casting, winding });
  G.intents = { decals, tags, casting, winding };
}

export function emitSlots() { emit('slots', { slots: G.slots.map((q) => ({ ...q })), bag: G.sbag.slice() }); }
