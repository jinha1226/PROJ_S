import * as THREE from 'three';
import { G } from '../core/state.js';
import { BOSSES, MAGE } from '../data/enemies.js';
import { ITEMS } from '../data/items.js';
import { COLORS, STONE } from '../data/stones.js';
import { _w } from './common.js';
import * as K from './diorama.js';
import { heroSpec } from './hero-doll.js';
import { View } from './view.js';

export function dollSpec(e) {
  const sp = dollSpecBase(e);
  if (e.type === 'npc') return sp;
  if (e.boss) {
    sp.scale *= BOSSES[e.boss].scale;
    const top = e.type === 'mage' ? 1.5 : e.type === 'charger' ? 0.86 : 0.82, z = e.type === 'charger' ? 0.3 : 0;
    sp.parts = [...sp.parts, { s: 'cyl', p: [0, top, z], k: [0.17, 0.07, 0.17], c: 0x3e3834 }, ...[0, 1, 2, 3, 4, 5, 6].map((k) => ({ s: 'cone', p: [Math.cos(k * 0.8976) * 0.15, top + 0.1 + (k % 2) * 0.05, z + Math.sin(k * 0.8976) * 0.15], k: [0.03, 0.14 + (k % 2) * 0.08, 0.03], c: 0x4a4440 })), { s: 'oct', p: [0, top + 0.03, z + 0.17], k: 0.035, c: 0xff2a1a, glow: true }];
  }
  return sp;
}

