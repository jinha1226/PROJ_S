import * as THREE from 'three';
import * as K from './diorama.js';
import { G } from '../core/state.js';
import { W3 } from './common.js';
import { heroSpec } from './hero-doll.js';
import { ports } from './ports.js';
import { Sfx } from './sfx.js';
import { View } from './view.js';

/* ---------- 원형 턴제 화면: 분신 · 도달 범위 · 남은 거리 · 카메라 추적 · 전투 시작 ---------- */
Object.assign(View, {
  freeDecals: [], camFocus: null, ghost: null, ghostDanger: false, warnIds: new Set(),
  /** 반투명 분신을 (x,y)에 세운다. danger = 적 예고 범위 안 */
  setGhost(x, y, yaw, left, danger) {
    if (!this.ghost) {
      const sp = heroSpec(G.eq), d = K.doll(sp.parts, { scale: 1.3, gloss: 0.3 });
      d.mat.transparent = true; d.mat.opacity = 0.45; d.mat.depthWrite = false; d.mat.emissive.setRGB(0.15, 0.3, 0.6);
      d.ol.visible = false; d.mesh.castShadow = false;
      this.dio.scene.add(d.root); this.ghost = d;
      const tag = document.createElement('div'); tag.className = 'gleft'; this.labelRoot.appendChild(tag); this.ghostTag = tag;
    }
    const g = this.ghost; g.root.visible = true; g.root.position.set(x, 0, y); if (yaw != null) g.root.rotation.y = yaw;
    this.ghostDanger = !!danger; this.ghostTag.style.display = left == null ? 'none' : ''; if (left != null) this.ghostTag.textContent = `${left.toFixed(1)}m 남음`;
  },
  clearGhost() { if (this.ghost) { this.ghost.root.visible = false; this.ghostTag.style.display = 'none'; } },
  disposeGhost() { if (this.ghost) { this.dio.scene.remove(this.ghost.root); this.ghostTag.remove(); this.ghost = null; } },
  /** 분신 자리에서 칠 수 있는 적(빨간 테두리)과 기회 공격을 부르는 적(⚠) */
  setThreats(ids, warns) {
    for (const [id, ev] of this.evs) ev.threat = ids.has(id);
    this.warnIds = warns;
  },
  freeFrame(sdt, time) {
    const g = this.ghost;
    if (g && g.root.visible) {
      g.mat.opacity = this.ghostDanger ? 0.35 + 0.3 * Math.abs(Math.sin(time * 8)) : 0.45;
      g.mat.emissive.setRGB(this.ghostDanger ? 0.7 : 0.15, this.ghostDanger ? 0.1 : 0.3, this.ghostDanger ? 0.1 : 0.6);
      const s = {}; this.dio.labels.toScreen(new THREE.Vector3(g.root.position.x, 1.7, g.root.position.z), s);
      this.ghostTag.style.transform = `translate(${s.x.toFixed(1)}px,${s.y.toFixed(1)}px) translate(-50%,-100%)`;
    }
    for (const [id, ev] of this.evs) {
      const w = this.warnIds.has(id);
      if (w && !ev.warnEl) { ev.warnEl = document.createElement('span'); ev.warnEl.className = 'oppwarn'; ev.warnEl.textContent = '⚠'; ev.tag.prepend(ev.warnEl); }
      if (ev.warnEl) ev.warnEl.style.display = w ? '' : 'none';
    }
  },
  /** 원형 턴제 사건 — 처리했으면 true */
  freeOn(type, d) {
    const D = this.dio;
    switch (type) {
      case 'combat':
        if (d.start) { ports.UI.combatBanner(d.ambush); D.hitstop(180); D.rig.shake(0.2); Sfx.play(d.ambush ? 'gem' : 'alert'); }
        else { this.camFocus = null; ports.UI.combatBanner(null); }
        ports.UI.freeHud?.(); return true;
      case 'focus': this.camFocus = W3(d.x, d.y); return true;
      case 'focusEnd': this.camFocus = null; D.timeScale = 1; return true;
      case 'myTurn': this.camFocus = null; D.timeScale = 1; ports.UI.freeHud?.(); ports.UI.freeTurnStart?.(); return true;
      case 'opp': { const ev = this.evs.get(d.id); if (ev) { D.labels.pop(W3(ev.cur.x, ev.cur.z, ev.h + 0.4), '기회 공격!', { color: '#ffb070', cls: 'word', vx: 0 }); ev.sqv += 5; } Sfx.play('swing'); return true; }
      default: return false;
    }
  },
});
