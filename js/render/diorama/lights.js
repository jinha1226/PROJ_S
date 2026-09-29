import * as THREE from 'three';

/* ---------------- 조명 프리셋 ----------------
   던전: 거의 칠흑. 빛은 횃불(일렁임)과 원소뿐, 아주 약한 푸른 달빛이 윤곽만 남긴다.
   정착지: 영원한 황혼. 모닥불이 유일한 따뜻한 빛이고 그 반경은 모닥불 밝기가 정한다. */
export function dungeonLights(scene) {
  const hemi = new THREE.HemisphereLight(0x3a4a78, 0x0a0a12, 0.55);
  const moon = new THREE.DirectionalLight(0x5a70b0, 0.28); moon.position.set(-4, 10, 6);
  const torch = new THREE.SpotLight(0xff9a44, 62, 10, 1.25, 0.9, 2);
  torch.castShadow = true; torch.shadow.mapSize.set(1024, 1024); torch.shadow.bias = -0.0015; torch.shadow.normalBias = 0.03;
  torch.shadow.camera.near = 0.5; torch.shadow.camera.far = 16;
  scene.add(hemi, moon, torch, torch.target);
  let t = 0;
  return {
    hemi, moon, torch, boost: 1, base: 62, objs: [hemi, moon, torch, torch.target],
    update(dt, p) {
      t += dt;
      // 일렁임: 느린 숨 + 빠른 떨림 + 가끔 푹 꺼질 듯
      const f = 1 + Math.sin(t * 2.1) * 0.06 + Math.sin(t * 13) * 0.05 + Math.sin(t * 7.3 + 1) * 0.06 + Math.sin(t * 23.7) * 0.03 - Math.max(0, Math.sin(t * 0.7) - 0.93) * 3;
      this.boost += (1 - this.boost) * Math.min(1, dt * 3);
      torch.intensity = this.base * f * this.boost;
      torch.position.set(p.x + 0.3 + Math.sin(t * 5) * 0.04, 3.3, p.z + 0.45 + Math.cos(t * 4.3) * 0.03);
      torch.target.position.set(p.x, 0, p.z);
    },
  };
}

export function settlementLights(scene) {
  const hemi = new THREE.HemisphereLight(0x4a5a8a, 0x10101a, 0.95);
  const dusk = new THREE.DirectionalLight(0x7a88c0, 0.55); dusk.position.set(-6, 12, 8);
  // 모닥불: 위에서 내리비추는 스포트(그림자) + 주변을 데우는 점광원
  const fire = new THREE.SpotLight(0xff8a38, 60, 12, 1.35, 0.85, 1.6);
  fire.castShadow = true; fire.shadow.mapSize.set(1024, 1024); fire.shadow.bias = -0.0015; fire.shadow.normalBias = 0.03; fire.shadow.camera.near = 0.5; fire.shadow.camera.far = 20;
  const warm = new THREE.PointLight(0xff7a30, 8, 6, 1.4);
  scene.add(hemi, dusk, dusk.target, fire, fire.target, warm);
  let t = 0, g = 30, gT = 30, flare = 0;
  const src = new THREE.Vector3(5, 0, 7);
  return {
    hemi, fire, boost: 1, objs: [hemi, dusk, dusk.target, fire, fire.target, warm],
    /** 모닥불 밝기(0~100) → 빛 세기와 반경 */
    setGlow(v, snap) { gT = v; if (snap) g = v; },
    flare() { flare = 1; },
    get glow() { return g; },
    update(dt, p) {
      t += dt; g += (gT - g) * Math.min(1, dt * 0.8); flare = Math.max(0, flare - dt * 0.5);
      const k = g / 100, low = g <= 20, f = 1 + Math.sin(t * 9) * 0.05 + Math.sin(t * 15.3) * 0.04 + (low ? Math.sin(t * 5.1) * 0.22 + Math.sin(t * 11.7) * 0.12 : 0);
      fire.position.set(src.x, 3.6 + k * 1.2, src.z + 0.3); fire.target.position.set(src.x, 0, src.z);
      fire.distance = 6 + k * 12 + flare * 8; fire.angle = 0.9 + k * 0.55;
      fire.intensity = (40 + k * 90 + flare * 120) * f;
      warm.position.set(src.x, 0.9, src.z); warm.intensity = (3 + k * 9 + flare * 20) * f; warm.distance = 3 + k * 5;
      dusk.position.set(p.x - 7, 13, p.z + 6); dusk.target.position.set(p.x, 0, p.z);
    },
  };
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
