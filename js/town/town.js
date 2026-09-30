import * as THREE from 'three';
import { colony, tickReal } from '../core/colony.js';
import { META, processReturn, rel, saveMeta } from '../core/meta.js';
import { furnCells, roomName } from '../core/rooms.js';
import { costOf, inLight, invalidate, missing, radius, roomAt, roomTier, rooms } from '../core/settlement.js';
import { Game } from '../core/state.js';
import { hearthGlow } from '../core/visitors.js';
import { FURN, ROOMS, SCX, SCY, SH, SW, TERRAIN } from '../data/build.js';
import { CLOCK, STATIONS } from '../data/colony.js';
import { weaponId } from '../data/gear.js';
import { WORKTALK } from '../data/lines.js';
import { JOBS } from '../data/town.js';
import { GLOW } from '../data/visitors.js';
import { W3, _tv, _w } from '../render/common.js';
import * as K from '../render/diorama.js';
import { dollSpec, matProp, weaponDoll } from '../render/dolls.js';
import { SettleView } from '../render/settle-view.js';
import { Sfx } from '../render/sfx.js';
import { View } from '../render/view.js';
import { $, UI } from '../ui/ui.js';
import { pick } from '../util/rng.js';
import { jo } from '../util/text.js';
import { TownNPC, talkLine } from './town-npc.js';

/* ================= 정착지: 40×40 땅 · 방 · 주민 (docs/설계_정착지_건설.md 1단계) ================= */
const I = (x, y) => y * SW + x;
const HERO_AT = [SCX - 1, SCY + 1.1];
const CRAFT_ROOMS = Object.keys(STATIONS);

