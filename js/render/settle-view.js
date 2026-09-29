import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { FLOOR_BY_ID, FURN, TR, WALLS, ZONE_BY_ID, ZONE_TYPES } from '../data/build.js';
import * as K from './diorama.js';
import { FURN_H, furnAnim, furnExtras, furnParts, glowSprite } from './furniture.js';

/* ================= 정착지 3D (docs/설계_정착지_건설.md §3 · §4 · §8) =================
   40×40 격자: 칸 (x, y) = 월드 (x, 0, z=y), 칸 크기 1. 땅·바닥·벽·나무·바위는 InstancedMesh(편집마다 다시 채운다), 가구는 하나씩(누를 수 있게).
   빛 반경 밖은 모든 재질에 끼운 셰이더 조각이 어둡게 덮고, 경계가 일렁인다. */
const _m = new THREE.Matrix4(), _q = new THREE.Quaternion(), _p = new THREE.Vector3(), _sc = new THREE.Vector3(), _up = new THREE.Vector3(0, 1, 0), _col = new THREE.Color();
const WHITE = new THREE.Color(1, 1, 1), NORAY = () => {};
const merged = (parts) => mergeGeometries(parts.map(K.partGeo));
/** 가구 크기(회전이 홀수면 가로·세로가 바뀐다) — core/rooms.js furnSize와 같다 */
const footprint = (k, rot = 0) => { const F = FURN[k]; return rot % 2 ? [F.h, F.w] : [F.w, F.h]; };
/** 땅 색: 흙 풀 폐허 물(바닥) 나무 밑 바위 밑 광맥 밑 */
const GROUND = [0xdcc28e, 0x7cc45a, 0x8a867e, 0x1d4a80, 0x68ac4a, 0xb4a88e, 0xa89c88];
const WK = { [WALLS.wood.id]: { c: 0xb07a44, h: 0.95, t: 0.21 }, [WALLS.stone.id]: { c: 0xa6a298, h: 1.05, t: 0.25 } }, DOOR = WALLS.door.id;
const C_BP = new THREE.Color(0x5ee6ff), C_BAD = new THREE.Color(0xff4a4a), C_OK = new THREE.Color(0x6aff8a);
const FIRE_K = [0.7, 1, 1.35], DIRT_F = new THREE.Color(0.62, 0.47, 0.3);

