import * as THREE from 'three';
import * as K from './diorama.js';
import { G } from '../core/state.js';
import { BOSSES, MAGE } from '../data/enemies.js';
import { ITEMS } from '../data/items.js';
import { COLORS, STONE } from '../data/stones.js';
import { SKIN, _w } from './common.js';
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
    return { h: 1.05, col: e.npcData.look.cloth, scale: 0.92, parts: npcParts(e.npcData),
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
  if (e.type === 'hero') return {
    h: 1.15, col: 0x3f86d8, scale: 1,
    parts: [...feet(0x6b3f25),
      { s: 'sphere', p: [0, 0.32, 0], k: [0.24, 0.25, 0.21], c: 0x3f86d8 },
      { s: 'cyl', p: [0, 0.25, 0], k: [0.238, 0.05, 0.208], c: 0x7a4a28 },
      { s: 'sphere', p: [0, 0.26, 0.205], k: [0.045, 0.04, 0.02], c: 0xffd35a },
      { s: 'torus', p: [0, 0.5, 0], r: [Math.PI / 2, 0, 0], k: 0.15, tube: 0.4, c: 0xe0443a },
      { s: 'cone', p: [0.06, 0.44, -0.2], r: [-0.5, 0, 0.3], k: [0.06, 0.18, 0.04], c: 0xe0443a },
      { s: 'sphere', p: [0, 0.75, 0], k: 0.27, c: SKIN },
      { s: 'sphere', p: [0, 0.8, -0.05], k: [0.285, 0.23, 0.28], c: 0x5a3020 },
      { s: 'sphere', p: [0, 0.9, -0.02], k: [0.27, 0.17, 0.27], c: 0x2f7fe0 },
      { s: 'cyl', p: [0, 0.86, 0.02], k: [0.29, 0.04, 0.29], c: 0xf2e6c8 },
      { s: 'cone', p: [0.2, 1.02, -0.08], r: [0.3, 0, -0.9], k: [0.05, 0.22, 0.03], c: 0xe0443a },
      { s: 'sphere', p: [0.05, 0.83, 0.2], k: [0.15, 0.06, 0.08], r: [0, 0, -0.2], c: 0x5a3020 },
      ...eyes(0.72, 0.235),
      { s: 'sphere', p: [-0.16, 0.65, 0.2], k: [0.045, 0.025, 0.02], c: 0xff9a9a }, { s: 'sphere', p: [0.16, 0.65, 0.2], k: [0.045, 0.025, 0.02], c: 0xff9a9a },
      { s: 'sphere', p: [-0.27, 0.36, 0.04], k: 0.075, c: SKIN }, { s: 'sphere', p: [0.28, 0.4, 0.07], k: 0.075, c: SKIN },
      { s: 'cyl', p: [0, 0.37, -0.24], r: [Math.PI / 2, 0, 0], k: [0.17, 0.04, 0.17], c: 0x9aa6b8 },
      { s: 'sphere', p: [0, 0.37, -0.27], k: [0.05, 0.05, 0.03], c: 0xffd35a },
      { s: 'cyl', p: [0.31, 0.5, 0.09], r: [0.15, 0, -0.15], k: [0.028, 0.32, 0.028], c: 0x5a3a22 },
      { s: 'cyl', p: [0.33, 0.64, 0.1], k: [0.05, 0.05, 0.05], c: 0x3a2a1a }],
    extra: (d) => {
      const f = new THREE.Group();
      const o = new THREE.Mesh(new THREE.ConeGeometry(0.08, 0.22, 7).translate(0, 0.11, 0), new THREE.MeshBasicMaterial({ color: new THREE.Color(2.6, 0.9, 0.2) }));
      const i = new THREE.Mesh(new THREE.ConeGeometry(0.045, 0.14, 7).translate(0, 0.07, 0), new THREE.MeshBasicMaterial({ color: new THREE.Color(3, 2.5, 1) }));
      f.add(o, i); f.position.set(0.335, 0.66, 0.1); d.body.add(f);
      const wh = new THREE.Group(); wh.position.set(-0.28, 0.37, 0.06); wh.rotation.x = 0.5; d.body.add(wh);
      return { wh, update(dt, t) { const s = 1 + Math.sin(t * 20) * 0.12 + Math.sin(t * 33) * 0.08; o.scale.set(1, s, 1); i.scale.set(1, s * 1.05, 1); f.rotation.z = Math.sin(t * 6) * 0.1; if (Math.random() < dt * 8) { f.getWorldPosition(_w); _w.y += 0.2; View.dio.sparks.emit({ pos: _w, n: 1, color: 0xff9a3a, color2: 0xffe36a, speed: 0.3, up: 1.2, grav: 0.6, life: 0.6, size: 0.07 }); } } };
    },
  };
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
  };
  return K.doll(P[m] || P.광석, { gloss: 1.3 }).root;
}

export const weaponDoll = (id) => K.doll(WEAPON_PARTS[id.replace('+', '')], { gloss: id.endsWith('+') ? 1.8 : 1.1 });

