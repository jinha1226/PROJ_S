import { visibleFoes } from '../core/fov.js';
import { calcStats, dropGear, equip, gearName, gearScore, holder, unequip } from '../core/gear.js';
import { META, saveMeta } from '../core/meta.js';
import { G, Game } from '../core/state.js';
import { AFFIXES, BAG_MAX, CAPS, GEAR_BASES, LEGENDS, RARITY, SLOTS, SLOT_ICON, SLOT_NAME, WEAPON_TRAIT, affixLine, isWeapon, matName, slotKind, weaponOf } from '../data/gear.js';
import { FORMS } from '../data/weapons.js';
import { Anim, act } from '../flow.js';
import { Preview } from '../render/gear-preview.js';
import { Town } from '../town/town.js';
import { $, UI } from './ui.js';

/* ================= 아이템 창 (docs/설계_아이템_장비.md §10) ================= */
const AREA = { head: 'head', neck: 'neck', weapon: 'weapon', off: 'off', hands: 'hands', body: 'body', feet: 'feet', ring1: 'ring1', ring2: 'ring2' };
const rc = (it) => RARITY[it.rarity].css;
const inCombat = () => Game.mode === 'dungeon' && visibleFoes().some((e) => e.awake);

function baseLines(it) {
  const B = GEAR_BASES[it.base], out = [];
  if (B.weapon) { const w = weaponOf(it), F = FORMS[w.form]; out.push(`${F.icon} ${F.name} · 피해 ${w.dmg[0]}–${w.dmg[1]}`); if (WEAPON_TRAIT[B.weapon]) out.push(WEAPON_TRAIT[B.weapon].line); }
  if (B.mat) out.push(`${matName(it.base)} · 방어 ${B.def}${B.eva ? ` · 회피 ${B.eva > 0 ? '+' : ''}${B.eva}%` : ''}`);
  if (B.block) out.push(`방어 +${B.def} · 막기 ${B.block}%`);
  if (B.vision) out.push('시야 +1 · 붙은 적을 칠 때 불 1');
  return out;
}
function cardHtml(it, title, diffIds) {
  const known = it.known, lines = baseLines(it).map((l) => `<div>${l}</div>`);
  for (const a of it.affixes) {
    const tag = diffIds && diffIds.add.has(a.id) ? ' <b style="color:#7dffa0">새 옵션</b>' : '';
    lines.push(`<div style="color:#bcd4ff">${affixLine(a, a.known)}${tag}</div>`);
  }
  if (diffIds) for (const id of diffIds.lost) lines.push(`<div style="color:#ff8a8a;text-decoration:line-through">${AFFIXES[id].line.replace('{v}', '').replace('{skill}', '')}</div>`);
  if (it.legend) lines.push(`<div style="color:#ff9a3a;font-weight:700">★ ${known ? LEGENDS[it.legend].line : '???'}</div>`);
  return `<div class="gcard" style="--c:${rc(it)}"><div class="gct"><small>${title}</small><b style="color:${rc(it)}">${gearName(it)}</b><small>${RARITY[it.rarity].name} ${SLOT_NAME[slotKind(it)]}${known ? '' : ' · 입으면 옵션이 하나씩, 한 층 내려가면 전부 드러난다'}</small></div>${lines.join('')}</div>`;
}
/** 갈아입으면 바뀌는 최종 수치 (미확인 새 장비는 기본 수치만) */
function statDiff(eq, slot, it) {
  const probe = it.known ? it : { ...it, affixes: it.affixes.filter((a) => a.known), legend: null };
  const a = calcStats(eq), b = calcStats({ ...eq, [slot]: probe });
  const wA = weaponOf(eq.weapon), wB = weaponOf(slot === 'weapon' ? probe : eq.weapon);
  const rows = [['최대 HP', a.maxHp, b.maxHp, ''], ['방어', a.def, b.def, ''], ['회피', a.eva, b.eva, '%'], ['막기', a.block, b.block, '%'], ['피해', wA.dmg[1] + a.dmg, wB.dmg[1] + b.dmg, ''], ['급소 확률', a.crit, b.crit, '%'], ['시야', a.vision, b.vision, '']];
  for (const k of ['fire', 'bolt', 'frost', 'poison']) rows.push([{ fire: '불', bolt: '번개', frost: '냉기', poison: '독' }[k] + ' 저항', a.res[k], b.res[k], '%']);
  const out = rows.filter(([, x, y]) => x !== y).map(([n, x, y, u]) => `<span class="${y > x ? 'up' : 'dn'}">${n} ${y > x ? '+' : ''}${y - x}${u}</span>`);
  if (slot === 'weapon' && wA.form !== wB.form) out.unshift(`<span class="form">형태: ${FORMS[wA.form].name} → ${FORMS[wB.form].name}</span>`);
  return out.join(' ') || '<span style="color:#9aa2bd">수치 변화 없음</span>';
}

