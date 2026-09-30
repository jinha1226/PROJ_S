import { FLOOR_TYPES, TR, WALLS, ZONE_TYPES } from '../data/build.js';
import * as K from '../render/diorama.js';
import { dollSpecBase, weaponDoll } from '../render/dolls.js';
import { heroSpec } from '../render/hero-doll.js';
import { SettleView } from '../render/settle-view.js';
import { ROLE_COLOR, THREAT, hurtLevel, isWall, swingOffset, tileAt, windupLevel } from './scenes.js';

/* ================= A: 지금 모습 (DioramaKit 그대로: 인형 · 툰 · 윤곽선 · 틸트시프트) =================
   던전은 레이드 실험실과 같은 GridView + 인형, 정착지는 본편 SettleView + 주민 인형. */
const { THREE } = K;
const PALETTE = { floor: 0x34313b, floor2: 0x3e3943, wall: 0x74717b, wall2: 0x5c5864, void: 0x08070c, grassFloor: 0x3b523c, waterFloor: 0x23445f, dim: 0.5 };
/** 레이드 실험실의 파티 차림 (js/lab/view.js LOOK과 같다) */
const LOOK = {
  hero: { weapon: 'sword', eq: { body: { base: 'body_leather' }, cloak: { base: 'cloak' } } },
  guard: { weapon: 'mace', eq: { body: { base: 'body_plate' }, head: { base: 'head_chain' }, off: { base: 'shield' } } },
  sword: { weapon: 'greatsword', eq: { body: { base: 'body_chain' } } },
  archer: { weapon: 'crossbow', eq: { body: { base: 'body_leather' }, head: { base: 'head_leather' } } },
  healer: { weapon: null, eq: { body: { base: 'body_cloth' }, head: { base: 'head_cloth' }, off: { base: 'orb_green' } } },
};
const NPC_JOB = { walk: 'cook', farm: 'herbalist', craft: 'blacksmith', haul: 'hunter' };
const SKINS = [0xf2c8a0, 0xd8a47a, 0xb07a52, 0xf0d0b0];
const FURN_OF = { bench: 'herbtable', logs: 'heap' };
const basic = (color, opacity, add = false) => new THREE.MeshBasicMaterial({ color, transparent: true, opacity, depthWrite: false, side: THREE.DoubleSide, blending: add ? THREE.AdditiveBlending : THREE.NormalBlending });
const flat = (geo) => geo.rotateX(-Math.PI / 2);

