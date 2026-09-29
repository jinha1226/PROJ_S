import * as THREE from 'three';
import { CameraRig } from './diorama/camera.js';
import { Labels, Particles, Transients } from './diorama/effects.js';
import { LightPool, dungeonLights, settlementLights } from './diorama/lights.js';
import { LOOK, SHARED } from './diorama/materials.js';
import { createPost } from './diorama/post.js';

/* ---------------- 조립 ---------------- */
export function createDiorama(container, o = {}) {
  const renderer = new THREE.WebGLRenderer({ antialias: false, powerPreference: 'high-performance', stencil: false });
  renderer.shadowMap.enabled = true; renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  renderer.toneMapping = THREE.ACESFilmicToneMapping; renderer.toneMappingExposure = o.exposure ?? 1.15;
  container.appendChild(renderer.domElement);
  const scene = new THREE.Scene(); scene.background = new THREE.Color(o.background ?? 0x05060b);
  const camera = new THREE.PerspectiveCamera(30, 1, 1, 140);
  const rig = new CameraRig(camera, renderer.domElement);
  let lights = (o.preset === 'settlement' ? settlementLights : dungeonLights)(scene);
  const pool = new LightPool(scene, 4);
  const sparks = new Particles(scene, 1000, THREE.AdditiveBlending);
  const puffs = new Particles(scene, 360, THREE.NormalBlending);
  const fx = new Transients(scene);
  const labels = new Labels(o.labelRoot || document.body, camera);
  const post = createPost(renderer, scene, camera);
  const raycaster = new THREE.Raycaster(), ground = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
  const fog = groundFog(); scene.add(fog);
  const dio = { THREE, renderer, scene, camera, rig, lights, preset: o.preset || 'dungeon', pool, sparks, puffs, fx, labels, post, onFrame: null, timeScale: 1, lightTarget: null, grid: null, pr: 1, _stop: 0 };
  dio.pr = Math.min(window.devicePixelRatio || 1, 2);
  function resize() {
    const w = container.clientWidth || innerWidth, h = container.clientHeight || innerHeight;
    renderer.setPixelRatio(dio.pr); renderer.setSize(w, h);
    camera.aspect = w / h; rig.fit(w / h); camera.setViewOffset(w, h, 0, rig.viewShiftY, w, h); camera.updateProjectionMatrix();
    post.setSize(w, h, dio.pr); labels.setSize(w, h);
    const s = h * dio.pr / (2 * Math.tan(camera.fov * Math.PI / 360));
    sparks.mat.uniforms.uScale.value = s; puffs.mat.uniforms.uScale.value = s;
  }
  addEventListener('resize', resize); resize();
  dio.resize = resize;
  /** 던전(칠흑·횃불) ↔ 정착지(황혼·모닥불) 전환. 조명·배경·후처리·안개만 바꾸고 나머지는 그대로 쓴다. */
  const LOOKS = {
    dungeon: { bg: 0x030305, exposure: 1.2, post: { vig: 0.62, grain: 0.022, blur: 0.6, sat: 0.84, shadowTint: 0x05070e }, fog: [0x1c2440, 0.2], shadow: 0.22 },
    settlement: { bg: 0x0a0d16, exposure: 1.15, post: { vig: 0.5, grain: 0.02, blur: 0.5, sat: 0.82, shadowTint: 0x060912 }, fog: [0x2a3452, 0.24], shadow: 0.26 },
  };
  const applyLook = (name) => { const L = LOOKS[name]; scene.background.set(L.bg); renderer.toneMappingExposure = L.exposure; post.setLook(L.post); fog.material.uniforms.uCol.value.set(L.fog[0]); fog.material.uniforms.uA.value = L.fog[1]; LOOK.uShadow.value = L.shadow; };
  applyLook(dio.preset);
  dio.setPreset = (name, opt = {}) => {
    if (name === dio.preset) return;
    for (const L of lights.objs) scene.remove(L);
    lights = dio.lights = (name === 'settlement' ? settlementLights : dungeonLights)(scene);
    dio.preset = name; applyLook(name);
    rig.tilesAcross = opt.tilesAcross ?? (name === 'settlement' ? 11.5 : 9.5);
    resize();
  };
  dio.hitstop = (ms) => { dio._stop = Math.max(dio._stop, ms / 1000); };
  dio.ray = (sx, sy) => { const r = renderer.domElement.getBoundingClientRect(); raycaster.setFromCamera(new THREE.Vector2(((sx - r.left) / r.width) * 2 - 1, -((sy - r.top) / r.height) * 2 + 1), camera); return raycaster; };
  dio.pickGround = (sx, sy) => { const hit = new THREE.Vector3(); if (!dio.ray(sx, sy).ray.intersectPlane(ground, hit)) return null; return { x: Math.round(hit.x), y: Math.round(hit.z) }; };
  let last = performance.now(), acc = 0, frames = 0;
  function frame(now) {
    requestAnimationFrame(frame);
    const dt = Math.min(0.05, Math.max(0, (now - last) / 1000)); last = now;
    let sdt = dt;
    if (dio._stop > 0) { dio._stop -= dt; sdt = dt * 0.05; }
    sdt *= dio.timeScale;
    SHARED.uTime.value += sdt;
    dio.onFrame?.(sdt, dt);
    rig.update(dt);
    dio.lights.update(sdt, dio.lightTarget || rig.focus);
    pool.update(sdt); sparks.update(sdt); puffs.update(sdt); fx.update(sdt); labels.update(dt);
    dio.grid?.update(sdt, SHARED.uTime.value, dio.lightTarget || rig.focus, camera.position);
    const s = labels.toScreen(dio.lightTarget || rig.focus); post.setFocus(1 - s.y / labels.H);
    fog.position.set(rig.focus.x, 0.14, rig.focus.z);
    motes(sdt, dio);
    post.render(SHARED.uTime.value);
    frames++; acc += dt;
    if (acc > 2.5) { const avg = acc / frames; if (avg > 0.024 && dio.pr > 1) { dio.pr = Math.max(1, dio.pr - 0.25); resize(); } acc = 0; frames = 0; }
  }
  requestAnimationFrame(frame);
  return dio;
}

