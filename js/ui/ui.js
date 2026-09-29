import { emitSlots, snapHud } from '../core/snap.js';
import { G, Game, TL } from '../core/state.js';
import { SKILLS } from '../data/skills.js';
import { Anim } from '../flow.js';
import { Sfx } from '../render/sfx.js';
import { View } from '../render/view.js';

/* ================= 입력 · 화면 ================= */
export const $ = (s) => document.querySelector(s);
/** 로그·배너 문구의 이모지를 걷어 낸다(쓸쓸한 톤) */
export const noEmoji = (t) => String(t).replace(/[\p{Extended_Pictographic}\uFE0F\u200D]/gu, '').replace(/\s{2,}/g, ' ').trim();

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
    const box = $('#skills');
    for (const sk of SKILLS) {
      const b = document.createElement('button'); b.className = 'sk'; b.style.setProperty('--c', sk.css);
      b.innerHTML = `${sk.icon}<small>${sk.name}</small><span class="cd"></span>`;
      this.hold(b, () => this.skillBtn(sk.id), () => this.skillInfo(sk.id));
      box.appendChild(b); this.skEls[sk.id] = b;
    }
    this.hold($('#btn-wait'), () => this.waitBtn(), () => this.startRest());
    const souls = $('#souls');
    for (let k = 0; k < 6; k++) { const b = document.createElement('button'); b.className = 'slot'; b.innerHTML = '<span class="si"></span><span class="scd"></span>'; b.onclick = () => this.slotInfo(k); souls.appendChild(b); }
    this.hold($('#btn-wpn'), () => this.swapWeapon(), () => this.weaponInfo());
    $('#btn-bag').onclick = () => { Sfx.play('ui'); this.openBag(); };
    $('#btn-ctx').onclick = () => this.ctxBtn();
    $('#btn-tilt').onclick = () => { const q = View.dio.rig.toggleTilt(); this.toast(q ? '45도 쿼터뷰' : '탑뷰'); };
    $('#btn-home').onclick = () => { View.dio.rig.reset(); this.toast('기본 탑뷰로 복귀'); };
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
  overlayOpen() { return !$('#screen').classList.contains('hidden') || !$('#help').classList.contains('hidden') || !$('#sheet').classList.contains('hidden'); },
  instant(fn) { if (Anim.active) return; TL.reset(); fn(); snapHud(); emitSlots(); const q = TL.q.slice().sort((a, b) => a.t - b.t); TL.reset(); for (const e of q) e.fn(); },
  info(html) { const el = $('#info'); el.innerHTML = html + '<div style="color:#9aa2bd;font-size:11.5px;margin-top:6px">화면을 탭하면 닫힌다</div>'; el.classList.remove('hidden'); el.onclick = () => this.hideInfo(); },
  hideInfo() { $('#info').classList.add('hidden'); },
  syncButtons() { $('#bagcount').textContent = G.inv.reduce((a, b) => a + b.n, 0) || ''; },
  syncAll() { TL.reset(); snapHud(); emitSlots(); for (const q of TL.q) q.fn(); TL.reset(); this.renderWeapon(); },
  toast(t) { const el = $('#toast'); el.textContent = t; el.classList.add('on'); clearTimeout(this._tt); this._tt = setTimeout(() => el.classList.remove('on'), 1500); },
};