export class StyleA {
  constructor(host) {
    this.host = host;
    this.wrap = document.createElement('div'); this.wrap.className = 'sl-layer'; host.appendChild(this.wrap);
    this.labels = document.createElement('div'); this.labels.className = 'sl-labels'; host.appendChild(this.labels);
    const dio = this.dio = K.createDiorama(this.wrap, { preset: 'dungeon', labelRoot: this.labels });
    dio.rig.minZoom = dio.rig.maxZoom = 1; // 고정 시점
    dio.rig.onTap = null;
    this.on = true; this.st = null; this.sc = null; this.built = {};
    this.lightPos = new THREE.Vector3();
    // 꺼져 있을 때는 그리지 않는다(createDiorama는 스스로 프레임을 돈다)
    const render = dio.post.render.bind(dio.post);
    dio.post.render = () => { if (this.on) render(); };
    dio.onFrame = (dt) => { if (this.on && this.st) this.update(this.st, dt); };
  }
  show(on) { this.on = on; this.wrap.style.display = on ? 'block' : 'none'; if (on) this.resize(); }
  resize() { this.dio.resize(); this.frameCam(); }
  setFrozen(f) { this.dio.timeScale = f ? 0 : 1; }
  frameCam() {
    const sc = this.sc; if (!sc) return;
    const rig = this.dio.rig; rig.tilesAcross = sc.w + 0.6; rig.pitchT = rig.TOP; rig.yawT = 0; rig.zoomT = 1;
    rig.fit(this.wrap.clientWidth / Math.max(1, this.wrap.clientHeight));
    rig.focusT.set((sc.w - 1) / 2, 0, (sc.h - 1) / 2 + 0.3); rig.snap();
    this.dio.resize();
  }
  setScene(sc) {
    this.sc = sc;
    for (const [id, b] of Object.entries(this.built)) b.group.visible = id === sc.id;
    const b = this.built[sc.id] ||= sc.id === 'settle' ? this.buildSettle(sc) : this.buildDungeon(sc);
    b.group.visible = true; this.cur = b;
    this.dio.setPreset(sc.id === 'settle' ? 'settlement' : 'dungeon');
    this.dio.grid = b.grid || null;
    if (this.built.settle) this.built.settle.view.group.visible = sc.id === 'settle';
    if (this.built.dungeon) this.built.dungeon.grid.group.visible = sc.id === 'dungeon';
    this.dio.lightTarget = sc.id === 'dungeon' ? this.lightPos : null;
    this.frameCam();
  }
  render(st) { this.st = st; } // 실제 그리기는 디오라마 프레임에서
  /* ---------- 던전 ---------- */
  buildDungeon(sc) {
    const scene = this.dio.scene, group = new THREE.Group(); scene.add(group);
    const W = sc.w, H = sc.h, surf = new Uint8Array(W * H);
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) { const c = tileAt(sc, x, y); surf[y * W + x] = c === '~' ? K.SURF.WATER : c === '"' ? K.SURF.GRASS : 0; }
    const grid = new K.GridView(scene, { w: W, h: H, kind: (i) => (isWall(tileAt(sc, i % W, (i / W) | 0)) ? 'wall' : 'floor'), palette: PALETTE, wallH: 1.2 });
    grid.setTerrain({ surf });
    const torch = new THREE.PointLight(0xffbe78, 10, 7); group.add(torch);
    const actors = sc.actors.map((a) => this.dungeonActor(a, group));
    // 예고: 테두리 · 옅은 바탕 · 차오르는 안쪽
    const tele = sc.tele.map((T) => {
      const g = new THREE.Group(); group.add(g);
      const th0 = -T.ang - T.half, len = T.half * 2;
      const geos = T.type === 'fan'
        ? [new THREE.RingGeometry(T.r - 0.14, T.r, 40, 1, th0, len), new THREE.CircleGeometry(T.r, 40, th0, len), new THREE.CircleGeometry(T.r, 40, th0, len)]
        : [new THREE.RingGeometry(T.r - 0.12, T.r, 40), new THREE.CircleGeometry(T.r, 40), new THREE.CircleGeometry(T.r, 40)];
      const [edge, base, fill] = geos.map((geo, n) => { const m = new THREE.Mesh(flat(geo), basic(n === 0 ? 0xff5a5a : n === 1 ? 0xf34750 : 0xff3040, [0.85, 0.18, 0.42][n])); m.position.y = 0.09 + n * 0.005; g.add(m); return m; });
      return { g, edge, base, fill };
    });
    const arc = new THREE.Mesh(new THREE.RingGeometry(0.95, 1.35, 24, 1, -0.55, 1.1).rotateX(-Math.PI / 2), basic(0xffffff, 0.9, true)); group.add(arc);
    const shots = sc.shots.map((S) => { const m = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.04, 0.04), new THREE.MeshBasicMaterial({ color: S.foe ? 0xd8d0ff : 0xfff0c8 })); group.add(m); return m; });
    const warn = new THREE.Mesh(new THREE.RingGeometry(0.72, 1.05, 24, 1, -0.55, 1.1).rotateX(-Math.PI / 2), basic(0xff4a3a, 0.5)); group.add(warn);
    return { group, grid, actors, tele, arc, shots, warn, torch };
  }
  dungeonActor(a, group) {
    const look = LOOK[a.kind], foe = a.side === 'foe';
    const eq = look && { ...look.eq, ...(look.weapon ? { weapon: { base: look.weapon } } : {}) };
    const sp = a.kind === 'boss' ? dollSpecBase({ type: 'charger' }) : a.kind === 'goblin' ? dollSpecBase({ type: 'goblin' }) : a.kind === 'skeleton' ? dollSpecBase({ type: 'archer' }) : heroSpec(eq || {});
    const scale = a.kind === 'boss' ? 2.1 : foe ? 0.85 : 1.15;
    const doll = K.doll(sp.parts, { scale, gloss: 0.28 });
    const col = foe ? 0xff4a4a : new THREE.Color(ROLE_COLOR[a.role]).getHex();
    const ring = new THREE.Mesh(new THREE.RingGeometry(a.kind === 'boss' ? 0.68 : 0.34, a.kind === 'boss' ? 0.76 : 0.41, 32).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ color: col, side: THREE.DoubleSide, transparent: true, opacity: 0.9 }));
    ring.position.y = 0.08; doll.root.add(ring);
    let wh = null;
    if (look && sp.extra) { wh = sp.extra(doll).wh; if (look.weapon) wh.add(weaponDoll(look.weapon).root); }
    group.add(doll.root);
    return { a, doll, wh, h: (sp.h || 1) * scale };
  }
  /* ---------- 정착지 ---------- */
  buildSettle(sc) {
    const scene = this.dio.scene, group = new THREE.Group(); scene.add(group);
    const W = sc.w, H = sc.h, N = W * H, S = { W, H, cx: sc.hearth.x, cy: sc.hearth.y, terr: new Uint8Array(N), floor: new Uint8Array(N), wall: new Uint8Array(N), zone: new Uint8Array(N), furn: [] };
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
      const i = y * W + x, c = tileAt(sc, x, y);
      S.terr[i] = c === 'g' ? TR.grass : TR.dirt;
      if (c === '=' || c === 'D' || c === 'W' || c === 'S') S.floor[i] = c === 'S' ? FLOOR_TYPES.stone.id : FLOOR_TYPES.wood.id;
      if (c === 'W') S.wall[i] = WALLS.wood.id; else if (c === 'S') S.wall[i] = WALLS.stone.id; else if (c === 'D') S.wall[i] = WALLS.door.id;
      if (c === 'f') { S.zone[i] = ZONE_TYPES.field.id; S.floor[i] = FLOOR_TYPES.dirt.id; } else if (c === 's') S.zone[i] = ZONE_TYPES.stock.id;
    }
    let n = 0;
    for (const p of sc.props) {
      const i = p.y * W + p.x;
      if (p.k === 'tree') S.terr[i] = TR.tree; else if (p.k === 'rock') S.terr[i] = TR.rock;
      else if (p.k === 'crate' || p.k === 'sack' || p.k === 'stones') continue;
      else S.furn.push({ id: 'f' + n++, k: FURN_OF[p.k] || p.k, x: p.x, y: p.y, rot: p.rot || 0 });
    }
    const view = new SettleView(scene); view.setWorld(S); view.setLight(sc.light.r); view.setFire(2);
    // 창고 짐: 상자 · 자루 · 돌 (한 인형으로)
    const stock = [];
    for (const p of sc.props) {
      if (p.k === 'crate') stock.push({ s: 'box', p: [p.x, 0.22, p.y], k: [0.5, 0.44, 0.5], c: 0xb07a48 }, { s: 'box', p: [p.x + 0.05, 0.56, p.y], k: [0.34, 0.26, 0.34], c: 0xc08a50 });
      else if (p.k === 'sack') stock.push({ s: 'sphere', p: [p.x, 0.2, p.y], k: [0.26, 0.22, 0.24], c: 0xd8c8a0 });
      else if (p.k === 'stones') stock.push(...[[-0.15, 0], [0.15, 0.1], [0, -0.15]].map(([dx, dz], k) => ({ s: 'ico', p: [p.x + dx, 0.1, p.y + dz], k: [0.16, 0.12, 0.15], c: k ? 0x9a968c : 0xaaa69c })));
    }
    // 밭 작물: 칸마다 싹 여섯
    const crops = [];
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) if (tileAt(sc, x, y) === 'f') for (let r = 0; r < 2; r++) for (let q = 0; q < 3; q++) crops.push({ s: 'cone', p: [x - 0.3 + q * 0.3, 0.14, y - 0.22 + r * 0.44], k: [0.08, 0.26, 0.08], seg: 5, c: [0x5ad84a, 0x6ac84a][(x + y + q) % 2] });
    for (const parts of [stock, crops]) { const d = K.doll(parts, { gloss: 0.3 }); d.mesh.receiveShadow = true; group.add(d.root); }
    const actors = sc.actors.map((a, k) => {
      const npc = { id: a.id, name: a.id, job: NPC_JOB[a.job], mood: 1, look: { skin: SKINS[k % SKINS.length], hair: a.hair, cloth: a.cloth } };
      const sp = dollSpecBase({ type: 'npc', npcData: npc });
      const doll = K.doll(sp.parts, { scale: sp.scale * 1.05, gloss: 0.22 });
      group.add(doll.root);
      let box = null;
      if (a.job === 'haul') { box = K.doll([{ s: 'box', p: [0, 0.62, 0.3], k: [0.34, 0.26, 0.28], c: 0xb07a48 }]); doll.body.add(box.root); }
      return { a, doll, h: sp.h, box };
    });
    return { group, view, actors, grid: null };
  }
  /* ---------- 매 프레임 ---------- */
  update(st, dt) {
    const b = this.cur; if (!b) return;
    const t = st.t;
    for (const s of st.actors) {
      const A = b.actors.find((q) => q.a === s.a); if (!A) continue;
      const r = A.doll.root, hurt = hurtLevel(s), wl = windupLevel(s);
      const back = hurt * 0.12, shiver = s.a.kind === 'boss' && s.k > 0.5 && !s.burst ? Math.sin(t * 46) * 0.05 * s.k : 0;
      const step = s.walk ? Math.abs(Math.sin(s.walk)) * 0.08 : 0;
      r.position.set(s.x - Math.cos(s.ang) * back + shiver, step, s.y - Math.sin(s.ang) * back);
      r.rotation.y = Math.atan2(Math.cos(s.ang), Math.sin(s.ang));
      A.doll.pivot.position.y = s.bob * 0.02;
      A.doll.pivot.rotation.x = wl ? -0.25 * wl : s.a.job === 'farm' && !s.walk ? 0.25 + Math.sin(s.k * Math.PI * 2) * 0.1 : 0;
      const sq = hurt * 0.2; A.doll.pivot.scale.set(1 + sq * 0.5, 1 - sq, 1 + sq * 0.5);
      const em = A.doll.mat.emissive; em.setRGB(0, 0, 0);
      if (hurt) em.setRGB(hurt, hurt, hurt);
      if (wl) em.setRGB(0.35 * wl, 0.08 * wl, 0);
      if (A.wh) { const sw = swingOffset(s); A.wh.rotation.set(0.2 + Math.max(0, -sw) * 0.6, s.act === 'swing' || s.act === 'fight' ? sw : 0, 0.45); }
      if (A.box) A.box.root.visible = !!s.carry;
      if (s.a.id === 'hero') { this.lightPos.set(s.x, 0, s.y); if (b.torch) b.torch.position.set(s.x + 0.3, 1.8, s.y + 0.3); }
    }
    if (b.view) b.view.frame(dt, t);
    if (b.tele) st.tele.forEach((T, n) => {
      const m = b.tele[n]; if (!m) return;
      m.g.position.set(T.x, 0, T.y);
      const pulse = 0.75 + 0.25 * Math.sin(t * (8 + T.fill * 14));
      m.edge.material.opacity = 0.85 * pulse;
      m.fill.scale.setScalar(Math.max(0.02, T.burst ? 1 : T.fill)); m.fill.material.opacity = T.burst ? 0.7 * (1 - T.burst) : 0.42;
    });
    if (b.arc) {
      const S = st.swing; b.arc.visible = !!S;
      if (S) { b.arc.position.set(S.x, 0.55, S.y); b.arc.rotation.y = -(S.ang - 1.0 + 2.0 * S.k); b.arc.material.opacity = 0.95 * (1 - S.k * 0.7); }
    }
    if (b.shots) b.shots.forEach((m, n) => {
      const s = st.shots.find((q) => q.foe === this.sc.shots[n].foe); m.visible = !!s;
      if (s) { m.position.set(s.x, s.h, s.y); m.rotation.y = -s.ang; }
    });
    if (b.warn) {
      const w = st.actors.find((s) => windupLevel(s) > 0);
      b.warn.visible = !!w;
      if (w) { const lv = windupLevel(w); b.warn.position.set(w.x, 0.1, w.y); b.warn.rotation.y = -w.ang; b.warn.material.color.set(THREAT); b.warn.material.opacity = 0.25 + 0.5 * lv; }
    }
  }
}
