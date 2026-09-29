import { visibleFoes } from '../core/fov.js';
import { calcStats, canEnchant, dropGear, equip, fullyKnown, gearCss, gearName, gearScore, holder, jewelKnown, knownView, unequip } from '../core/gear.js';
import { useItem } from '../core/items.js';
import { META, saveMeta } from '../core/meta.js';
import { G, Game } from '../core/state.js';
import { AMULETS, BAG_MAX, BRANDS, CAPS, EGOS, ELEM, GEAR_BASES, ORBS, QUALITY, RES_MUL, RINGS, SLOTS, SLOT_ICON, SLOT_NAME, UNRANDS, isJewel, isWeapon, matName, plusMax, slotKind, twoHanded, weaponOf } from '../data/gear.js';
import { COLORS, ORB_PURPLE, STONE } from '../data/stones.js';
import { CRITS, FORMS, SHAPES } from '../data/weapons.js';
import { Anim, act } from '../flow.js';
import { Preview } from '../render/gear-preview.js';
import { Sfx } from '../render/sfx.js';
import { Town } from '../town/town.js';
import { $, UI } from './ui.js';

/* ================= 가방 · 장비 창 (docs/설계_아이템_장비.md §12) ================= */
/** 같은 색 영혼석 개수 · 배율 (정착지에서는 등불지기의 영혼석) */
const stonesOf = () => (holder().town ? META.hero.slots : G.slots) || [];
const colorN = (color) => stonesOf().filter((q) => q.stone && STONE[q.stone].color === color).length;
const cmul = (w) => 1 + 0.15 * colorN(w.color);
const dot = (color) => `<span style="color:${COLORS[color].css}">●</span>`;

const inCombat = () => Game.mode === 'dungeon' && visibleFoes().some((e) => e.awake);
const sign = (v) => (v >= 0 ? `+${v}` : `${v}`);
const RES_DOT = (r) => (r > 0 ? '●'.repeat(r) : r < 0 ? '▼'.repeat(-r) : '—');
const has = (k) => (G.inv || []).some((q) => q.k === k);
const CN = { red: '빨강', purple: '보라', green: '초록' };
const PROP = {
  dmg: (p) => `피해 +${p.v}`, def: (p) => `방어 +${p.v}`, eva: (p) => `회피 +${p.v}%`, maxHp: (p) => `최대 HP +${p.v}`, res: (p) => `${ELEM[p.e].name} 저항 +1`, vision: () => '시야 +1',
  cd: (p) => `${CN[p.c]} 영혼석 쿨타임 −1`, brand: (p) => `${BRANDS[p.b].name}: ${BRANDS[p.b].line}`, ego: (p) => `${EGOS[p.g].name}: ${EGOS[p.g].line}`,
};
const COST = { maxHp: () => '최대 HP −3', torch: () => '횃불 소모 +25%', vision: () => '시야 −1', eva: () => '회피 −5%', cdUp: (c) => `${CN[c]} 영혼석 쿨타임 +1` };

