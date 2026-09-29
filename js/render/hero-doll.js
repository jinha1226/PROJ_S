import * as THREE from 'three';
import { GEAR_BASES, MAT_COLOR, RARITY_ORDER, SLOTS, isWeapon, weaponId } from '../data/gear.js';
import { _w } from './common.js';
import * as K from './diorama.js';
import { weaponDoll } from './dolls.js';
import { View } from './view.js';

/* ---------- 등불지기 인형: SD 비율, 두건 그림자 속 빛나는 두 눈, 해진 망토, 녹슨 흉갑, 허리 주머니, 횃불 ----------
   입은 장비가 모양을 바꾼다 (docs/설계_아이템_장비.md §11). look = 횃불을 이은 주민의 옷 색 */
const THICK = { cloth: 1, leather: 1.04, chain: 1.08, plate: 1.14 };
const LIMB = { cloth: 1.05, leather: 1.1, chain: 1.16, plate: 1.24 };
const GLOW = { magic: [0.02, 0.04, 0.12], rare: [0.1, 0.07, 0], legend: [0.14, 0.05, 0] };
const NECK_GEM = { fireDmg: 0xff7a1a, boltDmg: 0xffe14a, frostDmg: 0x8fdcff, poisonDmg: 0x79e05a };
const RUST = 0x6a4028, DARK = 0x0a0809, EYE = 0xffd48a;

