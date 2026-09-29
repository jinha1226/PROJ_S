import { Anim, act, descend, freeRun } from '../flow.js';
import { endPlayerTurn, exploreMove, exploreTick, detect, startCombat, attackPlan, walkAttack, playerWalk, freeWait } from '../core/free.js';
import { costMap, dist, distXY, meleeReach, pathPoints, posOf, sweep } from '../core/space.js';
import { los } from '../core/fov.js';
import { pickGear } from '../core/gear.js';
import { playerWait } from '../core/combat.js';
import { G, Game, I, TL, entAt, isFoe } from '../core/state.js';
import { CATS, catOf } from '../data/enemies.js';
import { FREE } from '../data/free.js';
import { T_STAIRS, T_WALL } from '../data/terrain.js';
import { weaponOf } from '../data/gear.js';
import { View } from '../render/view.js';
import { $, UI } from './ui.js';

/* ================= 원형 턴제 입력: 조이스틱 · 분신 · 걸어가서 공격 · 조준 ================= */
const FI = { keys: new Set(), joy: null, walk: null, ghost: null, atk: null, cm: null, envT: 0, lastTap: 0, stepT: 0, lastPrev: 0, sugg: null };
const flushNow = (fn) => { TL.reset(); const r = fn(); const q = TL.q.slice().sort((a, b) => a.t - b.t); TL.reset(); for (const e of q) e.fn(); return r; };
const active = () => G.free && Game.mode === 'dungeon' && !G.over && G.player && G.player.alive;
const myTurn = () => G.fc && G.fc.side === 'player';
const KEYV = { arrowup: [0, -1], w: [0, -1], arrowdown: [0, 1], s: [0, 1], arrowleft: [-1, 0], a: [-1, 0], arrowright: [1, 0], d: [1, 0], q: [-1, -1], e: [1, -1], z: [-1, 1], c: [1, 1] };
/** 조이스틱 또는 키보드 방향(화면 기준, 길이 ≤ 1). 없으면 null */
function stick() {
  if (FI.joy && FI.joy.on) return [FI.joy.vx, FI.joy.vy];
  let x = 0, y = 0; for (const k of FI.keys) { const v = KEYV[k]; if (v) { x += v[0]; y += v[1]; } }
  const L = Math.hypot(x, y); return L > 0 ? [x / L, y / L] : null;
}
function worldDir(sx, sy) { const yaw = View.dio.rig.yaw; return [Math.cos(yaw) * sx + Math.sin(yaw) * sy, -Math.sin(yaw) * sx + Math.cos(yaw) * sy]; }
function pickPoint(sx, sy) { const ray = View.dio.ray(sx, sy).ray, t = -ray.origin.y / ray.direction.y; if (!(t > 0)) return null; return [ray.origin.x + ray.direction.x * t, ray.origin.z + ray.direction.z * t]; }
function inDanger(x, y) {
  const tx = Math.round(x), ty = Math.round(y);
  for (const e of G.ents) {
    if (!e.alive || !isFoe(e)) continue;
    if (e.cast && e.cast.tiles.some(([a, b]) => a === tx && b === ty)) return true;
    if (e.charge) { const [ex, ey] = posOf(e), vx = x - ex, vy = y - ey, along = vx * e.charge.ux + vy * e.charge.uy, lat = Math.abs(vx * e.charge.uy - vy * e.charge.ux); if (along > 0 && along < e.charge.len + 0.5 && lat < 0.8) return true; }
  }
  return false;
}
function expectDmg(t) {
  const w = weaponOf(G.eq.weapon), weak = G.weakKnown[catOf(t)] && CATS[catOf(t)].weak === w.form, k = (weak ? 1.5 : 1) * (t.st.frozen ? 1.5 : 1) * (G.fc && G.fc.ambush ? 1.5 : 1);
  return [Math.ceil((w.dmg[0] + G.ps.dmg) * k), Math.ceil((w.dmg[1] + G.ps.dmg) * k)];
}