export const Town = {
  sv: null,
  npcs: [],
  hero: null,
  center: new THREE.Vector3(SCX, 0, SCY),
  objs: [],
  tags: [],
  roomTags: [],
  shower: [],
  busy: false,
  spIdx: 1, // 배속(CLOCK.speeds)
  pileObjs: new Map(),
  /** 기능 자리(월드 좌표 [x, z]): 모닥불 · 출발문 · 제단 · 창고 더미 · 작업방 가운데 */
  spot(kind) {
    const S = META.settle;
    if (kind === 'plaza') return [SCX, SCY];
    const fk = { gate: 'gate', altar: 'altar', storage: 'heap' }[kind];
    if (fk) { const f = S.furn.find((q) => q.k === fk); if (f) return [f.x, f.y]; }
    const r = rooms().find((q) => q.kind === kind); if (r) return [r.cx, r.cy];
    return [SCX + 1.5, SCY + 1.5];
  },
  /** 일하는 자리: 작업방 안의 빈 칸 하나(없으면 모닥불 곁) */
  workSpot(n) {
    const b = JOBS[n.job].b, r = b && rooms().find((q) => q.kind === b);
    if (!r) return [SCX + 1.6, SCY + 1.6];
    const occ = new Set(); for (const f of META.settle.furn) for (const [x, y] of furnCells(f)) occ.add(I(x, y));
    const free = [...r.cells].filter((i) => !occ.has(i));
    const i = free.length ? free[Math.floor(Math.random() * free.length)] : [...r.cells][0];
    return [i % SW, (i / SW) | 0];
  },
  /** 걸어갈 길: 벽은 막히고 문·빈칸은 지난다(4방향). 칸 좌표 목록 */
  route(fx, fz, tx, tz) {
    const S = META.settle, a = I(Math.round(fx), Math.round(fz)), b = I(Math.round(tx), Math.round(tz));
    if (a < 0 || b < 0 || a >= SW * SH || b >= SW * SH) return [[tx, tz]];
    const block = (i) => (S.wall[i] && S.wall[i] !== 3) || TERRAIN[S.terr[i]].id === 'water';
    const prev = new Int32Array(SW * SH).fill(-1), q = [a]; prev[a] = a;
    for (let h = 0; h < q.length && prev[b] < 0; h++) {
      const c = q[h], x = c % SW, y = (c / SW) | 0;
      for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) { const nx = x + dx, ny = y + dy, n = ny * SW + nx; if (nx < 0 || ny < 0 || nx >= SW || ny >= SH || prev[n] >= 0 || (block(n) && n !== b)) continue; prev[n] = c; q.push(n); }
    }
    if (prev[b] < 0) return [[tx, tz]];
    const out = []; for (let c = b; c !== a; c = prev[c]) out.push([c % SW, (c / SW) | 0]);
    out.reverse(); if (out.length) out[out.length - 1] = [tx, tz]; else out.push([tx, tz]);
    return out;
  },
  enter(r = {}) {
    Game.mode = 'town';
    const res = processReturn(r); saveMeta();
    UI.toTown(); View.clear(); $('#lowhp').style.opacity = '0';
    View.dio.rig.followRate = 6.5; // 정착지: 끌어서 둘러보는 느긋한 초점
    // 조각을 넣기 전의 원경, 아직 오지 않은 방문자로 짓고 연출로 바꾼다
    if (res.shard) META.lit[res.shard - 1] = false;
    this.build(res.visitors);
    if (res.shard) META.lit[res.shard - 1] = true;
    this.busy = true;
    this.startIntro(); this.renderClock();
    if (res.dark) { setTimeout(() => { this.busy = false; this.afterReport = () => this.endingDark(); this.report(r, res); }, 700); this.renderHud(); return; }
    const hasLoot = r.loot && Object.keys(r.loot).length, steps = [];
    steps.push((next) => this.waitIntro(next));
    if (hasLoot) steps.push((next) => { this.lootShower(r.loot); setTimeout(next, 2600); });
    if (res.shard) steps.push((next) => this.shardScene(res.shard, next));
    for (const v of res.visitors) steps.push((next) => this.visitorArrive(v, () => setTimeout(next, 300)));
    steps.push(() => {
      this.busy = false;
      this.afterReport = () => { if (res.ending) this.endingDawn(); else if (META.needSuccessor) this.successionSheet(); };
      this.report(r, res);
    });
    const run = (k) => steps[k] && steps[k](() => run(k + 1));
    setTimeout(() => run(0), 200);
    this.renderHud();
  },
  clear() {
    const D = View.dio;
    this.sv?.dispose(); this.sv = null; D.grid = null;
    for (const o of this.objs) D.scene.remove(o); this.objs = [];
    for (const n of this.npcs) D.scene.remove(n.d.root); this.npcs = [];
    for (const t of [...this.tags, ...this.roomTags]) t.remove(); this.tags = []; this.roomTags = [];
    for (const s of this.shower) D.scene.remove(s.o); this.shower = [];
    for (const o of this.pileObjs.values()) D.scene.remove(o); this.pileObjs.clear();
    this.hero = null; this.lands = []; this.graves = []; this.visitorDolls = []; this.orbs = []; this.intro = null;
    const rig = D.rig; Object.assign(rig, { drag: null, onePan: false, panMode: false, bounds: null, maxZoom: 1.7 }); D.camera.far = 140; D.camera.updateProjectionMatrix();
    $('#townhud').style.opacity = '';
  },
  build(skipVisitors = []) {
    const D = View.dio; this.clear(); invalidate();
    D.setPreset('settlement', { tilesAcross: 12 });
    D.camera.far = 320; D.camera.updateProjectionMatrix();
    Object.assign(D.rig, { onePan: true, panMode: true, bounds: [2, 2, SW - 3, SH - 3], maxZoom: 2.2 });
    D.rig.reset(); // 정착지는 늘 탑뷰(정면·기본 확대)로 시작한다
    this.sv = new SettleView(D.scene);
    colony(); this.refreshWorld(); this.syncPiles();
    for (const n of META.npcs) this.npcs.push(new TownNPC(n));
    if (META.hero) {
      const sp = dollSpec({ type: 'hero', face: [0, 1], eq: META.hero.eq }), d = K.doll(sp.parts, { scale: 1.3, gloss: sp.gloss }); const ex = sp.extra(d); if (META.hero.eq.weapon) ex.wh.add(weaponDoll(weaponId(META.hero.eq.weapon), META.hero.eq.weapon).root);
      d.root.position.set(HERO_AT[0], 0, HERO_AT[1]); d.root.rotation.y = 0.6; d.mesh.userData.pick = { hero: true }; D.scene.add(d.root); this.objs.push(d.root); this.hero = d;
    }
    this.buildHearth(skipVisitors);
    D.lightTarget = this.center; D.rig.focusT.copy(this.center); D.rig.snap();
  },
  /** 땅·방·청사진·빛을 다시 그린다(건설할 때마다) */
  refreshWorld() {
    const S = META.settle, sv = this.sv; if (!sv) return;
    sv.setWorld(S); sv.setBlueprints(S.bp, new Set(S.bp.filter((b) => Object.keys(missing(costOf(b))).length).map((b) => b.id))); sv.setLight(radius()); sv.setFire(this.fireLevel()); // 재료가 모자란 청사진은 빨강
    for (const t of this.roomTags) t.remove(); this.roomTags = [];
    for (const r of rooms()) {
      const tag = document.createElement('div'); tag.className = 'btag'; tag.textContent = `${r.kind ? ROOMS[r.kind].icon : '▫'} ${roomName(r)}`;
      tag.dataset.x = r.cx; tag.dataset.z = r.cy; View.labelRoot.appendChild(tag); this.roomTags.push(tag);
    }
  },
  /** 바닥 더미(베고 캔 것 · 거둔 식량): 나르기 일이 창고로 옮긴다 */
  syncPiles() {
    const D = View.dio, C = META.colony; if (!C) return;
    const live = new Set(C.piles.map((p) => p.id));
    for (const [id, o] of this.pileObjs) if (!live.has(id)) { D.scene.remove(o); this.pileObjs.delete(id); }
    for (const p of C.piles) {
      let o = this.pileObjs.get(p.id);
      if (!o) { o = matProp(p.m); o.position.set(p.x + ((p.id * 37) % 7 - 3) * 0.06, 0.02, p.y + ((p.id * 53) % 7 - 3) * 0.06); o.rotation.y = p.id; D.scene.add(o); this.pileObjs.set(p.id, o); }
      o.scale.setScalar(0.9 + Math.min(0.8, p.n * 0.05));
    }
  },
  /** 한 시간(또는 여러 시간)이 흐른 뒤: 화면을 따라잡는다 */
  afterHours() {
    const C = META.colony;
    if (C.changed) { C.changed = false; this.refreshWorld(); this.syncPiles(); if (this.buildMode) this.renderBuild?.(); }
    this.renderClock(); this.renderHud(); saveMeta(); this.workRefresh?.();
    for (const t of this.npcs) if (t.doing !== t.n.doing || t.n.carry) { t.doing = t.n.doing; if (t.state !== 'walk') t.t = t.dur; } // 할 일이 바뀌면 곧 움직인다
  },
  fireLevel() { const g = hearthGlow(); return g <= GLOW.low ? 1 : g < GLOW.vision ? 2 : 3; },
  /* ---------- 들어올 때 줌인 (§8.1): 높은 곳에서 어둠 속 작은 불빛 → 마을. 누르면 건너뛴다 ---------- */
  startIntro() {
    const rig = View.dio.rig; this.intro = { t: 0, T: 2.2, done: [] };
    rig.zoom = rig.zoomT = 2.6; rig.pitch = rig.pitchT = rig.TOP + 0.25; rig.focusT.copy(this.center); rig.snap();
    const h = $('#townhud'); h.style.transition = 'none'; h.style.opacity = '0';
  },
  waitIntro(next) { if (!this.intro) { next(); return; } this.intro.done.push(next); },
  skipIntro() { if (this.intro) { this.intro.t = this.intro.T; this.introFrame(0); } },
  introFrame(dt) {
    const q = this.intro; if (!q) return;
    const rig = View.dio.rig; q.t = Math.min(q.T, q.t + dt); const k = q.t / q.T, e = 1 - Math.pow(1 - k, 3);
    rig.zoom = rig.zoomT = 2.6 + (1 - 2.6) * e; rig.pitch = rig.pitchT = rig.TOP + 0.25 * (1 - e);
    if (k >= 1) { this.intro = null; const h = $('#townhud'); h.style.transition = 'opacity .5s'; h.style.opacity = '1'; for (const f of q.done) f(); }
  },
  /** 빛이 넓어질 때: 살짝 물러나 경계를 보여준 뒤 돌아온다 */
  widenLight() {
    const rig = View.dio.rig; rig.zoomT = 1.7; this.sv?.setLight(radius());
    setTimeout(() => { rig.zoomT = 1; }, 1600);
  },
  /** 장비를 바꾸면 모닥불 곁 모험가 인형도 다시 입힌다 */
  redressHero() {
    if (!this.hero || !META.hero) return;
    const D = View.dio, old = this.hero, sp = dollSpec({ type: 'hero', face: [0, 1], eq: META.hero.eq }), d = K.doll(sp.parts, { scale: 1.3, gloss: sp.gloss }), ex = sp.extra(d);
    if (META.hero.eq.weapon) ex.wh.add(weaponDoll(weaponId(META.hero.eq.weapon), META.hero.eq.weapon).root);
    d.root.position.copy(old.root.position); d.root.rotation.y = old.root.rotation.y; d.mesh.userData.pick = { hero: true };
    D.scene.remove(old.root); this.objs.splice(this.objs.indexOf(old.root), 1, d.root); D.scene.add(d.root); this.hero = d;
    D.sparks.emit({ pos: _w.set(d.root.position.x, 0.6, d.root.position.z), n: 20, color: 0xffffff, color2: 0xffd84a, speed: 1.6, up: 1.4, grav: 0, life: 0.6, size: 0.12, spread: 0.4 });
  },
  lootShower(loot) {
    const D = View.dio, list = [];
    for (const [m, n] of Object.entries(loot)) for (let k = 0; k < Math.min(n, 6); k++) list.push(m);
    list.slice(0, 26).forEach((m, k) => {
      const o = matProp(m); o.scale.setScalar(1.4);
      const a = Math.random() * 6.28, r = 0.4 + Math.random() * 1.1;
      o.position.set(this.center.x + Math.cos(a) * 0.3, 5 + k * 0.15, this.center.z - 0.4 + Math.sin(a) * 0.3);
      D.scene.add(o);
      this.shower.push({ o, v: new THREE.Vector3(Math.cos(a) * r * 1.2, 0, Math.sin(a) * r * 1.2), delay: k * 0.07, life: 9 });
    });
    for (const t of this.npcs) { const a = Math.random() * 6.28; t.goto(this.center.x + Math.cos(a) * 2.2, this.center.z + Math.sin(a) * 2.0, 'gather', 3.5, [this.center.x, this.center.z]); }
    Sfx.play('gem');
  },
  /** 빛 안의 빈 칸 하나(돌아다니기) */
  wanderSpot() {
    const S = META.settle, R = radius();
    for (let k = 0; k < 30; k++) {
      const x = SCX + Math.round((Math.random() - 0.5) * 2 * (R - 1)), y = SCY + Math.round((Math.random() - 0.5) * 2 * (R - 1)), i = I(x, y);
      if (x < 0 || y < 0 || x >= SW || y >= SH || !inLight(x, y, R - 1) || S.wall[i] || !TERRAIN[S.terr[i]].build) continue;
      if (S.furn.some((f) => furnCells(f).some(([a, b]) => a === x && b === y))) continue;
      return [x, y];
    }
    return [SCX + 2, SCY + 2];
  },
  decide(t) {
    const n = t.n, others = this.npcs.filter((o) => o !== t), r = Math.random();
    const bad = others.filter((o) => (n.rel[o.n.id] || 0) <= -20);
    const ok = (x, z) => bad.every((o) => o.pos.distanceTo(W3(x, z)) > 3 && (!o.target || o.target.distanceTo(W3(x, z)) > 3));
    if (t.partner) { t.partner.partner = null; t.partner = null; }
    if (this.decideTask(t)) return;
    const w = this.workSpot(n);
    if (n.t.C <= -1 && r < 0.3) { t.goto(w[0], w[1], 'nap', 5); return; }
    const friends = others.filter((o) => (n.rel[o.n.id] || 0) >= 20 && !o.partner && o.state !== 'walk' && o.state !== 'gather');
    if (friends.length && r < 0.35 + n.t.X * 0.12) {
      const f = friends[Math.floor(Math.random() * friends.length)];
      for (let k = 0; k < 8; k++) {
        const a = Math.random() * 6.28, x = this.center.x + Math.cos(a) * 1.9, z = this.center.z + Math.sin(a) * 1.7, x2 = this.center.x + Math.cos(a + 0.5) * 1.9, z2 = this.center.z + Math.sin(a + 0.5) * 1.7;
        if (!ok(x, z)) continue;
        t.partner = f; f.partner = t; rel(n, f.n, 2); // 수다를 떨면 조금씩 가까워진다
        t.goto(x, z, 'chat', 6, [x2, z2]); f.goto(x2, z2, 'chat', 6, [x, z]); return;
      }
    }
    if (r < 0.6 + n.t.O * 0.1) { for (let k = 0; k < 6; k++) { const [x, z] = this.wanderSpot(); if (ok(x, z)) { t.goto(x, z, 'idle', 2 + Math.random() * 2); return; } } }
    const room = JOBS[n.job].b && rooms().find((q) => q.kind === JOBS[n.job].b);
    if (!room) { t.goto(this.center.x + 1.5, this.center.z + 1.5, 'idle', 3); return; }
    t.goto(w[0], w[1], 'work', Math.max(2.5, 6 + n.t.C * 1.6), [room.cx, room.cy]);
  },
  /** 정착지의 일(core/colony.js)을 따라 움직인다. 쉴 때만 예전처럼 돌아다닌다 */
  decideTask(t) {
    const n = t.n, tk = n.task;
    if (n.doing === 'sleep' || n.doing === 'faint') {
      const beds = META.settle.furn.filter((f) => f.k === 'bed'), b = beds[META.npcs.indexOf(n)];
      const [x, z] = b ? [b.x, b.y] : [SCX + Math.cos(META.npcs.indexOf(n)) * 2.2, SCY + Math.sin(META.npcs.indexOf(n)) * 2.2];
      t.goto(x, z, 'sleep', 4); return true;
    }
    if (n.carry) { const [x, z] = this.spot('storage'); t.setCarry(n.carry); n.carry = null; t.goto(x + 0.6, z + 0.6, 'drop', 0.8, [x, z]); return true; }
    if (!tk || tk.x == null || n.doing === 'rest') return false;
    // 일할 자리: 나무·바위·밭은 그 칸 옆, 작업방은 방 안
    let x = tk.x, z = tk.y, face = null;
    if (tk.kind === 'gather' || tk.kind === 'build' || tk.kind === 'farm') { const a = Math.atan2(SCY - tk.y, SCX - tk.x); x = tk.x + Math.cos(a) * 0.7; z = tk.y + Math.sin(a) * 0.7; face = [tk.x, tk.y]; }
    else if (tk.kind === 'craft' || tk.kind === 'cook') { const r = rooms().find((q) => q.kind === (tk.room || 'inn')); if (r) { const i = [...r.cells][(n.id.charCodeAt(1) * 7) % r.cells.size]; x = i % SW; z = (i / SW) | 0; face = [r.cx, r.cy]; } }
    t.task = tk.kind;
    if (Math.hypot(t.pos.x - x, t.pos.z - z) < 0.4) { t.state = 'task'; t.t = 0; t.dur = 5; return true; }
    t.goto(x, z, 'task', 5, face); return true;
  },
  bubble(t) {
    const n = t.n; let text;
    if (t.state === 'task' && t.n.task) text = { build: '🔨 뚝딱뚝딱', gather: t.n.task.what === 'tree' ? '🪓 영차!' : '⛏ 쾅!', farm: '🌾 …', cook: '🍲 보글보글', craft: pick(WORKTALK[JOBS[t.n.job].work] || ['⚒']), haul: '📦 영차' }[t.task] || '…';
    else if (t.state === 'sleep') text = '💤';
    else if (t.state === 'chat') text = pick(['💬', '😄', '💬 그러니까…', '하하']);
    else if (t.state === 'nap') text = '💤';
    else if (t.state === 'work') text = n.mood <= -1 ? '😤 …' : pick(WORKTALK[JOBS[n.job].work]);
    else if (t.state === 'gather') text = n.t.X >= 1 ? '우와, 이게 다 뭐야?' : n.t.H <= -1 ? '하나쯤 없어져도…' : '수고했어요.';
    else text = talkLine(n);
    View.dio.labels.pop(W3(t.pos.x, t.pos.z, 1.75), '', { html: `<span class="bub">${text}</span>`, cls: 'gem', vx: 0, rise: 14, dur: 2.6 });
  },
  frame(sdt) {
    const D = View.dio, time = K.SHARED.uTime.value;
    this.introFrame(sdt);
    if (!this.busy && !this.intro && META.settle && tickReal(sdt, CLOCK.speeds[this.spIdx])) this.afterHours();
    this.sv?.frame(sdt, time);
    for (const t of this.npcs) t.update(sdt, time);
    this.hearthFrame(sdt, time);
    if (Math.random() < sdt * (4 + (this.glow ?? 30) * 0.2)) D.sparks.emit({ pos: _w.set(SCX, 0.5, SCY), n: 1, color: 0xff8a2a, color2: 0xffe36a, speed: 0.4, up: 1 + (this.glow ?? 30) / 50, grav: 0.4, life: 0.9, size: 0.1, spread: 0.25 }); // 불이 밝을수록 불티가 많다
    for (let i = this.shower.length - 1; i >= 0; i--) {
      const s = this.shower[i]; if (s.delay > 0) { s.delay -= sdt; continue; }
      s.life -= sdt; const o = s.o; s.v.y -= 16 * sdt; o.position.addScaledVector(s.v, sdt); o.rotation.x += sdt * 5; o.rotation.z += sdt * 4;
      if (o.position.y < 0.02) { o.position.y = 0.02; if (Math.abs(s.v.y) > 1.5) { D.sparks.emit({ pos: o.position, n: 3, color: 0xfff2b0, speed: 1.5, life: 0.4, size: 0.1 }); if (Math.random() < 0.4) Sfx.play('pickgem'); } s.v.y *= -0.4; s.v.x *= 0.6; s.v.z *= 0.6; o.rotation.x *= 0.5; o.rotation.z *= 0.5; }
      if (s.life < 1) o.scale.setScalar(Math.max(0.01, s.life * 1.4));
      if (s.life <= 0) { D.scene.remove(o); this.shower.splice(i, 1); }
    }
    const s = {}, far = D.rig.zoom > 1.8;
    for (const tag of this.roomTags) {
      if (far) { tag.style.display = 'none'; continue; } tag.style.display = '';
      D.labels.toScreen(_tv.set(+tag.dataset.x, 1.6, +tag.dataset.z), s);
      tag.style.transform = `translate(${s.x.toFixed(1)}px,${s.y.toFixed(1)}px) translate(-50%,-100%)`;
    }
  },
  tap(sx, sy) {
    if (this.intro) { this.skipIntro(); return; }
    if (this.busy) return;
    if (this.buildMode) { this.buildTap(sx, sy); return; }
    const ray = View.dio.ray(sx, sy), list = [...this.objs, ...this.npcs.map((t) => t.d.root)];
    if (this.sv) list.push(this.sv.group);
    for (const h of ray.intersectObjects(list, true)) {
      const p = h.object.userData.pick; if (!p) continue;
      if (p.npc) { const n = META.npcs.find((q) => q.id === p.npc); if (n) { this.npcCard(n); const t = this.npcs.find((q) => q.n === n); if (t) this.bubble(t); } return; }
      if (p.hero) { this.heroCard(); return; }
      if (p.visitor) { this.visitorCard(p.visitor); return; }
      if (p.grave) { this.graveInfo(p.grave); return; }
      if (p.fire) { this.open('plaza'); return; }
      if (p.furn) { const f = META.settle.furn.find((q) => q.id === p.furn); if (f) { this.openFurn(f); return; } }
    }
    const c = View.dio.pickGround(sx, sy); if (!c) return;
    if (Math.abs(c.x - SCX) <= 1 && Math.abs(c.y - SCY) <= 1) { this.open('plaza'); return; }
    const r = roomAt(c.x, c.y); if (r) this.roomCard(r);
  },
  /** 가구를 누르면 그 기능: 제단 · 출발문 · 창고 더미 · 작업대(방이 있어야) */
  openFurn(f) {
    if (f.k === 'altar') { this.open('altar'); return; }
    if (f.k === 'gate') { this.open('gate'); return; }
    if (f.k === 'heap' || f.k === 'shelf') { this.open('storage'); return; }
    const r = roomAt(f.x, f.y);
    if (r && CRAFT_ROOMS.includes(r.kind)) { this.open(r.kind); return; }
    const need = Object.entries(ROOMS).find(([, R]) => R.need[f.k]);
    UI.toast(need && need[0] !== 'bedroom' ? `${FURN[f.k].name}. 벽과 문으로 둘러싸면 ${jo(ROOMS[need[0]].name, '이가')} 된다.` : FURN[f.k].name);
  },
  roomCard(r) {
    const furn = Object.entries(r.furn).map(([k, n]) => `${FURN[k].icon} ${FURN[k].name}${n > 1 ? ` ${n}` : ''}`).join(' · ') || '가구 없음';
    const hint = !r.kind ? '안에 놓인 가구로 방의 쓰임이 정해진다.' : CRAFT_ROOMS.includes(r.kind) ? `${roomTier(r)}등급 작업방 · 작업대를 누르면 제작 주문.` : '';
    UI.info(`<h3>${r.kind ? ROOMS[r.kind].icon : '▫'} ${roomName(r)} <small style="color:#9aa2bd">${r.cells.size}칸</small></h3><div class="gtxt">${furn}</div>${hint ? `<div class="gtxt" style="color:#9aa2bd">${hint}</div>` : ''}`);
  },
  open(id) {
    Sfx.play('ui');
    if (id === 'gate') this.gate(); else if (id === 'altar') this.altar(); else if (id === 'storage') this.storage(); else if (id === 'plaza') this.rest(); else this.craft(id);
  },
};
