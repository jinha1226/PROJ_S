import * as THREE from 'three';
import * as K from '../diorama.js';
import { CLOUD, SURF } from '../../data/codes.js';
import { OUTLINE, SHARED, _c, _e, _m4, _q, _s, _v, hash, outlineGeo, outlineMaterial, toon } from './materials.js';

/* ---------------- 격자: 바닥 · 벽(반투명) · 물/기름/얼음/풀 · 불 · 구름 · 바닥 표시 ---------------- */
export function tileGeo(w, h, d, topC = 1, sideC = 0.72) {
  const g = new THREE.BoxGeometry(w, h, d);
  const n = g.getAttribute('normal'), col = new Float32Array(n.count * 3);
  for (let i = 0; i < n.count; i++) { const ny = n.getY(i), v = ny > 0.5 ? topC : ny < -0.5 ? 0.35 : sideC; col[i * 3] = col[i * 3 + 1] = col[i * 3 + 2] = v; }
  g.setAttribute('color', new THREE.BufferAttribute(col, 3)); g.deleteAttribute('uv');
  return g;
}

export /** 둥근 얼음판(칸 경계 없는 모드) */
function roundSlab(r, h) {
  const g = new THREE.CylinderGeometry(r, r * 1.04, h, 16);
  const n = g.getAttribute('normal'), col = new Float32Array(n.count * 3);
  for (let i = 0; i < n.count; i++) { const v = n.getY(i) > 0.5 ? 1 : 0.78; col[i * 3] = col[i * 3 + 1] = col[i * 3 + 2] = v; }
  g.setAttribute('color', new THREE.BufferAttribute(col, 3)); g.deleteAttribute('uv'); return g;
}
function roundedRectGeo(size, r) {
  const s = size / 2, sh = new THREE.Shape();
  sh.moveTo(-s + r, -s); sh.lineTo(s - r, -s); sh.quadraticCurveTo(s, -s, s, -s + r); sh.lineTo(s, s - r); sh.quadraticCurveTo(s, s, s - r, s);
  sh.lineTo(-s + r, s); sh.quadraticCurveTo(-s, s, -s, s - r); sh.lineTo(-s, -s + r); sh.quadraticCurveTo(-s, -s, -s + r, -s);
  return new THREE.ShapeGeometry(sh, 4).rotateX(-Math.PI / 2);
}

