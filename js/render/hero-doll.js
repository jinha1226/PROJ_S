import * as THREE from 'three';
import { BRANDS, EGOS, ELEM, GEAR_BASES, MAT_COLOR, SLOTS, weaponId } from '../data/gear.js';
import { COLORS } from '../data/stones.js';
import { torchTier } from '../data/torch.js';
import { WEAPONS } from '../data/weapons.js';
import { G } from '../core/state.js';
import { SKIN, _w } from './common.js';
import * as K from './diorama.js';
import { GLOW_TEX, GRIP2 } from './dolls.js';
import { View } from './view.js';

/* ---------- 주인공 인형: 입은 장비가 모양을 바꾼다 (docs/설계_아이템_장비.md §11) ---------- */
const THICK = { cloth: 1, leather: 1.04, chain: 1.08, plate: 1.15 };
const LIMB = { cloth: 1.05, leather: 1.12, chain: 1.18, plate: 1.28 };
/** 테두리광: 속성 = 원소 색 기운, 랜다트 = 보랏빛, 픽다트 = 금빛 (등급 색 광택은 없다) */
const GLOW = { randart: [0.1, 0.03, 0.14], unrand: [0.16, 0.1, 0] };
const NECK_GEM = { memory: 0xffd070, regen: 0x6ae08a, chain: 0xb45aff, reflect: 0xdfe8f0, silence: 0x6a9aff };

