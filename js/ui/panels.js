import * as THREE from 'three';
import { visibleFoes } from '../core/fov.js';
import { itemName, useItem } from '../core/items.js';
import { G, Game, I } from '../core/state.js';
import { swapStone } from '../core/stones.js';
import { CATS, DROPS, ENEMY, MAGE, catOf, kindOf, monRes } from '../data/enemies.js';
import { ELEM } from '../data/gear.js';
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
    const sel = inv.find((q) => q.k === this.itemSel), cells = Math.max(10, Math.ceil(inv.length / 5) * 5);
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
    return `${detail}<div class="sec">소모품 ${inv.reduce((a, q) => a + q.n, 0)} <small>? = 아직 정체를 모른다</small></div>${inv.length ? `<div class="bggrid">${grid}</div>` : '<p style="color:#9aa2bd;font-size:13px">비어 있다. 바닥의 반짝이는 물건을 밟으면 줍는다.</p>'}`;
  },
  bindItems(sh) {
    sh.querySelectorAll('[data-k]').forEach((b) => { b.onclick = () => { this.itemSel = this.itemSel === b.dataset.k ? null : b.dataset.k; this.renderInv(); }; });
    const use = sh.querySelector('[data-use]'); if (use) use.onclick = () => { const k = use.dataset.use; this.itemSel = null; sh.classList.add('hidden'); sh.classList.remove('tall'); this.useFromBag(k); };
    const back = sh.querySelector('[data-iback]'); if (back) back.onclick = () => { this.itemSel = null; this.renderInv(); };
  },
  /** 영혼석 탭: 저장 중인 영혼석(가방)만 칸으로. 누르면 설명 · 같은 색 칸과 바꾸기 · 버리기 */
  stonesHtml() {
    const safe = !visibleFoes().some((e) => e.awake), max = G.sbagMax || 3, sel = this.selBag ?? -1, selId = sel >= 0 ? G.sbag[sel] : null;
    const grid = Array.from({ length: max }, (_, k) => { const id = G.sbag[k]; if (!id) return '<div class="bgc empty"></div>'; const d = STONE[id], C = COLORS[d.color]; return `<button class="bgc ${k === sel ? 'sel' : ''}" style="--c:${C.css}" data-b="${k}">${d.icon}<small>${d.name}</small></button>`; }).join('');
    let detail = '';
    if (selId) {
      const d = STONE[selId], C = COLORS[d.color], same = G.slots.map((q, k) => [q, k]).filter(([q, k]) => q.stone && q.color === d.color && k < (G.level || 6));
      const swaps = same.map(([q, k]) => `<button data-sw="${k}" ${safe ? '' : 'disabled'}>${STONE[q.stone].icon} ${jo(STONE[q.stone].name, '과와')} 바꾸기</button>`).join('');
      detail = `<div class="gdetail"><div class="gcard" style="--c:${C.css}"><div class="gct"><small>${C.name} 영혼석 · 쿨타임 ${d.cd}</small><b style="color:${C.css}">${d.icon} ${d.name}</b></div><div>${d.line}</div>
        ${same.length ? (safe ? '' : '<div style="color:#ff9aa4">적이 보이는 곳에서는 바꿀 수 없다.</div>') : `<div style="color:#9aa2bd">끼울 수 있는 ${C.name} 칸이 없다. 다른 색으로 바꾸는 건 정착지 제단에서.</div>`}</div>
        <div class="row">${swaps}<button data-drop="1">버리기</button><button data-sback="1">닫기</button></div></div>`;
    }
    return `${detail}<div class="sec">영혼석 가방 ${G.sbag.length}/${max} <small>장착한 영혼석은 화면 아래 영혼석 칸에 있다. 같은 색 칸하고만 바꾼다.</small></div><div class="bggrid">${grid}</div>`;
  },
  bindStones(sh) {
    const sel = this.selBag ?? -1;
    sh.querySelectorAll('[data-b]').forEach((b) => { b.onclick = () => { const k = +b.dataset.b; this.selBag = this.selBag !== k ? k : -1; this.renderInv(); }; });
    sh.querySelectorAll('[data-sw]').forEach((b) => { b.onclick = () => { this.instant(() => swapStone(sel, +b.dataset.sw)); this.selBag = -1; this.renderInv(); }; });
    const back = sh.querySelector('[data-sback]'); if (back) back.onclick = () => { this.selBag = -1; this.renderInv(); };
    const drop = sh.querySelector('[data-drop]'); if (drop) drop.onclick = () => { const id = G.sbag.splice(sel, 1)[0]; this.selBag = -1; this.toast(`「${STONE[id].name}」을 버렸다`); this.instant(() => {}); this.renderInv(); };
  },
  useFromBag(k) {
    const def = ITEMS[k];
    if (def.target) { this.invTab = 'gear'; this.openInv(); this.toast(`${def.name}: 장비를 골라 ${k === 'ident' ? '[확인]' : '[강화]'}`); return; }
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
    if (e.poison) extra = ' 칼에 독이 묻어 있다 — 맞으면 중독.';
    if (e.armor) extra = ' 갑옷이 두껍다.';
    const inj = [e.st.bleed ? `🩸 출혈 ${e.st.bleed}` : '', e.st.frac ? `🦴 골절 ${e.st.frac} (한 턴씩 쉰다)` : '', e.st.vital ? '✧ 급소 노출 — 다음 찌르기 치명타' : ''].filter(Boolean).join(' · ');
    const drops = ['red', 'purple', 'green'].map((c) => { const S = STONE[DROPS[kd][c]], col = COLORS[c].css; return `<div><b style="color:${col}">● ${S.icon} ${S.name}</b> <span style="color:#9aa2bd">${S.line}</span></div>`; }).join('');
    this.info(`<h3>${e.name} <small style="color:#9aa2bd">${C.name} · HP ${e.hp}/${e.max} ${st}</small></h3><div>${B.desc}${extra}</div><div class="hint">💡 ${B.tip}</div>
      ${B.speed || B.danger ? `<div style="margin-top:4px">${B.speed === 'fast' ? '<b style="color:#ff9a6a">» 빠르다. 도망칠 수 없다.</b> ' : B.speed === 'slow' ? '<b style="color:#9ab8ff">« 느리다. 걸어서 떼어 놓을 수 있다.</b> ' : ''}${B.danger ? `⚠ ${B.danger}` : ''}</div>` : ''}
      ${inj ? `<div style="margin-top:4px">${inj}</div>` : ''}
      <div style="margin-top:6px">약점: ${G.weakKnown[cat] ? `<b style="color:#ffe14a">${FORMS[C.weak].icon} ${FORMS[C.weak].name}</b> (피해 1.5배·부상 강화)` : '? — 맞혀 보면 드러난다'}</div>
      <div style="margin-top:4px;font-size:12.5px">저항: ${['fire', 'frost', 'bolt', 'poison'].map((el) => { const r = monRes(e, el); return `${ELEM[el].name} <b style="color:${r > 0 ? '#9fd8ff' : r < 0 ? '#ff9a9a' : '#9aa2bd'}">${r > 0 ? '●'.repeat(r) : r < 0 ? '▼'.repeat(-r) : '—'}</b>`; }).join(' · ')}</div>
      <div class="gtxt" style="margin-top:6px">떨어지는 영혼석 <small style="color:#9aa2bd">셋 중 하나 무작위(각 1/3)</small>${drops}</div>`);
  },
  showTile(x, y) {
    const i = I(x, y); if (!G.seen[i]) return;
    const s = G.surf[i], t = G.tile[i], bk = G.block && G.block.get(i);
    if (bk) { const H = HIDDEN[bk], who = Object.values(STONE).filter((q) => q.elem === H.skill && q.tgt.t !== 'around' && q.tgt.t !== 'sight').map((q) => `${q.icon} ${q.name}`).join(' · '); this.info(`<div><b>${H.name}</b> — ${H.hint}.<br><small>영혼석 스킬 ${who}을(를) 이 칸에 쓰면 열린다</small></div>`); return; }
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
      <tr><td>구역</td><td>구역 4곳 × 5층. 5층의 보스를 잡으면 귀환의 문이 열리고 다음 구역이 열린다</td></tr>
      <tr><td>📜 귀환</td><td>귀환 두루마리로 전리품을 들고 돌아올 수 있지만, 그 구역은 처음부터 다시</td></tr>
      <tr><td>🕯 죽음</td><td>모험가·영혼석·이번 전리품을 잃는다. 정착지와 마을 사람은 남고 새 모험가가 나선다</td></tr>
      <tr><td>🆘 구조</td><td>갇히거나 길 잃은 사람을 부딪혀 풀어 주고, 곁에 둔 채 계단을 내려가면 마을로 온다</td></tr>
      <tr><td>재료</td><td>무기로 쓰러뜨리면 가죽·뼈·심장 중 하나. 바닥의 약초·광석·기름·얼음을 밟으면 채집</td></tr>
      <tr><td>마을</td><td>💎 제단(다른 색 덮어쓰기) · 🔨 제작(누가 만드느냐로 결과가 다름) · 🚪 준비 · 🔥 휴식</td></tr></table>
      <h4>장비</h4><table>
      <tr><td>🛡 장비 창</td><td>무기·보조·머리·몸통·장갑·신발·목걸이·반지 2. 가방 20칸은 소모품·영혼석과 따로</td></tr>
      <tr><td>등급</td><td>일반(흰) · 마법(파랑, 옵션 1~2) · 희귀(노랑, 3~4, 미확인) · 전설(주황, 고유 효과, 미확인)</td></tr>
      <tr><td>미확인</td><td>입으면 옵션이 하나씩, 한 층 내려가면 전부 드러난다. 확인 두루마리는 즉시</td></tr>
      <tr><td>비교</td><td>가방 장비를 누르면 입은 것과 나란히 — 바뀌는 수치가 초록(오름)·빨강(내림)</td></tr>
      <tr><td>전투 중</td><td>장착·해제마다 한 턴. 무기↔보조(두 번째 무기) 맞바꾸기는 턴 없음</td></tr>
      <tr><td>기본</td><td>회피 10%. 상한: 방어 6 · 회피 40% · 막기 30% · 최대 HP +20 · 저항 50%</td></tr>
      <tr><td>얻는 곳</td><td>적 12%(갑옷 고블린·멧돼지 25%), 층마다 상자 1~2, 보스 2개. 정착지 대장간 제작</td></tr>
      <tr><td>죽으면</td><td>입은 장비·가방은 잃고, 정착지 창고의 장비는 남는다</td></tr></table>
      <h4>공격 형태 · 부상 · 약점</h4><table>
      <tr><td>⚔ 베기</td><td>출혈(매 턴 1). 짐승에게 약점</td></tr>
      <tr><td>🔨 타격</td><td>골절: 한 턴씩 쉬고 돌진을 못 한다. 해골에게 약점</td></tr>
      <tr><td>🗡 찌르기</td><td>급소 표식 → 다음 찌르기 치명타(×2). 갑옷에게 약점</td></tr>
      <tr><td>약점</td><td>피해 1.5배·부상 강화. 처음 맞혀 본 뒤 머리 위에 표시된다</td></tr>
      <tr><td>◆ 표시</td><td>지금 무기로 한 방에 쓰러뜨릴 수 있다 — 색은 떨어질 영혼석의 색</td></tr></table>
      <h4>영혼석</h4><table>
      <tr><td>스킬</td><td>영혼석 하나 = 액티브 스킬 하나. 아래 6칸이 스킬 버튼. 쓰면 행동 한 번, 쿨타임이 찬다</td></tr>
      <tr><td>쿨타임</td><td>내 턴이 끝날 때마다 1 준다. 전투 중에만 흐르고, 보이는 깨어 있는 적이 없으면 모두 준비된다</td></tr>
      <tr><td>🔴 빨강</td><td>내 공격(무기·스킬)이 적중하면 1 더 — 몰아친다</td></tr>
      <tr><td>🟣 보라</td><td>대기하면 1 더 — 기다렸다 터뜨린다</td></tr>
      <tr><td>🟢 초록</td><td>적에게 맞으면 1 더 — 버티다 되갚는다</td></tr>
      <tr><td>한 라운드</td><td>영혼석마다 색 감소는 한 라운드(내 턴 + 적 턴)에 한 번, 방금 쓴 스킬은 제외</td></tr>
      <tr><td>연쇄</td><td>스킬이 원소 반응을 부르면 단계가 오른다(물벼락 → 번개). 3단계부터 슬로모션</td></tr>
      <tr><td>칸</td><td>6칸은 처음 끼운 색으로 고정. 차면 가방(3개)으로. 같은 색끼리만, 적이 안 보일 때 교체</td></tr>
      <tr><td>드롭</td><td>몬스터마다 영혼석 셋(🔴🟣🟢) 중 하나가 무작위. 무기로 쓰러뜨리면 확실히, 불·번개 등으로 쓰러뜨리면 40%</td></tr></table>
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
      <tr><td>길게 누르기</td><td>칸·적 정보. 영혼석 칸을 길게 누르면 설명·쿨타임·색 감소 조건</td></tr>
      <tr><td>스킬·던지기</td><td>영혼석 칸 → 칸 탭(미리보기) → 같은 칸 한 번 더 탭. 자기 대상 스킬은 칸을 한 번 더</td></tr>
      <tr><td>⏳ 대기</td><td>한 턴 쉰다. 길게 누르면 적이 안 보일 때 회복될 때까지 휴식</td></tr>
      <tr><td>카메라</td><td>두 손가락 회전·핀치 확대, ◢ 탑뷰↔45도, ⌂ 기본 시점</td></tr>
      <tr><td>키보드</td><td>WASD/화살표 + QEZC 대각, Space 대기, 1–6 영혼석 스킬, I 가방</td></tr></table>`;
    el.classList.remove('hidden');
    el.querySelector('.close').onclick = () => el.classList.add('hidden');
  },
});
