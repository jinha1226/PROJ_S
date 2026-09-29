import * as THREE from 'three';

/* ---------------- 조명 프리셋 ---------------- */
export function dungeonLights(scene) {
  const hemi = new THREE.HemisphereLight(0x5068b0, 0x121120, 0.6);
  const moon = new THREE.DirectionalLight(0x6f88d0, 0.45); moon.position.set(-4, 10, 6);
  const torch = new THREE.SpotLight(0xffa04c, 42, 10, 1.25, 0.9, 2);
  torch.castShadow = true; torch.shadow.mapSize.set(1024, 1024); torch.shadow.bias = -0.0015; torch.shadow.normalBias = 0.03;
  torch.shadow.camera.near = 0.5; torch.shadow.camera.far = 16;
  scene.add(hemi, moon, torch, torch.target);
  let t = 0;
  return {
    hemi, moon, torch, boost: 1, base: 42, objs: [hemi, moon, torch, torch.target],
    update(dt, p) {
      t += dt;
      const f = 1 + Math.sin(t * 13) * 0.035 + Math.sin(t * 7.3 + 1) * 0.05 + Math.sin(t * 23.7) * 0.025;
      this.boost += (1 - this.boost) * Math.min(1, dt * 3);
      torch.intensity = this.base * f * this.boost;
      torch.position.set(p.x + 0.3 + Math.sin(t * 5) * 0.02, 3.3, p.z + 0.45);
      torch.target.position.set(p.x, 0, p.z);
    },
  };
}

export function settlementLights(scene) {
  const hemi = new THREE.HemisphereLight(0xfff0d8, 0x7a6a50, 1.25);
  const sun = new THREE.DirectionalLight(0xffe6c0, 2.6); sun.position.set(-6, 12, 8);
  sun.castShadow = true; sun.shadow.mapSize.set(2048, 2048); sun.shadow.bias = -0.0008; sun.shadow.normalBias = 0.03; sun.shadow.radius = 3;
  Object.assign(sun.shadow.camera, { left: -11, right: 11, top: 11, bottom: -11, near: 1, far: 40 }); sun.shadow.camera.updateProjectionMatrix();
  scene.add(hemi, sun, sun.target);
  return { hemi, sun, boost: 1, objs: [hemi, sun, sun.target], update(dt, p) { sun.position.set(p.x - 7, 13, p.z + 6); sun.target.position.set(p.x, 0, p.z); } };
}

/* 이펙트용 점광원 풀 — 개수를 고정해 셰이더 재컴파일을 막는다 */
export class LightPool {
  constructor(scene, n = 4) {
    this.l = [];
    for (let i = 0; i < n; i++) { const L = new THREE.PointLight(0xffffff, 0, 6, 1.6); L.userData = { life: 0, max: 1, peak: 0 }; L.position.set(0, -50, 0); scene.add(L); this.l.push(L); }
  }
  flash(pos, color, peak = 30, life = 0.35, dist = 6) {
    const L = this.l.reduce((a, b) => (a.userData.life < b.userData.life ? a : b));
    L.position.set(pos.x, (pos.y ?? 0) + 0.9, pos.z); L.color.set(color); L.distance = dist;
    Object.assign(L.userData, { life, max: life, peak }); L.intensity = peak;
  }
  update(dt) {
    for (const L of this.l) {
      const u = L.userData; if (u.life <= 0) { L.intensity = 0; continue; }
      u.life -= dt; L.intensity = u.peak * Math.pow(Math.max(0, u.life / u.max), 1.4);
    }
  }
}
