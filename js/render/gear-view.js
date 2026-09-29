import * as THREE from 'three';
import * as K from './diorama.js';
import { G, I, XY } from '../core/state.js';
import { GEAR_BASES, MAT_COLOR, RARITY, weaponId } from '../data/gear.js';
import { gearName } from '../core/gear.js';
import { W3, _tv } from './common.js';
import { weaponDoll } from './dolls.js';
import { ports } from './ports.js';
import { Sfx } from './sfx.js';
import { View } from './view.js';

/* ---------- 바닥 장비(등급색 빛기둥 · 이름표) · 상자 · 장비 연출 ---------- */
const BEAM_H = { magic: 1.1, rare: 2.0, legend: 3.6 };
function gearProp(it) {
  const B = GEAR_BASES[it.base], k = B.slot, c = B.mat ? MAT_COLOR[B.mat] : 0xc8c8d0;
  if (B.weapon) { const d = weaponDoll(weaponId(it)); d.root.rotation.set(Math.PI / 2, 0, 0.7); d.root.position.set(0, 0.07, -0.2); const g = new THREE.Group(); g.add(d.root); return g; }
  const P = {
    body: [{ s: 'sphere', p: [0, 0.16, 0], k: [0.2, 0.16, 0.14], c }, { s: 'sphere', p: [-0.17, 0.22, 0], k: 0.07, c }, { s: 'sphere', p: [0.17, 0.22, 0], k: 0.07, c }],
    head: [{ s: 'sphere', p: [0, 0.1, 0], k: [0.18, 0.13, 0.18], c }, ...(B.mat === 'plate' ? [{ s: 'cone', p: [-0.17, 0.2, 0], r: [0, 0, 0.7], k: [0.04, 0.16, 0.04], c: 0xf2ead8 }, { s: 'cone', p: [0.17, 0.2, 0], r: [0, 0, -0.7], k: [0.04, 0.16, 0.04], c: 0xf2ead8 }] : [])],
    hands: [{ s: 'sphere', p: [-0.09, 0.08, 0], k: 0.08, c }, { s: 'sphere', p: [0.09, 0.08, 0], k: 0.08, c }],
    feet: [{ s: 'box', p: [-0.08, 0.07, 0], k: [0.1, 0.14, 0.18], c }, { s: 'box', p: [0.08, 0.07, 0], k: [0.1, 0.14, 0.18], c }],
    off: it.base === 'shield' ? [{ s: 'cyl', p: [0, 0.05, 0], k: [0.2, 0.05, 0.2], c: 0x9a6a3e }, { s: 'torus', p: [0, 0.08, 0], r: [Math.PI / 2, 0, 0], k: 0.19, tube: 0.12, c: RARITY[it.rarity].hex }] : [{ s: 'cyl', p: [0, 0.05, 0], r: [0, 0, Math.PI / 2], k: [0.03, 0.34, 0.03], c: 0x5a3a22 }, { s: 'sphere', p: [0.18, 0.05, 0], k: 0.06, c: 0xff8a2a }],
    neck: [{ s: 'torus', p: [0, 0.03, 0], r: [Math.PI / 2, 0, 0], k: 0.13, tube: 0.12, c: 0xd8b04a }, { s: 'oct', p: [0, 0.07, 0.13], k: 0.05, c: 0xc07aff }],
    ring: [{ s: 'torus', p: [0, 0.09, 0], k: 0.07, tube: 0.25, c: 0xffd35a }, { s: 'oct', p: [0, 0.17, 0], k: 0.035, c: 0x7fdcff }],
  }[k];
  return K.doll(P, { gloss: 1.2 }).root;
}
function makeGearMesh(it) {
  const g = new THREE.Group(), prop = gearProp(it); g.add(prop);
  const h = BEAM_H[it.rarity];
  if (h) {
    const beam = new THREE.Mesh(new THREE.CylinderGeometry(0.12, 0.22, h, 12, 1, true).translate(0, h / 2, 0), new THREE.MeshBasicMaterial({ color: RARITY[it.rarity].hex, transparent: true, opacity: 0.35, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide }));
    g.add(beam); g.userData.beam = beam;
  }
  g.userData.prop = prop; g.userData.ph = Math.random() * 6; g.userData.it = it;
  const tag = document.createElement('div'); tag.className = 'gtag'; tag.style.color = RARITY[it.rarity].css; tag.textContent = gearName(it); tag.style.display = 'none';
  View.labelRoot.appendChild(tag); g.userData.tag = tag;
  return g;
}
function chestModel() {
  const g = new THREE.Group();
  const base = K.doll([{ s: 'box', p: [0, 0.18, 0], k: [0.62, 0.36, 0.44], c: 0x8a5a32 }, { s: 'box', p: [0, 0.18, 0.225], k: [0.64, 0.06, 0.02], c: 0xd4a840 }, { s: 'box', p: [0, 0.3, 0.23], k: [0.1, 0.1, 0.03], c: 0xffd35a }], { gloss: 0.8 });
  const lidPivot = new THREE.Group(); lidPivot.position.set(0, 0.36, -0.22);
  const lid = K.doll([{ s: 'box', p: [0, 0.07, 0.22], k: [0.64, 0.14, 0.46], c: 0x9a6a3e }, { s: 'box', p: [0, 0.07, 0.22], k: [0.66, 0.05, 0.1], c: 0xd4a840 }], { gloss: 0.8 });
  lidPivot.add(lid.root); g.add(base.root, lidPivot); g.userData.lid = lidPivot;
  return g;
}

