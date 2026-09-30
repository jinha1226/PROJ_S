import { canEnchant, craftArmor, craftWeapon, gearCss, gearName, makeGear } from '../core/gear.js';
import { META, craftNote, invAdd, invCount, moodAdd, newHero, packLimit, recipeName, saveMeta } from '../core/meta.js';
import { progOf } from '../core/progress.js';
import { hasRoom, radius } from '../core/settlement.js';
import { cap, hearthGlow } from '../core/visitors.js';
import { ROOMS, SCX, SCY } from '../data/build.js';
import { ROLES } from '../data/classes.js';
import { BOSSES } from '../data/enemies.js';
import { QUALITY, SLOTS, SLOT_ICON, hasQuality, isWeapon, slotKind } from '../data/gear.js';
import { ITEMS, MATS } from '../data/items.js';
import { COLORS, STONE } from '../data/stones.js';
import { ZONES } from '../data/terrain.js';
import { JAR_WOOD } from '../data/torch.js';
import { BLD, CRAFT_B, JOBS, MOODS, ORIGINS, RECIPES, TRAITS, adj } from '../data/town.js';
import { LANDS } from '../data/visitors.js';
import { enterDungeon } from '../flow.js';
import { W3 } from '../render/common.js';
import { Sfx } from '../render/sfx.js';
import { View } from '../render/view.js';
import { classOf } from '../sim/classes.js';
import { $, UI } from '../ui/ui.js';
import { pick, rand } from '../util/rng.js';
import { jo } from '../util/text.js';
import { talkLine } from './town-npc.js';
import { Town } from './town.js';

