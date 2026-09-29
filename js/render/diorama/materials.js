import * as THREE from 'three';
import { mergeGeometries, mergeVertices } from 'three/addons/utils/BufferGeometryUtils.js';

export const SHARED = { uTime: { value: 0 } };

export const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

export const hash = (n) => { const s = Math.sin(n * 127.1 + 311.7) * 43758.5453; return s - Math.floor(s); };

export const _m4 = new THREE.Matrix4(), _q = new THREE.Quaternion(), _e = new THREE.Euler(), _v = new THREE.Vector3(), _s = new THREE.Vector3(), _c = new THREE.Color();

/* ---------------- 재질: 무광 툰 2단 + 디더링 그림자 경계 + 차가운 테두리광 ----------------
   그림자 경계는 BAYER 디더링으로 잉크로 판 듯하게. 광택은 gloss > 1(얼음·보석)에만 남긴다.
   desat: 채도를 낮춘다(의미 있는 색 — 불·영혼석·원소 — 은 0으로 둔다). rim: 인물의 푸른 윤곽광. */
export const GRADIENT = (() => {
  const t = new THREE.DataTexture(new Uint8Array([40, 40, 40, 255, 255, 255, 255, 255]), 2, 1);
  t.minFilter = t.magFilter = THREE.NearestFilter; t.generateMipmaps = false; t.needsUpdate = true; return t;
})();

export const BAYER = `float bayer4(vec2 p){ ivec2 q = ivec2(mod(floor(p), 4.0)); int k = q.x + q.y * 4;
  float m[16] = float[16](0.,8.,2.,10.,12.,4.,14.,6.,3.,11.,1.,9.,15.,7.,13.,5.); return (m[k] + 0.5) / 16.0; }`;

/** 전체 톤(던전·정착지 프리셋이 바꾼다) */
export const LOOK = { uShadow: { value: 0.14 }, uRimCol: { value: new THREE.Color(0.22, 0.36, 0.7) } };