export function dollSpecBase(e) {
  if (e.type === 'npc') {
    const cage = e.caged;
    return { h: 1.05, col: e.npcData.look.cloth, scale: 0.92, parts: npcParts(e.npcData),
      extra: (d) => {
        if (!cage) return {};
        const bars = [];
        for (let k = 0; k < 10; k++) { const a = k * Math.PI / 5; bars.push({ s: 'cyl', p: [Math.cos(a) * 0.42, 0.6, Math.sin(a) * 0.42], k: [0.025, 1.2, 0.025], c: 0x6a6a78 }); }
        bars.push({ s: 'cyl', p: [0, 1.22, 0], k: [0.47, 0.06, 0.47], c: 0x55555f }, { s: 'cyl', p: [0, 0.03, 0], k: [0.47, 0.06, 0.47], c: 0x55555f }, { s: 'sphere', p: [0, 1.3, 0], k: 0.07, c: 0x8a8a98 });
        const c = K.doll(bars, { gloss: 0.9 }); d.root.add(c.root); return { cage: c.root };
      } };
  }
  const feet = (c, s = 1) => [{ s: 'sphere', p: [-0.1 * s, 0.06, 0.03], k: [0.08 * s, 0.06, 0.11 * s], c }, { s: 'sphere', p: [0.1 * s, 0.06, 0.03], k: [0.08 * s, 0.06, 0.11 * s], c }];
  const glowEyes = (y, z, sp, c, k = 0.02) => [{ s: 'sphere', p: [-sp, y, z], k: [k, k * 0.8, k * 0.6], c, glow: true }, { s: 'sphere', p: [sp, y, z], k: [k, k * 0.8, k * 0.6], c, glow: true }];
  if (e.type === 'hero') return heroSpec(e.eq || G.eq, G.heroLook);
  if (e.type === 'goblin') {
    // 굶주려 뼈가 드러난 마른 몸, 굽은 등, 긴 손, 녹슨 칼을 끈다
    const skin = e.poison ? 0x5e6a4e : 0x6b7156, dark = e.poison ? 0x46503a : 0x4e533f, blade = e.poison ? 0x6aa04a : 0x6a5446;
    return {
      h: 0.95, col: skin, scale: 0.9,
      parts: [...feet(0x2e2820, 0.85),
        { s: 'cyl', p: [-0.08, 0.17, 0], k: [0.04, 0.24, 0.04], c: dark }, { s: 'cyl', p: [0.08, 0.17, 0], k: [0.04, 0.24, 0.04], c: dark },
        { s: 'sphere', p: [0, 0.29, 0], k: [0.14, 0.09, 0.12], c: 0x3a2e24 },
        { s: 'sphere', p: [0, 0.42, 0.02], r: [0.35, 0, 0], k: [0.15, 0.19, 0.12], c: skin },
        ...[0.36, 0.43, 0.5].map((y) => ({ s: 'torus', p: [0, y, 0.05], r: [Math.PI / 2 + 0.35, 0, 0], k: [0.13, 0.1, 0.1], tube: 0.08, arc: Math.PI, c: dark })),
        { s: 'sphere', p: [0, 0.56, 0.16], k: [0.19, 0.16, 0.17], c: skin },
        { s: 'cone', p: [-0.25, 0.6, 0.12], r: [0, 0, Math.PI / 2 + 0.3], k: [0.055, 0.24, 0.035], c: dark }, { s: 'cone', p: [0.25, 0.6, 0.12], r: [0, 0, -Math.PI / 2 - 0.3], k: [0.055, 0.24, 0.035], c: dark },
        { s: 'sphere', p: [-0.08, 0.53, 0.3], k: [0.04, 0.02, 0.02], c: 0x14100c }, { s: 'sphere', p: [0.08, 0.53, 0.3], k: [0.04, 0.02, 0.02], c: 0x14100c },
        ...glowEyes(0.58, 0.31, 0.075, e.poison ? 0xa8ff6a : 0xffd84a, 0.022),
        { s: 'box', p: [0, 0.48, 0.3], r: [0.2, 0, 0], k: [0.1, 0.018, 0.02], c: 0x1a0e0c }, { s: 'cone', p: [-0.03, 0.465, 0.31], r: [Math.PI, 0, 0], k: [0.012, 0.03, 0.012], c: 0xb8ad8a }, { s: 'cone', p: [0.04, 0.465, 0.31], r: [Math.PI, 0, 0], k: [0.012, 0.03, 0.012], c: 0xb8ad8a },
        // 긴 팔: 손이 무릎 아래까지
        { s: 'cyl', p: [-0.2, 0.33, 0.1], r: [0.2, 0, -0.18], k: [0.035, 0.34, 0.035], c: skin }, { s: 'cyl', p: [0.2, 0.33, 0.1], r: [0.2, 0, 0.18], k: [0.035, 0.34, 0.035], c: skin },
        { s: 'sphere', p: [-0.24, 0.16, 0.14], k: [0.055, 0.045, 0.06], c: dark }, { s: 'sphere', p: [0.24, 0.16, 0.14], k: [0.055, 0.045, 0.06], c: dark },
        { s: 'box', p: [0.27, 0.1, 0.32], r: [1.25, 0, 0], k: [0.035, 0.34, 0.08], c: blade }, { s: 'box', p: [0.27, 0.15, 0.2], r: [1.25, 0, 0], k: [0.08, 0.03, 0.03], c: 0x3a2e24 },
        ...(e.poison ? [{ s: 'sphere', p: [0.27, 0.06, 0.46], k: 0.025, c: 0x9dff6a, glow: true }] : []),
        // 갑옷 고블린: 몸에 안 맞는 찌그러진 판금
        ...(e.armor ? [{ s: 'sphere', p: [0.02, 0.66, 0.12], r: [0.25, 0, 0.3], k: [0.21, 0.12, 0.2], c: 0x5a5856 }, { s: 'box', p: [0.08, 0.72, 0.12], r: [0, 0, 0.35], k: [0.03, 0.08, 0.2], c: 0x4a4644 }, { s: 'box', p: [0, 0.44, 0.16], r: [0.4, 0.15, -0.12], k: [0.28, 0.22, 0.05], c: 0x5e5a56 }, { s: 'box', p: [-0.2, 0.52, 0.06], r: [0, 0, 0.5], k: [0.14, 0.06, 0.16], c: 0x4e4a46 }, { s: 'sphere', p: [0.2, 0.5, 0.05], k: [0.09, 0.05, 0.09], c: 0x6a4028 }] : [])],
    };
  }
  if (e.type === 'mage') {
    // 긴 두건 속은 완전히 어둡고 두 점의 빛만. 손끝에 원소 빛
    const M = MAGE[e.elem], robe = new THREE.Color(M.robe).multiplyScalar(0.45).getHex();
    return {
      h: 1.5, col: robe, scale: 1,
      parts: [
        { s: 'cone', p: [0, 0.36, 0], k: [0.3, 0.72, 0.3], c: robe },
        ...[0, 1, 2, 3, 4].map((k) => ({ s: 'box', p: [Math.cos(k * 1.26) * 0.25, 0.05, Math.sin(k * 1.26) * 0.25], r: [0, -k * 1.26, 0.1], k: [0.12, 0.1, 0.02], c: robe })),
        { s: 'sphere', p: [0, 0.72, 0], k: [0.2, 0.14, 0.18], c: robe },
        { s: 'sphere', p: [0, 0.86, 0.04], k: [0.17, 0.17, 0.14], c: 0x050406 },
        { s: 'cone', p: [0, 1.08, -0.06], r: [-0.25, 0, 0], k: [0.24, 0.62, 0.24], c: robe },
        { s: 'torus', p: [0, 0.86, 0.1], k: [0.18, 0.2, 0.12], tube: 0.2, c: robe },
        ...glowEyes(0.87, 0.19, 0.055, M.color, 0.024),
        { s: 'cyl', p: [-0.24, 0.5, 0.1], r: [0.3, 0, -0.25], k: [0.03, 0.26, 0.03], c: 0xb3a98a }, { s: 'sphere', p: [-0.27, 0.38, 0.14], k: 0.04, c: 0xb3a98a },
        { s: 'sphere', p: [0.28, 0.46, 0.08], k: 0.045, c: 0xb3a98a },
        { s: 'cyl', p: [0.3, 0.58, 0.08], k: [0.022, 1.0, 0.022], c: 0x2e2218 }, { s: 'torus', p: [0.3, 1.07, 0.08], r: [Math.PI / 2, 0, 0], k: 0.07, tube: 0.25, c: 0x3a3028 }],
      extra: (d) => {
        const orb = new THREE.Mesh(new THREE.SphereGeometry(0.08, 14, 10), new THREE.MeshBasicMaterial({ color: new THREE.Color(M.color).multiplyScalar(2.4), toneMapped: false }));
        orb.position.set(0.3, 1.14, 0.08); d.body.add(orb);
        return { update(dt, t, ev) { const c = ev.casting; orb.scale.setScalar(1 + Math.sin(t * 5) * 0.08 + (c ? 0.7 + Math.sin(t * 22) * 0.25 : 0)); if (Math.random() < dt * (c ? 30 : 3)) { orb.getWorldPosition(_w); View.dio.sparks.emit({ pos: _w, n: 1, color: M.color, color2: 0xffffff, speed: c ? 1 : 0.2, up: 0.3, grav: 0, life: 0.5, size: 0.08 }); } } };
      },
    };
  }
  if (e.type === 'charger') return {
    // 뿔 달린 거대한 짐승, 쇠사슬과 가시 박힌 갑주
    h: 1.25, col: 0x3a2e28, scale: 1.18,
    parts: [
      ...[[-0.2, 0.15], [0.2, 0.15], [-0.2, -0.24], [0.2, -0.24]].map(([x, z]) => ({ s: 'cyl', p: [x, 0.12, z], k: [0.09, 0.24, 0.09], c: 0x221a16 })),
      { s: 'sphere', p: [0, 0.44, -0.06], k: [0.36, 0.32, 0.46], c: 0x3a2e28 },
      { s: 'box', p: [0, 0.66, -0.14], r: [0.12, 0, 0], k: [0.46, 0.1, 0.46], c: 0x46464c },
      ...[[-0.16, -0.32], [0.16, -0.32], [0, -0.12], [-0.16, 0.05], [0.16, 0.05]].map(([x, z]) => ({ s: 'cone', p: [x, 0.8, z], k: [0.045, 0.16, 0.045], c: 0x5a5a60 })),
      ...[-0.02, 0.2].map((z) => ({ s: 'torus', p: [0, 0.44, z], r: [0, 0, 0], k: [0.37, 0.33, 0.33], tube: 0.05, c: 0x4a4a50 })),
      { s: 'sphere', p: [0, 0.46, 0.36], k: [0.24, 0.22, 0.22], c: 0x2e2420 },
      { s: 'cyl', p: [0, 0.4, 0.54], r: [Math.PI / 2, 0, 0], k: [0.1, 0.09, 0.08], c: 0x4a3a34 },
      // 뿔: 크게 휘어 앞으로
      { s: 'cone', p: [-0.22, 0.62, 0.42], r: [0.9, 0, 0.9], k: [0.06, 0.34, 0.06], c: 0xb8ad90 }, { s: 'cone', p: [0.22, 0.62, 0.42], r: [0.9, 0, -0.9], k: [0.06, 0.34, 0.06], c: 0xb8ad90 },
      { s: 'cone', p: [-0.34, 0.74, 0.62], r: [1.5, 0, 0.4], k: [0.04, 0.2, 0.04], c: 0xa89c80 }, { s: 'cone', p: [0.34, 0.74, 0.62], r: [1.5, 0, -0.4], k: [0.04, 0.2, 0.04], c: 0xa89c80 },
      { s: 'cone', p: [-0.1, 0.38, 0.56], r: [-0.4, 0, 0.35], k: [0.03, 0.13, 0.03], c: 0xb8ad90 }, { s: 'cone', p: [0.1, 0.38, 0.56], r: [-0.4, 0, -0.35], k: [0.03, 0.13, 0.03], c: 0xb8ad90 },
      ...glowEyes(0.54, 0.52, 0.11, 0xff4020, 0.025),
      { s: 'box', p: [0, 0.3, 0.2], r: [0.3, 0, 0], k: [0.05, 0.25, 0.03], c: 0x4a4a50 }],
  };
  // 해골 궁수: 금 가고 이가 빠진 뼈, 너덜너덜한 천, 눈구멍의 희미한 불빛
  const bone = 0xb3a98a, boneD = 0x8a8068;
  return {
    h: 1.1, col: bone, scale: 0.95,
    parts: [...feet(boneD, 0.8),
      { s: 'cyl', p: [-0.08, 0.2, 0], k: [0.03, 0.3, 0.03], c: bone }, { s: 'cyl', p: [0.08, 0.2, 0], k: [0.03, 0.3, 0.03], c: bone },
      { s: 'sphere', p: [0, 0.34, 0], k: [0.13, 0.06, 0.1], c: boneD },
      { s: 'cyl', p: [0, 0.45, -0.03], k: [0.03, 0.24, 0.03], c: boneD },
      ...[0.44, 0.51, 0.58].map((y, k) => ({ s: 'torus', p: [0, y, 0], r: [Math.PI / 2, 0, 0], k: [0.15 - k * 0.01, 0.12, 0.11], tube: 0.1, c: bone })),
      ...[0, 1, 2, 3].map((k) => ({ s: 'box', p: [-0.12 + k * 0.08, 0.36 - (k % 2) * 0.05, 0.1], r: [0.1, 0, (k - 1.5) * 0.1], k: [0.06, 0.2 + (k % 2) * 0.08, 0.015], c: 0x2a2624 })),
      { s: 'box', p: [0, 0.52, -0.13], r: [0.2, 0, 0], k: [0.3, 0.3, 0.02], c: 0x2e2a26 },
      { s: 'sphere', p: [0, 0.78, 0.01], k: [0.19, 0.18, 0.18], c: bone },
      { s: 'box', p: [0, 0.66, 0.1], k: [0.15, 0.06, 0.1], c: bone },
      { s: 'sphere', p: [-0.07, 0.78, 0.15], k: [0.05, 0.05, 0.03], c: 0x0a0806 }, { s: 'sphere', p: [0.07, 0.78, 0.15], k: [0.05, 0.05, 0.03], c: 0x0a0806 },
      ...glowEyes(0.78, 0.165, 0.07, 0x7a9ad8, 0.016),
      ...[-0.05, -0.02, 0.04].map((x) => ({ s: 'box', p: [x, 0.64, 0.155], k: [0.018, 0.025, 0.01], c: 0xd8cca8 })),
      { s: 'box', p: [0.05, 0.86, 0.12], r: [0, 0, 0.5], k: [0.012, 0.1, 0.01], c: 0x2a2420 },
      { s: 'sphere', p: [-0.24, 0.44, 0.12], k: 0.04, c: bone }, { s: 'sphere', p: [0.22, 0.36, 0.06], k: 0.04, c: bone },
      { s: 'cyl', p: [-0.2, 0.52, 0.08], r: [0, 0, -0.35], k: [0.022, 0.2, 0.022], c: bone }, { s: 'cyl', p: [0.2, 0.46, 0.04], r: [0, 0, 0.35], k: [0.022, 0.2, 0.022], c: bone },
      { s: 'torus', p: [-0.27, 0.44, 0.12], r: [0, -Math.PI / 2, -Math.PI / 2], k: 0.3, tube: 0.07, arc: Math.PI, c: 0x3a2e22 },
      { s: 'cyl', p: [-0.27, 0.44, 0.12], k: [0.006, 0.58, 0.006], c: 0x8a8070 },
      { s: 'cyl', p: [0.12, 0.52, -0.18], r: [0.3, 0, -0.3], k: [0.06, 0.3, 0.06], c: 0x3a2a1e }],
  };
}

