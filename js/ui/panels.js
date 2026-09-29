import * as THREE from 'three';
import { visibleFoes } from '../core/fov.js';
import { itemName, useItem } from '../core/items.js';
import { G, Game, I } from '../core/state.js';
import { swapStone } from '../core/stones.js';
import { CATS, DROPS, ENEMY, MAGE, catOf, kindOf, monRes } from '../data/enemies.js';
import { BAG_MAX, ELEM } from '../data/gear.js';
import { CAT_ICON, ITEMS, ITEM_COL } from '../data/items.js';
import { COLORS, STONE } from '../data/stones.js';
import { C_STEAM, S_ASH, S_GRASS, S_ICE, S_OIL, S_WATER, T_DOOR, T_OPEN, T_STAIRS, T_WALL } from '../data/terrain.js';
import { HIDDEN } from '../data/visitors.js';
import { FORMS } from '../data/weapons.js';
import { Anim, act } from '../flow.js';
import { stIcons } from '../render/entity-view.js';
import { jo } from '../util/text.js';
import { $, UI } from './ui.js';

Object.assign(UI, {
  /* ---- 가방 = 장비 창(서브탭: 장비 · 소모품 · 영혼석) ---- */
  openBag(tab) { if (G.over || Anim.active) return; if (tab) this.invTab = tab; this.openInv(); },
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
    return `${detail}<div class="sec">소모품 ${inv.reduce((a, q) => a + q.n, 0)} <small>? 아직 정체를 모른다</small></div><div class="bggrid">${grid}</div>`;
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
        ${same.length ? (safe ? '' : '<div style="color:#ff9aa4">적이 보이면 교체할 수 없다.</div>') : `<div style="color:#9aa2bd">같은 색 칸 없음 · 다른 색은 정착지 제단에서 교체</div>`}</div>
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
      ${B.speed || B.danger ? `<div style="margin-top:4px">${B.speed === 'fast' ? '<b style="color:#ff9a6a">» 빠르다. 도망칠 수 없다.</b> ' : B.speed === 'slow' ? '<b style="color:#9ab8ff">« 느리다. 걸어서 떼어 놓을 수 있다.</b> ' : ''}${B.danger ? `⚠ ${B.danger}` : ''}</div>` : ''}
      ${inj ? `<div style="margin-top:4px">${inj}</div>` : ''}
      <div style="margin-top:6px">약점: ${G.weakKnown[cat] ? `<b style="color:#ffe14a">${FORMS[C.weak].icon} ${FORMS[C.weak].name}</b> · 피해 1.5배, 부상이 깊어진다` : '? · 맞혀 보면 드러난다'}</div>
      <div style="margin-top:4px;font-size:12.5px">저항: ${['fire', 'frost', 'bolt', 'poison'].map((el) => { const r = monRes(e, el); return `${ELEM[el].name} <b style="color:${r > 0 ? '#9fd8ff' : r < 0 ? '#ff9a9a' : '#9aa2bd'}">${r > 0 ? '●'.repeat(r) : r < 0 ? '▼'.repeat(-r) : '—'}</b>`; }).join(' · ')}</div>
      <div class="gtxt" style="margin-top:6px">떨어지는 영혼석 <small style="color:#9aa2bd">셋 중 하나가 무작위로</small>${drops}</div>`);
  },
  showTile(x, y) {
    const i = I(x, y); if (!G.seen[i]) return;
    const s = G.surf[i], t = G.tile[i], bk = G.block && G.block.get(i);
    if (bk) { const H = HIDDEN[bk], who = Object.values(STONE).filter((q) => q.elem === H.skill && q.tgt.t !== 'around' && q.tgt.t !== 'sight').map((q) => `${q.icon} ${q.name}`).join(' · '); this.info(`<div><b>${H.name}</b><br>${H.hint}.<br><small>이 칸에 ${who} 스킬을 쓰면 열린다.</small></div>`); return; }
    const T = { [S_WATER]: '💧 물웅덩이<br>들어가면 젖는다. 번개가 이어진 물을 타고 흐르고, 냉기를 맞으면 언다.', [S_GRASS]: '🌿 풀<br>불이 붙으면 매 턴 옆 풀로 번진다.', [S_OIL]: '🛢 기름<br>불이 닿으면 이어진 기름이 차례로 터진다.', [S_ICE]: '🧊 얼음<br>올라서면 같은 방향으로 끝까지 미끄러진다. 불에 녹는다.', [S_ASH]: '재<br>불탄 자리.' };
    let txt = T[s] || (t === T_DOOR ? '🚪 닫힌 문<br>시야를 막는다. 부딪히면 열린다.' : t === T_OPEN ? '🚪 열린 문<br>옆에 서면 닫을 수 있다.' : t === T_STAIRS ? '⬇ 계단<br>올라서면 내려갈 수 있다.' : t === T_WALL ? '벽<br>적을 밀쳐 부딪히게 하면 피해를 준다.' : '돌바닥');
    if (G.fire[i]) txt += '<br>🔥 불타는 중';
    if (G.cloud[i]) txt += G.cloud[i] === C_STEAM ? '<br>♨ 증기: 시야를 막는다. 안에 있으면 피해 1을 받고 젖는다.' : '<br>🌫 연기: 시야를 막는다.';
    if (G.items.has(i)) txt += `<br>✦ ${itemName(G.items.get(i))}`;
    this.info(`<div>${txt}</div>`);
  },
  help(open) {
    const el = $('#help');
    if (!open) { el.classList.add('hidden'); return; }
    el.innerHTML = `<button class="close">닫기</button><h2>원소 도감</h2><p style="color:#9aa2bd;font-size:13px;margin:4px 0 0">적도 나도 같은 규칙을 받는다.</p>
      <h4>원정 · 정착지</h4><table>
      <tr><td>구역</td><td>구역은 네 곳, 구역마다 5층. 5층의 보스를 잡으면 귀환의 문과 다음 구역이 열린다.</td></tr>
      <tr><td>📜 귀환</td><td>귀환 두루마리로 전리품을 들고 돌아온다. 그 구역은 처음부터 다시 해야 한다.</td></tr>
      <tr><td>🕯 죽음</td><td>모험가와 영혼석, 이번 전리품을 잃는다. 정착지와 마을 사람은 남고 새 모험가가 나선다.</td></tr>
      <tr><td>🆘 구조</td><td>갇히거나 길 잃은 사람에게 부딪히면 풀려난다. 곁에 둔 채 계단을 내려가면 마을로 온다.</td></tr>
      <tr><td>재료</td><td>무기로 쓰러뜨리면 가죽·뼈·심장 중 하나를 얻는다. 바닥의 약초·광석·기름·얼음은 밟으면 줍는다.</td></tr>
      <tr><td>마을</td><td>💎 제단: 다른 색으로 덮어쓰기 · 🔨 제작: 만드는 사람에 따라 결과가 다르다 · 🚪 준비 · 🔥 휴식</td></tr></table>
      <h4>장비</h4><table>
      <tr><td>🛡 장비 창</td><td>무기·보조손·머리·몸통·장갑·신발·목걸이·반지 두 개. 장비 가방 20칸은 소모품·영혼석과 따로다.</td></tr>
      <tr><td>등급</td><td>일반은 흰색. 마법은 파랑, 옵션 1~2개. 희귀는 노랑, 옵션 3~4개. 전설은 주황, 고유 효과가 있다. 희귀와 전설은 정체를 모른 채 얻는다.</td></tr>
      <tr><td>미확인</td><td>무기는 10번 맞히면, 방어구는 30턴 입으면 드러난다. 확인 두루마리는 바로 알려 준다.</td></tr>
      <tr><td>비교</td><td>가방의 장비를 누르면 입은 것과 나란히 보인다. 오르는 수치는 초록, 내리는 수치는 빨강.</td></tr>
      <tr><td>전투 중</td><td>장착과 해제에 한 턴씩 든다.</td></tr>
      <tr><td>기본</td><td>기본 회피 10%. 한계는 방어 6, 회피 40%, 막기 30%, 최대 HP 20 추가, 저항 50%.</td></tr>
      <tr><td>얻는 곳</td><td>적이 12% 확률로 떨군다. 갑옷 고블린과 멧돼지는 25%. 층마다 상자 1~2개, 보스는 2개. 정착지 대장간에서도 만든다.</td></tr>
      <tr><td>죽으면</td><td>입은 장비와 가방은 잃는다. 정착지 창고의 장비는 남는다.</td></tr></table>
      <h4>공격 형태 · 부상 · 약점</h4><table>
      <tr><td>⚔ 베기</td><td>출혈, 매 턴 피해 1. 짐승의 약점이다.</td></tr>
      <tr><td>🔨 타격</td><td>골절, 한 턴씩 쉬고 돌진하지 못한다. 해골의 약점이다.</td></tr>
      <tr><td>🗡 찌르기</td><td>급소 표식을 남기고, 다음 찌르기가 두 배 치명타가 된다. 갑옷 입은 적의 약점이다.</td></tr>
      <tr><td>약점</td><td>피해 1.5배, 부상이 깊어진다. 처음 맞혀 본 뒤 머리 위에 표시된다.</td></tr>
      <tr><td>◆ 표시</td><td>지금 무기로 한 방에 쓰러뜨릴 수 있다. 색은 떨어질 영혼석의 색이다.</td></tr></table>
      <h4>영혼석</h4><table>
      <tr><td>스킬</td><td>영혼석 하나에 스킬 하나. 아래 6칸이 스킬 버튼이다. 쓰면 한 번 행동하고 쿨타임이 찬다.</td></tr>
      <tr><td>쿨타임</td><td>내 턴이 끝날 때마다 한 턴씩 줄어든다. 전투가 끝나도 그대로 이어진다.</td></tr>
      <tr><td>🔴 빨강</td><td>무기나 스킬이 적중하면 한 턴 더 줄어든다.</td></tr>
      <tr><td>🟣 보라</td><td>대기하면 한 턴 더 줄어든다.</td></tr>
      <tr><td>🟢 초록</td><td>적에게 맞으면 한 턴 더 줄어든다.</td></tr>
      <tr><td>한 라운드</td><td>색에 따른 감소는 영혼석마다 한 라운드에 한 번이다. 라운드는 내 턴과 적 턴을 합친 것. 방금 쓴 스킬은 빠진다.</td></tr>
      <tr><td>연쇄</td><td>물벼락 뒤 번개처럼 스킬이 원소 반응을 부르면 단계가 오른다. 3단계부터 화면이 느려진다.</td></tr>
      <tr><td>칸</td><td>칸의 색은 처음 끼운 영혼석으로 정해진다. 칸이 차면 영혼석 가방에 세 개까지 둔다. 같은 색끼리, 적이 안 보일 때만 바꾼다.</td></tr>
      <tr><td>드롭</td><td>몬스터마다 빨강·보라·초록 영혼석 중 하나가 무작위로 떨어진다. 무기로 쓰러뜨리면 반드시, 불이나 번개 같은 원소로 쓰러뜨리면 40% 확률이다.</td></tr></table>
      <h4>원소 시너지</h4><table>
      <tr><td>💧 + ⚡</td><td>젖은 대상이나 물웅덩이에 번개가 닿으면 이어진 물과 젖은 대상이 모두 감전된다. 피해 2가 더해지고 기절한다.</td></tr>
      <tr><td>💧 + ❄</td><td>젖은 대상이 얼면 빙결이 2턴에서 5턴으로 늘어난다. 물웅덩이는 얼음이 된다.</td></tr>
      <tr><td>🔥 + 🧊</td><td>불이 빙결을 녹이면 증기가 터져 피해 4를 더 준다. 증기구름은 시야를 막고, 안에 있으면 젖는다.</td></tr>
      <tr><td>☠ + 🔥</td><td>중독된 대상에 불이 닿으면 독이 터진다. 피해 7, 주변 8칸에 피해 3. 옆의 중독된 적도 이어서 터진다.</td></tr>
      <tr><td>🔥 + 💧</td><td>젖은 대상은 불 피해를 절반만 받고 증기만 난다. 물에 들어가면 화상이 꺼진다.</td></tr>
      <tr><td>🧊 + 물리</td><td>빙결된 적은 공격과 충돌 피해를 1.5배 받고, 죽으면 산산이 부서진다.</td></tr></table>
      <h4>지형</h4><table>
      <tr><td>💧 물웅덩이</td><td>들어가면 젖는다. 번개가 물 전체로 흐른다.</td></tr>
      <tr><td>🌿 풀</td><td>불이 붙으면 매 턴 옆 풀로 번진다.</td></tr>
      <tr><td>🛢 기름</td><td>불이 닿으면 이어진 기름이 차례로 터진다. 피해 6.</td></tr>
      <tr><td>🧊 얼음</td><td>올라서면 끝까지 미끄러진다. 밀치기와 잘 맞는다.</td></tr>
      <tr><td>🧱 벽</td><td>밀쳐서 부딪히면 피해 4와 기절. 돌진하던 멧돼지는 피해 5와 기절.</td></tr>
      <tr><td>좁은 복도</td><td>무리를 하나씩 상대한다.</td></tr>
      <tr><td>🚪 문</td><td>닫힌 문은 시야를 막는다. 열린 문은 옆에서 닫을 수 있다.</td></tr></table>
      <h4>적의 예고</h4><table>
      <tr><td>붉은 줄무늬 칸</td><td>마법사가 다음 턴에 주문을 떨어뜨릴 자리. 벗어나면 맞지 않는다.</td></tr>
      <tr><td>주황 화살표</td><td>멧돼지의 돌진 경로. 비켜서면 멧돼지가 벽에 박는다.</td></tr>
      <tr><td>붉은 점선</td><td>궁수가 조준하고 있다. 시야를 끊으면 쏘지 못한다.</td></tr>
      <tr><td>💤 · !</td><td>자는 중 · 방금 나를 발견했다</td></tr></table>
      <h4>조작</h4><table>
      <tr><td>탭</td><td>옆 칸은 이동·공격·문 열기. 먼 칸은 자동 이동. 먼 적은 정보.</td></tr>
      <tr><td>길게 누르기</td><td>칸과 적의 정보를 본다. 영혼석 칸은 설명과 쿨타임, 색 감소 조건을 보여 준다.</td></tr>
      <tr><td>스킬·던지기</td><td>영혼석 칸을 누르고 대상 칸을 탭하면 미리보기가 뜬다. 같은 칸을 한 번 더 탭하면 발동한다. 자기 대상 스킬은 영혼석 칸을 한 번 더 누른다.</td></tr>
      <tr><td>⏳ 대기</td><td>한 턴 기다린다. 길게 누르면 다 나을 때까지 쉰다. 적이 보이면 쉴 수 없다.</td></tr>
      <tr><td>카메라</td><td>두 손가락으로 회전, 핀치로 확대. ◢ 탑뷰와 45도 전환 · ⌂ 기본 시점</td></tr>
      <tr><td>키보드</td><td>WASD·화살표 이동, QEZC 대각선, Space 대기, 1~6 영혼석 스킬, I 가방</td></tr></table>`;
    el.classList.remove('hidden');
    el.querySelector('.close').onclick = () => el.classList.add('hidden');
  },
});
