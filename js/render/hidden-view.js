import { G, XY } from '../core/state.js';
import { T_STAIRS, T_WALL } from '../data/terrain.js';
import { W3 } from './common.js';
import * as K from './diorama.js';
import { propDoll } from './dolls.js';
import { ports } from './ports.js';
import { Sfx } from './sfx.js';
import { View } from './view.js';

/* ---------- 숨은 방 입구 · 기록 · 귀환 빛 ---------- */
const BLOCK_PARTS = {
  thorn: () => { const P = []; for (let k = 0; k < 9; k++) { const a = k * 0.7, r = 0.18 + (k % 3) * 0.1; P.push({ s: 'cone', p: [Math.cos(a) * r, 0.35 + (k % 4) * 0.18, Math.sin(a) * r * 0.5], r: [Math.sin(a) * 0.9, 0, Math.cos(a) * 0.9], k: [0.05, 0.55, 0.05], c: 0x3a2e24 }); } P.push({ s: 'ico', detail: 1, p: [0, 0.55, 0], k: [0.42, 0.55, 0.3], c: 0x2e3a26 }); return P; },
  water: () => [{ s: 'cyl', p: [-0.44, 0.35, 0], k: [0.06, 0.7, 0.06], c: 0x4a4a52 }, { s: 'cyl', p: [0.44, 0.35, 0], k: [0.06, 0.7, 0.06], c: 0x4a4a52 }, { s: 'box', p: [0, 0.02, 0], k: [0.9, 0.02, 0.9], c: 0x0c1a2e }],
  gate: () => { const P = [{ s: 'box', p: [0, 1.15, 0], k: [1.0, 0.14, 0.26], c: 0x3a3430 }]; for (let k = -2; k <= 2; k++) P.push({ s: 'box', p: [k * 0.18, 0.55, 0], k: [0.05, 1.1, 0.05], c: 0x6a5a4a }); P.push({ s: 'box', p: [0, 0.35, 0], k: [0.9, 0.05, 0.05], c: 0x6a5a4a }, { s: 'box', p: [0, 0.75, 0], k: [0.9, 0.05, 0.05], c: 0x6a5a4a }, { s: 'torus', p: [0.38, 1.3, 0.1], k: 0.14, tube: 0.05, c: 0x7a6a50 }); return P; },
  rubble: () => { const P = []; for (let k = 0; k < 8; k++) P.push({ s: 'ico', p: [((k * 37) % 7) / 7 - 0.45, 0.15 + (k % 3) * 0.22, ((k * 53) % 5) / 5 - 0.4], k: [0.2 + (k % 3) * 0.06, 0.16, 0.2], c: k % 2 ? 0x5a5650 : 0x4a4640 }); return P; },
};

Object.assign(View, {
  blocks: new Map(),
  syncBlocks() {
    for (const m of this.blocks.values()) this.dio.scene.remove(m.root); this.blocks.clear();
    if (!G.block) return;
    for (const [i, kind] of G.block) { const [x, y] = XY(i), d = propDoll(BLOCK_PARTS[kind](), 1); d.root.position.set(x, 0, y); d.root.visible = !!(this.seen && this.seen[i]); this.dio.scene.add(d.root); this.blocks.set(i, d); }
  },
  /** 벽이 바닥이 되면 격자만 다시 짓는다(인형·물건은 그대로) */
  rebuildGrid() {
    this.grid?.dispose();
    this.grid = new K.GridView(this.dio.scene, { w: G.W, h: G.H, kind: this.tileKind, palette: G.theme.pal, wallH: 1.2 });
    this.dio.grid = this.grid;
    this.grid.setTerrain({ surf: G.surf, fire: G.fire, cloud: G.cloud, cloudT: G.cloudT });
    if (this.vis) this.applyVis(this.vis, this.seen);
  },
  storyOn(type, d) {
    const D = this.dio;
    switch (type) {
      case 'hiddenOpen': {
        const i = d.y * G.W + d.x, m = this.blocks.get(i); if (m) { D.scene.remove(m.root); this.blocks.delete(i); }
        const P = W3(d.x, d.y, 0.5), col = { thorn: 0xff8a3a, water: 0x9fe2ff, gate: 0xffe14a, rubble: 0xb0a898 }[d.kind];
        D.puffs.emit({ pos: P, n: 24, color: d.kind === 'thorn' ? 0x3a3028 : 0x9a9488, speed: 2.2, grav: 0, life: 0.9, size: 0.4, grow: 1 });
        D.sparks.emit({ pos: P, n: 30, color: col, color2: 0xffffff, speed: 3, up: 1.5, grav: 0.5, life: 0.7, size: 0.12 });
        D.rig.shake(0.35); D.pool.flash(P, col, 40, 0.6, 6); Sfx.play(d.kind === 'rubble' ? 'blunt' : d.kind === 'gate' ? 'zap' : d.kind === 'water' ? 'freeze' : 'fire');
        this.rebuildGrid(); return true;
      }
      case 'lore': ports.Town.loreInfo?.(d.zone); Sfx.chime?.(3); return true;
      case 'recallGlow': {
        const ev = this.evs.get(0); if (!ev) return true;
        D.fx.ring(W3(ev.cur.x, ev.cur.z, 0.05), 0xffd890, 1.4, 0.2, 1.1);
        D.sparks.emit({ pos: W3(ev.cur.x, ev.cur.z, 0.2), n: 40, color: 0xffe0a0, color2: 0xffffff, speed: 0.6, up: 2.2, grav: 0, life: 1.1, size: 0.1, spread: 0.6 });
        D.pool.flash(W3(ev.cur.x, ev.cur.z), 0xffd890, 50, 1.4, 5); Sfx.play('tele'); return true;
      }
      default: return false;
    }
  },
  tileKind: (i) => (G.block && G.block.has(i) ? 'floor' : G.tile[i] === T_WALL ? 'wall' : G.tile[i] === T_STAIRS ? 'void' : 'floor'),
});
