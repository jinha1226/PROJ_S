import { META, loadMeta, resetMeta } from '../core/meta.js';
import { G, Game } from '../core/state.js';
import { COLORS, STONE } from '../data/stones.js';
import { returnToTown } from '../flow.js';
import { Sfx } from '../render/sfx.js';
import { Town } from '../town/town.js';
import { $, UI } from './ui.js';

Object.assign(UI, {
  /* ---- 큰 화면 ---- */
  screen(html) { const s = $('#screen'); s.innerHTML = `<div class="box">${html}</div>`; s.classList.remove('hidden'); },
  title() {
    this.screen(`<h1>횃불과 원소</h1><p style="color:#c8a878;margin-top:0;font-family:var(--serif)">세상에 남은 마지막 모닥불</p>
      <p>어둠은 잊음이다. 사람들은 서로의 이름을 잊고 흩어졌다.<br>남은 불은 작은 정착지의 모닥불 하나 — 그 불은 <b>사람으로</b> 탄다.</p>
      <p style="font-size:13px">횃불을 들고 내려가 원소와 지형으로 어둠의 주인을 쓰러뜨려라.<br>되찾은 등불 조각을 모닥불에 넣으면, 흩어진 이들이 불빛을 따라 찾아온다.</p>
      <div class="chips"><span>탭 — 이동·공격</span><span>먼 칸 탭 — 자동 이동</span><span>길게 누르기 — 정보</span><span>스킬 → 칸 탭 → 한 번 더 탭</span><span>두 손가락 — 회전</span><span>핀치 — 확대</span></div>
      <button class="bigbtn" id="btn-start">정착지로</button>
      <p style="font-size:12px;color:#7d86a6;margin-top:14px">진행은 이 브라우저에 저장된다 · <a href="#" id="btn-wipe" style="color:#9aa2bd">처음부터</a></p>`);
    $('#btn-start').onclick = () => { Sfx.init(); this.start(); };
    $('#btn-wipe').onclick = (ev) => { ev.preventDefault(); if (confirm('정착지와 모험가 기록을 모두 지울까?')) { try { localStorage.removeItem('torch-meta-v3'); } catch (_) { /* 없음 */ } resetMeta(); UI.toast('기록을 지웠다'); } };
  },
  start() {
    const had = (() => { try { return !!localStorage.getItem('torch-meta-v3'); } catch (_) { return false; } })();
    if (!META) loadMeta();
    $('#screen').classList.add('hidden');
    Town.enter({ reason: had ? 'resume' : 'first' });
  },
  toTown() {
    Game.mode = 'town'; this.exitTarget(); this.hideInfo();
    $('#hud').classList.add('hidden'); $('#townhud').classList.remove('hidden'); $('#floorcard').classList.remove('on'); $('#log').innerHTML = '';
    this.layout();
  },
  toDungeon() { Game.mode = 'dungeon'; $('#sheet').classList.add('hidden'); this.hideInfo(); $('#townhud').classList.add('hidden'); $('#hud').classList.remove('hidden'); this.layout(); },
  gameOver() {
    this.screen(`<h2>쓰러졌다</h2><p>구역 ${G.zone}-${G.zf} — ${G.theme.name}</p>${this.statsHtml()}<p style="color:#ff9aa4;font-size:13px">영혼석과 이번 원정의 전리품을 잃었다. 정착지와 마을 사람들은 남는다.</p><button class="bigbtn" id="btn-again">정착지로 — 새 모험가가 나선다</button>`);
    $('#btn-again').onclick = () => { $('#screen').classList.add('hidden'); returnToTown('death'); };
  },
  victory() { returnToTown('boss'); },
  statsHtml() {
    const s = G.stats, build = G.slots.filter((q) => q.stone).map((q) => `<span style="color:${COLORS[q.color].css}">${STONE[q.stone].icon}</span>`).join(' ') || '없음';
    return `<div class="stats"><div>처치<b>${s.kills}</b></div><div>원소 반응<b>${s.combos}</b></div><div>3단계+ 연쇄<b>${s.chains}</b></div><div>최고 연쇄<b>${s.best}단계</b></div><div>영혼석<b>${s.stones}</b></div><div>턴<b>${s.turns}</b></div></div><p>이번 빌드: ${build}</p><p style="font-size:12.5px;color:#9aa2bd">다음 판엔 다른 색 조합을 노려 보자 — 막타 무기가 색을 정한다.</p>`;
  },
});
