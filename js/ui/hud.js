import { closeDoor, colorMul, playerMove } from '../core/combat.js';
import { gearCss, gearName, pickGear } from '../core/gear.js';
import { itemName } from '../core/items.js';
import { G, Game, I, entAt } from '../core/state.js';
import { leaveStone, stoneCd, takeStone } from '../core/stones.js';
import { useLamp } from '../core/torch.js';
import { BOSSES } from '../data/enemies.js';
import { weaponOf } from '../data/gear.js';
import { CAT_ICON, ITEMS } from '../data/items.js';
import { COLORS, STONE } from '../data/stones.js';
import { T_OPEN, T_STAIRS, T_WALL, ZONES, ZONE_FLOORS } from '../data/terrain.js';
import { torchTier } from '../data/torch.js';
import { CRITS, FORMS, SHAPES } from '../data/weapons.js';
import { Anim, act, descend } from '../flow.js';
import { Sfx } from '../render/sfx.js';
import { $, UI } from './ui.js';

Object.assign(UI, {
  /** 공격 길게 누르기: 지금 무기 정보 (무기 교체는 없다 — 바꾸려면 가방에서 장착) */
  weaponInfo() {
    const w = G.eq.weapon, W = weaponOf(w), F = FORMS[W.form], o = G.eq.off;
    this.info(`<h3>${F.icon} ${w ? gearName(w) : '맨손'} <small style="color:${COLORS[W.color].css}">● ${COLORS[W.color].name} ×${colorMul(W).toFixed(2)}</small></h3><div>${W.hands === 2 ? '양손' : '한손'} · ${F.name} · 피해 ${W.dmg[0]}–${W.dmg[1]}${W.range ? ` · 원거리 ${W.range}칸` : ''}</div><div>모양: ${SHAPES[W.shape]}</div><div style="color:#ffd27a">치명 ×2: ${CRITS[W.crit]}</div>${o ? `<div>보조손: <b style="color:${gearCss(o)}">${gearName(o)}</b></div>` : ''}<div class="hint" style="margin-top:6px">💡 같은 색 영혼석 1개당 무기 피해 +15% · 베기 = 출혈, 타격 = 골절, 찌르기 = 급소 표식</div>`);
  },
  renderWeapon() {
    if (!G.eq) return;
    const W = weaponOf(G.eq.weapon), F = FORMS[W.form];
    $('#btn-wpn').innerHTML = `${F.icon}<small>${G.eq.weapon ? gearName(G.eq.weapon) : '맨손'}</small>`;
    $('#btn-wpn').style.boxShadow = `inset 0 -3px 0 ${COLORS[W.color].css}`;
    $('#gearcount').textContent = G.bag && G.bag.length ? G.bag.length : '';
  },
  /* ---- 퀵슬롯: 소모품 6칸 ---- */
  renderQuick() {
    const box = $('#quick'); if (!box || !G.inv) return;
    [...box.children].forEach((b, k) => {
      const q = G.inv[k];
      b.classList.toggle('empty', !q);
      if (!q) { b.innerHTML = '·'; return; }
      const def = ITEMS[q.k], col = '#' + (G.look[q.k]?.color ?? 0xffffff).toString(16).padStart(6, '0');
      b.innerHTML = `<i class="sw" style="background:${col}"></i>${CAT_ICON[def.cat]}<small>${G.known[q.k] ? def.name : '?'}</small>${q.n > 1 ? `<b>${q.n}</b>` : ''}`;
    });
  },
  quickUse(k) {
    const q = G.inv[k]; if (!q || G.over || Anim.active || this.overlayOpen()) return;
    Sfx.play('ui'); this.travel = null; this.explore = false; this.rest = null;
    if (this.mode === 'target') this.exitTarget();
    this.useFromBag(q.k);
  },
  quickInfo(k) { const q = G.inv[k]; if (!q) return; const def = ITEMS[q.k]; this.info(`<h3>${CAT_ICON[def.cat]} ${itemName(q.k)} ×${q.n}</h3><div>${G.known[q.k] ? def.desc : '정체를 모른다 — 써 보면 알게 된다'}</div>`); },
  /* ---- 발밑 영혼석: 흡수 / 가방 / 두고 가기(흩어짐) ---- */
  stoneOffer(d) {
    const id = d.id, S = STONE[id], C = COLORS[S.color], empty = G.slots.some((q, k) => !q.stone && k < (G.level || 6)), same = G.slots.map((q, k) => [q, k]).filter(([q, k]) => q.stone && q.color === S.color && k < (G.level || 6)), full = G.sbag.length >= (G.sbagMax || 3);
    const swap = !empty && same.length ? `<div class="sec">바꿔 끼울 칸 <small>빠진 영혼석은 가방으로${full ? ' — 가방이 차서 흩어진다' : ''}</small></div><div class="gems" style="grid-template-columns:repeat(${Math.min(6, same.length)},1fr)">${same.map(([q, k]) => `<button class="gch" style="--c:${C.css}" data-sw="${k}">${STONE[q.stone].icon}<small>${STONE[q.stone].name}</small></button>`).join('')}</div>` : '';
    const sh = $('#sheet'); sh.classList.remove('stones-view'); sh.innerHTML = `<h3><span><span style="color:${C.css}">●</span> ${S.icon} ${S.name} <small style="color:#9aa2bd">영혼석 · 쿨타임 ${S.cd}</small></span></h3>
      <div class="gtxt">${S.line}</div><div class="gtxt" style="color:#9aa2bd">${C.name}: ${C.trig} 쿨타임 1 더 감소</div>
      <div class="wrow" style="grid-template-columns:1fr 1fr 1fr;margin-top:10px">
        <button class="wbtn" data-a="absorb" ${empty ? '' : 'disabled style="opacity:.4"'}>흡수<small>${empty ? '빈 칸에 끼워 스킬로' : '열린 빈 칸 없음'}</small></button>
        <button class="wbtn" data-a="bag" ${full ? 'disabled style="opacity:.4"' : ''}>가방에<small>${G.sbag.length}/${G.sbagMax || 3}</small></button>
        <button class="wbtn" data-a="leave">두고 가기<small>바로 흩어진다</small></button></div>${swap}`;
    sh.classList.remove('hidden');
    const done = (ok) => { sh.classList.add('hidden'); if (ok) this.renderWeapon?.(); if (this.explore) setTimeout(() => this.exploreStep(), 60); };
    sh.querySelector('[data-a="absorb"]').onclick = () => { let ok = false; this.instant(() => { ok = takeStone('absorb'); }); done(ok); };
    sh.querySelector('[data-a="bag"]').onclick = () => { let ok = false; this.instant(() => { ok = takeStone('bag'); }); done(ok); };
    sh.querySelector('[data-a="leave"]').onclick = () => { this.instant(() => leaveStone()); done(false); };
    sh.querySelectorAll('[data-sw]').forEach((b) => { b.onclick = () => { let ok = false; this.instant(() => { ok = takeStone('absorb', +b.dataset.sw); }); done(ok); }; });
  },
  legendFlash() { const el = $('#legendflash'); el.classList.remove('on'); void el.offsetWidth; el.classList.add('on'); },
  renderSlots(d) {
    this.slotsSnap = d;
    [...$('#souls').children].forEach((b, k) => {
      const q = d.slots[k], def = q.stone ? STONE[q.stone] : null, locked = k >= (G.level || 6);
      b.classList.toggle('locked', locked);
      if (locked && !def) { b.classList.remove('on', 'ready', 'cool'); b.style.setProperty('--c', 'transparent'); b.querySelector('.si').textContent = '🔒'; b.querySelector('.sn').textContent = `레벨 ${k + 1}`; b.querySelector('.scd').textContent = ''; return; }
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
    if (!q.stone) { this.info('<div>빈 칸 — 영혼석을 얻으면 스킬 버튼이 된다. 처음 끼우는 영혼석의 색으로 이 칸의 색이 정해진다.<br>몬스터를 <b>무기로</b> 쓰러뜨리면 그 몬스터의 영혼석 셋(🔴🟣🟢) 중 하나가 무작위로 떨어진다 — 몬스터를 길게 누르면 무엇이 나오는지 보인다</div>'); return; }
    const d = STONE[q.stone], C = COLORS[d.color];
    this.info(`<h3><span style="color:${C.css}">●</span> ${d.icon} ${d.name} <small style="color:#9aa2bd">쿨타임 ${stoneCd(q.stone)}턴${q.cd > 0 ? ` · 남은 ${q.cd}` : ' · 준비됨'}</small></h3><div>${d.line}</div><div class="hint" style="margin-top:4px">${C.name}: ${C.trig} 쿨타임 1 더 감소 (한 라운드 한 번)</div>`);
  },
  /* ---- HUD ---- */
  hp(hp, max) {
    const w = Math.max(0, hp / max) * 100;
    // 빈사(30% 이하): 화면 가장자리가 조여 들고 심장이 뛴다
    const low = hp > 0 && hp <= max * 0.3; $('#lowhp').style.opacity = low ? String(0.45 + 0.55 * (1 - hp / (max * 0.3))) : '0';
    if (low && !this.heartT) this.heartT = setInterval(() => { const p = G.player; if (Game.mode === 'dungeon' && p && p.alive && p.hp <= p.max * 0.3) Sfx.play('heart'); else { clearInterval(this.heartT); this.heartT = 0; } }, 1000);
    $('#hpfill').style.width = w + '%'; $('#hpghost').style.width = w + '%'; $('#hptext').textContent = `${Math.max(0, hp)} / ${max}`;
  },
  pstatus(st) {
    this.lastSt = st;
    const L = [['wet', '💧', '젖음'], ['frozen', '🧊', '빙결'], ['burn', '🔥', '화상'], ['poison', '☠', '중독'], ['stun', '💫', '기절'], ['haste', '💨', '가속'], ['immune', '🛡', '해독']];
    $('#pstatus').innerHTML = (this.shieldV > 0 ? `<span class="pill" style="border-color:#9fd8ff">🛡${this.shieldV}</span> ` : '') + L.filter(([k]) => st[k] > 0).map(([k, ic]) => `<span class="pill">${ic}${st[k]}</span>`).join(' ');
  },
  hud(d) {
    this.lastHud = d; this.shieldV = d.shield;
    this.hp(d.hp, d.max); this.pstatus(d.st);
    $('#turns').textContent = `턴 ${d.turn}`;
    $('#floorname').textContent = `구역 ${G.zone}-${G.zf} ${G.theme.name}`;
    $('#lootcount').textContent = G.loot ? `🎒 ${Object.values(G.loot.mats).reduce((a, b) => a + b, 0)}` : '';
    $('#torchval').textContent = Number.isInteger(d.torch) ? d.torch : d.torch.toFixed(1);
    $('#torch').className = torchTier(d.torch);
    $('#enemycount').textContent = `👁 ${d.enemyCount}`; $('#enemycount').classList.toggle('zero', d.enemyCount === 0);
    $('#btn-explore').disabled = d.enemyCount > 0;
    $('#hud').classList.toggle('danger', !!d.danger);
    this.drawMap($('#minimap'));
    this.bossBar(d.boss);
    $('#bagcount').textContent = d.inv ? d.inv : '';
    this.renderQuick();
    const c = $('#btn-ctx');
    if (d.stairs) { c.disabled = false; c.classList.add('live'); c.innerHTML = '⬇<small>내려가기</small>'; c.dataset.act = 'stairs'; }
    else if (d.lamp) { c.disabled = false; c.classList.add('live'); c.innerHTML = '🕯<small>불씨 옮기기</small>'; c.dataset.act = 'lamp'; }
    else if (d.gear) { c.disabled = false; c.classList.add('live'); c.innerHTML = `✋<small style="color:${d.gear.css}">${d.gear.name} 줍기</small>`; c.dataset.act = 'gear'; }
    else if (d.rescue) { c.disabled = false; c.classList.add('live'); c.innerHTML = '🤝<small>구하기</small>'; c.dataset.act = 'rescue'; c.dataset.x = d.rescue[0]; c.dataset.y = d.rescue[1]; }
    else if (d.closedDoor) { c.disabled = false; c.classList.add('live'); c.innerHTML = '🚪<small>문 열기</small>'; c.dataset.act = 'open'; c.dataset.x = d.closedDoor[0]; c.dataset.y = d.closedDoor[1]; }
    else if (d.door) { c.disabled = false; c.classList.remove('live'); c.innerHTML = '🚪<small>문 닫기</small>'; c.dataset.act = 'door'; c.dataset.x = d.door[0]; c.dataset.y = d.door[1]; }
    else { c.disabled = true; c.classList.remove('live'); c.innerHTML = '·<small>—</small>'; c.dataset.act = ''; }
    c.classList.toggle('hidden', c.disabled); // 할 일이 있을 때만 떠오른다
  },
  ctxBtn() {
    if (Anim.active || G.over) return;
    const c = $('#btn-ctx');
    if (c.dataset.act === 'stairs') descend();
    else if (c.dataset.act === 'lamp') this.instant(() => { useLamp(); this.drawMap($('#minimap')); });
    else if (c.dataset.act === 'gear') { this.instant(() => pickGear()); this.renderWeapon(); }
    else if (c.dataset.act === 'open' || c.dataset.act === 'rescue') { const x = +c.dataset.x, y = +c.dataset.y; act(() => playerMove(x - G.player.x, y - G.player.y)); }
    else if (c.dataset.act === 'door') { const x = +c.dataset.x, y = +c.dataset.y; if (G.tile[I(x, y)] === T_OPEN && !entAt(x, y)) act(() => closeDoor(x, y)); }
  },
  log(t, cls) {
    this.logLines.push({ t, cls }); if (this.logLines.length > 120) this.logLines.shift();
    const el = $('#log'); const div = document.createElement('div'); div.textContent = t; if (cls) div.className = cls;
    el.appendChild(div); while (el.children.length > 4) el.firstChild.remove();
    [...el.children].forEach((c, k, a) => c.classList.toggle('old', k < a.length - 1));
    setTimeout(() => { div.style.opacity = '0'; setTimeout(() => div.remove(), 700); }, 6000);
  },
  banner(text, elem) {
    const el = $('#banner'); const C = { bolt: '#ffe14a', fire: '#ff9a3a', poison: '#9dff6a', ice: '#9fe2ff', steam: '#f2f6ff', push: '#ffd08a', info: '#c8d4ff' };
    el.textContent = text; el.style.color = C[elem] || '#fff'; el.classList.remove('show'); void el.offsetWidth; el.classList.add('show');
  },
  hurt(big) { const el = $('#hurt'); el.classList.toggle('big', !!big); el.classList.add('on'); requestAnimationFrame(() => requestAnimationFrame(() => el.classList.remove('on'))); },
  floorCard() {
    const F = G.theme, el = $('#floorcard'), B = G.bossFloor ? BOSSES[ZONES[G.zone - 1].boss] : null;
    el.querySelector('.k').textContent = `구역 ${G.zone} · ${G.zf} / ${ZONE_FLOORS}층${B ? ' · 보스' : ''}`; el.querySelector('.n').textContent = B ? `${F.name} — ${B.name}` : F.name; el.querySelector('.t').textContent = '💡 ' + (B ? `${B.desc} ${B.tip}` : F.tip);
    el.classList.add('on'); clearTimeout(this._fc); this._fc = setTimeout(() => el.classList.remove('on'), 4200);
    $('#log').innerHTML = '';
  },
  bossBar(b) {
    const el = $('#bossbar'); if (!b) { el.classList.add('hidden'); return; }
    el.classList.remove('hidden'); $('#bossname').textContent = '👑 ' + b.name; $('#bossfill').style.width = Math.max(0, b.hp / b.max * 100) + '%';
  },
  drawMap(canvas) {
    if (!G.seen || !canvas) return;
    const ctx = canvas.getContext('2d'), w = G.W, h = G.H;
    canvas.width = w * 3; canvas.height = h * 3;
    ctx.fillStyle = '#090d19'; ctx.fillRect(0, 0, canvas.width, canvas.height);
    for (let i = 0; i < G.seen.length; i++) {
      if (!G.seen[i]) continue;
      const x = i % w * 3, y = ((i / w) | 0) * 3;
      ctx.fillStyle = G.tile[i] === 0 ? '#555766' : G.vis[i] ? '#a7a58a' : '#5c6071';
      if (G.tile[i] === T_STAIRS) ctx.fillStyle = '#a5caff';
      if (G.lamps?.has(i)) ctx.fillStyle = '#ffd578';
      ctx.fillRect(x, y, 3, 3);
    }
    for (const e of G.ents) if (e.alive && !e.ally && G.vis[I(e.x, e.y)]) { ctx.fillStyle = '#ff5b62'; ctx.fillRect(e.x * 3, e.y * 3, 3, 3); }
    ctx.fillStyle = '#fff5a0'; ctx.fillRect(G.player.x * 3 - 1, G.player.y * 3 - 1, 5, 5);
  },
  openHudOverlay(html) { $('#hud-overlay-body').innerHTML = html; $('#hud-overlay').classList.remove('hidden'); },
  closeHudOverlay() { $('#hud-overlay').classList.add('hidden'); $('#hud-overlay-body').innerHTML = ''; },
  openMap() {
    this.openHudOverlay('<h2>전체 지도</h2><canvas id="fullmap"></canvas><p>누른 곳으로 걸어간다. 노랑: 나 · 빨강: 적 · 금빛: 등잔 · 파랑: 계단</p>');
    const cv = $('#fullmap'); this.drawMap(cv);
    cv.onclick = (ev) => { // 지도에서 누른 곳으로: 가 본 바닥 중 가장 가까운 칸
      const r = cv.getBoundingClientRect(), tx = Math.floor(((ev.clientX - r.left) / r.width) * G.W), ty = Math.floor(((ev.clientY - r.top) / r.height) * G.H);
      let best = null, bd = 99;
      for (let dy = -3; dy <= 3; dy++) for (let dx = -3; dx <= 3; dx++) { const x = tx + dx, y = ty + dy; if (x < 0 || y < 0 || x >= G.W || y >= G.H) continue; const i = I(x, y); if (!G.seen[i] || G.tile[i] === T_WALL) continue; const d = Math.abs(dx) + Math.abs(dy); if (d < bd) { bd = d; best = [x, y]; } }
      if (!best) { this.toast('아직 가 보지 않은 곳이다'); return; }
      this.closeHudOverlay(); if (Anim.active || G.over || (best[0] === G.player.x && best[1] === G.player.y)) return;
      this.explore = false; this.rest = null; this.startTravel(best[0], best[1]);
    };
  },
  openLog() {
    this.openHudOverlay('<h2>기록</h2>' + this.logLines.map((q) => `<div class="entry ${q.cls || ''}"></div>`).join(''));
    [...$('#hud-overlay-body').querySelectorAll('.entry')].forEach((el, i) => { el.textContent = this.logLines[i].t; });
    $('#hud-overlay').scrollTop = $('#hud-overlay').scrollHeight;
  },
});
