import * as THREE from 'three';
import { G } from '../core/state.js';
import { BOSSES, MAGE } from '../data/enemies.js';
import { ITEMS } from '../data/items.js';
import { COLORS, STONE } from '../data/stones.js';
import { OLD_WEAPON, WEAPONS } from '../data/weapons.js';
import { _w } from './common.js';
import * as K from './diorama.js';
import { hatParts, headParts } from './heads.js';
import { heroSpec } from './hero-doll.js';
import { View } from './view.js';

export function dollSpec(e) {
  const sp = dollSpecBase(e);
  if (e.type === 'npc') return sp;
  if (e.boss) {
    sp.scale *= BOSSES[e.boss].scale;
    const top = e.type === 'mage' ? 1.5 : e.type === 'charger' ? 0.86 : 0.82, z = e.type === 'charger' ? 0.3 : 0;
    sp.parts = [...sp.parts, { s: 'cyl', p: [0, top, z], k: [0.17, 0.08, 0.17], c: 0xffc83a }, ...[0, 1, 2, 3, 4].map((k) => ({ s: 'cone', p: [Math.cos(k * 1.2566) * 0.14, top + 0.1, z + Math.sin(k * 1.2566) * 0.14], k: [0.035, 0.1, 0.035], c: 0xffd84a })), { s: 'sphere', p: [0, top + 0.02, z + 0.17], k: 0.03, c: 0xff3a5a }];
  }
  return sp;
}

