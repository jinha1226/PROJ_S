import { emitSlots, snapHud } from '../core/snap.js';
import { G, Game, TL } from '../core/state.js';
import { RT } from '../data/realtime.js';
import { Sfx } from '../render/sfx.js';
import { View } from '../render/view.js';

/* ================= 입력 · 화면 ================= */
export const $ = (s) => document.querySelector(s);

export const UI = {
  mode: 'normal',
  pend: null,
  valid: new Set(),
  prevIdx: -1,
  prev: null,
  buffered: null,
  travel: null,
  rest: null,
  skEls: {},
  logLines: [],
  lastHud: null,
  init() {
    // 대기 버튼: 누르고 있으면 제자리에서 시간이 흐르고, 짧게 누르면 쉬기(다시 누르면 멈춘다)
    const w = $('#btn-wait'); let t0 = 0;
    w.addEventListener('pointerdown', () => { t0 = performance.now(); this.joyHold = true; });
    const up = () => { if (!this.joyHold) return; this.joyHold = false; if (performance.now() - t0 < RT.restTap) { if (G.resting) this.stopAuto(); else this.startRest(); } };
    w.addEventListener('pointerup', up); w.addEventListener('pointercancel', up); w.addEventListener('pointerleave', up);
    $('#btn-attack').onclick = () => this.weaponInfo(); // 공격은 저절로 나간다: 이 칸은 무기 정보
    $('#btn-explore').onclick = () => this.startExplore();
    $('#btn-map').onclick = () => this.openMap();
    $('#log').onclick = () => this.openLog();
    $('#pstatus').onclick = () => this.openStatus();
    $('#hud-overlay-close').onclick = () => this.closeHudOverlay();
    // 퀵슬롯: 가방 소모품이 들어온 순서대로 6칸. 탭 = 사용(던지기는 조준), 길게 = 설명
    for (let k = 0; k < 6; k++) { const b = document.createElement('button'); b.className = 'qs empty'; this.hold(b, () => this.quickUse(k), () => this.quickInfo(k)); $('#quick').appendChild(b); }
    const souls = $('#souls');
    // 영혼석 6칸(한 줄) = 스킬 버튼. 탭 = 조준/발동, 길게 = 설명
    for (let k = 0; k < 6; k++) { const b = document.createElement('button'); b.className = 'slot'; b.innerHTML = '<span class="si"></span><small class="sn"></small><span class="scd"></span><b class="aur"></b>'; this.hold(b, () => this.stoneBtn(k), () => this.slotInfo(k)); souls.appendChild(b); }
    this.hold($('#btn-wpn'), () => this.weaponInfo(), () => this.weaponInfo());
    $('#btn-bag').onclick = () => { Sfx.play('ui'); this.openInv(); }; // 가방 = 장비 창(서브탭으로 소모품·영혼석)
    $('#btn-ctx').onclick = () => this.ctxBtn();
    $('#btn-status').onclick = () => this.openStatus();
    $('#btn-tilt').onclick = () => { const q = View.dio.rig.toggleTilt(); this.toast(q ? '45도 쿼터뷰' : '탑뷰'); };
    $('#btn-home').onclick = () => { View.dio.rig.reset(); this.toast('기본 시점으로 돌아왔다.'); };
    $('#btn-cancel').onclick = () => this.exitTarget();
    $('#btn-help').onclick = () => this.help(true);
    $('#btn-sound').onclick = () => { Sfx.on = !Sfx.on; $('#btn-sound').textContent = Sfx.on ? '🔊' : '🔇'; };
    addEventListener('keydown', (e) => this.key(e));
    this.layout(); addEventListener('resize', () => this.layout());
    document.addEventListener('gesturestart', (e) => e.preventDefault());
  },
  layout() {
    const town = Game.mode === 'town', top = $(town ? '#ttop' : '#top').getBoundingClientRect().bottom, bot = innerHeight - $(town ? '#tbottom' : '#bottom').getBoundingClientRect().top;
    View.dio.rig.viewShiftY = Math.round((bot - top) * 0.5); View.dio.resize();
  },
  hold(el, click, long) {
    let t = 0, fired = false;
    el.addEventListener('pointerdown', () => { fired = false; clearTimeout(t); t = setTimeout(() => { fired = true; long(); }, 480); });
    const cancel = () => clearTimeout(t);
    el.addEventListener('pointerup', cancel); el.addEventListener('pointerleave', cancel); el.addEventListener('pointercancel', cancel);
    el.addEventListener('click', () => { if (!fired) click(); fired = false; });
    el.addEventListener('contextmenu', (e) => e.preventDefault());
  },
  overlayOpen() { return !$('#screen').classList.contains('hidden') || !$('#help').classList.contains('hidden') || !$('#sheet').classList.contains('hidden') || !$('#hud-overlay').classList.contains('hidden'); },
  instant(fn) { TL.reset(); fn(); snapHud(); emitSlots(); const q = TL.q.slice().sort((a, b) => a.t - b.t); TL.reset(); for (const e of q) e.fn(); },
  info(html) { const el = $('#info'); el.innerHTML = html + '<div style="color:#9aa2bd;font-size:11.5px;margin-top:6px">화면을 탭하면 닫힌다</div>'; el.classList.remove('hidden'); el.onclick = () => this.hideInfo(); },
  hideInfo() { $('#info').classList.add('hidden'); this.highlightEnemy = null; View.refreshDecals(); },
  syncButtons() { $('#bagcount').textContent = G.inv.reduce((a, b) => a + b.n, 0) || ''; this.renderQuick?.(); },
  syncAll() { TL.reset(); snapHud(); emitSlots(); for (const q of TL.q) q.fn(); TL.reset(); this.renderWeapon(); },
  toast(t) { const el = $('#toast'); el.textContent = t; el.classList.add('on'); clearTimeout(this._tt); this._tt = setTimeout(() => el.classList.remove('on'), 1500); },
};
