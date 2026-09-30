import * as THREE from 'three';

/* ================= 정착지 가구 모양 (docs/설계_정착지_건설.md §4.1) =================
   가구 하나 = 기본 도형 목록(한 메시로 합친다) + 빛·보석 같은 덧붙이. 회전 전 기준: 가로 w칸은 x, 세로 h칸은 z, 앞은 +z */
const WOOD = 0xb07a48, WOOD_D = 0x7a5030, WOOD_DD = 0x5a3a22, STONE = 0xa8a294, IRON = 0x3a3a44, BONE = 0xeee6d0;
const B = (x, y, z, w, h, d, c, r) => ({ s: 'box', p: [x, y, z], k: [w, h, d], c, r });
const C = (x, y, z, rad, h, c, r, seg = 10) => ({ s: 'cyl', p: [x, y, z], k: [rad, h, rad], c, r, seg });
const legs = (w, d, h, c = WOOD_D) => [[-1, -1], [1, -1], [-1, 1], [1, 1]].map(([a, b]) => B(a * w, h / 2, b * d, 0.07, h, 0.07, c));
const scaled = (parts, s) => parts.map((p) => ({ ...p, p: p.p.map((v) => v * s), k: p.k.map((v) => v * s) }));
const h01 = (n) => { const s = Math.sin(n * 91.7 + 17.3) * 43758.5453; return s - Math.floor(s); };

/** 청사진 상자 높이 */
export const FURN_H = { bed: 0.5, table: 0.75, chair: 0.85, shelf: 1.3, lamp: 1.3, hearth: 1.3, anvil: 0.65, herbtable: 1.0, leather: 1.15, bookshelf: 1.55, decor: 0.55, altar: 1.0, gate: 1.15, heap: 0.6 };

