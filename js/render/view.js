import * as THREE from 'three';
import { hitRange } from '../core/combat.js';
import { G, Game, I, XY, itemSnap, tileAt } from '../core/state.js';
import { CATS } from '../data/enemies.js';
import { weaponId } from '../data/gear.js';
import { MATS } from '../data/items.js';
import { COLORS, STONE } from '../data/stones.js';
import { T_DOOR, T_OPEN, T_STAIRS, T_WALL } from '../data/terrain.js';
import { torchTier } from '../data/torch.js';
import { FORMS } from '../data/weapons.js';
import { W3, _tv, _w } from './common.js';
import * as K from './diorama.js';
import { GLOW_TEX, itemDoll, makeGem, matProp, propDoll, weaponDoll } from './dolls.js';
import { EntView, stIcons } from './entity-view.js';
import { ports } from './ports.js';
import { Sfx } from './sfx.js';

export const View = {
  gems: new Map(),
  lamps: new Map(),

  matMeshes: new Map(),
  portal: null,
  shield: 0,
  boost: 1,
  dio: null,
  grid: null,
  evs: new Map(),
  doors: new Map(),
  itemMeshes: new Map(),
  stairs: null,
  labelRoot: null,
  intents: { decals: [], tags: {}, casting: [], winding: [] },
  lightPos: new THREE.Vector3(),
  seen: null,
  vis: null,
  init() {
    this.labelRoot = document.getElementById('labels');
    const dio = this.dio = K.createDiorama(document.getElementById('stage'), { preset: 'dungeon', labelRoot: this.labelRoot });
    dio.lightTarget = this.lightPos;
    dio.rig.onTap = (x, y) => ports.UI.onTap(x, y);
    dio.rig.onLongPress = (x, y) => ports.UI.onLongPress(x, y);
    dio.rig.onLongRelease = () => ports.UI.hideInfo();
    dio.onFrame = (sdt) => (Game.mode === 'town' ? ports.Town.frame(sdt) : this.frame(sdt));
  },
  clear() {
    this.grid?.dispose(); this.grid = null; this.dio.grid = null;
    for (const ev of this.evs.values()) ev.dispose(); this.evs.clear();
    for (const d of this.doors.values()) this.dio.scene.remove(d.root); this.doors.clear();
    for (const m of this.itemMeshes.values()) this.dio.scene.remove(m.root); this.itemMeshes.clear();
    if (this.stairs) this.dio.scene.remove(this.stairs); this.stairs = null;
    for (const g of this.gems.values()) this.dio.scene.remove(g); this.gems.clear();
    for (const g of this.lamps.values()) this.dio.scene.remove(g); this.lamps.clear();
    this.clearGear();
    for (const m of this.matMeshes.values()) this.dio.scene.remove(m); this.matMeshes.clear();
    if (this.portal) { this.dio.scene.remove(this.portal); this.portal = null; }
    for (const m of this.blocks.values()) this.dio.scene.remove(m.root); this.blocks.clear();
    this.dio.labels.clear();
  },
  buildFloor() {
    this.clear();
    const F = G.theme;
    this.dio.setPreset('dungeon');
    this.grid = new K.GridView(this.dio.scene, { w: G.W, h: G.H, kind: this.tileKind, palette: F.pal, wallH: 1.2 });
    this.dio.grid = this.grid;
    for (let i = 0; i < G.W * G.H; i++) if (G.tile[i] === T_DOOR || G.tile[i] === T_OPEN) this.makeDoor(i);
    if (!G.bossFloor) this.makeStairs(G.stairs); else if (G.exitOpen) this.makePortal(G.stairs);
    this.syncMats(); this.syncBlocks();
    for (const e of G.ents) this.evs.set(e.id, new EntView(e));
    this.grid.setTerrain({ surf: G.surf, fire: G.fire, cloud: G.cloud, cloudT: G.cloudT });
    this.applyVis(G.vis, G.seen);
    this.syncItems(itemSnap());
    this.syncGems([...G.stones.entries()]); this.syncGear([...G.gear.entries()]); this.syncChests();
    this.syncLamps();
    this.setWeapon(weaponId(G.eq.weapon), G.eq.weapon); this.shield = G.player.shield || 0;
    this.intents = { decals: [], tags: {}, casting: [], winding: [] };
    const p = G.player; this.lightPos.set(p.x, 0, p.y); this.dio.lightTarget = this.lightPos;
    this.dio.rig.focusT.set(p.x, 0, p.y); this.dio.rig.snap();
    this.refreshDecals();
  },
  makeDoor(i) {
    const [x, y] = XY(i), alongX = tileAt(x - 1, y) === T_WALL && tileAt(x + 1, y) === T_WALL;
    const root = new THREE.Group(); root.position.set(x, 0, y); if (!alongX) root.rotation.y = Math.PI / 2;
    const frame = propDoll([{ s: 'box', p: [-0.46, 0.62, 0], k: [0.12, 1.24, 0.3], c: 0x5a4636 }, { s: 'box', p: [0.46, 0.62, 0], k: [0.12, 1.24, 0.3], c: 0x5a4636 }, { s: 'box', p: [0, 1.2, 0], k: [1.04, 0.14, 0.32], c: 0x5a4636 }], 1);
    const hinge = new THREE.Group(); hinge.position.set(-0.4, 0, 0);
    const panel = propDoll([{ s: 'box', p: [0.4, 0.55, 0], k: [0.8, 1.08, 0.1], c: 0x9a6a3e }, { s: 'box', p: [0.4, 0.3, 0.02], k: [0.82, 0.08, 0.12], c: 0x4a4a55 }, { s: 'box', p: [0.4, 0.82, 0.02], k: [0.82, 0.08, 0.12], c: 0x4a4a55 }, { s: 'sphere', p: [0.7, 0.56, 0.08], k: 0.05, c: 0xffd35a }], 1);
    hinge.add(panel.root); root.add(frame.root, hinge);
    this.dio.scene.add(root);
    const open = G.tile[i] === T_OPEN;
    this.doors.set(i, { root, hinge, open, a: open ? -1.5 : 0 });
  },
  makeStairs(i) {
    const [x, y] = XY(i), g = new THREE.Group(); g.position.set(x, 0, y);
    const steps = propDoll([0, 1, 2, 3].map((k) => ({ s: 'box', p: [0, -0.06 - k * 0.075, -0.33 + k * 0.2], k: [0.92, 0.075, 0.26], c: [0x8a90a8, 0x6a7088, 0x4a5068, 0x2e3248][k] })), 1);
    const glow = new THREE.Mesh(new THREE.PlaneGeometry(0.9, 0.9).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ color: new THREE.Color(0.3, 0.6, 1.6), transparent: true, opacity: 0.8 }));
    glow.position.y = -0.33; g.add(steps.root, glow); g.userData.glow = glow;
    this.dio.scene.add(g); this.stairs = g; g.visible = false;
  },
  syncItems(list) {
    const keep = new Set(list.map(([i]) => i));
    for (const [i, m] of this.itemMeshes) if (!keep.has(i)) { this.dio.scene.remove(m.root); this.itemMeshes.delete(i); }
    for (const [i, k] of list) {
      if (this.itemMeshes.has(i)) continue;
      const d = itemDoll(k), [x, y] = XY(i); d.root.position.set(x, 0, y); d.root.userData.ph = Math.random() * 6;
      this.dio.scene.add(d.root); this.itemMeshes.set(i, d);
    }
    this.applyItemVis();
  },
  applyItemVis() {
    const sn = (i) => !!(this.seen && this.seen[i]);
    for (const [i, d] of this.itemMeshes) d.root.visible = sn(i);
    for (const [i, g] of this.gems) if (!g.userData.drop) g.visible = sn(i);
    for (const [i, m] of this.matMeshes) m.visible = sn(i);
    for (const [i, m] of this.blocks) m.root.visible = sn(i);
  },
  syncGems(list) {
    const keep = new Set(list.map(([i]) => i));
    for (const [i, g] of this.gems) if (!keep.has(i)) { this.dio.scene.remove(g); this.gems.delete(i); }
    for (const [i, id] of list) if (!this.gems.has(i)) { const g = makeGem(id), [x, y] = XY(i); g.position.set(x, 0, y); this.dio.scene.add(g); this.gems.set(i, g); }
    this.applyItemVis();
  },
  syncMats() {
    for (const m of this.matMeshes.values()) this.dio.scene.remove(m); this.matMeshes.clear();
    for (const [i, m] of G.mats) { const g = matProp(m), [x, y] = XY(i); g.position.set(x, 0, y); g.userData.ph = Math.random() * 6; this.dio.scene.add(g); this.matMeshes.set(i, g); }
    this.applyItemVis();
  },
  makePortal(i) {
    const [x, y] = XY(i), g = new THREE.Group(); g.position.set(x, 0, y);
    const ring = new THREE.Mesh(new THREE.TorusGeometry(0.42, 0.07, 10, 32), new THREE.MeshBasicMaterial({ color: new THREE.Color(1.2, 1.9, 3) }));
    const disc = new THREE.Mesh(new THREE.CircleGeometry(0.4, 32), new THREE.MeshBasicMaterial({ color: new THREE.Color(0.5, 0.9, 2.2), transparent: true, opacity: 0.7, side: THREE.DoubleSide, blending: THREE.AdditiveBlending, depthWrite: false }));
    ring.position.y = disc.position.y = 0.62; g.add(ring, disc); g.userData = { ring, disc };
    this.dio.scene.add(g); this.portal = g;
  },
  /** 손에 든 무기 모양. it이 아는 원소 브랜드면 칼날에 그 빛 */
  setWeapon(id, it) {
    const pe = this.evs.get(0); if (!pe || !pe.extra.wh) return;
    const wh = pe.extra.wh; for (const c of [...wh.children]) if (!c.userData.keep) wh.remove(c); // 양손 무기의 둘째 손(keep)은 남긴다
    const d = weaponDoll(id, it); wh.add(d.root);
    const b = it && it.idX && it.brand, el = b && { fire: 0xff5a1a, frost: 0x6ac8ff, bolt: 0xffe14a, poison: 0x5ad84a }[b];
    if (el) d.mat.emissive.setHex(el).multiplyScalar(0.55);
  },
  applyVis(vis, seen) {
    this.vis = vis; this.seen = seen;
    const lvl = new Uint8Array(vis.length); for (let i = 0; i < vis.length; i++) lvl[i] = vis[i] ? 2 : seen[i] ? 1 : 0;
    this.grid.setVisibility(lvl);
    for (const [i, d] of this.doors) d.root.visible = !!seen[i];
    if (this.stairs) this.stairs.visible = !!seen[G.stairs];
    this.applyItemVis();
  },
  pickTile(sx, sy) {
    const ray = this.dio.ray(sx, sy), meshes = [];
    for (const ev of this.evs.values()) if (ev.id !== 0 && ev.visible && !ev.dead) meshes.push(ev.d.mesh);
    const hit = ray.intersectObjects(meshes, false)[0];
    if (hit) for (const ev of this.evs.values()) if (ev.d.mesh === hit.object) { const e = G.ents.find((q) => q.id === ev.id); if (e && e.alive) return { x: e.x, y: e.y }; }
    return this.dio.pickGround(sx, sy);
  },
  refreshDecals() {
    if (!this.grid) return;
    const list = [...this.intents.decals], p = G.player;
    if (ports.UI.mode === 'target') list.push(...ports.UI.targetDecals());
    const hi = G.ents.find((e) => e.id === ports.UI.highlightEnemy && e.alive);
    if (hi) {
      list.push({ x: hi.x, y: hi.y, kind: 4, color: 0xffdf79, alpha: 1, blink: 0.5 });
      for (const q of this.intents.decals) if (q.kind !== 1) list.push({ ...q, alpha: 1 });
    }
    if (G.seen[G.stairs] && G.tile[G.stairs] === T_STAIRS) list.push({ x: G.stairs % G.W, y: (G.stairs / G.W) | 0, kind: 4, color: 0x7fb8ff, alpha: 0.9, blink: 0.6, scale: 1.15 });
    this.grid.setDecals(list);
  },
  syncLamps() {
    for (const [i, g] of this.lamps) if (!G.lamps?.has(i)) { this.dio.scene.remove(g); this.lamps.delete(i); }
    for (const [i] of G.lamps || []) if (!this.lamps.has(i)) {
      const g = new THREE.Group(), x = i % G.W, y = (i / G.W) | 0;
      g.position.set(x, 0, y);
      const metal = new THREE.MeshStandardMaterial({ color: 0x9a7042, metalness: .28, roughness: .48 });
      const stem = new THREE.Mesh(new THREE.CylinderGeometry(.055, .075, .28, 8), metal); stem.position.y = .16;
      const foot = new THREE.Mesh(new THREE.CylinderGeometry(.18, .21, .07, 8), metal); foot.position.y = .035;
      const cup = new THREE.Mesh(new THREE.CylinderGeometry(.15, .12, .065, 8), metal); cup.position.y = .34;
      const cap = new THREE.Mesh(new THREE.ConeGeometry(.19, .15, 8), metal); cap.position.y = .69;
      const flame = new THREE.Mesh(new THREE.ConeGeometry(.09, .22, 7), new THREE.MeshBasicMaterial({ color: 0xffd878 })); flame.position.y = .51;
      const halo = new THREE.Sprite(new THREE.SpriteMaterial({ map: GLOW_TEX, color: 0xffc46a, blending: THREE.AdditiveBlending, transparent: true, depthWrite: false, opacity: .45 }));
      halo.position.y = .52; halo.scale.set(.95, .95, 1);
      g.add(stem, foot, cup, halo, flame, cap);
      for (const [bx, bz] of [[-.12, 0], [.12, 0], [0, -.12], [0, .12]]) {
        const bar = new THREE.Mesh(new THREE.CylinderGeometry(.012, .012, .29, 5), metal); bar.position.set(bx, .52, bz); g.add(bar);
      }
      g.userData.flame = flame; g.userData.halo = halo;
      this.dio.scene.add(g); this.lamps.set(i, g);
    }
  },
  /** 모든 인형: 지난 틱과 이번 틱 사이를 G.alpha만큼 보간한 자리. 서 있는 적은 노리는 쪽을 본다 */
  placeUnits(dt) {
    const a = G.alpha ?? 1;
    for (const e of G.ents) {
      if (!e.alive || e.px == null) continue;
      const ev = this.evs.get(e.id); if (!ev) continue;
      const ox = e.ppx ?? e.px, oy = e.ppy ?? e.py;
      ev.place(ox + (e.px - ox) * a, oy + (e.py - oy) * a, dt);
      if (e.id !== 0 && !ev.walking && e.ang != null) ev.yawT = Math.atan2(Math.cos(e.ang), Math.sin(e.ang));
    }
  },
  frame(sdt) {
    ports.Loop.frame(sdt);
    const time = K.SHARED.uTime.value, D = this.dio;
    const casting = new Set(this.intents.casting), winding = new Set(this.intents.winding);
    this.placeUnits(sdt);
    this.syncProjs(sdt, time);
    for (const [id, ev] of this.evs) {
      ev.casting = casting.has(id); ev.winding = winding.has(id);
      ev.update(sdt, time);
      if (ev.gone) { ev.dispose(); this.evs.delete(id); }
    }
    const pev = this.evs.get(0);
    D.rig.followRate = 16; // 던전: 걷는 등불지기를 바짝 따라간다(정착지는 기본 6.5)
    if (pev) { D.rig.focusT.set(pev.cur.x, 0, pev.cur.z); this.lightPos.copy(pev.d.root.position); }
    const tier = torchTier(G.torch ?? 100);
    // 밝기: 가장 어두울 때(꺼짐)가 예전의 가장 밝을 때(거리 10 · 세기 42), 밝을수록 더 밝다
    D.lights.torch.distance = tier === 'out' ? 10 : tier === 'low' ? 11 : tier === 'mid' ? 12.5 : 14;
    D.lights.base = tier === 'out' ? 42 : tier === 'low' ? 50 : tier === 'mid' ? 60 : 72;
    this.syncLamps();
    for (const [i, g] of this.lamps) { g.visible = !!G.seen[i]; g.userData.flame.scale.y = .85 + Math.sin(time * 9 + i) * .16; g.userData.halo.material.opacity = .35 + Math.sin(time * 7 + i) * .08; }
    for (const [, d] of this.itemMeshes) { if (!d.root.visible) continue; d.root.position.y = 0.05 + Math.abs(Math.sin(time * 2.4 + d.root.userData.ph)) * 0.09; d.root.rotation.y = time * 0.9 + d.root.userData.ph; }
    for (const [, d] of this.doors) { const tgt = d.open ? -1.5 : 0; d.a += (tgt - d.a) * Math.min(1, sdt * 12); d.hinge.rotation.y = d.a; }
    if (this.stairs) this.stairs.userData.glow.material.opacity = 0.55 + Math.sin(time * 2.5) * 0.25;
    for (const [, m] of this.matMeshes) { m.position.y = 0.02 + Math.abs(Math.sin(time * 2 + m.userData.ph)) * 0.05; if (m.visible && Math.random() < sdt * 1.5) this.dio.sparks.emit({ pos: _w.set(m.position.x, 0.4, m.position.z), n: 1, color: 0xfff2b0, speed: 0.4, up: 0.6, grav: 0, life: 0.6, size: 0.09 }); }
    if (this.portal) { const u = this.portal.userData; u.ring.rotation.y = time * 1.5; u.disc.lookAt(this.dio.camera.position); u.disc.material.opacity = 0.5 + Math.sin(time * 4) * 0.2; if (Math.random() < sdt * 20) this.dio.sparks.emit({ pos: _w.set(this.portal.position.x, 0.6, this.portal.position.z), n: 1, color: 0x7fb8ff, color2: 0xffffff, speed: 1, up: 1, grav: 0, life: 0.7, size: 0.1, spread: 0.4 }); }
    for (const [, g] of this.gems) {
      const u = g.userData;
      if (u.drop) {
        const dr = u.drop; dr.t = Math.min(1, dr.t + sdt / 0.95); const k = dr.t, m = Math.min(1, k / 0.55);
        g.position.x = dr.fx + (dr.tx - dr.fx) * m; g.position.z = dr.fy + (dr.ty - dr.fy) * m;
        g.position.y = Math.abs(Math.sin(Math.PI * 3.2 * Math.sqrt(k))) * 1.0 * Math.pow(1 - k, 1.5);
        if (k >= 1) { u.drop = null; g.visible = !!(this.seen && this.seen[I(dr.tx, dr.ty)]); }
      } else g.position.y = 0.04 + Math.sin(time * 2.2 + u.ph) * 0.05;
      u.crystal.rotation.y = time * 1.6 + u.ph; u.glow.material.opacity = 0.5 + 0.3 * Math.sin(time * 3 + u.ph);
    }
    this.gearFrame(sdt, time);
    const s = {};
    for (const ev of this.evs.values()) {
      const r = ev.d.root, txtIntent = this.intents.tags[ev.id] || '', txtSt = stIcons(ev.st), show = r.visible && !ev.dead && (ev.id !== 0 || txtSt);
      if (!show) { if (ev.tagShown) { ev.tag.style.display = 'none'; ev.tagShown = false; } continue; }
      if (!ev.tagShown) { ev.tag.style.display = ''; ev.tagShown = true; }
      D.labels.toScreen(_tv.set(r.position.x, r.position.y + ev.h + 0.18, r.position.z), s);
      ev.tag.style.transform = `translate(${s.x.toFixed(1)}px,${s.y.toFixed(1)}px) translate(-50%,-100%)`;
      let extra = '';
      if (ev.cat) {
        if (G.weakKnown[ev.cat]) extra += `<span class="wk">${FORMS[CATS[ev.cat].weak].icon}</span>`;
        const e = G.ents.find((q) => q.id === ev.id); // ◆ 한 방에 쓰러뜨릴 수 있음 · ×2 치명 조건 충족
        if (e && ev.hp <= hitRange(e)[1]) extra += '<b class="fin" style="color:#ffe38a">◆</b>';
      }
      const txt = txtIntent + extra + txtSt;
      if (txt !== ev.tagTxt) { ev.tagTxt = txt; ev.tagIco.innerHTML = txt; ev.tagIco.className = 'ico' + (txtIntent && txtIntent !== '💤' ? ' intent' : ''); }
      if (ev.tagHp) { const w = Math.round(Math.max(0, ev.hp / ev.max) * 100); if (w !== ev.tagW) { ev.tagW = w; ev.tagHp.style.width = w + '%'; } }
    }
  },
  /* ---------- 사건 → 연출 ---------- */
  on(type, d) {
    if (this.gearOn(type, d) || this.storyOn(type, d)) return;
    const D = this.dio, ev = d && d.id != null ? this.evs.get(d.id) : null;
    switch (type) {
      case 'move': if (ev) { ev.moveTo(d.x, d.y, d.dur, d.hop, d.kind); ev.visible = d.id === 0 || !!d.seen; if (d.kind === 'step' && ev.visible) D.puffs.emit({ pos: W3(ev.cur.x, ev.cur.z, 0.06), n: 2, color: 0x8a8098, speed: 0.4, grav: 0, life: 0.4, size: 0.18, flat: true }); if (d.id === 0 && d.kind === 'step') Sfx.play('step'); if (d.kind === 'dash') D.puffs.emit({ pos: W3(ev.cur.x, ev.cur.z, 0.1), n: 3, color: 0x9a8e80, speed: 0.8, grav: 0, life: 0.5, size: 0.3, flat: true }); } break;
      case 'face': if (ev) ev.yawT = Math.atan2(d.dx, d.dy); break;
      case 'lunge': ev?.lunge(d.dx, d.dy, d.amt ?? 0.36); if (ev && d.id === 0) Sfx.play('swing'); break;
      case 'bump': if (ev) { ev.lunge(d.dx, d.dy, 0.3); D.puffs.emit({ pos: W3(ev.cur.x + d.dx * 0.5, ev.cur.z + d.dy * 0.5, 0.5), n: 10, color: 0xa89c8c, color2: 0x6a6258, speed: 1.8, grav: 0, life: 0.6, size: 0.35, grow: 0.8 }); D.sparks.emit({ pos: W3(ev.cur.x + d.dx * 0.5, ev.cur.z + d.dy * 0.5, 0.6), n: 12, color: 0xffe0a0, speed: 4, life: 0.3, size: 0.1 }); } break;
      case 'hit': this.hitFx(ev, d); break;
      case 'heal': if (ev) { D.labels.pop(W3(ev.cur.x, ev.cur.z, 1.1), '+' + d.amt, { color: '#7dffa0', cls: 'big' }); D.sparks.emit({ pos: W3(ev.cur.x, ev.cur.z, 0.6), n: 18, color: 0x7dffa0, color2: 0xffffff, speed: 1.2, up: 2, grav: 0, life: 0.8, size: 0.12, spread: 0.4 }); Sfx.play('heal'); } break;
      case 'hp': if (ev) { ev.hp = d.hp; ev.max = d.max; } if (d.id === 0) ports.UI.hp(d.hp, d.max); break;
      case 'status': if (ev) ev.st = d.st; if (d.id === 0) ports.UI.pstatus(d.st); break;
      case 'die': this.dieFx(ev, d); break;
      case 'terrain': this.grid.setTerrain(d); for (const [i, dd] of this.doors) dd.open = d.tile[i] === T_OPEN; break;
      case 'vis': this.applyVis(d.vis, d.seen); for (const [id, v] of d.ents) { const e2 = this.evs.get(id); if (e2) e2.visible = id === 0 || !!v; } break;
      case 'intents': this.intents = d; this.refreshDecals(); break;
      case 'hud': ports.UI.hud(d); break;
      case 'log': ports.UI.log(d.t, d.cls); break;
      case 'banner': ports.UI.banner(d.text, d.elem); break;
      case 'shake': D.rig.shake(d.a); break;
      case 'items': this.syncItems(d); break;
      case 'door': { const dd = this.doors.get(I(d.x, d.y)); if (dd) dd.open = d.open; Sfx.play('door'); break; }
      case 'gameover': setTimeout(() => ports.UI.gameOver(), 900); break;
      case 'swing': if (ev) { ev.swing = { t: 0, form: d.form }; ev.lunge(d.dx, d.dy, d.form === 'pierce' ? 0.45 : 0.3); } this.swingFx(d, ev); break;
      case 'stone': this.stoneFx(d); break;
      case 'free': if (ev) { if (ev.extra.cage) { const c = ev.extra.cage; this.dio.fx.add(c, 0.4, (k) => { c.position.y = k * 1.5; c.scale.setScalar(1 - k); }, false); } ev.sqv += 6; this.dio.labels.pop(W3(ev.cur.x, ev.cur.z, 1.4), '고마워요!', { color: '#9dffb5', cls: 'word', vx: 0 }); this.dio.sparks.emit({ pos: W3(ev.cur.x, ev.cur.z, 0.6), n: 20, color: 0xfff2b0, color2: 0xffffff, speed: 2, up: 1.5, grav: 0, life: 0.6, size: 0.12 }); Sfx.play('pick'); } break;
      case 'loot': this.dio.labels.pop(W3(d.x, d.y, 1.0), `+${MATS[d.m] || '📜'} ${d.m}`, { color: '#ffe38a', cls: 'word', vx: 20, rise: 40, dur: 1.1, delay: 0.25 }); break;
      case 'matPick': { const i = I(d.x, d.y), m = this.matMeshes.get(i); if (m) { this.dio.scene.remove(m); this.matMeshes.delete(i); } this.dio.labels.pop(W3(d.x, d.y, 0.9), `+${MATS[d.m]} ${d.m}`, { color: '#ffe38a', cls: 'word', vx: 0 }); this.dio.sparks.emit({ pos: W3(d.x, d.y, 0.3), n: 14, color: 0xfff2b0, speed: 1.5, up: 1.5, grav: 0, life: 0.5, size: 0.1 }); Sfx.play('pick'); break; }
      case 'portal': this.makePortal(I(d.x, d.y)); this.dio.fx.ring(W3(d.x, d.y), 0x7fb8ff, 0.2, 3, 0.8); this.dio.pool.flash(W3(d.x, d.y), 0x9fd0ff, 80, 1, 9); Sfx.play('tele'); break;
      case 'horn': if (ev) { ev.sqv += 7; this.dio.labels.pop(W3(ev.cur.x, ev.cur.z, ev.h + 0.4), '📯 뿌우우!', { color: '#ffd08a', cls: 'word', vx: 0, rise: 40 }); this.dio.fx.ring(W3(ev.cur.x, ev.cur.z), 0xffd08a, 0.3, 3, 0.6); this.dio.rig.shake(0.3); Sfx.play('snort'); } break;
      case 'chainStage': this.boost = 1 + 0.2 * (d.stage - 1); if (d.stage > 3 && this._slow) { ports.UI.banner(`연쇄 ${d.stage}단계!`, 'chain'); clearTimeout(this._sm); this._sm = setTimeout(() => this.endSlow(), 450); } break;
      case 'chainEnd': this.boost = 1; break;
      case 'slowmo': this.slowmo(d.stage); break;
      case 'slots': ports.UI.renderSlots(d); break;
      case 'stoneDrop': {
        const [tx, ty] = d.to, i = I(tx, ty); let g = this.gems.get(i);
        if (!g) { g = makeGem(d.id); this.dio.scene.add(g); this.gems.set(i, g); }
        g.userData.drop = { t: 0, fx: d.from[0], fy: d.from[1], tx, ty }; g.position.set(d.from[0], 0.6, d.from[1]); g.visible = true;
        this.dio.labels.pop(W3(d.from[0], d.from[1], 1.2), d.part, { color: COLORS[STONE[d.id].color].css, cls: 'word', vx: 0, rise: 34, dur: 1.2 });
        Sfx.play('gem'); break;
      }
      case 'stonePick': {
        const i = I(d.x, d.y), g = this.gems.get(i); if (g) { this.gems.delete(i); const y0 = g.position.y; this.dio.fx.add(g, 0.4, (k) => { g.position.y = y0 + k * 1.6; g.scale.setScalar(1 + k * 0.6 - k * k * 1.4); }, false); }
        this.dio.sparks.emit({ pos: W3(d.x, d.y, 0.4), n: 20, color: COLORS[STONE[d.id].color].hex, color2: 0xffffff, speed: 2, up: 2, grav: 0, life: 0.6, size: 0.13 });
        Sfx.play('pickgem'); break;
      }
      case 'stoneFade': {
        const i = I(d.x, d.y), g = this.gems.get(i); if (g) { this.gems.delete(i); const s0 = g.scale.x; this.dio.fx.add(g, 0.45, (k) => { g.scale.setScalar(s0 * (1 - k)); g.position.y += 0.004; }, false); }
        this.dio.puffs.emit({ pos: W3(d.x, d.y, 0.4), n: 12, color: COLORS[STONE[d.id].color].hex, speed: 1.2, grav: 0, life: 0.6, size: 0.25 });
        break;
      }
      case 'spawn': { const nv = new EntView(d.e); nv.visible = d.seen == null ? true : !!d.seen; this.evs.set(d.e.id, nv); this.dio.puffs.emit({ pos: W3(d.e.x, d.e.y, 0.5), n: 14, color: 0xc8a0ff, color2: 0xffffff, speed: 1.8, grav: 0, life: 0.6, size: 0.35, grow: 1 }); Sfx.play('tele'); break; }
      case 'vanish': if (ev) { ev.dead = true; ev.deadT = 0; this.dio.puffs.emit({ pos: W3(ev.cur.x, ev.cur.z, 0.5), n: 10, color: 0xc8a0ff, speed: 1.5, grav: 0, life: 0.5, size: 0.3 }); } break;
      case 'shield': this.shield = d.v; { const pe = this.evs.get(0); if (pe) { pe.bubbleHit = 1; this.dio.labels.pop(W3(pe.cur.x, pe.cur.z, 1.4), `🛡+${d.add}`, { color: '#9fd8ff', cls: 'word', vx: 0 }); } } ports.UI.shieldV = d.v; ports.UI.pstatus(ports.UI.lastSt || G.player.st); Sfx.play('shield'); break;
      case 'shieldHit': this.shield = d.left; { const pe = this.evs.get(0); if (pe) { pe.bubbleHit = 1; this.dio.labels.pop(W3(pe.cur.x, pe.cur.z, 1.2), `🛡${d.absorbed}`, { color: '#9fd8ff', cls: 'big' }); this.dio.sparks.emit({ pos: W3(pe.cur.x, pe.cur.z, 0.6), n: 16, color: 0x9fd8ff, color2: 0xffffff, speed: 3, life: 0.35, size: 0.12 }); } } ports.UI.shieldV = d.left; ports.UI.pstatus(ports.UI.lastSt || G.player.st); Sfx.play('shield'); break;
      case 'weakReveal': if (ev) { this.dio.labels.pop(W3(ev.cur.x, ev.cur.z, ev.h + 0.7), `약점 발견 ${FORMS[d.form].icon}`, { color: '#ffe14a', cls: 'word', vx: 0, rise: 50, dur: 1.4 }); ports.UI.toast(`${FORMS[d.form].icon} 약점을 알아냈다.`); } break;
      default: this.fx(type, d, ev);
    }
  },
};