export function propDoll(parts, scale = 1.15) { return K.doll(parts, { scale, gloss: 0.5, shadow: true }); }

export function itemDoll(k) {
  const cat = ITEMS[k].cat, c = G.look[k].color;
  if (cat === 'potion') return propDoll([{ s: 'sphere', p: [0, 0.14, 0], k: 0.13, c }, { s: 'cyl', p: [0, 0.29, 0], k: [0.05, 0.1, 0.05], c: 0xdfe8f0 }, { s: 'cyl', p: [0, 0.36, 0], k: [0.055, 0.05, 0.055], c: 0x9a6a3a }, { s: 'sphere', p: [-0.05, 0.19, 0.09], k: 0.03, c: 0xffffff }]);
  if (cat === 'scroll') return propDoll([{ s: 'cyl', p: [0, 0.09, 0], r: [0, 0, Math.PI / 2], k: [0.08, 0.34, 0.08], c }, { s: 'cyl', p: [0, 0.09, 0], r: [0, 0, Math.PI / 2], k: [0.085, 0.06, 0.085], c: 0xd0343a }, { s: 'sphere', p: [0.19, 0.09, 0], k: 0.035, c: 0x7a4a28 }, { s: 'sphere', p: [-0.19, 0.09, 0], k: 0.035, c: 0x7a4a28 }]);
  return propDoll([{ s: 'sphere', p: [0, 0.14, 0], k: [0.14, 0.15, 0.14], c }, { s: 'cyl', p: [0, 0.3, 0], k: [0.06, 0.06, 0.06], c: 0x7a5a3a }, { s: 'torus', p: [0, 0.22, 0], r: [Math.PI / 2, 0, 0], k: 0.1, tube: 0.18, c: 0xd8c8a0 }]);
}

