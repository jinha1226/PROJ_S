import { PHYS } from '../data/colors.js';
import { CATS, catOf, monRes } from '../data/enemies.js';
import { CAPS, RES_MUL, clampRes, weaponOf } from '../data/gear.js';
import { S_ICE, S_WATER, T_DOOR, T_OPEN, T_STAIRS, T_WALL } from '../data/terrain.js';
import { DARK, torchTier } from '../data/torch.js';
import { JOBS } from '../data/town.js';
import { FORMS } from '../data/weapons.js';
import { D8, cheb, sgn } from '../util/grid.js';
import { pick, rand, ri } from '../util/rng.js';
import { jo } from '../util/text.js';
import { applyFire, fireAt, shock } from './elements.js';
import { dropGearFrom, gearName, openChest, weaponUsed } from './gear.js';
import { addItem, identify, itemName } from './items.js';
import { META, saveMeta } from './meta.js';
import { emitStatus, snapTerrain } from './snap.js';
import { G, I, emit, entAt, inb, isFoe, isP, itemSnap, log, standable } from './state.js';
import { auraOnHurt, dropStone, gainXp, reduceColor } from './stones.js';

const ELEM_OF = { fire: 'fire', burn: 'fire', blast: 'fire', shock: 'bolt', frost: 'frost', poison: 'poison' };
const DOT = { burn: 1, poison: 1, bleed: 1 }; // 지속 피해는 '적중'이 아니다

export function damage(e, amt, kind = 'hit', o = {}) {
  if (!e.alive || amt <= 0) return 0;
  let label = o.label || '';
  // 붉은 오브: 빨강 영혼석 스킬 피해 +N
  if (isFoe(e) && G.ctx && G.ctx.color === 'red' && G.ps && G.ps.orb.red && !DOT[kind] && (!o.src || o.src === G.player)) amt += G.ps.orb.red;
  if (e.st.frozen > 0 && PHYS[kind]) { amt = Math.ceil(amt * 1.5); if (!label) label = '빙결 강타'; }
  if (isFoe(e) && !e.awake) e.awake = true;
  if (e.hidden) reveal(e); // 숨어 있던 적은 맞으면 드러난다
  const src = o.src || G.curSrc;
  // 장비: 내가 맞을 때 회피·막기·방어·저항, 내가 칠 때 원소 피해
  const struck = isP(e) && src && src !== e && isFoe(src);
  if (isP(e) && G.ps) {
    const ps = G.ps, el = ELEM_OF[kind];
    if ((kind === 'hit' || kind === 'charge') && src && isFoe(src)) {
      const eva = Math.min(CAPS.eva, ps.eva);
      if (rand() * 100 < eva) { emit('dodge', { id: 0 }); G.hurt = true; G.hurtTurn = G.stats.turns; return 0; } // 피해도 공격받은 것(자동 탐험·휴식이 멈춘다)
      if (ps.block && rand() * 100 < ps.block) { emit('block', { id: 0 }); amt = 0; }
    }
    if (amt > 0 && src && isFoe(src) && G.torch === 0 && !G.darkAmbushUsed) {
      G.darkAmbushUsed = true; amt = Math.ceil(amt * 1.5); label = '어둠 속 기습';
      log('어둠 속에서 기습당했다.', 'bad');
    }
    if (amt > 0 && PHYS[kind] && src && isFoe(src)) amt += DARK[torchTier(G.torch ?? 100)].atk; // 어둠 속 적은 사납다
    if (amt > 0 && ps.legend.has('thornPlate')) amt = Math.ceil(amt * 1.2);
    // 줄이기: 물리 = 0~방어 무작위(최소 1) · 원소 = 저항 단계 배율 (docs/밸런스_기준.md §2~§3)
    if (amt > 0 && PHYS[kind] && ps.def) amt = Math.max(1, amt - ri(0, ps.def));
    if (amt > 0 && el && ps.res[el]) amt = Math.max(ps.res[el] >= 3 ? 0 : 1, Math.round(amt * RES_MUL[ps.res[el]]));
  } else if (isFoe(e) && ELEM_OF[kind]) { const r = monRes(e, ELEM_OF[kind]); if (r) { amt = Math.max(r >= 3 ? 0 : 1, Math.round(amt * RES_MUL[clampRes(r)])); if (r >= 2 && !label) label = '저항'; if (r <= -1 && !label) label = '약함'; } if (amt <= 0) { emit('immune', { id: e.id }); return 0; } }
  if (struck && G.ps && G.ps.vengeance) G.vengeance = G.ps.vengeance; // 되갚음: 다음 무기 공격 +2
  if (struck && G.ps && G.ps.thorns && src.alive && PHYS[kind] && cheb(src.x, src.y, e.x, e.y) <= 1) { const s0 = src; damage(s0, G.ps.thorns, 'impact', { label: '가시', src: G.player }); } // 가시
  if (struck) reduceColor('green'); // 초록: 적에게 맞았을 때(0 피해·보호막이 막아도)
  if (isP(e) && G.auras && G.auras.guard && amt > 0) amt = Math.ceil(amt / 2); // 막기
  if (isP(e) && e.shield > 0) { const a = Math.min(e.shield, amt); e.shield -= a; amt -= a; emit('shieldHit', { absorbed: a, left: e.shield }); }
  if (isP(e) && amt > 0) G.combatDmg = (G.combatDmg || 0) + Math.min(amt, e.hp);
  // 빨강: 내 공격(무기·스킬)이 적에게 적중
  if (isFoe(e) && amt > 0 && (!src || src === G.player) && G.ctx && G.ctx.origin !== 'enemy' && !DOT[kind]) reduceColor('red');
  if (amt > 0) {
    e.hp -= amt;
    if (isP(e)) { (G.hurtLog ||= []).push({ turn: G.stats.turns, who: src && src !== e ? src.name : HURT_BY[kind] || '알 수 없는 것', amt, kind }); if (G.hurtLog.length > 8) G.hurtLog.shift(); } // 사망 요약
    emit('hit', { id: e.id, amt, kind, dx: o.dx || 0, dy: o.dy || 0, label, big: !!o.big || amt >= 7, crit: !!o.crit });
    emit('hp', { id: e.id, hp: Math.max(0, e.hp), max: e.max });
  }
  if (o.form) e.lastForm = o.form; else if (kind !== 'bleed') e.lastForm = null;
  if (isP(e)) { G.hurt = true; if (src && src !== e && isFoe(src)) G.hurtTurn = G.stats.turns; } // 공격받은 턴: 적의 공격만(중독·출혈·불 같은 지속 피해는 아니다)
  if (e.hp <= 0) { kill(e); return amt; }
  if (struck && e.alive) auraOnHurt(src); // 반격·독 가시·번개 갑주·서리 갑주
  return amt;
}