/* ---------- 정착지 인형 · 건물 ---------- */
export function npcParts(n) {
  const L = n.look, S = L.skin, Hc = L.hair, C = L.cloth, eye = 0x1a1420;
  const P = [
    { s: 'sphere', p: [-0.09, 0.07, 0.03], k: [0.085, 0.065, 0.11], c: 0x4a3322 }, { s: 'sphere', p: [0.09, 0.07, 0.03], k: [0.085, 0.065, 0.11], c: 0x4a3322 },
    { s: 'sphere', p: [0, 0.31, 0], k: [0.22, 0.24, 0.2], c: C },
    { s: 'sphere', p: [0, 0.72, 0], k: 0.25, c: S },
    { s: 'sphere', p: [0, 0.79, -0.05], k: [0.265, 0.22, 0.26], c: Hc },
    { s: 'sphere', p: [-0.085, 0.7, 0.22], k: [0.035, 0.05, 0.03], c: eye }, { s: 'sphere', p: [0.085, 0.7, 0.22], k: [0.035, 0.05, 0.03], c: eye },
    { s: 'sphere', p: [-0.074, 0.72, 0.245], k: 0.012, c: 0xffffff }, { s: 'sphere', p: [0.096, 0.72, 0.245], k: 0.012, c: 0xffffff },
    { s: 'sphere', p: [-0.15, 0.63, 0.19], k: [0.04, 0.022, 0.02], c: 0xff9a9a }, { s: 'sphere', p: [0.15, 0.63, 0.19], k: [0.04, 0.022, 0.02], c: 0xff9a9a },
    { s: 'sphere', p: [-0.24, 0.33, 0.04], k: 0.065, c: S }, { s: 'sphere', p: [0.24, 0.33, 0.04], k: 0.065, c: S },
  ];
  switch (n.job) {
    case 'blacksmith': P.push({ s: 'box', p: [0, 0.3, 0.17], k: [0.3, 0.32, 0.06], c: 0x7a4a28 }, { s: 'sphere', p: [0, 0.6, 0.17], k: [0.15, 0.1, 0.08], c: Hc }, { s: 'cyl', p: [0.27, 0.42, 0.08], k: [0.022, 0.3, 0.022], c: 0x6a4526 }, { s: 'box', p: [0.27, 0.58, 0.08], k: [0.14, 0.08, 0.08], c: 0x8a92a4 }); break;
    case 'herbalist': P.push({ s: 'sphere', p: [0, 0.82, -0.04], k: [0.29, 0.25, 0.29], c: 0x5a9a4a }, { s: 'cone', p: [0, 1.02, -0.14], r: [-0.6, 0, 0], k: [0.08, 0.2, 0.08], c: 0x5a9a4a }, { s: 'cyl', p: [-0.28, 0.28, 0.06], k: [0.1, 0.1, 0.1], c: 0xb08a4a }, { s: 'sphere', p: [-0.28, 0.35, 0.06], k: [0.08, 0.04, 0.08], c: 0x6ac84a }); break;
    case 'hunter': P.push({ s: 'sphere', p: [0, 0.86, -0.02], k: [0.27, 0.16, 0.27], c: 0x8a6a4a }, { s: 'cone', p: [-0.15, 1.0, 0], k: [0.05, 0.1, 0.05], c: 0x8a6a4a }, { s: 'cone', p: [0.15, 1.0, 0], k: [0.05, 0.1, 0.05], c: 0x8a6a4a }, { s: 'torus', p: [0, 0.38, -0.2], r: [0, 0, Math.PI / 2], k: 0.26, tube: 0.07, arc: Math.PI, c: 0x7a4a28 }); break;
    case 'scholar': P.push({ s: 'cone', p: [0, 0.3, 0], k: [0.27, 0.56, 0.27], c: C }, { s: 'torus', p: [-0.085, 0.7, 0.24], k: 0.05, tube: 0.2, c: 0x2a2a2a }, { s: 'torus', p: [0.085, 0.7, 0.24], k: 0.05, tube: 0.2, c: 0x2a2a2a }, { s: 'box', p: [-0.25, 0.38, 0.12], r: [0.3, 0, 0], k: [0.16, 0.2, 0.05], c: 0xa03a3a }); break;
    case 'cook': P.push({ s: 'cyl', p: [0, 0.98, -0.02], k: [0.18, 0.2, 0.18], c: 0xffffff }, { s: 'sphere', p: [0, 1.12, -0.02], k: [0.22, 0.1, 0.22], c: 0xffffff }, { s: 'box', p: [0, 0.3, 0.17], k: [0.28, 0.3, 0.05], c: 0xffffff }); break;
    default: P.push({ s: 'cone', p: [0, 1.0, -0.03], k: [0.27, 0.42, 0.27], c: 0x8a7ab0 }, { s: 'oct', p: [0.27, 0.52, 0.1], k: 0.07, c: 0xb45aff });
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