/* ---------- 영혼석 · 무기 오브젝트 ---------- */
export const _texCache = {};

export function badgeTex(id) {
  if (_texCache[id]) return _texCache[id];
  const def = STONE[id], c = document.createElement('canvas'); c.width = c.height = 128; const g = c.getContext('2d');
  g.beginPath(); g.arc(64, 64, 58, 0, Math.PI * 2); g.fillStyle = '#000'; g.fill();
  g.beginPath(); g.arc(64, 64, 52, 0, Math.PI * 2); g.fillStyle = COLORS[def.color].css; g.fill();
  g.beginPath(); g.arc(64, 64, 40, 0, Math.PI * 2); g.fillStyle = '#1c1628'; g.fill();
  g.fillStyle = 'rgba(255,255,255,.35)'; g.beginPath(); g.ellipse(48, 40, 16, 8, -0.6, 0, Math.PI * 2); g.fill();
  g.font = '44px "Apple Color Emoji","Segoe UI Emoji","Noto Color Emoji",sans-serif'; g.textAlign = 'center'; g.textBaseline = 'middle'; g.fillStyle = '#fff';
  g.fillText(def.icon, 64, 68);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return (_texCache[id] = t);
}

export const GLOW_TEX = (() => { const c = document.createElement('canvas'); c.width = c.height = 64; const g = c.getContext('2d'); const gr = g.createRadialGradient(32, 32, 0, 32, 32, 32); gr.addColorStop(0, 'rgba(255,255,255,1)'); gr.addColorStop(0.4, 'rgba(255,255,255,.35)'); gr.addColorStop(1, 'rgba(255,255,255,0)'); g.fillStyle = gr; g.fillRect(0, 0, 64, 64); return new THREE.CanvasTexture(c); })();

export function makeGem(id) {
  const col = COLORS[STONE[id].color], g = new THREE.Group();
  const crystal = K.doll([{ s: 'oct', k: [0.19, 0.28, 0.19], c: col.hex }, { s: 'oct', p: [-0.03, 0.04, 0.09], k: [0.07, 0.1, 0.04], c: 0xffffff }], { gloss: 1.5 });
  crystal.root.position.y = 0.3;
  const glow = new THREE.Sprite(new THREE.SpriteMaterial({ map: GLOW_TEX, color: col.hex, blending: THREE.AdditiveBlending, transparent: true, depthWrite: false, toneMapped: false }));
  glow.scale.setScalar(1.5); glow.position.y = 0.32;
  const badge = new THREE.Sprite(new THREE.SpriteMaterial({ map: badgeTex(id), transparent: true, depthWrite: false, toneMapped: false }));
  badge.scale.setScalar(0.62); badge.position.y = 0.95;
  g.add(crystal.root, glow, badge);
  g.userData = { crystal: crystal.root, glow, badge, ph: Math.random() * 6 };
  return g;
}

