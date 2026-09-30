import * as THREE from 'three';
import { ROLE_COLOR, THREAT, hurtLevel, isWall, isWallish, swingOffset, tileAt, windupLevel } from './scenes.js';

/* ================= B: 절제된 로우폴리 =================
   면이 보이는 평면 음영(광택 없음) · 흙빛 팔레트 · 4~5등신 · 얼굴은 단순하게.
   따뜻한 불빛 하나(횃불/모닥불)가 그림자를 드리우고, 나머지는 차고 옅은 주변광 + 약한 안개. 위협은 붉은 주황 하나로. */
const h2 = (x, y, s = 0) => { const v = Math.sin(x * 127.1 + y * 311.7 + s * 74.7) * 43758.5453; return v - Math.floor(v); };
const MATS = new Map();
/** 평면 음영 재질(색마다 하나) */
const M = (c) => { let m = MATS.get(c); if (!m) { m = new THREE.MeshLambertMaterial({ color: c, flatShading: true }); MATS.set(c, m); } return m; };
const glow = (c, opacity = 1, add = false) => new THREE.MeshBasicMaterial({ color: c, transparent: opacity < 1 || add, opacity, depthWrite: !(opacity < 1 || add), side: THREE.DoubleSide, blending: add ? THREE.AdditiveBlending : THREE.NormalBlending, fog: false });
const flat = (geo) => geo.rotateX(-Math.PI / 2);
const TH = new THREE.Color(THREAT).getHex();

/* ---------- 도형 ---------- */
function mesh(geo, c, x = 0, y = 0, z = 0, cast = true) { const m = new THREE.Mesh(geo, typeof c === 'number' ? M(c) : c); m.position.set(x, y, z); m.castShadow = cast; m.receiveShadow = true; return m; }
const box = (w, h, d, c, x, y, z) => mesh(new THREE.BoxGeometry(w, h, d), c, x, y, z);
const cyl = (r0, r1, h, c, x, y, z, seg = 6) => mesh(new THREE.CylinderGeometry(r0, r1, h, seg), c, x, y, z);
const ico = (r, c, x, y, z) => mesh(new THREE.IcosahedronGeometry(r, 0), c, x, y, z);
/** 흔들린 꼭짓점: 돌·바위가 손으로 깎은 듯 보이게 */
function rough(geo, amt, seed) {
  const p = geo.getAttribute('position');
  const key = (i) => `${p.getX(i).toFixed(3)},${p.getY(i).toFixed(3)},${p.getZ(i).toFixed(3)}`, off = {};
  for (let i = 0; i < p.count; i++) { const k = key(i); off[k] ||= [(h2(i, seed, 1) - 0.5) * amt, (h2(i, seed, 2) - 0.5) * amt, (h2(i, seed, 3) - 0.5) * amt]; }
  for (let i = 0; i < p.count; i++) { const o = off[key(i)]; p.setXYZ(i, p.getX(i) + o[0], p.getY(i) + o[1], p.getZ(i) + o[2]); }
  geo.computeVertexNormals(); return geo;
}

