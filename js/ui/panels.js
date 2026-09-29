import * as THREE from 'three';
import { visibleFoes } from '../core/fov.js';
import { itemName, useItem } from '../core/items.js';
import { META } from '../core/meta.js';
import { G, Game, I } from '../core/state.js';
import { swapStone } from '../core/stones.js';
import { BOSSES, CATS, DROPS, ENEMY, MAGE, MON_RES, catOf, kindOf, monRes } from '../data/enemies.js';
import { BAG_MAX, ELEM, UNRANDS } from '../data/gear.js';
import { CAT_ICON, ITEMS, ITEM_COL } from '../data/items.js';
import { COLORS, STONE } from '../data/stones.js';
import { C_STEAM, S_ASH, S_GRASS, S_ICE, S_OIL, S_WATER, T_DOOR, T_OPEN, T_STAIRS, T_WALL } from '../data/terrain.js';
import { HIDDEN } from '../data/visitors.js';
import { FORMS } from '../data/weapons.js';
import { act } from '../flow.js';
import { stIcons } from '../render/entity-view.js';
import { jo } from '../util/text.js';
import { $, UI } from './ui.js';

Object.assign(UI, {
  /* ---- 가방 = 장비 창(서브탭: 장비 · 소모품 · 영혼석) ---- */
  openBag(tab) { if (G.over) return; if (tab) this.invTab = tab; this.openInv(); },
  /** 소모품 탭: 장비와 같은 칸 모양. 누르면 위에 설명 카드와 [사용] */
  itemsHtml(inv) {
    const sel = inv.find((q) => q.k === this.itemSel), cells = Math.max(BAG_MAX, Math.ceil(inv.length / 5) * 5); // 장비 가방과 같은 칸 수
    const col = (k) => '#' + new THREE.Color(G.look[k] ? G.look[k].color : 0xffffff).getHexString();
    const grid = Array.from({ length: cells }, (_, n) => {
      const q = inv[n]; if (!q) return '<div class="bgc empty"></div>';
      const known = G.known[q.k];
      return `<button class="bgc ${q.k === this.itemSel ? 'sel' : ''}" style="--c:${col(q.k)}" data-k="${q.k}">${CAT_ICON[ITEMS[q.k].cat]}${known ? '' : '<i style="color:#ffe38a">?</i>'}<b class="cnt">${q.n}</b><small>${itemName(q.k)}</small></button>`;
    }).join('');
    let detail = '';
    if (sel) {
      const def = ITEMS[sel.k], known = G.known[sel.k], town = Game.mode !== 'dungeon';
      detail = `<div class="gdetail"><div class="gcard" style="--c:${col(sel.k)}"><div class="gct"><small>${{ potion: '물약', scroll: '두루마리', throw: '던지는 것' }[def.cat] || '소모품'} · ${sel.n}개</small><b style="color:${col(sel.k)}">${CAT_ICON[def.cat]} ${itemName(sel.k)}${known ? '' : ' ?'}</b></div><div>${known ? def.desc : def.cat === 'throw' ? '던지면 정체를 안다.' : '써 보면 정체를 안다.'}</div></div>
        <div class="row">${town ? '<button disabled>정착지에서는 쓰지 않는다</button>' : `<button class="pri" data-use="${sel.k}">${def.cat === 'throw' ? '🎯 던지기' : '사용'}</button>`}<button data-iback="1">닫기</button></div></div>`;
    }
    return `${detail}<div class="sec">소모품 ${inv.reduce((a, q) => a + q.n, 0)}</div><div class="bggrid">${grid}</div>`;
  },
  bindItems(sh) {
    sh.querySelectorAll('[data-k]').forEach((b) => { b.onclick = () => { this.itemSel = this.itemSel === b.dataset.k ? null : b.dataset.k; this.renderInv(); }; });
    const use = sh.querySelector('[data-use]'); if (use) use.onclick = () => { const k = use.dataset.use; this.itemSel = null; sh.classList.add('hidden'); sh.classList.remove('tall'); this.useFromBag(k); };
    const back = sh.querySelector('[data-iback]'); if (back) back.onclick = () => { this.itemSel = null; this.renderInv(); };
  },
  /** 영혼석 탭: 저장 중인 영혼석(가방)만 칸으로. 누르면 설명 · 같은 색 칸과 바꾸기 · 버리기 */
  stonesHtml() {
    const safe = !visibleFoes().some((e) => e.awake), max = G.sbagMax || 3, sel = this.selBag ?? -1, selId = sel >= 0 ? G.sbag[sel] : null;
    const grid = Array.from({ length: max }, (_, k) => { const id = G.sbag[k], number = `보관함 ${String(k + 1).padStart(2, '0')}`; if (!id) return `<div class="stone-cell empty"><span class="stone-number">${number}</span><small>비어 있음</small></div>`; const d = STONE[id], C = COLORS[d.color]; return `<button class="stone-cell ${k === sel ? 'sel' : ''}" style="--c:${C.css}" data-b="${k}" aria-label="${number}: ${d.name}"><span class="stone-number">${number}</span><span class="stone-icon">${d.icon}</span><small>${d.name}</small></button>`; }).join('');
    let detail = '';
    if (selId) {
      const d = STONE[selId], C = COLORS[d.color], same = G.slots.map((q, k) => [q, k]).filter(([q, k]) => q.stone && q.color === d.color && k < (G.level || 6));
      const swaps = same.map(([q, k]) => `<button data-sw="${k}" ${safe ? '' : 'disabled'}>${STONE[q.stone].icon} ${jo(STONE[q.stone].name, '과와')} 바꾸기</button>`).join('');
      detail = `<div class="gdetail"><div class="gcard" style="--c:${C.css}"><div class="gct"><small>${C.name} 영혼석 · 쿨타임 ${d.cd}</small><b style="color:${C.css}">${d.icon} ${d.name}</b></div><div>${d.line}</div>
        ${same.length ? '' : ''}</div>
        <div class="row">${swaps}<button data-drop="1">버리기</button><button data-sback="1">닫기</button></div></div>`;
    }
    return `<div class="stone-vault"><div class="stone-vault-head"><b>영혼석 보관함 ${G.sbag.length}/${max}</b>저장한 영혼석</div><div class="stone-storage">${grid}</div><div class="stone-vault-note">같은 색 칸과 교체 · 적이 없을 때</div></div>${detail}`;
  },
  bindStones(sh) {
    const sel = this.selBag ?? -1;
    sh.querySelectorAll('[data-b]').forEach((b) => { b.onclick = () => { const k = +b.dataset.b; this.selBag = this.selBag !== k ? k : -1; this.renderInv(); }; });
    sh.querySelectorAll('[data-sw]').forEach((b) => { b.onclick = () => { this.instant(() => swapStone(sel, +b.dataset.sw)); this.selBag = -1; this.renderInv(); }; });
    const back = sh.querySelector('[data-sback]'); if (back) back.onclick = () => { this.selBag = -1; this.renderInv(); };
    const drop = sh.querySelector('[data-drop]'); if (drop) drop.onclick = () => { const id = G.sbag.splice(sel, 1)[0]; this.selBag = -1; this.toast(`${jo(STONE[id].name, '을를')} 버렸다.`); this.instant(() => {}); this.renderInv(); };
  },
  useFromBag(k) {
    const def = ITEMS[k];
    if (def.target) { this.invTab = 'gear'; this.openInv(); this.toast(`${def.name}: ${k === 'ident' ? '확인할' : '강화할'} 장비를 고른다.`); return; }
    if (def.cat === 'throw') { this.enterTarget({ kind: 'item', id: k, name: '🫙 ' + itemName(k), range: 5 + (G.ps ? G.ps.throwRange : 0), color: G.known[k] ? ITEM_COL[k] : 0xd0d0e0, run: (x, y) => useItem(k, x, y) }); return; }
    if (G.player.st.frozen || G.player.st.stun) return;
    act(() => useItem(k));
  },
  /* ---- 정보 카드 ---- */
  showEnemy(e) {
    this.selectedEnemy = e.id;
    if (e.ally) { this.info(`<h3>👻 영혼 고블린 <small style="color:#9aa2bd">남은 ${e.life}턴</small></h3><div>보이는 적에게 달려가 공격한다. 부딪히면 자리를 바꾼다.</div>`); return; }
    const B = ENEMY[e.type], st = stIcons(e.st), cat = catOf(e), C = CATS[cat], kd = kindOf(e);
    let extra = '';
    if (e.type === 'mage') extra = ` 주문: ${MAGE[e.elem].icon}`;
    if (e.poison) extra = ' 칼에 독이 묻어 있어 맞으면 중독된다.';
    if (e.armor) extra = ' 갑옷이 두껍다.';
    const inj = [e.st.bleed ? `🩸 출혈 ${e.st.bleed}` : '', e.st.frac ? `🦴 골절 ${e.st.frac} · 한 턴씩 쉰다` : '', e.st.vital ? '✧ 급소 노출 · 다음 찌르기는 치명타' : ''].filter(Boolean).join(' · ');
    const drops = ['red', 'purple', 'green'].map((c) => { const S = STONE[DROPS[kd][c]], col = COLORS[c].css; return `<div><b style="color:${col}">● ${S.icon} ${S.name}</b> <span style="color:#9aa2bd">${S.line}</span></div>`; }).join('');
    this.info(`<h3>${e.name} <small style="color:#9aa2bd">${C.name} · HP ${e.hp}/${e.max} ${st}</small></h3><div>${B.desc}${extra}</div><div class="hint">💡 ${B.tip}</div>
      ${B.speed || B.danger ? `<div style="margin-top:4px">${B.speed === 'fast' ? '<b style="color:#ff9a6a">» 빠르다</b> ' : B.speed === 'slow' ? '<b style="color:#9ab8ff">« 느리다</b> ' : ''}${B.danger ? `⚠ ${B.danger}` : ''}</div>` : ''}
      ${inj ? `<div style="margin-top:4px">${inj}</div>` : ''}
      <div style="margin-top:6px">약점: ${G.weakKnown[cat] ? `<b style="color:#ffe14a">${FORMS[C.weak].icon} ${FORMS[C.weak].name}</b> · 피해 1.5배, 부상이 깊어진다` : '? · 맞혀 보면 드러난다'}</div>
      <div style="margin-top:4px;font-size:12.5px">저항: ${['fire', 'frost', 'bolt', 'poison'].map((el) => { const r = monRes(e, el); return `${ELEM[el].name} <b style="color:${r > 0 ? '#9fd8ff' : r < 0 ? '#ff9a9a' : '#9aa2bd'}">${r > 0 ? '●'.repeat(r) : r < 0 ? '▼'.repeat(-r) : '—'}</b>`; }).join(' · ')}</div>
      <div class="gtxt" style="margin-top:6px">떨어지는 영혼석 <small style="color:#9aa2bd">셋 중 하나가 무작위로</small>${drops}</div>`);
  },
  showTile(x, y) {
    const i = I(x, y); if (!G.seen[i]) return;
    const s = G.surf[i], t = G.tile[i], bk = G.block && G.block.get(i);
    if (bk) { const H = HIDDEN[bk], who = Object.values(STONE).filter((q) => q.elem === H.skill && q.tgt.t !== 'around' && q.tgt.t !== 'sight').map((q) => `${q.icon} ${q.name}`).join(' · '); this.info(`<div><b>${H.name}</b><br>${H.hint}.</div>`); return; }
    const T = { [S_WATER]: '💧 물웅덩이', [S_GRASS]: '🌿 풀', [S_OIL]: '🛢 기름', [S_ICE]: '🧊 얼음', [S_ASH]: '재' };
    let txt = T[s] || (t === T_DOOR ? '🚪 닫힌 문' : t === T_OPEN ? '🚪 열린 문' : t === T_STAIRS ? '⬇ 계단' : t === T_WALL ? '벽' : '돌바닥');
    if (G.fire[i]) txt += '<br>🔥 불타는 중';
    if (G.cloud[i]) txt += G.cloud[i] === C_STEAM ? '<br>♨ 증기' : '<br>🌫 연기';
    if (G.items.has(i)) txt += `<br>✦ ${itemName(G.items.get(i))}`;
    this.info(`<div>${txt}</div>`);
  },
  help(open) {
    const el = $('#help');
    if (!open) { el.classList.add('hidden'); return; }
    const M = META || {}, book = M.foeBook || {}, weakKnown = (Game.mode === 'town' ? M.hero && M.hero.weakKnown : G.weakKnown) || {};
    const resTxt = (k) => Object.entries(MON_RES[k] || {}).map(([el, v]) => `${ELEM[el].name} ${v > 0 ? '●'.repeat(v) : '▼'.repeat(-v)}`).join(' ');
    const foes = (M.seenFoes || []).map((k) => {
      const f = book[k] || { name: (BOSSES[k] || ENEMY[k] || {}).name || k }, weak = f.cat && weakKnown[f.cat] ? `${FORMS[CATS[f.cat].weak].icon} ${FORMS[CATS[f.cat].weak].name}` : '?';
      return `<tr><td>${f.name}</td><td>${f.hp ? `HP ${f.hp} · 공격 ${f.atk}` : ''}<br><small>약점 ${weak}${resTxt(k) ? ' · ' + resTxt(k) : ''}</small></td></tr>`;
    }).join('') || '<tr><td colspan="2">아직 없다</td></tr>';
    const seenS = new Set(M.seenStones || []);
    const stones = ['red', 'purple', 'green'].map((c) => `<h4 style="color:${COLORS[c].css}">${COLORS[c].name}</h4><table>${Object.entries(STONE).filter(([, S]) => S.color === c).map(([id, S]) => seenS.has(id) ? `<tr><td>${S.icon} ${S.name}</td><td>${S.line}</td></tr>` : '<tr><td>???</td><td></td></tr>').join('')}</table>`).join('');
    const seenU = new Set(M.unrandsSeen || []);
    const relics = Object.entries(UNRANDS).map(([id, U]) => seenU.has(id) ? `<tr><td>${U.name}</td><td>${U.line}<br><small>${U.owner ? U.owner + ' · ' : ''}${U.story}</small></td></tr>` : '<tr><td>???</td><td></td></tr>').join('');
    el.innerHTML = `<button class="close">닫기</button><h2>도감</h2>
      <h4>만난 적</h4><table>${foes}</table>
      <h4>영혼석 ${seenS.size}/${Object.keys(STONE).length}</h4>${stones}
      <h4>유품 ${seenU.size}/${Object.keys(UNRANDS).length}</h4><table>${relics}</table>`;
    el.classList.remove('hidden');
    el.querySelector('.close').onclick = () => el.classList.add('hidden');
  },

});