/** 장비 설명 줄 — 모르는 것은 "?" */
function cardLines(it) {
  const B = GEAR_BASES[it.base], out = [];
  const Q = QUALITY[it.q];
  if (B.weapon) {
    const w = weaponOf(it), F = FORMS[w.form], C = COLORS[w.color], n = colorN(w.color);
    out.push(`${dot(w.color)} <b style="color:${C.css}">${C.name}</b> · ${w.hands === 2 ? '양손' : '한손'} · ${F.icon} ${F.name}${w.range ? ` · 원거리 ${w.range}칸` : ''}`);
    out.push(`피해 ${w.dmg[0]}–${w.dmg[1]}${w.shape === 'twin' ? ' ×2' : ''}${Q && Q.dmg ? ` <b>+${Q.dmg}</b>(품질)` : ''}${it.idP ? (it.plus ? ` <b>${sign(it.plus)}</b> (명중 ${sign(it.plus * 2)}%)` : '') : ' · 강화치 ?'} × <b style="color:${C.css}">${cmul(w).toFixed(2)}</b> <small style="color:#9aa2bd">(${C.name} 영혼석 ${n}개)</small>`);
    out.push(`모양: ${SHAPES[w.shape]}`, `<span style="color:#ffd27a">치명 ×2: ${CRITS[w.crit]}</span>${w.stun ? ' · 기절 25%' : ''}${w.retreat ? ' · 치고 1칸 물러남' : ''}`);
    if (w.range) out.push('<small style="color:#9aa2bd">붙은 적에게 쏘면 피해 절반</small>');
  } else if (B.orb) out.push(`${dot(B.orb)} ${ORBS[B.orb].line(1 + (it.idP ? it.plus : 0))}${it.idP ? '' : ' · 강화치 ?'}${B.orb === 'purple' ? `<br><small style="color:#9aa2bd">${Object.entries(ORB_PURPLE).map(([k, l]) => `${STONE[k].name} ${l}`).join(' · ')}</small>` : ''} <small style="color:#9aa2bd">(한손 무기일 때만 · 강화 최대 +${plusMax(it)})</small>`);
  else if (!B.jewel) out.push(`${B.mat ? matName(it.base) + ' · ' : ''}방어 ${B.def}${Q && Q.def ? ` <b>+${Q.def}</b>(품질)` : ''}${it.idP ? (it.plus ? ` <b>${sign(it.plus)}</b>` : '') : ' · 강화치 ?'}${B.eva ? ` · 회피 ${sign(B.eva)}%` : ''}${B.block ? ` · 막기 ${B.block}%` : ''} <small style="color:#9aa2bd">(강화 최대 +${plusMax(it)})</small>`);
  if (it.brand) out.push(it.idX ? `<span style="color:${gearCss(it)}">⚔ ${BRANDS[it.brand].name}: ${BRANDS[it.brand].line}</span>` : '<span style="color:#bcd4ff">빛난다 — 무기 속성 ?</span>');
  if (it.ego) out.push(it.idX ? `<span style="color:${gearCss(it)}">✦ ${EGOS[it.ego].name}: ${EGOS[it.ego].line}</span>` : '<span style="color:#bcd4ff">빛난다 — 방어구 속성 ?</span>');
  if (B.jewel && !it.art && !it.un) {
    if (jewelKnown(it)) { const T = (B.slot === 'neck' ? AMULETS : RINGS)[it.jt]; out.push(`<span style="color:#9fd8ff">${T.line.replace('{v}', sign(it.jv)).replace('{e}', it.je ? ELEM[it.je].name : '')}</span>`); }
    else out.push('<span style="color:#bcd4ff">정체 ? — 끼워 보면(보호·회피·힘·체력 반지) 또는 확인 두루마리로</span>');
  }
  if (it.art) { for (const p of it.art.props) out.push(p.known ? `<span style="color:#d0a0ff">◆ ${PROP[p.id](p)}</span>` : '<span style="color:#9a88b8">◆ ???</span>'); if (it.art.cost && fullyKnown(it)) out.push(`<span style="color:#ff8a8a">대가: ${COST[it.art.cost.id](it.art.cost.c)}</span>`); }
  if (it.un) { const U = UNRANDS[it.un]; out.push(`<span style="color:#ffcf4a;font-weight:700">★ ${U.line}</span>`, `<span style="color:#c8b890;font-size:11.5px">“${U.story}”${it.owner || U.owner ? ` — ${it.owner || U.owner}` : ''}</span>`); }
  return out;
}
function cardHtml(it, title) {
  const B = GEAR_BASES[it.base], tag = (it.un ? '옛 등불지기의 유품' : it.art ? '유물' : B.jewel ? '장신구' : it.brand || it.ego ? '속성 장비' : '기본템') + (QUALITY[it.q] ? ` · 품질 ${it.q}` : '');
  return `<div class="gcard" style="--c:${gearCss(it)}"><div class="gct"><small>${title}</small><b style="color:${gearCss(it)}">${gearName(it)}${it.art ? ' <small>(유물)</small>' : ''}</b><small>${tag} · ${SLOT_NAME[slotKind(it)]}${fullyKnown(it) ? '' : ' · 모르는 것이 있다 — 입어 보면(무기 10번 적중, 방어구 30턴) 또는 확인 두루마리'}</small></div>${cardLines(it).map((l) => `<div>${l}</div>`).join('')}</div>`;
}
const knownEq = (eq) => Object.fromEntries(Object.entries(eq).map(([k, v]) => [k, knownView(v)]));
/** 무기 피해 최대(색 배율 포함) */
const topDmg = (w, s) => Math.round((w.dmg[1] + s.dmg) * cmul(w)) * (w.shape === 'twin' ? 2 : 1);
/** 갈아입으면 바뀌는 최종 수치 — 아는 것만. 모르는 것이 있으면 "?" */
function statDiff(eq, slot, it) {
  const known = knownEq(eq), next = { ...known, [slot]: knownView(it) };
  if (slot === 'weapon' && twoHanded(it)) next.off = null;
  const a = calcStats(known), b = calcStats(next), wA = weaponOf(known.weapon), wB = weaponOf(next.weapon);
  const rows = [['최대 HP', a.maxHp, b.maxHp, ''], ['방어', a.def, b.def, ''], ['회피', a.eva, b.eva, '%'], ['막기', a.block, b.block, '%'], ['피해', topDmg(wA, a), topDmg(wB, b), ''], ['급소', a.crit, b.crit, '%'], ['시야', a.vision, b.vision, '']];
  for (const k of ['fire', 'frost', 'bolt', 'poison']) rows.push([ELEM[k].name + ' 저항', a.res[k], b.res[k], '단계']);
  const out = rows.filter(([, x, y]) => x !== y).map(([n, x, y, u]) => `<span class="${y > x ? 'up' : 'dn'}">${n} ${y > x ? '+' : ''}${y - x}${u}</span>`);
  if (slot === 'weapon') {
    if (wA.color !== wB.color) out.unshift(`<span class="form" style="font-weight:700">색: ${dot(wA.color)} ${COLORS[wA.color].name} → ${dot(wB.color)} ${COLORS[wB.color].name}</span>`);
    out.push(`<span style="color:${COLORS[wB.color].css}">${COLORS[wB.color].name} 영혼석 ${colorN(wB.color)}개 → 피해 ×${cmul(wB).toFixed(2)}</span>`);
    if (wA.form !== wB.form) out.unshift(`<span class="form">형태: ${FORMS[wA.form].name} → ${FORMS[wB.form].name}</span>`);
    if (twoHanded(it) && known.off) out.push(`<span class="dn">⚠ 양손 무기 — ${gearName(known.off)}은 가방으로</span>`);
  }
  if (slot === 'off' && twoHanded(known.weapon)) out.push('<span class="dn">⚠ 이 세트는 양손 무기 — 보조손을 들 수 없다</span>');
  if (!fullyKnown(it)) out.push('<span style="color:#bcd4ff">? 모르는 값은 빼고 비교</span>');
  return out.join(' ') || '<span style="color:#9aa2bd">아는 수치 변화 없음</span>';
}
/** 가방의 두루마리로 [확인] [강화] */
function scrollButtons(it) {
  if (Game.mode !== 'dungeon' || !it) return '';
  const b = [];
  if (!fullyKnown(it) && has('ident')) b.push('<button data-act="ident">📜 확인</button>');
  const k = isWeapon(it) ? 'enchW' : 'enchA';
  if (!isJewel(it) && has(k) && canEnchant(it, isWeapon(it) ? 'w' : 'a')) b.push(`<button data-act="${k}">✨ 강화 +1</button>`);
  else if (!isJewel(it) && has(k) && (it.art || it.un)) b.push('<button disabled>유물은 강화할 수 없다</button>');
  return b.join('');
}