export const WEAPON_PARTS = {
  sword: [{ s: 'box', p: [0, 0.3, 0], k: [0.065, 0.48, 0.02], c: 0xe4ecf6 }, { s: 'box', p: [0, 0.06, 0], k: [0.22, 0.045, 0.05], c: 0xd4a840 }, { s: 'cyl', p: [0, -0.03, 0], k: [0.025, 0.12, 0.025], c: 0x5a3a22 }],
  axe: [{ s: 'cyl', p: [0, 0.2, 0], k: [0.026, 0.54, 0.026], c: 0x7a4a28 }, { s: 'box', p: [0.08, 0.4, 0], k: [0.18, 0.15, 0.03], c: 0xcfd6e2 }],
  mace: [{ s: 'cyl', p: [0, 0.16, 0], k: [0.026, 0.42, 0.026], c: 0x5a3a22 }, { s: 'sphere', p: [0, 0.4, 0], k: 0.095, c: 0x9aa2b4 }, { s: 'cone', p: [0.1, 0.4, 0], r: [0, 0, -Math.PI / 2], k: [0.03, 0.07, 0.03], c: 0xdfe4ee }, { s: 'cone', p: [-0.1, 0.4, 0], r: [0, 0, Math.PI / 2], k: [0.03, 0.07, 0.03], c: 0xdfe4ee }, { s: 'cone', p: [0, 0.5, 0], k: [0.03, 0.07, 0.03], c: 0xdfe4ee }],
  hammer: [{ s: 'cyl', p: [0, 0.2, 0], k: [0.028, 0.54, 0.028], c: 0x6a4526 }, { s: 'box', p: [0, 0.46, 0], k: [0.26, 0.13, 0.13], c: 0x8a92a4 }],
  dagger: [{ s: 'box', p: [0, 0.17, 0], k: [0.05, 0.25, 0.015], c: 0xeef2f8 }, { s: 'box', p: [0, 0.04, 0], k: [0.14, 0.035, 0.04], c: 0x8a6a3a }, { s: 'cyl', p: [0, -0.03, 0], k: [0.022, 0.09, 0.022], c: 0x3a2618 }],
  spear: [{ s: 'cyl', p: [0, 0.3, 0], k: [0.02, 0.86, 0.02], c: 0x8a5a32 }, { s: 'cone', p: [0, 0.8, 0], k: [0.045, 0.16, 0.045], c: 0xe4ecf6 }],
};

export function matProp(m) {
  const P = {
    가죽: [{ s: 'box', p: [0, 0.06, 0], r: [0, 0.4, 0.1], k: [0.34, 0.06, 0.26], c: 0xa0643a }],
    뼈: [{ s: 'cyl', p: [0, 0.07, 0], r: [0, 0, Math.PI / 2], k: [0.04, 0.34, 0.04], c: 0xf2ead8 }, { s: 'sphere', p: [0.17, 0.07, 0], k: 0.06, c: 0xf2ead8 }, { s: 'sphere', p: [-0.17, 0.07, 0], k: 0.06, c: 0xf2ead8 }],
    심장: [{ s: 'sphere', p: [0, 0.1, 0], k: [0.12, 0.13, 0.1], c: 0xd02a4a }],
    약초: [0, 1, 2, 3].map((k) => ({ s: 'cone', p: [Math.cos(k * 1.57) * 0.07, 0.14, Math.sin(k * 1.57) * 0.07], r: [Math.sin(k * 1.57) * 0.4, 0, -Math.cos(k * 1.57) * 0.4], k: [0.06, 0.28, 0.03], c: 0x5ad84a })).concat([{ s: 'sphere', p: [0, 0.28, 0], k: 0.05, c: 0xff7ab0 }]),
    광석: [{ s: 'ico', p: [0, 0.12, 0], k: [0.2, 0.14, 0.17], c: 0x7a7a88 }, { s: 'oct', p: [0.07, 0.2, 0.05], k: 0.06, c: 0x7fe0ff }, { s: 'oct', p: [-0.08, 0.18, -0.02], k: 0.05, c: 0xffd84a }],
    기름: [{ s: 'sphere', p: [0, 0.12, 0], k: [0.15, 0.12, 0.15], c: 0x3a3440 }, { s: 'cyl', p: [0, 0.25, 0], k: [0.04, 0.06, 0.04], c: 0x8a6a3a }],
    얼음: [{ s: 'oct', p: [0, 0.18, 0], k: [0.11, 0.2, 0.11], c: 0xbfeaff }, { s: 'oct', p: [0.1, 0.1, 0.04], k: [0.06, 0.1, 0.06], c: 0xdff6ff }],
    마석: [{ s: 'oct', p: [0, 0.2, 0], k: [0.13, 0.2, 0.13], c: 0xb45aff }],
    기록: [{ s: 'box', p: [0, 0.05, 0], r: [0, 0.3, 0], k: [0.3, 0.03, 0.38], c: 0xd8c8a0 }, { s: 'cyl', p: [0, 0.07, -0.19], r: [0, 0, Math.PI / 2], k: [0.04, 0.34, 0.04], c: 0xb8a878 }, { s: 'sphere', p: [0.06, 0.08, 0.08], k: [0.05, 0.02, 0.05], c: 0x8a2a2a }],
  };
  return K.doll(P[m] || P.광석, { gloss: 1.3 }).root;
}

export const weaponDoll = (id) => K.doll(WEAPON_PARTS[id.replace('+', '')], { gloss: id.endsWith('+') ? 1.8 : 1.1 });

