import * as THREE from 'three';
import { _c } from './materials.js';

/* ---------------- 파티클 (고정 풀, 한 번의 드로우) ---------------- */
export class Particles {
  constructor(scene, max, blending) {
    this.max = max; this.n = 0;
    const F = (k) => new Float32Array(max * k);
    this.pos = F(3); this.vel = F(3); this.col = F(3); this.life = F(1); this.maxLife = F(1); this.size = F(1); this.grav = F(1); this.drag = F(1); this.grow = F(1);
    const g = new THREE.BufferGeometry();
    this.aPos = new THREE.BufferAttribute(F(3), 3).setUsage(THREE.DynamicDrawUsage);
    this.aCol = new THREE.BufferAttribute(F(3), 3).setUsage(THREE.DynamicDrawUsage);
    this.aSize = new THREE.BufferAttribute(F(1), 1).setUsage(THREE.DynamicDrawUsage);
    this.aAlpha = new THREE.BufferAttribute(F(1), 1).setUsage(THREE.DynamicDrawUsage);
    g.setAttribute('position', this.aPos); g.setAttribute('aCol', this.aCol); g.setAttribute('aSize', this.aSize); g.setAttribute('aAlpha', this.aAlpha);
    g.setDrawRange(0, 0);
    const additive = blending === THREE.AdditiveBlending;
    this.mat = new THREE.ShaderMaterial({
      uniforms: { uScale: { value: 600 } },
      vertexShader: `attribute vec3 aCol; attribute float aSize; attribute float aAlpha; uniform float uScale;
        varying vec3 vC; varying float vA;
        void main(){ vC = aCol; vA = aAlpha; vec4 mv = modelViewMatrix * vec4(position, 1.0); gl_Position = projectionMatrix * mv; gl_PointSize = aSize * uScale / -mv.z; }`,
      fragmentShader: `varying vec3 vC; varying float vA;
        void main(){ vec2 d = gl_PointCoord - 0.5; float r = length(d); if (r > 0.5) discard;
          float a = ${additive ? 'smoothstep(0.5, 0.0, r)' : 'smoothstep(0.5, 0.3, r)'} * vA;
          gl_FragColor = vec4(vC${additive ? ' * (1.0 + 1.5 * smoothstep(0.25, 0.0, r))' : ' * (0.85 + 0.3 * (0.5 - d.y))'}, a); }`,
      transparent: true, depthWrite: false, blending,
    });
    this.points = new THREE.Points(g, this.mat); this.points.frustumCulled = false; this.points.renderOrder = additive ? 20 : 15;
    scene.add(this.points);
  }
  emit(o) {
    const n = o.n ?? 10, c1 = new THREE.Color(o.color ?? 0xffffff), c2 = new THREE.Color(o.color2 ?? o.color ?? 0xffffff);
    const P = o.pos, sp = o.spread ?? 0.12, speed = o.speed ?? 2, up = o.up ?? 0;
    for (let k = 0; k < n; k++) {
      if (this.n >= this.max) return;
      const i = this.n++;
      let dx = Math.random() * 2 - 1, dy = Math.random() * 2 - 1, dz = Math.random() * 2 - 1;
      const l = Math.hypot(dx, dy, dz) || 1; dx /= l; dy /= l; dz /= l;
      if (o.flat) dy *= 0.25;
      if (o.hemi) dy = Math.abs(dy);
      const s = speed * (0.35 + Math.random() * 0.85);
      this.pos[i * 3] = P.x + dx * sp * Math.random(); this.pos[i * 3 + 1] = P.y + dy * sp * Math.random(); this.pos[i * 3 + 2] = P.z + dz * sp * Math.random();
      this.vel[i * 3] = dx * s + (o.vx ?? 0); this.vel[i * 3 + 1] = dy * s + up; this.vel[i * 3 + 2] = dz * s + (o.vz ?? 0);
      _c.copy(c1).lerp(c2, Math.random());
      this.col[i * 3] = _c.r; this.col[i * 3 + 1] = _c.g; this.col[i * 3 + 2] = _c.b;
      this.maxLife[i] = this.life[i] = (o.life ?? 0.6) * (0.6 + Math.random() * 0.7);
      this.size[i] = (o.size ?? 0.15) * (0.6 + Math.random() * 0.8);
      this.grav[i] = o.grav ?? -6; this.drag[i] = o.drag ?? 2.2; this.grow[i] = o.grow ?? 0;
    }
  }
  update(dt) {
    let w = 0;
    const A = this.aPos.array, C = this.aCol.array, S = this.aSize.array, AL = this.aAlpha.array;
    for (let i = 0; i < this.n; i++) {
      const L = this.life[i] - dt; if (L <= 0) continue;
      const dr = Math.exp(-this.drag[i] * dt);
      let vx = this.vel[i * 3] * dr, vy = (this.vel[i * 3 + 1] + this.grav[i] * dt) * dr, vz = this.vel[i * 3 + 2] * dr;
      let px = this.pos[i * 3] + vx * dt, py = this.pos[i * 3 + 1] + vy * dt, pz = this.pos[i * 3 + 2] + vz * dt;
      if (py < 0.02 && vy < 0) { py = 0.02; vy *= -0.3; vx *= 0.6; vz *= 0.6; }
      const sz = this.size[i] * (1 + this.grow[i] * dt);
      if (w !== i) {
        this.maxLife[w] = this.maxLife[i]; this.grav[w] = this.grav[i]; this.drag[w] = this.drag[i]; this.grow[w] = this.grow[i];
        this.col[w * 3] = this.col[i * 3]; this.col[w * 3 + 1] = this.col[i * 3 + 1]; this.col[w * 3 + 2] = this.col[i * 3 + 2];
      }
      this.life[w] = L; this.size[w] = sz;
      this.pos[w * 3] = px; this.pos[w * 3 + 1] = py; this.pos[w * 3 + 2] = pz;
      this.vel[w * 3] = vx; this.vel[w * 3 + 1] = vy; this.vel[w * 3 + 2] = vz;
      const k = L / this.maxLife[w];
      A[w * 3] = px; A[w * 3 + 1] = py; A[w * 3 + 2] = pz;
      C[w * 3] = this.col[w * 3]; C[w * 3 + 1] = this.col[w * 3 + 1]; C[w * 3 + 2] = this.col[w * 3 + 2];
      S[w] = sz * (0.4 + 0.6 * Math.min(1, k * 2.5)); AL[w] = Math.min(1, k * 1.8) * Math.min(1, (1 - k) * 12 + 0.2);
      w++;
    }
    this.n = w;
    this.points.geometry.setDrawRange(0, w);
    this.aPos.needsUpdate = this.aCol.needsUpdate = this.aSize.needsUpdate = this.aAlpha.needsUpdate = true;
  }
}