export function kill(e) {
  const shatter = e.st.frozen > 0;
  e.alive = false; e.act = null;
  emit('die', { id: e.id, shatter });
  if (isP(e)) { G.over = true; G.deathBy = (G.hurtLog || []).slice(-1)[0] || null; log('쓰러졌다…', 'bad'); emit('gameover'); return; }
  if (e.ally) return;
  if (e.npc) { log(`${jo(e.name, '을를')} 잃었다…`, 'bad'); return; }
  G.stats.kills++; gainXp(e);
  // 무기로 쓰러뜨리면 재료 하나(무작위 — 막타 형태와 상관없다)
  const f = e.lastForm, part = f ? pick(['가죽', '뼈', '심장']) : null;
  if (part) { addLoot(part, 1); emit('loot', { x: e.x, y: e.y, m: part }); }
  if (e.boss) {
    G.exitOpen = true; G.tile[G.stairs] = T_STAIRS; snapTerrain();
    addLoot('마석', 1); addLoot(pick(['가죽', '뼈', '심장']), 2);
    emit('portal', { x: G.stairs % G.W, y: (G.stairs / G.W) | 0 }); emit('banner', { text: `${e.name} 격파!`, elem: 'chain' });
    log('귀환의 문이 열렸다.', 'syn');
  }
  log(`${shatter ? `${jo(e.name, '이가')} 산산이 부서졌다.` : `${jo(e.name, '을를')} 쓰러뜨렸다.`}${part ? ` ${jo(part, '이가')} 남았다.` : ''}`, 'good');
  if (e.st.bleed > 0 && G.ps && G.ps.legend.has('bloodFang')) {
    emit('bloodBurst', { x: e.x, y: e.y }); log('피의 송곳니에서 피가 터졌다.', 'syn');
    for (const [dx, dy] of D8) { const o = entAt(e.x + dx, e.y + dy); if (o && o.alive && isFoe(o) && !CATS[catOf(o)].noBleed) { o.st.bleed += 2; emitStatus(o); } }
  }
  dropStone(e, f);
  dropGearFrom(e);
}