export function liquidMaterial(kind) {
  const water = kind === 'water';
  const m = new THREE.MeshPhongMaterial(water
    ? { color: 0x2f7be0, specular: 0xe6f2ff, shininess: 80, transparent: true, opacity: 0.88, emissive: 0x071a36 }
    : { color: 0x0b0a10, specular: 0xffffff, shininess: 150, transparent: true, opacity: 0.94, emissive: 0x000000 });
  m.onBeforeCompile = (sh) => {
    sh.uniforms.uTime = SHARED.uTime;
    sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nvarying vec3 vWP;').replace('#include <project_vertex>', `#include <project_vertex>
{ vec4 w4 = vec4(transformed, 1.0);
#ifdef USE_INSTANCING
  w4 = instanceMatrix * w4;
#endif
  vWP = (modelMatrix * w4).xyz; }`);
    const amp = water ? '0.14' : '0.06', spd = water ? '1.0' : '0.35';
    sh.fragmentShader = sh.fragmentShader.replace('#include <common>', '#include <common>\nvarying vec3 vWP;\nuniform float uTime;')
      .replace('#include <normal_fragment_maps>', `#include <normal_fragment_maps>
{ vec2 q = vWP.xz; float t = uTime * ${spd};
  vec2 g = vec2(cos(q.x * 3.3 + t * 1.7) + 0.6 * cos(q.y * 4.1 - t * 1.2 + q.x * 1.3), sin(q.y * 3.1 + t * 1.4) + 0.6 * sin(q.x * 3.7 + q.y * 1.9 - t)) * ${amp};
  normal = normalize(normal + (viewMatrix * vec4(g.x, 0.0, g.y, 0.0)).xyz); }`)
      .replace('#include <emissivemap_fragment>', water ? `#include <emissivemap_fragment>
{ vec2 q = vWP.xz; float c = sin(q.x * 5.0 + sin(q.y * 4.0 + uTime) * 1.5 + uTime * 0.8) * sin(q.y * 5.5 + sin(q.x * 3.0 - uTime * 0.7) * 1.5);
  float visK = 1.0;
#ifdef USE_COLOR
  visK = vColor.g * vColor.g;
#endif
  totalEmissiveRadiance *= visK;
  totalEmissiveRadiance += vec3(0.05, 0.16, 0.34) * smoothstep(0.5, 0.95, c) * visK; }` : `#include <emissivemap_fragment>
{ float f = dot(vWP.xz, vec2(0.9, 0.5)) + sin(vWP.x * 2.3 + uTime * 0.4) * 0.3 + uTime * 0.05;
  totalEmissiveRadiance += 0.07 * (0.5 + 0.5 * cos(6.2831 * (vec3(0.0, 0.33, 0.67) + f))); }`);
  };
  m.customProgramCacheKey = () => 'dk-liquid-' + kind;
  return m;
}

export function decalMaterial() {
  return new THREE.ShaderMaterial({
    uniforms: { uTime: SHARED.uTime },
    vertexShader: `attribute vec4 aCol; attribute float aKind; attribute float aRot; attribute float aBlink;
varying vec4 vCol; varying float vKind; varying float vBlink; varying vec2 vP;
void main(){ vCol = aCol; vKind = aKind; vBlink = aBlink; float c = cos(aRot), s = sin(aRot); vec2 p = uv - 0.5;
  vP = vec2(c * p.x - s * p.y, s * p.x + c * p.y);
  gl_Position = projectionMatrix * modelViewMatrix * instanceMatrix * vec4(position, 1.0); }`,
    fragmentShader: `uniform float uTime; varying vec4 vCol; varying float vKind; varying float vBlink; varying vec2 vP;
float sdBox(vec2 p, vec2 b, float r){ vec2 q = abs(p) - b + r; return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r; }
float sdSeg(vec2 p, vec2 a, vec2 b){ vec2 pa = p - a, ba = b - a; float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0); return length(pa - ba * h); }
void main(){
  vec2 p = vP; float a = 0.0; int k = int(vKind + 0.5);
  if (k == 0) { float d = sdBox(p, vec2(0.44), 0.1); a = smoothstep(0.015, -0.015, d) * 0.4 + smoothstep(0.04, 0.0, abs(d + 0.025)) * 0.6; }
  else if (k == 1) { float d = sdBox(p, vec2(0.43), 0.11); float e = smoothstep(0.035, 0.008, abs(d + 0.02)); vec2 ap = abs(p); a = e * step(0.19, ap.x) * step(0.19, ap.y); }
  else if (k == 2) { float d = min(sdSeg(p, vec2(-0.27, -0.14), vec2(0.0, 0.14)), sdSeg(p, vec2(0.27, -0.14), vec2(0.0, 0.14))); a = smoothstep(0.085, 0.055, d); a += smoothstep(0.02, -0.02, sdBox(p, vec2(0.44), 0.1)) * 0.18; }
  else if (k == 3) { a = smoothstep(0.12, 0.09, length(p)); }
  else if (k == 4) { float r = length(p); a = smoothstep(0.05, 0.02, abs(r - 0.41)); }
  else if (k == 5) { float d = sdBox(p, vec2(0.45), 0.08); float inside = smoothstep(0.01, -0.01, d); float stripe = step(0.5, fract((p.x + p.y) * 3.5 - uTime * 1.2));
    a = inside * (0.3 + 0.32 * stripe) + smoothstep(0.045, 0.0, abs(d + 0.02)) * 0.95; }
  else if (k == 6) { float d = min(sdSeg(p, vec2(-0.24), vec2(0.24)), sdSeg(p, vec2(-0.24, 0.24), vec2(0.24, -0.24))); a = smoothstep(0.08, 0.05, d); }
  else if (k == 7) { float r = length(p); a = smoothstep(0.5, 0.3, r) * 0.55; }
  else if (k == 8) { float r = length(p); float inside = smoothstep(0.455, 0.44, r); float stripe = step(0.5, fract((p.x + p.y) * 7.0 - uTime * 1.2)); a = inside * (0.26 + 0.3 * stripe) + smoothstep(0.02, 0.0, abs(r - 0.44)) * 0.95; }
  else if (k == 9) { vec2 q = abs(p); float inside = step(q.x, 0.48) * step(q.y, 0.5); float stripe = step(0.5, fract(p.y * 9.0 - uTime * 2.0)); a = inside * (0.22 + 0.3 * stripe) + smoothstep(0.03, 0.0, abs(q.x - 0.46)) * step(q.y, 0.5) * 0.9; }
  float blink = mix(1.0, 0.3 + 0.7 * (0.5 + 0.5 * sin(uTime * 9.0)), vBlink);
  a *= vCol.a * blink;
  if (a < 0.01) discard;
  gl_FragColor = vec4(vCol.rgb, a);
}`,
    transparent: true, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -2,
  });
}

export class GridView {
  /**
   * @param o.kind (i) => 'wall' | 'floor' | 'void'
   * @param o.palette { floor, floor2, wall, wall2, void, grassFloor, waterFloor, dim }
   */
  constructor(scene, o) {
    const { w, h, kind, palette, wallH = 1.2, seamless = false } = o;
    this.seamless = seamless;
    Object.assign(this, { scene, w, h, wallH, pal: palette });
    this.group = new THREE.Group(); scene.add(this.group);
    this.lvl = null; this.surf = new Uint8Array(w * h); this.fire = new Uint8Array(w * h); this.cloud = new Uint8Array(w * h); this.cloudT = new Uint8Array(w * h);
    const K = new Uint8Array(w * h);
    for (let i = 0; i < w * h; i++) K[i] = kind(i) === 'wall' ? 2 : kind(i) === 'floor' ? 1 : 0;
    this.floorIdx = []; this.wallIdx = [];
    for (let i = 0; i < w * h; i++) {
      if (K[i] === 1) this.floorIdx.push(i);
      else if (K[i] === 2) {
        const x = i % w, y = (i / w) | 0; let near = false;
        for (let dy = -1; dy <= 1 && !near; dy++) for (let dx = -1; dx <= 1; dx++) { const nx = x + dx, ny = y + dy; if (nx >= 0 && ny >= 0 && nx < w && ny < h && K[ny * w + nx] === 1) { near = true; break; } }
        if (near) this.wallIdx.push(i);
      }
    }
    const P = (c) => new THREE.Color(c);
    this.cFloor = P(palette.floor); this.cFloor2 = P(palette.floor2 ?? palette.floor); this.cWall = P(palette.wall); this.cWall2 = P(palette.wall2 ?? palette.wall);
    this.cGrassF = P(palette.grassFloor ?? 0x3d5a2e); this.cWaterF = P(palette.waterFloor ?? 0x1a2a55); this.cAsh = P(palette.ash ?? 0x2a2422); this.cMem = P(palette.memTint ?? 0x28305a);
    this.dim = palette.dim ?? 0.34;

    const base = new THREE.Mesh(new THREE.PlaneGeometry(w + 30, h + 30).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ color: palette.void ?? 0x05060a }));
    base.position.set(w / 2 - 0.5, -0.34, h / 2 - 0.5); this.group.add(base);

    const nF = this.floorIdx.length, nW = this.wallIdx.length;
    const fs = seamless ? 1.0 : 0.955;
    this.floorMesh = new THREE.InstancedMesh(tileGeo(fs, 0.3, fs, 1.0, 0.6), toon({ vertexColors: true, gloss: 0.16 }), nF);
    this.floorMesh.receiveShadow = true;
    this.floorBase = this.floorIdx.map((i) => { const x = i % w, y = (i / w) | 0; return this.cFloor.clone().lerp(this.cFloor2, seamless ? 0.35 + (Math.sin(x * 0.7 + y * 0.4) + Math.sin(y * 0.9 - x * 0.3)) * 0.15 + hash(i) * 0.12 : ((x + y) & 1) ? 0.85 : 0.1 + hash(i) * 0.3).multiplyScalar(0.93 + hash(i + 7) * 0.12); });

    const wg = tileGeo(1.0, wallH, 1.0, 1.0, 0.72);
    this.wallFade = new THREE.InstancedBufferAttribute(new Float32Array(Math.max(1, nW)), 1);
    wg.setAttribute('aFade', this.wallFade);
    this.wallMesh = new THREE.InstancedMesh(wg, toon({ vertexColors: true, gloss: 0.22, fade: true }), nW);
    this.wallMesh.castShadow = true; this.wallMesh.receiveShadow = true;
    const wog = outlineGeo(wg); wog.setAttribute('aFade', this.wallFade);
    this.wallOL = new THREE.InstancedMesh(wog, outlineMaterial({ width: 0.035, fade: true }), nW);
    this.wallBase = this.wallIdx.map((i) => this.cWall.clone().lerp(this.cWall2, hash(i * 3.1)).multiplyScalar(0.9 + hash(i + 3) * 0.15));

    this.water = new THREE.InstancedMesh(seamless ? new THREE.CircleGeometry(0.74, 18).rotateX(-Math.PI / 2) : new THREE.PlaneGeometry(1, 1).rotateX(-Math.PI / 2), liquidMaterial('water'), nF);
    this.oil = new THREE.InstancedMesh(seamless ? new THREE.CircleGeometry(0.7, 18).rotateX(-Math.PI / 2) : roundedRectGeo(0.97, 0.24), liquidMaterial('oil'), nF);
    this.ice = new THREE.InstancedMesh(seamless ? roundSlab(0.66, 0.12) : tileGeo(0.99, 0.12, 0.99, 1, 0.78), toon({ color: 0xd4f3ff, vertexColors: true, gloss: 1.3, emissive: 0x0d2a3d }), nF);
    this.ice.receiveShadow = true;
    const blade = new THREE.ConeGeometry(0.055, 0.44, 3).translate(0, 0.22, 0);
    { const pa = blade.getAttribute('position'), col = new Float32Array(pa.count * 3); for (let i = 0; i < pa.count; i++) { const t = pa.getY(i) / 0.44; const v = 0.45 + t * 0.75; col[i * 3] = v * 0.75; col[i * 3 + 1] = v; col[i * 3 + 2] = v * 0.55; } blade.setAttribute('color', new THREE.BufferAttribute(col, 3)); }
    this.BLADES = 10;
    this.grass = new THREE.InstancedMesh(blade, toon({ color: 0x6cc24a, vertexColors: true, gloss: 0.2, sway: true }), nF * this.BLADES);

    const flame = (r, hh) => new THREE.ConeGeometry(r, hh, 7).translate(0, hh / 2, 0);
    this.flameO = new THREE.InstancedMesh(flame(0.22, 0.62), new THREE.MeshBasicMaterial({ color: new THREE.Color(1.0, 0.42, 0.06), toneMapped: false }), 240);
    this.flameI = new THREE.InstancedMesh(flame(0.12, 0.42), new THREE.MeshBasicMaterial({ color: new THREE.Color(1.0, 0.86, 0.3), toneMapped: false }), 240);
    this.puffs = new THREE.InstancedMesh(new THREE.IcosahedronGeometry(0.32, 1), toon({ color: 0xffffff, gloss: 0.1, transparent: true, opacity: 0.8, emissive: 0x1a1d26 }), 480);
    this.puffs.renderOrder = 12;

    this.DCAP = 800;
    const dg = new THREE.PlaneGeometry(1, 1).rotateX(-Math.PI / 2);
    this.dCol = new THREE.InstancedBufferAttribute(new Float32Array(this.DCAP * 4), 4); this.dKind = new THREE.InstancedBufferAttribute(new Float32Array(this.DCAP), 1);
    this.dRot = new THREE.InstancedBufferAttribute(new Float32Array(this.DCAP), 1); this.dBlink = new THREE.InstancedBufferAttribute(new Float32Array(this.DCAP), 1);
    dg.setAttribute('aCol', this.dCol); dg.setAttribute('aKind', this.dKind); dg.setAttribute('aRot', this.dRot); dg.setAttribute('aBlink', this.dBlink);
    this.decals = new THREE.InstancedMesh(dg, decalMaterial(), this.DCAP); this.decals.count = 0; this.decals.renderOrder = 10;

    for (const m of [this.floorMesh, this.wallMesh, this.wallOL, this.water, this.oil, this.ice, this.grass, this.flameO, this.flameI, this.puffs, this.decals]) { m.frustumCulled = false; this.group.add(m); }
    for (const m of [this.water, this.oil, this.ice, this.grass, this.flameO, this.flameI, this.puffs]) m.count = 0;
    // instanceColor를 미리 만들어 둔다(없으면 첫 setColorAt에서 셰이더가 바뀐다)
    for (const m of [this.floorMesh, this.wallMesh, this.water, this.oil, this.ice, this.grass, this.puffs]) { if (m.instanceMatrix.count) m.setColorAt(0, _c.setRGB(1, 1, 1)); }
    this.fireList = []; this.cloudList = [];
    this.refresh();
  }
  surfaceY(x, y) { const i = y * this.w + x; if (x < 0 || y < 0 || x >= this.w || y >= this.h) return 0; const s = this.surf[i]; return s === SURF.WATER ? -0.09 : s === SURF.ICE ? 0.07 : 0; }
  setTerrain(t) { if (t.surf) this.surf.set(t.surf); if (t.fire) this.fire.set(t.fire); if (t.cloud) this.cloud.set(t.cloud); if (t.cloudT) this.cloudT.set(t.cloudT); this.refresh(); }
  setVisibility(lvl) { this.lvl = lvl; this.refresh(); }
  refresh() {
    const { w, surf, lvl } = this; const L = (i) => (lvl ? lvl[i] : 2);
    for (let k = 0; k < this.floorIdx.length; k++) {
      const i = this.floorIdx[k], l = L(i), x = i % w, y = (i / w) | 0;
      if (!l) { _m4.makeScale(0, 0, 0); this.floorMesh.setMatrixAt(k, _m4); continue; }
      const s = surf[i];
      _m4.makeTranslation(x, s === SURF.WATER && !this.seamless ? -0.26 : -0.15, y); this.floorMesh.setMatrixAt(k, _m4);
      _c.copy(this.floorBase[k]);
      if (s === SURF.GRASS) _c.lerp(this.cGrassF, 0.65); else if (s === SURF.ASH) _c.lerp(this.cAsh, 0.7); else if (s === SURF.WATER) _c.lerp(this.cWaterF, 0.75);
      if (l === 1) _c.multiplyScalar(this.dim).lerp(this.cMem, 0.18);
      this.floorMesh.setColorAt(k, _c);
    }
    this.floorMesh.instanceMatrix.needsUpdate = true; if (this.floorMesh.instanceColor) this.floorMesh.instanceColor.needsUpdate = true;
    for (let k = 0; k < this.wallIdx.length; k++) {
      const i = this.wallIdx[k], l = L(i), x = i % w, y = (i / w) | 0;
      if (!l) _m4.makeScale(0, 0, 0); else _m4.makeTranslation(x, this.wallH / 2, y);
      this.wallMesh.setMatrixAt(k, _m4); this.wallOL.setMatrixAt(k, _m4);
      _c.copy(this.wallBase[k]); if (l === 1) _c.multiplyScalar(this.dim + 0.08).lerp(this.cMem, 0.15);
      this.wallMesh.setColorAt(k, _c);
    }
    this.wallMesh.instanceMatrix.needsUpdate = this.wallOL.instanceMatrix.needsUpdate = true; if (this.wallMesh.instanceColor) this.wallMesh.instanceColor.needsUpdate = true;
    let nw = 0, no = 0, ni = 0, ng = 0;
    for (let k = 0; k < this.floorIdx.length; k++) {
      const i = this.floorIdx[k], l = L(i); if (!l) continue;
      const s = surf[i]; if (!s || s === SURF.ASH) continue;
      const x = i % w, y = (i / w) | 0, f = l === 2 ? 1 : this.dim + 0.1;
      if (s === SURF.WATER) { _m4.makeTranslation(x, this.seamless ? 0.012 + hash(i) * 0.006 : -0.08, y); this.water.setMatrixAt(nw, _m4); this.water.setColorAt(nw, _c.setScalar(f)); nw++; }
      else if (s === SURF.OIL) { _m4.makeTranslation(x, 0.012 + (this.seamless ? hash(i + 5) * 0.006 : 0), y); this.oil.setMatrixAt(no, _m4); this.oil.setColorAt(no, _c.setScalar(f)); no++; }
      else if (s === SURF.ICE) { _m4.makeTranslation(x, 0.02, y); this.ice.setMatrixAt(ni, _m4); this.ice.setColorAt(ni, _c.setScalar(f)); ni++; }
      else if (s === SURF.GRASS) {
        for (let b = 0; b < this.BLADES; b++) {
          const hx = hash(i * 13 + b), hz = hash(i * 7 + b * 5 + 1), hs = hash(i + b * 17 + 3);
          _e.set((hash(i + b) - 0.5) * 0.5, hash(i * 3 + b) * 6.28, (hash(i * 5 + b) - 0.5) * 0.5); _q.setFromEuler(_e);
          _m4.compose(_v.set(x + (hx - 0.5) * 0.8, 0, y + (hz - 0.5) * 0.8), _q, _s.setScalar(0.7 + hs * 0.7));
          this.grass.setMatrixAt(ng, _m4); this.grass.setColorAt(ng, _c.setRGB(0.8 + hs * 0.4, 0.85 + hx * 0.3, 0.7 + hz * 0.3).multiplyScalar(f)); ng++;
        }
      }
    }
    const fin = (m, n) => { m.count = n; m.instanceMatrix.needsUpdate = true; if (m.instanceColor) m.instanceColor.needsUpdate = true; };
    fin(this.water, nw); fin(this.oil, no); fin(this.ice, ni); fin(this.grass, ng);
    this.fireList = []; this.cloudList = [];
    for (let i = 0; i < this.w * this.h; i++) {
      if (!L(i)) continue;
      if (this.fire[i]) this.fireList.push(i);
      if (this.cloud[i]) this.cloudList.push(i);
    }
  }
  setDecals(list) {
    const n = Math.min(list.length, this.DCAP);
    for (let k = 0; k < n; k++) {
      const d = list[k], sc = d.scale ?? 1;
      _e.set(0, d.yaw ?? 0, 0); _q.setFromEuler(_e);
      _m4.compose(_v.set(d.x, 0.085 + (d.h ?? 0) + this.surfaceY(Math.round(d.x), Math.round(d.y)) * 0.5 + k * 0.00002, d.y), _q, _s.set(d.sx ?? sc, 1, d.sz ?? sc));
      this.decals.setMatrixAt(k, _m4);
      _c.set(d.color ?? 0xffffff);
      this.dCol.setXYZW(k, _c.r, _c.g, _c.b, d.alpha ?? 1); this.dKind.setX(k, d.kind ?? 0); this.dRot.setX(k, d.rot ?? 0); this.dBlink.setX(k, d.blink ?? 0);
    }
    this.decals.count = n; this.decals.instanceMatrix.needsUpdate = true;
    this.dCol.needsUpdate = this.dKind.needsUpdate = this.dRot.needsUpdate = this.dBlink.needsUpdate = true;
  }
  update(dt, t, focus, camPos) {
    // 불꽃
    let n = 0;
    for (const i of this.fireList) {
      const x = i % this.w, y = (i / this.w) | 0, lv = this.fire[i];
      for (let f = 0; f < 3 && n < 240; f++) {
        const ph = hash(i * 3 + f) * 6.28, big = f === 0 ? 1 : 0.62;
        const ox = f === 0 ? 0 : (hash(i + f * 9) - 0.5) * 0.55, oz = f === 0 ? 0 : (hash(i * 2 + f * 5) - 0.5) * 0.55;
        const sy = big * (0.75 + 0.3 * Math.sin(t * 13 + ph) + 0.12 * Math.sin(t * 29 + ph * 2)) * (lv >= 2 ? 1 : 0.7);
        const sxz = big * (0.9 + 0.12 * Math.sin(t * 17 + ph));
        _e.set(Math.sin(t * 9 + ph) * 0.12, t * 2 + ph, Math.cos(t * 7 + ph) * 0.12); _q.setFromEuler(_e);
        _m4.compose(_v.set(x + ox, 0.01, y + oz), _q, _s.set(sxz, sy, sxz));
        this.flameO.setMatrixAt(n, _m4);
        _m4.compose(_v.set(x + ox, 0.02, y + oz), _q, _s.set(sxz, sy * 0.95, sxz)); this.flameI.setMatrixAt(n, _m4);
        n++;
      }
    }
    this.flameO.count = this.flameI.count = n; this.flameO.instanceMatrix.needsUpdate = this.flameI.instanceMatrix.needsUpdate = true;
    // 구름(증기 흰색 / 연기 회색)
    n = 0;
    for (const i of this.cloudList) {
      const x = i % this.w, y = (i / this.w) | 0, steam = this.cloud[i] === CLOUD.STEAM, life = Math.min(1, this.cloudT[i] / 3 + 0.35);
      for (let f = 0; f < 3 && n < 480; f++) {
        const ph = hash(i * 5 + f) * 6.28;
        const s = (0.8 + 0.35 * Math.sin(t * 1.7 + ph)) * life * (steam ? 1.0 : 1.2);
        _m4.compose(_v.set(x + Math.sin(ph) * 0.28, 0.45 + f * 0.28 + Math.sin(t * 1.3 + ph) * 0.08, y + Math.cos(ph * 1.3) * 0.28), _q.identity(), _s.setScalar(s));
        this.puffs.setMatrixAt(n, _m4); this.puffs.setColorAt(n, steam ? _c.setRGB(1, 1, 1.05) : _c.setRGB(0.42, 0.42, 0.47)); n++;
      }
    }
    this.puffs.count = n; this.puffs.instanceMatrix.needsUpdate = true; if (this.puffs.instanceColor) this.puffs.instanceColor.needsUpdate = true;
    // 카메라와 주인공 사이 벽을 반투명(디더)으로
    if (focus && camPos) {
      const dx = camPos.x - focus.x, dz = camPos.z - focus.z, hl = Math.hypot(dx, dz), camH = Math.max(0.1, camPos.y - focus.y);
      const nx = hl > 1e-4 ? dx / hl : 0, nz = hl > 1e-4 ? dz / hl : 1, reach = this.wallH * hl / camH + 0.5;
      const arr = this.wallFade.array; let dirty = false;
      for (let k = 0; k < this.wallIdx.length; k++) {
        const i = this.wallIdx[k], rx = (i % this.w) - focus.x, rz = ((i / this.w) | 0) - focus.z;
        let target = 0;
        if (Math.abs(rx) < 5 && Math.abs(rz) < 5) { const along = rx * nx + rz * nz, lat = Math.abs(rx * nz - rz * nx); if (along > 0.1 && along < reach && lat < 1.0) target = 0.7; }
        const cur = arr[k];
        if (cur !== target) { let v = cur + (target - cur) * Math.min(1, dt * 10); if (Math.abs(v - target) < 0.02) v = target; arr[k] = v; dirty = true; }
      }
      if (dirty) this.wallFade.needsUpdate = true;
    }
  }
  dispose() {
    this.scene.remove(this.group);
    this.group.traverse((o) => { o.geometry?.dispose(); if (o.material && o.material !== OUTLINE) o.material.dispose(); });
  }
}