Object.assign(View, {
  gearMeshes: new Map(), chestMeshes: new Map(),
  clearGear() {
    for (const g of this.gearMeshes.values()) { this.dio.scene.remove(g); g.userData.tag.remove(); } this.gearMeshes.clear();
    for (const c of this.chestMeshes.values()) this.dio.scene.remove(c); this.chestMeshes.clear();
  },
  syncGear(list) {
    const keep = new Set(list.map(([i]) => i));
    for (const [i, g] of this.gearMeshes) if (!keep.has(i)) { this.dio.scene.remove(g); g.userData.tag.remove(); this.gearMeshes.delete(i); }
    for (const [i, it] of list) if (!this.gearMeshes.has(i)) { const g = makeGearMesh(it), [x, y] = XY(i); g.position.set(x, 0, y); this.dio.scene.add(g); this.gearMeshes.set(i, g); }
  },
  syncChests() {
    for (const [i, c] of G.chests) { if (this.chestMeshes.has(i)) continue; const m = chestModel(), [x, y] = XY(i); m.position.set(x, 0, y); m.rotation.y = (i % 4) * 0.15 - 0.2; if (c.open) m.userData.lid.rotation.x = -1.9; this.dio.scene.add(m); this.chestMeshes.set(i, m); }
  },
  gearFrame(sdt, time) {
    const s = {}, p = G.player;
    for (const [i, g] of this.gearMeshes) {
      const seen = !!(this.seen && this.seen[i]), u = g.userData; g.visible = seen || !!u.drop;
      if (u.drop) {
        const dr = u.drop; dr.t = Math.min(1, dr.t + sdt / 0.8); const k = dr.t, m = Math.min(1, k / 0.55);
        g.position.set(dr.fx + (dr.tx - dr.fx) * m, Math.abs(Math.sin(Math.PI * 3 * Math.sqrt(k))) * 0.9 * Math.pow(1 - k, 1.5), dr.fy + (dr.ty - dr.fy) * m);
        if (k >= 1) u.drop = null;
      } else u.prop.position.y = 0.02 + Math.abs(Math.sin(time * 2 + u.ph)) * 0.05;
      u.prop.rotation.y = time * 0.8 + u.ph;
      if (u.beam) u.beam.material.opacity = 0.25 + 0.15 * Math.sin(time * 3 + u.ph) + (u.it.rarity === 'legend' ? 0.2 : 0);
      const [x, y] = XY(i), near = g.visible && Math.max(Math.abs(x - p.x), Math.abs(y - p.y)) <= 3;
      if (!near) { if (u.tag.style.display !== 'none') u.tag.style.display = 'none'; continue; }
      u.tag.style.display = ''; this.dio.labels.toScreen(_tv.set(g.position.x, 0.75, g.position.z), s);
      u.tag.style.transform = `translate(${s.x.toFixed(1)}px,${s.y.toFixed(1)}px) translate(-50%,-100%)`;
    }
    for (const [i, c] of this.chestMeshes) { c.visible = !!(this.seen && this.seen[i]); const L = c.userData.lid; if (L.userData.open && L.rotation.x > -1.9) L.rotation.x -= sdt * 6; }
  },
  /** 장비 사건 — 처리했으면 true */
  gearOn(type, d) {
    const D = this.dio, pe = this.evs.get(0);
    switch (type) {
      case 'gears': this.syncGear(d); return true;
      case 'gearDrop': {
        const i = I(d.x, d.y); let g = this.gearMeshes.get(i);
        if (!g) { g = makeGearMesh(d.it); this.dio.scene.add(g); this.gearMeshes.set(i, g); }
        g.userData.drop = { t: 0, fx: d.from[0], fy: d.from[1], tx: d.x, ty: d.y };
        if (d.it.legend) { ports.UI.legendFlash(); D.pool.flash(W3(d.x, d.y), 0xff8a2a, 90, 0.8, 8); D.rig.shake(0.3); Sfx.play('crit'); }
        else if (d.it.rarity !== 'common') Sfx.play('gem');
        return true;
      }
      case 'chest': { const c = this.chestMeshes.get(I(d.x, d.y)); if (c) c.userData.lid.userData.open = true; D.sparks.emit({ pos: W3(d.x, d.y, 0.5), n: 26, color: 0xffd35a, color2: 0xffffff, speed: 2.5, up: 2, grav: -2, life: 0.7, size: 0.13 }); D.pool.flash(W3(d.x, d.y), 0xffd070, 40, 0.5, 5); Sfx.play('door'); return true; }
      case 'equip': {
        if (pe) { pe.redress({ type: 'hero', eq: d.eq }); this.setWeapon(weaponId(d.eq.weapon)); D.sparks.emit({ pos: W3(pe.cur.x, pe.cur.z, 0.6), n: 22, color: 0xffffff, color2: 0xffd84a, speed: 1.6, up: 1.4, grav: 0, life: 0.6, size: 0.12, spread: 0.4 }); }
        ports.UI.renderWeapon(); Sfx.play('pick'); return true;
      }
      case 'dodge': if (pe) { pe.lunge(Math.random() < 0.5 ? 1 : -1, 0, 0.3); D.labels.pop(W3(pe.cur.x, pe.cur.z, 1.3), '회피!', { color: '#9fe2ff', cls: 'word', vx: 0 }); Sfx.play('swing'); } return true;
      case 'block': if (pe) { pe.bubbleHit = 1; D.labels.pop(W3(pe.cur.x, pe.cur.z, 1.3), '막기!', { color: '#ffd08a', cls: 'word', vx: 0 }); D.sparks.emit({ pos: W3(pe.cur.x, pe.cur.z, 0.5), n: 14, color: 0xffe0a0, speed: 3.5, life: 0.3, size: 0.1 }); Sfx.play('blunt'); } return true;
      case 'miss': D.labels.pop(W3(d.x, d.y, 1.0), '빗나감', { color: '#c8ccd8', cls: 'word', vx: 0 }); return true;
      case 'immune': if (pe) D.labels.pop(W3(pe.cur.x, pe.cur.z, 1.3), '화상 면역', { color: '#ffb070', cls: 'word', vx: 0 }); return true;
      case 'bloodBurst': D.sparks.emit({ pos: W3(d.x, d.y, 0.5), n: 34, color: 0xff1a2a, color2: 0x8a0010, speed: 4, up: 1, grav: -6, life: 0.6, size: 0.14 }); D.fx.ring(W3(d.x, d.y), 0xff2a3a, 0.2, 1.6, 0.4); return true;
      default: return false;
    }
  },
});