/** 숨은 적이 드러난다 */
export function reveal(e) {
  if (!e.hidden) return; e.hidden = false; e.revealed = true;
  emit('move', { id: e.id, x: e.x, y: e.y, dur: 1, hop: 0, kind: 'step', seen: G.vis[I(e.x, e.y)] ? 1 : 0 });
  if (G.vis[I(e.x, e.y)]) { emit('splash', { x: e.x, y: e.y }); log(`물속에서 ${jo(e.name, '이가')} 튀어나왔다.`, 'bad'); }
}
/** 주인공을 다치게 한 것(적이 아닐 때) */
const HURT_BY = { burn: '불길', fire: '불길', blast: '폭발', shock: '번개', frost: '냉기', poison: '독', bleed: '출혈', wall: '벽', impact: '충돌', steam: '증기' };

export function addLoot(m, n) { G.loot.mats[m] = (G.loot.mats[m] || 0) + n; }

export function freeDropSpot(x, y) {
  const ok = (a, b) => inb(a, b) && standable(a, b) && G.tile[I(a, b)] !== T_STAIRS && !G.stones.has(I(a, b)) && !G.items.has(I(a, b)) && !G.gear.has(I(a, b));
  if (ok(x, y)) return [x, y];
  for (let r = 1; r <= 2; r++) for (let dy = -r; dy <= r; dy++) for (let dx = -r; dx <= r; dx++) if (ok(x + dx, y + dy)) return [x + dx, y + dy];
  return null;
}

export function heal(e, n) { const v = Math.min(n, e.max - e.hp); if (v <= 0) return; e.hp += v; emit('heal', { id: e.id, amt: v }); emit('hp', { id: e.id, hp: e.hp, max: e.max }); }

/** 힘 모으던 행동·예고를 끊는다(기절·빙결·골절) */
export function cancelIntent(e) { if (e.act) { e.act = null; e.cd = Math.max(e.cd || 0, 0.4); } }

export function faceTo(e, t) { const dx = sgn(t.x - e.x), dy = sgn(t.y - e.y); if (dx || dy) { e.face = [dx, dy]; emit('face', { id: e.id, dx, dy }); } }

export function moveEnt(e, x, y, o = {}) {
  const fx = e.x, fy = e.y; e.x = x; e.y = y;
  if (e.px != null) { e.px = e.ppx = x; e.py = e.ppy = y; } // 칸을 옮기면 소수 위치도 그 칸 가운데로(보간하지 않고 바로)
  if (o.face !== false && (x !== fx || y !== fy)) e.face = [sgn(x - fx), sgn(y - fy)];
  emit('move', { id: e.id, x, y, dur: o.dur ?? 115, hop: o.hop ?? 0.1, kind: o.kind || 'step', seen: isP(e) || (G.vis[I(x, y)] && !e.hidden) ? 1 : 0 });
}

export function onEnter(e) {
  if (!e.alive) return;
  const i = I(e.x, e.y);
  if (G.surf[i] === S_WATER) {
    let ch = false;
    if (e.st.burn) { e.st.burn = 0; ch = true; emit('steam', { x: e.x, y: e.y, small: true }); }
    if (e.st.wet < 3 && !(isP(e) && G.ps && G.ps.wetImm)) { e.st.wet = 3; ch = true; } // 물걸음은 젖지 않는다
    if (ch) emitStatus(e);
    emit('splash', { x: e.x, y: e.y, small: true });
  }
  if (G.fire[i] > 0) applyFire(e, 2);
  if (isP(e) && e.alive) {
    if (G.items.has(i)) {
      const k = G.items.get(i); G.items.delete(i); addItem(k); G.stats.items++;
      if (G.ps && G.ps.autoId && !G.known[k]) identify(k);
      emit('items', itemSnap()); emit('pickup', { x: e.x, y: e.y }); log(`${jo(itemName(k), '을를')} 주웠다.`, 'good');
    }
    if (G.stones.has(i)) { G.stoneOffer = i; emit('stoneOffer', { i, id: G.stones.get(i) }); } // 흡수할지, 가방에 넣을지 고른다
    if (G.mats.get(i) === '기록') { G.mats.delete(i); emit('matPick', { x: e.x, y: e.y, m: '기록' }); if (!META.lore.includes(G.zone)) { META.lore.push(G.zone); saveMeta(); } emit('lore', { zone: G.zone }); log('옛 등불지기의 기록 한 장을 주웠다.', 'syn'); }
    else if (G.mats.has(i)) { const m = G.mats.get(i); G.mats.delete(i); addLoot(m, 1); emit('matPick', { x: e.x, y: e.y, m }); log(`${jo(m, '을를')} 채집했다.`, 'good'); }
    if (G.gear.has(i)) log(`${jo(gearName(G.gear.get(i)), '이가')} 떨어져 있다.`, 'info');
    if (G.tile[i] === T_STAIRS) log('내려가는 계단이다.', 'info');
  }
}