Object.assign(Town, {
  renderHud() {
    const h = META.hero, cl = META.cleared.map((c, k) => (c ? `✓${k + 1}` : '')).filter(Boolean).join(' ');
    const S = META.settle, res = S ? `<br>🪵 ${S.stock.나무 || 0} · 🪨 ${S.stock.돌 || 0} · 🔮 ${META.mats.마석 || 0} · 빛 ${radius()}칸${S.bp.length ? ` · 청사진 ${S.bp.length}` : ''}` : '';
    $('#tinfo').innerHTML = `<b class="glow">🔥 ${hearthGlow()}</b> · 주민 ${META.npcs.length}/${cap()}${META.visitors.length ? ` · 방문자 ${META.visitors.length}` : ''} · ${h ? `등불지기 ${h.name}(${h.gen}대) HP ${h.hp}/${h.max}` : META.needSuccessor ? '횃불을 들 사람을 골라야 한다' : `다음 등불지기 ${META.gen + 1}대째`}${cl ? ` · 구역 ${cl}` : ''}${res}`;
  },
  sheet(html) { const sh = $('#sheet'); sh.innerHTML = html; sh.classList.remove('hidden'); sh.querySelector('.close')?.addEventListener('click', () => sh.classList.add('hidden')); return sh; },
  /* ---- 출발문: 구역 선택 · 준비 ---- */
  gate() {
    if (!META.hero && META.needSuccessor) { this.successionSheet(); return; }
    if (!META.hero) { META.hero = newHero(); saveMeta(); this.build(); this.renderHud(); UI.toast(`${META.hero.gen}대 등불지기 ${jo(META.hero.name, '이가')} 나섰다.`); }
    const h = META.hero;
    if (!this.prep) this.prep = { zone: Math.min(3, META.cleared.findIndex((c) => !c) < 0 ? 3 : META.cleared.findIndex((c) => !c)), items: {} };
    const P = this.prep, lim = packLimit(), carried = invCount(h.inv) + Object.values(P.items).reduce((a, b) => a + b, 0);
    const zones = ZONES.map((z, k) => { const open = k === 0 || META.cleared[k - 1]; return `<button class="wbtn ${P.zone === k ? 'on' : ''}" data-z="${k}" ${open ? '' : 'disabled style="opacity:.35"'}>${META.cleared[k] ? '✓' : open ? '▶' : '🔒'} 구역 ${k + 1}<small style="color:#9aa2bd">${z.name} · ${BOSSES[z.boss].name}</small></button>`; }).join('');
    const items = Object.entries(META.items).filter(([, n]) => n > 0).map(([k, n]) => `<div class="prow"><span>${ITEMS[k].name} <small style="color:#9aa2bd">창고 ${n}</small></span><span><button data-m="${k}">−</button><b>${P.items[k] || 0}</b><button data-p="${k}">+</button></span></div>`).join('') || '<p style="color:#9aa2bd;font-size:13px">창고에 소모품이 없다.</p>';
    const sh = this.sheet(`<h3>🚪 출발문 <button class="close">닫기</button></h3>
      <div class="gtxt">모험가 <b>${h.name}</b> (${h.gen}대째) · HP ${h.hp}/${h.max} · 영혼석 ${h.slots.filter((q) => q.stone).map((q) => `<span style="color:${COLORS[q.color].css}">${STONE[q.stone].icon}</span>`).join('') || '없음'}</div>
      <div class="sec">구역</div><div class="wrow">${zones}</div>
      <div class="sec">준비물 ${carried}/${lim} <small>이미 든 것 ${invCount(h.inv)} · 마을 사람이 늘면 더 챙겨 준다</small></div>${items}
      <div class="sec">장비</div><div class="gtxt">${SLOTS.filter((k) => h.eq[k]).map((k) => `<span style="color:${gearCss(h.eq[k])}">${SLOT_ICON[k]} ${gearName(h.eq[k])}</span>`).join(' · ')}</div>
      <button class="wbtn" data-inv="1" style="width:100%;margin-top:6px">🛡 장비 창 · 창고 ${META.gear.length} · 가방 ${h.bag.length}/20</button>
      ${META.buff === 'feast' ? '<div class="gtxt" style="margin-top:6px">🍲 든든한 한 끼를 먹었다. 출발할 때 보호막 6</div>' : ''}
      <button class="bigbtn" id="btn-depart">구역 ${P.zone + 1}로 출발</button>`);
    sh.querySelectorAll('[data-z]').forEach((b) => { b.onclick = () => { P.zone = +b.dataset.z; this.gate(); }; });
    sh.querySelectorAll('[data-p]').forEach((b) => { b.onclick = () => { const k = b.dataset.p; if (carried >= lim) { UI.toast('더는 못 챙긴다'); return; } if (k === 'recall' && (P.items.recall || 0) + (h.inv.find((q) => q.k === 'recall')?.n || 0) >= 1) { UI.toast('귀환 두루마리는 한 원정에 하나만'); return; } if ((P.items[k] || 0) < META.items[k]) { P.items[k] = (P.items[k] || 0) + 1; this.gate(); } }; });
    sh.querySelectorAll('[data-m]').forEach((b) => { b.onclick = () => { const k = b.dataset.m; if (P.items[k]) { P.items[k]--; this.gate(); } }; });
    sh.querySelector('[data-inv]').onclick = () => UI.openInv();
    sh.querySelector('#btn-depart').onclick = () => this.depart();
  },
  depart() {
    const h = META.hero, P = this.prep;
    for (const [k, n] of Object.entries(P.items)) if (n > 0) { META.items[k] -= n; invAdd(h.inv, k, n); h.known[k] = true; }
    const zone = P.zone + 1; this.prep = null;
    $('#sheet').classList.add('hidden');
    const D = View.dio, [gx, gy] = this.spot('gate'), g = { x: gx, y: gy }; D.fx.ring(W3(g.x, g.y), 0xb45aff, 0.3, 3, 0.6); D.pool.flash(W3(g.x, g.y), 0xc08aff, 80, 0.6, 8); Sfx.play('tele');
    for (const t of this.npcs) if (t.n.t.X >= 0 || t.n.t.E >= 1) { t.goto(g.x + (Math.random() - 0.5) * 3, g.y + 2 + Math.random(), 'gather', 3, [g.x, g.y]); }
    this.busy = true;
    setTimeout(() => { this.busy = false; enterDungeon(zone); }, 1300);
  },
  /* ---- 영혼석 제단: 칸 정리 · 다른 색 덮어쓰기 ---- */
  altar() {
    const h = META.hero;
    if (!h) { UI.toast('영혼석을 지닌 모험가가 없다'); return; }
    const sel = this.altarSel ?? -1, selId = sel >= 0 ? h.sbag[sel] : null;
    const chip = (id, attrs, cls = '') => { if (!id) return `<button class="gch empty" ${attrs}>·<small>빈 칸</small></button>`; const d = STONE[id]; return `<button class="gch ${cls}" style="--c:${COLORS[d.color].css}" ${attrs}>${d.icon}<small>${d.name}</small></button>`; };
    const slots = h.slots.map((q, k) => chip(q.stone, `data-s="${k}"`, selId ? (q.color === STONE[selId].color || !q.stone ? 'ok' : 'warn') : '')).join('');
    const bag = [0, 1, 2].map((k) => chip(h.sbag[k], `data-b="${k}"`, k === sel ? 'sel' : '')).join('');
    const keeper = META.npcs.find((n) => n.origin === 'keeper');
    const line = this.altarMsg || (selId ? `<b style="color:${COLORS[STONE[selId].color].css}">${STONE[selId].icon} ${STONE[selId].name}</b><br>${STONE[selId].line}` : '');
    const sh = this.sheet(`<h3>💎 영혼석 제단 <button class="close">닫기</button></h3>
      ${keeper ? `<div class="gtxt">${keeper.name}: “${talkLine(keeper)}”</div>` : ''}
      <div class="sec">영혼석 6칸</div><div class="gems">${slots}</div>
      <div class="sec">가방 ${h.sbag.length}/3</div><div class="gems" style="grid-template-columns:repeat(3,1fr)">${bag}</div>
      <div class="gline">${line}</div>`);
    this.altarMsg = null;
    sh.querySelectorAll('[data-b]').forEach((b) => { b.onclick = () => { const k = +b.dataset.b; this.altarSel = h.sbag[k] && sel !== k ? k : -1; this.altarArm = -1; this.altar(); }; });
    sh.querySelectorAll('[data-s]').forEach((b) => { b.onclick = () => {
      const k = +b.dataset.s, q = h.slots[k];
      if (!selId) { if (q.stone) { this.altarMsg = `<b style="color:${COLORS[q.color].css}">${STONE[q.stone].icon} ${STONE[q.stone].name}</b><br>${STONE[q.stone].line}`; this.altar(); } return; }
      const same = !q.stone || q.color === STONE[selId].color;
      if (!same && this.altarArm !== k) { this.altarArm = k; this.altarMsg = `⚠ <b>${jo(STONE[q.stone].name, '이가')}</b> 사라지고 이 칸이 <b style="color:${COLORS[STONE[selId].color].css}">${jo(COLORS[STONE[selId].color].name, '이가')}</b> 된다. 한 번 더 누르면 덮어쓴다.`; this.altar(); return; }
      if (same && q.stone) h.sbag[sel] = q.stone; else h.sbag.splice(sel, 1);
      const lost = !same ? q.stone : null;
      q.stone = selId; q.color = STONE[selId].color; q.cd = 0;
      this.altarSel = -1; this.altarArm = -1; saveMeta();
      this.altarMsg = lost ? `${jo(STONE[lost].name, '이가')} 빛이 되어 흩어졌다. 칸이 ${COLORS[q.color].name} 빛으로 물들었다.` : `${jo(STONE[selId].name, '을를')} 끼웠다.`;
      const [ax, ay] = this.spot('altar'), b2 = { x: ax, y: ay }; View.dio.fx.ring(W3(b2.x, b2.y), COLORS[q.color].hex, 0.3, 2.2, 0.5); View.dio.sparks.emit({ pos: W3(b2.x, b2.y, 1.4), n: 30, color: COLORS[q.color].hex, color2: 0xffffff, speed: 3, grav: 0, life: 0.7, size: 0.14 }); Sfx.chime(3);
      this.altar();
    }; });
  },
  /* ---- 제작소 ---- */
  craft(bid) {
    const have = CRAFT_B.filter((b) => hasRoom(b));
    if (!have.length) { UI.toast('작업방이 아직 없다.'); return; }
    if (!bid || !have.includes(bid)) bid = have[0];
    const workers = META.npcs.filter((n) => JOBS[n.job].b === bid);
    if (!workers.some((n) => n.id === this.crafter)) this.crafter = workers[0]?.id;
    const cr = workers.find((n) => n.id === this.crafter), closed = META.closed[bid];
    const tabs = have.map((b) => `<button class="wbtn ${b === bid ? 'on' : ''}" data-t="${b}">${BLD[b].icon} ${BLD[b].name}</button>`).join('');
    const who = workers.length ? workers.map((n) => `<button class="wbtn ${n === cr ? 'on' : ''}" data-c="${n.id}">${MOODS[n.mood + 2]} ${n.name}<small style="color:#9aa2bd">${craftNote(n)}</small></button>`).join('') : '<p style="color:#9aa2bd">일할 사람이 없다.</p>';
    const rows = RECIPES.filter((q) => q.b === bid && (!q.hidden || META.recipes[q.id])).map((q) => {
      const ok = Object.entries(q.in).every(([m, n]) => (META.mats[m] || 0) >= n);
      const inp = Object.entries(q.in).map(([m, n]) => `<span style="color:${(META.mats[m] || 0) >= n ? '#dfe3f5' : '#ff8a8a'}">${MATS[m]}${m} ${META.mats[m] || 0}/${n}</span>`).join(' ');
      return `<div class="prow"><span>${recipeName(q)}${q.hidden ? ' <small style="color:#ffe38a">새 제작법</small>' : ''}<br><small>${inp}</small></span><button class="mk" data-r="${q.id}" ${ok && cr && !closed ? '' : 'disabled'}>만들기</button></div>`;
    }).join('');
    const sh = this.sheet(`<h3>제작 <button class="close">닫기</button></h3><div class="wrow" style="grid-template-columns:repeat(3,1fr)">${tabs}</div>
      ${closed ? `<div class="gtxt" style="color:#ff9aa4;margin-top:8px">💢 ${closed} 때문에 이번엔 작업이 멈췄다.</div>` : ''}
      <div class="sec">누가 만들까</div><div class="wrow">${who}</div>
      <div class="sec">제작법</div>${rows}<div class="gline">${this.craftMsg || ''}</div>
      <div class="sec">재료</div><div class="gtxt">${Object.entries(MATS).map(([m, ic]) => `${ic}${m} ${META.mats[m] || 0}`).join(' · ')}</div>`);
    this.craftMsg = null;
    sh.querySelectorAll('[data-t]').forEach((b) => { b.onclick = () => this.craft(b.dataset.t); });
    sh.querySelectorAll('[data-c]').forEach((b) => { b.onclick = () => { this.crafter = b.dataset.c; this.craft(bid); }; });
    sh.querySelectorAll('[data-r]').forEach((b) => { b.onclick = () => { const q = RECIPES.find((r) => r.id === b.dataset.r); if (q.enhance || q.quality) { this.enhancePick(q, cr, bid); return; } this.doCraft(q, cr, bid); this.craft(bid); }; });
  },
  /** 대장장이: 마석 1 + 광석 2로 창고(또는 등불지기)의 장비 하나를 강화 +1, 또는 품질 한 단계(데드셀안 §5). 성실한 대장장이는 가끔 광석을 덜 쓴다 */
  enhancePick(q, n, bid) {
    const ok = q.quality ? (it) => hasQuality(it.base) && (it.q || 1) < 4 : (it) => canEnchant(it, isWeapon(it) ? 'w' : 'a');
    const pool = [...META.gear.map((it) => ['창고', it]), ...(META.hero ? [...Object.values(META.hero.eq), ...META.hero.bag].filter(Boolean).map((it) => ['등불지기', it]) : [])].filter(([, it]) => ok(it));
    const sh = this.sheet(`<h3>${q.quality ? '품질을 올릴' : '강화할'} 장비 <button class="close">닫기</button></h3><div class="gtxt">${n.name}: “${n.t.C >= 1 ? '제대로 두드려 주지.' : '뭐, 해 보지.'}” <small style="color:#9aa2bd">${q.quality ? '무기·방어구·방패만, 명장의 품질까지' : '유물·장신구는 강화할 수 없다'}</small></div>
      ${pool.map(([w, it], k) => `<div class="prow"><span style="color:${gearCss(it)}">${gearName(it, true)} <small>${w}</small></span><button class="mk" data-e="${k}">${q.quality ? `→ ${QUALITY[(it.q || 1) + 1].name}` : '+1'}</button></div>`).join('') || `<p style="color:#9aa2bd">${q.quality ? '품질을 올릴' : '강화할'} 수 있는 장비가 없다.</p>`}`);
    sh.querySelectorAll('[data-e]').forEach((b) => { b.onclick = () => {
      const it = pool[+b.dataset.e][1]; META.mats.마석 -= 1; const save = n.t.C >= 1 && rand() < 0.35; META.mats.광석 -= save ? 1 : 2;
      if (q.quality) it.q = (it.q || 1) + 1; else { it.plus++; it.idP = true; } moodAdd(n, n.t.C >= 1 ? 1 : 0); saveMeta();
      this.craftMsg = `✅ <b>${gearName(it, true)}</b>${save ? `<br>${adj(n, 'C')} ${jo(n.name, '이가')} 광석을 하나 아꼈다.` : ''}`;
      const [bx, by] = this.spot(bid), B = { x: bx, y: by }, D = View.dio; D.sparks.emit({ pos: W3(B.x, B.y, 1.2), n: 30, color: 0xffe14a, color2: 0xffffff, speed: 3, up: 2, grav: -3, life: 0.7, size: 0.13 }); Sfx.play('crit');
      Town.redressHero?.(); this.craft(bid);
    }; });
  },
  doCraft(q, n, bid) {
    for (const [m, k] of Object.entries(q.in)) META.mats[m] -= k;
    const notes = [], t = n.t;
    const plus = rand() < 0.1 + t.O * 0.07 + t.C * 0.05 + n.mood * 0.05, extra = t.C >= 1 && rand() < 0.35;
    if (t.H <= -1 && rand() < 0.3) { const m = pick(Object.keys(q.in)); if (META.mats[m] > 0) { META.mats[m]--; notes.push(`${jo(n.name, '이가')} ${m} 하나를 슬쩍 챙겼다`); } }
    let made;
    if (q.out) { const cnt = (q.n || 1) + (extra ? 1 : 0) + (plus ? 1 : 0); META.items[q.out] = (META.items[q.out] || 0) + cnt; made = `${ITEMS[q.out].name} ×${cnt}`; if (extra) notes.push(`${adj(n, 'C')} ${jo(n.name, '이가')} 하나 더 만들었다`); if (plus) notes.push('손끝이 좋아 하나 더 나왔다'); }
    else if (q.weapon) { const it = craftWeapon(q.weapon + (plus ? '+' : '')); META.gear.push(it); made = gearName(it); if (plus) notes.push(`명품이 나왔다. ${adj(n, 'O')} ${n.name}의 솜씨다`); }
    else if (q.gear) { const it = makeGear(q.gear, { plus: plus ? 1 : 0, q: 2, known: true }); META.gear.push(it); made = gearName(it); if (plus) notes.push(`명품이 나왔다. ${adj(n, 'O')} ${n.name}의 솜씨다`); }
    else if (q.armor) { const it = craftArmor(q.armor + (plus ? '+' : '')); META.gear.push(it); made = gearName(it); if (plus) notes.push(`명품이 나왔다. ${adj(n, 'O')} ${n.name}의 솜씨다`); }
    else { META.buff = 'feast'; made = '든든한 한 끼 · 다음 출발 보호막 6'; }
    moodAdd(n, t.C >= 1 ? 1 : 0);
    saveMeta();
    this.craftMsg = `✅ <b>${made}</b>${notes.length ? '<br>' + notes.join(' · ') : ''}`;
    const [bx, by] = this.spot(bid), b = { x: bx, y: by }, D = View.dio; D.sparks.emit({ pos: W3(b.x, b.y, 1.2), n: 30, color: plus ? 0xffe14a : 0xffb040, color2: 0xffffff, speed: 3, up: 2, grav: -3, life: 0.7, size: 0.13 }); D.pool.flash(W3(b.x, b.y), 0xffc070, 50, 0.5, 6); Sfx.play(plus ? 'crit' : 'blunt');
    const tn = this.npcs.find((x) => x.n === n); if (tn) View.dio.labels.pop(W3(tn.pos.x, tn.pos.z, 1.75), '', { html: `<span class="bub">${plus ? '이건 걸작이야!' : t.C <= -1 ? '됐지? 이 정도면…' : '다 됐어.'}</span>`, cls: 'gem', vx: 0, rise: 14, dur: 2.4 });
  },
  /* ---- 창고 · 휴식 · 카드 ---- */
  storage() {
    const it = Object.entries(META.items).filter(([, n]) => n > 0).map(([k, n]) => `${ITEMS[k].name} ×${n}`).join(' · ') || '없음';
    const ws = META.gear.map((it) => `<span style="color:${gearCss(it)}">${SLOT_ICON[slotKind(it)]} ${gearName(it)}</span>`).join(' · ') || '없음';
    const fallen = META.fallen.slice(-6).reverse().map((f) => `<div>🕯 ${f.name} (${f.gen}대) · 구역 ${f.zone}-${f.zf}, ${f.kills}마리</div>`).join('') || '<div>아직 아무도 쓰러지지 않았다.</div>';
    this.sheet(`<h3>📦 창고 <button class="close">닫기</button></h3>
      <div class="sec">재료</div><div class="gems" style="grid-template-columns:repeat(4,1fr)">${Object.entries(MATS).map(([m, ic]) => `<div class="gch" style="--c:#6a6050">${ic}<small>${m} ${META.mats[m] || 0}</small></div>`).join('')}</div>
      <div class="sec">소모품</div><div class="gtxt">${it}</div>
      <div class="sec">장비 ${META.gear.length}</div><div class="gtxt">${ws}</div>
      <div class="sec">구역</div><div class="gtxt">${ZONES.map((z, k) => `${META.cleared[k] ? '✓' : '·'} ${k + 1}. ${z.name} · ${BOSSES[z.boss].name}`).join('<br>')}</div>
      <div class="sec">기억할 이름들</div><div class="gtxt">${(META.rememberedKeepers || []).map((name) => `<div>🕯 ${name} · 등잔의 불씨를 이어받았다</div>`).join('') || '<div>아직 기억해 낸 이름이 없다.</div>'}${fallen}</div>`);
  },
  rest() {
    const h = META.hero, D = View.dio, b = { x: SCX, y: SCY };
    D.pool.flash(W3(b.x, b.y), 0xffa040, 90, 0.8, 7); D.sparks.emit({ pos: W3(b.x, b.y, 0.5), n: 30, color: 0xff9a3a, color2: 0xffe36a, speed: 2, up: 2.5, grav: 0.5, life: 1, size: 0.15 }); Sfx.play('fire');
    const S = META.settle, jar = JAR_WOOD;
    const sh = this.sheet(`<h3>🔥 모닥불 <button class="close">닫기</button></h3>${this.hearthInfo()}
      <div class="sec">불씨 단지 <small>던전에서 쓰면 횃불을 채운다. 창고 ${META.items.ember_jar || 0}개 · 출발문에서 챙긴다</small></div>
      <button class="wbtn" id="btn-jar" style="width:100%" ${(S.stock.나무 || 0) >= jar ? '' : 'disabled'}>🏺 모닥불 불씨를 단지에 담기 <small>🪵 나무 ${jar} · 지금 ${S.stock.나무 || 0}</small></button>`);
    sh.querySelector('#btn-jar').onclick = () => { if ((S.stock.나무 || 0) < jar) return; S.stock.나무 -= jar; META.items.ember_jar = (META.items.ember_jar || 0) + 1; saveMeta(); Sfx.play('fire'); UI.toast('불씨 단지를 하나 채웠다.'); this.rest(); };
    if (!h) { UI.toast(META.needSuccessor ? '횃불을 들 사람을 골라야 한다' : '출발문에서 새 등불지기가 나선다'); return; }
    h.hp = h.max; saveMeta(); this.renderHud();
    const n = META.npcs.slice().sort((a, c) => c.t.E + c.t.A - (a.t.E + a.t.A))[0];
    UI.toast(`${h.name}의 상처가 다 나았다.`);
    if (n) { const t = this.npcs.find((x) => x.n === n); if (t) View.dio.labels.pop(W3(t.pos.x, t.pos.z, 1.75), '', { html: `<span class="bub">${n.t.E >= 1 ? '푹 쉬어요, 제발…' : n.t.A >= 1 ? '따뜻한 거 좀 먹어요' : '다 나았으면 가 봐'}</span>`, cls: 'gem', vx: 0, rise: 14, dur: 2.6 }); }
  },
  npcCard(n) {
    const bars = TRAITS.map(([k, nm]) => { const v = n.t[k], w = Math.abs(v) * 25; return `<div class="trt"><span>${nm}</span><div class="tb"><i style="${v >= 0 ? 'left:50%' : `left:${50 - w}%`};width:${w}%;background:${v >= 0 ? '#7fd08a' : '#ff8a8a'}"></i></div><b>${v > 0 ? '+' + v : v}</b></div>`; }).join('');
    const rs = META.npcs.filter((m) => m !== n).map((m) => [m, n.rel[m.id] || 0]).sort((a, b) => b[1] - a[1]);
    const fr = rs.filter(([, v]) => v >= 20).map(([m]) => m.name).join(', ') || '—', fo = rs.filter(([, v]) => v <= -20).map(([m]) => m.name).join(', ') || '—';
    UI.info(`<h3>${MOODS[n.mood + 2]} ${n.name} <small style="color:#9aa2bd">${JOBS[n.job].icon} ${JOBS[n.job].name} · ${JOBS[n.job].b ? BLD[JOBS[n.job].b].name : '어디서나'}${n.origin && ORIGINS[n.origin] && ORIGINS[n.origin].name !== JOBS[n.job].name ? ` · ${ORIGINS[n.origin].name} 출신` : ''}</small></h3><div class="gtxt">“${talkLine(n)}”</div>${bars}
      <div class="gtxt" style="margin-top:6px">😊 친한 사이: ${fr}<br>😠 불편한 사이: ${fo}<br>🔨 솜씨: ${craftNote(n)}</div>${this.growthLine(n)}`);
    this.growthBtn(n);
  },
  /** 성장: 레벨 · Class · 찍을 점수 (등불지기와 같은 규칙, docs/설계_직업.md) */
  growthLine(rec) {
    const pr = progOf(rec), k = classOf(pr.build);
    return `<div class="gtxt" style="margin-top:6px">🎓 레벨 ${pr.level} · ${k.kind === 'none' ? '직업 없음' : `<b style="color:${ROLES[k.role].css}">${k.title}</b>`}${pr.points ? ` · <b style="color:#ffe38a">찍을 점수 ${pr.points}</b>` : ''} <button class="mini" data-grow="1">직업</button></div>`;
  },
  growthBtn(rec) { const b = document.querySelector('#info [data-grow]'); if (b) b.onclick = (ev) => { ev.stopPropagation(); UI.hideInfo(); UI.openClassPicker(rec); }; },
  heroCard() {
    const h = META.hero; if (!h) return;
    UI.info(`<h3>🧭 ${h.name} <small style="color:#9aa2bd">${h.gen}대째 모험가 · HP ${h.hp}/${h.max}</small></h3><div class="gtxt">장비: ${SLOTS.filter((k) => h.eq[k]).map((k) => `<span style="color:${gearCss(h.eq[k])}">${SLOT_ICON[k]}${gearName(h.eq[k])}</span>`).join(' ')}<br>영혼석: ${h.slots.filter((q) => q.stone).map((q) => `<span style="color:${COLORS[q.color].css}">${STONE[q.stone].icon}${STONE[q.stone].name}</span>`).join(' ') || '없음'}<br>가방: ${h.inv.map((q) => `${ITEMS[q.k].name}×${q.n}`).join(', ') || '비어 있음'}</div>${this.growthLine(h)}`);
    this.growthBtn(h);
  },
  report(r, res) {
    const W = { boss: `🏆 구역 ${r.zone} 보스 격파!${r.first ? ' 다음 구역이 열렸다.' : ''}`, recall: `📜 귀환 두루마리로 구역 ${r.zone}-${r.zf}에서 돌아왔다.`, death: `🕯 ${jo(r.hero, '이가')} 구역 ${r.zone}-${r.zf}에서 쓰러졌다. 영혼석과 전리품을 잃었다. 이름을 비석에 새겼다.`, first: '🔥 세상에 남은 마지막 모닥불. 사람이 모일수록 밝게 탄다.', resume: '🏕 정착지로 돌아왔다.' }[r.reason] || '';
    const loot = r.loot && Object.keys(r.loot).length ? Object.entries(r.loot).map(([m, n]) => `${MATS[m]}${m} ${n}`).join(' · ') : '';
    const lost = r.lost && Object.keys(r.lost).length ? Object.entries(r.lost).map(([m, n]) => `${m} ${n}`).join(' · ') : '';
    const arr = res.arrived.map((n) => `<div>🙋 ${adj(n, 'X')}, ${adj(n, 'C')} ${JOBS[n.job].name} ${n.name}</div>`).join('');
    const blt = [...new Set(res.wants)].map((b) => `<div>🏗 ${ROOMS[b].icon} ${jo(ROOMS[b].name, '이가')} 없어 아직 일을 못 한다.</div>`).join('');
    const evs = res.events.map((e) => `<div>${e.icon} ${e.text}</div>`).join('');
    const after = () => { const f = this.afterReport; this.afterReport = null; if (f) f(); };
    const vis = res.visitors.map((v) => `<div>❔ ${JOBS[v.npc.job].name} ${jo(v.npc.name, '이가')} 모닥불 앞에서 기다린다.</div>`).join('') + res.left.map((v) => `<div>🚶 기다리던 ${jo(v.npc.name, '이가')} 떠났다.</div>`).join('');
    const sh2 = [res.shard ? `<div>🔥 ${LANDS[res.shard - 1].name}의 등불 조각을 모닥불에 넣었다.</div>` : '', res.recallReward ? '<div>📜 보스를 처음 쓰러뜨려 귀환 두루마리를 하나 얻었다.</div>' : ''].join('');
    if (!W && !loot && !arr && !evs && !vis && !sh2) { after(); return; }
    const rs = this.sheet(`<h3>귀환 보고 <button class="close">확인</button></h3><div class="gtxt">${W}</div>${sh2 ? `<div class="gtxt" style="color:#f0c070;margin-top:6px">${sh2}</div>` : ''}
      ${res.dark ? '<div class="gtxt" style="color:#8a9ab8;margin-top:6px">정착지에는 아무도 남아 있지 않다…</div>' : ''}${vis ? `<div class="sec">방문자</div><div class="gtxt">${vis}</div>` : ''}
      ${loot ? `<div class="sec">가져온 것</div><div class="gtxt">${loot}</div>` : ''}${lost ? `<div class="sec">잃은 것</div><div class="gtxt" style="color:#ff9aa4">${lost}</div>` : ''}
      ${arr || blt ? `<div class="sec">새 얼굴</div><div class="gtxt">${arr}${blt}</div>` : ''}
      ${evs ? `<div class="sec">그동안 마을에서는</div><div class="gtxt">${evs}</div>` : ''}`);
    rs.querySelector('.close').addEventListener('click', after);
    this.renderHud();
  },
});
