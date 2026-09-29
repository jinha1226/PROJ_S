import * as THREE from 'three';
import { BRANDS, EGOS, ELEM, GEAR_BASES, MAT_COLOR, SLOTS, weaponId } from '../data/gear.js';
import { COLORS } from '../data/stones.js';
import { WEAPONS } from '../data/weapons.js';
import { SKIN, _w } from './common.js';
import * as K from './diorama.js';
import { GLOW_TEX, GRIP2 } from './dolls.js';
import { hatParts, headParts } from './heads.js';
import { View } from './view.js';

/* ---------- 주인공 인형: 입은 장비가 모양을 바꾼다 (docs/설계_아이템_장비.md §11) ---------- */
const THICK = { cloth: 1, leather: 1.04, chain: 1.08, plate: 1.15 };
const LIMB = { cloth: 1.05, leather: 1.12, chain: 1.18, plate: 1.28 };
/** 테두리광: 속성 = 원소 색 기운, 랜다트 = 보랏빛, 픽다트 = 금빛 (등급 색 광택은 없다) */
const GLOW = { randart: [0.1, 0.03, 0.14], unrand: [0.16, 0.1, 0] };
const HAIR = 0x6e4a30;
const NECK_GEM = { memory: 0xffd070, regen: 0x6ae08a, chain: 0xb45aff, reflect: 0xdfe8f0, silence: 0x6a9aff };