export function push(e, dx, dy, n) {
  const giant = isFoe(e) && G.ps && G.ps.legend.has('giantMace');
  let k = 0, left = n + (giant ? 1 : 0);
  while (left > 0 && k < 12 && e.alive) {
    const nx = e.x + dx, ny = e.y + dy;
    if (!standable(nx, ny)) {
      emit('bump', { id: e.id, dx, dy }); 
      damage(e, 4 + (isFoe(e) && G.ps ? G.ps.wallDmg : 0), 'wall', { dx, dy, label: '벽 쾅!', big: true });
      if (e.alive && !isP(e)) { e.st.stun = Math.max(e.st.stun, 1); emitStatus(e); cancelIntent(e); }
      if (giant) { emit('shake', { a: 0.3 }); for (const [ax, ay] of D8) { const o = entAt(e.x + ax, e.y + ay); if (o && o !== e && o.alive && isFoe(o)) damage(o, 1, 'impact', { label: '흔들림' }); } }
      emit('shake', { a: 0.35 });
      if (!isP(e)) G.stats.combos++;
      break;
    }
    const o = entAt(nx, ny);
    if (o) {
      emit('bump', { id: e.id, dx, dy }); 
      damage(e, 3, 'impact', { dx, dy, label: '충돌' }); damage(o, 3, 'impact', { dx, dy });
      emit('shake', { a: 0.3 }); break;
    }
    moveEnt(e, nx, ny, { dur: 85, hop: 0.05, kind: 'push', face: false }); k++; left--;
    if (G.surf[I(nx, ny)] === S_ICE && left === 0) left = 1;
  }
  if (e.alive) onEnter(e);
  return k;
}

export function openDoor(x, y) { G.tile[I(x, y)] = T_OPEN; emit('door', { x, y, open: true }); snapTerrain(); }

/* ================= 주인공 행동 ================= */
/** 갇힌 사람을 풀어 준다(부딪히거나 구하기 버튼) */
export function freeNpc(e) {
  const p = G.player; e.freed = true; faceTo(p, e); emit('free', { id: e.id });
  log(`${JOBS[e.npcData.job].name} ${jo(e.name, '을를')} 풀어 주었다.`, 'good');
}
/** 붙은 칸 하나를 건드린다(구하기·상자·문 버튼). 걷기는 시계(clock.js)가, 공격은 전투 코어(sim/weapon.js)가 맡는다 */
export function playerMove(dx, dy) {
  const p = G.player, nx = p.x + dx, ny = p.y + dy;
  if (!inb(nx, ny)) return false;
  const t = G.tile[I(nx, ny)];
  if (t === T_WALL) return false;
  const e = entAt(nx, ny);
  if (e && e.npc && !e.freed) { freeNpc(e); return true; }
  if (G.chests.has(I(nx, ny)) && !G.chests.get(I(nx, ny)).open) { p.face = [dx, dy]; emit('face', { id: 0, dx, dy }); openChest(nx, ny); return true; }
  if (t === T_DOOR) { p.face = [dx, dy]; emit('face', { id: 0, dx, dy }); openDoor(nx, ny); log('문을 열었다.', 'info'); return true; }
  return false;
}

export const curW = () => weaponOf(G.eq && G.eq.weapon);
/** 한 번 칠 때 예상 피해 [최소, 최대]: 약점·빙결·급소·쌍단검 포함 (적 위 ◆ 표시) */
export function hitRange(t) {
  const w = curW(), ps = G.ps || { dmg: 0, critMul: 2 }, weak = t && CATS[catOf(t)].weak === w.form, vital = t && w.form === 'pierce' && t.st.vital > 0;
  const k = (weak ? 1.5 : 1) * (t && t.st.frozen ? 1.5 : 1) * (vital ? ps.critMul + (weak ? 0.5 : 0) : 1) * (w.shape === 'twin' ? 2 : 1);
  return w.dmg.map((v) => Math.ceil((v + ps.dmg) * k));
}

