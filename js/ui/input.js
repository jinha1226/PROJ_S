import { playerMove, playerWait } from '../core/combat.js';
import { findPath, visibleFoes } from '../core/fov.js';
import { previewFor, targetsFor, useSkill } from '../core/skills.js';
import { emitStatus } from '../core/snap.js';
import { G, Game, I, XY, entAt, inb, isFoe, isP, log } from '../core/state.js';
import { SK, SKILLS } from '../data/skills.js';
import { T_DOOR, T_STAIRS, T_WALL } from '../data/terrain.js';
import { Anim, act, descend, returnToTown } from '../flow.js';
import { Sfx } from '../render/sfx.js';
import { View } from '../render/view.js';
import { Town } from '../town/town.js';
import { $, UI } from './ui.js';
import { cheb } from '../util/grid.js';

Object.assign(UI, {
  /* ---- 지도 입력 ---- */
  onTap(sx, sy) {
    if (this.overlayOpen()) return;
    if (!$('#info').classList.contains('hidden')) { this.hideInfo(); return; }
    if (Game.mode === 'town') { Town.tap(sx, sy); return; }
    const t = View.pickTile(sx, sy); if (!t || !inb(t.x, t.y)) return;
    this.travel = null; this.rest = null;
    if (Anim.active) { if (this.mode === 'normal') this.buffered = t; return; }
    this.tapTile(t.x, t.y);
  },
  onLongPress(sx, sy) {
    if (this.overlayOpen() || Anim.active) return;
    if (Game.mode === 'town') { Town.tap(sx, sy); return; }
    const t = View.pickTile(sx, sy); if (!t || !inb(t.x, t.y)) return;
    const e = entAt(t.x, t.y);
    if (e && !isP(e) && G.vis[I(t.x, t.y)]) this.showEnemy(e); else this.showTile(t.x, t.y);
  },
  tapTile(x, y) {
    if (G.over || G.player.st.frozen || G.player.st.stun) return;
    if (this.mode === 'target') { this.tapTarget(x, y); return; }
    const p = G.player, d = cheb(p.x, p.y, x, y), i = I(x, y), e = entAt(x, y), seenFoe = e && isFoe(e) && G.vis[i];
    if (d === 0) { if (G.tile[i] === T_STAIRS) descend(); else if (G.weps.has(i)) this.weaponCard(); else this.toast('⏳ 대기는 아래 버튼 — 길게 누르면 휴식'); return; }
    if (seenFoe && d > 1) { this.showEnemy(e); return; }
    if (d === 1) { if (G.tile[i] === T_WALL) return; act(() => playerMove(x - p.x, y - p.y)); return; }
    if (!G.seen[i] || G.tile[i] === T_WALL) { this.toast('아직 모르는 곳이다'); return; }
    this.startTravel(x, y);
  },
  startTravel(x, y) {
    const path = findPath(G.player.x, G.player.y, x, y);
    if (!path) { this.toast('갈 수 있는 길이 없다'); return; }
    this.travel = { path, first: true }; this.travelStep();
  },
  travelStep() {
    const tr = this.travel; if (!tr) return;
    const p = G.player;
    if (!tr.first && (visibleFoes().length || G.hurt)) { this.travel = null; if (visibleFoes().length) this.toast('적이 보인다 — 멈춤'); return; }
    const [nx, ny] = tr.path[0];
    if (cheb(nx, ny, p.x, p.y) !== 1 || entAt(nx, ny)) { this.travel = null; return; }
    if (G.tile[I(nx, ny)] !== T_DOOR) tr.path.shift();
    tr.first = false; if (!tr.path.length) this.travel = null;
    act(() => playerMove(nx - p.x, ny - p.y));
  },
  waitBtn() { if (G.player.st.frozen || G.player.st.stun) return; this.travel = null; this.rest = null; if (this.mode === 'target') this.exitTarget(); act(() => playerWait()); },
  startRest() {
    if (Anim.active || G.over) return;
    if (visibleFoes().length) { this.toast('적이 보여서 쉴 수 없다'); return; }
    if (G.player.hp >= G.player.max && !G.player.st.poison) { this.toast('쉴 필요가 없다'); return; }
    this.rest = { n: 0 }; this.toast('휴식 중… (탭하면 멈춤)'); this.restStep();
  },
  restStep() {
    const r = this.rest; if (!r) return; const p = G.player;
    if (visibleFoes().length || G.hurt || r.n >= 40 || (p.hp >= p.max && !p.st.poison && !p.st.burn)) { this.rest = null; return; }
    r.n++; act(() => playerWait());
  },
  afterTurn() {
    View.refreshDecals(); this.syncButtons();
    if (G.over) return;
    if (G.pendingReturn) { const r = G.pendingReturn; G.pendingReturn = null; G.over = true; setTimeout(() => returnToTown(r), 700); return; }
    const p = G.player;
    if (p.st.frozen > 0 || p.st.stun > 0) {
      setTimeout(() => act(() => { const fz = p.st.frozen > 0; if (p.st.frozen > 0) p.st.frozen--; if (p.st.stun > 0) p.st.stun--; emitStatus(p); log(fz ? '얼어붙어 움직일 수 없다…' : '기절해서 움직일 수 없다…', 'bad'); return true; }), 260);
      return;
    }
    if (this.buffered) { const b = this.buffered; this.buffered = null; this.tapTile(b.x, b.y); return; }
    if (this.travel) { setTimeout(() => this.travelStep(), 30); return; }
    if (this.rest) { setTimeout(() => this.restStep(), 20); }
  },
  /* ---- 대상 지정 ---- */
  skillBtn(id) {
    if (G.over || this.overlayOpen()) return;
    Sfx.play('ui');
    if (this.mode === 'target' && this.pend?.id === id) { this.exitTarget(); return; }
    const sk = SK[id];
    if (G.cd[id] > 0) { this.toast(`${sk.name}: ${G.cd[id]}턴 뒤에 다시 쓸 수 있다`); return; }
    if (G.player.st.frozen || G.player.st.stun) return;
    this.enterTarget({ kind: 'skill', id, name: sk.icon + ' ' + sk.name, range: sk.range, color: sk.color, needsEnemy: !!sk.needsEnemy, run: (x, y) => useSkill(id, x, y) });
  },
  enterTarget(pend) {
    this.travel = null; this.rest = null; this.hideInfo();
    this.mode = 'target'; this.pend = pend; this.prevIdx = -1; this.prev = null;
    this.valid = targetsFor(pend);
    for (const [k, b] of Object.entries(this.skEls)) b.classList.toggle('sel', pend.kind === 'skill' && k === pend.id);
    $('#targetbar').classList.add('on');
    $('#targettext').innerHTML = this.valid.size ? `<b>${pend.name}</b> — 대상 칸을 탭하면 결과를 미리 보여준다` : `<b>${pend.name}</b> — 닿는 대상이 없다`;
    View.refreshDecals();
  },
  exitTarget() {
    this.mode = 'normal'; this.pend = null; this.prev = null; this.prevIdx = -1;
    for (const b of Object.values(this.skEls)) b.classList.remove('sel');
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
    if (!this.valid.has(i)) { if (x === G.player.x && y === G.player.y) { this.exitTarget(); return; } this.toast('사거리·시야 밖이다'); return; }
    if (this.prevIdx === i) { const pend = this.pend; this.exitTarget(); act(() => pend.run(x, y)); return; }
    this.prevIdx = i; this.prev = previewFor(this.pend, x, y); Sfx.play('ui');
    $('#targettext').innerHTML = `<b>${this.pend.name}</b> ${this.prev.note}<br><small style="color:#9aa2bd">같은 칸을 한 번 더 탭하면 발동</small>`;
    View.refreshDecals();
  },
  key(e) {
    if (Game.mode !== 'dungeon') return;
    if (e.repeat && !/Arrow|[wasdqezc]/.test(e.key)) return;
    const k = e.key.toLowerCase();
    if (k === 'escape') { this.exitTarget(); this.hideInfo(); $('#sheet').classList.add('hidden'); $('#help').classList.add('hidden'); return; }
    if (this.overlayOpen()) return;
    const map = { arrowup: [0, -1], w: [0, -1], arrowdown: [0, 1], s: [0, 1], arrowleft: [-1, 0], a: [-1, 0], arrowright: [1, 0], d: [1, 0], q: [-1, -1], e: [1, -1], z: [-1, 1], c: [1, 1] };
    if (map[k]) {
      e.preventDefault();
      const [sx, sy] = map[k], yaw = View.dio.rig.yaw, wx = Math.cos(yaw) * sx + Math.sin(yaw) * sy, wy = -Math.sin(yaw) * sx + Math.cos(yaw) * sy;
      const st = Math.round(Math.atan2(wy, wx) / (Math.PI / 4)), dx = Math.round(Math.cos(st * Math.PI / 4)), dy = Math.round(Math.sin(st * Math.PI / 4));
      if (Anim.active) return;
      this.tapTile(G.player.x + dx, G.player.y + dy); return;
    }
    if (k === ' ' || k === '.') { e.preventDefault(); this.waitBtn(); return; }
    if (k === '>') { if (G.tile[I(G.player.x, G.player.y)] === T_STAIRS) descend(); return; }
    if (k === 'i') { this.openBag(); return; }
    const n = parseInt(k, 10); if (n >= 1 && n <= 5) this.skillBtn(SKILLS[n - 1].id);
  },
});
