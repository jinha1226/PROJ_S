import * as K from '../render/diorama.js';
import { heroSpec } from '../render/hero-doll.js';
import { dollSpecBase, weaponDoll } from '../render/dolls.js';
import { Sfx } from '../render/sfx.js';
import { WEAPONS } from '../data/weapons.js';
import { walls } from './space.js';

const { THREE } = K;
const palette = { floor: 0x34313b, floor2: 0x3e3943, wall: 0x74717b, wall2: 0x5c5864, void: 0x08070c, grassFloor: 0x3b523c, waterFloor: 0x23445f, dim: 0.5 };
/** 파티원마다 다른 차림과 무기: 누가 휘둘렀는지 한눈에 보이게 */
const LOOK = {
  hero: { weapon: 'sword', eq: { body: { base: 'body_leather' }, cloak: { base: 'cloak' } } },
  guard: { weapon: 'mace', eq: { body: { base: 'body_plate' }, head: { base: 'head_chain' }, off: { base: 'shield' } } },
  sword: { weapon: 'greatsword', eq: { body: { base: 'body_chain' } } },
  archer: { weapon: 'crossbow', eq: { body: { base: 'body_leather' }, head: { base: 'head_leather' } } },
  healer: { weapon: null, eq: { body: { base: 'body_cloth' }, head: { base: 'head_cloth' }, off: { base: 'orb_green' } } },
};
const MELEE = new Set(['slash', 'blunt', 'counter']);
/** 맞은 쪽에 튀는 불꽃 색 */
const SPARK = { slash: [0xffffff, 0xffd98a], blunt: [0xffb45a, 0xfff0c0], arrow: [0xfff2d0, 0xc8b89a], orb: [0xb6ff9a, 0xfff6b0], water: [0x7fd0ff, 0xffffff], bolt: [0xffe14a, 0xffffff], counter: [0xffd46a, 0xffffff], cleave: [0xff6a3a, 0xffc070], scatter: [0xff4a4a, 0xffb070] };
const ease = (k) => 1 - Math.pow(1 - k, 3);
const V = (x, y, h = 0) => new THREE.Vector3(x, h, y);
const isFoe = (u) => u.role === 'boss' || u.role === 'add';

