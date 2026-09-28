import * as THREE from 'three';
import * as K from './diorama.js';
import { G, I } from '../core/state.js';
import { catOf } from '../data/enemies.js';
import { _w, easeInOut, easeOut } from './common.js';
import { dollSpec } from './dolls.js';
import { View } from './view.js';

export class EntView {
  constructor(e) {
    this.id = e.id; this.type = e.type;
    const sp = dollSpec(e);
    this.d = K.doll(sp.parts, { scale: sp.scale * 1.3, gloss: 0.75 });
    this.h = sp.h * sp.scale * 1.3; this.col = sp.col;
    this.extra = sp.extra ? sp.extra(this.d) : {};
    View.dio.scene.add(this.d.root);
    this.cur = new THREE.Vector3(e.x, 0, e.y); this.from = this.cur.clone(); this.to = this.cur.clone();
    this.t = 1; this.dur = 0.11; this.hop = 0; this.mk = 'step'; this.lt = 1; this.ld = [0, 0]; this.la = 0;
    this.yaw = Math.atan2(e.face[0], e.face[1]); this.yawT = this.yaw;
    this.sq = 0; this.sqv = 0; this.flash = 0; this.jolt = new THREE.Vector3();
    this.st = { ...e.st }; this.visible = e.id === 0 || !!G.vis[I(e.x, e.y)]; this.dead = false; this.gone = false; this.deadT = 0;
    this.hp = e.hp; this.max = e.max; this.phase = Math.random() * 6; this.acc = 0; this.casting = false; this.winding = false;
    this.tag = document.createElement('div'); this.tag.className = 'tag'; this.tag.style.display = 'none'; this.tagShown = false;
    this.tag.innerHTML = e.id === 0 ? '<div class="ico"></div>' : '<div class="ico"></div><div class="hpb"><i></i></div>';
    this.tagIco = this.tag.firstChild; this.tagHp = e.id === 0 ? null : this.tag.lastChild.firstChild; this.tagTxt = null; this.tagW = -1;
    View.labelRoot.appendChild(this.tag);
    this.cat = e.id === 0 || e.ally ? null : catOf(e); this.boss = !!e.boss; this.ally = !!e.ally; this.swing = null;
    if (e.ally && !e.npc) { this.d.mat.transparent = true; this.d.mat.opacity = 0.6; this.baseEm = [0.28, 0.12, 0.45]; }
    this.d.root.position.copy(this.cur); this.d.root.rotation.y = this.yaw; this.d.root.visible = this.visible;
  }
  moveTo(x, y, dur, hop, kind) {
    this.from.copy(this.cur); this.to.set(x, 0, y); this.t = 0; this.dur = Math.max(0.02, dur / 1000); this.hop = hop; this.mk = kind;
    const dx = x - this.from.x, dz = y - this.from.z;
    if (kind !== 'push' && kind !== 'slide' && kind !== 'tele' && Math.abs(dx) + Math.abs(dz) > 0.01) this.yawT = Math.atan2(dx, dz);
    if (kind === 'tele') { this.cur.set(x, 0, y); this.t = 1; }
  }
  lunge(dx, dy, amt = 0.36) { this.ld = [dx, dy]; this.la = amt; this.lt = 0; if (dx || dy) this.yawT = Math.atan2(dx, dy); this.sqv += 2.5; }
  update(dt, time) {
    const r = this.d.root;
    if (this.t < 1) {
      this.t = Math.min(1, this.t + dt / this.dur);
      this.cur.lerpVectors(this.from, this.to, this.mk === 'step' ? easeInOut(this.t) : easeOut(this.t));
      if (this.t >= 1 && this.hop > 0.08) this.sqv -= 3.2;
    }
    const hopY = this.t < 1 ? Math.sin(Math.PI * this.t) * this.hop : 0;
    let lx = 0, lz = 0;
    if (this.lt < 1) { this.lt = Math.min(1, this.lt + dt / 0.17); const s = Math.sin(Math.PI * this.lt); lx = this.ld[0] * s * this.la; lz = this.ld[1] * s * this.la; }
    const a = -420 * this.sq - 17 * this.sqv; this.sqv += a * dt; this.sq += this.sqv * dt;
    this.jolt.multiplyScalar(Math.exp(-dt * 11));
    let dy = this.yawT - this.yaw; while (dy > Math.PI) dy -= Math.PI * 2; while (dy < -Math.PI) dy += Math.PI * 2; this.yaw += dy * Math.min(1, dt * 16);
    const sy = View.grid ? View.grid.surfaceY(Math.round(this.cur.x), Math.round(this.cur.z)) : 0;
    const frozen = this.st.frozen > 0;
    let wx = 0;
    if (this.winding && !frozen) wx = Math.sin(time * 40) * 0.035;
    r.position.set(this.cur.x + this.jolt.x + lx + wx, sy + hopY + this.jolt.y, this.cur.z + this.jolt.z + lz);
    r.rotation.y = this.yaw;
    const sq = frozen ? 0 : this.sq;
    this.d.pivot.scale.set(1 - sq * 0.5, 1 + sq, 1 - sq * 0.5);
    this.d.pivot.position.y = frozen || this.dead ? 0 : Math.abs(Math.sin(time * 3.2 + this.phase)) * 0.02;
    if (this.id !== 0) { const k = Math.min(1, dt * 8), fr = this.st.frac > 0 && !this.dead; this.d.pivot.rotation.z += ((fr ? 0.32 : 0) - this.d.pivot.rotation.z) * k; this.d.pivot.rotation.x += ((fr ? 0.14 : 0) - this.d.pivot.rotation.x) * k; }
    this.flash = Math.max(0, this.flash - dt * 7);
    const em = this.d.mat.emissive; em.setRGB(...(this.baseEm || [0, 0, 0]));
    if (frozen) em.setRGB(0.1, 0.24, 0.36);
    else if (this.st.burn > 0) em.setRGB(0.28 + 0.14 * Math.sin(time * 14), 0.08, 0);
    else if (this.st.poison > 0) em.setRGB(0.03, 0.13 + 0.06 * Math.sin(time * 6), 0.02);
    if (this.flash > 0) em.addScalar(this.flash * 1.7);
    this.statusFx(dt, time, frozen);
    if (this.dead) {
      this.deadT += dt; const k = this.deadT / 0.34;
      const s = k < 0.3 ? 1 + k * 0.8 : Math.max(0, 1.24 * (1 - (k - 0.3) / 0.7));
      this.d.pivot.scale.set(s * 1.1, s * (k < 0.3 ? 0.75 : 1.05), s * 1.1); r.rotation.y += dt * 12;
      if (k >= 1) { r.visible = false; this.gone = true; }
    } else r.visible = this.visible;
    this.extra.update?.(dt, time, this);
    if (this.extra.wh) this.animWeapon(dt);
    if (this.id === 0) this.shieldFx(dt, time);
  }
  animWeapon(dt) {
    const wh = this.extra.wh; let rx = 0.5, ry = 0, pz = 0.06;
    if (this.swing) {
      const sw = this.swing; sw.t = Math.min(1, sw.t + dt / 0.22); const k = sw.t, e = Math.sin(Math.PI * k);
      if (sw.form === 'slash') { ry = 1.4 - 2.8 * easeOut(k); rx = 0.5 + 0.9 * e; }
      else if (sw.form === 'blunt') rx = k < 0.35 ? 0.5 - 1.7 * (k / 0.35) : -1.2 + 3.1 * easeOut((k - 0.35) / 0.65);
      else { rx = 0.5 + 1.1 * Math.min(1, k * 3); pz = 0.06 + 0.4 * e; }
      if (k >= 1) this.swing = null;
    }
    wh.rotation.set(rx, ry, 0); wh.position.z = pz;
  }
  shieldFx(dt, time) {
    const v = View.shield || 0;
    if (v > 0 && !this.bubble) {
      this.bubble = new THREE.Mesh(new THREE.SphereGeometry(0.62, 20, 14), K.toon({ color: 0x9fd8ff, gloss: 1.5, transparent: true, opacity: 0.22, emissive: 0x1a4a7a }));
      this.bubble.position.y = 0.5; this.d.root.add(this.bubble); this.bubbleHit = 0;
    }
    if (!this.bubble) return;
    this.bubble.visible = v > 0; this.bubbleHit = Math.max(0, this.bubbleHit - dt * 4);
    const s = 1 + Math.sin(time * 3) * 0.03 + this.bubbleHit * 0.25; this.bubble.scale.setScalar(s * (0.85 + Math.min(v, 8) * 0.03));
    this.bubble.material.opacity = 0.16 + this.bubbleHit * 0.4;
  }
  statusFx(dt, time, frozen) {
    if (frozen && !this.ice) {
      this.ice = new THREE.Group();
      const g = new THREE.BoxGeometry(0.72, this.h * 0.95 + 0.1, 0.72).translate(0, (this.h * 0.95 + 0.1) / 2, 0);
      const m = new THREE.Mesh(g, K.toon({ color: 0xbfeaff, gloss: 1.4, transparent: true, opacity: 0.5, emissive: 0x16405a }));
      const ol = new THREE.Mesh(K.outlineGeo(g), K.outlineMaterial({ width: 0.025, color: 0x1a4a6a }));
      this.ice.add(m, ol); this.d.root.add(this.ice);
    }
    if (this.ice) { this.ice.visible = frozen; this.ice.rotation.y = -this.yaw + 0.3; }
    const stun = this.st.stun > 0 && !frozen && !this.dead;
    if (stun && !this.stars) {
      this.stars = new THREE.Group();
      for (let k = 0; k < 3; k++) { const s = new THREE.Mesh(new THREE.OctahedronGeometry(0.07), new THREE.MeshBasicMaterial({ color: new THREE.Color(2.2, 1.9, 0.4) })); s.position.set(Math.cos(k * 2.09) * 0.28, 0, Math.sin(k * 2.09) * 0.28); this.stars.add(s); }
      this.stars.position.y = this.h + 0.1; this.d.root.add(this.stars);
    }
    if (this.stars) { this.stars.visible = stun; this.stars.rotation.y = time * 5; }
    const vital = this.st.vital > 0 && !this.dead;
    if (vital && !this.vmark) {
      this.vmark = new THREE.Group();
      const m = new THREE.Mesh(new THREE.OctahedronGeometry(0.075), new THREE.MeshBasicMaterial({ color: new THREE.Color(2.8, 2.4, 1.1) }));
      const ring = new THREE.Mesh(new THREE.RingGeometry(0.1, 0.13, 20), new THREE.MeshBasicMaterial({ color: new THREE.Color(2.4, 1.8, 0.6), transparent: true, side: THREE.DoubleSide, blending: THREE.AdditiveBlending, depthWrite: false }));
      this.vmark.add(m, ring); this.vmark.position.set(0.06, this.h * 0.45, 0.3 * (this.h / 1.2)); this.d.root.add(this.vmark);
    }
    if (this.vmark) { this.vmark.visible = vital; const s = 1 + Math.sin(time * 8) * 0.25; this.vmark.scale.setScalar(s); this.vmark.children[0].rotation.y = time * 4; this.vmark.children[1].lookAt(View.dio.camera.position); }
    if (!this.d.root.visible || this.dead) return;
    this.acc += dt; if (this.acc < 0.09) return; this.acc = 0;
    const p = this.d.root.position, D = View.dio;
    if (this.st.burn > 0) D.sparks.emit({ pos: _w.set(p.x, p.y + this.h * 0.5, p.z), n: 2, color: 0xff8a2a, color2: 0xffe36a, speed: 0.6, up: 1.6, grav: 1, life: 0.5, size: 0.2, spread: 0.3 });
    if (this.st.poison > 0 && Math.random() < 0.5) D.puffs.emit({ pos: _w.set(p.x, p.y + this.h * 0.8, p.z), n: 1, color: 0x79e05a, color2: 0x3a8a2a, speed: 0.2, up: 0.8, grav: 0, life: 0.8, size: 0.16, spread: 0.3 });
    if (this.st.bleed > 0 && Math.random() < 0.8) { D.sparks.emit({ pos: _w.set(p.x + (Math.random() - 0.5) * 0.3, p.y + this.h * 0.55, p.z + (Math.random() - 0.5) * 0.3), n: 1, color: 0xff1a2a, color2: 0x9a0010, speed: 0.2, grav: -9, life: 0.5, size: 0.1, drag: 0 }); if (Math.random() < 0.25) D.puffs.emit({ pos: _w.set(p.x + (Math.random() - 0.5) * 0.5, 0.03, p.z + (Math.random() - 0.5) * 0.5), n: 1, color: 0x8a0a14, speed: 0, grav: 0, life: 1.6, size: 0.22, flat: true }); }
    if (this.st.wet > 0 && !frozen && Math.random() < 0.4) D.sparks.emit({ pos: _w.set(p.x + (Math.random() - 0.5) * 0.4, p.y + this.h * 0.6, p.z + (Math.random() - 0.5) * 0.4), n: 1, color: 0x5aa8ff, speed: 0.1, grav: -7, life: 0.45, size: 0.07, drag: 0 });
  }
  dispose() {
    View.dio.scene.remove(this.d.root); this.tag.remove();
    this.d.root.traverse((o) => { if (o.geometry) o.geometry.dispose(); if (o.material && o.material !== this.d.ol.material) o.material.dispose?.(); });
  }
}

export function stIcons(st) { return (st.bleed ? '🩸' : '') + (st.frac ? '🦴' : '') + (st.vital ? '✧' : '') + (st.wet ? '💧' : '') + (st.frozen ? '🧊' : '') + (st.burn ? '🔥' : '') + (st.poison ? '☠' : '') + (st.stun ? '💫' : '') + (st.fear ? '😱' : '') + (st.haste ? '💨' : ''); }
