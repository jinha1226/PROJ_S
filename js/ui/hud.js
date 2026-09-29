import { closeDoor } from '../core/combat.js';
import { gearName, pickGear, swapHands } from '../core/gear.js';
import { G, I, entAt } from '../core/state.js';
import { stoneCd } from '../core/stones.js';
import { BOSSES } from '../data/enemies.js';
import { RARITY, isWeapon, weaponOf } from '../data/gear.js';
import { COLORS, STONE } from '../data/stones.js';
import { T_OPEN, ZONES } from '../data/terrain.js';
import { FORMS } from '../data/weapons.js';
import { Anim, act, descend } from '../flow.js';
import { Sfx } from '../render/sfx.js';
import { $, UI } from './ui.js';

Object.assign(UI, {
  swapWeapon() {
    if (Anim.active || G.over) return;
    if (!isWeapon(G.eq.off)) { this.toast('보조 칸에 무기가 없다 — 🛡 장비 창에서 두 번째 무기를 보조에'); return; }
    this.instant(() => swapHands());
    const W = weaponOf(G.eq.weapon); this.toast(`${FORMS[W.form].icon} ${gearName(G.eq.weapon)} — ${FORMS[W.form].name} (${FORMS[W.form].injury}, 막타 → ${FORMS[W.form].part})`); Sfx.play('ui');
  },
  weaponInfo() {
    const r = ['weapon', 'off'].map((k) => { const it = G.eq[k]; if (!it) return `<div>　${k === 'off' ? '보조' : '무기'}: 없음</div>`; if (!isWeapon(it)) return `<div>　보조: <b style="color:${RARITY[it.rarity].css}">${gearName(it)}</b></div>`; const W = weaponOf(it), F = FORMS[W.form], C = COLORS[F.color]; return `<div>${k === 'weapon' ? '▶' : '　'} ${F.icon} <b style="color:${RARITY[it.rarity].css}">${gearName(it)}</b> ${F.name} ${W.dmg[0]}–${W.dmg[1]} · 부상 ${F.injury} · 막타 → ${F.part} <b style="color:${C.css}">●${C.name}</b></div>`; }).join('');
    this.info(`<h3>무기 · 보조 <small style="color:#9aa2bd">탭 = 맞바꾸기(보조가 무기일 때, 턴 소모 없음)</small></h3>${r}<div class="hint" style="margin-top:6px">💡 베기 = 출혈, 타격 = 골절(한 턴씩 쉰다·돌진 끊음), 찌르기 = 급소 표식 → 다음 찌르기 치명타</div>`);
  },
  renderWeapon() {
    if (!G.eq) return;
    const W = weaponOf(G.eq.weapon), F = FORMS[W.form], o = G.eq.off;
    $('#btn-wpn').innerHTML = `${F.icon}<small>${G.eq.weapon ? gearName(G.eq.weapon) : '맨손'}</small><small style="font-size:9px;opacity:.7">${isWeapon(o) ? '⇄ ' + gearName(o) : o ? gearName(o) : '보조 없음'}</small>`;
    $('#btn-wpn').style.boxShadow = `inset 0 -3px 0 ${COLORS[F.color].css}`;
    $('#gearcount').textContent = G.bag && G.bag.length ? G.bag.length : '';
  },
  legendFlash() { const el = $('#legendflash'); el.classList.remove('on'); void el.offsetWidth; el.classList.add('on'); },
  renderSlots(d) {
    this.slotsSnap = d;
    [...$('#souls').children].forEach((b, k) => {
      const q = d.slots[k], def = q.stone ? STONE[q.stone] : null;
      b.classList.toggle('on', !!def); b.style.setProperty('--c', q.color ? COLORS[q.color].css : 'transparent');
      b.querySelector('.si').textContent = def ? def.icon : '';
      b.querySelector('.sn').textContent = def ? def.name : '';
      b.classList.toggle('ready', !!def && !(q.cd > 0)); // 사용 가능: 밝게 빛남
      b.classList.toggle('cool', q.cd > 0); b.querySelector('.scd').textContent = q.cd > 0 ? q.cd : '';
    });
    this.renderAuras();
    $('#bagcount').textContent = (G.inv.reduce((a, b) => a + b.n, 0) + (d.bag.length ? ` · ◆${d.bag.length}` : '')) || '';
  },
  flashSlot(k) { const b = $('#souls').children[k]; if (!b) return; b.classList.remove('flash'); void b.offsetWidth; b.classList.add('flash'); },
  /** 색 감소: 해당 칸들이 그 색으로 번쩍이며 "−1" */
  cdFlash(slots, color) {
    const css = COLORS[color].css;
    for (const [k, n] of slots) {
      const b = $('#souls').children[k]; if (!b) continue;
      b.classList.remove('dec'); void b.offsetWidth; b.classList.add('dec');
      const m = document.createElement('span'); m.className = 'minus'; m.style.color = css; m.textContent = `−${n}`; b.appendChild(m); setTimeout(() => m.remove(), 900);
    }
  },
  /** 지속 효과: 남은 라운드를 칸에 작게 */
  renderAuras() {
    const A = G.auras || {};
    [...$('#souls').children].forEach((b, k) => { const q = G.slots[k], a = q && q.stone && STONE[q.stone].aura, r = a && A[a] ? A[a] - 1 : 0; b.querySelector('.aur').textContent = r > 0 ? `${r}R` : ''; });
  },
  slotInfo(k) {
    const q = (this.slotsSnap || { slots: G.slots }).slots[k];
    if (!q.stone) { this.info('<div>빈 칸 — 영혼석을 얻으면 스킬 버튼이 된다. 처음 끼우는 영혼석의 색으로 이 칸의 색이 정해진다.<br>몬스터를 <b>무기로</b> 쓰러뜨리면 막타 형태에 따라 영혼석이 떨어진다: ⚔베기→가죽🟢 · 🔨타격→뼈🟣 · 🗡찌르기→심장🔴</div>'); return; }
    const d = STONE[q.stone], C = COLORS[d.color];
    this.info(`<h3><span style="color:${C.css}">●</span> ${d.icon} ${d.name} <small style="color:#9aa2bd">쿨타임 ${stoneCd(q.stone)}턴${q.cd > 0 ? ` · 남은 ${q.cd}` : ' · 준비됨'}</small></h3><div>${d.line}</div><div class="hint" style="margin-top:4px">${C.name}: ${C.trig} 쿨타임 1 더 감소 (한 라운드 한 번)</div>`);
  },
  /* ---- HUD ---- */
  hp(hp, max) {
    const w = Math.max(0, hp / max) * 100;
    $('#hpfill').style.width = w + '%'; $('#hpghost').style.width = w + '%'; $('#hptext').textContent = `${Math.max(0, hp)} / ${max}`;
  },
  pstatus(st) {
    this.lastSt = st;
    const L = [['wet', '💧', '젖음'], ['frozen', '🧊', '빙결'], ['burn', '🔥', '화상'], ['poison', '☠', '중독'], ['stun', '💫', '기절'], ['haste', '💨', '가속'], ['immune', '🛡', '해독']];
    $('#pstatus').innerHTML = (this.shieldV > 0 ? `<span class="pill" style="border-color:#9fd8ff">🛡 보호막 ${this.shieldV}</span> ` : '') + L.filter(([k]) => st[k] > 0).map(([k, ic, nm]) => `<span class="pill">${ic} ${nm} ${st[k]}</span>`).join(' ');
  },
  hud(d) {
    this.lastHud = d; this.shieldV = d.shield;
    this.hp(d.hp, d.max); this.pstatus(d.st);
    $('#turns').textContent = `턴 ${d.turn}`;
    $('#floorname').textContent = `구역 ${G.zone}-${G.zf} ${G.theme.name}`;
    $('#lootcount').textContent = G.loot ? `🎒 ${Object.values(G.loot.mats).reduce((a, b) => a + b, 0)}` : '';
    this.bossBar(d.boss);
    $('#bagcount').textContent = d.inv ? d.inv : '';
    const c = $('#btn-ctx');
    if (d.stairs) { c.disabled = false; c.classList.add('live'); c.innerHTML = '⬇<small>내려가기</small>'; c.dataset.act = 'stairs'; }
    else if (d.gear) { c.disabled = false; c.classList.add('live'); c.innerHTML = `✋<small style="color:${RARITY[d.gear.rarity].css}">${d.gear.name} 줍기</small>`; c.dataset.act = 'gear'; }
    else if (d.door) { c.disabled = false; c.classList.remove('live'); c.innerHTML = '🚪<small>문 닫기</small>'; c.dataset.act = 'door'; c.dataset.x = d.door[0]; c.dataset.y = d.door[1]; }
    else { c.disabled = true; c.classList.remove('live'); c.innerHTML = '·<small>—</small>'; c.dataset.act = ''; }
  },
  ctxBtn() {
    if (Anim.active || G.over) return;
    const c = $('#btn-ctx');
    if (c.dataset.act === 'stairs') descend();
    else if (c.dataset.act === 'gear') { this.instant(() => pickGear()); this.renderWeapon(); }
    else if (c.dataset.act === 'door') { const x = +c.dataset.x, y = +c.dataset.y; if (G.tile[I(x, y)] === T_OPEN && !entAt(x, y)) act(() => closeDoor(x, y)); }
  },
  log(t, cls) {
    const el = $('#log'); const div = document.createElement('div'); div.textContent = t; if (cls) div.className = cls;
    el.appendChild(div); while (el.children.length > 3) el.firstChild.remove();
    [...el.children].forEach((c, k, a) => c.classList.toggle('old', k < a.length - 1));
    setTimeout(() => { div.style.opacity = '0'; setTimeout(() => div.remove(), 700); }, 6000);
  },
  banner(text, elem) {
    const el = $('#banner'); const C = { bolt: '#ffe14a', fire: '#ff9a3a', poison: '#9dff6a', ice: '#9fe2ff', steam: '#f2f6ff', push: '#ffd08a', info: '#c8d4ff' };
    el.textContent = text; el.style.color = C[elem] || '#fff'; el.classList.remove('show'); void el.offsetWidth; el.classList.add('show');
  },
  hurt() { const el = $('#hurt'); el.classList.add('on'); requestAnimationFrame(() => requestAnimationFrame(() => el.classList.remove('on'))); },
  floorCard() {
    const F = G.theme, el = $('#floorcard'), B = G.bossFloor ? BOSSES[ZONES[G.zone - 1].boss] : null;
    el.querySelector('.k').textContent = `구역 ${G.zone} · ${G.zf} / 3층${B ? ' · 보스' : ''}`; el.querySelector('.n').textContent = B ? `${F.name} — ${B.name}` : F.name; el.querySelector('.t').textContent = '💡 ' + (B ? `${B.desc} ${B.tip}` : F.tip);
    el.classList.add('on'); clearTimeout(this._fc); this._fc = setTimeout(() => el.classList.remove('on'), 4200);
    $('#log').innerHTML = '';
  },
  bossBar(b) {
    const el = $('#bossbar'); if (!b) { el.classList.add('hidden'); return; }
    el.classList.remove('hidden'); $('#bossname').textContent = '👑 ' + b.name; $('#bossfill').style.width = Math.max(0, b.hp / b.max * 100) + '%';
  },
});
