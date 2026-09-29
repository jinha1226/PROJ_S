import * as THREE from 'three';
import { G } from '../core/state.js';
import { KCOL, PHYS } from '../data/colors.js';
import { MAGE } from '../data/enemies.js';
import { AURA, COLORS, STONE } from '../data/stones.js';
import { W3 } from './common.js';
import * as K from './diorama.js';
import { ports } from './ports.js';
import { Sfx } from './sfx.js';
import { View } from './view.js';

Object.assign(View, {
  swingFx(d, ev) {
    const D = this.dio, a = ev ? ev.cur.clone() : W3(G.player.x, G.player.y), dx = d.dx, dz = d.dy, len = Math.hypot(dx, dz) || 1;
    const tint = d.counter ? 0x7dffa0 : d.extra ? 0xff8a8a : 0xffffff;
    if (d.form === 'slash') {
      const m = new THREE.Mesh(new THREE.RingGeometry(0.42, 0.72, 22, 1, -1.2, 2.4).rotateX(-Math.PI / 2), D.fx.basic(tint, 0.9));
      m.position.set(a.x + dx / len * 0.25, 0.55, a.z + dz / len * 0.25); m.rotation.y = -Math.atan2(dz, dx);
      D.fx.add(m, 0.2, (k) => { m.scale.setScalar(0.8 + k * 0.5); m.material.opacity = 0.9 * (1 - k); m.rotation.y += 0.05; });
    } else if (d.form === 'pierce') {
      const m = new THREE.Mesh(new THREE.PlaneGeometry(0.09, 1.3).rotateX(-Math.PI / 2).translate(0, 0, 0.65), D.fx.basic(tint, 1));
      m.position.set(a.x, 0.55, a.z); m.rotation.y = Math.atan2(dx, dz);
      D.fx.add(m, 0.16, (k) => { m.scale.set(1 - k * 0.6, 1, 0.4 + k * 0.9); m.material.opacity = 1 - k; });
    } else {
      D.fx.ring(W3(d.tx, d.ty), 0xffd08a, 0.2, 1.3, 0.3);
      D.puffs.emit({ pos: W3(d.tx, d.ty, 0.15), n: 8, color: 0xa89c8c, speed: 2, grav: 0, life: 0.5, size: 0.3, flat: true });
      D.rig.shake(0.12);
    }
    Sfx.play(d.form);
  },
  stoneFx(d) {
    const D = this.dio, pe = this.evs.get(0); if (!pe) return;
    const def = STONE[d.id], col = COLORS[def.color], st = d.stage, base = W3(pe.cur.x, pe.cur.z);
    D.labels.pop(W3(pe.cur.x, pe.cur.z, pe.h + 0.25), '', { html: `<span class="gpop" style="--c:${col.css}">${def.icon}</span>`, scale: 1 + 0.25 * (st - 1), rise: 60 + st * 12, dur: 1.2, vx: (d.slot - 2.5) * 16, cls: 'gem' });
    D.fx.ring(base, col.hex, 0.3, 0.9 + 0.45 * st, 0.4 + 0.05 * st);
    if (st >= 2) D.fx.burst(W3(pe.cur.x, pe.cur.z, 0.6), col.hex, 0.3 + 0.18 * st, 0.3);
    D.sparks.emit({ pos: W3(pe.cur.x, pe.cur.z, 0.7), n: 8 + 8 * st, color: col.hex, color2: 0xffffff, speed: 2 + st * 0.9, up: 1, grav: -1, life: 0.55, size: 0.12 + 0.025 * st });
    D.pool.flash(base, col.hex, 18 + 14 * st, 0.35, 4 + st);
    D.rig.shake(0.05 * st);
    if (st >= 2) D.hitstop(25 + 12 * st);
    ports.UI.flashSlot(d.slot);
    Sfx.chime(st);
  },
  /** 지속 효과 오라: 캐릭터 발밑 고리 + 색 */
  setAuras(A) {
    const pe = this.evs.get(0); if (!pe) return;
    if (pe.auraG) { pe.d.root.remove(pe.auraG); pe.auraG = null; }
    const keys = Object.keys(A || {}); if (!keys.length) return;
    const g = new THREE.Group();
    keys.forEach((k, j) => {
      const c = new THREE.Color(AURA[k].hex).multiplyScalar(1.6), m = new THREE.Mesh(new THREE.TorusGeometry(0.46 + j * 0.09, 0.025, 6, 40), new THREE.MeshBasicMaterial({ color: c, transparent: true, opacity: 0.8, blending: THREE.AdditiveBlending, depthWrite: false }));
      m.rotation.x = Math.PI / 2; m.position.y = 0.08 + j * 0.12; m.userData.k = k; g.add(m);
    });
    pe.d.root.add(g); pe.auraG = g; this.dio.pool.flash(W3(pe.cur.x, pe.cur.z), AURA[keys[0]].hex, 30, 0.4, 4);
  },
  slowmo(stage) {
    this._slow = true; this.dio.timeScale = 0.3; document.body.classList.add('slowmo');
    ports.UI.banner(`연쇄 ${stage}단계!`, 'chain'); Sfx.play('slow');
    clearTimeout(this._sm); this._sm = setTimeout(() => this.endSlow(), 850);
  },
  endSlow() { this._slow = false; this.dio.timeScale = 1; document.body.classList.remove('slowmo'); },
  hitFx(ev, d) {
    if (!ev) return;
    const D = this.dio, player = ev.id === 0, B = this.boost;
    ev.flash = 1; ev.sqv -= d.big ? 9 : 6.5;
    if (d.dx || d.dy) ev.jolt.set(d.dx * 0.3, 0.06, d.dy * 0.3);
    const p = W3(ev.cur.x, ev.cur.z, ev.h * 0.75);
    D.labels.pop(p, String(d.amt), { color: player ? '#ff5a6a' : KCOL[d.kind] || '#fff', cls: d.big ? 'big' : '' });
    if (d.label) D.labels.pop(W3(ev.cur.x, ev.cur.z, ev.h * 0.75 + 0.5), d.label, { color: KCOL[d.kind] || '#ffe38a', cls: 'word', vx: 0, rise: 42, dur: 1.15 });
    const c = W3(ev.cur.x, ev.cur.z, ev.h * 0.5);
    switch (d.kind) {
      case 'fire': case 'burn': D.sparks.emit({ pos: c, n: d.kind === 'burn' ? 5 : 14, color: 0xff7a1a, color2: 0xffe36a, speed: 2.5, up: 2, grav: 2, life: 0.5, size: 0.2 }); break;
      case 'shock': D.sparks.emit({ pos: c, n: 18, color: 0xffe14a, color2: 0xffffff, speed: 5, life: 0.3, size: 0.12, grav: -2 }); break;
      case 'frost': D.sparks.emit({ pos: c, n: 14, color: 0x8fdcff, color2: 0xffffff, speed: 3, life: 0.5, size: 0.14, grav: -8 }); break;
      case 'poison': D.puffs.emit({ pos: c, n: 5, color: 0x79e05a, color2: 0x3a8a2a, speed: 0.6, up: 0.8, grav: 0, life: 0.7, size: 0.3 }); break;
      case 'steam': D.puffs.emit({ pos: c, n: 8, color: 0xffffff, color2: 0xcfe0ff, speed: 1.2, up: 1.5, grav: 0, life: 0.8, size: 0.45, grow: 1 }); break;
      case 'blast': D.sparks.emit({ pos: c, n: 20, color: 0x79e05a, color2: 0xffe36a, speed: 5, life: 0.5, size: 0.2 }); break;
      case 'bleed': D.sparks.emit({ pos: c, n: 6, color: 0xff1a2a, color2: 0x9a0010, speed: 1.5, grav: -8, life: 0.4, size: 0.1 }); break;
      default: D.sparks.emit({ pos: c, n: Math.round((10 + d.amt * 2) * B), color: d.crit ? 0xffe14a : 0xffffff, color2: 0xffd27a, speed: 4.5 * B, life: 0.3, size: 0.13, grav: -6, vx: d.dx * 2.5, vz: d.dy * 2.5 });
    }
    if (d.crit) { D.fx.ring(c, 0xffe14a, 0.1, 1.2, 0.3, c.y); D.pool.flash(c, 0xfff0a0, 40, 0.25, 4); }
    const phys = PHYS[d.kind] || d.kind === 'blast';
    if (phys) D.hitstop(d.big ? 100 : 55);
    D.rig.shake((player ? 0.2 + d.amt * 0.03 : 0.05 + d.amt * 0.02) * B);
    if (player) ports.UI.hurt();
    Sfx.play(player ? 'hurt' : { fire: 'fire', burn: 'tick', shock: 'zap', frost: 'freeze', poison: 'tick', steam: 'hiss', blast: 'boom', bleed: 'tick' }[d.kind] || (d.crit ? 'crit' : 'hit'));
  },
  dieFx(ev, d) {
    if (!ev) return;
    const D = this.dio, p = W3(ev.cur.x, ev.cur.z, ev.h * 0.5);
    ev.dead = true; ev.deadT = 0;
    D.sparks.emit({ pos: p, n: 26, color: ev.col, color2: 0xffffff, speed: 4.5, up: 2, life: 0.6, size: 0.16, grav: -9 });
    D.puffs.emit({ pos: p, n: 10, color: 0xdad4e8, color2: 0x9a94a8, speed: 1.8, life: 0.7, size: 0.4, grav: 0.5, grow: 1 });
    if (d.shatter) D.sparks.emit({ pos: p, n: 30, color: 0x8fdcff, color2: 0xffffff, speed: 5.5, life: 0.8, size: 0.17, grav: -10 });
    // 장난감 조각이 튄다
    const geo = new THREE.BoxGeometry(0.11, 0.11, 0.11); geo.userData.keep = false;
    const mat = K.toon({ color: d.shatter ? 0xbfeaff : ev.col, gloss: 0.9 });
    const bits = new THREE.Group();
    for (let k = 0; k < 7; k++) { const m = new THREE.Mesh(geo, mat); m.castShadow = true; m.userData.v = new THREE.Vector3((Math.random() - 0.5) * 4, 2.5 + Math.random() * 3, (Math.random() - 0.5) * 4); m.position.copy(p); m.scale.setScalar(0.6 + Math.random() * 0.8); bits.add(m); }
    D.fx.add(bits, 0.9, (k, dt) => { for (const m of bits.children) { const v = m.userData.v; v.y -= 14 * dt; m.position.addScaledVector(v, dt); if (m.position.y < 0.06) { m.position.y = 0.06; v.y *= -0.35; v.x *= 0.6; v.z *= 0.6; } m.rotation.x += dt * 9; m.rotation.z += dt * 7; if (k > 0.7) m.scale.multiplyScalar(0.9); } });
    D.fx.ring(p, 0xffffff, 0.2, 1.1, 0.3);
    D.hitstop(75); D.rig.shake(0.18); Sfx.play(d.shatter ? 'shatter' : 'die');
    if (ev.id === 0) { ev.dead = false; ev.d.pivot.rotation.z = Math.PI / 2; ev.d.pivot.position.y = 0.2; }
  },
  fx(type, d) {
    const D = this.dio, ev = d && d.id != null ? this.evs.get(d.id) : null;
    const P = (x, y, h = 0.4) => W3(x, y, h);
    switch (type) {
      case 'arc': { const a = P(d.a[0], d.a[1], 0.3), b = P(d.b[0], d.b[1], 0.3); D.fx.bolt(a, b, 0xffe14a, 0.06, 0.24, 0.18); D.sparks.emit({ pos: b, n: 6, color: 0xffe14a, color2: 0xffffff, speed: 3, life: 0.25, size: 0.1 }); D.pool.flash(b, 0xffe680, 14, 0.2, 4); Sfx.play('zap'); break; }
      case 'bolt': { const a = P(d.from[0], d.from[1], 0.8), b = P(d.to[0], d.to[1], 0.45); D.fx.bolt(a, b, 0xffe14a, 0.11, 0.3, 0.25); D.fx.bolt(a, b, 0xfff3a0, 0.05, 0.22, 0.35); D.pool.flash(b, 0xffe680, 40, 0.3, 6); D.sparks.emit({ pos: b, n: 20, color: 0xffe14a, color2: 0xffffff, speed: 5, life: 0.3, size: 0.12 }); D.rig.shake(0.15); D.lights.boost = 1.6; Sfx.play('zap'); break; }
      case 'zap': D.sparks.emit({ pos: P(d.x, d.y, 0.05), n: 6, color: 0xffe14a, color2: 0xffffff, speed: 2.5, life: 0.25, size: 0.1, flat: true }); break;
      case 'skybolt': for (const [x, y] of d.tiles) { D.fx.bolt(P(x + (Math.random() - 0.5) * 0.6, y + (Math.random() - 0.5) * 0.6, 7), P(x, y, 0.05), 0xffe14a, 0.1, 0.32, 0.4); D.fx.ring(P(x, y), 0xffe14a, 0.1, 0.8, 0.3); D.sparks.emit({ pos: P(x, y, 0.1), n: 10, color: 0xffe14a, color2: 0xffffff, speed: 4, life: 0.3, size: 0.12 }); } D.pool.flash(P(d.tiles[0][0], d.tiles[0][1]), 0xfff0a0, 70, 0.35, 8); D.rig.shake(0.35); D.hitstop(60); Sfx.play('thunder'); break;
      case 'meteor': for (const [x, y] of d.tiles) { D.fx.burst(P(x, y, 0.3), 0xff6a1a, 0.9, 0.35); D.sparks.emit({ pos: P(x, y, 0.3), n: 12, color: 0xff7a1a, color2: 0xffe36a, speed: 3.5, up: 2, life: 0.5, size: 0.18 }); } D.pool.flash(P(d.tiles[0][0], d.tiles[0][1]), 0xff8a3a, 60, 0.45, 7); D.rig.shake(0.35); Sfx.play('boom'); break;
      case 'frostfall': for (const [x, y] of d.tiles) D.sparks.emit({ pos: P(x, y, 2.5), n: 10, color: 0x8fdcff, color2: 0xffffff, speed: 1, vz: 0, up: -6, grav: -10, life: 0.5, size: 0.15, spread: 0.4 }); Sfx.play('freeze'); break;
      case 'explosion': { const small = d.small, col = d.elem === 'poison' ? 0x79e05a : 0xff6a1a, col2 = d.elem === 'poison' ? 0xd8ff6a : 0xffe36a, p = P(d.x, d.y, 0.4);
        D.fx.burst(p, col, (small ? 0.8 : 1.35) * this.boost, small ? 0.3 : 0.4); D.fx.ring(p, col2, 0.3, (small ? 1.2 : 1.9) * this.boost, 0.4);
        D.sparks.emit({ pos: p, n: small ? 14 : 34, color: col, color2: col2, speed: 6, up: 2, life: 0.55, size: 0.2 });
        D.puffs.emit({ pos: p, n: small ? 3 : 8, color: 0x3a3440, color2: 0x6a6070, speed: 1.5, up: 1.5, grav: 0, life: 0.9, size: 0.5, grow: 1.2 });
        D.pool.flash(p, col, small ? 35 : 80, 0.45, 7); D.rig.shake(small ? 0.25 : 0.5); D.hitstop(small ? 30 : 85); D.lights.boost = 1.5; Sfx.play('boom'); break; }
      case 'steam': { const n = d.big ? 22 : d.small ? 6 : 12; D.puffs.emit({ pos: P(d.x, d.y, 0.3), n, color: 0xffffff, color2: 0xd6e6ff, speed: d.big ? 2 : 1, up: 1.4, grav: 0.2, life: 1, size: d.big ? 0.6 : 0.45, grow: 1.2, spread: 0.4 }); if (d.big) { D.fx.ring(P(d.x, d.y), 0xffffff, 0.3, 1.6, 0.45); D.hitstop(70); D.rig.shake(0.3); } Sfx.play('hiss'); break; }
      case 'freeze': D.sparks.emit({ pos: P(d.x, d.y, 0.2), n: d.center ? 16 : 7, color: 0x8fdcff, color2: 0xffffff, speed: 2.5, up: 1, life: 0.55, size: 0.13 }); if (d.center) { D.fx.ring(P(d.x, d.y), 0x8fdcff, 0.2, 1.5, 0.4); D.pool.flash(P(d.x, d.y), 0x9fe8ff, 35, 0.4, 5); Sfx.play('freeze'); } break;
      case 'ignite': D.sparks.emit({ pos: P(d.x, d.y, 0.2), n: d.small ? 6 : 14, color: 0xff7a1a, color2: 0xffe36a, speed: 1.8, up: 2.2, grav: 1, life: 0.55, size: 0.18 }); if (!d.small) { D.pool.flash(P(d.x, d.y), 0xff8a3a, 30, 0.35, 5); Sfx.play('fire'); } break;
      case 'splash': D.sparks.emit({ pos: P(d.x, d.y, 0.05), n: d.small ? 5 : 12, color: d.color ?? 0x4d97ff, color2: d.color ? 0x6a6070 : 0xbfe4ff, speed: 1.6, up: 2.6, grav: -9, life: 0.5, size: 0.1 }); if (!d.small) D.fx.ring(P(d.x, d.y), d.color ?? 0x4d97ff, 0.1, 0.8, 0.3); Sfx.play(d.small ? 'step' : 'splash'); break;
      case 'splat': D.puffs.emit({ pos: P(d.x, d.y, 0.4), n: 6, color: 0x79e05a, color2: 0x3a8a2a, speed: 1.4, grav: -2, life: 0.5, size: 0.22 }); break;
      case 'proj': this.projectile(d); break;
      case 'alert': if (ev) { ev.sqv += 5; D.labels.pop(W3(ev.cur.x, ev.cur.z, ev.h + 0.3), '!', { color: '#ffe14a', cls: 'big', vx: 0, rise: 20, dur: 0.8 }); Sfx.play('alert'); } break;
      case 'cast': if (ev) { ev.sqv += 3; D.pool.flash(W3(ev.cur.x, ev.cur.z), MAGE[d.elem].color, 25, 0.5, 4); Sfx.play('cast'); } break;
      case 'release': if (ev) { ev.sqv -= 5; ev.flash = 0.6; } break;
      case 'windup': if (ev) { ev.jolt.set(-(G.ents.find((e) => e.id === d.id)?.face[0] ?? 0) * 0.15, 0, 0); D.puffs.emit({ pos: W3(ev.cur.x, ev.cur.z, 0.1), n: 8, color: 0x9a8e80, speed: 1.4, grav: 0, life: 0.6, size: 0.3, flat: true }); D.rig.shake(0.1); Sfx.play('snort'); } break;
      case 'aim': Sfx.play('draw'); break;
      case 'dash': Sfx.play('dash'); break;
      case 'shove': D.fx.ring(P(d.x, d.y), 0xf2e6c8, 0.2, 1.1, 0.25); D.sparks.emit({ pos: P(d.x, d.y, 0.5), n: 12, color: 0xffffff, color2: 0xf2e6c8, speed: 4, vx: d.dx * 4, vz: d.dy * 4, life: 0.3, size: 0.12 }); Sfx.play('push'); break;
      case 'pcast': { const pe = this.evs.get(0); if (pe) { const c = d.color ?? 0xffffff; D.sparks.emit({ pos: W3(pe.cur.x, pe.cur.z, 0.7), n: 10, color: c, color2: 0xffffff, speed: 1.5, grav: 0, life: 0.35, size: 0.12 }); pe.sqv += 3; } break; }
      case 'stoneOffer': ports.UI.stoneOffer(d); break;
      case 'cdReduce': ports.UI.cdFlash(d.slots, d.color); { const pe = this.evs.get(0); if (pe) D.sparks.emit({ pos: W3(pe.cur.x, pe.cur.z, 0.8), n: 6 * d.slots.length, color: COLORS[d.color].hex, color2: 0xffffff, speed: 1.2, up: 1.2, grav: 0, life: 0.5, size: 0.09 }); } Sfx.chime(1); break;
      case 'aura': this.setAuras(d); ports.UI.renderAuras(); break;
      case 'stonesReady': ports.UI.toast('전투가 끝났다 — 영혼석 스킬이 모두 준비됐다'); break;
      case 'venomCloud': for (let k = 0; k < 8; k++) { const a = k * 0.785; D.puffs.emit({ pos: P(d.x + Math.cos(a), d.y + Math.sin(a), 0.4), n: 3, color: 0x79e05a, color2: 0x3a8a2a, speed: 0.4, up: 0.4, grav: 0, life: 1.4, size: 0.45, grow: 1 }); } Sfx.play('hiss'); break;
      case 'pickup': D.sparks.emit({ pos: P(d.x, d.y, 0.4), n: 16, color: 0xffe38a, color2: 0xffffff, speed: 1.5, up: 1.5, grav: 0, life: 0.6, size: 0.12 }); Sfx.play('pick'); break;
      case 'identify': ports.UI.banner('✦ ' + d.text, 'info'); break;
      case 'drink': case 'read': { const pe = this.evs.get(0); if (pe) { D.sparks.emit({ pos: W3(pe.cur.x, pe.cur.z, 0.6), n: 20, color: d.color, color2: 0xffffff, speed: 1.2, up: 1.6, grav: 0, life: 0.8, size: 0.13, spread: 0.4 }); pe.sqv += 4; } Sfx.play(type === 'drink' ? 'drink' : 'read'); break; }
      case 'poof': D.puffs.emit({ pos: P(d.x, d.y, 0.5), n: 16, color: 0xc8b8ff, color2: 0xffffff, speed: 2, grav: 0, life: 0.6, size: 0.4, grow: 1 }); D.sparks.emit({ pos: P(d.x, d.y, 0.5), n: 16, color: 0xb45aff, color2: 0xffffff, speed: 3, grav: 0, life: 0.5, size: 0.12 }); Sfx.play('tele'); break;
      case 'scare': if (ev) D.labels.pop(W3(ev.cur.x, ev.cur.z, ev.h + 0.2), '겁먹음!', { color: '#d6a0ff', cls: 'word', vx: 0, rise: 30 }); break;
      case 'ring': D.fx.ring(P(d.x, d.y), 0xff7a1a, 0.3, 2.2, 0.45); D.pool.flash(P(d.x, d.y), 0xff8a3a, 60, 0.5, 7); Sfx.play('fire'); break;
      case 'shatter': D.sparks.emit({ pos: P(d.x, d.y, 0.3), n: 14, color: 0xffffff, color2: d.color, speed: 3, up: 1.5, life: 0.45, size: 0.1, grav: -9 }); Sfx.play('glass'); break;
      case 'smokeburst': D.puffs.emit({ pos: P(d.x, d.y, 0.5), n: 26, color: 0x8a8a94, color2: 0x55555e, speed: 2.4, grav: 0, life: 1.1, size: 0.6, grow: 1, spread: 0.6 }); Sfx.play('hiss'); break;
      default: break;
    }
  },
  projectile(d) {
    const D = this.dio, a = W3(d.from[0], d.from[1], 0.75), b = W3(d.to[0], d.to[1], 0.45), dur = (d.dur ?? 250) / 1000;
    let obj, arc = 0.35, trail = null;
    if (d.kind === 'arrow') {
      obj = new THREE.Group();
      const shaft = new THREE.Mesh(new THREE.CylinderGeometry(0.018, 0.018, 0.5, 5).rotateX(Math.PI / 2), new THREE.MeshBasicMaterial({ color: 0xc89a5a }));
      const tip = new THREE.Mesh(new THREE.ConeGeometry(0.04, 0.1, 5).rotateX(Math.PI / 2).translate(0, 0, 0.28), new THREE.MeshBasicMaterial({ color: 0xffffff }));
      obj.add(shaft, tip); obj.userData.align = true; arc = 0.15;
      trail = (p) => D.sparks.emit({ pos: p, n: 1, color: 0xff8a8a, speed: 0, grav: 0, life: 0.18, size: 0.06 });
    } else if (d.kind === 'quarrel') { // 석궁 쇠살: 굵고 짧게, 거의 곧게 날아간다
      obj = new THREE.Group();
      const shaft = new THREE.Mesh(new THREE.CylinderGeometry(0.026, 0.026, 0.36, 6).rotateX(Math.PI / 2), new THREE.MeshBasicMaterial({ color: 0x7a5a3a }));
      const tip = new THREE.Mesh(new THREE.ConeGeometry(0.05, 0.12, 4).rotateX(Math.PI / 2).translate(0, 0, 0.23), new THREE.MeshBasicMaterial({ color: 0xdfe6f0 }));
      const fin = new THREE.Mesh(new THREE.BoxGeometry(0.12, 0.012, 0.08).translate(0, 0, -0.15), new THREE.MeshBasicMaterial({ color: COLORS.purple.hex }));
      obj.add(shaft, tip, fin); obj.userData.align = true; arc = 0.04;
      trail = (p) => D.sparks.emit({ pos: p, n: 1, color: 0xd6a0ff, speed: 0, grav: 0, life: 0.15, size: 0.06 });
    } else if (d.kind === 'pebble') { // 투석구 돌: 작은 돌이 돌며 포물선으로
      obj = new THREE.Mesh(new THREE.IcosahedronGeometry(0.075, 0), K.toon({ color: 0x9a9aa8, gloss: 0.6 })); obj.userData.spin = true; arc = 0.5;
      trail = (p) => { if (Math.random() < 0.35) D.puffs.emit({ pos: p, n: 1, color: 0xb8b0a0, speed: 0, grav: 0, life: 0.25, size: 0.08 }); };
    } else if (d.kind === 'boomerang') { // 부메랑: 눕힌 V자 날이 빙글빙글 (갈 때·올 때 사건이 따로 온다)
      obj = new THREE.Group(); const m = K.toon({ color: 0xc89a5a, gloss: 1 }), mt = K.toon({ color: COLORS.red.hex, gloss: 1 });
      for (const sx of [-1, 1]) {
        const arm = new THREE.Mesh(new THREE.BoxGeometry(0.07, 0.03, 0.3), m); arm.position.set(sx * 0.085, 0, 0.044); arm.rotation.y = sx * 0.6;
        const t = new THREE.Mesh(new THREE.SphereGeometry(0.04, 8, 6), mt); t.position.set(sx * 0.17, 0, 0.16); obj.add(arm, t);
      }
      arc = 0.12;
      trail = (p, dt) => { obj.rotation.y += dt * 22; D.sparks.emit({ pos: p, n: 1, color: COLORS.red.hex, color2: 0xffffff, speed: 0, grav: 0, life: 0.2, size: 0.07 }); };
    } else if (d.kind === 'flask') {
      obj = new THREE.Mesh(new THREE.SphereGeometry(0.11, 10, 8), K.toon({ color: d.color, gloss: 1 })); obj.userData.spin = true; arc = 1.3;
    } else {
      const col = d.kind === 'fire' ? [2.4, 0.8, 0.15] : d.kind === 'frost' ? [0.7, 1.8, 2.4] : d.kind === 'bone' ? [2.2, 2.1, 1.8] : [0.6, 2.2, 0.4];
      obj = new THREE.Mesh(new THREE.SphereGeometry(d.kind === 'dart' ? 0.06 : 0.13, 12, 8), new THREE.MeshBasicMaterial({ color: new THREE.Color(...col) }));
      const c1 = d.kind === 'fire' ? 0xff7a1a : d.kind === 'frost' ? 0x8fdcff : d.kind === 'bone' ? 0xfff2d0 : 0x79e05a;
      trail = (p) => D.sparks.emit({ pos: p, n: 2, color: c1, color2: 0xffffff, speed: 0.3, grav: 0, life: 0.3, size: 0.12 });
      arc = d.kind === 'dart' ? 0.15 : 0.4;
    }
    D.fx.projectile(a, b, obj, dur, arc, trail);
    Sfx.play(d.kind === 'arrow' || d.kind === 'quarrel' ? 'arrow' : d.kind === 'flask' || d.kind === 'pebble' ? 'throw' : 'whoosh');
  },
});