/* ---------- 사람(4~5등신) ---------- */
const PERSON = {
  hero: { cloth: 0x6e5438, trim: 0x4a3a2a, skin: 0xc79f7e, hair: 0x33261c, pants: 0x3e3a34, cloak: 0x5a3c2e },
  guard: { cloth: 0x646a74, trim: 0x8a909a, skin: 0xb8906e, hair: 0x2a2624, pants: 0x3a3c42, helm: 0x7c828c },
  sword: { cloth: 0x4e4450, trim: 0x6a5a58, skin: 0xc49a78, hair: 0x221c1c, pants: 0x36303a },
  archer: { cloth: 0x4c5a44, trim: 0x6a5a3e, skin: 0xb88c68, hair: 0x4a3a24, pants: 0x3a3a30, hood: 0x44503c },
  healer: { cloth: 0xa89e86, trim: 0x7a7060, skin: 0xd0aa88, hair: 0xc8c0aa, pants: 0x6a6252, hood: 0x9a907a },
  goblin: { cloth: 0x5a4632, trim: 0x3e3024, skin: 0x6e7650, hair: 0x2e3222, pants: 0x3e3226 },
  skeleton: { cloth: 0x3a3632, trim: 0x2a2826, skin: 0xc8c0a8, hair: 0xc8c0a8, pants: 0xb8b098 },
  boss: { cloth: 0x3c3a3e, trim: 0x5a5250, skin: 0x5e5048, hair: 0x2a2220, pants: 0x2e2c30 },
};
function person(s) {
  const a = s.a, k = a.kind, P = PERSON[k] || { cloth: a.cloth, trim: 0x3a2e24, skin: 0xc49a78, hair: a.hair, pants: 0x3e3830 };
  const thin = k === 'skeleton' ? 0.55 : 1, bulk = k === 'boss' ? 1.35 : k === 'guard' ? 1.12 : 1;
  const root = new THREE.Group(), body = new THREE.Group(); root.add(body);
  const legH = 0.6, hip = legH;
  const legs = [-1, 1].map((sx) => { const g = new THREE.Group(); g.position.set(sx * 0.09 * bulk, hip, 0); g.add(box(0.1 * thin * bulk, legH, 0.11 * thin * bulk, P.pants, 0, -legH / 2, 0), box(0.12 * bulk, 0.07, 0.18, 0x2a241e, 0, -legH + 0.035, 0.03)); body.add(g); return g; });
  const torso = new THREE.Group(); torso.position.y = hip; body.add(torso);
  const robe = k === 'healer';
  torso.add(cyl(0.2 * bulk * (k === 'skeleton' ? 0.7 : 1), 0.15 * bulk, 0.5, P.cloth, 0, 0.25, 0, 6));
  if (robe) torso.add(cyl(0.16, 0.26, 0.5, P.cloth, 0, -0.18, 0, 6));
  torso.add(box(0.34 * bulk, 0.06, 0.2 * bulk, P.trim, 0, 0.02, 0)); // 허리띠
  if (k === 'skeleton') for (let i = 0; i < 3; i++) torso.add(box(0.26, 0.025, 0.16, 0xc8c0a8, 0, 0.14 + i * 0.1, 0.02));
  const neck = 0.52, headR = k === 'boss' ? 0.16 : k === 'goblin' ? 0.16 : 0.14;
  const head = new THREE.Group(); head.position.y = neck + headR; torso.add(head);
  head.add(ico(headR, P.skin, 0, 0, 0));
  if (k === 'goblin') head.add(mesh(new THREE.ConeGeometry(0.05, 0.2, 4).rotateZ(Math.PI / 2), P.skin, -0.2, 0.02, -0.02), mesh(new THREE.ConeGeometry(0.05, 0.2, 4).rotateZ(-Math.PI / 2), P.skin, 0.2, 0.02, -0.02));
  else if (k === 'boss') head.add(mesh(new THREE.ConeGeometry(0.05, 0.28, 4).rotateZ(0.6), 0xcfc4a8, -0.15, 0.16, 0), mesh(new THREE.ConeGeometry(0.05, 0.28, 4).rotateZ(-0.6), 0xcfc4a8, 0.15, 0.16, 0), box(0.2, 0.04, 0.05, 0x1a1414, 0, 0.0, headR * 0.92));
  else if (k === 'skeleton') head.add(box(0.05, 0.04, 0.02, 0x1a1612, -0.05, 0.02, headR * 0.92), box(0.05, 0.04, 0.02, 0x1a1612, 0.05, 0.02, headR * 0.92));
  else if (k === 'guard') head.add(mesh(new THREE.CylinderGeometry(headR * 1.08, headR * 1.12, headR * 1.3, 7), P.helm, 0, 0.03, 0), box(headR * 1.4, 0.03, 0.03, 0x1a1a1e, 0, 0.0, headR * 1.08));
  else if (P.hood) head.add(mesh(new THREE.ConeGeometry(headR * 1.35, headR * 2.2, 6), P.hood, 0, headR * 0.35, -0.03));
  else head.add(mesh(new THREE.SphereGeometry(headR * 1.06, 6, 3, 0, Math.PI * 2, 0, Math.PI * 0.55), P.hair, 0, 0.012, -0.012)); // 머리칼
  const shoulder = 0.46;
  const arms = [-1, 1].map((sx) => { const g = new THREE.Group(); g.position.set(sx * 0.24 * bulk, shoulder, 0); g.add(box(0.085 * thin * bulk, 0.46, 0.09 * thin * bulk, sx > 0 ? P.cloth : P.cloth, 0, -0.21, 0), box(0.07, 0.07, 0.07, P.skin, 0, -0.45, 0)); torso.add(g); return g; });
  if (k === 'guard' || k === 'boss') for (const sx of [-1, 1]) torso.add(box(0.16 * bulk, 0.08, 0.2 * bulk, P.trim, sx * 0.24 * bulk, 0.5, 0));
  if (k === 'hero') { const c = box(0.34, 0.62, 0.03, P.cloak, 0, 0.08, -0.14); c.rotation.x = 0.12; torso.add(c); }
  // 무기(오른손 = +x 팔 끝). 팔 뿌리에서 앞(+z)으로 뻗는다
  const hand = new THREE.Group(); hand.position.y = -0.45; arms[1].add(hand);
  const off = new THREE.Group(); off.position.y = -0.45; arms[0].add(off);
  const W = (geo, c, x, y, z) => { hand.add(mesh(geo, c, x, y, z)); };
  if (k === 'hero') { W(new THREE.BoxGeometry(0.035, 0.035, 0.7), 0xc8ccd0, 0, 0, 0.38); W(new THREE.BoxGeometry(0.16, 0.03, 0.03), 0x6a5030, 0, 0, 0.04); off.add(cyl(0.025, 0.025, 0.36, 0x5a3e26, 0, 0.12, 0.04)); const fl = new THREE.Mesh(new THREE.ConeGeometry(0.07, 0.18, 5), glow(0xffb04a)); fl.position.set(0, 0.36, 0.04); off.add(fl); }
  else if (k === 'guard') { W(new THREE.CylinderGeometry(0.02, 0.02, 0.5, 5).rotateX(Math.PI / 2), 0x5a4432, 0, 0, 0.2); W(new THREE.DodecahedronGeometry(0.07, 0), 0x6a6e76, 0, 0, 0.45); const sh = box(0.05, 0.42, 0.34, 0x5a626e, -0.06, 0.18, 0.16); off.add(sh); }
  else if (k === 'sword') { W(new THREE.BoxGeometry(0.05, 0.03, 1.0), 0xb8bcc4, 0, 0, 0.55); W(new THREE.BoxGeometry(0.22, 0.04, 0.04), 0x5a4a3a, 0, 0, 0.06); }
  else if (k === 'archer' || k === 'skeleton') { const bow = mesh(new THREE.TorusGeometry(0.34, 0.018, 4, 10, Math.PI * 0.9).rotateZ(Math.PI * 0.55), k === 'skeleton' ? 0x4a4038 : 0x6a4a2c, 0, 0.1, 0.15); bow.rotation.y = Math.PI / 2; off.add(bow); }
  else if (k === 'healer') { W(new THREE.CylinderGeometry(0.02, 0.025, 1.1, 5), 0x5a4430, 0, 0.3, 0.06); const gem = new THREE.Mesh(new THREE.OctahedronGeometry(0.07, 0), glow(0xa6d880)); gem.position.set(0, 0.88, 0.06); hand.add(gem); }
  else if (k === 'goblin') { W(new THREE.BoxGeometry(0.05, 0.03, 0.46), 0x7a7a72, 0, 0, 0.26); }
  else if (k === 'boss') { W(new THREE.CylinderGeometry(0.03, 0.03, 0.9, 5).rotateX(Math.PI / 2), 0x3a2e24, 0, 0, 0.4); W(new THREE.BoxGeometry(0.26, 0.22, 0.3), 0x55504c, 0, 0, 0.82); }
  else if (a.job === 'craft') { W(new THREE.CylinderGeometry(0.018, 0.018, 0.32, 5).rotateX(Math.PI / 2), 0x5a4430, 0, 0, 0.14); W(new THREE.BoxGeometry(0.12, 0.07, 0.07), 0x6a6e76, 0, 0, 0.3); }
  else if (a.job === 'farm') { W(new THREE.CylinderGeometry(0.018, 0.018, 0.8, 5).rotateX(Math.PI / 2), 0x6a4a2c, 0, 0, 0.3); W(new THREE.BoxGeometry(0.14, 0.02, 0.1), 0x6a6e76, 0, -0.04, 0.68); }
  let crate = null;
  if (a.job === 'haul') { crate = box(0.34, 0.24, 0.26, 0x8a6a44, 0, 0.3, 0.26); torso.add(crate); }
  const scale = (k === 'boss' ? 1.45 : k === 'goblin' ? 0.74 : k === 'skeleton' ? 0.98 : 1) * 1.12;
  root.scale.setScalar(scale);
  root.traverse((o) => { if (o.isMesh && o.material.isMeshBasicMaterial) o.castShadow = false; });
  return { root, body, torso, head, legs, arms, hand, crate, k };
}

