import * as THREE from 'three';
import { gearCss, gearHex, gearName, gearTier } from '../core/gear.js';
import { G, I, XY } from '../core/state.js';
import { GEAR_BASES, MAT_COLOR, weaponId } from '../data/gear.js';
import { COLORS } from '../data/stones.js';
import { WEAPONS } from '../data/weapons.js';
import { W3, _tv } from './common.js';
import * as K from './diorama.js';
import { GLOW_TEX, weaponDoll } from './dolls.js';
import { ports } from './ports.js';
import { Sfx } from './sfx.js';
import { View } from './view.js';

/* ---------- 바닥 장비(빛기둥 없음 — 속성·유물만 은은히 빛난다) · 이름표 · 상자 · 장비 연출 ---------- */
function gearProp(it) {
  const B = GEAR_BASES[it.base], k = B.slot, c = B.mat ? MAT_COLOR[B.mat] : 0xc8c8d0;
  if (B.weapon) { const d = weaponDoll(weaponId(it), it); d.root.rotation.set(Math.PI / 2, 0, 0.7); d.root.position.set(0, 0.07, -0.2); const g = new THREE.Group(); g.add(d.root); return g; }
  if (B.orb) { // 오브: 그 색으로 빛나는 구슬
    const c = COLORS[B.orb].hex, g = new THREE.Group(), d = K.doll([{ s: 'sphere', p: [0, 0.14, 0], k: 0.1, c }, { s: 'sphere', p: [-0.035, 0.18, 0.07], k: 0.025, c: 0xffffff }], { gloss: 1.5 });
    d.mat.emissive.setHex(c).multiplyScalar(0.45);
    const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: GLOW_TEX, color: c, blending: THREE.AdditiveBlending, transparent: true, depthWrite: false, opacity: 0.7 })); s.scale.setScalar(0.7); s.position.y = 0.14;
    g.add(d.root, s); return g;
  }
  const P = {
    body: [{ s: 'sphere', p: [0, 0.16, 0], k: [0.2, 0.16, 0.14], c }, { s: 'sphere', p: [-0.17, 0.22, 0], k: 0.07, c }, { s: 'sphere', p: [0.17, 0.22, 0], k: 0.07, c }],
    head: [{ s: 'sphere', p: [0, 0.1, 0], k: [0.18, 0.13, 0.18], c }],
    cloak: [{ s: 'box', p: [0, 0.03, 0], r: [0, 0.3, 0], k: [0.42, 0.04, 0.34], c: it.un === 'mistCloak' ? 0x6aa8d8 : 0x7a2a2a }, { s: 'sphere', p: [0, 0.06, -0.15], k: [0.05, 0.03, 0.05], c: 0xd8b04a }],
    hands: [{ s: 'sphere', p: [-0.09, 0.08, 0], k: 0.08, c }, { s: 'sphere', p: [0.09, 0.08, 0], k: 0.08, c }],
    feet: [{ s: 'box', p: [-0.08, 0.07, 0], k: [0.1, 0.14, 0.18], c }, { s: 'box', p: [0.08, 0.07, 0], k: [0.1, 0.14, 0.18], c }],
    off: [{ s: 'cyl', p: [0, 0.05, 0], k: it.base === 'shield' ? [0.22, 0.05, 0.22] : [0.15, 0.05, 0.15], c: 0x9a6a3e }, { s: 'torus', p: [0, 0.08, 0], r: [Math.PI / 2, 0, 0], k: it.base === 'shield' ? 0.21 : 0.14, tube: 0.12, c: 0x9aa6b8 }],
    neck: [{ s: 'torus', p: [0, 0.03, 0], r: [Math.PI / 2, 0, 0], k: 0.13, tube: 0.12, c: 0xd8b04a }, { s: 'oct', p: [0, 0.07, 0.13], k: 0.05, c: 0xc07aff }],
    ring: [{ s: 'torus', p: [0, 0.09, 0], k: 0.07, tube: 0.25, c: 0xffd35a }, { s: 'oct', p: [0, 0.17, 0], k: 0.035, c: 0x7fdcff }],
  }[k];
  return K.doll(P, { gloss: 1.2 }).root;
}
function makeGearMesh(it) {
  const g = new THREE.Group(), prop = gearProp(it); g.add(prop);
  const tier = gearTier(it);
  if (tier !== 'plain') { // 속성은 그 원소 색, 랜다트는 보랏빛, 픽다트는 금빛 — 은은하게
    const col = tier === 'unrand' ? 0xffcf4a : tier === 'randart' ? 0xc890ff : gearHex(it);
    const glow = new THREE.Sprite(new THREE.SpriteMaterial({ map: GLOW_TEX, color: col, blending: THREE.AdditiveBlending, transparent: true, depthWrite: false, opacity: 0.6 }));
    glow.scale.setScalar(tier === 'unrand' ? 1.4 : 1.0); glow.position.y = 0.2; g.add(glow); g.userData.glow = glow;
  }
  g.userData.prop = prop; g.userData.ph = Math.random() * 6; g.userData.it = it;
  const tag = document.createElement('div'); tag.className = 'gtag'; tag.style.color = gearCss(it); tag.textContent = gearName(it); tag.style.display = 'none';
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
      if (u.glow) u.glow.material.opacity = 0.4 + 0.2 * Math.sin(time * 2.5 + u.ph);
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
        if (d.it.un) { ports.UI.legendFlash(); D.pool.flash(W3(d.x, d.y), 0xff8a2a, 90, 0.8, 8); D.rig.shake(0.3); Sfx.play('crit'); }
        else if (d.it.art || d.it.brand || d.it.ego) Sfx.play('gem');
        return true;
      }
      case 'chest': { const c = this.chestMeshes.get(I(d.x, d.y)); if (c) c.userData.lid.userData.open = true; D.sparks.emit({ pos: W3(d.x, d.y, 0.5), n: 26, color: 0xffd35a, color2: 0xffffff, speed: 2.5, up: 2, grav: -2, life: 0.7, size: 0.13 }); D.pool.flash(W3(d.x, d.y), 0xffd070, 40, 0.5, 5); Sfx.play('door'); return true; }
      case 'equip': {
        if (pe) { pe.redress({ type: 'hero', eq: d.eq }); this.setWeapon(weaponId(d.eq.weapon), d.eq.weapon); D.sparks.emit({ pos: W3(pe.cur.x, pe.cur.z, 0.6), n: 22, color: 0xffffff, color2: 0xffd84a, speed: 1.6, up: 1.4, grav: 0, life: 0.6, size: 0.12, spread: 0.4 }); }
        ports.UI.renderWeapon(); Sfx.play('pick'); return true;
      }
      case 'wset': { // 세트 교체(턴 없음): 등에서 꺼내 드는 짧은 동작 + 무기 색 반짝이
        if (pe) {
          pe.redress({ type: 'hero', eq: d.eq }); this.setWeapon(weaponId(d.eq.weapon), d.eq.weapon); pe.swing = { t: 0, form: 'draw', dur: 0.3 };
          const w = d.eq.weapon && WEAPONS[weaponId(d.eq.weapon)]; D.sparks.emit({ pos: W3(pe.cur.x, pe.cur.z, 0.75), n: 18, color: w ? COLORS[w.color].hex : 0xffffff, color2: 0xffffff, speed: 1.4, up: 1.2, grav: 0, life: 0.5, size: 0.11, spread: 0.3 });
        }
        ports.UI.renderWeapon?.(); Sfx.play('draw'); return true;
      }
      case 'dodge': if (pe) { pe.lunge(Math.random() < 0.5 ? 1 : -1, 0, 0.3); D.labels.pop(W3(pe.cur.x, pe.cur.z, 1.3), '회피!', { color: '#9fe2ff', cls: 'word', vx: 0 }); Sfx.play('swing'); } return true;
      case 'block': if (pe) { pe.bubbleHit = 1; D.labels.pop(W3(pe.cur.x, pe.cur.z, 1.3), '막기!', { color: '#ffd08a', cls: 'word', vx: 0 }); D.sparks.emit({ pos: W3(pe.cur.x, pe.cur.z, 0.5), n: 14, color: 0xffe0a0, speed: 3.5, life: 0.3, size: 0.1 }); Sfx.play('blunt'); } return true;
      case 'miss': D.labels.pop(W3(d.x, d.y, 1.0), '빗나감', { color: '#c8ccd8', cls: 'word', vx: 0 }); return true;
      case 'immune': if (pe) D.labels.pop(W3(pe.cur.x, pe.cur.z, 1.3), '화상 면역', { color: '#ffb070', cls: 'word', vx: 0 }); return true;
      case 'levelUp': ports.UI.banner(`레벨 ${d.level} — 영혼석 칸이 열렸다`, 'info'); if (pe) { D.sparks.emit({ pos: W3(pe.cur.x, pe.cur.z, 0.4), n: 40, color: 0xffe38a, color2: 0xffffff, speed: 1.6, up: 2.4, grav: 0, life: 1, size: 0.12, spread: 0.5 }); D.fx.ring(W3(pe.cur.x, pe.cur.z), 0xffe38a, 0.3, 2, 0.6); } Sfx.chime(4); return true;
      case 'relic': ports.UI.legendFlash(); ports.UI.banner(`★ ${d.name}`, 'fire'); ports.UI.toast(`${d.owner ? d.owner + '의 유품 — ' : ''}${d.story}`); Sfx.play('crit'); return true;
      case 'enchant': if (pe) { D.sparks.emit({ pos: W3(pe.cur.x, pe.cur.z, 0.6), n: 30, color: 0xffe38a, color2: 0xffffff, speed: 2, up: 2, grav: 0, life: 0.7, size: 0.12, spread: 0.4 }); D.fx.ring(W3(pe.cur.x, pe.cur.z), 0xffe38a, 0.2, 1.2, 0.4); } Sfx.chime(3); return true;
      case 'bloodBurst': D.sparks.emit({ pos: W3(d.x, d.y, 0.5), n: 34, color: 0xff1a2a, color2: 0x8a0010, speed: 4, up: 1, grav: -6, life: 0.6, size: 0.14 }); D.fx.ring(W3(d.x, d.y), 0xff2a3a, 0.2, 1.6, 0.4); return true;
      default: return false;
    }
  },
});