/* ---------------- 일시 이펙트: 번개 줄기, 충격파 고리, 폭발 구, 투사체 ---------------- */
export class Transients {
  constructor(scene) { this.scene = scene; this.list = []; this.ringGeo = new THREE.RingGeometry(0.82, 1, 40).rotateX(-Math.PI / 2); this.ballGeo = new THREE.SphereGeometry(1, 20, 14); }
  add(obj, life, update, dispose = true) { this.scene.add(obj); this.list.push({ obj, life, max: life, update, dispose }); return obj; }
  update(dt) {
    for (let i = this.list.length - 1; i >= 0; i--) {
      const t = this.list[i]; t.life -= dt;
      const k = 1 - Math.max(0, t.life) / t.max;
      t.update?.(k, dt, t);
      if (t.life <= 0) {
        this.scene.remove(t.obj);
        if (t.dispose) t.obj.traverse((o) => { if (o.geometry && o.geometry !== this.ringGeo && o.geometry !== this.ballGeo && !o.geometry.userData.keep) o.geometry.dispose(); if (o.material && !o.material.userData.keep) o.material.dispose(); });
        this.list.splice(i, 1);
      }
    }
  }
  basic(color, opacity = 1) { return new THREE.MeshBasicMaterial({ color, transparent: true, opacity, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide }); }
  bolt(a, b, color = 0xffe14a, width = 0.09, life = 0.26, jag = 0.22) {
    const len = a.distanceTo(b), n = Math.max(3, Math.ceil(len * 3.2));
    const pts = [];
    for (let i = 0; i <= n; i++) {
      const p = a.clone().lerp(b, i / n);
      if (i > 0 && i < n) p.add(new THREE.Vector3((Math.random() - 0.5) * jag * 2, (Math.random() - 0.5) * jag * 1.4, (Math.random() - 0.5) * jag * 2));
      pts.push(p);
    }
    const g = new THREE.Group();
    const dir = b.clone().sub(a).normalize();
    const side1 = new THREE.Vector3().crossVectors(dir, new THREE.Vector3(0, 1, 0)); if (side1.lengthSq() < 1e-4) side1.set(1, 0, 0); side1.normalize();
    const side2 = new THREE.Vector3().crossVectors(dir, side1).normalize();
    for (const [side, w, col, op] of [[side1, width, color, 0.9], [side2, width, color, 0.9], [side1, width * 0.35, 0xffffff, 1], [side2, width * 0.35, 0xffffff, 1]]) {
      const pos = [], idx = [];
      pts.forEach((p, i) => { pos.push(p.x + side.x * w, p.y + side.y * w, p.z + side.z * w, p.x - side.x * w, p.y - side.y * w, p.z - side.z * w); if (i) { const o = (i - 1) * 2; idx.push(o, o + 1, o + 2, o + 1, o + 3, o + 2); } });
      const geo = new THREE.BufferGeometry(); geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); geo.setIndex(idx);
      g.add(new THREE.Mesh(geo, this.basic(col, op)));
    }
    g.renderOrder = 25;
    return this.add(g, life, (k) => { const f = (1 - k) * (0.6 + Math.random() * 0.4); g.children.forEach((m) => { m.material.opacity = f; }); });
  }
  ring(pos, color, r0 = 0.2, r1 = 1.4, life = 0.4, y = 0.08) {
    const m = new THREE.Mesh(this.ringGeo, this.basic(color, 0.9)); m.position.set(pos.x, y, pos.z); m.renderOrder = 22;
    return this.add(m, life, (k) => { const e = 1 - Math.pow(1 - k, 3); const r = r0 + (r1 - r0) * e; m.scale.set(r, 1, r); m.material.opacity = 0.9 * (1 - k); });
  }
  burst(pos, color, r = 1.2, life = 0.35) {
    const m = new THREE.Mesh(this.ballGeo, this.basic(color, 0.95)); m.position.copy(pos); m.renderOrder = 23;
    const core = new THREE.Mesh(this.ballGeo, this.basic(0xffffff, 1)); m.add(core); core.scale.setScalar(0.55);
    return this.add(m, life, (k) => { const e = 1 - Math.pow(1 - k, 2.5); m.scale.setScalar(0.2 + r * e); m.material.opacity = 0.95 * (1 - k); core.material.opacity = Math.max(0, 1 - k * 2.2); });
  }
  projectile(a, b, obj, dur, arc = 0.6, onStep) {
    obj.position.copy(a);
    const d = b.clone().sub(a);
    if (obj.userData.align) obj.lookAt(b);
    return this.add(obj, dur, (k, dt) => {
      obj.position.copy(a).addScaledVector(d, k); obj.position.y += Math.sin(Math.PI * k) * arc;
      if (obj.userData.spin) obj.rotation.x += dt * 14;
      onStep?.(obj.position, dt);
    });
  }
}