Object.assign(UI, {
  freeInit() {
    const c = View.dio.renderer.domElement, joy = $('#joy');
    c.addEventListener('pointerdown', (e) => {
      if (!active() || this.overlayOpen() || e.clientY < innerHeight * 0.42 || FI.joy) return;
      if (G.fc && !myTurn()) return;
      FI.joy = { id: e.pointerId, ox: e.clientX, oy: e.clientY, vx: 0, vy: 0, on: false };
    });
    c.addEventListener('pointermove', (e) => {
      const j = FI.joy; if (!j || e.pointerId !== j.id) return;
      const dx = e.clientX - j.ox, dy = e.clientY - j.oy, d = Math.hypot(dx, dy);
      if (!j.on && d > 14) { j.on = true; joy.style.display = 'block'; joy.style.transform = `translate(${j.ox}px,${j.oy}px)`; FI.walk = null; }
      if (j.on) { const m = Math.min(1, d / 60), k = d > 0 ? m / d : 0; j.vx = dx * k; j.vy = dy * k; joy.firstChild.style.transform = `translate(${j.vx * 36}px,${j.vy * 36}px)`; }
    });
    const up = (e) => { const j = FI.joy; if (!j || e.pointerId !== j.id) return; FI.joy = null; joy.style.display = 'none'; if (j.on && myTurn() && FI.ghost) this.freeHud(); };
    c.addEventListener('pointerup', up); c.addEventListener('pointercancel', up);
    addEventListener('keyup', (e) => { if (FI.keys.delete(e.key.toLowerCase()) && myTurn() && FI.ghost) this.freePreview(); });
    addEventListener('blur', () => FI.keys.clear());
  },
  freeKey(k, down) { if (down) { FI.keys.add(k); FI.walk = null; } else FI.keys.delete(k); },
  freeSugg(v) { FI.sugg = v; },
  freeReset() { FI.ghost = null; FI.atk = null; FI.walk = null; FI.cm = null; FI.sugg = null; View.clearGhost?.(); View.freeDecals = []; View.setThreats?.(new Set(), new Set()); View.refreshDecals(); this.freeHud(); },
  freeFrame(dt) {
    if (!active()) { if (View.ghost && !G.free) View.disposeGhost(); return; }
    if (Anim.active || this.overlayOpen()) return;
    const p = G.player, ev = View.evs.get(0), sv = this.mode === 'target' ? null : stick();
    if (!G.fc) {
      // 탐험: 조이스틱 · 키보드 / 경로 걷기
      if (p.st.frozen > 0 || p.st.stun > 0) FI.walk = null;
      let dx = 0, dy = 0;
      if (sv && !p.st.frozen && !p.st.stun) { const [wx, wy] = worldDir(sv[0], sv[1]); dx = wx * FREE.speed * dt; dy = wy * FREE.speed * dt; }
      else if (FI.walk && FI.walk.length) { const [tx, ty] = FI.walk[0], d = distXY(p.px, p.py, tx, ty), s = FREE.speed * dt; if (d <= s) { dx = tx - p.px; dy = ty - p.py; FI.walk.shift(); } else { dx = ((tx - p.px) / d) * s; dy = ((ty - p.py) / d) * s; } }
      if (Math.abs(dx) + Math.abs(dy) > 1e-5) {
        const changed = flushNow(() => exploreMove(dx, dy));
        if (ev) { ev.cur.set(p.px, 0, p.py); ev.t = 1; ev.yawT = Math.atan2(dx, dy); FI.stepT += dt; if (FI.stepT > 0.27) { FI.stepT = 0; ev.sqv -= 2.2; } }
        if (changed) { View.refreshDecals(); this.syncButtons(); const k = detect(); if (k) { FI.walk = null; FI.joy && (FI.joy.on = false); freeRun(() => startCombat(k)); return; } }
      }
      FI.envT += dt;
      if (FI.envT >= FREE.envEvery) { FI.envT = 0; flushNow(() => exploreTick()); View.refreshDecals(); const k = detect(); if (k) { FI.walk = null; freeRun(() => startCombat(k)); } }
      return;
    }
    if (!myTurn()) return;
    // 내 턴: 조이스틱은 분신을 움직인다
    if (sv) {
      if (!FI.cm) FI.cm = costMap(p, G.fc.move);
      const g = FI.ghost || { x: p.px, y: p.py }, [wx, wy] = worldDir(sv[0], sv[1]);
      const probe = { type: 'hero', px: g.x, py: g.y, x: Math.round(g.x), y: Math.round(g.y), st: {} };
      const r = sweep(probe, wx * 4 * dt, wy * 4 * dt, { ignore: p });
      const c = FI.cm.cost[I(Math.round(r.x), Math.round(r.y))];
      if (isFinite(c) && c <= G.fc.move + 1e-6) { FI.ghost = { x: r.x, y: r.y }; FI.atk = null; }
      FI.lastPrev += dt;
      if (FI.lastPrev > 0.1) { FI.lastPrev = 0; this.freeGhostPath(); this.freePreview(); }
    }
  },
  freeGhostPath() {
    const g = FI.ghost; if (!g) return;
    if (!FI.cm) FI.cm = costMap(G.player, G.fc.move);
    const path = pathPoints(G.player, FI.cm, g.x, g.y);
    if (path) { g.pts = path.pts; g.cost = path.cost; } else { FI.ghost = null; }
  },
  /** 분신 자리 기준의 도달 범위 · 경로 · 닿는 적 · 기회 공격 경고 */
  freePreview() {
    const dec = [], threat = new Set(), warns = new Set(), p = G.player;
    if (!G.fc || !myTurn()) { View.freeDecals = dec; View.clearGhost?.(); View.setThreats(threat, warns); View.refreshDecals(); this.freeHud(); return; }
    if (!FI.cm) FI.cm = costMap(p, G.fc.move);
    for (let i = 0; i < FI.cm.cost.length; i++) if (isFinite(FI.cm.cost[i]) && G.seen[i]) dec.push({ x: i % G.W, y: (i / G.W) | 0, kind: 7, color: 0x9fd0ff, alpha: 0.16, scale: 1.5 });
    const g = FI.ghost, [ox, oy] = g ? [g.x, g.y] : posOf(p);
    if (g && g.pts) {
      for (let k = 1; k < g.pts.length; k++) { const [ax, ay] = g.pts[k - 1], [bx, by] = g.pts[k], d = distXY(ax, ay, bx, by); for (let s = 0.4; s < d; s += 0.45) dec.push({ x: ax + ((bx - ax) * s) / d, y: ay + ((by - ay) * s) / d, kind: 3, color: 0xffffff, alpha: 0.9 }); }
      View.setGhost(g.x, g.y, Math.atan2(g.x - p.px, g.y - p.py), G.fc.move - g.cost, inDanger(g.x, g.y));
    } else View.clearGhost();
    const R = meleeReach(p);
    for (const e of G.ents) {
      if (!e.alive || !isFoe(e) || !G.vis[I(e.x, e.y)]) continue;
      const [ex, ey] = posOf(e), d = distXY(ox, oy, ex, ey);
      if (d <= R) threat.add(e.id);
      else if (d <= 5.5 && los(Math.round(ox), Math.round(oy), e.x, e.y)) for (let s = 0.6; s < d - 0.4; s += 0.7) dec.push({ x: ox + ((ex - ox) * s) / d, y: oy + ((ey - oy) * s) / d, kind: 3, color: 0xffe38a, alpha: 0.35 });
      if (g && e.awake && dist(p, e) <= FREE.reach && distXY(g.x, g.y, ex, ey) > FREE.reach) warns.add(e.id);
    }
    View.freeDecals = dec; View.setThreats(threat, warns); View.refreshDecals(); this.freeHud();
  },
  freeHud() {
    const bar = $('#freebar'); if (!bar) return;
    if (!G.free || Game.mode !== 'dungeon') { bar.style.display = 'none'; return; }
    bar.style.display = '';
    const fc = G.fc, c = $('#btn-ctx');
    if (!fc) { bar.innerHTML = '🚶 <b>탐험</b> — 아래쪽을 끌어 걷기 · 먼 곳을 탭하면 걸어간다'; return; }
    if (fc.side !== 'player') { bar.innerHTML = '⏳ <b>적의 턴</b> — 두 번 탭하면 빨리 넘긴다'; return; }
    const g = FI.ghost;
    bar.innerHTML = `🏃 이동 <b>${fc.move.toFixed(1)}m</b> · ⚔ 행동 <b>${fc.actions}</b>${g && g.cost != null ? ` · 분신까지 ${g.cost.toFixed(1)}m` : ''}${FI.atk != null ? ' · <b style="color:#ffe38a">' + (FI.atkText || '') + '</b>' : ''}`;
    c.disabled = false; c.classList.add('live');
    if (g && g.pts && FI.atk == null) { c.innerHTML = `🏃<small>이동 ${g.cost.toFixed(1)}m</small>`; c.dataset.act = 'fmove'; }
    else { c.innerHTML = '⏭<small>턴 끝</small>'; c.dataset.act = 'fend'; c.classList.remove('live'); }
  },
  freeTurnStart() { FI.cm = null; FI.ghost = null; FI.atk = null; FI.sugg = null; this.freePreview(); },
  freeAfter() { FI.cm = null; if (FI.ghost && G.fc && myTurn()) this.freeGhostPath(); this.freePreview(); },
  combatBanner(ambush) { this.banner(ambush == null ? '전투 끝' : ambush ? '⚔ 기습!' : '⚔ 전투 시작', ambush == null ? 'info' : ambush ? 'bolt' : 'fire'); },
  freeConfirm() {
    const g = FI.ghost; if (!g || !g.pts || Anim.active) return;
    FI.ghost = null; FI.cm = null; View.clearGhost();
    freeRun(() => playerWalk(g.pts, g.cost));
  },
  freeCtx(a) {
    if (a === 'fmove') { this.freeConfirm(); return true; }
    if (a === 'fend') { if (!Anim.active && myTurn()) { FI.ghost = null; View.clearGhost(); freeRun(() => endPlayerTurn()); } return true; }
    return false;
  },
  freeWaitBtn() {
    if (Anim.active) return;
    if (!G.fc) { freeRun(() => { playerWait(); exploreTick(); return true; }); return; }
    if (!myTurn()) return;
    FI.ghost = null; View.clearGhost(); freeRun(() => freeWait());
  },
  freeTap(sx, sy) {
    const now = performance.now(), dbl = now - FI.lastTap < 380; FI.lastTap = now;
    if (Anim.active) { if (G.fc && G.fc.side === 'enemy' && dbl) View.dio.timeScale = 3; return; }
    const pt = pickPoint(sx, sy); if (!pt) return;
    const tt = View.pickTile(sx, sy), p = G.player;
    const foe = tt && (() => { const e = entAt(tt.x, tt.y); return e && isFoe(e) && G.vis[I(e.x, e.y)] ? e : null; })();
    if (this.mode === 'target') { this.freeTargetTap(foe ? posOf(foe) : pt); return; }
    const onSelf = distXY(pt[0], pt[1], p.px, p.py) < 0.5;
    if (!G.fc) {
      if (foe) { this.showEnemy(foe); return; }
      if (onSelf) { const i = I(p.x, p.y); if (G.tile[i] === T_STAIRS) descend(); else if (G.gear.has(i)) { this.instant(() => pickGear()); this.renderWeapon(); } return; }
      const tx = Math.round(pt[0]), ty = Math.round(pt[1]);
      if (tx < 0 || ty < 0 || tx >= G.W || ty >= G.H || !G.seen[I(tx, ty)] || G.tile[I(tx, ty)] === T_WALL) { this.toast('아직 모르는 곳이다'); return; }
      const path = pathPoints(p, costMap(p, 80, { passAllies: true }), pt[0], pt[1]); if (!path) { this.toast('갈 수 있는 길이 없다'); return; }
      FI.walk = path.pts.slice(1); return;
    }
    if (!myTurn()) return;
    if (foe) {
      if (FI.atk === foe.id) { FI.atk = null; FI.ghost = null; View.clearGhost(); if (G.fc.actions <= 0) { this.toast('이번 턴 행동을 이미 썼다'); return; } act(() => walkAttack(foe)); return; }
      const plan = attackPlan(foe); if (!plan) { this.toast('이동 거리로는 닿지 않는다'); this.showEnemy(foe); return; }
      const [lo, hi] = expectDmg(foe);
      FI.atk = foe.id; FI.atkText = `${foe.name} 공격 — 예상 피해 ${lo}–${hi} · 한 번 더 탭`;
      FI.ghost = plan.pts ? { x: plan.pts[plan.pts.length - 1][0], y: plan.pts[plan.pts.length - 1][1], pts: plan.pts, cost: plan.cost } : null;
      this.freePreview(); return;
    }
    if (onSelf) { FI.ghost = null; FI.atk = null; this.freePreview(); return; }
    if (FI.ghost && distXY(pt[0], pt[1], FI.ghost.x, FI.ghost.y) < 0.6 && FI.atk == null) { this.freeConfirm(); return; }
    if (!FI.cm) FI.cm = costMap(p, G.fc.move);
    const c = FI.cm.cost[I(Math.round(pt[0]), Math.round(pt[1]))];
    if (!isFinite(c) || c > G.fc.move + 1e-6) { this.toast('이번 턴에 갈 수 없는 곳'); return; }
    const probe = { type: 'hero', px: Math.round(pt[0]), py: Math.round(pt[1]), x: Math.round(pt[0]), y: Math.round(pt[1]), st: {} }, r = sweep(probe, pt[0] - probe.px, pt[1] - probe.py, { ignore: p });
    FI.ghost = { x: r.x, y: r.y }; FI.atk = null; this.freeGhostPath(); this.freePreview();
  },

  /* ---- 조준: 사거리 원 · 효과 미리보기 · 밖이면 이동 제안 ---- */
  freeOrigin() { const g = FI.ghost; return g && g.pts ? [g.x, g.y] : posOf(G.player); },
  freeTargets(pend) {
    const [ox, oy] = this.freeOrigin(), R = pend.needsEnemy ? FREE.reach : pend.range, set = new Set();
    for (let y = Math.floor(oy - R); y <= Math.ceil(oy + R); y++) for (let x = Math.floor(ox - R); x <= Math.ceil(ox + R); x++) {
      if (x < 0 || y < 0 || x >= G.W || y >= G.H) continue; const i = I(x, y);
      if (!G.vis[i] || G.tile[i] === T_WALL || distXY(ox, oy, x, y) > R + 0.001 || (Math.round(ox) === x && Math.round(oy) === y)) continue;
      if (pend.needsEnemy) { const e = entAt(x, y); if (!e || !isFoe(e)) continue; }
      if (!los(Math.round(ox), Math.round(oy), x, y)) continue;
      set.add(i);
    }
    return set;
  },
  freeTargetDecals() {
    const [ox, oy] = this.freeOrigin(), R = this.pend.needsEnemy ? FREE.reach : this.pend.range, list = [{ x: ox, y: oy, kind: 4, color: this.pend.color, alpha: 0.8, scale: (R * 2) / 0.82 }];
    for (const i of this.valid) list.push({ x: i % G.W, y: (i / G.W) | 0, kind: 7, color: this.pend.color, alpha: this.prevIdx === i ? 0 : 0.35, scale: 1.4 });
    if (this.prev) list.push(...this.prev.extra.map((d) => (d.kind === 0 ? { ...d, kind: 7, scale: 1.5 } : d)));
    if (FI.sugg) list.push({ x: FI.sugg[0], y: FI.sugg[1], kind: 4, color: 0x9fd0ff, alpha: 1, blink: 1 });
    return list;
  },
  freeTargetTap(pt) {
    const x = Math.round(pt[0]), y = Math.round(pt[1]), i = I(x, y);
    if (x < 0 || y < 0 || x >= G.W || y >= G.H) return;
    if (!this.valid.has(i)) {
      // 사거리 밖: 여기서 쏘려면 어디까지 가야 하나
      if (!G.fc || !myTurn() || G.tile[i] === T_WALL || !G.vis[i]) { this.toast('사거리·시야 밖이다'); return; }
      const R = this.pend.needsEnemy ? FREE.reach : this.pend.range, cm = costMap(G.player, G.fc.move); let best = null;
      for (let k = 0; k < cm.cost.length; k++) { const c = cm.cost[k]; if (!isFinite(c)) continue; const qx = k % G.W, qy = (k / G.W) | 0; if (distXY(qx, qy, x, y) <= R && los(qx, qy, x, y) && (!best || c < best.c)) best = { x: qx, y: qy, c }; }
      if (!best) { this.toast('이번 턴에는 닿지 않는다'); return; }
      const path = pathPoints(G.player, cm, best.x, best.y); FI.ghost = { x: best.x, y: best.y, pts: path.pts, cost: path.cost }; FI.sugg = [best.x, best.y];
      const pend = this.pend; this.enterTarget(pend); this.tapTarget(x, y);
      $('#targettext').innerHTML = `<b>${pend.name}</b> 여기서 쏘려면 <b>${path.cost.toFixed(1)}m</b> 이동 — 같은 곳을 한 번 더 탭하면 이동 후 발동`;
      return;
    }
    this.tapTarget(x, y);
  },
  /** 원형 턴제에서 조준 결과를 실행: 분신이 있으면 먼저 걸어간다 */
  freeWrapRun(pend) {
    const run = pend.run;
    pend.run = (x, y) => { const g = FI.ghost; FI.ghost = null; FI.sugg = null; View.clearGhost(); if (g && g.pts) playerWalk(g.pts, g.cost); if (!G.player.alive) return true; return run(x, y); };
    return pend;
  },
});
