import * as THREE from 'three';
import { clamp } from './materials.js';

/* ---------------- 카메라: 탑뷰 ↔ 45도, 두 손가락 회전, 핀치 확대 ---------------- */
export class CameraRig {
  constructor(camera, dom) {
    this.cam = camera; this.dom = dom;
    this.TOP = THREE.MathUtils.degToRad(61); this.QUARTER = THREE.MathUtils.degToRad(44);
    this.base = 20; this.zoom = 1; this.zoomT = 1; this.minZoom = 0.5; this.maxZoom = 1.7; this.tilesAcross = 9.5;
    this.yaw = 0; this.yawT = 0; this.pitch = this.TOP; this.pitchT = this.TOP;
    this.focus = new THREE.Vector3(); this.focusT = new THREE.Vector3();
    this.shakeAmt = 0; this.shakeOff = new THREE.Vector3(); this.viewShiftY = 0;
    this.onTap = null; this.onLongPress = null; this.onLongRelease = null;
    // 정착지: drag = 한 손가락 끌기 받는 곳({down,move,up}, 없으면 onePan이면 화면 이동) · panMode = 두 손가락 가운데로 이동 · bounds = 초점 범위
    this.drag = null; this.onePan = false; this.panMode = false; this.bounds = null; this.dragging = false;
    this.ptr = new Map(); this.tap = null; this.g = null; this.lp = 0;
    const d = dom;
    d.addEventListener('pointerdown', (e) => this._down(e));
    d.addEventListener('pointermove', (e) => this._move(e));
    d.addEventListener('pointerup', (e) => this._up(e, true));
    d.addEventListener('pointercancel', (e) => this._up(e, false));
    d.addEventListener('wheel', (e) => { e.preventDefault(); this.zoomT = clamp(this.zoomT * (1 + e.deltaY * 0.0012), this.minZoom, this.maxZoom); }, { passive: false });
    d.addEventListener('contextmenu', (e) => e.preventDefault());
  }
  _pair() { const [a, b] = [...this.ptr.values()]; return { ang: Math.atan2(b.y - a.y, b.x - a.x), d: Math.hypot(b.x - a.x, b.y - a.y), cx: (a.x + b.x) / 2, cy: (a.y + b.y) / 2 }; }
  _down(e) {
    try { this.dom.setPointerCapture(e.pointerId); } catch (_) { /* noop */ }
    this.ptr.set(e.pointerId, { x: e.clientX, y: e.clientY });
    if (this.ptr.size === 1) {
      this.tap = { x: e.clientX, y: e.clientY, t: performance.now(), multi: false, moved: false, long: false, rot: e.pointerType === 'mouse' && e.button !== 0 };
      clearTimeout(this.lp);
      this.lp = setTimeout(() => { const t = this.tap; if (t && !t.multi && !t.moved && !t.rot) { t.long = true; this.onLongPress?.(t.x, t.y); } }, 480);
    } else { if (this.tap) this.tap.multi = true; clearTimeout(this.lp); if (this.dragging) { this.dragging = false; this.drag?.cancel?.(); } if (this.ptr.size === 2) this.g = this._pair(); }
  }
  _move(e) {
    const p = this.ptr.get(e.pointerId); if (!p) return;
    const dx = e.clientX - p.x, dy = e.clientY - p.y; p.x = e.clientX; p.y = e.clientY;
    const t = this.tap;
    if (t && !t.moved && Math.hypot(e.clientX - t.x, e.clientY - t.y) > 12) { t.moved = true; if (this.ptr.size === 1 && !t.multi && !t.rot && this.drag) { this.dragging = true; this.drag.down?.(t.x, t.y); } }
    if (this.ptr.size === 1 && t && t.moved && !t.multi && !t.rot) { if (this.dragging) this.drag.move?.(e.clientX, e.clientY); else if (this.onePan) this.pan(dx, dy); }
    if (this.ptr.size >= 2) {
      const n = this._pair(), o = this.g;
      if (o) {
        let da = n.ang - o.ang; if (da > Math.PI) da -= Math.PI * 2; if (da < -Math.PI) da += Math.PI * 2;
        if (this.panMode) { this.yawT += da; this.pan(n.cx - o.cx, n.cy - o.cy); }
        else { this.yawT += da - (n.cx - o.cx) * 0.009; this.pitchT = clamp(this.pitchT + (n.cy - o.cy) * 0.004, this.QUARTER - 0.15, this.TOP + 0.3); }
        if (o.d > 20 && n.d > 20) this.zoomT = clamp(this.zoomT * (o.d / n.d), this.minZoom, this.maxZoom);
      }
      this.g = n;
    } else if (t && t.rot) {
      this.yawT -= dx * 0.008; this.pitchT = clamp(this.pitchT + dy * 0.004, this.QUARTER - 0.15, this.TOP + 0.3);
    }
  }
  _up(e, ok) {
    if (!this.ptr.has(e.pointerId)) return;
    this.ptr.delete(e.pointerId);
    if (this.ptr.size < 2) this.g = null;
    if (this.ptr.size === 0) {
      clearTimeout(this.lp); const t = this.tap; this.tap = null;
      if (this.dragging) { this.dragging = false; this.drag?.up?.(e.clientX, e.clientY, ok); return; }
      if (t?.long) this.onLongRelease?.();
      if (ok && t && !t.multi && !t.moved && !t.long && !t.rot && performance.now() - t.t < 650) this.onTap?.(t.x, t.y);
    }
  }
  /** 화면에서 dx, dy 픽셀만큼 끈 만큼 땅을 옮긴다(초점은 반대로) */
  pan(dx, dy) {
    const H = this.dom.clientHeight || innerHeight, k = (2 * this.base * this.zoom * Math.tan(this.cam.fov * Math.PI / 360)) / H, s = Math.sin(this.yaw), c = Math.cos(this.yaw), kz = k / Math.max(0.5, Math.sin(this.pitch));
    this.focusT.x += -dx * k * c - dy * kz * s; this.focusT.z += dx * k * s - dy * kz * c;
    const b = this.bounds; if (b) { this.focusT.x = clamp(this.focusT.x, b[0], b[2]); this.focusT.z = clamp(this.focusT.z, b[1], b[3]); }
  }
  toggleTilt() { const mid = (this.TOP + this.QUARTER) / 2; this.pitchT = this.pitchT > mid ? this.QUARTER : this.TOP; return this.pitchT < mid; }
  reset() { this.yawT = Math.round(this.yaw / (Math.PI * 2)) * Math.PI * 2; this.pitchT = this.TOP; this.zoomT = 1; }
  snap() { this.focus.copy(this.focusT); this.yaw = this.yawT; this.pitch = this.pitchT; this.zoom = this.zoomT; }
  /** 세로 화면에서도 가로로 tilesAcross칸이 보이도록 기본 거리를 맞춘다 */
  fit(aspect) { const t = Math.tan(this.cam.fov * Math.PI / 360); this.base = Math.max(this.tilesAcross / (2 * t * aspect), (this.tilesAcross * 1.25) / (2 * t)); }
  shake(a) { this.shakeAmt = Math.min(0.9, this.shakeAmt + a); }
  update(dt) {
    const k = 1 - Math.exp(-dt * 9), kf = 1 - Math.exp(-dt * 6.5);
    this.yaw += (this.yawT - this.yaw) * k; this.pitch += (this.pitchT - this.pitch) * k; this.zoom += (this.zoomT - this.zoom) * k;
    const dist = this.base * this.zoom;
    this.focus.lerp(this.focusT, kf);
    this.shakeAmt *= Math.exp(-dt * 10);
    const s = this.shakeAmt, tt = performance.now() * 0.001;
    this.shakeOff.set(Math.sin(tt * 71) * s * 0.35, Math.sin(tt * 53 + 1) * s * 0.2, Math.sin(tt * 63 + 2) * s * 0.35);
    const h = Math.cos(this.pitch) * dist, y = Math.sin(this.pitch) * dist;
    this.cam.position.set(this.focus.x + Math.sin(this.yaw) * h, this.focus.y + y, this.focus.z + Math.cos(this.yaw) * h).add(this.shakeOff);
    this.cam.lookAt(this.focus.x + this.shakeOff.x, this.focus.y, this.focus.z + this.shakeOff.z);
  }
}