/** 가구 도형 목록 (K.partGeo 형식) */
export function furnParts(k) {
  switch (k) {
    case 'bed': return [B(0, 0.14, 0, 0.84, 0.2, 1.86, WOOD), B(0, 0.4, -0.9, 0.86, 0.6, 0.1, WOOD_D), B(0, 0.28, 0.9, 0.86, 0.32, 0.08, WOOD_D), B(0, 0.3, 0.02, 0.74, 0.12, 1.66, 0xf2ead8),
      { s: 'sphere', p: [0, 0.4, -0.62], k: [0.28, 0.07, 0.15], c: 0xffffff }, B(0, 0.38, 0.3, 0.8, 0.1, 1.08, 0xb84a3a), B(0, 0.39, -0.24, 0.8, 0.11, 0.12, 0xe6d6b4)];
    case 'table': return [B(0, 0.66, 0, 1.8, 0.1, 0.82, WOOD), ...legs(0.8, 0.32, 0.62), C(0.45, 0.77, 0.1, 0.07, 0.13, 0xd8d0c0), { s: 'sphere', p: [-0.35, 0.73, -0.05], k: [0.16, 0.06, 0.16], c: 0x9a6a3a }, { s: 'sphere', p: [-0.35, 0.77, -0.05], k: [0.1, 0.05, 0.08], c: 0xe0a850 }];
    case 'chair': return [B(0, 0.4, 0.04, 0.48, 0.07, 0.48, WOOD), ...legs(0.2, 0.2, 0.38).map((p) => ({ ...p, p: [p.p[0], p.p[1], p.p[2] + 0.04] })), B(0, 0.7, -0.17, 0.48, 0.52, 0.06, WOOD_D), B(0, 0.45, 0.04, 0.4, 0.04, 0.4, 0xb84a3a)];
    case 'shelf': return [B(-0.41, 0.63, -0.2, 0.06, 1.26, 0.44, WOOD_D), B(0.41, 0.63, -0.2, 0.06, 1.26, 0.44, WOOD_D), B(0, 0.63, -0.41, 0.84, 1.26, 0.03, WOOD_DD), ...[0.06, 0.46, 0.86, 1.24].map((y) => B(0, y, -0.2, 0.82, 0.05, 0.44, WOOD)),
      B(-0.17, 0.22, -0.18, 0.3, 0.28, 0.3, 0xc08a50), C(0.2, 0.2, -0.2, 0.1, 0.24, 0x7ab0c0), { s: 'sphere', p: [0.16, 0.62, -0.2], k: [0.17, 0.14, 0.15], c: 0xd8c8a0 }, B(-0.18, 0.6, -0.2, 0.24, 0.24, 0.26, 0x9a6a3a),
      C(-0.2, 0.98, -0.2, 0.07, 0.2, 0xc86a3a), C(0.0, 0.97, -0.2, 0.06, 0.18, 0x6a9a4a), C(0.2, 0.99, -0.2, 0.07, 0.22, 0xd8b060)];
    case 'lamp': return [C(0, 0.05, 0, 0.2, 0.1, STONE), C(0, 0.62, 0, 0.045, 1.14, IRON), B(0.12, 1.16, 0, 0.3, 0.04, 0.04, IRON), C(0.25, 1.1, 0, 0.01, 0.1, IRON),
      B(0.25, 0.94, 0, 0.18, 0.22, 0.18, 0xffe08a), { s: 'cone', p: [0.25, 1.1, 0], k: [0.14, 0.1, 0.14], seg: 4, r: [0, Math.PI / 4, 0], c: IRON }, B(0.25, 0.82, 0, 0.2, 0.03, 0.2, IRON)];
    case 'hearth': return [B(0, 0.36, -0.05, 0.9, 0.72, 0.8, STONE), B(0, 0.75, -0.05, 0.98, 0.08, 0.88, 0x8a847c), B(0, 0.25, 0.34, 0.46, 0.36, 0.04, 0x2a2020), B(0, 0.12, 0.35, 0.36, 0.08, 0.04, 0xff8a3a),
      B(-0.15, 1.08, -0.22, 0.34, 0.62, 0.34, 0x948e84), { s: 'sphere', p: [0.22, 0.88, 0.12], k: [0.15, 0.12, 0.15], c: 0x3a3a44 }, C(0.22, 0.98, 0.12, 0.12, 0.03, 0x2a2a30)];
    case 'anvil': return [C(0, 0.18, 0, 0.3, 0.36, WOOD_D), B(0, 0.4, 0, 0.26, 0.1, 0.18, IRON), B(0, 0.5, 0, 0.52, 0.12, 0.24, IRON), { s: 'cone', p: [0.34, 0.51, 0], r: [0, 0, -Math.PI / 2], k: [0.08, 0.2, 0.08], c: 0x4a4a56 },
      B(-0.12, 0.58, 0.05, 0.3, 0.03, 0.03, WOOD), B(-0.25, 0.59, 0.05, 0.07, 0.06, 0.12, 0x5a5a66), C(0.32, 0.12, 0.3, 0.11, 0.24, 0x6a5030), C(0.32, 0.23, 0.3, 0.09, 0.02, 0x5aa0e0)];
    case 'herbtable': return [B(0, 0.62, 0, 1.8, 0.08, 0.8, WOOD), ...legs(0.8, 0.32, 0.58),
      ...[-0.6, -0.12, 0.36].flatMap((x, n) => [C(x, 0.74, -0.05, 0.1, 0.16, 0xb0603a), { s: 'cone', p: [x, 0.92, -0.05], k: [0.12, 0.24, 0.12], c: [0x5ad84a, 0x7ac84a, 0x4ab86a][n] }]),
      C(0.72, 0.72, 0.15, 0.1, 0.12, 0x9a948a), C(0.76, 0.8, 0.12, 0.02, 0.18, WOOD_D, [0, 0, 0.5]), B(-0.3, 0.68, 0.24, 0.5, 0.04, 0.2, 0x8ac060), C(0.5, 0.14, 0.1, 0.22, 0.28, 0xc8a060)];
    case 'leather': return [C(-0.82, 0.56, 0, 0.05, 1.12, WOOD_D), C(0.82, 0.56, 0, 0.05, 1.12, WOOD_D), C(0, 1.06, 0, 0.04, 1.72, WOOD, [0, 0, Math.PI / 2]), B(-0.36, 0.74, 0, 0.62, 0.58, 0.04, 0xc89a6a), B(0.38, 0.78, 0, 0.54, 0.5, 0.04, 0x9a6a4a),
      B(-0.82, 0.03, 0, 0.3, 0.06, 0.3, WOOD_DD), B(0.82, 0.03, 0, 0.3, 0.06, 0.3, WOOD_DD), B(0.3, 0.1, 0.28, 0.36, 0.2, 0.2, 0xb08050)];
    case 'bookshelf': {
      const out = [B(-0.88, 0.76, -0.18, 0.08, 1.52, 0.44, WOOD_D), B(0.88, 0.76, -0.18, 0.08, 1.52, 0.44, WOOD_D), B(0, 1.5, -0.18, 1.86, 0.06, 0.46, WOOD_D), B(0, 0.76, -0.39, 1.8, 1.52, 0.03, WOOD_DD), ...[0.05, 0.52, 0.99].map((y) => B(0, y, -0.18, 1.78, 0.05, 0.44, WOOD))];
      const COL = [0xa03a3a, 0x3a6aa0, 0x4a8a4a, 0xc8a050, 0x6a4a8a, 0xd8d0c0];
      [0.08, 0.55, 1.02].forEach((y0, r) => { for (let x = -0.78, n = 0; x < 0.8; n++) { const w = 0.09 + h01(r * 31 + n) * 0.06, h = 0.28 + h01(r * 17 + n * 3) * 0.14; if (h01(r * 7 + n * 11) > 0.12) out.push(B(x + w / 2, y0 + h / 2, -0.18, w - 0.01, h, 0.32, COL[(r * 5 + n * 3) % COL.length])); x += w; } });
      return out;
    }
    case 'decor': return [C(0, 0.08, 0, 0.3, 0.16, STONE), C(0, 0.22, 0, 0.035, 0.62, BONE, [0, 0.7, Math.PI / 2]), C(0, 0.22, 0, 0.035, 0.62, BONE, [0, -0.7, Math.PI / 2]),
      { s: 'sphere', p: [0, 0.36, 0], k: [0.16, 0.15, 0.17], c: BONE }, B(0, 0.25, 0.08, 0.16, 0.06, 0.1, BONE), B(-0.06, 0.37, 0.15, 0.06, 0.05, 0.04, 0x2a2020), B(0.06, 0.37, 0.15, 0.06, 0.05, 0.04, 0x2a2020)];
    case 'altar': return scaled([C(0, 0.1, 0, 0.85, 0.2, 0xb8b2a4), C(0, 0.3, 0, 0.62, 0.2, 0xc8c2b4), C(0, 0.75, 0, 0.2, 0.7, 0xd8d2c4), { s: 'sphere', p: [0, 1.12, 0], k: [0.32, 0.1, 0.32], c: 0xa89a8a }], 0.6);
    case 'gate': return scaled([B(-0.78, 0.9, 0, 0.34, 1.8, 0.4, 0xa8a294), B(0.78, 0.9, 0, 0.34, 1.8, 0.4, 0xa8a294), B(0, 1.9, 0, 2.0, 0.32, 0.46, 0x948e80), B(0, 2.12, 0, 0.3, 0.2, 0.5, 0xb45aff), B(-0.78, 0.08, 0, 0.46, 0.16, 0.5, 0x8a8476), B(0.78, 0.08, 0, 0.46, 0.16, 0.5, 0x8a8476)], 0.5);
    case 'heap': return [C(-0.05, 0.08, 0.12, 0.08, 0.72, 0x8a5a32, [0, 0.25, Math.PI / 2]), C(-0.05, 0.08, -0.05, 0.08, 0.72, 0x7a5030, [0, 0.25, Math.PI / 2]), C(-0.05, 0.22, 0.04, 0.08, 0.7, 0x9a6a3a, [0, 0.25, Math.PI / 2]),
      { s: 'ico', p: [0.3, 0.1, -0.28], k: [0.14, 0.11, 0.13], c: 0x9a968c }, { s: 'ico', p: [0.18, 0.08, -0.36], k: [0.1, 0.08, 0.1], c: 0x8a867c }, { s: 'sphere', p: [-0.28, 0.2, -0.3], k: [0.17, 0.2, 0.16], c: 0xd8c8a0 }, B(0.28, 0.14, 0.26, 0.26, 0.26, 0.26, 0xb08050)];
  }
  return [B(0, 0.3, 0, 0.8, 0.6, 0.8, WOOD)];
}

