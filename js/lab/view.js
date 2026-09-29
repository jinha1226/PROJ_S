import * as K from '../render/diorama.js';
import { heroSpec } from '../render/hero-doll.js';
import { dollSpecBase } from '../render/dolls.js';
import { walls } from './space.js';

const { THREE } = K;
const palette = { floor: 0x34313b, floor2: 0x3e3943, wall: 0x74717b, wall2: 0x5c5864, void: 0x08070c, grassFloor: 0x3b523c, waterFloor: 0x23445f, dim: 0.5 };

export class LabView {
  constructor(container, onTap) {
    this.dio = K.createDiorama(container, { preset: 'dungeon' });
    this.dio.rig.tilesAcross = 16.5;
    this.dio.rig.fit(container.clientWidth / container.clientHeight);
    this.dio.rig.focusT.set(7.5, 0, 7.5); this.dio.rig.snap();
    this.dio.rig.onTap = (sx, sy) => {
      const p = this.dio.pickGround(sx, sy);
      if (p && p.x >= 1 && p.x <= 14 && p.y >= 1 && p.y <= 14) onTap(p);
    };
    const surf = new Uint8Array(256);
    for (let y = 7; y <= 9; y++) for (let x = 7; x <= 9; x++) surf[y * 16 + x] = K.SURF.WATER;
    for (let y = 2; y <= 5; y++) for (let x = 8; x <= 12; x++) surf[y * 16 + x] = K.SURF.GRASS;
    this.grid = new K.GridView(this.dio.scene, { w: 16, h: 16, kind: (i) => {
      const x = i % 16, y = (i / 16) | 0;
      return x === 0 || y === 0 || x === 15 || y === 15 || walls.has(`${x},${y}`) ? 'wall' : 'floor';
    }, palette, wallH: 1.2 });
    this.grid.setTerrain({ surf }); this.dio.grid = this.grid;
    this.actors = new Map(); this.areas = [];
    this.dio.onFrame = (dt) => this.onFrame?.(dt);
    const light = new THREE.PointLight(0xffbe78, 13, 8); light.position.set(3, 2, 8); this.dio.scene.add(light);
  }
  makeActor(u) {
    const sp = u.role === 'boss' ? dollSpecBase({ type: 'charger' }) : u.role === 'add' ? dollSpecBase({ type: 'goblin' }) : heroSpec({});
    const scale = u.role === 'boss' ? 2.1 : u.role === 'add' ? 0.85 : 1.15;
    const doll = K.doll(sp.parts, { scale, gloss: 0.28 });
    const ring = new THREE.Mesh(new THREE.RingGeometry(u.role === 'boss' ? 0.68 : 0.34, u.role === 'boss' ? 0.76 : 0.41, 32).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ color: u.color, side: THREE.DoubleSide, transparent: true, opacity: 0.9 }));
    ring.position.y = 0.08;
    doll.root.add(ring);
    this.dio.scene.add(doll.root);
    const actor = { doll, ring }; this.actors.set(u.id, actor); return actor;
  }
  clearAreas() {
    for (const m of this.areas) { this.dio.scene.remove(m); m.geometry.dispose(); m.material.dispose(); }
    this.areas.length = 0;
  }
  circle(x, y, r, color) {
    const mesh = new THREE.Mesh(new THREE.CircleGeometry(r, 32).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.36, depthWrite: false, side: THREE.DoubleSide }));
    mesh.position.set(x, 0.09, y); this.dio.scene.add(mesh); this.areas.push(mesh);
  }
  show(battle) {
    for (const u of battle.units) {
      const a = this.actors.get(u.id) || this.makeActor(u);
      a.doll.root.visible = u.hp > 0;
      a.doll.root.position.set(u.x, 0, u.y);
      a.ring.material.opacity = u.hp > 0 ? 0.9 : 0;
    }
    if (this.tele === battle.tele) return;
    this.tele = battle.tele; this.clearAreas();
    const t = battle.tele;
    if (!t) return;
    if (t.type === 'scatter') for (const at of t.at) this.circle(at.x, at.y, 1.1, 0xf34750);
    else {
      const target = battle.party.find((u) => u.id === t.target) || battle.hero;
      const bx = battle.boss.x, by = battle.boss.y;
      for (let y = Math.max(1, Math.floor(by - 3)); y <= Math.min(14, Math.ceil(by + 3)); y++)
        for (let x = Math.max(1, Math.floor(bx - 3)); x <= Math.min(14, Math.ceil(bx + 3)); x++)
          if (battle.inDanger({ x, y }, t)) this.circle(x, y, 0.48, 0xf34750);
      this.circle(target.x, target.y, 0.35, 0xffbb6e);
    }
  }
}