export class LabView {
  constructor(container, onTap) {
    this.labelRoot = document.createElement('div'); this.labelRoot.className = 'labels'; container.after(this.labelRoot);
    this.hurtEl = document.createElement('div'); this.hurtEl.className = 'hurtfx'; this.labelRoot.appendChild(this.hurtEl);
    this.dio = K.createDiorama(container, { preset: 'dungeon', labelRoot: this.labelRoot });
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
    this.actors = new Map(); this.areas = []; this.later = []; this.time = 0; this.slowT = 0; this.battle = null;
    this.dio.onFrame = (dt, real) => { this.update(dt, real ?? dt); this.onFrame?.(dt); };
    const light = new THREE.PointLight(0xffbe78, 13, 8); light.position.set(3, 2, 8); this.dio.scene.add(light);
    const wake = () => Sfx.init(); // 브라우저는 첫 입력 뒤에만 소리를 낸다
    addEventListener('pointerdown', wake); addEventListener('keydown', wake);
  }
  /** 새 전투: 쓰러진 인형·남은 연출을 치운다 */
  reset() {
    for (const a of this.actors.values()) { this.dio.scene.remove(a.doll.root); a.doll.root.traverse((o) => o.geometry?.dispose()); }
    this.actors.clear(); this.later.length = 0; this.dio.labels.clear(); this.dio.timeScale = 1; this.slowT = 0;
    this.clearAreas(); this.tele = null; this.hurtEl.classList.remove('on');
  }
  makeActor(u) {
    const look = LOOK[u.role];
    const eq = look && { ...look.eq, ...(look.weapon ? { weapon: { base: look.weapon } } : {}) };
    const sp = u.role === 'boss' ? dollSpecBase({ type: 'charger' }) : u.role === 'add' ? dollSpecBase({ type: 'goblin' }) : heroSpec(eq || {});
    const scale = u.role === 'boss' ? 2.1 : u.role === 'add' ? 0.85 : 1.15;
    const doll = K.doll(sp.parts, { scale, gloss: 0.28 });
    const ring = new THREE.Mesh(new THREE.RingGeometry(u.role === 'boss' ? 0.68 : 0.34, u.role === 'boss' ? 0.76 : 0.41, 32).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ color: u.color, side: THREE.DoubleSide, transparent: true, opacity: 0.9 }));
    ring.position.y = 0.08;
    doll.root.add(ring);
    let wh = null;
    if (look && sp.extra) {
      wh = sp.extra(doll).wh;
      if (look.weapon) wh.add(weaponDoll(look.weapon).root);
    }
    this.dio.scene.add(doll.root);
    const face = isFoe(u) ? -Math.PI / 2 : Math.PI / 2;
    const actor = {
      u, doll, ring, wh, form: look?.weapon ? WEAPONS[look.weapon].form : 'blunt', h: (sp.h || 1) * scale,
      cur: V(u.x, u.y), yaw: face, yawT: face, sq: 0, sqv: 0, flash: 0, flashCol: [1, 1, 1], jolt: new THREE.Vector3(),
      lunge: null, swing: null, hop: -1, dying: false, deadT: 0, pending: false, spawnT: u.role === 'add' ? 0 : 1, phase: Math.random() * 6,
    };
    doll.root.position.copy(actor.cur); doll.root.rotation.y = face;
    this.actors.set(u.id, actor); return actor;
  }
  actor(u) { return u && (this.actors.get(u.id) || this.makeActor(u)); }
  clearAreas() {
    for (const m of this.areas) { this.dio.scene.remove(m); m.geometry.dispose(); m.material.dispose(); }
    this.areas.length = 0;
  }
  area(geo, x, y, color, opacity, fill = false) {
    const mesh = new THREE.Mesh(geo.rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ color, transparent: true, opacity, depthWrite: false, side: THREE.DoubleSide }));
    mesh.position.set(x, fill ? 0.1 : 0.09, y); mesh.userData = { base: opacity, fill }; this.dio.scene.add(mesh); this.areas.push(mesh); return mesh;
  }
  /** 전투 상태를 따라간다: 예고 범위만 여기서 다시 그리고, 인형은 update가 부드럽게 옮긴다 */
  show(battle) {
    this.battle = battle;
    for (const u of battle.units) this.actor(u);
    const tele = battle.finished ? null : battle.tele; // 끝난 싸움에는 예고를 남기지 않는다
    if (this.tele === tele) return;
    this.tele = tele; this.clearAreas();
    const t = tele;
    if (!t) return;
    this.teleTotal = t.remaining;
    if (t.type === 'scatter') for (const at of t.at) {
      this.area(new THREE.RingGeometry(1.02, 1.15, 40), at.x, at.y, 0xff5a5a, 0.85);
      this.area(new THREE.CircleGeometry(1.15, 40), at.x, at.y, 0xf34750, 0.18);
      this.area(new THREE.CircleGeometry(1.15, 40), at.x, at.y, 0xff3040, 0.42, true);
    } else {
      // 판정(battle.inDanger)과 같은 부채꼴: 반지름 3.25, 코사인 0.58
      const bx = battle.boss.x, by = battle.boss.y, ang = Math.atan2(-(t.aim.y - by), t.aim.x - bx), half = Math.acos(0.58);
      this.area(new THREE.RingGeometry(3.1, 3.25, 48, 1, ang - half, half * 2), bx, by, 0xff5a5a, 0.85);
      this.area(new THREE.CircleGeometry(3.25, 48, ang - half, half * 2), bx, by, 0xf34750, 0.18);
      this.area(new THREE.CircleGeometry(3.25, 48, ang - half, half * 2), bx, by, 0xff3040, 0.42, true);
      const target = battle.party.find((u) => u.id === t.target) || battle.hero;
      this.area(new THREE.RingGeometry(0.3, 0.4, 28), target.x, target.y, 0xffbb6e, 0.9);
    }
  }
  after(sec, fn) { if (sec <= 0) fn(); else this.later.push({ t: sec, fn }); }

  /* ---------------- 전투가 알리는 일 ---------------- */
  fx(type, o, battle) {
    this.battle = battle;
    const D = this.dio;
    if (type === 'hit') this.hit(o);
    else if (type === 'heal') {
      const f = this.actor(o.from), t = this.actor(o.unit); if (!t) return;
      if (f) { f.sqv += 3; this.face(f, t.cur); }
      this.after(this.shoot(f, t, 'heal'), () => {
        D.sparks.emit({ pos: this.chest(t, 0.3), n: 16, color: 0x8cff8a, color2: 0xfff8b0, speed: 0.6, up: 1.6, grav: 0, life: 0.8, size: 0.13, spread: 0.35 });
        D.fx.ring(t.cur, 0x6aff7a, 0.2, 0.9, 0.45);
        this.pop(t, `+${o.amount}`, { color: '#8dff8a' }); Sfx.play('heal');
      });
    } else if (type === 'taunt') {
      const f = this.actor(o.from); if (!f) return;
      f.sqv += 4; D.fx.ring(f.cur, 0x66aaff, 0.3, 2.2, 0.5); this.pop(f, '도발', { cls: 'word', color: '#9cc8ff' }); Sfx.play('shield');
    } else if (type === 'guard') {
      const a = this.actor(o.unit); if (!a) return;
      a.sqv += 4; D.fx.ring(a.cur, 0xffd46a, 0.2, 1.3, 0.45); D.fx.ring(a.cur, 0xffd46a, 0.2, 0.8, 0.6, 0.5);
      this.pop(a, '반격 자세', { cls: 'word', color: '#ffe08a' }); Sfx.play('shield');
    } else if (type === 'tele') {
      const b = this.actor(battle.boss); if (!b) return;
      b.sqv -= 4; this.face(b, V(o.target.x, o.target.y)); D.fx.ring(b.cur, 0xff4a3a, 0.4, 2.6, 0.6); D.rig.shake(0.12); Sfx.play('alert'); Sfx.play('snort');
    } else if (type === 'slam') this.slam(o, battle);
    else if (type === 'phase') {
      const b = this.actor(battle.boss); if (!b) return;
      b.flash = 1; b.flashCol = [1, 0.25, 0.15]; b.sqv -= 6; D.rig.shake(0.5); D.hitstop(140);
      D.fx.ring(b.cur, 0xff5030, 0.5, 4.5, 0.8); D.fx.ring(b.cur, 0xffa050, 0.3, 3, 0.6, 0.6);
      D.puffs.emit({ pos: this.chest(b, 0.1), n: 26, color: 0x3a2a2a, color2: 0x6a4a3a, speed: 2.4, up: 0.8, flat: true, grav: 0, life: 0.9, size: 0.6, grow: 1.5 });
      this.pop(b, `${o.phase}단계`, { cls: 'word big', color: '#ff9a7a', dur: 1.3 }); Sfx.play('rumble'); Sfx.play('bighit');
    } else if (type === 'summon') {
      for (const u of o.units) {
        const a = this.actor(u); a.spawnT = 0;
        D.puffs.emit({ pos: V(u.x, u.y, 0.4), n: 20, color: 0x2a2830, color2: 0x5a5660, speed: 1.6, up: 0.8, grav: 0, life: 0.8, size: 0.5, grow: 1.2 });
        D.fx.ring(a.cur, 0xb5b9c6, 0.2, 1.4, 0.5);
      }
      D.rig.shake(0.25); Sfx.play('rumble'); Sfx.play('door');
    }
  }
  /** 때리는 쪽이 내딛고(또는 쏘고) 맞는 쪽이 번쩍·움찔한다. 원거리는 날아가 닿을 때 터진다 */
  hit(o) {
    const t = this.actor(o.unit), f = this.actor(o.from), kind = o.kind || 'slash';
    if (!t) return;
    if (o.killed) t.pending = true;
    let delay = 0;
    if (f && MELEE.has(kind)) { this.attack(f, t, kind === 'counter' ? 0.55 : 0.4); delay = 0.08; Sfx.play('swing'); }
    else if (kind === 'cleave' || kind === 'scatter') delay = 0.2;
    else if (kind === 'bolt') { if (f) { f.sqv += 3; this.face(f, t.cur); } delay = 0.05; }
    else if (f) { f.sqv += 2; this.face(f, t.cur); f.jolt.addScaledVector(this.dir(t.cur, f.cur), 0.08); delay = this.shoot(f, t, kind); }
    this.after(delay, () => this.impact(o, t, f, kind));
  }
  impact(o, t, f, kind) {
    const D = this.dio, foe = isFoe(t.u), boss = t.u.role === 'boss';
    const heavy = Math.min(1, o.amount / 12), dir = f ? this.dir(f.cur, t.cur) : new THREE.Vector3(), chest = this.chest(t);
    const hero = f?.u.role === 'hero' || t.u.role === 'hero', big = o.crit || o.amount >= 9;
    t.flash = 1; t.flashCol = kind === 'water' ? [0.3, 0.7, 1] : kind === 'bolt' ? [1, 0.95, 0.4] : foe ? [1, 1, 1] : [1, 0.35, 0.3];
    t.sqv -= 4 + 9 * heavy;
    t.jolt.addScaledVector(dir, (0.1 + 0.32 * heavy) * (boss ? 0.45 : 1));
    const [c1, c2] = SPARK[kind] || SPARK.slash;
    D.sparks.emit({ pos: chest, n: 8 + Math.round(16 * heavy), color: c1, color2: c2, speed: 2.4 + 2 * heavy, up: 1, vx: dir.x * 2, vz: dir.z * 2, life: 0.35, size: 0.1 + 0.06 * heavy, spread: 0.15 });
    if (kind === 'slash' || kind === 'counter') this.arc(chest, dir, kind === 'counter' ? 0xffd46a : 0xffffff, boss ? 1.1 : 0.7);
    if (kind === 'blunt' || kind === 'counter') { D.fx.ring(t.cur, 0xffc080, 0.2, 1.1, 0.3); D.puffs.emit({ pos: V(t.cur.x, t.cur.z, 0.15), n: 8, color: 0x5a5048, color2: 0x8a7a68, speed: 1.4, up: 0.3, flat: true, grav: 0, life: 0.5, size: 0.35, grow: 1 }); }
    if (kind === 'water') { D.puffs.emit({ pos: chest, n: 22, color: 0x4aa8ff, color2: 0xcff0ff, speed: 2.6, up: 2.2, grav: -9, life: 0.6, size: 0.16, spread: 0.3 }); D.fx.ring(t.cur, 0x6ac8ff, 0.3, 1.5, 0.45); }
    if (kind === 'bolt') {
      const top = chest.clone().add(new THREE.Vector3(0.3, 7, -0.4));
      D.fx.bolt(top, chest, 0xffe14a, o.crit ? 0.16 : 0.09, 0.3, 0.35);
      if (o.crit) { D.fx.bolt(top.clone().add(new THREE.Vector3(-0.6, 0, 0.3)), chest, 0xfff6a0, 0.08, 0.35, 0.4); D.fx.burst(chest, 0xffe14a, 1.6, 0.35); }
      D.pool.flash(chest, 0xffe890, o.crit ? 45 : 25, 0.3);
      D.fx.ring(t.cur, 0xffe14a, 0.3, o.crit ? 2.6 : 1.4, 0.4);
    }
    // 숫자: 적이 맞으면 흰색, 우리 편이 맞으면 붉게. 큰 한 방은 크게
    this.pop(t, String(o.amount), { color: o.crit ? '#ffe14a' : kind === 'water' ? '#9fdcff' : foe ? '#fff4dc' : '#ff7a66', cls: big ? 'big' : '', scale: 0.85 + heavy * 0.5 });
    if (o.crit) this.pop(t, '감전!', { cls: 'word', color: '#ffe14a', delay: 0.06, rise: 90 });
    if (kind === 'counter') this.pop(t, '반격!', { cls: 'word', color: '#ffd46a', delay: 0.05, rise: 90 });
    // 멈칫·흔들림: 등불지기가 주고받는 한 방과 큰 기술에만 (동료의 잔타까지 멈추면 실시간이 끊긴다)
    const stop = o.crit ? 150 : kind === 'counter' ? 120 : kind === 'bolt' ? 80 : hero ? (foe ? 50 : 90) : big ? 60 : 0;
    if (stop) D.hitstop(stop);
    D.rig.shake(o.crit ? 0.45 : kind === 'bolt' ? 0.22 : hero ? 0.1 + 0.2 * heavy : big ? 0.12 : 0.03);
    Sfx.play(({ slash: 'slash', blunt: 'blunt', arrow: 'hit', orb: 'pierce', water: 'splash', bolt: o.crit ? 'thunder' : 'zap', counter: 'crit' })[kind] || 'hit');
    if (kind === 'counter' || big) Sfx.play('bighit');
    if (!foe) { Sfx.play('hurt'); if (t.u.role === 'hero' || heavy > 0.6) this.hurtFlash(heavy); }
    if (o.killed) this.after(0.06, () => this.kill(t));
  }
  /** 파수병의 기믹이 터진다: 내려치기는 부채꼴 충격, 흩어져라는 원마다 폭발 */
  slam(o, battle) {
    const D = this.dio, b = this.actor(battle.boss); if (!b) return;
    const aim = V(o.aim.x, o.aim.y);
    if (o.type === 'cleave') this.attack(b, { cur: aim }, 0.9, true); else { b.sqv -= 8; b.hop = 0; }
    this.clearAreas(); this.tele = battle.tele;
    Sfx.play('whoosh');
    this.after(0.2, () => {
      if (o.type === 'cleave') {
        const d = this.dir(b.cur, aim), ang = Math.atan2(-d.z, d.x), half = Math.acos(0.58);
        const fan = new THREE.Mesh(new THREE.CircleGeometry(3.25, 40, ang - half, half * 2).rotateX(-Math.PI / 2), D.fx.basic(0xff7a3a, 0.8));
        fan.position.set(b.cur.x, 0.12, b.cur.z);
        D.fx.add(fan, 0.4, (k) => { fan.material.opacity = 0.8 * (1 - k); fan.scale.setScalar(0.85 + 0.2 * ease(k)); });
        for (let r = 0.8; r <= 3.2; r += 0.6) for (const s of [-0.7, 0, 0.7]) {
          const p = b.cur.clone().add(new THREE.Vector3(Math.cos(ang + s) * r, 0.1, -Math.sin(ang + s) * r));
          D.puffs.emit({ pos: p, n: 3, color: 0x4a4038, color2: 0x7a6a58, speed: 1.2, up: 1.2, grav: -2, life: 0.7, size: 0.4, grow: 1 });
        }
        D.fx.ring(b.cur, 0xff8a4a, 0.5, 3.4, 0.45);
      } else {
        for (const p of o.at) {
          const at = V(p.x, p.y, 0.3);
          D.fx.burst(at, 0xff4a3a, 1.2, 0.35); D.fx.ring(at, 0xff6a4a, 0.3, 1.4, 0.4);
          D.sparks.emit({ pos: at, n: 14, color: 0xff6a3a, color2: 0xffe0a0, speed: 3.2, up: 2.4, life: 0.55, size: 0.14 });
        }
        D.fx.ring(b.cur, 0xff5a3a, 0.6, 3, 0.4);
      }
      D.pool.flash(b.cur.clone().setY(0.6), 0xff8a50, 35, 0.35);
      D.rig.shake(o.hit.length ? 0.55 : 0.32); D.hitstop(o.hit.length ? 110 : 60);
      Sfx.play('boom'); if (o.hit.length) Sfx.play('bighit');
      for (const u of o.dodge) { const a = this.actors.get(u.id); if (a) this.pop(a, '회피', { cls: 'word', color: '#a8e0ff' }); }
    });
  }
  kill(a) {
    if (a.dying) return;
    const D = this.dio, chest = this.chest(a);
    a.dying = true; a.deadT = 0; a.flash = 1; a.flashCol = [1, 1, 1];
    if (a.u.role === 'boss') {
      D.hitstop(260); D.rig.shake(0.9); this.slowT = 1.4; D.timeScale = 0.3;
      D.fx.burst(chest, 0xffb070, 3.2, 0.7); D.fx.ring(a.cur, 0xffd08a, 0.5, 6, 0.9); D.pool.flash(chest, 0xffd8a0, 60, 0.6, 10);
      D.sparks.emit({ pos: chest, n: 70, color: 0xffd46a, color2: 0xffffff, speed: 6, up: 3, life: 1.1, size: 0.18, spread: 0.5 });
      D.puffs.emit({ pos: chest, n: 40, color: 0x3a3030, color2: 0x7a6a5a, speed: 3, up: 1, grav: 0, life: 1.4, size: 0.8, grow: 1.4 });
      Sfx.play('boom'); Sfx.play('thunder'); Sfx.play('die');
    } else if (isFoe(a.u)) {
      D.fx.burst(chest, 0xd8dce8, 0.9, 0.3);
      D.puffs.emit({ pos: chest, n: 18, color: 0x3a3840, color2: 0x8a8898, speed: 2, up: 1, grav: 0, life: 0.7, size: 0.4, grow: 1 });
      D.sparks.emit({ pos: chest, n: 16, color: 0xe8ecf8, color2: 0x9aa0b0, speed: 3, up: 2, life: 0.5, size: 0.12 });
      Sfx.play('die'); Sfx.play('shatter');
    } else {
      this.pop(a, '쓰러짐', { cls: 'word', color: '#c8b8b0', delay: 0.1 }); Sfx.play('die');
    }
  }

  /* ---------------- 작은 도구 ---------------- */
  dir(from, to) { const d = new THREE.Vector3(to.x - from.x, 0, to.z - from.z); return d.lengthSq() ? d.normalize() : d; }
  chest(a, k = 0.55) { return new THREE.Vector3(a.cur.x, a.h * k, a.cur.z); }
  face(a, p) { const dx = p.x - a.cur.x, dz = p.z - a.cur.z; if (dx || dz) a.yawT = Math.atan2(dx, dz); }
  /** 내딛기: 가벼운 쪽은 바로 찌르고, 무거운 쪽(파수병)은 한 번 물러났다 내리찍는다 */
  attack(a, t, amt, heavy = false) {
    const d = this.dir(a.cur, t.cur); this.face(a, t.cur);
    a.lunge = { dx: d.x, dz: d.z, amt, t: 0, dur: heavy ? 0.34 : 0.16, heavy }; a.sqv += heavy ? -3 : 2.5;
    if (a.wh) a.swing = { t: 0 };
  }
  /** 투사체. 닿기까지 걸리는 초를 돌려준다 */
  shoot(f, t, kind) {
    if (!f) return 0;
    const a = this.chest(f, 0.6), b = this.chest(t), dur = Math.min(0.4, a.distanceTo(b) / 16 + 0.06), D = this.dio;
    let obj, arc, trail = null;
    if (kind === 'arrow') {
      obj = new THREE.Mesh(new THREE.BoxGeometry(0.035, 0.035, 0.5), new THREE.MeshBasicMaterial({ color: f.u.role === 'add' ? 0xd8d0ff : 0xfff0c8 }));
      obj.userData.align = true; arc = 0.15; Sfx.play('arrow');
    } else {
      const col = kind === 'water' ? 0x4ab0ff : kind === 'heal' ? 0x7aff8a : 0xc8ff8a;
      obj = new THREE.Mesh(new THREE.SphereGeometry(kind === 'water' ? 0.2 : 0.12, 14, 10), D.fx.basic(col, 0.95));
      trail = (p) => (kind === 'water' ? D.puffs : D.sparks).emit({ pos: p, n: 1, color: col, color2: 0xffffff, speed: 0.2, grav: 0, life: 0.3, size: kind === 'water' ? 0.18 : 0.1 });
      arc = kind === 'water' ? 0.8 : 0.35; Sfx.play(kind === 'water' ? 'throw' : 'cast');
    }
    D.fx.projectile(a, b, obj, dur, arc, trail);
    return dur;
  }
  arc(p, dir, color, r) {
    const m = new THREE.Mesh(new THREE.RingGeometry(r * 0.72, r, 24, 1, -1.2, 2.4).rotateX(-Math.PI / 2), this.dio.fx.basic(color, 0.95));
    m.position.copy(p); const yaw = Math.atan2(-dir.z, dir.x), tilt = (Math.random() - 0.5) * 0.9; m.rotation.set(0, yaw, tilt);
    this.dio.fx.add(m, 0.2, (k) => { m.material.opacity = 0.95 * (1 - k); m.scale.setScalar(0.7 + 0.5 * ease(k)); m.rotation.y = yaw + 0.9 - 1.8 * ease(k); });
  }
  pop(a, text, o = {}) { this.dio.labels.pop(new THREE.Vector3(a.cur.x, a.h + 0.2, a.cur.z), text, o); }
  hurtFlash(heavy) {
    const el = this.hurtEl; el.style.setProperty('--k', String(0.35 + 0.65 * heavy));
    el.classList.remove('on'); void el.offsetWidth; el.classList.add('on');
  }

  /* ---------------- 매 프레임 ---------------- */
  update(dt, real) {
    this.time += dt;
    for (let i = this.later.length - 1; i >= 0; i--) { const l = this.later[i]; l.t -= dt; if (l.t <= 0) { this.later.splice(i, 1); l.fn(); } }
    if (this.slowT > 0) { this.slowT -= real; if (this.slowT <= 0) this.dio.timeScale = 1; }
    const b = this.battle; if (!b) return;
    const boss = this.actors.get('boss');
    // 예고 범위: 테두리는 깜빡이고 안쪽은 터질 때가 다가올수록 차오른다(턴제는 반쯤 찬 채 숨 쉰다)
    if (this.areas.length) {
      const prog = b.tele && b.mode !== 'A' && this.teleTotal ? 1 - Math.max(0, b.tele.remaining) / this.teleTotal : 0.5 + 0.2 * Math.sin(this.time * 4);
      const pulse = 0.75 + 0.25 * Math.sin(this.time * (b.mode === 'A' ? 5 : 8 + prog * 14));
      for (const m of this.areas) if (m.userData.fill) m.scale.setScalar(Math.max(0.02, prog)); else m.material.opacity = m.userData.base * pulse;
    }
    for (const a of this.actors.values()) {
      const u = a.u, r = a.doll.root, alive = u.hp > 0;
      if (!b.units.includes(u)) { r.visible = false; continue; }
      if (!alive && !a.dying && !a.pending) this.kill(a);
      // 자리: 격자에서 한 칸 옮겨도 미끄러지듯 따라가며 발걸음처럼 튄다
      const gap = Math.hypot(u.x - a.cur.x, u.y - a.cur.z);
      if (!a.dying) {
        if (gap > 0.02) {
          const k = 1 - Math.exp(-dt * (b.mode === 'C' ? 18 : 12));
          if (!a.lunge) this.face(a, { x: u.x, z: u.y });
          a.cur.x += (u.x - a.cur.x) * k; a.cur.z += (u.y - a.cur.z) * k;
        } else if (!a.lunge && a !== boss && boss && !isFoe(u)) this.face(a, boss.cur);
        else if (!a.lunge && a === boss && !b.tele) {
          const tgt = b.party.filter((p) => p.hp > 0).sort((p, q) => Math.hypot(p.x - u.x, p.y - u.y) - Math.hypot(q.x - u.x, q.y - u.y))[0];
          if (tgt) this.face(a, { x: tgt.x, z: tgt.y });
        }
      }
      const step = !a.dying && gap > 0.05 ? Math.abs(Math.sin(this.time * 16 + a.phase)) * Math.min(0.12, gap * 0.25) : 0;
      let lx = 0, lz = 0, jump = 0;
      if (a.lunge) {
        const L = a.lunge; L.t = Math.min(1, L.t + dt / L.dur); const k = L.t;
        const s = L.heavy ? (k < 0.5 ? -0.35 * Math.sin(Math.PI * k / 0.5) : Math.sin(Math.PI * (k - 0.5) / 0.5) * 1.1) : Math.sin(Math.PI * k);
        lx = L.dx * s * L.amt; lz = L.dz * s * L.amt; if (k >= 1) a.lunge = null;
      }
      if (a.hop >= 0) { a.hop = Math.min(1, a.hop + dt / 0.22); jump = Math.sin(Math.PI * a.hop) * 0.8; if (a.hop >= 1) { a.hop = -1; a.sqv -= 9; } }
      a.sqv += (-420 * a.sq - 17 * a.sqv) * dt; a.sq = Math.max(-0.45, Math.min(0.45, a.sq + a.sqv * dt));
      a.jolt.multiplyScalar(Math.exp(-dt * 11));
      let dy = a.yawT - a.yaw; while (dy > Math.PI) dy -= Math.PI * 2; while (dy < -Math.PI) dy += Math.PI * 2; a.yaw += dy * Math.min(1, dt * 14);
      const wind = a === boss && b.tele && !a.lunge ? Math.sin(this.time * 46) * 0.05 : 0; // 기믹 예고: 파수병이 떨며 힘을 모은다
      r.position.set(a.cur.x + a.jolt.x + lx + wind, step + jump + a.jolt.y, a.cur.z + a.jolt.z + lz);
      r.rotation.y = a.yaw;
      if (a.spawnT < 1) a.spawnT = Math.min(1, a.spawnT + dt / 0.35);
      const grow = a.spawnT < 1 ? ease(a.spawnT) * (1 + 0.25 * Math.sin(Math.PI * a.spawnT)) : 1;
      a.doll.pivot.scale.set((1 - a.sq * 0.5) * grow, (1 + a.sq) * grow, (1 - a.sq * 0.5) * grow);
      a.doll.pivot.position.y = alive ? Math.abs(Math.sin(this.time * 3.2 + a.phase)) * 0.02 : 0;
      // 번쩍임 + 상태 빛: 젖음(파랑), 반격 자세(금빛)
      a.flash = Math.max(0, a.flash - dt * 6);
      const em = a.doll.mat.emissive; em.setRGB(0, 0, 0);
      if (alive && b.wet.has(u.id)) {
        em.setRGB(0.02, 0.1 + 0.05 * Math.sin(this.time * 5), 0.22);
        if (Math.random() < dt * 5) this.dio.puffs.emit({ pos: this.chest(a, 0.4 + Math.random() * 0.4), n: 1, color: 0x6ac8ff, speed: 0.1, grav: -5, life: 0.5, size: 0.08 });
      }
      if (alive && u.role === 'hero' && b.guard > 0) em.setRGB(0.22 + 0.1 * Math.sin(this.time * 6), 0.16, 0.02);
      if (a.flash > 0) { const f = a.flash * a.flash * 1.9; em.r += f * a.flashCol[0]; em.g += f * a.flashCol[1]; em.b += f * a.flashCol[2]; }
      if (a.wh) this.animWeapon(a, dt);
      a.ring.material.opacity = alive ? 0.9 : 0;
      if (a.dying) this.animDeath(a, dt); else { r.visible = true; a.doll.pivot.rotation.x = 0; }
    }
  }
  animWeapon(a, dt) {
    let rx = 0.2, ry = 0, rz = 0.45, pz = 0.06;
    if (a.swing) {
      const sw = a.swing; sw.t = Math.min(1, sw.t + dt / 0.2); const k = sw.t, e = Math.sin(Math.PI * k);
      if (a.form === 'slash') { ry = 1.4 - 2.8 * ease(k); rx = 0.5 + 0.9 * e; }
      else if (a.form === 'blunt') rx = k < 0.35 ? 0.5 - 1.7 * (k / 0.35) : -1.2 + 3.1 * ease((k - 0.35) / 0.65);
      else { rx = 0.5 + 1.1 * Math.min(1, k * 3); pz = 0.06 + 0.4 * e; }
      rz = 0.45 * (1 - e); if (k >= 1) a.swing = null;
    }
    a.wh.rotation.set(rx, ry, rz); a.wh.position.z = pz;
  }
  /** 적은 부풀었다 흩어지고, 우리 편은 뒤로 넘어져 그 자리에 눕는다 */
  animDeath(a, dt) {
    const p = a.doll.pivot, r = a.doll.root, was = a.deadT; a.deadT += dt;
    if (isFoe(a.u)) {
      const boss = a.u.role === 'boss', k = a.deadT / (boss ? 1.1 : 0.4);
      const s = k < 0.3 ? 1 + k * 0.8 : Math.max(0, 1.24 * (1 - (k - 0.3) / 0.7));
      p.scale.set(s * 1.1, s * (k < 0.3 ? 0.75 : 1.05), s * 1.1); r.rotation.y = a.yaw + a.deadT * (boss ? 5 : 12);
      if (boss && Math.random() < dt * 30) this.dio.sparks.emit({ pos: this.chest(a, Math.random()), n: 3, color: 0xffd46a, color2: 0xffffff, speed: 3, up: 2, life: 0.5, size: 0.12, spread: 0.6 });
      r.visible = k < 1;
    } else {
      p.rotation.x = -1.45 * ease(Math.min(1, a.deadT / 0.45)); p.scale.set(1, 1, 1); r.visible = true;
      if (was < 0.45 && a.deadT >= 0.45) { // 땅에 닿는 순간 먼지와 작은 흔들림
        this.dio.puffs.emit({ pos: V(a.cur.x, a.cur.z, 0.1), n: 10, color: 0x3a3438, color2: 0x6a5e58, speed: 1.2, flat: true, grav: 0, life: 0.6, size: 0.35, grow: 1 });
        this.dio.rig.shake(0.08); Sfx.play('push');
      }
    }
  }
}