/* ---------- 덧붙이: 불빛 · 보석 · 문 원반 ---------- */
let _glow = null;
/** 부드러운 빛 무늬 (모든 불빛이 같이 쓴다) */
export function glowTex() {
  if (_glow) return _glow;
  const cv = document.createElement('canvas'); cv.width = cv.height = 64; const g = cv.getContext('2d'), gr = g.createRadialGradient(32, 32, 0, 32, 32, 32);
  gr.addColorStop(0, 'rgba(255,255,255,1)'); gr.addColorStop(0.25, 'rgba(255,255,255,0.55)'); gr.addColorStop(0.6, 'rgba(255,255,255,0.12)'); gr.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = gr; g.fillRect(0, 0, 64, 64); _glow = new THREE.CanvasTexture(cv); _glow.colorSpace = THREE.SRGBColorSpace; return _glow;
}
export function glowSprite(color, size, opacity = 0.8) {
  const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: glowTex(), color, blending: THREE.AdditiveBlending, transparent: true, depthWrite: false, opacity }));
  s.scale.setScalar(size); s.userData.size = size; s.userData.op = opacity; return s;
}
const GEM = new THREE.OctahedronGeometry(0.07, 0);
/** 가구 k의 덧붙이를 g(가구 묶음, 회전 전 좌표)에 넣고 애니메이션 목록을 돌려준다 */
export function furnExtras(k, g) {
  const a = {};
  if (k === 'lamp') { const s = glowSprite(0xffb050, 1.6, 0.75); s.position.set(0.25, 0.94, 0); g.add(s); a.glow = [s]; }
  else if (k === 'hearth') { const s = glowSprite(0xff7a2a, 0.9, 0.7); s.position.set(0, 0.2, 0.42); g.add(s); a.glow = [s]; }
  else if (k === 'altar') {
    a.gems = [0xff4a5a, 0xb45aff, 0x4ad86a].map((c, n) => { const m = new THREE.Mesh(GEM, new THREE.MeshBasicMaterial({ color: new THREE.Color(c).multiplyScalar(1.6), toneMapped: false })); m.userData.k = n; g.add(m); return m; });
    const s = glowSprite(0xb45aff, 1.3, 0.45); s.position.y = 0.85; g.add(s); a.glow = [s];
  } else if (k === 'gate') {
    const d = new THREE.Mesh(new THREE.CircleGeometry(0.3, 24), new THREE.MeshBasicMaterial({ color: new THREE.Color(0.7, 0.45, 1.6), transparent: true, opacity: 0.75, side: THREE.DoubleSide, toneMapped: false }));
    d.position.set(0, 0.48, 0); d.scale.set(1, 1.35, 1); g.add(d); a.disc = d;
  }
  return a;
}
/** 덧붙이 움직임 */
export function furnAnim(a, time, ph = 0) {
  if (a.glow) for (const s of a.glow) { const f = 1 + Math.sin(time * 3.1 + ph) * 0.05 + Math.sin(time * 7.7 + ph * 2) * 0.03; s.scale.setScalar(s.userData.size * f); s.material.opacity = s.userData.op * (0.9 + (f - 1) * 2); }
  if (a.gems) for (const m of a.gems) { const k = m.userData.k, an = time * 1.2 + k * 2.09; m.position.set(Math.cos(an) * 0.22, 0.86 + Math.sin(time * 2 + k) * 0.05, Math.sin(an) * 0.22); m.rotation.y = time * 2; }
  if (a.disc) a.disc.material.opacity = 0.6 + Math.sin(time * 3 + ph) * 0.15;
}