/* ---------- 어둠: 빛 반경 밖을 어둡게 (모든 재질에 끼운다) ---------- */
const NOISE = 'float svN(float a, float t){ return sin(a * 7.0 + t * 0.8) * 0.5 + sin(a * 13.0 - t * 1.3) * 0.3 + sin(a * 3.0 + t * 0.5) * 0.4; }';
function darkify(m, U) {
  const prev = m.onBeforeCompile, key = m.customProgramCacheKey.bind(m);
  m.onBeforeCompile = (sh, r) => {
    prev.call(m, sh, r);
    Object.assign(sh.uniforms, { svC: U.c, svR: U.r, svDim: U.dim, svT: U.t, svDark: U.dark });
    sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nvarying vec2 svP;').replace('#include <project_vertex>', `#include <project_vertex>
{ vec4 w4 = vec4(transformed, 1.0);
#ifdef USE_INSTANCING
  w4 = instanceMatrix * w4;
#endif
  svP = (modelMatrix * w4).xz; }`);
    sh.fragmentShader = sh.fragmentShader.replace('#include <common>', `#include <common>
varying vec2 svP; uniform vec2 svC; uniform float svR; uniform float svDim; uniform float svT; uniform vec3 svDark;
${NOISE}`).replace('#include <dithering_fragment>', `#include <dithering_fragment>
{ vec2 q = svP - svC; float d = length(q) + svN(atan(q.y, q.x + 1e-4), svT) * 0.3;
  gl_FragColor.rgb = mix(gl_FragColor.rgb * svDim, svDark, smoothstep(svR + 0.2, svR + 2.6, d)); }`);
  };
  m.customProgramCacheKey = () => 'sv-' + key();
  return m;
}
/** 청사진 · 미리보기: 반투명 상자 + 밝은 모서리 + 훑는 줄 */
function ghostMat(U) {
  return new THREE.ShaderMaterial({
    uniforms: { uT: U.t }, transparent: true, depthWrite: false, side: THREE.DoubleSide,
    vertexShader: `varying vec3 vL; varying vec3 vS; varying vec3 vC; varying float vY;
void main(){ vL = position; vC = vec3(1.0);
#ifdef USE_INSTANCING_COLOR
  vC = instanceColor;
#endif
  vS = vec3(length(instanceMatrix[0].xyz), length(instanceMatrix[1].xyz), length(instanceMatrix[2].xyz));
  vec4 w = modelMatrix * instanceMatrix * vec4(position, 1.0); vY = w.y; gl_Position = projectionMatrix * viewMatrix * w; }`,
    fragmentShader: `uniform float uT; varying vec3 vL; varying vec3 vS; varying vec3 vC; varying float vY;
void main(){ vec3 q = (0.5 - abs(vL)) * vS; float mid = q.x + q.y + q.z - min(q.x, min(q.y, q.z)) - max(q.x, max(q.y, q.z));
  float e = smoothstep(0.05, 0.015, mid), scan = step(0.65, fract(vY * 6.0 - uT * 1.4)) * 0.12;
  gl_FragColor = vec4(vC * (1.0 + e * 0.6), (0.26 + scan + e * 0.6) * (0.88 + 0.12 * sin(uT * 4.0))); }`,
  });
}
/** 바닥 사각 윤곽: 추천 자리(반짝임) · 시작점/선택 */
function rectMat(U, w, h, color, spark) {
  return new THREE.ShaderMaterial({
    uniforms: { uT: U.t, uS: { value: new THREE.Vector2(w + 0.4, h + 0.4) }, uC: { value: new THREE.Color(color) }, uK: { value: spark } }, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
    vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }',
    fragmentShader: `uniform float uT; uniform vec2 uS; uniform vec3 uC; uniform float uK; varying vec2 vUv;
float h21(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void main(){ vec2 p = (vUv - 0.5) * uS, q = abs(p) - (uS * 0.5 - 0.2) + 0.12; float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - 0.12;
  float pulse = 0.7 + 0.3 * sin(uT * 4.0 - uK), a = (smoothstep(0.06, 0.0, abs(d)) + exp(-abs(d) * 9.0) * 0.5 + step(d, 0.0) * 0.1) * pulse;
  vec2 g = floor(p * 4.0), f = fract(p * 4.0) - 0.5; float hh = h21(g + uK);
  float tw = pow(max(0.0, sin(uT * 2.5 + hh * 40.0)), 14.0) * smoothstep(0.12, 0.02, length(f)) * smoothstep(0.4, 0.0, abs(d)) * step(0.3, hh) * step(0.5, uK);
  gl_FragColor = vec4(uC * a * 0.65 + vec3(1.0, 0.95, 0.8) * tw * 1.4, 1.0); }`,
  });
}
/** 빛 경계: 땅 위에 일렁이는 띠 */
function ringMat(U) {
  return new THREE.ShaderMaterial({
    uniforms: { svC: U.c, svR: U.r, svT: U.t }, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
    vertexShader: 'varying vec2 vP; void main(){ vec4 w = modelMatrix * vec4(position, 1.0); vP = w.xz; gl_Position = projectionMatrix * viewMatrix * w; }',
    fragmentShader: `uniform vec2 svC; uniform float svR; uniform float svT; varying vec2 vP; ${NOISE}
void main(){ vec2 q = vP - svC; float a = atan(q.y, q.x + 1e-4), n = svN(a, svT), d = length(q) + n * 0.3 - svR;
  float band = exp(-d * d * 5.0) * (0.55 + 0.45 * sin(a * 9.0 - svT * 1.7 + n * 3.0)), haze = exp(-abs(d - 0.9) * 2.0) * (0.6 + 0.4 * sin(svT * 1.3 + a * 5.0));
  gl_FragColor = vec4(vec3(1.0, 0.78, 0.5) * band * 0.2 + vec3(0.35, 0.25, 0.8) * haze * 0.07, 1.0); }`,
  });
}

/* ---------- 인스턴스 묶음: begin → put… → end ---------- */
class Inst {
  constructor(par, geo, mat, o = {}) { Object.assign(this, { par, geo, mat, o, cap: 0, a: [], mesh: null, ol: null, vis: true }); }
  begin() { this.a.length = 0; return this; }
  put(x, y, z, ry = 0, sx = 1, sy = 1, sz = 1, c = WHITE) { this.a.push(x, y, z, ry, sx, sy, sz, c.r, c.g, c.b); }
  end() {
    const n = this.a.length / 10; if (n > this.cap) this.alloc(Math.max(n, this.cap * 2, 8));
    if (!this.mesh) return;
    const m = this.mesh, M = m.instanceMatrix.array, Cc = m.instanceColor.array, a = this.a;
    for (let i = 0; i < n; i++) { const j = i * 10; _q.setFromAxisAngle(_up, a[j + 3]); _m.compose(_p.set(a[j], a[j + 1], a[j + 2]), _q, _sc.set(a[j + 4], a[j + 5], a[j + 6])).toArray(M, i * 16); Cc[i * 3] = a[j + 7]; Cc[i * 3 + 1] = a[j + 8]; Cc[i * 3 + 2] = a[j + 9]; }
    m.count = n; m.instanceMatrix.needsUpdate = m.instanceColor.needsUpdate = true; if (this.ol) this.ol.count = n; this.show(this.vis);
  }
  alloc(cap) {
    this.free(); this.cap = cap;
    const m = this.mesh = new THREE.InstancedMesh(this.geo, this.mat, cap);
    m.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(cap * 3).fill(1), 3); // 미리 만들어 셰이더가 바뀌지 않게
    Object.assign(m, { frustumCulled: false, castShadow: !!this.o.cast, receiveShadow: !!this.o.recv, raycast: NORAY, renderOrder: this.o.order || 0 }); this.par.add(m);
    if (this.o.ol) { const l = this.ol = new THREE.InstancedMesh(this.olGeo ||= K.outlineGeo(this.geo), K.OUTLINE, cap); l.instanceMatrix = m.instanceMatrix; Object.assign(l, { frustumCulled: false, raycast: NORAY }); this.par.add(l); }
  }
  free() { for (const m of [this.mesh, this.ol]) if (m) { this.par.remove(m); m.dispose(); } this.mesh = this.ol = null; }
  show(v) { this.vis = v; const on = v && !!this.mesh && this.mesh.count > 0; if (this.mesh) this.mesh.visible = on; if (this.ol) this.ol.visible = on; }
  dispose() { this.free(); this.geo.dispose(); this.olGeo?.dispose(); }
}

/* ================= 정착지 보기 ================= */
export class SettleView {
  constructor(scene) {
    this.scene = scene; this.group = new THREE.Group(); scene.add(this.group);
    this.S = null; this.R = 6; this.mode = 'all'; this.fireK = 1; this._bp = []; this._bad = new Set(); this.tpl = {}; this.furn = [];
    const U = this.U = { c: { value: new THREE.Vector2(20, 20) }, r: { value: Math.sqrt(42) }, dim: { value: 1 }, t: { value: 0 }, dark: { value: new THREE.Color(0x07080f) } };
    const tile = darkify(K.toon({ vertexColors: true, gloss: 0.08 }), U), solid = this.mSolid = darkify(K.toon({ vertexColors: true, gloss: 0.4 }), U);
    const water = darkify(K.liquidMaterial('water'), U); water.color.set(0x2a6ab0);
    this.mZone = new THREE.MeshBasicMaterial({ transparent: true, opacity: 0.34, depthWrite: false });
    this.mGhost = ghostMat(U); this.mats = [tile, solid, water, this.mZone, this.mGhost];
    const g = this.group, flat = () => new THREE.PlaneGeometry(1, 1).rotateX(-Math.PI / 2), box = (c) => ({ s: 'box', ...c });
    // 어둠 바다 · 빛 경계
    this.void = new THREE.Mesh(new THREE.PlaneGeometry(400, 400).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ color: 0x07080f })); this.void.position.y = -0.45; this.void.raycast = NORAY; g.add(this.void);
    this.ring = new THREE.Mesh(flat(), ringMat(U)); this.ring.position.y = 0.09; this.ring.renderOrder = 2; this.ring.raycast = NORAY; g.add(this.ring);
    const I = this.I = {
      ground: new Inst(g, K.tileGeo(1, 1, 1, 1, 0.72), tile, { recv: true }),
      water: new Inst(g, flat(), water, {}),
      ruin: new Inst(g, merged([box({ p: [-0.22, 0.03, -0.2], k: [0.44, 0.06, 0.44], r: [0, 0.1, 0], c: 0xb0aca2 }), box({ p: [0.24, 0.025, -0.18], k: [0.4, 0.05, 0.4], c: 0xa29e94 }), box({ p: [0.02, 0.035, 0.24], k: [0.52, 0.07, 0.38], r: [0, -0.08, 0], c: 0xbab6ac })]), tile, { recv: true }),
      stub: new Inst(g, merged([box({ p: [0, 0.04, 0], k: [0.46, 0.08, 0.46], c: 0x9a968c }), { s: 'cyl', p: [0, 0.3, 0], k: [0.15, 0.5, 0.15], c: 0xc0bab0 }, { s: 'cyl', p: [0.02, 0.58, 0], r: [0.35, 0, 0.25], k: [0.13, 0.1, 0.13], c: 0xa8a294 }]), solid, { cast: true, ol: true }),
      tuft: new Inst(g, merged([[0, 0], [0.1, 0.06], [-0.08, 0.08]].map(([x, z], n) => ({ s: 'cone', p: [x, 0.1, z], k: [0.045, 0.22 - n * 0.04, 0.045], seg: 5, c: [0x5aa83a, 0x6ab84a, 0x4e9a34][n] }))), solid, {}),
      floor_dirt: new Inst(g, K.tileGeo(0.98, 0.06, 0.98, 1, 0.8), tile, { recv: true }),
      floor_wood: new Inst(g, merged([0, 1, 2].map((n) => box({ p: [-0.33 + n * 0.33, 0, 0], k: [0.31, 0.06, 0.98], c: [0xb07a44, 0xa06a3a, 0xbc8a50][n] }))), tile, { recv: true }),
      floor_stone: new Inst(g, merged([[-1, -1], [1, -1], [-1, 1], [1, 1]].map(([a, b], n) => box({ p: [a * 0.245, 0, b * 0.245], k: [0.47, 0.07, 0.47], c: [0xb4b0a6, 0xa6a298, 0xaca89e, 0xbab6ac][n] }))), tile, { recv: true }),
      floor_carpet: new Inst(g, merged([box({ k: [1, 0.05, 1], c: 0x8a2434 }), box({ p: [0, 0.006, 0], k: [0.76, 0.05, 0.76], c: 0xb83a4a }), box({ p: [0, 0.012, 0], r: [0, Math.PI / 4, 0], k: [0.28, 0.05, 0.28], c: 0xd8a040 })]), tile, { recv: true }),
      post: new Inst(g, K.tileGeo(1, 1, 1, 1.05, 0.78), solid, { cast: true, recv: true, ol: true }),
      link: new Inst(g, K.tileGeo(1, 1, 1, 1.05, 0.78), solid, { cast: true, recv: true, ol: true }),
      door: new Inst(g, merged([box({ p: [-0.42, 0.5, 0], k: [0.14, 1.0, 0.46], c: 0x6a4526 }), box({ p: [0.42, 0.5, 0], k: [0.14, 1.0, 0.46], c: 0x6a4526 }), box({ p: [0, 0.96, 0], k: [1.0, 0.14, 0.5], c: 0x5a3a22 }), box({ p: [0, 0.44, 0], k: [0.7, 0.86, 0.08], c: 0x8a5a32 }), box({ p: [-0.12, 0.44, 0.045], k: [0.03, 0.84, 0.01], c: 0x5a3a22 }), box({ p: [0.12, 0.44, 0.045], k: [0.03, 0.84, 0.01], c: 0x5a3a22 }), { s: 'sphere', p: [0.25, 0.44, 0.06], k: 0.035, c: 0xd8b040 }]), solid, { cast: true, ol: true }),
      tree: new Inst(g, merged([{ s: 'cyl', p: [0, 0.35, 0], k: [0.12, 0.7, 0.12], c: 0x6a4526 }, { s: 'ico', detail: 1, p: [0, 1.05, 0], k: [0.55, 0.6, 0.55], c: 0x4f9a3f }, { s: 'ico', p: [0.15, 1.45, 0.05], k: [0.38, 0.4, 0.38], c: 0x62b24f }]), solid, { cast: true, ol: true }),
      rock: new Inst(g, merged([{ s: 'ico', p: [0, 0.2, 0], k: [0.42, 0.32, 0.38], c: 0x9a968c }, { s: 'ico', p: [0.22, 0.12, 0.18], k: [0.22, 0.18, 0.2], c: 0x8a867e }, { s: 'ico', p: [-0.2, 0.1, 0.2], k: [0.18, 0.14, 0.16], c: 0xaaa69c }]), solid, { cast: true, ol: true }),
      ore: new Inst(g, merged([{ s: 'ico', p: [0, 0.2, 0], k: [0.42, 0.3, 0.38], c: 0x6e6862 }, { s: 'ico', p: [0.22, 0.12, 0.18], k: [0.22, 0.18, 0.2], c: 0x7a746c }, { s: 'oct', p: [0.02, 0.5, 0], r: [0.2, 0, 0.3], k: [0.1, 0.22, 0.1], c: 0x5ae0ff }, { s: 'oct', p: [-0.2, 0.4, 0.1], r: [-0.3, 0, -0.4], k: [0.08, 0.17, 0.08], c: 0xc46aff }, { s: 'oct', p: [0.22, 0.36, -0.1], r: [0.4, 0, 0.3], k: [0.08, 0.15, 0.08], c: 0xffc84a }, { s: 'oct', p: [0.12, 0.3, 0.26], r: [-0.2, 0, 0.5], k: [0.06, 0.12, 0.06], c: 0x5ae0ff }]), solid, { cast: true, ol: true }),
      zone: new Inst(g, flat(), this.mZone, { order: 1 }),
      bp: new Inst(g, new THREE.BoxGeometry(1, 1, 1), this.mGhost, { order: 3 }),
      pv: new Inst(g, new THREE.BoxGeometry(1, 1, 1), this.mGhost, { order: 4 }),
    };
    this.gFurn = new THREE.Group(); this.gMark = new THREE.Group(); this.gSel = new THREE.Group(); g.add(this.gFurn, this.gMark, this.gSel);
    this.makeFire();
    this.setLight(this.R);
  }
  /* ---------- 모닥불 (칸 cx, cy) ---------- */
  makeFire() {
    const f = this.fire = new THREE.Group(), stones = Array.from({ length: 8 }, (_, k) => ({ s: 'ico', p: [Math.cos(k * 0.785) * 0.34, 0.06, Math.sin(k * 0.785) * 0.34], k: [0.1, 0.08, 0.09], c: k % 2 ? 0x8a867e : 0x9a968c }));
    const base = new THREE.Mesh(merged([...stones, { s: 'cyl', p: [0, 0.08, 0], r: [0, 0.5, Math.PI / 2], k: [0.06, 0.5, 0.06], c: 0x6a4526 }, { s: 'cyl', p: [0, 0.1, 0], r: [0, -0.7, Math.PI / 2], k: [0.06, 0.5, 0.06], c: 0x5a3a22 }, { s: 'sphere', p: [0, 0.05, 0], k: [0.2, 0.04, 0.2], c: 0x3a2a24 }]), this.mSolid);
    base.castShadow = true; f.add(base);
    const cone = (r, h, c, x = 0, z = 0) => { const m = new THREE.Mesh(new THREE.ConeGeometry(r, h, 7).translate(0, h / 2, 0), new THREE.MeshBasicMaterial({ color: new THREE.Color(...c), toneMapped: false })); m.position.set(x, 0.08, z); return m; };
    this.flame = new THREE.Group(); this.flame.add(cone(0.17, 0.52, [1.0, 0.42, 0.06]), cone(0.1, 0.34, [1.0, 0.62, 0.12], 0.1, 0.05), cone(0.1, 0.3, [1.0, 0.62, 0.12], -0.09, -0.06), cone(0.09, 0.32, [1.0, 0.88, 0.35]));
    this.fireGlow = glowSprite(0xff9a3a, 3.2, 0.55); this.fireGlow.position.y = 0.4; this.fireGlow.raycast = NORAY;
    f.add(this.flame, this.fireGlow); f.traverse((o) => { if (o.isMesh) o.userData.pick = { fire: true }; }); this.group.add(f);
  }
  /** 땅 · 바닥 · 벽 · 나무 · 가구 · 구역 · 모닥불을 S로 다시 짓는다(편집마다 불러도 된다) */
  setWorld(S) {
    this.S = S; const { W, H } = S, I = this.I, at = (x, y) => (x < 0 || y < 0 || x >= W || y >= H ? 0 : S.wall[y * W + x]);
    this.U.c.value.set(S.cx, S.cy); this.fire.position.set(S.cx, 0, S.cy); this.ring.position.set(S.cx, 0.09, S.cy);
    for (const k in I) if (k !== 'bp' && k !== 'pv') I[k].begin();
    const occ = new Set(); for (const f of S.furn) { const [w, h] = footprint(f.k, f.rot); for (let dy = 0; dy < h; dy++) for (let dx = 0; dx < w; dx++) occ.add((f.y + dy) * W + f.x + dx); }
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
      const i = y * W + x, t = S.terr[i], h = K.hash(i * 1.37 + 0.5), h2 = K.hash(i * 3.11 + 7.1), rot = h2 * 6.28;
      _col.setHex(GROUND[t]).multiplyScalar(0.93 + h * 0.12 + ((x + y) & 1) * 0.025);
      if (t === TR.water) { I.ground.put(x, -0.42, y, 0, 1, 0.4, 1, _col); I.water.put(x, -0.09, y); } else I.ground.put(x, -0.2, y, 0, 1, 0.4, 1, _col);
      if (t === TR.tree) { const s = 0.72 + h2 * 0.3; I.tree.put(x + (h - 0.5) * 0.3, 0, y + (h2 - 0.5) * 0.3, rot, s, s, s, _col.setRGB(0.9 + h * 0.2, 0.95 + h2 * 0.1, 0.9)); }
      else if (t === TR.rock) { const s = 0.85 + h * 0.3; I.rock.put(x, 0, y, rot, s, s * (0.8 + h2 * 0.4), s); }
      else if (t === TR.ore) I.ore.put(x, 0, y, rot, 1, 1, 1);
      else if (t === TR.ruin && !S.floor[i]) { I.ruin.put(x, 0, y, Math.floor(h * 4) * Math.PI / 2); if (h2 < 0.14 && !S.wall[i] && !occ.has(i)) I.stub.put(x + (h - 0.5) * 0.3, 0, y + (h2 - 0.07) * 2, rot); }
      else if (t === TR.grass && h > 0.5 && !S.floor[i] && !S.wall[i] && !occ.has(i) && (x !== S.cx || y !== S.cy)) { const s = 0.8 + h2 * 0.5; I.tuft.put(x + (h - 0.75) * 1.4, 0, y + (h2 - 0.5) * 0.7, rot, s, s, s); }
      if (S.floor[i]) { const fk = FLOOR_BY_ID[S.floor[i]]; I['floor_' + fk]?.put(x, 0.03, y, 0, 1, 1, 1, _col.copy(fk === 'dirt' ? DIRT_F : WHITE).multiplyScalar(0.95 + h * 0.08)); }
      if (S.zone[i]) { const z = ZONE_TYPES[ZONE_BY_ID[S.zone[i]]]; if (z) I.zone.put(x, 0.075, y, 0, 0.92, 1, 0.92, _col.setHex(z.color)); }
      const w = S.wall[i]; if (!w) continue;
      if (w === DOOR) { const hz = (at(x - 1, y) && at(x - 1, y) !== DOOR) || (at(x + 1, y) && at(x + 1, y) !== DOOR); I.door.put(x, 0, y, hz ? 0 : Math.PI / 2); }
      else { const P = WK[w] || WK[WALLS.wood.id]; I.post.put(x, (P.h + 0.06) / 2, y, 0, P.t * 2 + 0.06, P.h + 0.06, P.t * 2 + 0.06, _col.setHex(P.c).multiplyScalar(0.94 + h * 0.08)); }
      for (const [dx, dy] of [[1, 0], [0, 1]]) { // 오른쪽 · 아래 이웃과 잇는다
        const v = at(x + dx, y + dy); if (!v || (w === DOOR && v === DOOR)) continue;
        const P = WK[w === DOOR ? v : w] || WK[WALLS.wood.id], ha = w === DOOR ? 0.4 : P.t, hb = v === DOOR ? 0.4 : (WK[v] || P).t, c = (ha + 1 - hb) / 2, len = 1 - hb - ha;
        I.link.put(x + dx * c, P.h / 2, y + dy * c, 0, dx ? len : P.t * 2, P.h, dy ? len : P.t * 2, _col.setHex(P.c).multiplyScalar(0.9 + h2 * 0.08));
      }
    }
    for (const k in I) if (k !== 'bp' && k !== 'pv') I[k].end();
    this._gb = Float32Array.from(I.ground.mesh.instanceColor.array); this.tint();
    this.buildFurn(S); this.setBlueprints(this._bp, this._bad); this.setLayers(this.mode);
  }
  /** 빛 밖 칸은 땅을 한 번 더 어둡게(칸 단위로 경계가 읽히게) */
  tint() {
    const S = this.S; if (!S || !this._gb) return;
    const R = this.R, a = this.I.ground.mesh.instanceColor, arr = a.array;
    for (let i = 0; i < S.W * S.H; i++) { const x = i % S.W, y = (i / S.W) | 0, k = (x - S.cx) ** 2 + (y - S.cy) ** 2 > R * R + R ? 0.5 : 1; for (let c = 0; c < 3; c++) arr[i * 3 + c] = this._gb[i * 3 + c] * k; }
    a.needsUpdate = true;
  }
  /* ---------- 가구: 종류마다 모양을 한 번 만들어 같이 쓴다 ---------- */
  buildFurn(S) {
    const keep = new Set([this.mSolid, K.OUTLINE, ...Object.values(this.tpl).flatMap((t) => [t.geo, t.ol])]);
    this.gFurn.traverse((o) => { if (o.material && !keep.has(o.material)) o.material.dispose(); if (o.geometry && !o.isSprite && !keep.has(o.geometry)) o.geometry.dispose(); });
    this.gFurn.clear(); this.furn = [];
    for (const f of S.furn) {
      if (!FURN[f.k]) continue;
      const t = this.tpl[f.k] ||= (() => { const geo = merged(furnParts(f.k)); return { geo, ol: K.outlineGeo(geo) }; })();
      const g = new THREE.Group(), body = new THREE.Group(), m = new THREE.Mesh(t.geo, this.mSolid); m.castShadow = m.receiveShadow = true;
      body.add(m, new THREE.Mesh(t.ol, K.OUTLINE)); g.add(body);
      const anim = furnExtras(f.k, body), [w, h] = footprint(f.k, f.rot);
      g.position.set(f.x + (w - 1) / 2, S.floor[f.y * S.W + f.x] ? 0.06 : 0, f.y + (h - 1) / 2); body.rotation.y = -(f.rot || 0) * Math.PI / 2;
      g.traverse((o) => { if (o.isMesh) o.userData.pick = { furn: f.id }; else if (o.isSprite) o.raycast = NORAY; });
      g.userData.furn = f.id; this.gFurn.add(g); this.furn.push({ g, anim, ph: K.hash(f.x * 7 + f.y) * 6 });
    }
  }
  /* ---------- 청사진 · 미리보기 ---------- */
  ghosts(inst, list, colorOf) {
    const S = this.S, W = S ? S.W : 40, H = S ? S.H : 40, built = (x, y) => S && x >= 0 && y >= 0 && x < W && y < H && S.wall[y * W + x], gw = new Set();
    for (const b of [...this._bp, ...list]) if (b.L === 'wall') gw.add(b.y * W + b.x);
    const wallAt = (x, y) => x >= 0 && y >= 0 && x < W && y < H && (gw.has(y * W + x) || built(x, y));
    inst.begin();
    for (const b of list) {
      const c = colorOf(b), { x, y } = b;
      if (b.L === 'floor') inst.put(x, 0.05, y, 0, 0.94, 0.1, 0.94, c);
      else if (b.L === 'wall' && b.k === 'door') { const hz = wallAt(x - 1, y) || wallAt(x + 1, y); inst.put(x, 0.5, y, 0, hz ? 0.96 : 0.24, 1, hz ? 0.24 : 0.96, c); }
      else if (b.L === 'wall') {
        inst.put(x, 0.52, y, 0, 0.5, 1.04, 0.5, c);
        for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) { if (!wallAt(x + dx, y + dy)) continue; const len = built(x + dx, y + dy) && !gw.has((y + dy) * W + x + dx) ? 0.5 : 0.25; inst.put(x + dx * (0.25 + len / 2), 0.5, y + dy * (0.25 + len / 2), 0, dx ? len : 0.44, 1, dy ? len : 0.44, c); }
      } else if (FURN[b.k]) { const [w, h] = footprint(b.k, b.rot), hh = FURN_H[b.k] || 0.8; inst.put(x + (w - 1) / 2, hh / 2 + 0.02, y + (h - 1) / 2, 0, w - 0.12, hh, h - 0.12, c); }
    }
    inst.end();
  }
  /** 청사진(반투명 하늘색, badIds에 있으면 빨강) */
  setBlueprints(bps = [], badIds = new Set()) { this._bp = bps; this._bad = badIds; this.ghosts(this.I.bp, bps, (b) => (badIds.has(b.id) ? C_BAD : C_BP)); }
  /** 끄는 동안: ok 초록, bad 빨강. 인자 없이 부르면 지운다 */
  setPreview(ok = [], bad = []) { const B = new Set(bad); this.ghosts(this.I.pv, [...ok, ...bad], (b) => (B.has(b) ? C_BAD : C_OK)); }
  /* ---------- 바닥 윤곽 ---------- */
  rect(par, x, y, w, h, color, spark) {
    const m = new THREE.Mesh(new THREE.PlaneGeometry(w + 0.4, h + 0.4).rotateX(-Math.PI / 2), rectMat(this.U, w, h, color, spark));
    m.position.set(x + (w - 1) / 2, 0.1, y + (h - 1) / 2); m.renderOrder = 5; m.raycast = NORAY; par.add(m);
  }
  clearGroup(g) { for (const o of [...g.children]) { o.geometry.dispose(); o.material.dispose(); g.remove(o); } }
  /** 추천 자리 [{x, y, w, h}] (왼쪽 위 칸 + 크기): 반짝이며 숨 쉬는 윤곽 */
  setMarkers(spots = []) { this.clearGroup(this.gMark); spots.forEach((s, n) => this.rect(this.gMark, s.x, s.y, s.w || 1, s.h || 1, 0xffd06a, 1 + n * 1.7)); }
  /** 시작점 · 선택 윤곽 {x0, y0, x1, y1} 또는 null */
  setSelect(r) {
    this.clearGroup(this.gSel); if (!r) return;
    const x = Math.min(r.x0, r.x1), y = Math.min(r.y0, r.y1); this.rect(this.gSel, x, y, Math.abs(r.x1 - r.x0) + 1, Math.abs(r.y1 - r.y0) + 1, 0xbff4ff, 0);
  }
  /* ---------- 빛 · 불 · 층 ---------- */
  /** 지을 수 있는 반경 R: 밖은 어둡고 경계가 일렁인다 */
  setLight(R) {
    this.R = R; const e = Math.sqrt(R * R + R); this.U.r.value = e;
    this.ring.scale.set(2 * e + 8, 1, 2 * e + 8); this.tint();
  }
  /** 모닥불 크기 1..3 */
  setFire(level) { this.fireK = FIRE_K[Math.max(1, Math.min(3, level | 0)) - 1]; }
  /** 'all' | 'floor'(벽·가구 숨김) | 'walls'(가구 숨김) | 'zones'(구역 말고 흐리게) */
  setLayers(mode = 'all') {
    this.mode = mode; const walls = mode !== 'floor', furn = mode === 'all' || mode === 'zones';
    for (const k of ['post', 'link', 'door']) this.I[k].show(walls);
    this.gFurn.visible = furn; this.U.dim.value = mode === 'zones' ? 0.4 : 1; this.mZone.opacity = mode === 'zones' ? 0.62 : 0.34;
  }
  frame(dt, time) {
    this.U.t.value = time;
    const k = this.fireK, fl = this.flame, s = k * (1 + Math.sin(time * 13) * 0.04 + Math.sin(time * 7.3 + 1) * 0.05);
    fl.scale.set(s * (1 + Math.sin(time * 17) * 0.05), s * (1 + Math.sin(time * 9.1) * 0.12 + Math.sin(time * 23.7) * 0.06), s); fl.rotation.y += dt * 1.3;
    this.fireGlow.scale.setScalar(3.2 * k * (0.95 + Math.sin(time * 11) * 0.04)); this.fireGlow.material.opacity = 0.45 + k * 0.1;
    for (const f of this.furn) furnAnim(f.anim, time, f.ph);
  }
  dispose() {
    this.scene.remove(this.group);
    for (const k in this.I) this.I[k].dispose();
    for (const t of Object.values(this.tpl)) { t.geo.dispose(); t.ol.dispose(); }
    this.group.traverse((o) => { if (o.isInstancedMesh) return; o.geometry?.dispose(); if (o.material && o.material !== K.OUTLINE && !this.mats.includes(o.material)) o.material.dispose(); });
    for (const m of this.mats) m.dispose();
    this.tpl = {}; this.furn = [];
  }
}