export function heroSpec(eq = {}) {
  const B = (slot) => eq[slot] && GEAR_BASES[eq[slot].base];
  const body = B('body'), head = B('head'), hands = B('hands'), feet = B('feet'), sh = eq.off, ob = sh && GEAR_BASES[sh.base]?.orb;
  const bodyCol = body ? MAT_COLOR[body.mat] : 0xe8d8b0, th = body ? THICK[body.mat] : 1;
  const coatCol = !body || body.mat === 'cloth' ? 0x557660 : bodyCol;
  const shirtCol = !body || body.mat === 'cloth' ? 0xe8d8b0 : bodyCol;
  const handCol = hands ? MAT_COLOR[hands.mat] : SKIN, hs = hands ? LIMB[hands.mat] : 1;
  const footCol = feet ? MAT_COLOR[feet.mat] : 0x6b3f25, fs = feet ? LIMB[feet.mat] : 1;
  const wid = eq.weapon && weaponId(eq.weapon), two = !!(wid && WEAPONS[wid]?.hands === 2); // 양손 무기: 왼손도 자루를 쥐고 횃불은 허리에
  // 몸: 단면을 돌린 한 덩어리 겉옷(아래 주름) + 굽은 팔·다리 관 — 도형을 붙인 티가 덜 나게 (몸통 재질은 칠하기로)
  const mat = body ? body.mat : 'cloth', T = th, sleeve = mat === 'plate' ? 0xc8d2de : coatCol;
  const coatPaint = [{ c: shirtCol, a: 0.62, vee: true, y0: 0.3, y1: 0.54 }]; // 앞섶(V)
  if (mat === 'chain') coatPaint.unshift({ c: 0x4c535e, band: 0.04, y0: 0.14, y1: 0.46 }); // 사슬 줄(앞섶이 위에)
  if (mat === 'plate') coatPaint.push({ c: 0xf2f6fa, a: 0.9, y0: 0.3, y1: 0.47 }); // 가슴판
  if (mat === 'leather') coatPaint.push({ c: 0x7a4e2c, y0: 0.12, y1: 0.19 }); // 가죽 밑단
  const legs = [-1, 1].flatMap((sx) => [
    { s: 'tube', path: [[0.1 * sx, 0.3, 0], [0.108 * sx, 0.2, 0.012], [0.115 * sx, 0.12, 0.01]], r0: 0.07, r1: 0.06, c: 0x49453e, shade: 0.2 },
    { s: 'lathe', p: [0.115 * sx, 0, 0.01], pts: [[0, 0.005], [0.082 * fs, 0.006], [0.09 * fs, 0.05], [0.08 * fs, 0.15], [0.09 * fs, 0.175], [0, 0.18]], seg: 16, c: footCol, shade: 0.25 },
    { s: 'sphere', p: [0.115 * sx, 0.048, 0.07], k: [0.08 * fs, 0.05 * fs, 0.1 * fs], c: footCol },
  ]);
  const arm = (sx, path) => [{ s: 'tube', path, r0: 0.078, r1: 0.056, c: sleeve, shade: 0.12 }, { s: 'torus', p: path[path.length - 1], r: [Math.PI / 2, 0, 0.4 * sx], k: [0.058, 0.058, 0.09], tube: 0.4, c: shirtCol }];
  const parts = [
    ...legs,
    { s: 'lathe', pts: [[0, 0.13], [0.22 * T, 0.118], [0.245 * T, 0.13], [0.222 * T, 0.2], [0.185 * T, 0.272], [0.2 * T, 0.34], [0.215 * T, 0.405], [0.205 * T, 0.458], [0.155 * T, 0.505], [0.085, 0.532], [0, 0.545]], k: [1, 1, 0.86], seg: 28, wave: 0.07, waveN: 7, waveTop: 0.26, c: coatCol, paint: coatPaint, shade: 0.22 },
    { s: 'torus', p: [0, 0.272, 0], r: [Math.PI / 2, 0, 0], k: [0.192 * T, 0.167 * T, 0.13], tube: 0.22, c: 0x775239 }, // 허리띠
    { s: 'box', p: [0, 0.272, 0.166 * T], k: [0.06, 0.05, 0.02], c: 0xc6a267, outline: false }, // 버클
    { s: 'torus', p: [0, 0.525, 0], r: [Math.PI / 2, 0, 0], k: [0.1, 0.09, 0.1], tube: 0.45, c: shirtCol }, // 옷깃
    ...arm(-1, [[-0.18 * T, 0.465, 0], [-0.25 * T, 0.41, 0.02], [-0.275, 0.355, 0.05]]),
    { s: 'sphere', p: [-0.28, 0.335, 0.055], k: 0.068 * hs, c: handCol },
    ...(two ? [...arm(1, [[0.18 * T, 0.465, 0], [0.245 * T, 0.38, 0.07], [0.215, 0.31, 0.12]]), ]
      : [...arm(1, [[0.18 * T, 0.465, 0], [0.235 * T, 0.38, 0.02], [0.25, 0.32, 0.05]]), { s: 'sphere', p: [0.255, 0.3, 0.06], k: 0.068 * hs, c: handCol }]), // 빈 손(횃불 빛은 조명이 맡는다)
  ];
  // 여행 장비: 어깨끈 + 허리 주머니(천·가죽)
  if (mat === 'cloth' || mat === 'leather') parts.push(
    { s: 'tube', path: [[-0.16 * T, 0.49, 0.1], [0, 0.4, 0.2 * T], [0.17 * T, 0.29, 0.13]], r0: 0.016, r1: 0.016, rs: 6, c: 0x6b4a30, outline: false },
    { s: 'lathe', p: [-0.2 * T, 0.2, 0.1], r: [0, 0.6, 0], pts: [[0, 0.0], [0.06, 0.005], [0.068, 0.05], [0.058, 0.1], [0, 0.104]], k: [1, 1, 0.7], seg: 12, c: 0x76563b, shade: 0.2 },
  );
  // 판금 어깨받이: 둥근 덮개
  if (mat === 'plate') for (const sx of [-1, 1]) parts.push({ s: 'lathe', p: [0.19 * sx * T, 0.44, 0], r: [0, 0, -0.35 * sx], pts: [[0, 0.075], [0.07, 0.07], [0.11, 0.035], [0.12, 0], [0.105, -0.01]], seg: 16, c: 0xe8eef6, shade: 0.15 });
  // 머리
  const legendHead = eq.head && eq.head.un === 'namelessHelm';
  // 얼굴 · 머리 모양(모자를 쓰면 옆·뒷머리만, 투구·두건이면 옆머리만)
  parts.push(...headParts({ skin: SKIN, hair: HAIR, eye: 0x3b4b40, style: 'short', cover: !head || legendHead ? 0 : head.mat === 'leather' ? 1 : 2 }));
  if (legendHead) parts.push({ s: 'cyl', p: [0, 0.95, 0], k: [0.2, 0.08, 0.2], c: 0xffc83a }, ...[0, 1, 2, 3, 4].map((k) => ({ s: 'cone', p: [Math.cos(k * 1.2566) * 0.17, 1.05, Math.sin(k * 1.2566) * 0.17], k: [0.04, 0.12, 0.04], c: 0xffd84a })));
  else if (head?.mat === 'cloth') parts.push(...hatParts('hood', { c: MAT_COLOR.cloth, trim: 0xb8a070 }));
  else if (head?.mat === 'leather') parts.push(...hatParts('hat', { c: 0x9a6a3a, trim: 0x6a4020 }));
  else if (head) parts.push(...hatParts('helm', { c: MAT_COLOR[head.mat], trim: 0x8a92a0 }),
    ...(head.mat === 'plate' ? [{ s: 'cone', p: [-0.24, 1.0, 0], r: [0, 0, 0.7], k: [0.05, 0.22, 0.05], c: 0xf2ead8 }, { s: 'cone', p: [0.24, 1.0, 0], r: [0, 0, -0.7], k: [0.05, 0.22, 0.05], c: 0xf2ead8 }] : []));
  // 목걸이: 보석 색은 종류, 첫 불씨 등잔은 가슴의 작은 등잔
  if (eq.neck && eq.neck.un === 'firstLamp') parts.push({ s: 'cyl', p: [0, 0.44, 0.21 * th], k: [0.06, 0.09, 0.06], c: 0x6a4a2a }, { s: 'sphere', p: [0, 0.45, 0.22 * th], k: 0.045, c: 0xffd070 });
  else if (eq.neck) parts.push({ s: 'oct', p: [0, 0.47, 0.19 * th], k: 0.045, c: NECK_GEM[eq.neck.jt] || 0xc07aff });
  // 망토: 등 뒤 천(물안개 망토는 물빛)
  if (eq.cloak) { const cc = eq.cloak.un === 'mistCloak' ? 0x6aa8d8 : eq.cloak.ego ? 0x5a3a6a : 0x7a2a2a; parts.push(
    { s: 'lathe', pts: [[0.28 * th, 0.1], [0.265 * th, 0.2], [0.24 * th, 0.34], [0.232 * th, 0.44], [0.19 * th, 0.5], [0.12, 0.54]], phi0: Math.PI / 2 + 0.25, phiLen: Math.PI - 0.5, k: [1, 1, 0.95], seg: 18, wave: 0.09, waveN: 9, waveTop: 0.42, c: cc, shade: 0.3 },
    { s: 'torus', p: [0, 0.535, 0], r: [Math.PI / 2, 0, 0], k: [0.12, 0.105, 0.1], tube: 0.35, c: cc },
    { s: 'sphere', p: [0, 0.52, 0.115], k: [0.035, 0.035, 0.02], c: 0xd8b04a }); }
  // 보조손: 방패(속성이면 테두리에 그 색). 오브는 extra에서 왼손 옆에 띄운다
  if (sh && !ob) { const r = sh.base === 'shield' ? 0.2 : 0.14, rim = sh.ego && sh.idX ? (EGOS[sh.ego].res ? ELEM[EGOS[sh.ego].res].hex : 0xd8c8a8) : sh.un ? 0xffcf4a : sh.art ? 0xd0a0ff : 0x9aa6b8; parts.push({ s: 'cyl', p: [-0.38, 0.4, 0.06], r: [0, 0, Math.PI / 2], k: [r, 0.05, r], c: 0x9a6a3e }, { s: 'torus', p: [-0.41, 0.4, 0.06], r: [0, Math.PI / 2, 0], k: r, tube: 0.12, c: rim }, { s: 'sphere', p: [-0.43, 0.4, 0.06], k: [0.03, 0.05, 0.05], c: 0xffd35a }); }
  const all = SLOTS.map((k) => eq[k]).filter(Boolean), legend = all.some((it) => it.un), art = all.some((it) => it.art);
  const top = legend ? 'unrand' : art ? 'randart' : null, bright = all.some((it) => it.plus >= 3);
  const pw = eq.weapon && eq.weapon.idX && eq.weapon.brand ? BRANDS[eq.weapon.brand] : null, elemGlow = pw && pw.elem ? new THREE.Color(ELEM[pw.elem].hex).multiplyScalar(0.12).toArray() : null;
  return {
    h: 1.15, col: bodyCol, scale: 1, glow: GLOW[top] || elemGlow, gloss: 0.22 + (bright ? 0.35 : 0) + (top ? 0.15 : 0), // 광택은 낮게(플라스틱처럼 번들거리지 않게)
    parts,
    extra: (d) => {
      const wh = new THREE.Group(); wh.position.set(-0.28, 0.37, 0.06); wh.rotation.x = 0.5; d.body.add(wh);
      // 양손 무기: 둘째 손이 자루를 함께 쥔다(무기와 같이 휘두른다, setWeapon이 지우지 않게 keep)
      if (two && GRIP2[wid]) { const h2 = K.doll([{ s: 'sphere', k: 0.075 * hs, c: handCol }], { gloss: 0.22 }).root; h2.position.set(...GRIP2[wid]); h2.userData.keep = true; wh.add(h2); }
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
          if (legend && d.root.visible && Math.random() < dt * 14) { // 전설: 몸 주위를 도는 작은 불꽃
            const a = t * 2.4 + Math.floor(Math.random() * 5) * 1.2566; d.root.getWorldPosition(_w);
            View.dio.sparks.emit({ pos: _w.set(_w.x + Math.cos(a) * 0.5, _w.y + 0.5 + Math.sin(t * 3 + a) * 0.15, _w.z + Math.sin(a) * 0.5), n: 1, color: 0xff8a2a, color2: 0xffd84a, speed: 0.1, up: 0.4, grav: 0, life: 0.5, size: 0.1 });
          }
        },
      };
    },
  };
}