Object.assign(UI, {
  invSel: null,
  openInv() {
    if (G.over && Game.mode === 'dungeon') return;
    if (Game.mode === 'town' && !META.hero) { this.toast('출발문에서 새 등불지기가 나서야 한다'); return; }
    this.invSel = null; this.renderInv();
  },
  renderInv() {
    const H = holder(), eq = H.eq, bag = H.bag, s = calcStats(knownEq(eq)), w = weaponOf(eq.weapon), sh = $('#sheet');
    sh.classList.add('tall');
    const wdot = (it) => (it && GEAR_BASES[it.base].weapon ? `<i class="wdot" style="background:${COLORS[weaponOf(it).color].css}"></i>` : it && GEAR_BASES[it.base].orb ? `<i class="wdot" style="background:${COLORS[GEAR_BASES[it.base].orb].css}"></i>` : '');
    const cell = (slot) => { const it = eq[slot]; return `<button class="eqs ${it ? 'on' : ''}" style="grid-area:${slot};--c:${it ? gearCss(it) : 'rgba(255,255,255,.2)'}" data-eq="${slot}">${SLOT_ICON[slot]}${wdot(it)}<small>${it ? gearName(it) : slot === 'off' && twoHanded(eq.weapon) ? '(양손)' : SLOT_NAME[slot]}</small></button>`; };
    const better = (it) => { const k = slotKind(it), tgt = k === 'ring' ? [eq.ring1, eq.ring2] : [eq[k]]; return tgt.some((o) => !o || gearScore(it) > gearScore(o) + 0.5); };
    const bagCells = Array.from({ length: BAG_MAX }, (_, k) => { const it = bag[k]; return it ? `<button class="bgc" style="--c:${gearCss(it)}" data-bag="${k}">${SLOT_ICON[slotKind(it)]}${wdot(it)}${better(it) ? '<i>▲</i>' : ''}<small>${gearName(it)}</small></button>` : '<div class="bgc empty"></div>'; }).join('');
    const town = H.town, stash = town ? META.gear : [];
    const stashCells = town ? (stash.length ? stash.map((it, k) => `<button class="bgc" style="--c:${gearCss(it)}" data-st="${k}">${SLOT_ICON[slotKind(it)]}<small>${gearName(it)}</small></button>`).join('') : '<p style="color:#9aa2bd;font-size:12.5px">창고가 비어 있다 — 대장간에서 만들거나, 가방에서 옮겨 둔다.</p>') : '';
    // 서브탭: 장비 · 소모품 · 영혼석(던전)
    const inv = town ? META.hero.inv || [] : G.inv || [], dungeon = !town;
    const tabs = [['gear', `🛡 장비 ${bag.length}`], ['items', `🧪 소모품 ${inv.reduce((a, q) => a + q.n, 0)}`], ...(dungeon ? [['stones', `💎 영혼석 ${G.sbag.length}`]] : [])];
    let tab = this.invTab || 'gear'; if (!tabs.some(([k]) => k === tab)) tab = 'gear';
    let detail = '';
    const sel = tab === 'gear' ? this.invSel : null;
    if (sel) {
      const it = sel.from === 'bag' ? bag[sel.i] : sel.from === 'stash' ? stash[sel.i] : eq[sel.slot];
      if (!it) this.invSel = null;
      else if (sel.from === 'eq') {
        detail = `${cardHtml(it, '입은 것')}<div class="row"><button data-act="unequip" ${bag.length >= BAG_MAX ? 'disabled' : ''}>해제</button>${scrollButtons(it)}<button data-act="back">닫기</button></div>${bag.length >= BAG_MAX ? '<div class="gline" style="color:#ff9aa4">가방이 가득 찼다</div>' : ''}`;
      } else if (sel.from === 'stash') {
        detail = `${cardHtml(it, '창고')}<div class="row"><button class="pri" data-act="take" ${bag.length >= BAG_MAX ? 'disabled' : ''}>가방으로</button><button data-act="back">닫기</button></div>`;
      } else {
        const k = slotKind(it), slots = k === 'ring' ? ['ring1', 'ring2'] : [k];
        const tgt = sel.slot && slots.includes(sel.slot) ? sel.slot : slots.find((x) => !eq[x]) || slots[0];
        const tabs2 = slots.length > 1 ? `<div class="wrow" style="margin-bottom:6px">${slots.map((x) => `<button class="wbtn ${x === tgt ? 'on' : ''}" data-tab="${x}">${SLOT_NAME[x]}${x === 'ring1' ? ' 1' : ' 2'}${eq[x] ? `<small style="color:${gearCss(eq[x])}">${gearName(eq[x])}</small>` : '<small>비어 있음</small>'}</button>`).join('')}</div>` : '';
        const cur = eq[tgt], blocked = k === 'off' && twoHanded(eq.weapon);
        detail = `${tabs2}${cur ? cardHtml(cur, '입은 것') : ''}${cardHtml(it, cur ? '새것' : '가방')}
          <div class="gline">${statDiff(eq, tgt, it)}</div>
          <div class="row"><button class="pri" data-act="equip" data-slot="${tgt}" ${blocked ? 'disabled' : ''}>${SLOT_NAME[tgt]}에 장착${inCombat() ? ' (한 턴)' : ''}</button>${scrollButtons(it)}<button data-act="drop">${town ? '창고로' : '버리기'}</button><button data-act="back">닫기</button></div>`;
      }
    }
    sh.innerHTML = `<h3>🎒 가방 · 장비 <small style="color:#9aa2bd;font-weight:400">${inCombat() ? '⚠ 전투 중 — 바꿀 때마다 한 턴' : '안전 — 자유롭게 바꾼다'}</small><button class="close">닫기</button></h3>
      <div class="eqgrid">${SLOTS.map((k) => cell(k)).join('')}<div class="doll" style="grid-area:doll" id="invdoll"></div></div>
      <button class="stline" data-act="stats">HP ${H.unit.max} · 방어 ${s.def} · 회피 ${s.eva}%${s.block ? ` · 막기 ${s.block}%` : ''} · 피해 ${w.dmg[0] + s.dmg}–${w.dmg[1] + s.dmg} <b style="color:${COLORS[w.color].css}">×${cmul(w).toFixed(2)}</b> <small>▸ 자세히</small></button>
      ${detail ? `<div class="gdetail">${detail}</div>` : ''}
      <div class="invtabs">${tabs.map(([k, l]) => `<button class="${tab === k ? 'on' : ''}" data-itab="${k}">${l}</button>`).join('')}</div>
      ${tab === 'items' ? this.itemsHtml(inv) : tab === 'stones' ? this.stonesHtml() : `<div class="sec">가방 ${bag.length}/${BAG_MAX} <small>▲ = 아는 것만 봐도 지금 것보다 나아 보인다 · ? = 모르는 것이 있다</small></div><div class="bggrid">${bagCells}</div>
      ${town ? `<div class="sec">창고 ${stash.length} <small>정착지에 남는다 — 죽어도 잃지 않는다</small></div><div class="bggrid">${stashCells}</div>` : ''}`}`;
    sh.classList.remove('hidden');
    Preview.mount($('#invdoll'), eq);
    sh.querySelector('.close').onclick = () => { sh.classList.add('hidden'); sh.classList.remove('tall'); };
    sh.querySelectorAll('[data-eq]').forEach((b) => { b.onclick = () => { this.invSel = eq[b.dataset.eq] ? { from: 'eq', slot: b.dataset.eq } : null; this.renderInv(); }; });
    sh.querySelectorAll('[data-bag]').forEach((b) => { b.onclick = () => { this.invSel = { from: 'bag', i: +b.dataset.bag }; this.renderInv(); }; });
    sh.querySelectorAll('[data-st]').forEach((b) => { b.onclick = () => { this.invSel = { from: 'stash', i: +b.dataset.st }; this.renderInv(); }; });
    sh.querySelectorAll('[data-tab]').forEach((b) => { b.onclick = () => { this.invSel = { ...this.invSel, slot: b.dataset.tab }; this.renderInv(); }; });
    sh.querySelectorAll('[data-act]').forEach((b) => { b.onclick = () => this.invAct(b.dataset.act, b.dataset.slot); });
    sh.querySelectorAll('[data-itab]').forEach((b) => { b.onclick = () => { this.invTab = b.dataset.itab; this.invSel = null; this.selBag = -1; Sfx.play('ui'); this.renderInv(); }; });
    if (tab === 'items') this.bindItems(sh);
    if (tab === 'stones') this.bindStones(sh);
  },
  invAct(a, slot) {
    const sel = this.invSel, H = holder();
    if (a === 'back') { this.invSel = null; this.renderInv(); return; }
    if (a === 'stats') { this.statsCard(); return; }
    if (a === 'take') { const it = META.gear.splice(sel.i, 1)[0]; H.bag.push(it); saveMeta(); this.invSel = null; this.renderInv(); return; }
    const it = sel && (sel.from === 'bag' ? H.bag[sel.i] : sel.from === 'eq' ? H.eq[sel.slot] : null);
    if (a === 'ident' || a === 'enchW' || a === 'enchA') { // 두루마리 읽기 = 한 턴
      if (Anim.active) { this.toast('잠깐 — 움직임이 끝난 뒤에'); return; }
      const uid = it && it.uid; act(() => useItem(a, uid)); this.renderInv(); Sfx.play('gem'); return;
    }
    const run = (fn) => {
      if (Game.mode === 'dungeon' && inCombat()) { if (Anim.active) { this.toast('잠깐 — 움직임이 끝난 뒤에'); return; } act(() => { fn(); return true; }); }
      else this.instant(fn);
      if (Game.mode === 'town') { saveMeta(); Town.redressHero?.(); Town.renderHud(); }
      this.invSel = null; this.renderInv();
    };
    if (a === 'equip') run(() => equip(sel.i, slot));
    else if (a === 'unequip') run(() => unequip(sel.slot));
    else if (a === 'drop') { this.instant(() => dropGear(sel.i)); if (Game.mode === 'town') saveMeta(); this.invSel = null; this.renderInv(); }
  },
  /** 전투 수치(누르면 출처) — 캐릭터 정보 카드와 상태창이 함께 쓴다. 모르는 장비 효과는 빼고 */
  statsRows() {
    const H = holder(), s = calcStats(knownEq(H.eq)), w = weaponOf(H.eq.weapon), m = cmul(w);
    s.src.dmg = [[`${H.eq.weapon ? gearName(H.eq.weapon) : '맨손'} 기본`, `${w.dmg[0]}~${w.dmg[1]}`], ...(s.src.dmg || []), [`× (1 + 0.15 × ${COLORS[w.color].name} ${colorN(w.color)})`, `×${m.toFixed(2)}`]];
    const src = (k) => (s.src[k] || []).map(([l, v]) => `<div class="srcl">${l} <b>${typeof v === 'number' && v > 0 ? '+' : ''}${v}</b></div>`).join('') || '<div class="srcl">—</div>';
    const row = (name, val, k, cap) => `<details><summary>${name} <b>${val}</b>${cap ? ` <small style="color:#ffd84a">(최대)</small>` : ''}</summary>${src(k)}</details>`;
    const flags = [];
    for (const it of SLOTS.map((k) => H.eq[k]).filter(Boolean)) {
      const v = knownView(it);
      if (it.un) flags.push(`<div style="color:#ffcf4a">★ ${UNRANDS[it.un].name}: ${UNRANDS[it.un].line}</div>`);
      if (v.brand) flags.push(`<div>⚔ ${BRANDS[v.brand].name}: ${BRANDS[v.brand].line}</div>`);
      if (GEAR_BASES[it.base].orb) flags.push(`<div>${dot(GEAR_BASES[it.base].orb)} ${gearName(it)}: ${ORBS[GEAR_BASES[it.base].orb].line(1 + v.plus)}</div>`);
      if (v.ego && !EGOS[v.ego].res) flags.push(`<div>✦ ${EGOS[v.ego].name}: ${EGOS[v.ego].line}</div>`);
      if (isJewel(it) && !it.art && !it.un && jewelKnown(it) && !['prot', 'eva', 'str', 'vit', 'res'].includes(it.jt)) flags.push(`<div>💍 ${gearName(it)}: ${(GEAR_BASES[it.base].slot === 'neck' ? AMULETS : RINGS)[it.jt].line}</div>`);
      if (!fullyKnown(it)) flags.push(`<div style="color:#bcd4ff">? ${gearName(it)} — 모르는 효과가 있다</div>`);
    }
    return `${row('최대 HP', `${H.unit.max} (기본 ${H.base})`, 'maxHp')}${row('방어', `${s.def} <small style="color:#9aa2bd">(맞을 때 0~${s.def} 줄임)</small>`, 'def', s.capped.def)}${row('회피', `${s.eva}% / ${CAPS.eva}%`, 'eva', s.capped.eva)}
      ${row('막기', `${s.block}%`, 'block', s.capped.block)}${row('피해', `${Math.round((w.dmg[0] + s.dmg) * m)}–${Math.round((w.dmg[1] + s.dmg) * m)} <small>(${w.dmg[0] + s.dmg}–${w.dmg[1] + s.dmg} ×${m.toFixed(2)} · ${FORMS[w.form].name} · 치명: ${CRITS[w.crit]})</small>`, 'dmg')}${row('급소 확률', `${s.crit}%${s.critMul > 2 ? ` · ×${s.critMul}` : ''}`, 'crit')}${s.acc ? row('명중', `${100 + s.acc}%`, 'acc') : ''}
      ${['fire', 'frost', 'bolt', 'poison'].map((k) => row(`${ELEM[k].name} 저항`, `${RES_DOT(s.res[k])} <small style="color:#9aa2bd">받는 피해 ×${RES_MUL[s.res[k]]}</small>`, 'res' + k)).join('')}
      <div class="gtxt" style="margin-top:6px">${flags.join('') || '<span style="color:#9aa2bd">특수 효과 없음</span>'}</div>
      <div class="gtxt" style="color:#9aa2bd;margin-top:4px">빌드의 중심은 영혼석 — 장비는 그것을 받쳐준다.</div>`;
  },
  statsCard() { this.info(`<h3>🧭 캐릭터 정보 <small style="color:#9aa2bd">수치를 누르면 출처</small></h3>${this.statsRows()}`); },
});