/* ---------- 정착지 인형 · 건물 ---------- */
/** 정착지 주민: 두건과 누더기, 직업 도구. 얼굴은 드러나지만 눈매가 지치고 볼이 패였다 */
export function npcParts(n) {
  const L = n.look, S = new THREE.Color(L.skin).multiplyScalar(0.78).getHex(), Sd = new THREE.Color(L.skin).multiplyScalar(0.55).getHex(), Hc = new THREE.Color(L.hair).multiplyScalar(0.7).getHex(), C = L.cloth, eye = 0x0e0a0a;
  const P = [
    { s: 'sphere', p: [-0.09, 0.06, 0.03], k: [0.08, 0.06, 0.11], c: 0x2a2018 }, { s: 'sphere', p: [0.09, 0.06, 0.03], k: [0.08, 0.06, 0.11], c: 0x2a2018 },
    { s: 'cone', p: [0, 0.3, 0], k: [0.25, 0.56, 0.23], c: C },
    ...[0, 1, 2, 3].map((k) => ({ s: 'box', p: [Math.cos(k * 1.57 + 0.4) * 0.21, 0.04, Math.sin(k * 1.57 + 0.4) * 0.19], r: [0, -k * 1.57, 0.12], k: [0.11, 0.08, 0.02], c: C })),
    { s: 'sphere', p: [0, 0.5, 0], k: [0.2, 0.12, 0.17], c: C },
    { s: 'sphere', p: [0, 0.72, 0.02], k: [0.2, 0.21, 0.19], c: S },
    { s: 'sphere', p: [-0.1, 0.67, 0.13], k: [0.05, 0.035, 0.03], c: Sd }, { s: 'sphere', p: [0.1, 0.67, 0.13], k: [0.05, 0.035, 0.03], c: Sd },
    { s: 'sphere', p: [-0.065, 0.735, 0.185], k: [0.03, 0.018, 0.012], c: eye }, { s: 'sphere', p: [0.065, 0.735, 0.185], k: [0.03, 0.018, 0.012], c: eye },
    { s: 'sphere', p: [-0.065, 0.712, 0.182], k: [0.03, 0.012, 0.01], c: Sd }, { s: 'sphere', p: [0.065, 0.712, 0.182], k: [0.03, 0.012, 0.01], c: Sd },
    { s: 'box', p: [0, 0.65, 0.19], k: [0.05, 0.008, 0.01], c: 0x2a1a16 },
    { s: 'sphere', p: [0, 0.77, -0.05], k: [0.21, 0.18, 0.2], c: Hc },
    { s: 'sphere', p: [-0.22, 0.42, 0.06], k: 0.055, c: S }, { s: 'sphere', p: [0.22, 0.42, 0.06], k: 0.055, c: S },
  ];
  const hood = (c) => [{ s: 'sphere', p: [0, 0.79, -0.03], k: [0.24, 0.24, 0.23], c }, { s: 'torus', p: [0, 0.74, 0.1], k: [0.19, 0.19, 0.12], tube: 0.2, c }, { s: 'box', p: [0.04, 0.62, -0.16], r: [0.2, 0, 0.1], k: [0.3, 0.2, 0.03], c }];
  switch (n.job) {
    case 'blacksmith': P.push({ s: 'box', p: [0, 0.3, 0.17], k: [0.28, 0.32, 0.05], c: 0x3a2618 }, { s: 'cyl', p: [0.26, 0.4, 0.08], k: [0.02, 0.3, 0.02], c: 0x3a2818 }, { s: 'box', p: [0.26, 0.56, 0.08], k: [0.13, 0.07, 0.07], c: 0x4a4644 }, { s: 'sphere', p: [0, 0.6, 0.15], k: [0.13, 0.08, 0.07], c: Hc }); break;
    case 'herbalist': P.push(...hood(0x3e4a34), { s: 'cyl', p: [-0.27, 0.3, 0.06], k: [0.1, 0.1, 0.1], c: 0x5a4630 }, { s: 'sphere', p: [-0.27, 0.36, 0.06], k: [0.08, 0.04, 0.08], c: 0x4a6a3a }); break;
    case 'hunter': P.push(...hood(0x4a3a28), { s: 'torus', p: [0, 0.4, -0.2], r: [0, 0, Math.PI / 2], k: 0.26, tube: 0.06, arc: Math.PI, c: 0x3a2818 }, { s: 'box', p: [0.14, 0.36, -0.18], r: [0.3, 0, 0], k: [0.06, 0.28, 0.06], c: 0x4a3a2a }); break;
    case 'scholar': P.push(...hood(0x34324a), { s: 'torus', p: [-0.065, 0.735, 0.2], k: 0.045, tube: 0.18, c: 0x1a1a1a }, { s: 'torus', p: [0.065, 0.735, 0.2], k: 0.045, tube: 0.18, c: 0x1a1a1a }, { s: 'cyl', p: [-0.24, 0.4, 0.12], r: [0, 0, Math.PI / 2], k: [0.05, 0.22, 0.05], c: 0xb8a878 }); break;
    case 'cook': P.push({ s: 'cyl', p: [0, 0.94, -0.02], k: [0.17, 0.12, 0.17], c: 0x8a8274 }, { s: 'box', p: [0, 0.3, 0.17], k: [0.26, 0.3, 0.04], c: 0x7a7266 }, { s: 'cyl', p: [0.26, 0.45, 0.1], k: [0.015, 0.34, 0.015], c: 0x4a3a2a }, { s: 'sphere', p: [0.26, 0.28, 0.1], k: [0.05, 0.03, 0.05], c: 0x3a3230 }); break;
    case 'fisher': P.push(...hood(0x34424e), { s: 'cyl', p: [0.24, 0.62, 0.06], r: [0.2, 0, -0.35], k: [0.012, 0.9, 0.012], c: 0x4a3a2a }, { s: 'sphere', p: [-0.2, 0.25, -0.1], k: [0.13, 0.12, 0.1], c: 0x5a5448 }); break;
    case 'boatman': P.push({ s: 'cyl', p: [0, 0.9, -0.02], k: [0.3, 0.02, 0.3], c: 0x3a3228 }, { s: 'sphere', p: [0, 0.92, -0.02], k: [0.17, 0.1, 0.17], c: 0x3a3228 }, { s: 'cyl', p: [0.26, 0.55, 0.06], k: [0.02, 1.0, 0.02], c: 0x4a3a2a }, { s: 'box', p: [0.26, 0.1, 0.06], k: [0.1, 0.2, 0.02], c: 0x4a3a2a }); break;
    case 'gravekeeper': P.push(...hood(0x2a2a30), { s: 'cyl', p: [0.26, 0.45, 0.06], r: [0, 0, 0.1], k: [0.018, 0.7, 0.018], c: 0x3a2e24 }, { s: 'box', p: [0.29, 0.1, 0.06], k: [0.1, 0.14, 0.02], c: 0x4a4644 }, { s: 'cyl', p: [-0.26, 0.3, 0.1], k: [0.05, 0.1, 0.05], c: 0x3a3632 }, { s: 'sphere', p: [-0.26, 0.3, 0.1], k: 0.03, c: 0xffb050, glow: true }); break;
    case 'miner': P.push({ s: 'sphere', p: [0, 0.82, -0.01], k: [0.23, 0.14, 0.23], c: 0x5a5046 }, { s: 'sphere', p: [0, 0.84, 0.21], k: 0.035, c: 0xffd070, glow: true }, { s: 'cyl', p: [0.26, 0.42, 0.06], k: [0.018, 0.4, 0.018], c: 0x4a3a2a }, { s: 'box', p: [0.26, 0.62, 0.06], r: [0, 0, 0.2], k: [0.26, 0.04, 0.04], c: 0x4a4644 }); break;
    case 'pilgrim': P.push({ s: 'cyl', p: [0, 0.88, -0.02], k: [0.36, 0.02, 0.36], c: 0x4a4436 }, { s: 'cone', p: [0, 0.96, -0.02], k: [0.2, 0.14, 0.2], c: 0x4a4436 }, { s: 'cyl', p: [0.26, 0.55, 0.06], k: [0.02, 1.1, 0.02], c: 0x4a3a2a }, { s: 'torus', p: [0.26, 1.1, 0.06], k: 0.05, tube: 0.3, c: 0x6a5a40 }); break;
    default: P.push(...hood(0x3a3448), { s: 'oct', p: [0.26, 0.5, 0.1], k: 0.06, c: 0xb45aff, glow: true });
  }
  return P;
}