export function heroSpec(eq = {}, look = null) {
  const B = (slot) => eq[slot] && GEAR_BASES[eq[slot].base];
  const body = B('body'), head = B('head'), hands = B('hands'), feet = B('feet'), off = eq.off, offB = B('off');
  const bodyCol = body ? MAT_COLOR[body.mat] : 0x3a3530, th = body ? THICK[body.mat] : 1;
  const handCol = hands ? MAT_COLOR[hands.mat] : 0x4a3a2e, hs = hands ? LIMB[hands.mat] : 1;
  const footCol = feet ? MAT_COLOR[feet.mat] : 0x2e241c, fs = feet ? LIMB[feet.mat] : 1;
  const cloak = look ? look.cloth : 0x2c2a33;
  const parts = [
    // 다리 · 장화
    { s: 'cyl', p: [-0.09, 0.2, 0], k: [0.065, 0.28, 0.065], c: 0x24201c }, { s: 'cyl', p: [0.09, 0.2, 0], k: [0.065, 0.28, 0.065], c: 0x24201c },
    { s: 'sphere', p: [-0.1, 0.06, 0.03], k: [0.085 * fs, 0.065 * fs, 0.12 * fs], c: footCol }, { s: 'sphere', p: [0.1, 0.06, 0.03], k: [0.085 * fs, 0.065 * fs, 0.12 * fs], c: footCol },
    // 몸통(넓은 어깨) · 녹슨 흉갑 · 허리띠 · 주머니
    { s: 'sphere', p: [0, 0.48, 0], k: [0.26 * th, 0.25, 0.19 * th], c: bodyCol },
    { s: 'sphere', p: [0, 0.52, 0.07 * th], k: [0.2 * th, 0.17, 0.14 * th], c: body && body.mat !== 'cloth' ? bodyCol : 0x5c5650 },
    { s: 'sphere', p: [-0.05, 0.55, 0.19 * th], k: [0.035, 0.03, 0.02], c: RUST }, { s: 'sphere', p: [0.07, 0.47, 0.19 * th], k: [0.05, 0.035, 0.02], c: RUST },
    { s: 'cyl', p: [0, 0.33, 0], k: [0.235 * th, 0.05, 0.18 * th], c: 0x3a2618 },
    { s: 'box', p: [0.15, 0.3, 0.16 * th], r: [0, -0.4, 0], k: [0.1, 0.1, 0.06], c: 0x4a3222 }, { s: 'box', p: [0.15, 0.35, 0.17 * th], r: [0, -0.4, 0], k: [0.1, 0.03, 0.065], c: 0x3a2618 },
    // 어깨 · 팔(조금 길게) · 손
    { s: 'sphere', p: [-0.27 * th, 0.62, 0], k: [0.1, 0.08, 0.1], c: 0x4a4440 }, { s: 'sphere', p: [0.27 * th, 0.62, 0], k: [0.1, 0.08, 0.1], c: 0x4a4440 },
    { s: 'cyl', p: [-0.31, 0.46, 0.02], r: [0, 0, -0.12], k: [0.05, 0.28, 0.05], c: 0x2e2a26 }, { s: 'cyl', p: [0.3, 0.5, 0.05], r: [-0.25, 0, 0.1], k: [0.05, 0.24, 0.05], c: 0x2e2a26 },
    { s: 'sphere', p: [-0.33, 0.31, 0.04], k: 0.065 * hs, c: handCol }, { s: 'sphere', p: [0.3, 0.4, 0.1], k: 0.065 * hs, c: handCol },
    // 망토(등) · 횃불 자루
    { s: 'box', p: [0, 0.44, -0.2 * th], r: [0.12, 0, 0], k: [0.5 * th, 0.5, 0.05], c: cloak },
    { s: 'cyl', p: [0.31, 0.52, 0.11], r: [0.15, 0, -0.1], k: [0.026, 0.3, 0.026], c: 0x3a2818 },
    { s: 'cyl', p: [0.33, 0.66, 0.12], k: [0.045, 0.05, 0.045], c: 0x2a1c12 },
  ];
  // 몸통 재질
  if (body?.mat === 'leather') parts.push({ s: 'box', p: [0, 0.5, 0.18 * th], r: [0, 0, 0.7], k: [0.05, 0.4, 0.03], c: 0x3a2618 });
  if (body?.mat === 'chain') for (const y of [0.38, 0.47, 0.56]) parts.push({ s: 'torus', p: [0, y, 0], r: [Math.PI / 2, 0, 0], k: [0.24 * th, 0.19 * th, 0.2 * th], tube: 0.05, c: 0x44464a });
  if (body?.mat === 'plate') parts.push({ s: 'sphere', p: [-0.28, 0.64, 0], k: [0.13, 0.08, 0.12], c: bodyCol }, { s: 'sphere', p: [0.28, 0.64, 0], k: [0.13, 0.08, 0.12], c: bodyCol }, { s: 'box', p: [0.02, 0.52, 0.2 * th], r: [0, 0, 0.15], k: [0.06, 0.02, 0.02], c: DARK });
  // 머리: 얼굴은 늘 그림자 속, 두 눈만 빛난다
  const legendHead = eq.head && eq.head.rarity === 'legend';
  parts.push({ s: 'sphere', p: [0, 0.86, 0.06], k: [0.17, 0.15, 0.12], c: DARK },
    { s: 'sphere', p: [-0.06, 0.87, 0.175], k: [0.024, 0.02, 0.012], c: EYE, glow: true }, { s: 'sphere', p: [0.06, 0.87, 0.175], k: [0.024, 0.02, 0.012], c: EYE, glow: true });
  if (!head) parts.push({ s: 'sphere', p: [0, 0.9, -0.02], k: [0.235, 0.24, 0.23], c: cloak }, { s: 'cone', p: [0, 1.08, -0.12], r: [-0.5, 0, 0], k: [0.1, 0.24, 0.1], c: cloak }, { s: 'torus', p: [0, 0.86, 0.11], k: [0.19, 0.17, 0.12], tube: 0.22, c: cloak });
  else if (legendHead) parts.push({ s: 'sphere', p: [0, 0.9, -0.01], k: [0.24, 0.22, 0.24], c: 0x3a3230 }, ...[0, 1, 2, 3, 4, 5].map((k) => ({ s: 'cone', p: [Math.cos(k * 1.047) * 0.18, 1.1, Math.sin(k * 1.047) * 0.18 - 0.02], k: [0.035, 0.16, 0.035], c: 0x5a4a3e })), { s: 'oct', p: [0, 1.02, 0.2], k: 0.035, c: 0xff7a2a, glow: true });
  else if (head.mat === 'cloth') parts.push({ s: 'sphere', p: [0, 0.9, -0.03], k: [0.25, 0.25, 0.24], c: MAT_COLOR.cloth }, { s: 'torus', p: [0, 0.86, 0.11], k: [0.19, 0.17, 0.12], tube: 0.22, c: MAT_COLOR.cloth }, { s: 'box', p: [0.05, 1.03, -0.2], r: [0.6, 0, 0.3], k: [0.08, 0.18, 0.02], c: MAT_COLOR.cloth });
  else if (head.mat === 'leather') parts.push({ s: 'sphere', p: [0, 0.92, -0.02], k: [0.24, 0.2, 0.24], c: MAT_COLOR.leather }, { s: 'cyl', p: [0, 0.98, 0], k: [0.34, 0.025, 0.34], c: 0x3a2618 });
  else parts.push({ s: 'sphere', p: [0, 0.9, -0.01], k: [0.25, 0.24, 0.25], c: MAT_COLOR[head.mat] }, { s: 'box', p: [0, 0.87, 0.22], k: [0.2, 0.03, 0.04], c: DARK }, { s: 'box', p: [0, 0.8, 0.2], k: [0.03, 0.12, 0.04], c: MAT_COLOR[head.mat] },
    ...(head.mat === 'plate' ? [{ s: 'cone', p: [-0.22, 1.05, 0], r: [0, 0, 0.7], k: [0.045, 0.2, 0.045], c: 0xb8ad90 }, { s: 'cone', p: [0.22, 1.05, 0], r: [0, 0, -0.7], k: [0.045, 0.2, 0.045], c: 0xb8ad90 }] : [{ s: 'sphere', p: [0.18, 0.95, 0.12], k: 0.025, c: RUST }]));
  // 목걸이 보석(원소 색은 그대로 빛난다)
  if (eq.neck) { const el = eq.neck.affixes.find((a) => NECK_GEM[a.id] && a.known); parts.push({ s: 'oct', p: [0, 0.64, 0.17 * th], k: 0.04, c: el ? NECK_GEM[el.id] : 0xc07aff, glow: true }); }
  // 등: 방패(등급색 테두리)
  if (offB && off.base === 'shield') parts.push({ s: 'cyl', p: [0, 0.48, -0.27 * th], r: [Math.PI / 2, 0, 0], k: [0.22, 0.05, 0.22], c: 0x4a3a2a }, { s: 'torus', p: [0, 0.48, -0.3 * th], k: 0.21, tube: 0.1, c: off.rarity === 'common' ? 0x5a5a5e : { magic: 0x4a7ad0, rare: 0xc0a040, legend: 0xd06a20 }[off.rarity] }, { s: 'sphere', p: [0, 0.48, -0.32 * th], k: [0.045, 0.045, 0.03], c: RUST });
  let top = 'common'; for (const k of SLOTS) if (eq[k] && RARITY_ORDER.indexOf(eq[k].rarity) > RARITY_ORDER.indexOf(top)) top = eq[k].rarity;
  const legend = SLOTS.some((k) => eq[k] && eq[k].legend && k !== 'off');
  const torchBig = off && off.base === 'torch';
  return {
    h: 1.2, col: bodyCol, scale: 1, glow: GLOW[top], gloss: RARITY_ORDER.indexOf(top) >= 2 ? 1.2 : 0, rim: 1,
    parts,
    extra: (d) => {
      const f = new THREE.Group(), fs2 = torchBig ? 1.5 : 1;
      const o = new THREE.Mesh(new THREE.ConeGeometry(0.08 * fs2, 0.24 * fs2, 7).translate(0, 0.12 * fs2, 0), new THREE.MeshBasicMaterial({ color: new THREE.Color(2.6, 0.85, 0.18), toneMapped: false }));
      const i = new THREE.Mesh(new THREE.ConeGeometry(0.045 * fs2, 0.15 * fs2, 7).translate(0, 0.075 * fs2, 0), new THREE.MeshBasicMaterial({ color: new THREE.Color(3, 2.3, 0.9), toneMapped: false }));
      f.add(o, i); f.position.set(0.335, 0.69, 0.12); d.body.add(f);
      // 해진 망토 자락: 가장자리 천 조각이 흔들린다
      const strips = [], cg = K.toon({ color: cloak, rim: 1 });
      for (let k = 0; k < 5; k++) {
        const piv = new THREE.Group(), len = 0.16 + ((k * 7) % 3) * 0.05;
        const m = new THREE.Mesh(new THREE.BoxGeometry(0.085, len, 0.02).translate(0, -len / 2, 0), cg); m.castShadow = true;
        piv.position.set(-0.2 * th + k * 0.1 * th, 0.2, -0.24 * th); piv.add(m); d.body.add(piv); strips.push(piv);
      }
      const wh = new THREE.Group(); wh.position.set(-0.33, 0.33, 0.06); wh.rotation.x = 0.5; d.body.add(wh);
      if (isWeapon(off)) { const bw = weaponDoll(weaponId(off)); bw.root.position.set(0.1, 0.38, -0.29 * th); bw.root.rotation.set(0.2, 0, -0.7); bw.root.scale.setScalar(0.9); d.body.add(bw.root); }
      let lx = null, lz = 0, vx = 0, vz = 0;
      return {
        wh,
        update(dt, t, ev) {
          // 이동 속도 → 망토는 뒤로 날리고 불꽃은 반대로 기운다
          d.root.getWorldPosition(_w); if (lx !== null && dt > 0) { vx += ((_w.x - lx) / dt - vx) * Math.min(1, dt * 10); vz += ((_w.z - lz) / dt - vz) * Math.min(1, dt * 10); } lx = _w.x; lz = _w.z;
          const yaw = d.root.rotation.y, fwd = vx * Math.sin(yaw) + vz * Math.cos(yaw), side = vx * Math.cos(yaw) - vz * Math.sin(yaw), sp = Math.min(1, Math.hypot(vx, vz) / 5);
          strips.forEach((p, k) => { p.rotation.x = -0.1 - sp * 0.9 * Math.min(1, Math.max(0, fwd / 3 + 0.3)) - Math.sin(t * (3 + k * 0.7) + k) * (0.08 + sp * 0.2); p.rotation.z = Math.sin(t * 2.3 + k * 1.3) * 0.06; });
          const s = 1 + Math.sin(t * 20) * 0.12 + Math.sin(t * 33) * 0.08; o.scale.set(1, s, 1); i.scale.set(1, s * 1.05, 1);
          f.rotation.x = -Math.min(0.6, fwd * 0.12) + Math.sin(t * 6) * 0.05; f.rotation.z = Math.min(0.5, Math.max(-0.5, side * 0.1)) + Math.sin(t * 5) * 0.06;
          if (Math.random() < dt * 8 * fs2) { f.getWorldPosition(_w); _w.y += 0.22; View.dio.sparks.emit({ pos: _w, n: 1, color: 0xff8a2a, color2: 0xffd060, speed: 0.3, up: 1.2, grav: 0.6, life: 0.7, size: 0.06, vx: -vx * 0.2, vz: -vz * 0.2 }); }
          if (legend && d.root.visible && Math.random() < dt * 14) { // 전설: 몸 주위를 도는 작은 불씨
            const a = t * 2.4 + Math.floor(Math.random() * 5) * 1.2566; d.root.getWorldPosition(_w);
            View.dio.sparks.emit({ pos: _w.set(_w.x + Math.cos(a) * 0.5, _w.y + 0.55 + Math.sin(t * 3 + a) * 0.15, _w.z + Math.sin(a) * 0.5), n: 1, color: 0xff7a2a, color2: 0xffc060, speed: 0.1, up: 0.4, grav: 0, life: 0.5, size: 0.09 });
          }
        },
      };
    },
  };
}