/* ---------- 무기 한 번 적중: 형태 → 부상, 약점, 급소 ---------- */
export function weaponHit(t, ctx, o = {}) {
  if (!t || !t.alive) return;
  const p = G.player, w = curW(), f = w.form, dx = sgn(t.x - p.x), dy = sgn(t.y - p.y), ps = G.ps;
  if (ps.acc < 0 && rand() * 100 < -ps.acc) { emit('miss', { x: t.x, y: t.y }); log('빗나갔다.', 'info'); return; }
  const cat = catOf(t), C = CATS[cat], weak = C.weak === f;
  // 더하기: 기본 + 품질·강화치·반지 힘(ps.dmg), 되갚음 → 곱하기: 약점·급소 (docs/밸런스_기준.md §2)
  const venge = G.vengeance || 0; G.vengeance = 0;
  let dmg = ri(w.dmg[0], w.dmg[1]) + ps.dmg + (o.bonus || 0) + venge, label = o.counter ? '반격' : o.extra ? '추가 타격' : venge ? '되갚음' : '', crit = false;
  if (weak) {
    dmg = Math.ceil(dmg * 1.5) + ps.weakDmg;
    if (!G.weakKnown[cat]) { G.weakKnown[cat] = true; emit('weakReveal', { id: t.id, form: f }); log(`${jo(C.name, '은는')} ${FORMS[f].name}에 약하다.`, 'syn'); }
    label = label || '약점';
  }
  const cm = ps.critMul + (weak ? 0.5 : 0); // 꿰뚫기: ×3
  if (f === 'pierce' && t.st.vital > 0) { crit = true; dmg = Math.ceil(dmg * cm); t.st.vital = 0; label = '급소!'; }
  else if (f === 'pierce' && ps.crit && rand() * 100 < ps.crit) { crit = true; dmg = Math.ceil(dmg * cm); label = '급소!'; }
  if (w.range && o.near) { dmg = Math.max(1, Math.floor(dmg / 2)); label = label || '너무 가깝다'; } // 붙은 적에게 쏘면 절반
  const dealt = damage(t, dmg, 'hit', { dx, dy, label, big: crit || weak, form: f, crit, src: p });
  weaponUsed();
  if (ps.vamp && dealt > 0 && !C.noBleed) heal(p, Math.max(1, Math.floor(dealt * 0.3))); // 흡혈(해골 제외)
  if (t.alive) {
    if (f === 'slash' && !C.noBleed) t.st.bleed += (weak ? 5 : 3) + ps.bleed;
    if (f === 'blunt') { t.st.frac = Math.max(t.st.frac, (weak ? 5 : 3) + ps.fracBonus); if (t.act && t.act.kind === 'charge') { cancelIntent(t); log(`${t.name}의 다리가 부러져 돌진이 끊겼다.`, 'good'); } }
    if (f === 'pierce' && !crit && !o.noMark) t.st.vital = 1;
    if (w.stun && rand() * 100 < w.stun) { t.st.stun = Math.max(t.st.stun, 1); cancelIntent(t); log(`${jo(t.name, '이가')} 기절했다.`, 'good'); } // 철퇴
    emitStatus(t);
    if (f === 'blunt' && ps.fracPush && !o.noPush) push(t, dx, dy, 1);
    weaponBrand(t, ps.brand);
  }
}
/** 무기 브랜드: 원소는 원소 규칙 그대로 반응한다 */
function weaponBrand(t, b) {
  if (!b || !t.alive) return;
  if (b === 'fire') fireAt(t.x, t.y, 2);
  else if (b === 'frost') { const wet = t.st.wet > 0; damage(t, 2, 'frost', { label: '냉기' }); if (t.alive && wet) { t.st.frozen = Math.max(t.st.frozen, 1); t.st.wet = 0; emitStatus(t); emit('freeze', { x: t.x, y: t.y }); } }
  else if (b === 'bolt' && rand() < 0.25) { if (t.st.wet > 0 || G.surf[I(t.x, t.y)] === S_WATER) shock(t.x, t.y, 3); else damage(t, 3, 'shock', { label: '번개' }); }
  else if (b === 'poison' && !t.st.immune && resistOk(t, 'poison')) { t.st.poison = Math.max(t.st.poison, 2); emitStatus(t); }
}

/** 상태 이상에 걸리는가: 저항 +1 = 절반, +2 = 1/4, +3 = 안 걸림 */
export function resistOk(e, el) {
  const r = isP(e) ? (G.ps ? G.ps.res[el] || 0 : 0) : monRes(e, el);
  return r <= 0 || (r < 3 && rand() < Math.pow(0.5, r));
}

export function closeDoor(x, y) { G.tile[I(x, y)] = T_DOOR; emit('door', { x, y, open: false }); snapTerrain(); log('문을 닫았다.', 'info'); return true; }

/** 층을 시작할 때 보호막(뼈 흉갑 같은 장비) */
export const armorShield = () => (G.ps ? G.ps.floorShield : 0);