/** 바닥에 낮게 깔리는 안개 — 천천히 흐르는 잡음 한 장 */
function groundFog() {
  const m = new THREE.ShaderMaterial({
    uniforms: { uTime: SHARED.uTime, uCol: { value: new THREE.Color(0x1a2238) }, uA: { value: 0.32 } },
    vertexShader: 'varying vec3 vW; void main(){ vec4 w = modelMatrix * vec4(position, 1.0); vW = w.xyz; gl_Position = projectionMatrix * viewMatrix * w; }',
    fragmentShader: `uniform float uTime; uniform vec3 uCol; uniform float uA; varying vec3 vW;
float h(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p){ vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f); return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
void main(){
  vec2 p = vW.xz * 0.35;
  float v = n(p + vec2(uTime * 0.05, uTime * 0.03)) * 0.6 + n(p * 2.3 - vec2(uTime * 0.08, 0.0)) * 0.4;
  gl_FragColor = vec4(uCol, uA * smoothstep(0.25, 0.85, v));
}`,
    transparent: true, depthWrite: false,
  });
  const f = new THREE.Mesh(new THREE.PlaneGeometry(60, 60).rotateX(-Math.PI / 2), m); f.renderOrder = 9; f.frustumCulled = false;
  return f;
}

/** 공중에 천천히 떠다니는 불씨와 먼지(개수 제한) */
let moteT = 0;
function motes(dt, dio) {
  moteT += dt; if (moteT < 0.12) return; moteT = 0;
  const f = dio.rig.focus, x = f.x + (Math.random() - 0.5) * 12, z = f.z + (Math.random() - 0.5) * 16;
  if (Math.random() < 0.55) dio.sparks.emit({ pos: new THREE.Vector3(x, 0.2 + Math.random() * 1.5, z), n: 1, color: 0xff8a3a, color2: 0xffc070, speed: 0.08, up: 0.25, grav: -0.05, life: 3.5, size: 0.045, spread: 0.2, drag: 0.2 });
  else dio.puffs.emit({ pos: new THREE.Vector3(x, 0.3 + Math.random() * 1.8, z), n: 1, color: 0x6a6a78, speed: 0.05, up: 0.05, grav: 0, life: 4, size: 0.035, drag: 0.1 });
}

// DioramaKit 전체를 한 이름공간으로 (import * as K from './render/diorama.js')
export * from './diorama/materials.js';
export * from './diorama/camera.js';
export * from './diorama/post.js';
export * from './diorama/lights.js';
export * from './diorama/effects.js';
export * from './diorama/grid.js';
export { SURF, CLOUD } from '../data/codes.js';
export { THREE };