export function buildingModel(id) {
  const g = new THREE.Group(), anim = {};
  const add = (parts) => { const d = K.doll(parts, { desat: 0.55 }); d.mat.color.setScalar(0.62); d.mesh.receiveShadow = true; g.add(d.root); return d; }; // 황혼: 바랜 나무와 돌
  const roof = (w, h, y, c, x = 0, z = 0) => ({ s: 'cone', p: [x, y + h / 2, z], r: [0, Math.PI / 4, 0], k: [w, h, w], seg: 4, c });
  if (id === 'gate') {
    add([{ s: 'box', p: [-0.78, 0.9, 0], k: [0.34, 1.8, 0.4], c: 0xa8a294 }, { s: 'box', p: [0.78, 0.9, 0], k: [0.34, 1.8, 0.4], c: 0xa8a294 }, { s: 'box', p: [0, 1.9, 0], k: [2.0, 0.32, 0.46], c: 0x948e80 }, { s: 'box', p: [0, 2.12, 0], k: [0.3, 0.2, 0.5], c: 0xb45aff }, { s: 'box', p: [-0.78, 0.08, 0], k: [0.46, 0.16, 0.5], c: 0x8a8476 }, { s: 'box', p: [0.78, 0.08, 0], k: [0.46, 0.16, 0.5], c: 0x8a8476 }]);
    const disc = new THREE.Mesh(new THREE.CircleGeometry(0.6, 32), new THREE.MeshBasicMaterial({ color: new THREE.Color(0.32, 0.2, 0.62), transparent: true, opacity: 0.55, side: THREE.DoubleSide }));
    disc.position.set(0, 0.95, 0); disc.scale.set(1, 1.35, 1); g.add(disc); anim.disc = disc;
  } else if (id === 'altar') {
    add([{ s: 'cyl', p: [0, 0.1, 0], k: [0.85, 0.2, 0.85], c: 0xb8b2a4 }, { s: 'cyl', p: [0, 0.3, 0], k: [0.62, 0.2, 0.62], c: 0xc8c2b4 }, { s: 'cyl', p: [0, 0.75, 0], k: [0.2, 0.7, 0.2], c: 0xd8d2c4 }, { s: 'sphere', p: [0, 1.12, 0], k: [0.32, 0.1, 0.32], c: 0xa89a8a }]);
    anim.gems = [0xff4a5a, 0xb45aff, 0x4ad86a].map((c, k) => { const d = K.doll([{ s: 'oct', k: [0.1, 0.15, 0.1], c }], { gloss: 1.5 }); g.add(d.root); d.root.userData.k = k; return d.root; });
  } else if (id === 'storage') {
    add([{ s: 'box', p: [0, 0.5, 0], k: [1.5, 1.0, 1.2], c: 0xb07a48 }, roof(1.15, 0.7, 1.0, 0xc0443a), { s: 'box', p: [0, 0.35, 0.61], k: [0.5, 0.7, 0.04], c: 0x5a3a22 }, { s: 'box', p: [0.95, 0.18, 0.45], k: [0.36, 0.36, 0.36], c: 0x9a6a3a }, { s: 'box', p: [1.05, 0.5, 0.5], k: [0.26, 0.26, 0.26], c: 0xa87a48 }, { s: 'cyl', p: [-0.95, 0.25, 0.45], k: [0.18, 0.5, 0.18], c: 0x7a5030 }]);
  } else if (id === 'forge') {
    add([{ s: 'box', p: [0, 0.05, 0], k: [1.7, 0.1, 1.4], c: 0x8a847a }, ...[[-0.72, -0.55], [0.72, -0.55], [-0.72, 0.55], [0.72, 0.55]].map(([x, z]) => ({ s: 'cyl', p: [x, 0.65, z], k: [0.06, 1.2, 0.06], c: 0x6a4526 })), { s: 'box', p: [0, 1.3, 0], r: [0.12, 0, 0], k: [1.8, 0.1, 1.5], c: 0x8a4a3a }, { s: 'box', p: [-0.45, 0.45, -0.25], k: [0.6, 0.8, 0.6], c: 0x7a7068 }, { s: 'cyl', p: [-0.45, 1.5, -0.25], k: [0.14, 1.2, 0.14], c: 0x6a6058 }, { s: 'box', p: [0.35, 0.3, 0.25], k: [0.4, 0.2, 0.22], c: 0x3a3a44 }, { s: 'box', p: [0.35, 0.15, 0.25], k: [0.2, 0.22, 0.16], c: 0x3a3a44 }]);
    const glow = new THREE.Mesh(new THREE.BoxGeometry(0.34, 0.24, 0.02), new THREE.MeshBasicMaterial({ color: new THREE.Color(2.6, 0.9, 0.2) })); glow.position.set(-0.45, 0.4, 0.06); g.add(glow); anim.ember = glow; anim.smoke = [-0.45, 2.15, -0.25];
  } else if (id === 'herb') {
    add([{ s: 'box', p: [0, 0.4, -0.3], k: [1.0, 0.8, 0.8], c: 0xe8d8b0 }, roof(0.8, 0.6, 0.8, 0x5a8a3a, 0, -0.3), { s: 'box', p: [0, 0.3, 0.1], k: [0.3, 0.6, 0.04], c: 0x6a4526 },
      ...[-0.5, -0.17, 0.17, 0.5].flatMap((x) => [0.55, 0.85].map((z) => ({ s: 'cone', p: [x, 0.15, z], k: [0.09, 0.3, 0.09], c: 0x5ad84a }))), { s: 'box', p: [0, 0.03, 0.7], k: [1.3, 0.06, 0.55], c: 0x6a4a2a }]);
  } else if (id === 'hunter') {
    add([{ s: 'cone', p: [-0.2, 0.65, 0], k: [0.75, 1.3, 0.75], seg: 6, c: 0xa07a50 }, { s: 'cone', p: [-0.2, 0.3, 0.55], r: [0.4, 0, 0], k: [0.2, 0.6, 0.05], c: 0x5a3a22 }, { s: 'cyl', p: [0.55, 0.5, -0.3], k: [0.04, 1.0, 0.04], c: 0x6a4526 }, { s: 'cyl', p: [0.55, 0.5, 0.3], k: [0.04, 1.0, 0.04], c: 0x6a4526 }, { s: 'cyl', p: [0.55, 0.98, 0], r: [Math.PI / 2, 0, 0], k: [0.03, 0.66, 0.03], c: 0x6a4526 }, { s: 'box', p: [0.55, 0.72, 0.12], k: [0.04, 0.45, 0.25], c: 0xc89a6a }, { s: 'box', p: [0.55, 0.75, -0.16], k: [0.04, 0.38, 0.2], c: 0x9a6a4a }]);
  } else if (id === 'library') {
    add([{ s: 'cyl', p: [0, 0.9, 0], k: [0.6, 1.8, 0.6], seg: 10, c: 0xd8d0c0 }, { s: 'cone', p: [0, 2.15, 0], k: [0.75, 0.7, 0.75], seg: 10, c: 0x3a5ab0 }, { s: 'box', p: [0, 1.3, 0.56], k: [0.2, 0.3, 0.06], c: 0x3a3450 }, { s: 'box', p: [0, 0.4, 0.58], k: [0.3, 0.8, 0.04], c: 0x6a4526 }, { s: 'box', p: [0.7, 0.12, 0.35], k: [0.3, 0.24, 0.2], c: 0xa03a3a }, { s: 'box', p: [0.72, 0.28, 0.35], k: [0.26, 0.08, 0.18], c: 0x3a6aa0 }]);
  } else if (id === 'inn') {
    add([{ s: 'box', p: [0, 0.45, -0.2], k: [1.6, 0.9, 1.0], c: 0xf0e0c0 }, roof(1.2, 0.6, 0.9, 0xd08040, 0, -0.2), { s: 'cyl', p: [0.5, 1.4, -0.35], k: [0.1, 0.6, 0.1], c: 0x8a6a5a }, { s: 'box', p: [0, 0.3, 0.31], k: [0.35, 0.6, 0.04], c: 0x6a4526 }, { s: 'cyl', p: [-0.55, 0.28, 0.55], k: [0.3, 0.05, 0.3], c: 0x9a6a3a }, { s: 'cyl', p: [-0.55, 0.14, 0.55], k: [0.05, 0.28, 0.05], c: 0x6a4526 }, { s: 'sphere', p: [-0.55, 0.36, 0.55], k: [0.12, 0.08, 0.12], c: 0x3a3a44 }]);
    anim.smoke = [0.5, 1.8, -0.35];
  } else if (id === 'plaza') {
    add([...Array.from({ length: 10 }, (_, k) => ({ s: 'box', p: [Math.cos(k * 0.628) * 0.5, 0.08, Math.sin(k * 0.628) * 0.5], r: [0, -k * 0.628, 0], k: [0.2, 0.16, 0.14], c: 0x9a948a })), { s: 'cyl', p: [0, 0.07, 0.08], r: [0, 0, Math.PI / 2], k: [0.07, 0.6, 0.07], c: 0x6a4526 }, { s: 'cyl', p: [0, 0.07, -0.08], r: [0, 0.8, Math.PI / 2], k: [0.07, 0.6, 0.07], c: 0x5a3a22 },
      { s: 'box', p: [-1.3, 0.14, 0.9], r: [0, 0.4, 0], k: [0.8, 0.12, 0.25], c: 0x8a5a32 }, { s: 'box', p: [1.3, 0.14, 0.9], r: [0, -0.4, 0], k: [0.8, 0.12, 0.25], c: 0x8a5a32 }]);
  }
  return { g, anim };
}
