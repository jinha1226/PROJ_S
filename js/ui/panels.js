import * as THREE from 'three';
import { visibleFoes } from '../core/fov.js';
import { itemName, takeWeapon, useItem } from '../core/items.js';
import { G, I } from '../core/state.js';
import { swapStone } from '../core/stones.js';
import { CATS, DROPS, ENEMY, MAGE, catOf, kindOf } from '../data/enemies.js';
import { CAT_ICON, ITEMS, ITEM_COL } from '../data/items.js';
import { COLORS, STONE } from '../data/stones.js';
import { C_STEAM, S_ASH, S_GRASS, S_ICE, S_OIL, S_WATER, T_DOOR, T_OPEN, T_STAIRS, T_WALL } from '../data/terrain.js';
import { FORMS, WPN } from '../data/weapons.js';
import { Anim, act } from '../flow.js';
import { stIcons } from '../render/entity-view.js';
import { Sfx } from '../render/sfx.js';
import { $, UI } from './ui.js';

Object.assign(UI, {
  /* ---- 가방 ---- */
  openBag() { if (G.over || Anim.active) return; this.selBag = -1; this.renderBag(); $('#sheet').classList.remove('hidden'); },
  renderBag() {
    const sh = $('#sheet'), safe = !visibleFoes().some((e) => e.awake), sel = this.selBag ?? -1, selId = sel >= 0 ? G.sbag[sel] : null;
    const chip = (id, attrs, cls = '') => { if (!id) return `<button class="gch empty" ${attrs}>·<small>빈 칸</small></button>`; const d = STONE[id]; return `<button class="gch ${cls}" style="--c:${COLORS[d.color].css}" ${attrs}>${d.icon}<small>${d.name}</small></button>`; };
    const weps = G.wpn.map((w, k) => { const W = WPN(w), F = FORMS[W.form]; return `<button class="wbtn ${k === G.wi ? 'on' : ''}" data-w="${k}">${F.icon} ${W.name}<small style="color:#9aa2bd">${F.name}·${W.dmg[0]}–${W.dmg[1]}</small></button>`; }).join('');
    const slots = G.slots.map((q, k) => chip(q.stone, `data-s="${k}"`, selId && q.stone && q.color === STONE[selId].color ? 'ok' : '')).join('');
    const bag = [0, 1, 2].map((k) => chip(G.sbag[k], `data-b="${k}"`, k === sel ? 'sel' : '')).join('');
    const line = selId ? `<b style="color:${COLORS[STONE[selId].color].css}">${STONE[selId].icon} ${STONE[selId].name}</b> — ${STONE[selId].line}${safe ? ' · 반짝이는 같은 색 칸을 탭하면 교체' : ' · <span style="color:#ff9aa4">적이 보여서 지금은 교체할 수 없다</span>'} <button class="close" data-drop="1" style="height:28px;margin-left:6px">버리기</button>` : '영혼석을 탭하면 설명이 나온다';
    const rows = G.inv.length ? G.inv.map((q) => {
      const def = ITEMS[q.k], known = G.known[q.k], col = '#' + new THREE.Color(G.look[q.k].color).getHexString();
      return `<button class="item" data-k="${q.k}"><span class="sw" style="background:${col}">${CAT_ICON[def.cat]}</span><span class="nm">${itemName(q.k)}${known ? '' : ' <span style="color:#ffe38a">?</span>'}<small>${known ? def.desc : def.cat === 'throw' ? '던지면 정체를 안다' : '써 보면 정체를 안다'}</small></span><span class="n">×${q.n}</span></button>`;
    }).join('') : '<p style="color:#9aa2bd;font-size:13px">비어 있다. 바닥의 반짝이는 물건을 밟으면 줍는다.</p>';
    sh.innerHTML = `<h3>가방 <button class="close">닫기</button></h3>
      <div class="sec">무기 <small>탭하면 바꿔 든다 (턴 소모 없음)</small></div><div class="wrow">${weps}</div>
      <div class="sec">영혼석 6칸 <small>🔴 공격 적중 · 🟣 대기 · 🟢 피격 때 발동</small></div><div class="gems">${slots}</div>
      <div class="sec">영혼석 가방 ${G.sbag.length}/3 <small>같은 색 칸하고만 교체 · 적이 안 보일 때</small></div><div class="gems" style="grid-template-columns:repeat(3,1fr)">${bag}</div>
      <div class="gline">${line}</div>
      <div class="sec">물건</div>${rows}`;
    sh.querySelector('.close').onclick = () => sh.classList.add('hidden');
    sh.querySelectorAll('[data-w]').forEach((b) => { b.onclick = () => { if (+b.dataset.w !== G.wi) this.swapWeapon(); this.renderBag(); }; });
    sh.querySelectorAll('[data-b]').forEach((b) => { b.onclick = () => { const k = +b.dataset.b; this.selBag = G.sbag[k] && this.selBag !== k ? k : -1; this.renderBag(); }; });
    sh.querySelectorAll('[data-s]').forEach((b) => { b.onclick = () => {
      const k = +b.dataset.s, q = G.slots[k];
      if (selId && q.stone) {
        if (q.color !== STONE[selId].color) { this.toast('다른 색으로 바꾸는 건 정착지에서만 할 수 있다'); return; }
        if (!safe) { this.toast('적이 보이는 곳에서는 바꿀 수 없다'); return; }
        this.instant(() => swapStone(sel, k)); this.selBag = -1; this.renderBag(); return;
      }
      this.selBag = -1; this.renderBag();
      if (q.stone) sh.querySelector('.gline').innerHTML = `<b style="color:${COLORS[q.color].css}">${STONE[q.stone].icon} ${STONE[q.stone].name}</b> — ${STONE[q.stone].line}`;
    }; });
    const drop = sh.querySelector('[data-drop]'); if (drop) drop.onclick = () => { const id = G.sbag.splice(sel, 1)[0]; this.selBag = -1; this.toast(`「${STONE[id].name}」을 버렸다`); this.instant(() => {}); this.renderBag(); };
    sh.querySelectorAll('.item').forEach((b) => { b.onclick = () => { sh.classList.add('hidden'); this.useFromBag(b.dataset.k); }; });
  },
  weaponCard() {
    const i = I(G.player.x, G.player.y), id = G.weps.get(i); if (!id) return;
    const W = WPN(id), F = FORMS[W.form];
    const el = $('#info');
    el.innerHTML = `<h3>${F.icon} ${W.name} <small style="color:#9aa2bd">${F.name} ${W.dmg[0]}–${W.dmg[1]} · ${F.injury} · 막타 → ${F.part}</small></h3><div>무엇과 바꿀까? (바꾼 무기는 이 자리에 둔다)</div>
      <div class="row">${G.wpn.map((w, k) => `<button data-k="${k}">${WPN(w).name}와 교체</button>`).join('')}<button data-k="-1">그냥 둔다</button></div>`;
    el.classList.remove('hidden');
    el.onclick = (ev) => { const b = ev.target.closest('button'); if (!b) return; const k = +b.dataset.k; this.hideInfo(); if (k >= 0) { this.instant(() => takeWeapon(k)); Sfx.play('pick'); } };
  },
  useFromBag(k) {
    const def = ITEMS[k];
    if (def.cat === 'throw') { this.enterTarget({ kind: 'item', id: k, name: '🫙 ' + itemName(k), range: 5, color: G.known[k] ? ITEM_COL[k] : 0xd0d0e0, run: (x, y) => useItem(k, x, y) }); return; }
    if (G.player.st.frozen || G.player.st.stun) return;
    act(() => useItem(k));
  },
  /* ---- 정보 카드 ---- */
  showEnemy(e) {
    if (e.ally) { this.info(`<h3>👻 영혼 고블린 <small style="color:#9aa2bd">남은 ${e.life}턴</small></h3><div>보이는 적에게 달려가 공격한다. 부딪히면 자리를 바꾼다.</div>`); return; }
    const B = ENEMY[e.type], st = stIcons(e.st), cat = catOf(e), C = CATS[cat], kd = kindOf(e);
    let extra = '';
    if (e.type === 'mage') extra = ` 주문: ${MAGE[e.elem].icon}`;
    if (e.poison) extra = ' 칼에 독이 묻어 있다 — 맞으면 중독.';
    if (e.armor) extra = ' 갑옷이 두껍다.';
    const inj = [e.st.bleed ? `🩸 출혈 ${e.st.bleed}` : '', e.st.frac ? `🦴 골절 ${e.st.frac} (한 턴씩 쉰다)` : '', e.st.vital ? '✧ 급소 노출 — 다음 찌르기 치명타' : ''].filter(Boolean).join(' · ');
    const drops = ['slash', 'blunt', 'pierce'].map((f) => { const F = FORMS[f], S = STONE[DROPS[kd][F.color]], col = COLORS[F.color].css; return `<div>${F.icon} ${F.name} → ${F.part} <b style="color:${col}">● ${S.icon} ${S.name}</b> <span style="color:#9aa2bd">${S.line}</span></div>`; }).join('');
    this.info(`<h3>${e.name} <small style="color:#9aa2bd">${C.name} · HP ${e.hp}/${e.max} ${st}</small></h3><div>${B.desc}${extra}</div><div class="hint">💡 ${B.tip}</div>
      ${inj ? `<div style="margin-top:4px">${inj}</div>` : ''}
      <div style="margin-top:6px">약점: ${G.weakKnown[cat] ? `<b style="color:#ffe14a">${FORMS[C.weak].icon} ${FORMS[C.weak].name}</b> (피해 1.5배·부상 강화)` : '? — 맞혀 보면 드러난다'}</div>
      <div class="gtxt" style="margin-top:6px">막타 형태에 따라 떨어지는 영혼석${drops}</div>`);
  },
  showTile(x, y) {
    const i = I(x, y); if (!G.seen[i]) return;
    const s = G.surf[i], t = G.tile[i];
    const T = { [S_WATER]: '💧 물웅덩이 — 들어가면 젖는다. 번개가 이어진 물 전체로 흐른다. 냉기를 맞으면 얼음이 된다.', [S_GRASS]: '🌿 풀 — 불이 붙으면 매 턴 옆 풀로 번진다.', [S_OIL]: '🛢 기름 — 불이 닿으면 이어진 기름이 차례로 폭발한다.', [S_ICE]: '🧊 얼음 — 올라서면 같은 방향으로 끝까지 미끄러진다. 불에 녹는다.', [S_ASH]: '재 — 불탄 자리.' };
    let txt = T[s] || (t === T_DOOR ? '🚪 닫힌 문 — 시야를 막는다. 부딪히면 열린다.' : t === T_OPEN ? '🚪 열린 문 — 옆에 서서 ⬇ 옆 버튼으로 닫을 수 있다.' : t === T_STAIRS ? '⬇ 계단 — 올라서서 내려간다.' : t === T_WALL ? '벽 — 밀쳐서 부딪히게 하면 충돌 피해.' : '돌바닥');
    if (G.fire[i]) txt += '<br>🔥 불타는 중';
    if (G.cloud[i]) txt += G.cloud[i] === C_STEAM ? '<br>♨ 증기 — 시야를 막고, 안에 있으면 1 피해 + 젖음' : '<br>🌫 연기 — 시야를 막는다';
    if (G.items.has(i)) txt += `<br>✦ ${itemName(G.items.get(i))}`;
    this.info(`<div>${txt}</div>`);
  },
  help(open) {
    const el = $('#help');
    if (!open) { el.classList.add('hidden'); return; }
    el.innerHTML = `<button class="close">닫기</button><h2>원소 도감</h2><p style="color:#9aa2bd;font-size:13px;margin:4px 0 0">적도 나도 같은 규칙을 받는다.</p>
      <h4>원정 · 정착지</h4><table>
      <tr><td>구역</td><td>구역 4곳 × 3층. 3층의 보스를 잡으면 귀환의 문이 열리고 다음 구역이 열린다</td></tr>
      <tr><td>📜 귀환</td><td>귀환 두루마리로 전리품을 들고 돌아올 수 있지만, 그 구역은 처음부터 다시</td></tr>
      <tr><td>🕯 죽음</td><td>모험가·영혼석·이번 전리품을 잃는다. 정착지와 마을 사람은 남고 새 모험가가 나선다</td></tr>
      <tr><td>🆘 구조</td><td>갇히거나 길 잃은 사람을 부딪혀 풀어 주고, 곁에 둔 채 계단을 내려가면 마을로 온다</td></tr>
      <tr><td>재료</td><td>무기 막타 → 가죽·뼈·심장. 바닥의 약초·광석·기름·얼음을 밟으면 채집</td></tr>
      <tr><td>마을</td><td>💎 제단(다른 색 덮어쓰기) · 🔨 제작(누가 만드느냐로 결과가 다름) · 🚪 준비 · 🔥 휴식</td></tr></table>
      <h4>공격 형태 · 부상 · 약점</h4><table>
      <tr><td>⚔ 베기</td><td>출혈(매 턴 1). 짐승에게 약점. 막타 → 가죽 → 🟢 초록 영혼석</td></tr>
      <tr><td>🔨 타격</td><td>골절: 한 턴씩 쉬고 돌진을 못 한다. 해골에게 약점. 막타 → 뼈 → 🟣 보라</td></tr>
      <tr><td>🗡 찌르기</td><td>급소 표식 → 다음 찌르기 치명타(×2). 갑옷에게 약점. 막타 → 심장 → 🔴 빨강</td></tr>
      <tr><td>약점</td><td>피해 1.5배·부상 강화. 처음 맞혀 본 뒤 머리 위에 표시된다</td></tr>
      <tr><td>◆ 표시</td><td>지금 무기로 한 방에 쓰러뜨릴 수 있다 — 색은 떨어질 영혼석의 색</td></tr></table>
      <h4>영혼석</h4><table>
      <tr><td>🔴 빨강</td><td>내 무기 공격이 맞았을 때 발동</td></tr>
      <tr><td>🟣 보라</td><td>대기할 때 발동 (발동 후 2턴 쉰다)</td></tr>
      <tr><td>🟢 초록</td><td>내가 맞았을 때 발동 (한 턴에 한 번)</td></tr>
      <tr><td>연쇄</td><td>발동이 다른 발동·원소 반응을 부르면 단계가 오른다. 3단계부터 슬로모션</td></tr>
      <tr><td>칸</td><td>6칸은 처음 끼운 색으로 고정. 차면 가방(3개)으로. 같은 색끼리만, 적이 안 보일 때 교체</td></tr>
      <tr><td>원소 막타</td><td>무기가 아닌 불·번개 등으로 쓰러뜨리면 영혼석이 40%만 남고 부위가 무작위</td></tr></table>
      <h4>원소 시너지</h4><table>
      <tr><td>💧 + ⚡</td><td>젖은 대상·물웅덩이에 번개 → 이어진 물과 젖은 대상 전체로 감전(+2 피해, 기절)</td></tr>
      <tr><td>💧 + ❄</td><td>젖은 대상이 얼면 빙결 2턴 → 5턴. 물웅덩이는 얼음이 된다</td></tr>
      <tr><td>🔥 + 🧊</td><td>불이 빙결을 녹이며 증기 폭발(+4) — 증기구름은 시야를 막고 안에 있으면 젖는다</td></tr>
      <tr><td>☠ + 🔥</td><td>중독된 대상에 불 → 독 폭발(7), 주변 8칸에 3 — 옆의 중독된 적도 연쇄 폭발</td></tr>
      <tr><td>🔥 + 💧</td><td>젖은 대상은 불에 절반만 — 증기만 난다. 물에 들어가면 화상이 꺼진다</td></tr>
      <tr><td>🧊 + 물리</td><td>빙결된 적은 공격·충돌 피해 1.5배, 죽으면 산산조각</td></tr></table>
      <h4>지형</h4><table>
      <tr><td>💧 물웅덩이</td><td>들어가면 젖음. 번개가 전체로 흐른다</td></tr>
      <tr><td>🌿 풀</td><td>불이 붙으면 매 턴 옆 풀로 번진다</td></tr>
      <tr><td>🛢 기름</td><td>불이 닿으면 이어진 기름이 차례로 폭발(6)</td></tr>
      <tr><td>🧊 얼음</td><td>올라서면 끝까지 미끄러진다. 밀치기와 궁합</td></tr>
      <tr><td>🧱 벽</td><td>밀쳐서 부딪히면 4 피해 + 기절. 돌진한 멧돼지는 5 + 기절</td></tr>
      <tr><td>좁은 복도</td><td>무리를 한 명씩 상대한다</td></tr>
      <tr><td>🚪 문</td><td>닫힌 문은 시야를 막는다. 열린 문 옆에서 닫을 수 있다</td></tr></table>
      <h4>적의 예고</h4><table>
      <tr><td>붉은 줄무늬 칸</td><td>마법사가 다음 턴에 떨어뜨릴 자리 — 벗어나라</td></tr>
      <tr><td>주황 화살표</td><td>멧돼지의 돌진 경로 — 비켜서면 벽에 박는다</td></tr>
      <tr><td>붉은 점선</td><td>궁수의 조준 — 시야를 끊으면 쏘지 못한다</td></tr>
      <tr><td>💤 / !</td><td>자는 중 / 방금 나를 발견</td></tr></table>
      <h4>조작</h4><table>
      <tr><td>탭</td><td>옆 칸: 이동·공격·문 열기 / 먼 칸: 자동 이동 / 먼 적: 정보</td></tr>
      <tr><td>길게 누르기</td><td>칸·적 정보. 스킬 버튼을 길게 누르면 설명</td></tr>
      <tr><td>스킬·던지기</td><td>버튼 → 칸 탭(미리보기) → 같은 칸 한 번 더 탭</td></tr>
      <tr><td>⏳ 대기</td><td>한 턴 쉰다. 길게 누르면 적이 안 보일 때 회복될 때까지 휴식</td></tr>
      <tr><td>카메라</td><td>두 손가락 회전·핀치 확대, ◢ 탑뷰↔45도, ⌂ 기본 시점</td></tr>
      <tr><td>키보드</td><td>WASD/화살표 + QEZC 대각, Space 대기, 1–5 스킬, I 가방</td></tr></table>`;
    el.classList.remove('hidden');
    el.querySelector('.close').onclick = () => el.classList.add('hidden');
  },
});
