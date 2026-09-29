import { META } from '../core/meta.js';
import { G } from '../core/state.js';
import { stoneCd } from '../core/stones.js';
import { CATS } from '../data/enemies.js';
import { AURA, COLORS, LEVEL_XP, STONE } from '../data/stones.js';
import { torchSight } from '../data/torch.js';
import { JOBS } from '../data/town.js';
import { PERKS } from '../data/visitors.js';
import { FORMS } from '../data/weapons.js';
import { Sfx } from '../render/sfx.js';
import { $, UI } from './ui.js';

/* ================= 상태창: 등불지기 · 생명 · 전투 수치 · 상태 이상 · 영혼석 · 이번 원정 ================= */
const ST = [['wet', '💧', '젖음'], ['frozen', '🧊', '빙결'], ['burn', '🔥', '화상'], ['poison', '☠', '중독'], ['bleed', '🩸', '출혈'], ['stun', '💫', '기절'], ['frac', '🦴', '골절'], ['haste', '💨', '가속'], ['immune', '🛡', '해독'], ['fear', '😱', '공포']];
const bar = (label, v, max, col, txt) => `<span>${label}</span><div class="st-bar"><i style="width:${Math.max(0, Math.min(100, (v / Math.max(1, max)) * 100))}%;background:${col}"></i></div><b>${txt ?? `${v}/${max}`}</b>`;

Object.assign(UI, {
  openStatus() {
    if (G.over && !G.player) return;
    Sfx.play('ui');
    const p = G.player, h = META && META.hero, sh = $('#sheet');
    const perk = h && h.perk && PERKS[h.perk], torch = G.torch ?? 100, tmax = G.torchMax ?? 100;
    const st = ST.filter(([k]) => p.st[k] > 0).map(([k, ic, nm]) => `<div>${ic} ${nm} <b>${p.st[k]}턴</b></div>`).join('');
    const auras = Object.entries(G.auras || {}).map(([k, r]) => `<div style="color:#${AURA[k].hex.toString(16).padStart(6, '0')}">◎ ${AURA[k].name} <b>${Math.max(0, r - 1)}라운드</b></div>`).join('');
    const stones = G.slots.map((q) => {
      if (!q.stone) return '<div class="st-stone empty">·<small>빈 칸</small></div>';
      const S = STONE[q.stone], C = COLORS[S.color];
      return `<div class="st-stone" style="--c:${C.css}">${S.icon}<small style="color:${C.css}">${S.name}</small><small>${q.cd > 0 ? `${q.cd}턴 남음` : '준비됨'} · 쿨 ${stoneCd(q.stone)}</small></div>`;
    }).join('');
    const bag = G.sbag.map((id) => `${STONE[id].icon} ${STONE[id].name}`).join(' · ') || '없음';
    const weak = Object.keys(CATS).map((c) => `${CATS[c].name}${G.weakKnown && G.weakKnown[c] ? `: ${FORMS[CATS[c].weak].icon} ${FORMS[CATS[c].weak].name}` : ': ?'}`).join(' · ');
    const s = G.stats || {};
    sh.innerHTML = `<h3>📜 상태 <button class="close">닫기</button></h3>
      <div class="st-head"><b>${p.name || (h && h.name) || '등불지기'}</b><span style="color:#9aa2bd">레벨 ${G.level || 1}${(G.level || 1) < 6 ? ` · 경험 ${G.xp || 0}/${LEVEL_XP[G.level || 1]}` : ''} · ${h ? `${h.gen}대 등불지기` : ''}${h && h.job ? ` · 전 ${JOBS[h.job].name}` : ''} · 구역 ${G.zone}-${G.zf}</span></div>
      ${perk ? `<div class="gtxt" style="color:#ffe38a">✦ ${perk.name}: ${perk.desc}</div>` : ''}
      <div class="st-bars">${bar('HP', p.hp, p.max, '#ff5a6a')}${bar('보호막', p.shield || 0, 10, '#9fd8ff', String(p.shield || 0))}${bar('횃불', torch, tmax, '#ffb040', `${Number.isInteger(torch) ? torch : torch.toFixed(1)} · 시야 ${torchSight(torch)}칸`)}</div>
      <div class="sec">상태 이상 · 지속 효과</div><div class="st-list">${st + auras || '<div style="color:#9aa2bd">없음</div>'}</div>
      <div class="sec">영혼석 스킬</div><div class="st-grid">${stones}</div>
      <div class="gtxt" style="margin-top:4px">영혼석 가방 ${G.sbag.length}/${G.sbagMax || 3}: ${bag}</div>
      <div class="sec">전투 수치 <small>누르면 출처</small></div>${this.statsRows()}
      <div class="sec">알아낸 약점</div><div class="gtxt">${weak}</div>
      <div class="sec">이번 원정</div><div class="gtxt">처치 ${s.kills || 0} · 턴 ${s.turns || 0} · 원소 반응 ${s.combos || 0} · 최고 연쇄 ${s.best || 0}단계 · 영혼석 ${s.stones || 0}</div>`;
    sh.classList.add('tall'); sh.classList.remove('hidden');
    sh.querySelector('.close').onclick = () => { sh.classList.add('hidden'); sh.classList.remove('tall'); };
  },
});
