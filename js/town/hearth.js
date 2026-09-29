import * as THREE from 'three';
import { META } from '../core/meta.js';
import { glowParts, hearthGlow } from '../core/visitors.js';
import { VOICES } from '../data/lines.js';
import { BLD } from '../data/town.js';
import { GLOW, LANDS } from '../data/visitors.js';
import { W3, _w } from '../render/common.js';
import * as K from '../render/diorama.js';
import { npcParts } from '../render/dolls.js';
import { Sfx } from '../render/sfx.js';
import { View } from '../render/view.js';
import { UI } from '../ui/ui.js';
import { pick } from '../util/rng.js';
import { Town } from './town.js';

/* ================= 모닥불 · 원경 · 비석 · 방문자 인형 =================
   모닥불 밝기가 불꽃·빛 반경을 정하고, 넣은 등불 조각만큼 원경의 땅이 어둠 밖으로 드러난다. */
const VISIT_SPOT = [[3.3, 6.3], [3.5, 5.2]];
const GRAVE_SPOT = [[6.9, 6.0], [7.7, 6.0], [8.5, 6.0], [6.9, 8.1], [7.7, 8.1], [8.5, 8.1]];

/** 원경의 한 땅: 실루엣 + 먼 불빛. 밝아지면(lit) 색과 불빛이 살아난다 */
function landScene(L) {
  const g = new THREE.Group(), parts = [], lights = [], R = (a, b) => a + Math.random() * (b - a);
  const add = (p) => parts.push(p);
  if (L.id === 'lake') {
    add({ s: 'cyl', p: [5, -0.2, -6.5], k: [7.5, 0.05, 3.2], c: 0x1c2c40 });
    for (let k = 0; k < 14; k++) add({ s: 'cone', p: [R(-2, 12), 0.2, R(-4, -2.4)], k: [0.05, R(0.4, 0.8), 0.05], c: 0x3a4a3a });
    add({ s: 'box', p: [7, -0.05, -6], r: [0, 0.4, 0], k: [0.9, 0.12, 0.35], c: 0x4a3a2a });
    for (let k = 0; k < 5; k++) lights.push([R(0, 11), 0.3, R(-10, -8)]);
  } else if (L.id === 'forest') {
    for (let k = 0; k < 16; k++) { const x = R(-9, -2.4), z = R(-1, 15), h = R(1.6, 3); add({ s: 'cyl', p: [x, h * 0.25, z], k: [0.1, h * 0.5, 0.1], c: 0x2a2420 }); add({ s: 'cone', p: [x, h * 0.7, z], k: [R(0.5, 0.8), h * 0.8, R(0.5, 0.8)], c: 0x24342a }); }
    for (let k = 0; k < 5; k++) lights.push([R(-10, -6), 0.5, R(0, 14)]);
  } else if (L.id === 'mine') {
    for (let k = 0; k < 6; k++) add({ s: 'sphere', p: [R(13, 19), -0.3, R(-1, 15)], k: [R(1.6, 2.6), R(0.9, 1.8), R(1.6, 2.6)], c: 0x3a3228 });
    add({ s: 'box', p: [13.5, 1.1, 5], k: [0.12, 2.2, 0.12], c: 0x4a3a2a }, { s: 'box', p: [14.5, 1.1, 5], k: [0.12, 2.2, 0.12], c: 0x4a3a2a }, { s: 'box', p: [14, 2.2, 5], k: [1.2, 0.12, 0.2], c: 0x4a3a2a }, { s: 'torus', p: [14, 2.35, 5], k: 0.3, tube: 0.06, c: 0x5a5048 });
    for (let k = 0; k < 5; k++) lights.push([R(14, 20), 0.6, R(0, 14)]);
  } else {
    for (let k = 0; k < 6; k++) { const x = R(-4, 15), z = R(17.5, 22), h = R(3, 5.5), w = R(2, 3.2); add({ s: 'cone', p: [x, h / 2 - 0.3, z], k: [w, h, w], c: 0x3a4250 }); add({ s: 'cone', p: [x, h - 0.3 - h * 0.14, z], k: [w * 0.3, h * 0.3, w * 0.3], c: 0xc8d0dc }); }
    for (let k = 0; k < 5; k++) lights.push([R(-2, 13), 0.4, R(16, 18)]);
  }
  const d = K.doll(parts, { gloss: 0, shadow: false }); d.ol.visible = false; g.add(d.root);
  const pts = lights.map(([x, y, z]) => { const m = new THREE.Mesh(new THREE.SphereGeometry(0.09, 8, 6), new THREE.MeshBasicMaterial({ color: new THREE.Color(2.4, 1.3, 0.45), toneMapped: false, transparent: true, opacity: 0 })); m.position.set(x, y, z); m.userData.ph = Math.random() * 6; g.add(m); return m; });
  return { g, d, pts, k: 0, kT: 0 };
}

