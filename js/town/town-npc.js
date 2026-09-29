import * as THREE from 'three';
import * as K from '../render/diorama.js';
import { DIM, SULK, TALK } from '../data/lines.js';
import { GLOW } from '../data/visitors.js';
import { dominant } from '../core/meta.js';
import { hearthGlow } from '../core/visitors.js';
import { JOBS } from '../data/town.js';
import { _w } from '../render/common.js';
import { npcParts } from '../render/dolls.js';
import { View } from '../render/view.js';
import { Town } from './town.js';

const one = (L) => L[Math.floor(Math.random() * L.length)];
/** 상황에 맞는 한마디: 불이 약하면 불안, 기분이 나쁘면 퉁명, 아니면 가장 두드러진 성격대로 */
export function talkLine(n) {
  if (hearthGlow() <= GLOW.low && Math.random() < 0.6) return one(DIM);
  if (n.mood <= -1 && Math.random() < 0.6) return one(SULK);
  const k = dominant(n); return one(TALK[k[0]][k[1] === '+' ? 'hi' : 'lo']);
}

export class TownNPC {
  constructor(n, spawnAt) {
    this.n = n; const D = View.dio;
    this.d = K.doll(npcParts(n), { scale: 1.2, gloss: 0.7 }); D.scene.add(this.d.root);
    this.d.mesh.userData.pick = { npc: n.id };
    const w = Town.workSpot(n); this.pos = new THREE.Vector3(...(spawnAt || [w[0] + (Math.random() - 0.5), 0, w[1] + (Math.random() - 0.5)]));
    this.target = null; this.state = 'work'; this.t = 0; this.dur = 2 + Math.random() * 5; this.yaw = Math.random() * 6; this.yawT = this.yaw;
    this.phase = Math.random() * 6; this.bubbleT = 3 + Math.random() * 8; this.partner = null; this.face = null; this.hop = 0;
    this.d.root.position.copy(this.pos);
  }
  /** 벽을 돌아 문으로 다닌다(Town.route) */
  goto(x, z, next, dur, face) { this.path = Town.route(this.pos.x, this.pos.z, x, z); const [px, pz] = this.path.shift(); this.target = new THREE.Vector3(px, 0, pz); this.state = 'walk'; this.next = next; this.nextDur = dur; this.face = face || null; }
  update(dt, time) {
    const r = this.d.root, n = this.n, slow = n.mood <= -1 ? 0.75 : 1;
    this.t += dt; this.bubbleT -= dt;
    let bob = 0, tiltX = 0, tiltZ = 0, sy = 1;
    if (this.state === 'walk') {
      const d = this.target.clone().sub(this.pos), L = d.length();
      if (L < 0.05 && this.path && this.path.length) { this.pos.copy(this.target); const [px, pz] = this.path.shift(); this.target.set(px, 0, pz); }
      else if (L < 0.05) { this.pos.copy(this.target); this.state = this.next; this.t = 0; this.dur = this.nextDur; if (this.face) this.yawT = Math.atan2(this.face[0] - this.pos.x, this.face[1] - this.pos.z); }
      else { const st = Math.min(L, dt * 1.7 * slow); this.pos.addScaledVector(d.normalize(), st); this.yawT = Math.atan2(d.x, d.z); bob = Math.abs(Math.sin(time * 11 + this.phase)) * 0.09; }
    } else if (this.state === 'work') {
      const w = JOBS[n.job].work, k = time * 6 + this.phase;
      if (w === 'hammer' || w === 'carve') { tiltX = Math.max(0, Math.sin(k)) * 0.35; if (w === 'hammer' && Math.sin(k) > 0.97 && Math.random() < 0.5) View.dio.sparks.emit({ pos: _w.set(this.pos.x + Math.sin(this.yaw) * 0.45, 0.45, this.pos.z + Math.cos(this.yaw) * 0.45), n: 5, color: 0xffb040, color2: 0xffffff, speed: 2.5, life: 0.35, size: 0.08 }); }
      else if (w === 'farm') tiltX = 0.45 + Math.sin(k * 0.5) * 0.15;
      else if (w === 'read') tiltZ = Math.sin(k * 0.3) * 0.08;
      else if (w === 'stir') this.yawT += dt * 0.8;
      else { bob = Math.sin(k * 0.4) * 0.03; if (Math.random() < dt * 2) View.dio.sparks.emit({ pos: _w.set(this.pos.x, 1.1, this.pos.z), n: 1, color: 0xc07aff, speed: 0.4, up: 0.6, grav: 0, life: 0.8, size: 0.1 }); }
    } else if (this.state === 'chat') { bob = Math.abs(Math.sin(time * 4 + this.phase)) * 0.04; }
    else if (this.state === 'nap') { sy = 0.82; tiltX = 0.25; }
    else if (this.state === 'gather') { bob = Math.abs(Math.sin(time * 6 + this.phase)) * 0.1; }
    if (this.state !== 'walk' && this.t > this.dur) Town.decide(this);
    let dy = this.yawT - this.yaw; while (dy > Math.PI) dy -= Math.PI * 2; while (dy < -Math.PI) dy += Math.PI * 2; this.yaw += dy * Math.min(1, dt * 8);
    r.position.set(this.pos.x, bob, this.pos.z); r.rotation.y = this.yaw;
    this.d.pivot.rotation.x = tiltX; this.d.pivot.rotation.z = tiltZ; this.d.pivot.scale.set(1, sy, 1);
    if (this.bubbleT < 0) { this.bubbleT = 7 + Math.random() * 9; Town.bubble(this); }
  }
}
