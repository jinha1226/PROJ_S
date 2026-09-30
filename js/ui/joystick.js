import { setIntent, setPaused } from '../core/clock.js';
import { G, Game } from '../core/state.js';
import { RT } from '../data/realtime.js';
import { View } from '../render/view.js';
import { $, UI } from './ui.js';

/* ================= 떠오르는 조이스틱 · 이동 키 · Space (docs/설계_실시간_전환.md §2) =================
   손을 대고 있는 동안만 시간이 흐른다. 짧은 탭(RT.joyHoldMs 미만, 움직임 없음)은 탭으로 넘긴다. */
const KEYV = { arrowup: [0, -1], w: [0, -1], arrowdown: [0, 1], s: [0, 1], arrowleft: [-1, 0], a: [-1, 0], arrowright: [1, 0], d: [1, 0], q: [-1, -1], e: [1, -1], z: [-1, 1], c: [1, 1] };
/** 화면 기준 방향 → 지도 기준(카메라가 돌아가 있어도 위 = 화면 위) */
function worldDir(sx, sy) { const yaw = View.dio.rig.yaw; return [Math.cos(yaw) * sx + Math.sin(yaw) * sy, -Math.sin(yaw) * sx + Math.cos(yaw) * sy]; }

Object.assign(UI, {
  joy: null, joyKeys: new Set(), joyHold: false, joyTapBlock: false,
  joyInit() {
    const c = View.dio.renderer.domElement, ring = $('#joy');
    c.addEventListener('pointerdown', (e) => {
      this.joyTapBlock = false; // 새 손: 지난 조이스틱의 탭 막기는 끝났다
      if (Game.mode !== 'dungeon' || this.overlayOpen() || this.joy || e.clientY < innerHeight * (1 - RT.joyZone)) return;
      this.joy = { id: e.pointerId, ox: e.clientX, oy: e.clientY, dx: 0, dy: 0, t0: performance.now(), on: false };
    });
    c.addEventListener('pointermove', (e) => { const j = this.joy; if (j && e.pointerId === j.id) { j.dx = e.clientX - j.ox; j.dy = e.clientY - j.oy; } });
    const up = (e) => { const j = this.joy; if (!j || e.pointerId !== j.id) return; this.joy = null; ring.style.display = 'none'; };
    c.addEventListener('pointerup', up); c.addEventListener('pointercancel', up);
    addEventListener('keyup', (e) => { this.joyKeys.delete(e.key.toLowerCase()); });
    const drop = () => { this.joyKeys.clear(); this.joyHold = false; this.joy = null; ring.style.display = 'none'; }; // 포커스·화면을 잃으면 누르던 손도 놓는다
    addEventListener('blur', drop); document.addEventListener('visibilitychange', () => { if (document.hidden) drop(); });
  },
  /** 매 프레임(Loop.frame): 조이스틱·키 → 시간이 흐를 의도 */
  feedIntent() {
    const j = this.joy, ring = $('#joy'); let sx = 0, sy = 0, hold = this.joyHold || this.joyKeys.has(' ');
    if (j) {
      const d = Math.hypot(j.dx, j.dy);
      if (!j.on && (performance.now() - j.t0 >= RT.joyHoldMs || d > RT.joyDead)) { j.on = true; this.joyTapBlock = true; ring.style.display = 'block'; ring.style.transform = `translate(${j.ox}px,${j.oy}px)`; }
      if (j.on) {
        hold = true;
        if (d > RT.joyDead) { const m = Math.min(1, d / RT.joyMax); sx = (j.dx / d) * m; sy = (j.dy / d) * m; }
        ring.firstChild.style.transform = `translate(${sx * 36}px,${sy * 36}px)`;
      }
    }
    for (const k of this.joyKeys) { const v = KEYV[k]; if (v) { sx += v[0]; sy += v[1]; } }
    const L = Math.hypot(sx, sy); if (L > 1) { sx /= L; sy /= L; }
    const off = this.overlayOpen() || G.over || Game.mode !== 'dungeon';
    setIntent(L > 0 && !off ? worldDir(sx, sy) : null, hold && !off); setPaused(off);
  },
});
