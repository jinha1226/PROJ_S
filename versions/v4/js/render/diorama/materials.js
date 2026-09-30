import * as THREE from 'three';
import { mergeGeometries, mergeVertices } from 'three/addons/utils/BufferGeometryUtils.js';

export const SHARED = { uTime: { value: 0 } };

export const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

export const hash = (n) => { const s = Math.sin(n * 127.1 + 311.7) * 43758.5453; return s - Math.floor(s); };

export const _m4 = new THREE.Matrix4(), _q = new THREE.Quaternion(), _e = new THREE.Euler(), _v = new THREE.Vector3(), _s = new THREE.Vector3(), _c = new THREE.Color();

/* ---------------- 재질: 툰 3단 + 매끈한 플라스틱 하이라이트 ---------------- */
export const GRADIENT = (() => {
  const t = new THREE.DataTexture(new Uint8Array([70, 70, 70, 255, 160, 160, 160, 255, 255, 255, 255, 255]), 3, 1);
  t.minFilter = t.magFilter = THREE.NearestFilter; t.generateMipmaps = false; t.needsUpdate = true; return t;
})();

export const BAYER = `float bayer4(vec2 p){ ivec2 q = ivec2(mod(floor(p), 4.0)); int k = q.x + q.y * 4;
  float m[16] = float[16](0.,8.,2.,10.,12.,4.,14.,6.,3.,11.,1.,9.,15.,7.,13.,5.); return (m[k] + 0.5) / 16.0; }`;

export function toon(o = {}) {
  const { color = 0xffffff, gloss = 0.5, vertexColors = false, fade = false, sway = false,
    emissive = 0x000000, transparent = false, opacity = 1 } = o;
  const m = new THREE.MeshToonMaterial({ color, gradientMap: GRADIENT, vertexColors, emissive, transparent, opacity });
  m.userData.gloss = { value: gloss };
  m.onBeforeCompile = (sh) => {
    sh.uniforms.uGloss = m.userData.gloss; sh.uniforms.uTime = SHARED.uTime;
    let vs = sh.vertexShader, fs = sh.fragmentShader;
    vs = vs.replace('#include <common>', `#include <common>
uniform float uTime;
${fade ? 'attribute float aFade; varying float vFade;' : ''}`);
    let bv = '#include <begin_vertex>\n';
    if (fade) bv += 'vFade = aFade;\n';
    if (sway) bv += `
#ifdef USE_INSTANCING
float ph = instanceMatrix[3].x * 1.7 + instanceMatrix[3].z * 1.3;
#else
float ph = 0.0;
#endif
transformed.x += sin(uTime * 2.1 + ph) * 0.45 * position.y * position.y;
transformed.z += cos(uTime * 1.6 + ph * 1.3) * 0.32 * position.y * position.y;
`;
    vs = vs.replace('#include <begin_vertex>', bv);
    fs = fs.replace('#include <common>', `#include <common>
uniform float uGloss;
${fade ? 'varying float vFade;\n' + BAYER : ''}`);
    if (fade) fs = fs.replace('void main() {', 'void main() {\n  if (vFade > 0.01 && bayer4(gl_FragCoord.xy) < vFade) discard;');
    fs = fs.replace('#include <lights_fragment_end>', `#include <lights_fragment_end>
{
  vec3 Lc = min(reflectedLight.directDiffuse / max(diffuseColor.rgb, vec3(0.12)), vec3(1.6));
  vec3 Vd = normalize(vViewPosition);
  vec3 Hd = normalize(Vd + vec3(-0.3, 0.75, 0.2));
  float sp = pow(max(dot(normal, Hd), 0.0), 60.0);
  float rim = 1.0 - max(dot(normal, Vd), 0.0);
  totalEmissiveRadiance += uGloss * Lc * (smoothstep(0.3, 0.45, sp) * 1.6 + smoothstep(0.62, 0.95, rim) * 0.4);
}`);
    sh.vertexShader = vs; sh.fragmentShader = fs;
  };
  m.customProgramCacheKey = () => `dk-toon-${fade ? 1 : 0}${sway ? 1 : 0}`;
  return m;
}

