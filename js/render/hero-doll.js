import * as THREE from 'three';
import { GEAR_BASES, MAT_COLOR, RARITY_ORDER, SLOTS, isWeapon, weaponId } from '../data/gear.js';
import { SKIN, _w } from './common.js';
import { weaponDoll } from './dolls.js';
import { View } from './view.js';

/* ---------- 주인공 인형: 입은 장비가 모양을 바꾼다 (docs/설계_아이템_장비.md §11) ---------- */
const THICK = { cloth: 1, leather: 1.04, chain: 1.08, plate: 1.15 };
const LIMB = { cloth: 1.05, leather: 1.12, chain: 1.18, plate: 1.28 };
const GLOW = { magic: [0.02, 0.05, 0.14], rare: [0.12, 0.09, 0], legend: [0.16, 0.06, 0] };
const NECK_GEM = { fireDmg: 0xff7a1a, boltDmg: 0xffe14a, frostDmg: 0x8fdcff, poisonDmg: 0x79e05a };

export function heroSpec(eq = {}) {
  const B = (slot) => eq[slot] && GEAR_BASES[eq[slot].base];
  const body = B('body'), head = B('head'), hands = B('hands'), feet = B('feet'), off = eq.off, offB = B('off');
  const bodyCol = body ? MAT_COLOR[body.mat] : 0x3f86d8, th = body ? THICK[body.mat] : 1;
  const handCol = hands ? MAT_COLOR[hands.mat] : SKIN, hs = hands ? LIMB[hands.mat] : 1;
  const footCol = feet ? MAT_COLOR[feet.mat] : 0x6b3f25, fs = feet ? LIMB[feet.mat] : 1;
  const eyes = [
    { s: 'sphere', p: [-0.09, 0.72, 0.235], k: [0.04, 0.055, 0.03], c: 0x1a1420 }, { s: 'sphere', p: [0.09, 0.72, 0.235], k: [0.04, 0.055, 0.03], c: 0x1a1420 },
    { s: 'sphere', p: [-0.078, 0.74, 0.257], k: 0.014, c: 0xffffff }, { s: 'sphere', p: [0.102, 0.74, 0.257], k: 0.014, c: 0xffffff }];
  const parts = [
    { s: 'sphere', p: [-0.1, 0.07, 0.03], k: [0.09 * fs, 0.07 * fs, 0.12 * fs], c: footCol }, { s: 'sphere', p: [0.1, 0.07, 0.03], k: [0.09 * fs, 0.07 * fs, 0.12 * fs], c: footCol },
    { s: 'sphere', p: [0, 0.32, 0], k: [0.24 * th, 0.25 * th, 0.21 * th], c: bodyCol },
    { s: 'cyl', p: [0, 0.25, 0], k: [0.238 * th, 0.05, 0.208 * th], c: 0x7a4a28 },
    { s: 'sphere', p: [0, 0.26, 0.205 * th], k: [0.045, 0.04, 0.02], c: 0xffd35a },
    { s: 'torus', p: [0, 0.5, 0], r: [Math.PI / 2, 0, 0], k: 0.15 * th, tube: 0.4, c: 0xe0443a },
    { s: 'cone', p: [0.06, 0.44, -0.2 * th], r: [-0.5, 0, 0.3], k: [0.06, 0.18, 0.04], c: 0xe0443a },
    { s: 'sphere', p: [0, 0.75, 0], k: 0.27, c: SKIN },
    { s: 'sphere', p: [0, 0.8, -0.05], k: [0.285, 0.23, 0.28], c: 0x5a3020 },
    { s: 'sphere', p: [0.05, 0.83, 0.2], k: [0.15, 0.06, 0.08], r: [0, 0, -0.2], c: 0x5a3020 },
    ...eyes,
    { s: 'sphere', p: [-0.16, 0.65, 0.2], k: [0.045, 0.025, 0.02], c: 0xff9a9a }, { s: 'sphere', p: [0.16, 0.65, 0.2], k: [0.045, 0.025, 0.02], c: 0xff9a9a },
    { s: 'sphere', p: [-0.27, 0.36, 0.04], k: 0.075 * hs, c: handCol }, { s: 'sphere', p: [0.28, 0.4, 0.07], k: 0.075 * hs, c: handCol },
    { s: 'cyl', p: [0.31, 0.5, 0.09], r: [0.15, 0, -0.15], k: [0.028, 0.32, 0.028], c: 0x5a3a22 },
    { s: 'cyl', p: [0.33, 0.64, 0.1], k: [0.05, 0.05, 0.05], c: 0x3a2a1a },
  ];
  // 몸통 재질: 가죽 끈 / 사슬 줄무늬 / 판금 어깨받이
  if (body?.mat === 'leather') parts.push({ s: 'box', p: [0, 0.36, 0.19 * th], r: [0, 0, 0.7], k: [0.06, 0.42, 0.03], c: 0x5a3a22 });
  if (body?.mat === 'chain') for (const y of [0.22, 0.32, 0.42]) parts.push({ s: 'torus', p: [0, y, 0], r: [Math.PI / 2, 0, 0], k: [0.23 * th, 0.2 * th, 0.2 * th], tube: 0.06, c: 0x6a7280 });
  if (body?.mat === 'plate') parts.push({ s: 'sphere', p: [-0.24, 0.47, 0], k: [0.1, 0.07, 0.1], c: 0xe8eef6 }, { s: 'sphere', p: [0.24, 0.47, 0], k: [0.1, 0.07, 0.1], c: 0xe8eef6 }, { s: 'box', p: [0, 0.36, 0.2 * th], k: [0.2, 0.18, 0.03], c: 0xf2f6fa });
  // 머리
  const legendHead = eq.head && eq.head.rarity === 'legend';
  if (!head) parts.push({ s: 'sphere', p: [0, 0.9, -0.02], k: [0.27, 0.17, 0.27], c: 0x2f7fe0 }, { s: 'cyl', p: [0, 0.86, 0.02], k: [0.29, 0.04, 0.29], c: 0xf2e6c8 }, { s: 'cone', p: [0.2, 1.02, -0.08], r: [0.3, 0, -0.9], k: [0.05, 0.22, 0.03], c: 0xe0443a });
  else if (legendHead) parts.push({ s: 'cyl', p: [0, 0.95, 0], k: [0.2, 0.08, 0.2], c: 0xffc83a }, ...[0, 1, 2, 3, 4].map((k) => ({ s: 'cone', p: [Math.cos(k * 1.2566) * 0.17, 1.05, Math.sin(k * 1.2566) * 0.17], k: [0.04, 0.12, 0.04], c: 0xffd84a })));
  else if (head.mat === 'cloth') parts.push({ s: 'sphere', p: [0, 0.82, -0.04], k: [0.3, 0.27, 0.3], c: MAT_COLOR.cloth }, { s: 'cone', p: [0, 1.02, -0.16], r: [-0.6, 0, 0], k: [0.08, 0.22, 0.08], c: MAT_COLOR.cloth });
  else if (head.mat === 'leather') parts.push({ s: 'cyl', p: [0, 0.88, 0], k: [0.38, 0.03, 0.38], c: 0x7a4a28 }, { s: 'sphere', p: [0, 0.93, -0.02], k: [0.24, 0.14, 0.24], c: 0x9a6a3a });
  else parts.push({ s: 'sphere', p: [0, 0.86, -0.01], k: [0.29, 0.21, 0.29], c: MAT_COLOR[head.mat] }, { s: 'box', p: [0, 0.76, 0.27], k: [0.035, 0.14, 0.03], c: 0x8a92a0 },
    ...(head.mat === 'plate' ? [{ s: 'cone', p: [-0.24, 1.0, 0], r: [0, 0, 0.7], k: [0.05, 0.22, 0.05], c: 0xf2ead8 }, { s: 'cone', p: [0.24, 1.0, 0], r: [0, 0, -0.7], k: [0.05, 0.22, 0.05], c: 0xf2ead8 }] : []));
  // 목걸이 보석
  if (eq.neck) { const el = eq.neck.affixes.find((a) => NECK_GEM[a.id] && a.known); parts.push({ s: 'oct', p: [0, 0.47, 0.19 * th], k: 0.045, c: el ? NECK_GEM[el.id] : 0xc07aff }); }
  // 등: 방패(등급색 테두리) · 두 번째 무기는 extra에서
  if (offB && off.base === 'shield') parts.push({ s: 'cyl', p: [0, 0.37, -0.25 * th], r: [Math.PI / 2, 0, 0], k: [0.22, 0.05, 0.22], c: 0x9a6a3e }, { s: 'torus', p: [0, 0.37, -0.28 * th], k: 0.21, tube: 0.12, c: off.rarity === 'common' ? 0x9aa6b8 : { magic: 0x5a9aff, rare: 0xffd84a, legend: 0xff8a2a }[off.rarity] }, { s: 'sphere', p: [0, 0.37, -0.3 * th], k: [0.05, 0.05, 0.03], c: 0xffd35a });
  let top = 'common'; for (const k of SLOTS) if (eq[k] && RARITY_ORDER.indexOf(eq[k].rarity) > RARITY_ORDER.indexOf(top)) top = eq[k].rarity;
  const legend = SLOTS.some((k) => eq[k] && eq[k].legend && k !== 'off');
  const torchBig = off && off.base === 'torch';
  return {
    h: 1.15, col: bodyCol, scale: 1, glow: GLOW[top], gloss: 0.75 + RARITY_ORDER.indexOf(top) * 0.18,
    parts,
    extra: (d) => {
      const f = new THREE.Group(), fs2 = torchBig ? 1.5 : 1;
      const o = new THREE.Mesh(new THREE.ConeGeometry(0.08 * fs2, 0.22 * fs2, 7).translate(0, 0.11 * fs2, 0), new THREE.MeshBasicMaterial({ color: new THREE.Color(2.6, 0.9, 0.2) }));
      const i = new THREE.Mesh(new THREE.ConeGeometry(0.045 * fs2, 0.14 * fs2, 7).translate(0, 0.07 * fs2, 0), new THREE.MeshBasicMaterial({ color: new THREE.Color(3, 2.5, 1) }));
      f.add(o, i); f.position.set(0.335, 0.66, 0.1); d.body.add(f);
      const wh = new THREE.Group(); wh.position.set(-0.28, 0.37, 0.06); wh.rotation.x = 0.5; d.body.add(wh);
      if (isWeapon(off)) { const bw = weaponDoll(weaponId(off)); bw.root.position.set(0.1, 0.25, -0.26 * th); bw.root.rotation.set(0.2, 0, -0.7); bw.root.scale.setScalar(0.9); d.body.add(bw.root); }
      return {
        wh,
        update(dt, t) {
          const s = 1 + Math.sin(t * 20) * 0.12 + Math.sin(t * 33) * 0.08; o.scale.set(1, s, 1); i.scale.set(1, s * 1.05, 1); f.rotation.z = Math.sin(t * 6) * 0.1;
          if (Math.random() < dt * 8 * fs2) { f.getWorldPosition(_w); _w.y += 0.2; View.dio.sparks.emit({ pos: _w, n: 1, color: 0xff9a3a, color2: 0xffe36a, speed: 0.3, up: 1.2, grav: 0.6, life: 0.6, size: 0.07 }); }
          if (legend && d.root.visible && Math.random() < dt * 14) { // 전설: 몸 주위를 도는 작은 불꽃
            const a = t * 2.4 + Math.floor(Math.random() * 5) * 1.2566; d.root.getWorldPosition(_w);
            View.dio.sparks.emit({ pos: _w.set(_w.x + Math.cos(a) * 0.5, _w.y + 0.5 + Math.sin(t * 3 + a) * 0.15, _w.z + Math.sin(a) * 0.5), n: 1, color: 0xff8a2a, color2: 0xffd84a, speed: 0.1, up: 0.4, grav: 0, life: 0.5, size: 0.1 });
          }
        },
      };
    },
  };
}
