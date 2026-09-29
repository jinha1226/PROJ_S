import * as THREE from 'three';
import { G, I, XY } from '../core/state.js';
import { T_FLOOR, T_WALL } from '../data/terrain.js';
import { D4 } from '../util/grid.js';
import { GLOW_TEX, propDoll } from './dolls.js';
import { View } from './view.js';

/* ---------- 벽 촛대: 칠흑 속 몇 안 되는 빛. 실제 광원 없이 불꽃 + 번짐만(성능) ---------- */
const hash = (n) => { const s = Math.sin(n * 91.7 + 13.1) * 43758.5453; return s - Math.floor(s); };
Object.assign(View, {
  sconces: [],
  syncSconces() {
    for (const s of this.sconces) this.dio.scene.remove(s.g); this.sconces = [];
    const cand = [];
    for (let i = 0; i < G.W * G.H; i++) {
      if (G.tile[i] !== T_WALL || (G.block && G.block.has(i))) continue;
      const [x, y] = XY(i);
      for (const [dx, dy] of D4) { const nx = x + dx, ny = y + dy; if (nx < 0 || ny < 0 || nx >= G.W || ny >= G.H) continue; const j = I(nx, ny); if (G.tile[j] === T_FLOOR && G.room[j] >= 0) { cand.push([i, dx, dy]); break; } }
    }
    const want = Math.min(6, Math.floor(cand.length / 14));
    for (let k = 0; k < want; k++) {
      const [i, dx, dy] = cand[Math.floor(hash(k * 7 + G.floor * 31 + G.zone) * cand.length)], [x, y] = XY(i), g = new THREE.Group();
      const d = propDoll([{ s: 'box', p: [0, 0.75, 0], k: [0.06, 0.18, 0.06], c: 0x2a2624 }, { s: 'cyl', p: [0, 0.86, 0.08], k: [0.08, 0.03, 0.08], c: 0x2a2624 }, { s: 'cyl', p: [0, 0.94, 0.08], k: [0.035, 0.12, 0.035], c: 0xc8bca0 }], 1);
      const fl = new THREE.Mesh(new THREE.ConeGeometry(0.04, 0.12, 6).translate(0, 0.06, 0), new THREE.MeshBasicMaterial({ color: new THREE.Color(2.6, 1.3, 0.35), toneMapped: false })); fl.position.set(0, 1.0, 0.08);
      const halo = new THREE.Sprite(new THREE.SpriteMaterial({ map: GLOW_TEX, color: 0xff9a40, blending: THREE.AdditiveBlending, transparent: true, depthWrite: false, opacity: 0.5 })); halo.scale.setScalar(1.3); halo.position.set(0, 1.0, 0.1);
      g.add(d.root, fl, halo); g.position.set(x + dx * 0.5, 0, y + dy * 0.5); g.rotation.y = Math.atan2(dx, dy);
      g.visible = false; this.dio.scene.add(g); this.sconces.push({ g, i, fl, halo, ph: hash(k) * 6 });
    }
  },
  sconceFrame(time) {
    for (const s of this.sconces) {
      s.g.visible = !!(this.seen && this.seen[s.i]); if (!s.g.visible) continue;
      const f = 1 + Math.sin(time * 11 + s.ph) * 0.15 + Math.sin(time * 23 + s.ph) * 0.08; s.fl.scale.set(1, f, 1); s.halo.material.opacity = 0.35 + f * 0.15;
    }
  },
});