export class StyleB {
  constructor(host) {
    this.host = host;
    const r = this.renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'high-performance' });
    r.setPixelRatio(Math.min(devicePixelRatio || 1, 2)); r.shadowMap.enabled = true; r.shadowMap.type = THREE.PCFSoftShadowMap;
    r.toneMapping = THREE.ACESFilmicToneMapping; r.toneMappingExposure = 1.3;
    r.domElement.className = 'sl-canvas'; host.appendChild(r.domElement);
    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(30, 1, 0.5, 120);
    this.built = {}; this.sc = null; this.cur = null;
  }
  show(on) { this.renderer.domElement.style.display = on ? 'block' : 'none'; if (on) this.resize(); }
  resize() {
    const W = this.host.clientWidth || innerWidth, H = this.host.clientHeight || innerHeight;
    this.renderer.setSize(W, H); this.camera.aspect = W / H; this.fit(); this.camera.updateProjectionMatrix();
  }
  /** 장면 전체가 화면에 들어오게: 45도 남짓 기울인 고정 시점 */
  fit() {
    const sc = this.sc; if (!sc) return;
    const cam = this.camera, pitch = THREE.MathUtils.degToRad(60), cx = (sc.w - 1) / 2, cz = (sc.h - 1) / 2 + 0.2;
    const tv = Math.tan(THREE.MathUtils.degToRad(cam.fov / 2)), th = tv * cam.aspect;
    const dW = (sc.w / 2 - 0.1) / th, dH = ((sc.h * Math.sin(pitch)) / 2 + 0.9) / tv;
    const d = Math.max(dW, dH);
    cam.position.set(cx, Math.sin(pitch) * d, cz + Math.cos(pitch) * d); cam.lookAt(cx, 0.3, cz);
    cam.near = d * 0.5; cam.far = d * 2.2;
    if (this.cur) { this.cur.fog.near = d * 0.95; this.cur.fog.far = d * 1.9; }
  }
  setScene(sc) {
    this.sc = sc;
    const b = this.built[sc.id] ||= this.build(sc);
    this.scene = b.scene; this.cur = b; this.resize();
  }
  /* ---------- 짓기 ---------- */
  build(sc) {
    const dungeon = sc.id === 'dungeon', scene = new THREE.Scene(), W = sc.w, H = sc.h;
    const fogC = dungeon ? 0x1c1e26 : 0x262a2c;
    scene.background = new THREE.Color(fogC); scene.fog = new THREE.Fog(fogC, 20, 40);
    scene.add(new THREE.HemisphereLight(dungeon ? 0x8898b8 : 0xa0acc0, dungeon ? 0x3a342e : 0x4a4232, dungeon ? 1.4 : 1.45));
    const moon = new THREE.DirectionalLight(0x8ea4d0, dungeon ? 0.35 : 0.5); moon.position.set(-6, 12, 4); scene.add(moon);
    // 따뜻한 불빛: 위에서 비추는 스포트라이트(그림자) + 낮은 점광원(옆면)
    const warm = new THREE.SpotLight(0xffa860, dungeon ? 55 : 70, 16, 1.2, 0.85, 1.5);
    warm.castShadow = true; warm.shadow.mapSize.set(1024, 1024); warm.shadow.bias = -0.002; warm.shadow.normalBias = 0.03; warm.shadow.camera.near = 1; warm.shadow.camera.far = 14;
    const pt = new THREE.PointLight(0xffa050, dungeon ? 6 : 9, dungeon ? 6 : 8, 1.4);
    scene.add(warm, warm.target, pt);
    const root = new THREE.Group(); scene.add(root);
    let waterMesh = null, flame = null;
    // 바닥 칸: 칸마다 조금씩 다른 높이·기울기·색 → 돌판 느낌
    const tiles = [];
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) { const c = tileAt(sc, x, y); if (!isWall(c) && c !== '~') tiles.push([x, y, c]); }
    const floorGeo = rough(new THREE.BoxGeometry(0.96, 0.24, 0.96, 1, 1, 1), 0.035, 7).translate(0, -0.12, 0);
    const floor = new THREE.InstancedMesh(floorGeo, new THREE.MeshLambertMaterial({ flatShading: true }), tiles.length);
    floor.receiveShadow = true;
    const mtx = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler(), col = new THREE.Color(), v = new THREE.Vector3(), one = new THREE.Vector3(1, 1, 1);
    const TILE_C = { '.': dungeon ? 0x5a5650 : 0x6e604a, '"': 0x4f5a3c, g: 0x56603e, '=': 0x6a5038, D: 0x6a5038, f: 0x4a3a2a, s: 0x6a5c48, '#': 0x5a5650, W: 0x6a5038, S: 0x6a6660 };
    tiles.forEach(([x, y, c], i) => {
      const r = h2(x, y); e.set((h2(x, y, 2) - 0.5) * 0.03, (r - 0.5) * 0.1, (h2(x, y, 3) - 0.5) * 0.03); q.setFromEuler(e);
      mtx.compose(v.set(x, (h2(x, y, 4) - 0.5) * 0.03 + (c === 'f' ? -0.04 : 0), y), q, one); floor.setMatrixAt(i, mtx);
      floor.setColorAt(i, col.setHex(TILE_C[c] ?? 0x5a5650).multiplyScalar(0.9 + r * 0.16));
    });
    root.add(floor);
    // 정착지 바닥 칸(벽 밑 포함): 나무 널빤지 줄
    if (!dungeon) {
      const planks = [];
      for (const [x, y, c] of tiles) if (c === '=') for (let i = 0; i < 3; i++) planks.push([x, y, i]);
      const pg = new THREE.BoxGeometry(0.94, 0.03, 0.29), pm = new THREE.InstancedMesh(pg, new THREE.MeshLambertMaterial({ flatShading: true }), planks.length); pm.receiveShadow = true;
      planks.forEach(([x, y, i], n) => { mtx.compose(v.set(x, 0.015, y - 0.31 + i * 0.31), q.identity(), one); pm.setMatrixAt(n, mtx); pm.setColorAt(n, col.setHex([0x6e533a, 0x644a33, 0x735840][(i + x) % 3])); });
      root.add(pm);
    }
    // 벽
    if (dungeon) {
      const walls = []; for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) if (isWall(tileAt(sc, x, y))) walls.push([x, y]);
      const wg = rough(new THREE.BoxGeometry(1, 1.25, 1, 1, 2, 1), 0.06, 3).translate(0, 0.62, 0);
      const wm = new THREE.InstancedMesh(wg, new THREE.MeshLambertMaterial({ flatShading: true }), walls.length); wm.castShadow = wm.receiveShadow = true;
      walls.forEach(([x, y], i) => { e.set(0, (h2(x, y) - 0.5) * 0.08, 0); q.setFromEuler(e); mtx.compose(v.set(x, 0, y), q, v.clone().set(1, 0.9 + h2(x, y, 5) * 0.2, 1)); wm.setMatrixAt(i, mtx); wm.setColorAt(i, col.setHex(0x6c6760).multiplyScalar(0.85 + h2(x, y, 6) * 0.25)); });
      root.add(wm);
      // 물: 낮은 면, 매 프레임 잔물결
      let x0 = 99, x1 = -1, y0 = 99, y1 = -1;
      for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) if (tileAt(sc, x, y) === '~') { x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y); }
      if (x1 >= 0) {
        const bed = box(x1 - x0 + 1, 0.1, y1 - y0 + 1, 0x22282a, (x0 + x1) / 2, -0.3, (y0 + y1) / 2); bed.castShadow = false; root.add(bed);
        const geo = flat(new THREE.PlaneGeometry(x1 - x0 + 1, y1 - y0 + 1, (x1 - x0 + 1) * 3, (y1 - y0 + 1) * 3)).toNonIndexed();
        const water = new THREE.Mesh(geo, new THREE.MeshLambertMaterial({ color: 0x3f6576, flatShading: true, transparent: true, opacity: 0.9 }));
        water.position.set((x0 + x1) / 2, -0.1, (y0 + y1) / 2); water.receiveShadow = true; root.add(water); waterMesh = water;
        water.userData.base = Float32Array.from(geo.getAttribute('position').array);
      }
      // 풀: 가는 잎 무더기
      const tufts = []; for (const [x, y, c] of tiles) if (c === '"') for (let i = 0; i < 3; i++) tufts.push([x + (h2(x, y, i) - 0.5) * 0.8, y + (h2(y, x, i) - 0.5) * 0.8, h2(x, i, y)]);
      const tg = new THREE.ConeGeometry(0.06, 0.26, 3).translate(0, 0.13, 0), tm = new THREE.InstancedMesh(tg, new THREE.MeshLambertMaterial({ flatShading: true }), tufts.length);
      tufts.forEach(([x, y, r], i) => { e.set((r - 0.5) * 0.4, r * 6, 0); q.setFromEuler(e); mtx.compose(v.set(x, 0, y), q, one); tm.setMatrixAt(i, mtx); tm.setColorAt(i, col.setHex(r > 0.5 ? 0x5c6a44 : 0x4e5c3a)); });
      root.add(tm);
    } else {
      this.settleWalls(sc, root);
      // 밭 작물: 칸마다 두 줄 × 세 포기
      const crops = []; for (const [x, y, c] of tiles) if (c === 'f') for (let r = 0; r < 2; r++) for (let k = 0; k < 3; k++) crops.push([x - 0.3 + k * 0.3, y - 0.22 + r * 0.44, h2(x * 3 + k, y * 5 + r)]);
      const cg = new THREE.ConeGeometry(0.1, 0.3, 4).translate(0, 0.15, 0), cm = new THREE.InstancedMesh(cg, new THREE.MeshLambertMaterial({ flatShading: true }), crops.length); cm.castShadow = true;
      crops.forEach(([x, y, r], i) => { e.set(0, r * 3, (r - 0.5) * 0.3); q.setFromEuler(e); const k = 0.8 + r * 0.5; mtx.compose(v.set(x, -0.04, y), q, new THREE.Vector3(k, k, k)); cm.setMatrixAt(i, mtx); cm.setColorAt(i, col.setHex(r > 0.5 ? 0x6a7a44 : 0x5a6c3c)); });
      root.add(cm);
    }
    for (const p of sc.props) root.add(this.prop(p));
    if (sc.hearth) { const hg = this.hearth(sc.hearth); flame = hg.userData.flame; root.add(hg); }
    // 가장자리: 장면 밖은 어두운 흙
    const edge = mesh(flat(new THREE.PlaneGeometry(W + 30, H + 30)), dungeon ? 0x121216 : 0x1e2018, (W - 1) / 2, -0.26, (H - 1) / 2, false); root.add(edge);
    // 인물
    const actors = sc.actors.map((a) => {
      const P = person({ a }); root.add(P.root);
      const shadow = new THREE.Mesh(flat(new THREE.CircleGeometry(a.kind === 'boss' ? 0.55 : 0.3, 12)), glow(0x000000, 0.35)); shadow.position.y = 0.012; shadow.renderOrder = 1; root.add(shadow);
      let ring = null;
      if (a.side === 'ally') { ring = new THREE.Mesh(flat(new THREE.RingGeometry(0.36, 0.41, 28)), glow(new THREE.Color(ROLE_COLOR[a.role]).getHex(), 0.95)); ring.position.y = 0.02; ring.renderOrder = 2; root.add(ring); }
      else if (a.side === 'foe') { const r0 = a.kind === 'boss' ? 0.7 : 0.34; ring = new THREE.Mesh(flat(new THREE.RingGeometry(r0, r0 + 0.035, 24)), glow(0x7a2a24, 0.9)); ring.position.y = 0.02; ring.renderOrder = 2; root.add(ring); }
      // 한 방 직전: 붉은 주황으로 물들 재질(인물 하나만)
      const tint = [];
      if (a.act === 'windup' || a.act === 'hurt' || a.kind === 'boss') P.root.traverse((o) => { if (o.isMesh && o.material.isMeshLambertMaterial) { o.material = o.material.clone(); tint.push(o.material); } });
      return { a, P, shadow, ring, tint };
    });
    // 예고
    const tele = sc.tele.map((T) => {
      const g = new THREE.Group(); root.add(g);
      const th0 = -T.ang - T.half, len = T.half * 2, fan = T.type === 'fan';
      const base = new THREE.Mesh(flat(fan ? new THREE.CircleGeometry(T.r, 32, th0, len) : new THREE.CircleGeometry(T.r, 40)), glow(TH, 0.14));
      const fill = new THREE.Mesh(flat(fan ? new THREE.CircleGeometry(T.r, 32, th0, len) : new THREE.CircleGeometry(T.r, 40)), glow(TH, 0.4));
      const edge = new THREE.Mesh(flat(fan ? sectorOutline(T.r, th0, len, 0.07) : new THREE.RingGeometry(T.r - 0.07, T.r, 40)), glow(TH, 1));
      base.position.y = 0.03; fill.position.y = 0.035; edge.position.y = 0.04; base.renderOrder = fill.renderOrder = 3; edge.renderOrder = 4;
      g.add(base, fill, edge); return { g, base, fill, edge };
    });
    // 치켜든 적 앞 부채꼴 + 머리 위 표식
    const warn = new THREE.Group(); root.add(warn);
    const wf = new THREE.Mesh(flat(new THREE.CircleGeometry(1.05, 16, -0.55, 1.1)), glow(TH, 0.3)), we = new THREE.Mesh(flat(sectorOutline(1.05, -0.55, 1.1, 0.05)), glow(TH, 1));
    wf.position.y = 0.03; we.position.y = 0.04; wf.renderOrder = 3; we.renderOrder = 4; warn.add(wf, we);
    const mark = new THREE.Mesh(new THREE.ConeGeometry(0.09, 0.2, 3).rotateX(Math.PI), glow(TH, 1)); root.add(mark);
    // 휘두름 호
    const arc = new THREE.Mesh(flat(new THREE.RingGeometry(0.85, 1.35, 16, 1, -0.5, 1.0)), glow(0xffe6c0, 0.8, true)); arc.renderOrder = 5; root.add(arc);
    // 화살: 몸통 + 꼬리
    const shots = sc.shots.map((S) => {
      const g = new THREE.Group(); const c = S.foe ? TH : 0xe8dcc0;
      const b = new THREE.Mesh(new THREE.BoxGeometry(0.46, 0.035, 0.035), glow(c)); const tr = new THREE.Mesh(new THREE.BoxGeometry(0.9, 0.02, 0.02).translate(-0.6, 0, 0), glow(c, 0.35, true));
      g.add(b, tr); root.add(g); return g;
    });
    return { scene, fog: scene.fog, warm, pt, actors, tele, warn, wf, mark, arc, shots, water: waterMesh, flame, dungeon };
  }
  settleWalls(sc, root) {
    const W = sc.w, H = sc.h, parts = [];
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
      const c = tileAt(sc, x, y); if (!isWallish(c)) continue;
      const col = c === 'S' ? 0x7a756c : 0x6a4e34, hgt = c === 'S' ? 1.15 : 1.05;
      if (c === 'D') { // 문틀 + 반쯤 열린 문
        const hz = isWallish(tileAt(sc, x - 1, y)) || isWallish(tileAt(sc, x + 1, y));
        const g = new THREE.Group(); g.position.set(x, 0, y); if (!hz) g.rotation.y = Math.PI / 2;
        g.add(box(0.12, 1.05, 0.26, 0x4a3624, -0.44, 0.52, 0), box(0.12, 1.05, 0.26, 0x4a3624, 0.44, 0.52, 0), box(1.0, 0.12, 0.28, 0x3e2e20, 0, 1.0, 0));
        const d = box(0.7, 0.9, 0.06, 0x7a5a3a, 0.35, 0.46, 0); const piv = new THREE.Group(); piv.position.x = -0.38; piv.rotation.y = -1.0; piv.add(d); g.add(piv);
        root.add(g); continue;
      }
      parts.push(box(0.3, hgt, 0.3, col, x, hgt / 2, y));
      for (const [dx, dy] of [[1, 0], [0, 1]]) { const n = tileAt(sc, x + dx, y + dy); if (!isWallish(n)) continue; parts.push(box(dx ? 0.72 : 0.24, hgt * 0.97, dy ? 0.72 : 0.24, col, x + dx * 0.5, hgt * 0.485, y + dy * 0.5)); }
    }
    for (const p of parts) root.add(p);
  }
  prop(p) {
    const g = new THREE.Group(), w = p.w || 1, h = p.h || 1;
    g.position.set(p.x + (w - 1) / 2, 0, p.y + (h - 1) / 2); g.rotation.y = (p.rot || 0) * Math.PI / 2;
    const WOOD = 0x6a4c32, WOOD_D = 0x4a3624;
    switch (p.k) {
      case 'bed': g.add(box(0.8, 0.22, 1.84, WOOD, 0, 0.14, 0), box(0.82, 0.5, 0.08, WOOD_D, 0, 0.3, -0.9), box(0.72, 0.1, 0.36, 0xb8b0a0, 0, 0.3, -0.64), box(0.74, 0.12, 1.2, 0x6a4a44, 0, 0.3, 0.26)); break;
      case 'table': g.add(box(1.8, 0.08, 0.8, WOOD, 0, 0.68, 0)); for (const [a, b] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) g.add(box(0.08, 0.64, 0.08, WOOD_D, a * 0.8, 0.32, b * 0.32)); g.add(cyl(0.12, 0.1, 0.06, 0x9a9282, 0.4, 0.75, 0), cyl(0.05, 0.05, 0.14, 0x7a6a50, -0.3, 0.79, 0.1)); break;
      case 'chair': g.add(box(0.44, 0.06, 0.44, WOOD, 0, 0.42, 0), box(0.44, 0.5, 0.06, WOOD_D, 0, 0.7, -0.2)); for (const [a, b] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) g.add(box(0.05, 0.42, 0.05, WOOD_D, a * 0.18, 0.21, b * 0.18)); break;
      case 'shelf': g.add(box(0.86, 1.3, 0.42, WOOD_D, 0, 0.65, -0.22)); for (const [y, c] of [[0.3, 0x7a5a3e], [0.72, 0x5a6a70], [1.1, 0x8a7a5a]]) g.add(box(0.7, 0.24, 0.3, c, 0, y, -0.12)); break;
      case 'bench': g.add(box(1.8, 0.12, 0.78, WOOD, 0, 0.78, 0)); for (const [a, b] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) g.add(box(0.1, 0.74, 0.1, WOOD_D, a * 0.8, 0.37, b * 0.3)); g.add(box(0.2, 0.18, 0.24, 0x5a5e66, 0.6, 0.93, 0), box(0.5, 0.06, 0.1, 0x7a7e86, -0.2, 0.87, 0.1), box(0.3, 0.14, 0.3, 0x8a7a5a, -0.55, 0.91, -0.1)); break;
      case 'lamp': { g.add(cyl(0.16, 0.2, 0.1, 0x5a5650, 0, 0.05, 0), cyl(0.03, 0.03, 1.1, 0x2e2c2c, 0, 0.6, 0)); const l = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.2, 0.16), glow(0xffc070)); l.position.y = 1.1; g.add(l); break; }
      case 'tree': {
        g.add(cyl(0.1, 0.16, 1.1, 0x4a3a2c, 0, 0.55, 0));
        const c1 = mesh(rough(new THREE.IcosahedronGeometry(0.7, 0), 0.12, p.x + p.y), 0x46523a, 0, 1.45, 0); const c2 = mesh(rough(new THREE.IcosahedronGeometry(0.5, 0), 0.1, p.x * 3), 0x505c40, 0.18, 1.95, 0.05);
        g.add(c1, c2); break;
      }
      case 'rock': g.add(mesh(rough(new THREE.DodecahedronGeometry(0.42, 0), 0.12, p.x * 7 + p.y).scale(1, 0.7, 0.9), 0x77736a, 0, 0.22, 0), mesh(new THREE.DodecahedronGeometry(0.18, 0), 0x6a665e, 0.3, 0.1, 0.25)); break;
      case 'logs': for (let i = 0; i < 3; i++) { const l = cyl(0.11, 0.11, 0.8, i % 2 ? 0x5a4230 : 0x664a34, 0, 0.11 + (i === 2 ? 0.18 : 0), -0.12 + (i === 2 ? 0 : i * 0.24)); l.rotation.z = Math.PI / 2; g.add(l); } break;
      case 'crate': g.add(box(0.56, 0.44, 0.56, 0x7a5c3c, 0, 0.22, 0), box(0.4, 0.3, 0.4, 0x6e5236, 0.04, 0.59, 0)); break;
      case 'stones': for (let i = 0; i < 4; i++) g.add(mesh(new THREE.DodecahedronGeometry(0.15, 0), i % 2 ? 0x6e6a62 : 0x7e7a70, (h2(i, p.x) - 0.5) * 0.5, 0.12 + (i === 3 ? 0.14 : 0), (h2(p.y, i) - 0.5) * 0.5)); break;
      case 'sack': g.add(mesh(new THREE.IcosahedronGeometry(0.26, 0).scale(1, 0.85, 0.9), 0x9a8a68, 0, 0.22, 0)); break;
    }
    return g;
  }
  hearth(hp) {
    const g = new THREE.Group(); g.position.set(hp.x, 0, hp.y);
    for (let k = 0; k < 8; k++) { const a = k / 8 * Math.PI * 2; g.add(mesh(new THREE.DodecahedronGeometry(0.12, 0), k % 2 ? 0x5e5a54 : 0x6e6a62, Math.cos(a) * 0.38, 0.08, Math.sin(a) * 0.38)); }
    for (const r of [0.5, -0.7]) { const l = cyl(0.06, 0.06, 0.55, 0x3e2e22, 0, 0.1, 0); l.rotation.set(0, r, Math.PI / 2); g.add(l); }
    const fl = g.userData.flame = new THREE.Group();
    for (const [r, h, c, x, z] of [[0.2, 0.55, 0xd05a1e, 0, 0], [0.12, 0.4, 0xf09030, 0.08, 0.04], [0.1, 0.34, 0xf09030, -0.08, -0.05], [0.08, 0.3, 0xffd890, 0, 0]]) { const m = new THREE.Mesh(new THREE.ConeGeometry(r, h, 5).translate(0, h / 2, 0), glow(c)); m.position.set(x, 0.1, z); fl.add(m); }
    g.add(fl); return g;
  }
  /* ---------- 매 프레임 ---------- */
  render(st) {
    const b = this.cur; if (!b) return;
    const t = st.t;
    // 불빛
    if (st.light) {
      const L = st.light, f = st.flicker;
      b.warm.position.set(L.x + 0.4, b.dungeon ? 3.4 : 4.2, L.y + 0.6); b.warm.target.position.set(L.x, 0, L.y); b.warm.intensity = (b.dungeon ? 55 : 70) * f;
      b.pt.position.set(L.x + (b.dungeon ? -0.3 : 0), b.dungeon ? 1.2 : 0.8, L.y + (b.dungeon ? -0.2 : 0)); b.pt.intensity = (b.dungeon ? 6 : 9) * f;
    }
    if (b.flame) { const s = st.flicker; b.flame.scale.set(s * (1 + Math.sin(t * 17) * 0.05), s * (1 + Math.sin(t * 9.1) * 0.12), s); b.flame.rotation.y = t * 1.3; }
    if (b.water) {
      const geo = b.water.geometry, p = geo.getAttribute('position'), base = b.water.userData.base;
      for (let i = 0; i < p.count; i++) { const x = base[i * 3], z = base[i * 3 + 2]; p.setY(i, Math.sin(x * 4.1 + t * 1.6) * 0.025 + Math.cos(z * 3.7 - t * 1.2 + x) * 0.025); }
      p.needsUpdate = true; geo.computeVertexNormals();
    }
    let warnS = null;
    for (const s of st.actors) {
      const A = b.actors.find((q) => q.a === s.a); if (!A) continue;
      const P = A.P, hurt = hurtLevel(s), wl = windupLevel(s), sw = swingOffset(s);
      const back = hurt * 0.14, shiver = s.a.kind === 'boss' && s.k > 0.5 && !s.burst ? Math.sin(t * 40) * 0.04 * s.k : 0;
      const bob = s.walk ? Math.abs(Math.sin(s.walk)) * 0.05 : s.bob * 0.015;
      P.root.position.set(s.x - Math.cos(s.ang) * back + shiver, bob, s.y - Math.sin(s.ang) * back);
      P.root.rotation.y = Math.atan2(Math.cos(s.ang), Math.sin(s.ang));
      // 걷기: 팔다리 흔들기
      const lg = s.walk ? Math.sin(s.walk) * 0.6 : 0;
      P.legs[0].rotation.x = lg; P.legs[1].rotation.x = -lg;
      P.arms[0].rotation.x = -lg * 0.6;
      // 오른팔: 앞으로 든 자세 + 휘두름
      const ready = { swing: 1.2, fight: 1.2, windup: 1.2, craft: 0.9, farm: 0.7, block: 1.0, shoot: 0, cast: 0.2, hurt: 0.8, charge: 1.0 }[s.act] ?? (s.walk ? 0 : 0.2);
      P.arms[1].rotation.set(-ready - (s.act === 'windup' || s.act === 'craft' || s.act === 'charge' ? sw * 1.1 : 0), s.act === 'swing' || s.act === 'fight' ? -sw * 0.9 : 0, 0);
      if (s.a.kind === 'boss') P.arms[1].rotation.x = -1.0 - s.k * 1.6 * (s.burst ? 0 : 1) + (s.burst ? 1.2 * (1 - s.burst) : 0);
      if (!s.walk) P.arms[1].rotation.x += s.act === 'shoot' ? -1.3 : 0;
      if (s.act === 'shoot') P.arms[0].rotation.x = -1.4;
      if (s.act === 'block') P.arms[0].rotation.x = -1.2;
      if (s.act === 'cast') P.arms[0].rotation.x = -0.4 - Math.sin(s.k * Math.PI) * 0.8;
      if (s.carry) { P.arms[0].rotation.x = P.arms[1].rotation.x = -1.2; }
      P.torso.rotation.x = s.a.kind === 'goblin' ? 0.25 : s.a.job === 'farm' && !s.walk ? 0.35 : wl * -0.2 + (s.a.kind === 'boss' ? -0.15 * s.k : 0);
      if (P.crate) P.crate.visible = !!s.carry;
      A.shadow.position.set(P.root.position.x, 0.012, P.root.position.z);
      if (A.ring) A.ring.position.set(s.x, 0.02, s.y);
      const tintK = wl || (s.a.kind === 'boss' && !s.burst ? s.k * 0.22 : 0);
      for (const m of A.tint) m.emissive.setRGB(0.55 * tintK, 0.14 * tintK, 0.02 * tintK);
      if (hurt) for (const m of A.tint) m.emissive.setRGB(hurt, hurt, hurt);
      if (wl) warnS = s;
    }
    st.tele.forEach((T, n) => {
      const m = b.tele[n]; if (!m) return;
      m.g.position.set(T.x, 0, T.y);
      m.fill.scale.setScalar(Math.max(0.02, T.burst ? 1 : T.fill)); m.fill.material.opacity = T.burst ? 0.75 * (1 - T.burst) : 0.4;
      m.edge.material.opacity = 0.75 + 0.25 * Math.sin(t * (6 + T.fill * 14));
    });
    b.warn.visible = b.mark.visible = !!warnS;
    if (warnS) { const lv = windupLevel(warnS); b.warn.position.set(warnS.x, 0, warnS.y); b.warn.rotation.y = -warnS.ang; b.wf.material.opacity = 0.12 + 0.3 * lv; b.mark.position.set(warnS.x, 1.35 + Math.sin(t * 8) * 0.03, warnS.y); b.mark.scale.setScalar(0.8 + lv * 0.4); }
    const S = st.swing; b.arc.visible = !!S;
    if (S) { b.arc.position.set(S.x, 0.62, S.y); b.arc.rotation.y = -(S.ang - 1.0 + 2.0 * S.k); b.arc.material.opacity = 0.85 * (1 - S.k * 0.7); }
    b.shots.forEach((g, n) => { const s = st.shots.find((q) => q.foe === this.sc.shots[n].foe); g.visible = !!s; if (s) { g.position.set(s.x, s.h, s.y); g.rotation.y = -s.ang; } });
    this.renderer.render(this.scene, this.camera);
  }
}

/** 부채꼴 테두리(바깥 호 + 두 반지름) */
function sectorOutline(r, th0, len, w) {
  const sh = new THREE.Shape(), seg = 24;
  sh.moveTo(0, 0);
  for (let i = 0; i <= seg; i++) { const a = th0 + len * i / seg; sh.lineTo(Math.cos(a) * r, Math.sin(a) * r); }
  sh.lineTo(0, 0);
  const hole = new THREE.Path(), ri = r - w, mid = th0 + len / 2, off = w / Math.sin(len / 2), cx = Math.cos(mid) * off, cy = Math.sin(mid) * off;
  hole.moveTo(cx, cy);
  for (let i = 0; i <= seg; i++) { const a = th0 + len * i / seg; hole.lineTo(Math.cos(a) * ri, Math.sin(a) * ri); }
  hole.lineTo(cx, cy);
  sh.holes.push(hole);
  return new THREE.ShapeGeometry(sh);
}