export function toon(o = {}) {
  const { color = 0xffffff, gloss = 0, vertexColors = false, fade = false, sway = false,
    emissive = 0x000000, transparent = false, opacity = 1, desat = 0.3, rim = 0 } = o;
  const m = new THREE.MeshToonMaterial({ color, gradientMap: GRADIENT, vertexColors, emissive, transparent, opacity });
  m.userData.gloss = { value: gloss }; m.userData.desat = { value: desat }; m.userData.rim = { value: rim };
  m.onBeforeCompile = (sh) => {
    Object.assign(sh.uniforms, { uGloss: m.userData.gloss, uDesat: m.userData.desat, uRim: m.userData.rim, uTime: SHARED.uTime, uShadow: LOOK.uShadow, uRimCol: LOOK.uRimCol });
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
uniform float uGloss; uniform float uDesat; uniform float uRim; uniform float uShadow; uniform vec3 uRimCol;
${BAYER}
${fade ? 'varying float vFade;' : ''}`);
    // 2단 툰: 경계만 디더링
    fs = fs.replace('#include <gradientmap_pars_fragment>', `uniform sampler2D gradientMap;
vec3 getGradientIrradiance(vec3 normal, vec3 lightDirection) {
  float d = dot(normal, lightDirection) * 0.5 + 0.5;
  float b = bayer4(gl_FragCoord.xy) - 0.5;
  return vec3(mix(uShadow, 1.0, step(0.54 + b * 0.18, d)));
}`);
    if (fade) fs = fs.replace('void main() {', 'void main() {\n  if (vFade > 0.01 && bayer4(gl_FragCoord.xy) < vFade) discard;');
    fs = fs.replace('#include <color_fragment>', `#include <color_fragment>
diffuseColor.rgb = mix(diffuseColor.rgb, vec3(dot(diffuseColor.rgb, vec3(0.299, 0.587, 0.114))), uDesat);`);
    fs = fs.replace('#include <lights_fragment_end>', `#include <lights_fragment_end>
{
  vec3 Vd = normalize(vViewPosition);
  float rim = 1.0 - max(dot(normal, Vd), 0.0);
  totalEmissiveRadiance += uRim * uRimCol * smoothstep(0.55, 0.92, rim);
  if (uGloss > 1.0) {
    vec3 Lc = min(reflectedLight.directDiffuse / max(diffuseColor.rgb, vec3(0.12)), vec3(1.6));
    vec3 Hd = normalize(Vd + vec3(-0.3, 0.75, 0.2));
    float sp = pow(max(dot(normal, Hd), 0.0), 60.0);
    totalEmissiveRadiance += (uGloss - 1.0) * Lc * smoothstep(0.3, 0.45, sp) * 1.4;
  }
}`);
    sh.vertexShader = vs; sh.fragmentShader = fs;
  };
  m.customProgramCacheKey = () => `dk-toon2-${fade ? 1 : 0}${sway ? 1 : 0}`;
  return m;
}

export function outlineMaterial(o = {}) {
  const { width = 0.03, color = 0x07060a, fade = false } = o;
  return new THREE.ShaderMaterial({
    uniforms: { uW: { value: width }, uC: { value: new THREE.Color(color) } },
    vertexShader: `uniform float uW;
${fade ? 'attribute float aFade; varying float vFade;' : ''}
void main() {
  ${fade ? 'vFade = aFade;' : ''}
  // 손으로 그은 잉크: 점마다 굵기가 조금씩 다르다
  float jit = fract(sin(dot(floor(position * 9.0), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
  vec4 p = vec4(position + normal * uW * (0.7 + 0.6 * jit), 1.0);
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

export const OUTLINE = outlineMaterial({ width: 0.04 });

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
    default: g = new THREE.IcosahedronGeometry(1, p.detail ?? 0);
  }
  if (g.index) g = g.toNonIndexed();
  const k = p.k ?? 1, sc = typeof k === 'number' ? [k, k, k] : k;
  _e.set(...(p.r || [0, 0, 0])); _q.setFromEuler(_e);
  _m4.compose(_v.set(...(p.p || [0, 0, 0])), _q, _s.set(...sc));
  g.applyMatrix4(_m4);
  g.deleteAttribute('uv');
  const c = new THREE.Color(p.c ?? 0xffffff), n = g.getAttribute('position').count, arr = new Float32Array(n * 3);
  for (let i = 0; i < n; i++) { arr[i * 3] = c.r; arr[i * 3 + 1] = c.g; arr[i * 3 + 2] = c.b; }
  g.setAttribute('color', new THREE.BufferAttribute(arr, 3));
  return g;
}

/** 빛나는 부분(눈·원소 빛) 공용 재질: 조명을 받지 않고 톤매핑 밖에서 밝게 */
export const GLOW_MAT = new THREE.MeshBasicMaterial({ vertexColors: true, toneMapped: false, color: new THREE.Color(2.2, 2.2, 2.2) });

/** parts 중 glow: true 는 빛나는 메시로 따로(외곽선 없음) */
export function doll(parts, o = {}) {
  const lit = parts.filter((p) => !p.glow), glow = parts.filter((p) => p.glow);
  const geo = mergeGeometries(lit.map(partGeo));
  const mat = toon({ vertexColors: true, gloss: o.gloss ?? 0, desat: o.desat ?? 0.3, rim: o.rim ?? 0 });
  const mesh = new THREE.Mesh(geo, mat); mesh.castShadow = o.shadow !== false; mesh.receiveShadow = !!o.receive;
  const ol = new THREE.Mesh(outlineGeo(geo), o.outline || OUTLINE);
  const body = new THREE.Group(); body.add(mesh, ol); body.scale.setScalar(o.scale ?? 1);
  if (glow.length) { const gm = new THREE.Mesh(mergeGeometries(glow.map(partGeo)), GLOW_MAT); body.add(gm); }
  const pivot = new THREE.Group(); pivot.add(body);
  const root = new THREE.Group(); root.add(pivot);
  return { root, pivot, body, mesh, mat, ol, geo };
}
