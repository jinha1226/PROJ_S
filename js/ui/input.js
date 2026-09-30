import { flowing, setRest, setTarget, setWalk } from '../core/clock.js';
import { visibleFoes } from '../core/fov.js';
import { pickGear } from '../core/gear.js';
import { previewFor, selfPreview, targetsFor } from '../core/skills.js';
import { costMap, pathPoints } from '../core/space.js';
import { G, Game, I, XY, entAt, inb, isFoe, isP, seesEnt } from '../core/state.js';
import { useStone } from '../core/stones.js';
import { useLamp } from '../core/torch.js';
import { RT } from '../data/realtime.js';
import { COLORS, STONE } from '../data/stones.js';
import { T_STAIRS, T_WALL } from '../data/terrain.js';
import { act, descend, returnToTown } from '../flow.js';
import { Sfx } from '../render/sfx.js';
import { View } from '../render/view.js';
import { Town } from '../town/town.js';
import { jo } from '../util/text.js';
import { $, UI } from './ui.js';

Object.assign(UI, {
  /* ---- 지도 입력: 탭 = 노릴 적 고르기 · 그 칸까지 걷기 (docs/설계_실시간_전환.md §2) ---- */
  onTap(sx, sy) {
    if (this.overlayOpen()) return;
    if (!$('#info').classList.contains('hidden')) { this.hideInfo(); return; }
    if (Game.mode === 'town') { Town.tap(sx, sy); return; }
    if (this.joyTapBlock) { this.joyTapBlock = false; return; } // 조이스틱으로 누르고 있던 손
    const t = View.pickTile(sx, sy); if (!t || !inb(t.x, t.y) || G.over) return;
    if (this.mode === 'target') { this.tapTarget(t.x, t.y); return; } // 던지기 조준
    const p = G.player, i = I(t.x, t.y), e = entAt(t.x, t.y);
    if (e && isFoe(e) && seesEnt(e) && G.target === e.id) { this.highlightEnemy = e.id; this.showEnemy(e); View.refreshDecals(); return; } // 노린 적을 한 번 더: 정보 카드
    if (e && isFoe(e) && seesEnt(e)) { setTarget(e.id); this.highlightEnemy = e.id; View.refreshDecals(); this.toast(`${jo(e.name, '을를')} 먼저 노린다.`); return; }
    this.stopAuto();
    if (t.x === p.x && t.y === p.y) { if (G.tile[i] === T_STAIRS) descend(); else if (G.gear.has(i)) { this.instant(() => pickGear()); this.renderWeapon(); } return; }
    if (!G.seen[i] || G.tile[i] === T_WALL) { this.toast('아직 모르는 곳이다.'); return; }
    this.startTravel(t.x, t.y);
  },
  onLongPress(sx, sy) {
    if (this.overlayOpen() || (this.joy && this.joy.on)) return;
    if (Game.mode === 'town') { Town.tap(sx, sy); return; }
    const t = View.pickTile(sx, sy); if (!t || !inb(t.x, t.y)) return;
    const e = entAt(t.x, t.y);
    if (e && !isP(e) && G.vis[I(t.x, t.y)]) { this.highlightEnemy = e.id; this.showEnemy(e); View.refreshDecals(); }
    else this.showTile(t.x, t.y);
  },
  /** 그 칸까지 길을 찾아 걸어간다(걷는 동안 시간이 흐른다) */
  startTravel(x, y) {
    const p = G.player, path = pathPoints(p, costMap(p, 400, { seenOnly: true, passAllies: true, allow: I(x, y) }), x, y);
    if (!path) { this.toast('갈 수 있는 길이 없다.'); return false; }
    setWalk(path.pts.slice(1)); this.travel = { foes: visibleFoes().length }; return true;
  },
  /** 자동 걷기·탐험·쉬기를 멈춘다 */
  stopAuto(msg) {
    const was = this.travel || this.explore || G.resting;
    this.travel = null; this.explore = false; setWalk(null); setRest(false);
    if (was && msg) this.toast(msg);
  },
  /** 방금(지난 두 턴 안에) 적에게 공격받았다 */
  underAttack() {
    return (G.hurtTurn ?? -9) >= G.stats.turns - 1; // 실제로 적에게 맞은(또는 피한) 직후만 — 깨어 있는 먼 적·물속 거머리는 세지 않는다
  },
  /** 탐험은 적을 만났을 때만 멈춘다 */
  exploreDiscovery() { return visibleFoes().length > 0; },
  /** 탐험 중 들를 곳: 보이는 물건·장비·영혼석·재료(필요하면 등잔) */
  explorePickups() {
    const skip = this.exploreSkip || new Set(), out = [...G.items.keys(), ...G.gear.keys(), ...G.stones.keys(), ...(G.mats ? G.mats.keys() : [])];
    if (G.lamps && (G.torch ?? 100) <= (G.torchMax ?? 100) - 40) out.push(...G.lamps.keys());
    return out.filter((i) => G.seen[i] && !skip.has(i));
  },
  startExplore() {
    if (G.over || this.overlayOpen()) return;
    if (visibleFoes().length) { this.toast('적이 보인다.'); return; }
    if (this.underAttack()) { this.toast('공격받고 있다.'); return; }
    if (G.player.hp <= G.player.max * 0.3) { this.toast('너무 다쳤다.'); return; } // 빈사
    setRest(false); this.explore = true; this.exploreSkip = new Set();
    this.exploreStep();
  },
  /** 다음 들를 곳(보이는 물건 → 모르는 곳의 가장자리)을 정해 걷는다 */
  exploreStep() {
    const p = G.player, here = I(p.x, p.y), skip = (this.exploreSkip ||= new Set());
    if (G.gear.has(here)) { let ok = false; this.instant(() => { ok = pickGear(); }); this.renderWeapon(); if (!ok) skip.add(here); }
    if (G.lamps && G.lamps.has(here)) this.instant(() => useLamp());
    const cm = costMap(p, 400, { seenOnly: true, passAllies: true });
    const nearest = (cells) => cells.filter((i) => i !== here && !skip.has(i) && isFinite(cm.cost[i])).sort((a, b) => cm.cost[a] - cm.cost[b])[0];
    let goal = nearest(this.explorePickups());
    if (goal == null) {
      const front = [];
      for (let i = 0; i < G.seen.length; i++) {
        if (!G.seen[i] || G.tile[i] === T_WALL) continue;
        const x = i % G.W, y = (i / G.W) | 0;
        if ([[1, 0], [-1, 0], [0, 1], [0, -1]].some(([dx, dy]) => inb(x + dx, y + dy) && !G.seen[I(x + dx, y + dy)])) front.push(i);
      }
      goal = nearest(front);
    }
    if (goal == null) { this.explore = false; this.toast('더 탐험할 곳이 없다.'); return; }
    const path = pathPoints(p, cm, goal % G.W, (goal / G.W) | 0);
    if (!path) { skip.add(goal); return; } // 다음 프레임에 다른 곳을 고른다
    this.exploreGoal = goal; setWalk(path.pts.slice(1));
  },
  startRest() {
    if (G.over) return;
    if (visibleFoes().length) { this.toast('적이 보인다.'); return; }
    if (this.underAttack()) { this.toast('공격받고 있다.'); return; }
    if (G.player.hp >= G.player.max && !G.player.st.poison) { this.toast('쉴 필요가 없다.'); return; }
    this.travel = null; this.explore = false; setWalk(null); setRest(true); G.restN = 0;
    this.toast('쉬는 중이다. 탭하면 멈춘다.');
  },
  /** 매 프레임, 시간이 흐른 뒤: 자동 걷기·탐험·쉬기를 잇거나 멈추고, 멈춤 표시를 맞춘다 */
  afterTick(n) {
    this.renderSkills();
    const p = G.player, hurt = G.hurt; G.hurt = false;
    if (G.pendingReturn) { const r = G.pendingReturn; G.pendingReturn = null; G.over = true; this.stopAuto(); setTimeout(() => returnToTown(r), 700); return; }
    const foes = visibleFoes().length;
    if (hurt && (this.travel || this.explore || G.resting)) this.stopAuto('공격받았다. 멈춘다.');
    else if (this.explore && foes) this.stopAuto('적이 보인다. 탐험을 멈춘다.');
    else if (this.travel && foes > this.travel.foes) this.stopAuto('적이 보인다. 멈춘다.');
    else if (G.resting && (foes || G.stats.turns - G.restFrom >= RT.restMax || (p.hp >= p.max && !p.st.poison && !p.st.burn))) this.stopAuto();
    if (G.stuckAbort) { G.stuckAbort = false; if (this.explore && this.exploreGoal != null) (this.exploreSkip ||= new Set()).add(this.exploreGoal); } // 막힌 목표는 건너뛴다
    if (this.explore && !G.walk) this.exploreStep();
    if (this.travel && !G.walk) this.travel = null;
    document.body.classList.toggle('frozen', Game.mode === 'dungeon' && !G.over && !flowing());
    const fz = document.body.classList.contains('frozen'), tt = $('#turns'); if (tt) { const base = `${Math.floor(G.clock || 0)}초`, txt = fz ? `${base} · 멈춤` : base; if (tt.textContent !== txt) tt.textContent = txt; }
    if (n > 0) { View.refreshDecals(); this.syncButtons(); }
  },
  /* ---- 대상 지정 ---- */
  /** 영혼석 칸 = 스킬 버튼. 대상 스킬은 조준 → 칸 두 번 탭, 자기 대상 스킬은 한 번 더 누르면 발동 */
  stoneBtn(k) {
    if (G.over || this.overlayOpen()) return;
    const sl = G.slots[k], id = sl && sl.stone;
    if (!id && k >= (G.level || 6)) { this.toast(`레벨 ${k + 1}에 열리는 칸이다.`); return; }
    if (!id) { this.slotInfo(k); return; }
    const S = STONE[id], C = COLORS[S.color];
    if (this.mode === 'target' && this.pend?.slot === k) {
      if (this.pend.self) { const pend = this.pend; this.exitTarget(); act(() => pend.run()); return; }
      this.exitTarget(); return;
    }
    Sfx.play('ui');
    if (sl.cd > 0) { this.toast(`${S.name}: ${sl.cd}턴 남았다. ${C.trig} 한 턴 더 줄어든다.`); return; }
    if (G.player.st.frozen || G.player.st.stun) return;
    const T = S.tgt.t, self = T === 'self' || T === 'around' || T === 'sight';
    if (id === 'p_summon' && G.ents.filter((e) => e.alive && e.ally && !e.npc).length >= 2) this.toast('가장 오래된 영혼 고블린이 사라진다.');
    this.enterTarget({ kind: 'stone', slot: k, id, self, name: S.icon + ' ' + S.name, color: C.hex, run: self ? () => useStone(k) : (x, y) => useStone(k, x, y) });
  },
  enterTarget(pend) {
    this.travel = null; setRest(false); this.hideInfo();
    this.mode = 'target'; this.pend = pend; this.prevIdx = -1; this.prev = null;
    this.valid = pend.kind === 'skill' ? this.skillTargets(pend) : targetsFor(pend);
    [...$('#souls').children].forEach((b, k) => b.classList.toggle('sel', (pend.kind === 'stone' || pend.kind === 'skill') && k === pend.slot));
    $('#targetbar').classList.add('on');
    if (pend.self) { this.prev = selfPreview(pend.id); $('#targettext').innerHTML = `<b>${pend.name}</b> ${this.prev.note}<br><small style="color:#9aa2bd">칸을 한 번 더 누르면 발동</small>`; }
    else $('#targettext').innerHTML = this.valid.size ? `<b>${pend.name}</b> 대상 칸을 탭하면 결과가 보인다` : `<b>${pend.name}</b> 닿는 대상이 없다`;
    View.refreshDecals();
  },
  exitTarget() {
    this.mode = 'normal'; this.pend = null; this.prev = null; this.prevIdx = -1;
    for (const b of $('#souls').children) b.classList.remove('sel');
    $('#targetbar').classList.remove('on'); View.refreshDecals();
  },
  targetDecals() {
    const list = [];
    for (const i of this.valid) { const [x, y] = XY(i); list.push({ x, y, kind: 0, color: this.pend.color, alpha: this.prevIdx === i ? 0 : 0.17 }); }
    if (this.prev) list.push(...this.prev.extra);
    if (this.prevIdx >= 0) { const [x, y] = XY(this.prevIdx); list.push({ x, y, kind: 4, color: 0xffffff, alpha: 1, blink: 0.6 }); }
    return list;
  },
  tapTarget(x, y) {
    const i = I(x, y);
    if (this.pend.self) { if (x === G.player.x && y === G.player.y) { const pend = this.pend; this.exitTarget(); act(() => pend.run()); return; } this.exitTarget(); return; }
    if (!this.valid.has(i)) { if (x === G.player.x && y === G.player.y) { this.exitTarget(); return; } this.toast('사거리·시야 밖이다.'); return; }
    if (this.prevIdx === i) { const pend = this.pend; this.exitTarget(); act(() => pend.run(x, y)); return; }
    this.prevIdx = i; this.prev = this.pend.kind === 'skill' ? this.skillPreview(this.pend) : previewFor(this.pend, x, y); Sfx.play('ui');
    $('#targettext').innerHTML = `<b>${this.pend.name}</b> ${this.prev.note}<br><small style="color:#9aa2bd">같은 칸을 한 번 더 탭하면 발동</small>`;
    View.refreshDecals();
  },
  key(e) {
    if (Game.mode !== 'dungeon') return;
    const k = e.key.toLowerCase();
    if (k === 'escape') { this.exitTarget(); this.hideInfo(); $('#sheet').classList.add('hidden'); $('#help').classList.add('hidden'); return; }
    if (this.overlayOpen()) return;
    if (/^(arrow(up|down|left|right)|[wasdqezc ])$/.test(k)) { e.preventDefault(); if (k !== ' ') this.stopAuto(); this.joyKeys.add(k); return; }
    if (k === '>') { if (G.tile[I(G.player.x, G.player.y)] === T_STAIRS) descend(); return; }
    if (k === 'i') this.openBag();
  },
});
