import * as THREE from 'three';
import { CameraRig } from './diorama/camera.js';
import { Labels, Particles, Transients } from './diorama/effects.js';
import { LightPool, dungeonLights, settlementLights } from './diorama/lights.js';
import { SHARED } from './diorama/materials.js';
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
  /** 던전(어둡고 차가움) ↔ 정착지(낮, 따뜻함) 전환. 조명·배경·후처리만 바꾸고 나머지는 그대로 쓴다. */
  dio.setPreset = (name, opt = {}) => {
    if (name === dio.preset) return;
    for (const L of lights.objs) scene.remove(L);
    lights = dio.lights = (name === 'settlement' ? settlementLights : dungeonLights)(scene);
    dio.preset = name;
    const day = name === 'settlement';
    scene.background.set(opt.background ?? (day ? 0x6f9a5a : 0x05060b));
    renderer.toneMappingExposure = day ? 1.0 : 1.15;
    post.tv.uniforms.uVig.value = day ? 0.28 : 0.55;
    rig.tilesAcross = opt.tilesAcross ?? (day ? 11.5 : 9.5);
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
    post.render();
    frames++; acc += dt;
    if (acc > 2.5) { const avg = acc / frames; if (avg > 0.024 && dio.pr > 1) { dio.pr = Math.max(1, dio.pr - 0.25); resize(); } acc = 0; frames = 0; }
  }
  requestAnimationFrame(frame);
  return dio;
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
