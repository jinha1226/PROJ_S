import * as THREE from 'three';
import * as K from './diorama.js';
import { weaponId } from '../data/gear.js';
import { weaponDoll } from './dolls.js';
import { heroSpec } from './hero-doll.js';

/* ---------- 아이템 창의 작은 인형 (드래그로 돌려본다) ---------- */
export const Preview = {
  r: null, scene: null, cam: null, doll: null, yaw: 0.5, raf: 0, host: null, drag: null,
  mount(host, eq) {
    if (!this.r) {
      this.r = new THREE.WebGLRenderer({ antialias: true, alpha: true });
      this.r.toneMapping = THREE.ACESFilmicToneMapping; this.r.toneMappingExposure = 1.1;
      this.scene = new THREE.Scene();
      this.scene.add(new THREE.HemisphereLight(0xfff0e0, 0x404060, 1.3));
      const sun = new THREE.DirectionalLight(0xffffff, 2.2); sun.position.set(2, 4, 3); this.scene.add(sun);
      this.cam = new THREE.PerspectiveCamera(28, 1, 0.1, 20); this.cam.position.set(0, 1.25, 4.1); this.cam.lookAt(0, 0.72, 0);
      const c = this.r.domElement; c.style.touchAction = 'none';
      c.addEventListener('pointerdown', (e) => { this.drag = e.clientX; c.setPointerCapture?.(e.pointerId); });
      c.addEventListener('pointermove', (e) => { if (this.drag == null) return; this.yaw += (e.clientX - this.drag) * 0.02; this.drag = e.clientX; });
      c.addEventListener('pointerup', () => { this.drag = null; });
    }
    this.host = host; host.appendChild(this.r.domElement);
    const w = host.clientWidth || 130, h = host.clientHeight || 160;
    this.r.setPixelRatio(Math.min(2, devicePixelRatio || 1)); this.r.setSize(w, h); this.cam.aspect = w / h; this.cam.updateProjectionMatrix();
    this.set(eq);
    cancelAnimationFrame(this.raf);
    const loop = () => { if (!this.host || !this.host.isConnected) { this.raf = 0; return; } this.raf = requestAnimationFrame(loop); if (this.drag == null) this.yaw += 0.006; if (this.doll) this.doll.root.rotation.y = this.yaw; this.r.render(this.scene, this.cam); };
    loop();
  },
  set(eq) {
    if (!this.scene) return;
    if (this.doll) { this.scene.remove(this.doll.root); this.doll.root.traverse((o) => { if (o.geometry) o.geometry.dispose(); }); }
    const sp = heroSpec(eq), d = K.doll(sp.parts, { scale: 1.3, gloss: sp.gloss });
    const ex = sp.extra(d); if (eq.weapon) ex.wh.add(weaponDoll(weaponId(eq.weapon), eq.weapon).root);
    if (sp.glow) d.mat.emissive.setRGB(...sp.glow);
    this.doll = d; this.scene.add(d.root);
  },
};