export function outlineMaterial(o = {}) {
  const { width = 0.03, color = 0x120e18, fade = false } = o;
  return new THREE.ShaderMaterial({
    uniforms: { uW: { value: width }, uC: { value: new THREE.Color(color) } },
    vertexShader: `uniform float uW;
${fade ? 'attribute float aFade; varying float vFade;' : ''}
void main() {
  ${fade ? 'vFade = aFade;' : ''}
  vec4 p = vec4(position + normal * uW, 1.0);
  #ifdef USE_INSTANCING
  p = instanceMatrix * p;
  #endif
  gl_Position = projectionMatrix * modelViewMatrix * p;
}`,
    fragmentShader: `uniform vec3 uC;
${fade ? 'varying float vFade;\n' + BAYER : ''}
void main() {
  ${fade ? 'if (vFade > 0.01 && bayer4(gl_FragCoord.xy) < vFade) discard;' : ''}
  gl_FragColor = vec4(uC, 1.0);
}`,
    side: THREE.BackSide,
  });
}

export const OUTLINE = outlineMaterial({ width: 0.028 });

/** 외곽선용: 위치만 남겨 같은 점을 합치고 부드러운 법선을 만든다(모서리 틈 없음) */
export function outlineGeo(geo) {
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', geo.getAttribute('position').clone());
  if (geo.index) g.setIndex(geo.index.clone());
  const m = mergeVertices(g, 1e-3);
  m.computeVertexNormals();
  return m;
}