Object.assign(Town, {
  /** 원경·비석·방문자·모닥불 — build() 끝에서 부른다 */
  buildHearth(skipVisitors = []) {
    const D = View.dio;
    this.lands = LANDS.map((L) => { const s = landScene(L); s.kT = s.k = META.lit[L.zone - 1] ? 1 : 0; this.tintLand(s); D.scene.add(s.g); this.objs.push(s.g); return s; });
    this.graves = [];
    META.fallen.slice(-GRAVE_SPOT.length).forEach((f, k) => {
      const [x, z] = GRAVE_SPOT[k], d = K.doll([{ s: 'box', p: [0, 0.32, 0], k: [0.38, 0.62, 0.12], c: 0x5a5a60 }, { s: 'cyl', p: [0, 0.63, 0], r: [Math.PI / 2, 0, 0], k: [0.19, 0.12, 0.19], c: 0x5a5a60 }, { s: 'box', p: [0, 0.05, 0.14], k: [0.5, 0.1, 0.22], c: 0x3a3632 }, { s: 'cyl', p: [0.1, 0.82, 0], k: [0.035, 0.12, 0.035], c: 0xe8dcc0 }], { gloss: 0, scale: 1 });
      const flame = new THREE.Mesh(new THREE.ConeGeometry(0.035, 0.1, 6), new THREE.MeshBasicMaterial({ color: new THREE.Color(2.2, 1.2, 0.35), toneMapped: false })); flame.position.set(0.1, 0.93, 0); d.root.add(flame);
      d.root.position.set(x, 0, z); d.root.rotation.y = (Math.random() - 0.5) * 0.3; d.mesh.userData.pick = { grave: f };
      D.scene.add(d.root); this.objs.push(d.root); this.graves.push({ d, flame, f });
    });
    this.visitorDolls = [];
    for (const v of META.visitors) if (!skipVisitors.includes(v)) this.spawnVisitor(v);
    this.applyGlow(true);
  },
  tintLand(s) { const k = 0.12 + 0.88 * s.k; s.d.mat.color.setRGB(k, k, k); for (const m of s.pts) m.material.opacity = s.k; },
  spawnVisitor(v) {
    const D = View.dio, k = this.visitorDolls.length, [x, z] = VISIT_SPOT[k % VISIT_SPOT.length], d = K.doll(npcParts(v.npc), { scale: 1.2, gloss: 0 });
    d.root.position.set(x, 0, z); d.root.rotation.y = Math.atan2(BLD.plaza.x - x, BLD.plaza.y - z); d.mesh.userData.pick = { visitor: v }; D.scene.add(d.root);
    const tag = document.createElement('div'); tag.className = 'btag visit'; tag.textContent = `❔ ${v.npc.name}`; View.labelRoot.appendChild(tag); this.tags.push(tag);
    const q = { v, d, tag, ph: Math.random() * 6 }; this.visitorDolls.push(q); this.objs.push(d.root); return q;
  },
  removeVisitor(v) { const q = this.visitorDolls.find((o) => o.v === v); if (!q) return null; View.dio.scene.remove(q.d.root); q.tag.remove(); this.visitorDolls.splice(this.visitorDolls.indexOf(q), 1); return q; },
  /** 모닥불 밝기 → 불꽃 크기 · 빛 반경 · 원경 안개 */
  applyGlow(snap) {
    const g = hearthGlow(); this.glow = g;
    View.dio.lights.setGlow?.(g, snap);
  },
  hearthFrame(sdt, time) {
    const D = View.dio, s = {};
    for (const L of this.lands || []) { if (Math.abs(L.k - L.kT) > 0.001) { L.k += (L.kT - L.k) * Math.min(1, sdt * 1.2); this.tintLand(L); } for (const m of L.pts) m.scale.setScalar(0.8 + 0.35 * Math.sin(time * 3 + m.userData.ph)); }
    for (const q of this.graves || []) q.flame.scale.set(1, 0.8 + 0.3 * Math.sin(time * 11 + q.d.root.position.x * 5), 1);
    for (const q of this.visitorDolls || []) {
      q.d.root.rotation.y += Math.sin(time * 0.9 + q.ph) * sdt * 0.9; // 두리번
      D.labels.toScreen(_w.set(q.d.root.position.x, 1.85, q.d.root.position.z), s);
      q.tag.style.transform = `translate(${s.x.toFixed(1)}px,${s.y.toFixed(1)}px) translate(-50%,-100%)`;
    }
    if (this.glow <= GLOW.low && Math.random() < sdt * 2) D.pool.flash(W3(BLD.plaza.x, BLD.plaza.y), 0x6070a0, 6, 0.4, 3);
    const orbs = this.orbs || [];
    for (let i = orbs.length - 1; i >= 0; i--) { const o = orbs[i]; o.t += sdt; if (o.step(o)) orbs.splice(i, 1); }
  },
  /** 방문자 도착: 원경의 불빛 하나가 길을 따라 와서 인형이 된다 */
  visitorArrive(v, done) {
    const D = View.dio, k = this.visitorDolls.length, [x, z] = VISIT_SPOT[k % VISIT_SPOT.length], L = LANDS.find((q) => q.id === v.npc.from);
    const from = L ? new THREE.Vector3(5 + L.dir[0] * 9, 0.5, 7 + L.dir[1] * 11) : new THREE.Vector3(5, 0.5, -5);
    const orb = new THREE.Mesh(new THREE.SphereGeometry(0.14, 10, 8), new THREE.MeshBasicMaterial({ color: new THREE.Color(2.6, 1.5, 0.5), toneMapped: false })); orb.position.copy(from); D.scene.add(orb);
    const path = [from, new THREE.Vector3(5, 0.6, 1.8), new THREE.Vector3(x, 0.7, z)];
    this.orbs = this.orbs || [];
    this.orbs.push({ t: 0, step: (o) => {
      const T = 2.2, k2 = Math.min(1, o.t / T), seg = k2 < 0.55 ? 0 : 1, lk = seg === 0 ? k2 / 0.55 : (k2 - 0.55) / 0.45;
      orb.position.lerpVectors(path[seg], path[seg + 1], lk * lk * (3 - 2 * lk)); orb.position.y += Math.sin(o.t * 6) * 0.05;
      if (Math.random() < 0.6) D.sparks.emit({ pos: orb.position, n: 1, color: 0xffb060, speed: 0.2, up: 0.3, grav: 0, life: 0.6, size: 0.08 });
      if (k2 < 1) return false;
      D.scene.remove(orb); D.puffs.emit({ pos: W3(x, z, 0.4), n: 16, color: 0xb8b0a0, speed: 1.2, grav: 0, life: 0.8, size: 0.3, grow: 0.8 });
      this.spawnVisitor(v); Sfx.play('pick'); UI.toast(`${v.npc.name}이(가) 불빛을 보고 찾아왔다`); done && done(); return true;
    } });
  },
  /** 등불 조각 넣기: 목소리가 불로 빨려 들고, 불빛 파도가 원경의 어둠을 걷는다 */
  shardScene(zone, done) {
    const D = View.dio, c = W3(BLD.plaza.x, BLD.plaza.y), L = LANDS[zone - 1], land = this.lands[zone - 1];
    const shard = K.doll([{ s: 'oct', p: [0, 0, 0], k: [0.16, 0.3, 0.16], c: 0xffe0a0 }], { gloss: 0 }); shard.mat.emissive.setRGB(1.2, 0.7, 0.25); shard.root.position.set(c.x, 3.2, c.z); D.scene.add(shard.root);
    UI.banner(`🔥 등불 조각 — ${L.name}`, 'fire'); Sfx.play('gem');
    const voices = VOICES.slice(); let popped = 0;
    this.orbs = this.orbs || [];
    this.orbs.push({ t: 0, step: (o) => {
      const t = o.t;
      if (t < 1.4) { shard.root.position.y = 3.2 - (t / 1.4) * 2.6; shard.root.rotation.y = t * 4; if (Math.random() < 0.5) D.sparks.emit({ pos: shard.root.position, n: 2, color: 0xffd080, speed: 0.6, grav: 0, life: 0.5, size: 0.09 }); }
      else if (shard.root.parent) { D.scene.remove(shard.root); D.pool.flash(c, 0xffb050, 120, 1.4, 12); D.rig.shake(0.3); D.sparks.emit({ pos: W3(c.x, c.z, 0.6), n: 60, color: 0xff9a3a, color2: 0xffe36a, speed: 3.5, up: 3, grav: 0.4, life: 1.2, size: 0.16 }); View.dio.lights.flare?.(); Sfx.play('fire'); }
      if (t > 0.4 && t < 3 && popped < 6 && t > 0.4 + popped * 0.4) { popped++; const a = Math.random() * 6.28, r = 3 + Math.random() * 2; D.labels.pop(W3(c.x + Math.cos(a) * r, c.z + Math.sin(a) * r, 1.2), '', { html: `<span class="voice">${pick(voices)}</span>`, cls: 'gem', vx: 0, rise: 10, dur: 2.2 }); }
      if (t > 1.6 && !o.wave) { o.wave = true; D.fx.ring(W3(c.x, c.z, 0.1), 0xffc070, 0.5, 26, 2.4); }
      if (t > 2.2) land.kT = 1;
      if (t < 4.2) return false;
      this.applyGlow(); UI.banner(`${L.name}의 사람들이 기억을 되찾았다`, 'info'); done && done(); return true;
    } });
  },
  /** 모닥불 카드: 밝기와 그 까닭 */
  hearthInfo() {
    const g = hearthGlow(), parts = glowParts();
    const eff = [g <= GLOW.low ? '⚠ 불이 흔들린다 — 방문자가 오지 않는다' : `방문 확률 ${Math.round(Math.min(100, GLOW.visitBase + g * GLOW.visitPer))}%`, g >= GLOW.vision ? '✓ 출발 시 횃불 시야 +1' : `밝기 ${GLOW.vision}: 횃불 시야 +1`, g >= GLOW.shield ? '✓ 첫 층 보호막 +4' : `밝기 ${GLOW.shield}: 첫 층 보호막 +4`];
    return `<div class="sec">모닥불 밝기 <b>${g}</b>/100</div><div class="glowbar"><i style="width:${g}%"></i></div>
      <div class="gtxt">${parts.map(([t, v]) => `<div>${v >= 0 ? '▲' : '▼'} ${t} <b style="color:${v >= 0 ? '#e8b060' : '#8a9ab8'}">${v > 0 ? '+' : ''}${v}</b></div>`).join('') || '<div>아무도 없다.</div>'}</div>
      <div class="gtxt" style="margin-top:6px">${eff.join('<br>')}</div>`;
  },
});