/* ---------------- 화면 글자: 튀는 피해 숫자 ---------------- */
export class Labels {
  constructor(root, camera) { this.root = root; this.cam = camera; this.items = []; this.v = new THREE.Vector3(); this.W = 1; this.H = 1; }
  setSize(w, h) { this.W = w; this.H = h; }
  toScreen(p, out = {}) { this.v.copy(p).project(this.cam); out.x = (this.v.x * 0.5 + 0.5) * this.W; out.y = (-this.v.y * 0.5 + 0.5) * this.H; out.ok = this.v.z < 1; return out; }
  pop(p, text, o = {}) {
    const el = document.createElement('div'); el.className = 'dmg ' + (o.cls || ''); if (o.html) el.innerHTML = o.html; else el.textContent = text;
    if (o.color) el.style.color = o.color;
    el.style.opacity = '0';
    this.root.appendChild(el);
    this.items.push({ el, p: p.clone(), t: -(o.delay || 0), dur: o.dur ?? 0.95, vx: o.vx ?? (Math.random() - 0.5) * 60, rise: o.rise ?? 58, big: !!o.big, scale: o.scale ?? 1 });
    if (this.items.length > 36) this.items.shift().el.remove();
  }
  update(dt) {
    const s = {};
    for (let i = this.items.length - 1; i >= 0; i--) {
      const it = this.items[i]; it.t += dt;
      if (it.t < 0) continue;
      const k = it.t / it.dur;
      if (k >= 1) { it.el.remove(); this.items.splice(i, 1); continue; }
      this.toScreen(it.p, s);
      const up = it.rise * (1 - Math.pow(1 - Math.min(k * 1.6, 1), 3));
      const sc = (k < 0.09 ? 0.4 + (k / 0.09) * 1.15 : k < 0.22 ? 1.55 - ((k - 0.09) / 0.13) * 0.55 : 1) * (it.big ? 1.2 : 1) * it.scale;
      it.el.style.opacity = k > 0.72 ? String((1 - k) / 0.28) : '1';
      it.el.style.transform = `translate(${s.x + it.vx * Math.min(k * 2, 1)}px,${s.y - up}px) translate(-50%,-50%) scale(${sc})`;
    }
  }
  clear() { this.items.forEach((i) => i.el.remove()); this.items.length = 0; }
}