Object.assign(UI, {
  invSel: null,
  openInv() {
    if (G.over && Game.mode === 'dungeon') return;
    if (Game.mode === 'town' && !META.hero) { this.toast('출발문에서 새 모험가가 나서야 한다'); return; }
    this.invSel = null; this.renderInv();
  },
  renderInv() {
    const H = holder(), eq = H.eq, bag = H.bag, s = calcStats(eq), w = weaponOf(eq.weapon), sh = $('#sheet');
    sh.classList.add('tall');
    const cell = (slot) => { const it = eq[slot]; return `<button class="eqs ${it ? 'on' : ''}" style="grid-area:${AREA[slot]};--c:${it ? rc(it) : 'rgba(255,255,255,.2)'}" data-eq="${slot}">${SLOT_ICON[slot]}<small>${it ? gearName(it) : SLOT_NAME[slot]}</small></button>`; };
    const better = (it) => { const k = slotKind(it), tgt = k === 'ring' ? [eq.ring1, eq.ring2] : [eq[k]]; return tgt.some((o) => !o || gearScore(it) > gearScore(o) + 0.5); };
    const bagCells = Array.from({ length: BAG_MAX }, (_, k) => { const it = bag[k]; return it ? `<button class="bgc" style="--c:${rc(it)}" data-bag="${k}">${SLOT_ICON[slotKind(it)]}${better(it) ? '<i>▲</i>' : ''}<small>${gearName(it)}</small></button>` : '<div class="bgc empty"></div>'; }).join('');
    const town = H.town, stash = town ? META.gear : [];
    const stashCells = town ? (stash.length ? stash.map((it, k) => `<button class="bgc" style="--c:${rc(it)}" data-st="${k}">${SLOT_ICON[slotKind(it)]}<small>${gearName(it)}</small></button>`).join('') : '<p style="color:#9aa2bd;font-size:12.5px">창고가 비어 있다 — 대장간에서 만들거나, 가방에서 옮겨 둔다.</p>') : '';
    let detail = '';
    const sel = this.invSel;
    if (sel) {
      const it = sel.from === 'bag' ? bag[sel.i] : sel.from === 'stash' ? stash[sel.i] : eq[sel.slot];
      if (!it) this.invSel = null;
      else if (sel.from === 'eq') {
        detail = `${cardHtml(it, '입은 것')}<div class="row"><button data-act="unequip" ${bag.length >= BAG_MAX ? 'disabled' : ''}>해제</button><button data-act="back">닫기</button></div>${bag.length >= BAG_MAX ? '<div class="gline" style="color:#ff9aa4">가방이 가득 찼다</div>' : ''}`;
      } else if (sel.from === 'stash') {
        detail = `${cardHtml(it, '창고')}<div class="row"><button class="pri" data-act="take" ${bag.length >= BAG_MAX ? 'disabled' : ''}>가방으로</button><button data-act="back">닫기</button></div>`;
      } else {
        const k = slotKind(it), slots = k === 'ring' ? ['ring1', 'ring2'] : isWeapon(it) ? ['weapon', 'off'] : [k];
        const tgt = sel.slot && slots.includes(sel.slot) ? sel.slot : slots.find((x) => !eq[x]) || slots[0];
        const tabs = slots.length > 1 ? `<div class="wrow" style="margin-bottom:6px">${slots.map((x) => `<button class="wbtn ${x === tgt ? 'on' : ''}" data-tab="${x}">${SLOT_NAME[x]}${x === 'ring1' ? ' 1' : x === 'ring2' ? ' 2' : ''}${eq[x] ? `<small style="color:${rc(eq[x])}">${gearName(eq[x])}</small>` : '<small>비어 있음</small>'}</button>`).join('')}</div>` : '';
        const cur = eq[tgt], ids = { add: new Set(it.affixes.filter((a) => a.known).map((a) => a.id)), lost: [] };
        if (cur) { const had = new Set(cur.affixes.filter((a) => a.known).map((a) => a.id)); for (const id of [...ids.add]) if (had.has(id)) ids.add.delete(id); ids.lost = [...had].filter((id) => !it.affixes.some((a) => a.id === id)); }
        detail = `${tabs}${cur ? cardHtml(cur, '입은 것') : ''}${cardHtml(it, cur ? '새것' : '가방', cur ? ids : null)}
          <div class="gline">${statDiff(eq, tgt, it)}</div>
          <div class="row"><button class="pri" data-act="equip" data-slot="${tgt}">${SLOT_NAME[tgt]}에 장착${inCombat() ? ' (한 턴)' : ''}</button><button data-act="drop">${town ? '창고로' : '버리기(발밑)'}</button><button data-act="back">닫기</button></div>`;
      }
    }
    sh.innerHTML = `<h3>🛡 장비 <small style="color:#9aa2bd;font-weight:400">${inCombat() ? '⚠ 전투 중 — 바꿀 때마다 한 턴' : '안전 — 자유롭게 바꾼다'}</small><button class="close">닫기</button></h3>
      <div class="eqgrid">${SLOTS.map(cell).join('')}<div class="doll" style="grid-area:doll" id="invdoll"></div></div>
      <button class="stline" data-act="stats">HP ${H.unit.max} · 방어 ${s.def} · 회피 ${s.eva}%${s.block ? ` · 막기 ${s.block}%` : ''} · 피해 ${w.dmg[0] + s.dmg}–${w.dmg[1] + s.dmg} <small>▸ 자세히</small></button>
      ${detail ? `<div class="gdetail">${detail}</div>` : ''}
      <div class="sec">가방 ${bag.length}/${BAG_MAX} <small>▲ = 지금 것보다 나아 보인다</small></div><div class="bggrid">${bagCells}</div>
      ${town ? `<div class="sec">창고 ${stash.length} <small>정착지에 남는다 — 죽어도 잃지 않는다</small></div><div class="bggrid">${stashCells}</div>` : ''}`;
    sh.classList.remove('hidden');
    Preview.mount($('#invdoll'), eq);
    sh.querySelector('.close').onclick = () => { sh.classList.add('hidden'); sh.classList.remove('tall'); };
    sh.querySelectorAll('[data-eq]').forEach((b) => { b.onclick = () => { this.invSel = eq[b.dataset.eq] ? { from: 'eq', slot: b.dataset.eq } : null; this.renderInv(); }; });
    sh.querySelectorAll('[data-bag]').forEach((b) => { b.onclick = () => { this.invSel = { from: 'bag', i: +b.dataset.bag }; this.renderInv(); }; });
    sh.querySelectorAll('[data-st]').forEach((b) => { b.onclick = () => { this.invSel = { from: 'stash', i: +b.dataset.st }; this.renderInv(); }; });
    sh.querySelectorAll('[data-tab]').forEach((b) => { b.onclick = () => { this.invSel = { ...this.invSel, slot: b.dataset.tab }; this.renderInv(); }; });
    sh.querySelectorAll('[data-act]').forEach((b) => { b.onclick = () => this.invAct(b.dataset.act, b.dataset.slot); });
  },
  invAct(a, slot) {
    const sel = this.invSel, H = holder();
    if (a === 'back') { this.invSel = null; this.renderInv(); return; }
    if (a === 'stats') { this.statsCard(); return; }
    if (a === 'take') { const it = META.gear.splice(sel.i, 1)[0]; H.bag.push(it); saveMeta(); this.invSel = null; this.renderInv(); return; }
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
  statsCard() {
    const H = holder(), s = calcStats(H.eq), w = weaponOf(H.eq.weapon);
    const src = (k) => (s.src[k] || []).map(([l, v]) => `<div class="srcl">${l} <b>${v > 0 ? '+' : ''}${v}</b></div>`).join('') || '<div class="srcl">—</div>';
    const row = (name, val, k, cap) => `<details><summary>${name} <b>${val}</b>${cap ? ` <small style="color:#ffd84a">(최대)</small>` : ''}</summary>${src(k)}</details>`;
    const flags = [];
    for (const it of SLOTS.map((k) => H.eq[k]).filter(Boolean)) {
      if (it.legend && it.known) flags.push(`<div style="color:#ff9a3a">★ ${LEGENDS[it.legend].name}: ${LEGENDS[it.legend].line}</div>`);
      for (const a of it.affixes) if (a.known && !['hp', 'def', 'eva', 'dmg', 'crit'].includes(a.id) && !a.id.startsWith('res')) flags.push(`<div>· ${affixLine(a)}</div>`);
    }
    this.info(`<h3>🧭 캐릭터 정보 <small style="color:#9aa2bd">수치를 누르면 출처</small></h3>
      ${row('최대 HP', `${H.unit.max} (기본 ${H.base})`, 'maxHp', s.capped.maxHp)}${row('방어', `${s.def} / ${CAPS.def}`, 'def', s.capped.def)}${row('회피', `${s.eva}% / ${CAPS.eva}%`, 'eva', s.capped.eva)}
      ${row('막기', `${s.block}%`, 'block', s.capped.block)}${row('피해', `${w.dmg[0] + s.dmg}–${w.dmg[1] + s.dmg} (${FORMS[w.form].name})`, 'dmg')}${row('급소 확률', `${s.crit}%`, 'crit')}${s.acc ? row('명중', `${100 + s.acc}%`, 'acc') : ''}
      ${['fire', 'bolt', 'frost', 'poison'].map((k) => row({ fire: '불', bolt: '번개', frost: '냉기', poison: '독' }[k] + ' 저항', `${s.res[k]}%`, 'res' + k, s.capped['res' + k])).join('')}
      <div class="gtxt" style="margin-top:6px">${flags.join('') || '<span style="color:#9aa2bd">특수 옵션 없음</span>'}</div>
      <div class="gtxt" style="color:#9aa2bd;margin-top:4px">빌드의 중심은 영혼석 — 장비는 그것을 받쳐준다.</div>`);
  },
});