export function dollSpecBase(e) {
  if (e.type === 'npc') {
    const cage = e.caged;
    return { h: 1.05, col: e.npcData.look.cloth, scale: 0.92, gloss: 0.22, parts: npcParts(e.npcData),
      extra: (d) => {
        if (!cage) return {};
        const bars = [];
        for (let k = 0; k < 10; k++) { const a = k * Math.PI / 5; bars.push({ s: 'cyl', p: [Math.cos(a) * 0.42, 0.6, Math.sin(a) * 0.42], k: [0.025, 1.2, 0.025], c: 0x6a6a78 }); }
        bars.push({ s: 'cyl', p: [0, 1.22, 0], k: [0.47, 0.06, 0.47], c: 0x55555f }, { s: 'cyl', p: [0, 0.03, 0], k: [0.47, 0.06, 0.47], c: 0x55555f }, { s: 'sphere', p: [0, 1.3, 0], k: 0.07, c: 0x8a8a98 });
        const c = K.doll(bars, { gloss: 0.9 }); d.root.add(c.root); return { cage: c.root };
      } };
  }
  const feet = (c, s = 1) => [{ s: 'sphere', p: [-0.1 * s, 0.07, 0.03], k: [0.09 * s, 0.07, 0.12 * s], c }, { s: 'sphere', p: [0.1 * s, 0.07, 0.03], k: [0.09 * s, 0.07, 0.12 * s], c }];
  const eyes = (y, z, sp = 0.09, c = 0x1a1420, k = [0.04, 0.055, 0.03]) => [
    { s: 'sphere', p: [-sp, y, z], k, c }, { s: 'sphere', p: [sp, y, z], k, c },
    { s: 'sphere', p: [-sp + 0.012, y + 0.02, z + 0.022], k: 0.014, c: 0xffffff }, { s: 'sphere', p: [sp + 0.012, y + 0.02, z + 0.022], k: 0.014, c: 0xffffff }];
  if (e.type === 'hero') return heroSpec(e.eq || G.eq);
  if (e.type === 'goblin') {
    const skin = e.poison ? 0x9ccf6a : 0x86c05a, tunic = e.poison ? 0x7a3f9a : 0xa0573a;
    return {
      h: 0.95, col: skin, scale: 0.9,
      parts: [...feet(0x4a3322, 0.9),
        { s: 'sphere', p: [0, 0.27, 0], k: [0.2, 0.2, 0.18], c: tunic },
        { s: 'sphere', p: [0, 0.6, 0], k: [0.26, 0.23, 0.23], c: skin },
        { s: 'cone', p: [-0.3, 0.64, -0.02], r: [0, 0, Math.PI / 2 + 0.35], k: [0.07, 0.22, 0.05], c: skin },
        { s: 'cone', p: [0.3, 0.64, -0.02], r: [0, 0, -Math.PI / 2 - 0.35], k: [0.07, 0.22, 0.05], c: skin },
        { s: 'sphere', p: [-0.095, 0.63, 0.18], k: [0.065, 0.075, 0.045], c: 0xfff3a0 }, { s: 'sphere', p: [0.095, 0.63, 0.18], k: [0.065, 0.075, 0.045], c: 0xfff3a0 },
        { s: 'sphere', p: [-0.095, 0.62, 0.22], k: 0.032, c: 0x111111 }, { s: 'sphere', p: [0.095, 0.62, 0.22], k: 0.032, c: 0x111111 },
        { s: 'sphere', p: [0, 0.55, 0.23], k: [0.05, 0.045, 0.05], c: e.poison ? 0x7aa84a : 0x6a9c44 },
        { s: 'box', p: [0, 0.48, 0.2], r: [0.3, 0, 0], k: [0.1, 0.02, 0.02], c: 0x3a1a1a },
        { s: 'sphere', p: [-0.21, 0.3, 0.06], k: 0.06, c: skin }, { s: 'sphere', p: [0.21, 0.3, 0.06], k: 0.06, c: skin },
        { s: 'box', p: [0.24, 0.38, 0.15], r: [0.5, 0, 0], k: [0.035, 0.22, 0.07], c: e.poison ? 0x7dff6a : 0xd8dee8 },
        ...(e.armor ? [{ s: 'sphere', p: [0, 0.73, -0.02], k: [0.275, 0.16, 0.255], c: 0x8a93a8 }, { s: 'cone', p: [0, 0.92, -0.02], k: [0.05, 0.13, 0.05], c: 0xc8d0e0 }, { s: 'sphere', p: [0, 0.29, 0.03], k: [0.215, 0.17, 0.18], c: 0x8a93a8 }, { s: 'sphere', p: [-0.21, 0.42, 0], k: [0.08, 0.06, 0.08], c: 0xa8b0c4 }, { s: 'sphere', p: [0.21, 0.42, 0], k: [0.08, 0.06, 0.08], c: 0xa8b0c4 }] : [])],
    };
  }
  if (e.type === 'mage') {
    const M = MAGE[e.elem];
    return {
      h: 1.45, col: M.robe, scale: 1,
      parts: [
        { s: 'cone', p: [0, 0.33, 0], k: [0.3, 0.62, 0.3], c: M.robe },
        { s: 'sphere', p: [0, 0.58, 0], k: [0.17, 0.08, 0.17], c: 0xe8d8a0 },
        { s: 'sphere', p: [0, 0.75, 0], k: 0.23, c: 0xece2c8 },
        { s: 'sphere', p: [-0.078, 0.76, 0.18], k: [0.065, 0.06, 0.035], c: 0x1a1420 }, { s: 'sphere', p: [0.078, 0.76, 0.18], k: [0.065, 0.06, 0.035], c: 0x1a1420 },
        { s: 'box', p: [0, 0.66, 0.2], k: [0.1, 0.03, 0.03], c: 0xfaf4e4 },
        { s: 'sphere', p: [-0.075, 0.76, 0.2], k: [0.045, 0.035, 0.02], c: M.color }, { s: 'sphere', p: [0.075, 0.76, 0.2], k: [0.045, 0.035, 0.02], c: M.color },
        { s: 'cyl', p: [0, 0.9, 0], k: [0.37, 0.03, 0.37], c: M.robe },
        { s: 'cyl', p: [0, 0.95, 0], k: [0.25, 0.05, 0.25], c: 0xe8d8a0 },
        { s: 'cone', p: [0, 1.2, -0.04], r: [-0.2, 0, 0], k: [0.25, 0.56, 0.25], c: M.robe },
        { s: 'sphere', p: [-0.25, 0.42, 0.1], k: 0.06, c: 0xece2c8 }, { s: 'sphere', p: [0.28, 0.46, 0.08], k: 0.06, c: 0xece2c8 },
        { s: 'cyl', p: [0.3, 0.55, 0.08], k: [0.025, 0.95, 0.025], c: 0x6a4526 }],
      extra: (d) => {
        const orb = new THREE.Mesh(new THREE.SphereGeometry(0.09, 14, 10), new THREE.MeshBasicMaterial({ color: new THREE.Color(M.color).multiplyScalar(2.2) }));
        orb.position.set(0.3, 1.1, 0.08); d.body.add(orb);
        return { update(dt, t, ev) { const c = ev.casting; orb.scale.setScalar(1 + Math.sin(t * 5) * 0.08 + (c ? 0.7 + Math.sin(t * 22) * 0.25 : 0)); if (c && Math.random() < dt * 30) { orb.getWorldPosition(_w); View.dio.sparks.emit({ pos: _w, n: 1, color: M.color, color2: 0xffffff, speed: 1, grav: 0, life: 0.4, size: 0.12 }); } } };
      },
    };
  }
  if (e.type === 'charger') return {
    h: 1.2, col: 0x7b5134, scale: 1.12,
    parts: [
      { s: 'cyl', p: [-0.18, 0.1, 0.15], k: [0.08, 0.2, 0.08], c: 0x3a2618 }, { s: 'cyl', p: [0.18, 0.1, 0.15], k: [0.08, 0.2, 0.08], c: 0x3a2618 },
      { s: 'cyl', p: [-0.18, 0.1, -0.22], k: [0.08, 0.2, 0.08], c: 0x3a2618 }, { s: 'cyl', p: [0.18, 0.1, -0.22], k: [0.08, 0.2, 0.08], c: 0x3a2618 },
      { s: 'sphere', p: [0, 0.4, -0.05], k: [0.34, 0.3, 0.42], c: 0x7b5134 },
      { s: 'box', p: [0, 0.63, -0.12], r: [0.15, 0, 0], k: [0.4, 0.1, 0.4], c: 0x8f98ab },
      { s: 'cone', p: [0, 0.72, -0.34], r: [-1.1, 0, 0], k: [0.08, 0.26, 0.2], c: 0x4a2e1d },
      { s: 'sphere', p: [0, 0.52, 0.32], k: [0.25, 0.23, 0.22], c: 0x8a5c3c },
      { s: 'cyl', p: [0, 0.47, 0.52], r: [Math.PI / 2, 0, 0], k: [0.11, 0.1, 0.09], c: 0xf0a4a0 },
      { s: 'sphere', p: [-0.04, 0.48, 0.57], k: 0.022, c: 0x3a1a1a }, { s: 'sphere', p: [0.04, 0.48, 0.57], k: 0.022, c: 0x3a1a1a },
      { s: 'cone', p: [-0.12, 0.47, 0.5], r: [-0.4, 0, 0.35], k: [0.035, 0.15, 0.035], c: 0xfff6e0 }, { s: 'cone', p: [0.12, 0.47, 0.5], r: [-0.4, 0, -0.35], k: [0.035, 0.15, 0.035], c: 0xfff6e0 },
      { s: 'sphere', p: [-0.1, 0.6, 0.47], k: [0.035, 0.045, 0.03], c: 0x140c0c }, { s: 'sphere', p: [0.1, 0.6, 0.47], k: [0.035, 0.045, 0.03], c: 0x140c0c },
      { s: 'box', p: [-0.1, 0.665, 0.47], r: [0, 0, -0.45], k: [0.1, 0.025, 0.03], c: 0x3a2215 }, { s: 'box', p: [0.1, 0.665, 0.47], r: [0, 0, 0.45], k: [0.1, 0.025, 0.03], c: 0x3a2215 },
      { s: 'sphere', p: [0, 0.66, 0.3], k: [0.21, 0.1, 0.19], c: 0x9aa6ba },
      { s: 'cone', p: [-0.21, 0.78, 0.3], r: [0, 0, 0.7], k: [0.05, 0.22, 0.05], c: 0xf2ead8 }, { s: 'cone', p: [0.21, 0.78, 0.3], r: [0, 0, -0.7], k: [0.05, 0.22, 0.05], c: 0xf2ead8 }],
  };
  return {
    h: 1.05, col: 0x4d7d3c, scale: 0.95,
    parts: [...feet(0x3a2a1a),
      { s: 'sphere', p: [0, 0.3, 0], k: [0.21, 0.23, 0.19], c: 0x4d7d3c },
      { s: 'cone', p: [0, 0.38, -0.1], k: [0.26, 0.5, 0.18], c: 0x355a2a },
      { s: 'sphere', p: [0, 0.66, 0.01], k: 0.215, c: 0xeee4cc }, { s: 'box', p: [0, 0.575, 0.185], k: [0.11, 0.035, 0.03], c: 0xfaf4e4 },
      { s: 'sphere', p: [0, 0.71, -0.06], k: [0.255, 0.245, 0.245], c: 0x3f6d31 },
      { s: 'cone', p: [0, 0.86, -0.3], r: [-1.1, 0, 0], k: [0.1, 0.24, 0.1], c: 0x3f6d31 },
      ...eyes(0.665, 0.19, 0.075, 0x241a1a, [0.05, 0.06, 0.03]),
      { s: 'torus', p: [-0.27, 0.42, 0.12], r: [0, -Math.PI / 2, -Math.PI / 2], k: 0.3, tube: 0.08, arc: Math.PI, c: 0x8a5a2a },
      { s: 'cyl', p: [-0.27, 0.42, 0.12], k: [0.008, 0.58, 0.008], c: 0xeeeeee },
      { s: 'sphere', p: [-0.24, 0.42, 0.12], k: 0.06, c: 0xeee4cc }, { s: 'sphere', p: [0.22, 0.34, 0.06], k: 0.06, c: 0xeee4cc },
      { s: 'cyl', p: [0.12, 0.45, -0.2], r: [0.3, 0, -0.3], k: [0.07, 0.34, 0.07], c: 0x7a4a28 },
      { s: 'cone', p: [0.18, 0.65, -0.26], k: [0.045, 0.09, 0.045], c: 0xe04a3a }],
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

/* 무기 12종 인형: 손잡이(손)가 원점, 날은 +y. 폭은 x, 두께는 z */
const STEEL = 0xe4ecf6, WOOD = 0x7a4a28, GRIP = 0x3a2618, GOLD = 0xd4a840, IRON = 0x8a92a4;
const dagger = (x, rz) => { const s = Math.sin(rz), c = Math.cos(rz); return [{ s: 'box', p: [x - s * 0.17, c * 0.17, 0], r: [0, 0, rz], k: [0.05, 0.25, 0.015], c: 0xeef2f8 }, { s: 'cone', p: [x - s * 0.32, c * 0.32, 0], r: [0, 0, rz], k: [0.025, 0.05, 0.0075], c: 0xeef2f8 }, { s: 'box', p: [x - s * 0.04, c * 0.04, 0], r: [0, 0, rz], k: [0.13, 0.03, 0.04], c: 0x8a6a3a }, { s: 'cyl', p: [x + s * 0.03, -c * 0.03, 0], r: [0, 0, rz], k: [0.022, 0.09, 0.022], c: GRIP }]; };
const spikes = (x, y, z, r, c = 0xdfe4ee) => [[0, 0, -Math.PI / 2, r, 0, 0], [0, 0, Math.PI / 2, -r, 0, 0], [0, 0, 0, 0, r, 0], [Math.PI / 2, 0, 0, 0, 0, r], [-Math.PI / 2, 0, 0, 0, 0, -r]].map(([a, b, g, dx, dy, dz]) => ({ s: 'cone', p: [x + dx, y + dy, z + dz], r: [a, b, g], k: [0.025, 0.06, 0.025], c }));
export const WEAPON_PARTS = {
  // 손도끼: 짧은 자루 + 둥근 날 + 뒤 가시
  axe: [{ s: 'cyl', p: [0, 0.16, 0], k: [0.026, 0.52, 0.026], c: WOOD }, { s: 'box', p: [0.07, 0.34, 0], k: [0.12, 0.13, 0.03], c: 0xcfd6e2 }, { s: 'cyl', p: [0.13, 0.34, 0], r: [Math.PI / 2, 0, 0], k: [0.1, 0.028, 0.1], c: STEEL }, { s: 'cone', p: [-0.06, 0.36, 0], r: [0, 0, Math.PI / 2], k: [0.025, 0.07, 0.025], c: 0xcfd6e2 }],
  // 쇠사슬 도리깨: 손잡이 + 사슬 고리 셋 + 가시 쇠공
  flail: [{ s: 'cyl', p: [0, 0.06, 0], k: [0.026, 0.3, 0.026], c: WOOD }, { s: 'sphere', p: [0, 0.22, 0], k: 0.035, c: IRON },
    ...[0, 1, 2].map((j) => ({ s: 'torus', p: [0.03 + j * 0.035, 0.27 + j * 0.055, 0], r: [j % 2 ? Math.PI / 2 : 0, 0, -0.55], k: [0.025, 0.035, 0.025], tube: 0.3, c: 0xaab2c4 })),
    { s: 'sphere', p: [0.14, 0.45, 0], k: 0.075, c: 0x6a7080 }, ...spikes(0.14, 0.45, 0, 0.075)],
  // 쌍단검: 두 자루가 살짝 벌어진 채
  twin: [...dagger(-0.045, 0.14), ...dagger(0.045, -0.14)],
  // 부메랑: 굽은 V, 팔꿈치를 쥔다
  boomerang: [{ s: 'box', p: [-0.073, 0.007, 0], r: [0, 0, 0.6], k: [0.06, 0.26, 0.022], c: 0xc89a5a }, { s: 'box', p: [0.073, 0.007, 0], r: [0, 0, -0.6], k: [0.06, 0.26, 0.022], c: 0xc89a5a }, { s: 'cyl', p: [0, -0.1, 0], r: [Math.PI / 2, 0, 0], k: [0.042, 0.022, 0.042], c: 0xc89a5a },
    { s: 'sphere', p: [-0.147, 0.114, 0], k: [0.038, 0.038, 0.014], c: STEEL }, { s: 'sphere', p: [0.147, 0.114, 0], k: [0.038, 0.038, 0.014], c: STEEL }],
  // 대검: 길고 넓은 날 + 홈 + 긴 손잡이(두 손)
  greatsword: [{ s: 'box', p: [0, 0.46, 0], k: [0.11, 0.76, 0.025], c: 0xdfe6f0 }, { s: 'box', p: [0, 0.44, 0.013], k: [0.025, 0.6, 0.004], c: 0x9aa4b8 }, { s: 'cone', p: [0, 0.88, 0], k: [0.055, 0.08, 0.0125], c: 0xdfe6f0 },
    { s: 'box', p: [0, 0.07, 0], k: [0.32, 0.05, 0.06], c: GOLD }, { s: 'cyl', p: [0, -0.08, 0], k: [0.027, 0.26, 0.027], c: 0x3a2a4a }, { s: 'sphere', p: [0, -0.23, 0], k: 0.042, c: GOLD }],
  // 전투 망치: 긴 자루 + 네모 머리 + 양쪽 면 + 윗 가시
  hammer: [{ s: 'cyl', p: [0, 0.22, 0], k: [0.028, 0.7, 0.028], c: 0x6a4526 }, { s: 'cyl', p: [0, 0.02, 0], k: [0.034, 0.16, 0.034], c: 0x3a2a4a }, { s: 'box', p: [0, 0.47, 0], k: [0.07, 0.03, 0.07], c: GRIP },
    { s: 'box', p: [0, 0.56, 0], k: [0.28, 0.14, 0.14], c: IRON }, { s: 'cyl', p: [-0.15, 0.56, 0], r: [0, 0, Math.PI / 2], k: [0.085, 0.03, 0.085], c: 0xaab2c4 }, { s: 'cyl', p: [0.15, 0.56, 0], r: [0, 0, Math.PI / 2], k: [0.085, 0.03, 0.085], c: 0xaab2c4 }, { s: 'cone', p: [0, 0.67, 0], k: [0.03, 0.08, 0.03], c: 0xdfe4ee }],
  // 창: 긴 자루 + 쇠고리 + 날
  spear: [{ s: 'cyl', p: [0, 0.3, 0], k: [0.02, 0.86, 0.02], c: 0x8a5a32 }, { s: 'cyl', p: [0, 0.71, 0], k: [0.03, 0.04, 0.03], c: IRON }, { s: 'cone', p: [0, 0.81, 0], k: [0.045, 0.17, 0.02], c: STEEL }],
  // 석궁: 개머리 + 활 날개 + 시위 + 걸린 화살
  crossbow: [{ s: 'box', p: [0, 0.18, 0], k: [0.06, 0.46, 0.07], c: WOOD }, { s: 'box', p: [0, -0.06, 0], k: [0.08, 0.1, 0.09], c: 0x5a3a22 },
    { s: 'box', p: [-0.12, 0.34, 0], r: [0, 0, Math.PI / 2 + 0.25], k: [0.03, 0.26, 0.03], c: 0x4a3a5a }, { s: 'box', p: [0.12, 0.34, 0], r: [0, 0, -Math.PI / 2 - 0.25], k: [0.03, 0.26, 0.03], c: 0x4a3a5a },
    { s: 'box', p: [-0.123, 0.264, 0], r: [0, 0, 1.227], k: [0.008, 0.261, 0.008], c: 0xf2ead8 }, { s: 'box', p: [0.123, 0.264, 0], r: [0, 0, -1.227], k: [0.008, 0.261, 0.008], c: 0xf2ead8 },
    { s: 'cyl', p: [0, 0.32, 0.045], k: [0.012, 0.26, 0.012], c: 0xc89a5a }, { s: 'cone', p: [0, 0.47, 0.045], k: [0.022, 0.05, 0.022], c: STEEL }],
  sword: [{ s: 'box', p: [0, 0.3, 0], k: [0.065, 0.48, 0.02], c: STEEL }, { s: 'box', p: [0, 0.06, 0], k: [0.22, 0.045, 0.05], c: GOLD }, { s: 'cyl', p: [0, -0.03, 0], k: [0.025, 0.12, 0.025], c: 0x5a3a22 }],
  mace: [{ s: 'cyl', p: [0, 0.13, 0], k: [0.026, 0.48, 0.026], c: 0x5a3a22 }, { s: 'sphere', p: [0, 0.4, 0], k: 0.095, c: 0x9aa2b4 }, { s: 'cone', p: [0.1, 0.4, 0], r: [0, 0, -Math.PI / 2], k: [0.03, 0.07, 0.03], c: 0xdfe4ee }, { s: 'cone', p: [-0.1, 0.4, 0], r: [0, 0, Math.PI / 2], k: [0.03, 0.07, 0.03], c: 0xdfe4ee }, { s: 'cone', p: [0, 0.5, 0], k: [0.03, 0.07, 0.03], c: 0xdfe4ee }],
  // 레이피어: 가늘고 긴 날 + 가로 날밑 + 컵 고리 + 손등 활
  rapier: [{ s: 'box', p: [0, 0.39, 0], k: [0.022, 0.66, 0.012], c: 0xeef2f8 }, { s: 'cone', p: [0, 0.74, 0], k: [0.011, 0.05, 0.006], c: 0xeef2f8 }, { s: 'box', p: [0, 0.05, 0], k: [0.18, 0.02, 0.02], c: GOLD },
    { s: 'torus', p: [0, 0.06, 0], r: [Math.PI / 2, 0, 0], k: 0.06, tube: 0.2, c: GOLD }, { s: 'torus', p: [0, -0.03, 0], r: [0, 0, -Math.PI / 2], k: 0.08, tube: 0.15, arc: Math.PI, c: GOLD },
    { s: 'cyl', p: [0, -0.03, 0], k: [0.02, 0.14, 0.02], c: GRIP }, { s: 'sphere', p: [0, -0.11, 0], k: 0.03, c: GOLD }],
  // 투석구: 손가락 고리 + 늘어진 끈 두 가닥 + 주머니 + 돌
  sling: [{ s: 'torus', p: [0, 0.02, 0], r: [Math.PI / 2, 0, 0], k: 0.035, tube: 0.3, c: 0xa07a4a }, { s: 'box', p: [-0.03, -0.15, 0], r: [0, 0, 0.1], k: [0.012, 0.28, 0.012], c: 0xa07a4a }, { s: 'box', p: [0.03, -0.15, 0], r: [0, 0, -0.1], k: [0.012, 0.28, 0.012], c: 0xa07a4a },
    { s: 'sphere', p: [0, -0.31, 0], k: [0.065, 0.035, 0.055], c: 0x7a4a28 }, { s: 'sphere', p: [0, -0.275, 0], k: 0.04, c: 0x9a9aa8 }],
};
for (const [o, n] of Object.entries(OLD_WEAPON)) WEAPON_PARTS[o] = WEAPON_PARTS[n]; // 옛 id(단검) → 쌍단검
/** 색 리본을 매는 높이(기본 손 바로 아래) · 두 손 무기의 둘째 손 자리 */
const RIB = { greatsword: -0.26, crossbow: -0.12, sling: -0.08 };
export const GRIP2 = { twin: [0.1, -0.01, 0.02], greatsword: [0, -0.15, 0], hammer: [0, 0.17, 0], crossbow: [0, 0.2, 0.04] };
const ribbon = (c, y) => [{ s: 'torus', p: [0, y, 0], r: [Math.PI / 2, 0, 0], k: 0.034, tube: 0.4, c }, { s: 'box', p: [-0.022, y - 0.06, 0.012], r: [0, 0, -0.35], k: [0.024, 0.1, 0.008], c }, { s: 'box', p: [0.024, y - 0.055, 0.012], r: [0, 0, 0.3], k: [0.024, 0.09, 0.008], c }];

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

/** 무기 인형: 종류마다 모양 + 손잡이에 무기 색 리본. id 끝의 '+'(또는 it 강화 +2 이상)면 날에 광택 */
export function weaponDoll(id, it) {
  const k0 = id.replace('+', ''), k = OLD_WEAPON[k0] || k0, w = WEAPONS[k];
  return K.doll([...(WEAPON_PARTS[k] || WEAPON_PARTS.sword), ...(w ? ribbon(COLORS[w.color].hex, RIB[k] ?? -0.09) : [])], { gloss: id.endsWith('+') || it?.plus >= 2 ? 1.8 : 1.1 });
}

/* ---------- 정착지 인형 · 건물 ---------- */
/* ---------- 주민 인형: 매끈한 몸(단면 회전 겉옷 · 굽은 팔다리) + 머리 모양 + 직업 옷차림과 도구 ---------- */
const HAIR_STYLES = ['short', 'bob', 'pony', 'long', 'buzz', 'short', 'bob'];
const hashId = (s) => { let h = 7; for (const ch of String(s)) h = (h * 31 + ch.charCodeAt(0)) >>> 0; return h; };
const tone = (c, k) => { const f = (v) => Math.max(0, Math.min(255, Math.round(v * k))); return (f((c >> 16) & 255) << 16) | (f((c >> 8) & 255) << 8) | f(c & 255); };
/** 몸: robe = 발목까지 오는 긴 옷, apron = 앞치마 색, pose = 오른손 높이(도구를 들면 위로) */
function npcBody({ cloth, skin, shirt = 0xe8dcc4, pants = 0x4a4038, boots = 0x4a3322, robe = false, apron = null, belt = 0x6a4a30 }) {
  const hem = robe ? 0.02 : 0.12, coat = [[0, hem + 0.01], [0.21, hem], [robe ? 0.25 : 0.235, hem + 0.012], [0.215, 0.2], [0.18, 0.27], [0.195, 0.34], [0.205, 0.4], [0.195, 0.455], [0.148, 0.5], [0.082, 0.528], [0, 0.54]];
  const paint = [{ c: shirt, a: 0.55, vee: true, y0: 0.32, y1: 0.54 }];
  if (apron) paint.push({ c: apron, a: 0.75, y0: hem, y1: 0.43 });
  const parts = [
    { s: 'lathe', pts: coat, k: [1, 1, 0.86], seg: 26, wave: robe ? 0.05 : 0.07, waveN: 7, waveTop: 0.26, c: cloth, paint, shade: 0.24 },
    { s: 'torus', p: [0, 0.27, 0], r: [Math.PI / 2, 0, 0], k: [0.186, 0.162, 0.12], tube: 0.2, c: belt },
    { s: 'torus', p: [0, 0.52, 0], r: [Math.PI / 2, 0, 0], k: [0.095, 0.085, 0.1], tube: 0.45, c: shirt },
  ];
  for (const sx of [-1, 1]) {
    if (!robe) parts.push({ s: 'tube', path: [[0.095 * sx, 0.3, 0], [0.105 * sx, 0.2, 0.01], [0.11 * sx, 0.12, 0.01]], r0: 0.066, r1: 0.056, c: pants, shade: 0.2 });
    parts.push({ s: 'lathe', p: [0.11 * sx, 0, 0.01], pts: [[0, 0.005], [0.075, 0.006], [0.082, 0.045], [0.075, 0.12], [0, 0.125]], seg: 14, c: boots, shade: 0.25 }, { s: 'sphere', p: [0.11 * sx, 0.045, 0.065], k: [0.072, 0.045, 0.09], c: boots });
    parts.push({ s: 'tube', path: [[0.17 * sx, 0.455, 0], [0.235 * sx, 0.38, 0.02], [0.245 * sx, 0.32, 0.05]], r0: 0.07, r1: 0.052, c: cloth, shade: 0.12 }, { s: 'sphere', p: [0.25 * sx, 0.3, 0.06], k: 0.062, c: skin });
  }
  return parts;
}
export function npcParts(n) {
  const L = n.look, S = L.skin, Hc = L.hair, C = L.cloth, h = hashId(n.id || n.name), style = L.style || HAIR_STYLES[h % HAIR_STYLES.length];
  const head = (o = {}) => headParts({ skin: S, hair: Hc, eye: 0x2a2030, style, mood: n.mood || 0, ...o });
  const tool = (parts) => parts; // 오른손(x 0.25, y 0.3)에 쥔 도구
  let P;
  switch (n.job) {
    case 'blacksmith': P = [...npcBody({ cloth: C, skin: S, apron: 0x3a2618 }), ...head(), { s: 'tube', path: [[-0.085, 0.665, 0.25], [-0.04, 0.692, 0.272], [0, 0.686, 0.277], [0.04, 0.692, 0.272], [0.085, 0.665, 0.25]], r0: 0.02, r1: 0.02, rs: 8, c: tone(Hc, 1.15) }, // 콧수염
      ...tool([{ s: 'cyl', p: [0.26, 0.4, 0.07], k: [0.022, 0.28, 0.022], c: 0x6a4526 }, { s: 'box', p: [0.26, 0.55, 0.07], k: [0.14, 0.075, 0.075], c: 0x8a92a4 }])]; break;
    case 'herbalist': P = [...npcBody({ cloth: C, skin: S, apron: 0x8ab070 }), ...head({ cover: 2 }), ...hatParts('hood', { c: 0x5a9a4a, trim: 0x3f7a35 }),
      { s: 'lathe', p: [-0.3, 0.2, 0.08], pts: [[0, 0], [0.08, 0.005], [0.1, 0.1], [0, 0.1]], seg: 14, c: 0xb08a4a, paint: [{ c: 0x8a6a34, band: 0.025 }] }, ...[0, 1, 2].map((k) => ({ s: 'sphere', p: [-0.3 + (k - 1) * 0.04, 0.31, 0.08], k: [0.035, 0.05, 0.035], c: [0x6ac84a, 0x8ad86a, 0xe86a8a][k] }))]; break;
    case 'hunter': P = [...npcBody({ cloth: C, skin: S, shirt: 0xc8a878 }), ...head({ cover: 1 }), { s: 'lathe', p: [0, 0.76, 0.005], pts: [[0.3, 0.08], [0.295, 0.18], [0.24, 0.27], [0.13, 0.32], [0, 0.33]], seg: 22, wave: 0.05, waveN: 14, waveTop: 0.2, c: 0x8a6a4a, shade: 0.15, paint: [{ c: 0xd8c8a8, y0: 0.82, y1: 0.87 }] },
      ...[-1, 1].map((sx) => ({ s: 'cone', p: [0.15 * sx, 1.07, 0], r: [0, 0, -0.3 * sx], k: [0.05, 0.1, 0.035], c: 0x8a6a4a })), { s: 'torus', p: [0, 0.38, -0.2], r: [0, 0, Math.PI / 2], k: 0.26, tube: 0.06, arc: Math.PI, c: 0x7a4a28 }, { s: 'tube', path: [[0, 0.64, -0.21], [0, 0.38, -0.23], [0, 0.12, -0.21]], r0: 0.006, r1: 0.006, rs: 4, c: 0xe8e0c8, outline: false }]; break;
    case 'scholar': P = [...npcBody({ cloth: C, skin: S, robe: true, shirt: 0xd8d0e8 }), ...head(), ...[-1, 1].map((sx) => ({ s: 'torus', p: [0.087 * sx, 0.762, 0.305], k: 0.066, tube: 0.14, c: 0x3a2a1a, outline: false })), { s: 'tube', path: [[-0.022, 0.77, 0.305], [0, 0.78, 0.31], [0.022, 0.77, 0.305]], r0: 0.008, r1: 0.008, rs: 5, c: 0x3a2a1a, outline: false },
      { s: 'box', p: [-0.27, 0.34, 0.11], r: [0.3, 0.2, 0], k: [0.16, 0.2, 0.05], c: 0xa03a3a }, { s: 'box', p: [-0.265, 0.34, 0.14], r: [0.3, 0.2, 0], k: [0.14, 0.18, 0.02], c: 0xf2ead8 }]; break;
    case 'cook': P = [...npcBody({ cloth: C, skin: S, apron: 0xf4f0e8 }), ...head({ cover: 1 }), { s: 'lathe', p: [0, 0.76, 0.005], pts: [[0.24, 0.17], [0.23, 0.3], [0.26, 0.36], [0.3, 0.42], [0.25, 0.5], [0.12, 0.53], [0, 0.535]], seg: 22, wave: 0.08, waveN: 8, waveTop: 0.55, c: 0xffffff, shade: 0.12 },
      ...tool([{ s: 'cyl', p: [0.26, 0.42, 0.07], k: [0.018, 0.26, 0.018], c: 0x9a6a3a }, { s: 'sphere', p: [0.26, 0.56, 0.07], k: [0.05, 0.03, 0.05], c: 0x9a6a3a }])]; break;
    case 'fisher': P = [...npcBody({ cloth: C, skin: S, shirt: 0xdad2b8 }), ...head({ cover: 1 }), ...hatParts('hat', { c: 0xe8c860, trim: 0xc8a040 }),
      { s: 'cyl', p: [0.27, 0.62, 0.08], r: [0.2, 0, -0.35], k: [0.014, 0.9, 0.014], c: 0x8a5a32 }, { s: 'lathe', p: [-0.24, 0.16, -0.08], pts: [[0, 0], [0.11, 0.01], [0.12, 0.09], [0.09, 0.14], [0, 0.145]], seg: 14, c: 0xc8b890, shade: 0.2 }]; break;
    case 'boatman': P = [...npcBody({ cloth: C, skin: S, shirt: 0x9ab8d0 }), ...head({ cover: 1 }), { s: 'lathe', p: [0, 0.76, 0.005], pts: [[0.29, 0.1], [0.3, 0.16], [0.27, 0.25], [0.16, 0.31], [0, 0.325]], seg: 22, c: 0x2a4a6a, shade: 0.15, paint: [{ c: 0x3a6a8a, y0: 0.85, y1: 0.93 }] },
      { s: 'cyl', p: [0.27, 0.5, 0.08], k: [0.022, 1.0, 0.022], c: 0x9a6a3a }, { s: 'lathe', p: [0.27, -0.03, 0.08], pts: [[0, 0], [0.06, 0.02], [0.07, 0.14], [0.03, 0.2], [0, 0.2]], k: [1, 1, 0.3], seg: 12, c: 0x9a6a3a }]; break;
    case 'gravekeeper': P = [...npcBody({ cloth: C, skin: S, robe: true, shirt: 0x9a9aa8 }), ...head({ cover: 2 }), ...hatParts('hood', { c: 0x5a5a6a, trim: 0x44444f }),
      { s: 'cyl', p: [0.27, 0.42, 0.08], k: [0.02, 0.62, 0.02], c: 0x6a4526 }, { s: 'lathe', p: [0.27, 0.02, 0.08], pts: [[0, 0], [0.06, 0.03], [0.065, 0.13], [0, 0.14]], k: [1, 1, 0.25], seg: 12, c: 0x9aa2b4 },
      { s: 'cyl', p: [-0.27, 0.26, 0.1], k: [0.055, 0.1, 0.055], c: 0x3a3a44 }, { s: 'sphere', p: [-0.27, 0.26, 0.1], k: 0.038, c: 0xffd070, outline: false }]; break;
    case 'miner': P = [...npcBody({ cloth: C, skin: S, shirt: 0xc8b890 }), ...head({ cover: 2 }), ...hatParts('helm', { c: 0xe8b83a, trim: 0xb88a20 }).slice(0, 2), { s: 'sphere', p: [0, 0.9, 0.29], k: 0.045, c: 0xfff4c0, outline: false },
      { s: 'cyl', p: [0.27, 0.42, 0.08], k: [0.02, 0.42, 0.02], c: 0x6a4526 }, { s: 'tube', path: [[0.12, 0.6, 0.08], [0.27, 0.64, 0.08], [0.42, 0.6, 0.08]], r0: 0.024, r1: 0.012, rs: 6, c: 0x9aa2b4 }]; break;
    case 'pilgrim': P = [...npcBody({ cloth: C, skin: S, robe: true, shirt: 0xe8dcc0 }), ...head({ cover: 1 }), ...hatParts('hat', { c: 0xb89a6a, trim: 0x8a6a3a }),
      { s: 'cyl', p: [0.27, 0.55, 0.08], k: [0.022, 1.1, 0.022], c: 0x8a5a32 }, { s: 'torus', p: [0.27, 1.12, 0.08], k: 0.05, tube: 0.3, c: 0xffd84a }]; break;
    default: P = [...npcBody({ cloth: C, skin: S, robe: true, shirt: 0xd8c8f0 }), ...head({ cover: 2 }), { s: 'lathe', p: [0, 0.78, 0], r: [-0.12, 0, 0], pts: [[0.34, 0], [0.32, 0.05], [0.22, 0.2], [0.1, 0.4], [0.02, 0.55], [0, 0.56]], seg: 20, wave: 0.04, waveN: 5, waveTop: 0.3, c: 0x8a7ab0, shade: 0.2, paint: [{ c: 0xc8a8f0, y0: 0.78, y1: 0.84 }] },
      { s: 'oct', p: [0.27, 0.46, 0.1], k: 0.07, c: 0xb45aff }];
  }
  return P;
}

export function buildingModel(id) {
  const g = new THREE.Group(), anim = {};
  const add = (parts) => { const d = K.doll(parts, { gloss: 0.45 }); d.mesh.receiveShadow = true; g.add(d.root); return d; };
  const roof = (w, h, y, c, x = 0, z = 0) => ({ s: 'cone', p: [x, y + h / 2, z], r: [0, Math.PI / 4, 0], k: [w, h, w], seg: 4, c });
  if (id === 'gate') {
    add([{ s: 'box', p: [-0.78, 0.9, 0], k: [0.34, 1.8, 0.4], c: 0xa8a294 }, { s: 'box', p: [0.78, 0.9, 0], k: [0.34, 1.8, 0.4], c: 0xa8a294 }, { s: 'box', p: [0, 1.9, 0], k: [2.0, 0.32, 0.46], c: 0x948e80 }, { s: 'box', p: [0, 2.12, 0], k: [0.3, 0.2, 0.5], c: 0xb45aff }, { s: 'box', p: [-0.78, 0.08, 0], k: [0.46, 0.16, 0.5], c: 0x8a8476 }, { s: 'box', p: [0.78, 0.08, 0], k: [0.46, 0.16, 0.5], c: 0x8a8476 }]);
    const disc = new THREE.Mesh(new THREE.CircleGeometry(0.6, 32), new THREE.MeshBasicMaterial({ color: new THREE.Color(0.7, 0.45, 1.6), transparent: true, opacity: 0.75, side: THREE.DoubleSide }));
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