export function heroSpec(eq = {}) {
  const B = (slot) => eq[slot] && GEAR_BASES[eq[slot].base];
  const body = B('body'), head = B('head'), hands = B('hands'), feet = B('feet'), sh = eq.off, ob = sh && GEAR_BASES[sh.base]?.orb;
  const bodyCol = body ? MAT_COLOR[body.mat] : 0x3f86d8, th = body ? THICK[body.mat] : 1;
  const handCol = hands ? MAT_COLOR[hands.mat] : SKIN, hs = hands ? LIMB[hands.mat] : 1;
  const footCol = feet ? MAT_COLOR[feet.mat] : 0x6b3f25, fs = feet ? LIMB[feet.mat] : 1;
  const trimCol = body?.mat === 'plate' ? 0xdfe8f0 : body?.mat === 'chain' ? 0x9aa7b8 : body?.mat === 'leather' ? 0xc08a4d : 0xf2db9f;
  const wid = eq.weapon && weaponId(eq.weapon), two = !!(wid && WEAPONS[wid]?.hands === 2); // 양손 무기: 왼손도 자루를 쥐고 횃불은 허리에
  const eyes = [
    { s: 'sphere', p: [-0.09, 0.72, 0.235], k: [0.04, 0.055, 0.03], c: 0x1a1420 }, { s: 'sphere', p: [0.09, 0.72, 0.235], k: [0.04, 0.055, 0.03], c: 0x1a1420 },
    { s: 'sphere', p: [-0.078, 0.74, 0.257], k: 0.014, c: 0xffffff }, { s: 'sphere', p: [0.102, 0.74, 0.257], k: 0.014, c: 0xffffff }];
  const parts = [
    { s: 'sphere', p: [-0.1, 0.07, 0.03], k: [0.09 * fs, 0.07 * fs, 0.12 * fs], c: footCol }, { s: 'sphere', p: [0.1, 0.07, 0.03], k: [0.09 * fs, 0.07 * fs, 0.12 * fs], c: footCol },
    { s: 'cyl', p: [-0.1, 0.16, 0.01], k: [0.075 * fs, 0.055, 0.08 * fs], c: 0x4b382e }, { s: 'cyl', p: [0.1, 0.16, 0.01], k: [0.075 * fs, 0.055, 0.08 * fs], c: 0x4b382e },
    { s: 'sphere', p: [0, 0.32, 0], k: [0.24 * th, 0.25 * th, 0.21 * th], c: bodyCol },
    { s: 'sphere', p: [-0.235 * th, 0.43, 0], k: [0.105, 0.11, 0.12], c: bodyCol }, { s: 'sphere', p: [0.235 * th, 0.43, 0], k: [0.105, 0.11, 0.12], c: bodyCol },
    { s: 'box', p: [0, 0.38, 0.205 * th], k: [0.13, 0.18, 0.025], c: trimCol },
    { s: 'box', p: [0, 0.38, 0.229 * th], k: [0.025, 0.2, 0.015], c: 0x7b5638 },
    { s: 'cyl', p: [0, 0.25, 0], k: [0.238 * th, 0.05, 0.208 * th], c: 0x7a4a28 },
    { s: 'sphere', p: [0, 0.26, 0.205 * th], k: [0.045, 0.04, 0.02], c: 0xffd35a },
    { s: 'box', p: [-0.235 * th, 0.25, 0.02], k: [0.085, 0.12, 0.13], c: 0x785332 },
    { s: 'sphere', p: [-0.235 * th, 0.29, 0.092], k: 0.023, c: 0xe1be77 },
    { s: 'torus', p: [0, 0.5, 0], r: [Math.PI / 2, 0, 0], k: 0.15 * th, tube: 0.4, c: 0xe0443a },
    { s: 'cone', p: [0.06, 0.44, -0.2 * th], r: [-0.5, 0, 0.3], k: [0.06, 0.18, 0.04], c: 0xe0443a },
    { s: 'sphere', p: [0, 0.75, 0], k: 0.27, c: SKIN },
    { s: 'sphere', p: [0, 0.8, -0.05], k: [0.285, 0.23, 0.28], c: 0x5a3020 },
    { s: 'sphere', p: [0.05, 0.83, 0.2], k: [0.15, 0.06, 0.08], r: [0, 0, -0.2], c: 0x5a3020 },
    ...eyes,
    { s: 'sphere', p: [0, 0.68, 0.265], k: [0.035, 0.04, 0.028], c: 0xe9b391 },
    { s: 'box', p: [0, 0.605, 0.25], k: [0.075, 0.012, 0.015], c: 0x8f5149 },
    { s: 'box', p: [-0.09, 0.79, 0.238], r: [0, 0, -0.12], k: [0.085, 0.024, 0.02], c: 0x5a3020 },
    { s: 'box', p: [0.09, 0.79, 0.238], r: [0, 0, 0.12], k: [0.085, 0.024, 0.02], c: 0x5a3020 },
    { s: 'sphere', p: [-0.16, 0.65, 0.2], k: [0.045, 0.025, 0.02], c: 0xff9a9a }, { s: 'sphere', p: [0.16, 0.65, 0.2], k: [0.045, 0.025, 0.02], c: 0xff9a9a },
    { s: 'sphere', p: [-0.27, 0.36, 0.04], k: 0.075 * hs, c: handCol },
    ...(two ? [{ s: 'cyl', p: [0.24, 0.28, 0.1], r: [0.3, 0, -0.5], k: [0.024, 0.22, 0.024], c: 0x5a3a22 }, { s: 'cyl', p: [0.29, 0.37, 0.125], k: [0.042, 0.04, 0.042], c: 0x3a2a1a }]
      : [{ s: 'sphere', p: [0.28, 0.4, 0.07], k: 0.075 * hs, c: handCol }, { s: 'cyl', p: [0.31, 0.5, 0.09], r: [0.15, 0, -0.15], k: [0.028, 0.32, 0.028], c: 0x5a3a22 }, { s: 'cyl', p: [0.33, 0.64, 0.1], k: [0.05, 0.05, 0.05], c: 0x3a2a1a }]),
  ];
  if (!eq.cloak) parts.push(
    { s: 'box', p: [0, 0.37, -0.27 * th], k: [0.34, 0.37, 0.12], c: 0x705039 },
    { s: 'cyl', p: [0, 0.59, -0.29 * th], r: [0, 0, Math.PI / 2], k: [0.075, 0.31, 0.075], c: 0xcdbb8c },
    { s: 'box', p: [-0.13, 0.43, -0.355 * th], k: [0.035, 0.27, 0.025], c: 0xc09458 },
    { s: 'box', p: [0.13, 0.43, -0.355 * th], k: [0.035, 0.27, 0.025], c: 0xc09458 },
  );
  // 몸통 재질: 가죽 끈 / 사슬 줄무늬 / 판금 어깨받이
  if (body?.mat === 'leather') parts.push({ s: 'box', p: [0, 0.36, 0.19 * th], r: [0, 0, 0.7], k: [0.06, 0.42, 0.03], c: 0x5a3a22 });
  if (body?.mat === 'chain') for (const y of [0.22, 0.32, 0.42]) parts.push({ s: 'torus', p: [0, y, 0], r: [Math.PI / 2, 0, 0], k: [0.23 * th, 0.2 * th, 0.2 * th], tube: 0.06, c: 0x6a7280 });
  if (body?.mat === 'plate') parts.push({ s: 'sphere', p: [-0.24, 0.47, 0], k: [0.1, 0.07, 0.1], c: 0xe8eef6 }, { s: 'sphere', p: [0.24, 0.47, 0], k: [0.1, 0.07, 0.1], c: 0xe8eef6 }, { s: 'box', p: [0, 0.36, 0.2 * th], k: [0.2, 0.18, 0.03], c: 0xf2f6fa });
  // 머리
  const legendHead = eq.head && eq.head.un === 'namelessHelm';
  if (!head) parts.push({ s: 'sphere', p: [0, 0.9, -0.02], k: [0.27, 0.17, 0.27], c: 0x2f7fe0 }, { s: 'cyl', p: [0, 0.86, 0.02], k: [0.29, 0.04, 0.29], c: 0xf2e6c8 }, { s: 'sphere', p: [0, 0.905, 0.245], k: [0.06, 0.05, 0.02], c: 0xffd06b }, { s: 'cone', p: [0.2, 1.02, -0.08], r: [0.3, 0, -0.9], k: [0.05, 0.22, 0.03], c: 0xe0443a });
  else if (legendHead) parts.push({ s: 'cyl', p: [0, 0.95, 0], k: [0.2, 0.08, 0.2], c: 0xffc83a }, ...[0, 1, 2, 3, 4].map((k) => ({ s: 'cone', p: [Math.cos(k * 1.2566) * 0.17, 1.05, Math.sin(k * 1.2566) * 0.17], k: [0.04, 0.12, 0.04], c: 0xffd84a })));
  else if (head.mat === 'cloth') parts.push({ s: 'sphere', p: [0, 0.82, -0.04], k: [0.3, 0.27, 0.3], c: MAT_COLOR.cloth }, { s: 'cone', p: [0, 1.02, -0.16], r: [-0.6, 0, 0], k: [0.08, 0.22, 0.08], c: MAT_COLOR.cloth });
  else if (head.mat === 'leather') parts.push({ s: 'cyl', p: [0, 0.88, 0], k: [0.38, 0.03, 0.38], c: 0x7a4a28 }, { s: 'sphere', p: [0, 0.93, -0.02], k: [0.24, 0.14, 0.24], c: 0x9a6a3a });
  else parts.push({ s: 'sphere', p: [0, 0.86, -0.01], k: [0.29, 0.21, 0.29], c: MAT_COLOR[head.mat] }, { s: 'box', p: [0, 0.76, 0.27], k: [0.035, 0.14, 0.03], c: 0x8a92a0 },
    ...(head.mat === 'plate' ? [{ s: 'cone', p: [-0.24, 1.0, 0], r: [0, 0, 0.7], k: [0.05, 0.22, 0.05], c: 0xf2ead8 }, { s: 'cone', p: [0.24, 1.0, 0], r: [0, 0, -0.7], k: [0.05, 0.22, 0.05], c: 0xf2ead8 }] : []));
  // 목걸이: 보석 색은 종류, 첫 불씨 등잔은 가슴의 작은 등잔
  if (eq.neck && eq.neck.un === 'firstLamp') parts.push({ s: 'cyl', p: [0, 0.44, 0.21 * th], k: [0.06, 0.09, 0.06], c: 0x6a4a2a }, { s: 'sphere', p: [0, 0.45, 0.22 * th], k: 0.045, c: 0xffd070 });
  else if (eq.neck) parts.push({ s: 'oct', p: [0, 0.47, 0.19 * th], k: 0.045, c: NECK_GEM[eq.neck.jt] || 0xc07aff });
  // 망토: 등 뒤 천(물안개 망토는 물빛)
  if (eq.cloak) parts.push({ s: 'box', p: [0, 0.38, -0.21 * th], r: [0.15, 0, 0], k: [0.42 * th, 0.5, 0.04], c: eq.cloak.un === 'mistCloak' ? 0x6aa8d8 : eq.cloak.ego ? 0x5a3a6a : 0x7a2a2a }, { s: 'sphere', p: [0, 0.6, -0.12 * th], k: [0.2, 0.05, 0.1], c: 0xd8b04a });
  // 보조손: 방패(속성이면 테두리에 그 색). 오브는 extra에서 왼손 옆에 띄운다
  if (sh && !ob) { const r = sh.base === 'shield' ? 0.2 : 0.14, rim = sh.ego && sh.idX ? (EGOS[sh.ego].res ? ELEM[EGOS[sh.ego].res].hex : 0xd8c8a8) : sh.un ? 0xffcf4a : sh.art ? 0xd0a0ff : 0x9aa6b8; parts.push({ s: 'cyl', p: [-0.38, 0.4, 0.06], r: [0, 0, Math.PI / 2], k: [r, 0.05, r], c: 0x9a6a3e }, { s: 'torus', p: [-0.41, 0.4, 0.06], r: [0, Math.PI / 2, 0], k: r, tube: 0.12, c: rim }, { s: 'sphere', p: [-0.43, 0.4, 0.06], k: [0.03, 0.05, 0.05], c: 0xffd35a }); }
  const all = SLOTS.map((k) => eq[k]).filter(Boolean), legend = all.some((it) => it.un), art = all.some((it) => it.art);
  const top = legend ? 'unrand' : art ? 'randart' : null, bright = all.some((it) => it.plus >= 3), torchBig = false;
  const pw = eq.weapon && eq.weapon.idX && eq.weapon.brand ? BRANDS[eq.weapon.brand] : null, elemGlow = pw && pw.elem ? new THREE.Color(ELEM[pw.elem].hex).multiplyScalar(0.12).toArray() : null;
  return {
    h: 1.15, col: bodyCol, scale: 1, glow: GLOW[top] || elemGlow, gloss: 0.75 + (bright ? 0.45 : 0) + (top ? 0.2 : 0),
    parts,
    extra: (d) => {
      const f = new THREE.Group(), fs2 = torchBig ? 1.5 : 1;
      const o = new THREE.Mesh(new THREE.ConeGeometry(0.08 * fs2, 0.22 * fs2, 7).translate(0, 0.11 * fs2, 0), new THREE.MeshBasicMaterial({ color: new THREE.Color(2.6, 0.9, 0.2) }));
      const i = new THREE.Mesh(new THREE.ConeGeometry(0.045 * fs2, 0.14 * fs2, 7).translate(0, 0.07 * fs2, 0), new THREE.MeshBasicMaterial({ color: new THREE.Color(3, 2.5, 1) }));
      f.add(o, i); f.position.set(...(two ? [0.295, 0.37, 0.13] : [0.335, 0.66, 0.1])); d.body.add(f);
      const wh = new THREE.Group(); wh.position.set(-0.28, 0.37, 0.06); wh.rotation.x = 0.5; d.body.add(wh);
      // 양손 무기: 둘째 손이 자루를 함께 쥔다(무기와 같이 휘두른다, setWeapon이 지우지 않게 keep)
      if (two && GRIP2[wid]) { const h2 = K.doll([{ s: 'sphere', k: 0.075 * hs, c: handCol }], { gloss: 0.75 }).root; h2.position.set(...GRIP2[wid]); h2.userData.keep = true; wh.add(h2); }
      // 오브: 그 색으로 빛나는 구슬이 왼손 옆에 떠서 천천히 돈다
      let orb = null;
      if (ob) {
        const c = COLORS[ob].hex; orb = new THREE.Group(); orb.position.set(0.46, 0.42, 0.1);
        const core = new THREE.Mesh(new THREE.SphereGeometry(0.065, 16, 12), new THREE.MeshBasicMaterial({ color: new THREE.Color(c).multiplyScalar(1.8) }));
        const hi = new THREE.Mesh(new THREE.SphereGeometry(0.018, 8, 6), new THREE.MeshBasicMaterial({ color: 0xffffff })); hi.position.set(-0.022, 0.026, 0.045);
        const ring = new THREE.Mesh(new THREE.TorusGeometry(0.1, 0.008, 6, 28), new THREE.MeshBasicMaterial({ color: new THREE.Color(c).multiplyScalar(1.4) })); ring.rotation.x = 1.1;
        const halo = new THREE.Sprite(new THREE.SpriteMaterial({ map: GLOW_TEX, color: c, blending: THREE.AdditiveBlending, transparent: true, depthWrite: false, opacity: 0.8 })); halo.scale.setScalar(0.42);
        orb.add(core, hi, ring, halo); orb.userData.ring = ring; d.body.add(orb);
      }
      return {
        wh,
        update(dt, t) {
          if (orb) { orb.position.y = 0.42 + Math.sin(t * 2) * 0.03; orb.userData.ring.rotation.set(1.1, t * 1.2, 0); }
          const tier = torchTier(G.torch ?? 100), size = { high: 1, mid: 0.72, low: 0.4, out: 0.16 }[tier];
          const s = 1 + Math.sin(t * 20) * 0.12 + Math.sin(t * 33) * 0.08;
          o.scale.set(size, size * s, size); i.scale.set(size, size * s * 1.05, size);
          o.material.color.setHex(tier === 'out' ? 0x713327 : tier === 'low' ? 0xff7137 : 0xff9c35);
          i.visible = tier !== 'out'; f.rotation.z = Math.sin(t * 6) * 0.1;
          if (tier !== 'out' && Math.random() < dt * 8 * fs2 * size) { f.getWorldPosition(_w); _w.y += 0.2; View.dio.sparks.emit({ pos: _w, n: 1, color: 0xff9a3a, color2: 0xffe36a, speed: 0.3, up: 1.2, grav: 0.6, life: 0.6, size: 0.07 }); }
          if (legend && d.root.visible && Math.random() < dt * 14) { // 전설: 몸 주위를 도는 작은 불꽃
            const a = t * 2.4 + Math.floor(Math.random() * 5) * 1.2566; d.root.getWorldPosition(_w);
            View.dio.sparks.emit({ pos: _w.set(_w.x + Math.cos(a) * 0.5, _w.y + 0.5 + Math.sin(t * 3 + a) * 0.15, _w.z + Math.sin(a) * 0.5), n: 1, color: 0xff8a2a, color2: 0xffd84a, speed: 0.1, up: 0.4, grav: 0, life: 0.5, size: 0.1 });
          }
        },
      };
    },
  };
}