/* ---------------- 인형: 기본 도형을 합쳐 한 메시 + 외곽선 ---------------- */
/** 회전체: 단면 [반지름, 높이] 목록을 세로축으로 돌린다. wave = 아래쪽 옷 주름(n 갈래), phi = 일부만(망토) */
function latheGeo(p) {
  const g = new THREE.LatheGeometry(p.pts.map(([r, y]) => new THREE.Vector2(Math.max(0, r), y)), p.seg || 24, p.phi0 ?? 0, p.phiLen ?? Math.PI * 2);
  if (p.wave) {
    const pos = g.getAttribute('position'), top = p.waveTop ?? 9, bot = Math.min(...p.pts.map((q) => q[1]));
    for (let i = 0; i < pos.count; i++) {
      const x = pos.getX(i), y = pos.getY(i), z = pos.getZ(i); if (y >= top) continue;
      const k = 1 + p.wave * ((top - y) / Math.max(1e-4, top - bot)) * Math.sin((p.waveN || 7) * Math.atan2(x, z));
      pos.setXYZ(i, x * k, y, z * k);
    }
  }
  return g;
}
/** 굽은 관: path(점 목록)를 따라 반지름 r0 → r1로 가늘어진다. 끝은 둥글게 닫는다(팔·다리·소매) */
function tubeGeo(p) {
  const curve = new THREE.CatmullRomCurve3(p.path.map((v) => new THREE.Vector3(...v))), TS = p.ts || 10, RS = p.rs || 10;
  const g = new THREE.TubeGeometry(curve, TS, 1, RS, false), pos = g.getAttribute('position'), c = new THREE.Vector3(), v = new THREE.Vector3();
  for (let i = 0; i < pos.count; i++) {
    const t = Math.floor(i / (RS + 1)) / TS, r = p.r0 + (p.r1 - p.r0) * t; curve.getPointAt(Math.min(1, t), c);
    v.fromBufferAttribute(pos, i).sub(c).multiplyScalar(r).add(c); pos.setXYZ(i, v.x, v.y, v.z);
  }
  const caps = [[curve.getPointAt(0), p.r0], [curve.getPointAt(1), p.r1]].map(([q, r]) => new THREE.SphereGeometry(r, RS, 8).translate(q.x, q.y, q.z));
  const out = mergeGeometries([g.toNonIndexed(), ...caps.map((q) => q.toNonIndexed())].map((q) => { q.deleteAttribute('uv'); return q; }));
  return out;
}
export function partGeo(p) {
  let g;
  switch (p.s) {
    case 'sphere': g = new THREE.SphereGeometry(1, p.seg || 16, p.seg ? Math.max(6, (p.seg * 0.75) | 0) : 12); break;
    case 'box': g = new THREE.BoxGeometry(1, 1, 1); break;
    case 'cyl': g = new THREE.CylinderGeometry(p.top ?? 1, p.bot ?? 1, 1, p.seg || 12); break;
    case 'cone': g = new THREE.ConeGeometry(1, 1, p.seg || 12); break;
    case 'capsule': g = new THREE.CapsuleGeometry(0.5, p.len ?? 1, 4, 10); break;
    case 'torus': g = new THREE.TorusGeometry(1, p.tube ?? 0.2, 8, 18, p.arc ?? Math.PI * 2); break;
    case 'oct': g = new THREE.OctahedronGeometry(1, 0); break;
    case 'lathe': g = latheGeo(p); break;
    case 'tube': g = tubeGeo(p); break;
    default: g = new THREE.IcosahedronGeometry(1, p.detail ?? 0);
  }
  if (g.index) g = g.toNonIndexed();
  const k = p.k ?? 1, sc = typeof k === 'number' ? [k, k, k] : k;
  _e.set(...(p.r || [0, 0, 0])); _q.setFromEuler(_e);
  _m4.compose(_v.set(...(p.p || [0, 0, 0])), _q, _s.set(...sc));
  g.applyMatrix4(_m4);
  g.deleteAttribute('uv');
  const c = new THREE.Color(p.c ?? 0xffffff), pos = g.getAttribute('position'), n = pos.count, arr = new Float32Array(n * 3);
  let y0 = Infinity, y1 = -Infinity; if (p.shade) for (let i = 0; i < n; i++) { const y = pos.getY(i); y0 = Math.min(y0, y); y1 = Math.max(y1, y); }
  const pc = p.paint ? p.paint.map((q) => [q, new THREE.Color(q.c)]) : null, cx = p.p ? p.p[0] : 0, cz = p.p ? p.p[2] : 0;
  for (let i = 0; i < n; i++) {
    let col = c;
    // 칠하기: 몸통 둘레 각도(앞 = 0)와 높이로 옷깃·앞섶·줄무늬를 입힌다
    if (pc) { const x = pos.getX(i) - cx, y = pos.getY(i), z = pos.getZ(i) - cz, a = Math.atan2(x, z); for (const [q, qc] of pc) if (y >= (q.y0 ?? -9) && y <= (q.y1 ?? 9) && Math.abs(a) <= (q.vee ? q.a * (y - q.y0) / (q.y1 - q.y0) : q.a ?? 9) && (!q.band || Math.floor(y / q.band) % 2 === 0)) col = qc; }
    // 음영: 아래로 갈수록 조금 어둡게(바닥 쪽 그늘)
    const k2 = p.shade ? 1 - p.shade * (1 - (pos.getY(i) - y0) / Math.max(1e-4, y1 - y0)) : 1;
    arr[i * 3] = col.r * k2; arr[i * 3 + 1] = col.g * k2; arr[i * 3 + 2] = col.b * k2;
  }
  g.setAttribute('color', new THREE.BufferAttribute(arr, 3));
  return g;
}

export function doll(parts, o = {}) {
  const geo = mergeGeometries(parts.map(partGeo));
  const mat = toon({ vertexColors: true, gloss: o.gloss ?? 0.6 });
  const mesh = new THREE.Mesh(geo, mat); mesh.castShadow = o.shadow !== false; mesh.receiveShadow = !!o.receive;
  const silhouette = parts.filter((p) => p.outline !== false);
  const outlineSource = !silhouette.length || silhouette.length === parts.length ? geo : mergeGeometries(silhouette.map(partGeo));
  const ol = new THREE.Mesh(outlineGeo(outlineSource), o.outline || OUTLINE);
  if (outlineSource !== geo) outlineSource.dispose();
  const body = new THREE.Group(); body.add(mesh, ol); body.scale.setScalar(o.scale ?? 1);
  const pivot = new THREE.Group(); pivot.add(body);
  const root = new THREE.Group(); root.add(pivot);
  return { root, pivot, body, mesh, mat, ol, geo };
}
