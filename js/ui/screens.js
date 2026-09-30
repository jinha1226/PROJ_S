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
    this.screen(`<h1>횃불과 원소</h1><p style="color:#9fb0ff;margin-top:0">턴제 던전 · 정착지</p>
      <p>던전에서 영혼석과 재료를 모아 정착지를 키운다. 원소와 지형을 이용해 싸운다.</p>
      <p style="font-size:13px">몬스터를 쓰러뜨리면 영혼석 하나가 무작위로 떨어진다. 영혼석마다 스킬이 하나씩 있다.</p>
      <div class="chips"><span>탭: 이동·공격</span><span>먼 칸 탭: 자동 이동</span><span>길게 누르기: 정보</span><span>스킬: 칸 탭 후 한 번 더 탭</span><span>두 손가락: 회전</span><span>핀치: 확대</span></div>
      <button class="bigbtn" id="btn-start">정착지로</button>
      <p style="font-size:12px"><a href="raid-lab.html" style="color:#ffe0a0">레이드 실험실</a></p>
      <p style="font-size:12px;color:#7d86a6;margin-top:14px">진행은 이 브라우저에 저장된다 · <a href="#" id="btn-wipe" style="color:#9aa2bd">처음부터</a></p>`);
    $('#btn-start').onclick = () => { Sfx.init(); this.start(); };
    $('#btn-wipe').onclick = (ev) => { ev.preventDefault(); if (confirm('정착지와 모험가 기록을 모두 지울까?')) { try { localStorage.removeItem('torch-meta-v3'); } catch (_) { /* 없음 */ } resetMeta(); UI.toast('기록을 지웠다.'); } };
  },
  start() {
    const had = (() => { try { return !!localStorage.getItem('torch-meta-v3'); } catch (_) { return false; } })();
    if (!META) loadMeta();
    $('#screen').classList.add('hidden');
    Town.enter({ reason: had ? 'resume' : 'first' });
  },
  toTown() {
    Game.mode = 'town'; this.exitTarget(); this.hideInfo(); this.closeHudOverlay(); this.explore = false; this.logLines = [];
    $('#hud').classList.add('hidden'); $('#townhud').classList.remove('hidden'); $('#floorcard').classList.remove('on'); $('#log').innerHTML = '';
    this.layout();
  },
  toDungeon() { Game.mode = 'dungeon'; $('#sheet').classList.add('hidden'); this.hideInfo(); this.closeHudOverlay(); this.logLines = []; $('#townhud').classList.add('hidden'); $('#hud').classList.remove('hidden'); this.layout(); },
  gameOver() {
    // 사망 요약: 원인과 마지막 다섯 번의 피해
    const by = G.deathBy;
    const last = (G.hurtLog || []).slice(-5).map((q) => `<div>${(q.t ?? 0).toFixed(1)}초 · ${q.who} <b style="color:#ff9aa4">−${q.amt}</b></div>`).join('');
    this.screen(`<h2>쓰러졌다</h2><p>구역 ${G.zone}-${G.zf} · ${G.theme.name}${by ? ` · <b style="color:#ff9aa4">${by.who}에게</b>` : ''} · ${Math.floor(G.clock || 0)}초</p>
      ${last ? `<div class="gtxt" style="text-align:left;margin:6px auto;max-width:300px">${last}</div>` : ''}${this.statsHtml()}<p style="color:#ff9aa4;font-size:13px">이번 원정의 영혼석과 전리품을 잃었다.</p><button class="bigbtn" id="btn-again">정착지로</button>`);
    $('#btn-again').onclick = () => { $('#screen').classList.add('hidden'); returnToTown('death'); };
  },
  victory() { returnToTown('boss'); },
  statsHtml() {
    const s = G.stats, build = G.slots.filter((q) => q.stone).map((q) => `<span style="color:${COLORS[q.color].css}">${STONE[q.stone].icon}</span>`).join(' ') || '없음';
    return `<div class="stats"><div>처치<b>${s.kills}</b></div><div>원소 반응<b>${s.combos}</b></div><div>3단계 이상 연쇄<b>${s.chains}</b></div><div>최고 연쇄<b>${s.best}단계</b></div><div>영혼석<b>${s.stones}</b></div><div>시간<b>${Math.floor(G.clock || 0)}초</b></div></div><p>장착한 영혼석: ${build}</p>`;
  },
});
