import { colony, have, priOf, target } from '../core/colony.js';
import { addOrder, orderCost, orderWhy, roomOfKind, stationWorker, tierOf } from '../core/crafting.js';
import { gearCss, gearName } from '../core/gear.js';
import { META, saveMeta } from '../core/meta.js';
import { addStock, stockOf } from '../core/settlement.js';
import { ROOMS } from '../data/build.js';
import { CRAFT, CRAFT_BY_ID, CRYSTALS, STATIONS, WORKS, WORK_IDS } from '../data/colony.js';
import { hasQuality, isWeapon, plusMax } from '../data/gear.js';
import { MATS } from '../data/items.js';
import { JOBS, MOODS } from '../data/town.js';
import { $, UI } from '../ui/ui.js';
import { Town } from './town.js';

/* ================= 📋 일: 일 배정 · 제작 주문 · 목표 재고 (docs/설계_정착지_2단계.md §6 · §9) ================= */
const DOTS = ['·', '●', '●●', '●●●'];
const DOING = { build: '🔨', haul: '📦', farm: '🌾', cook: '🍲', craft: '⚒', gather: '🪓', rest: '💭', sleep: '💤', faint: '😵' };
const TGT = ['나무', '돌', '광석', '식량', '식사'];
const matTxt = (c) => Object.entries(c).map(([m, k]) => `<span style="color:${stockOf(m) >= k ? '#dfe3f5' : '#ff8a8a'}">${MATS[m] || ''}${m} ${k}</span>`).join(' ');
/** 장비 고르기가 필요한 주문의 대상 목록 */
function gearPool(R) {
  const h = META.hero, list = [...(META.gear || []).map((it) => ['창고', it]), ...(h ? [...Object.values(h.eq || {}), ...(h.bag || [])].filter(Boolean).map((it) => ['등불지기', it]) : [])];
  const out = R.out;
  const t = tierOf(R.room);
  return list.filter(([, it]) => (out.brand ? isWeapon(it) : out.ego ? !isWeapon(it) && hasQuality(it.base) : out.quality ? hasQuality(it.base) && (it.q || 1) < Math.min(4, t + 1) : out.enhance ? (it.plus || 0) < plusMax(it) : true));
}

Object.assign(Town, {
  workTab: 'jobs',
  workRoom: null,
  /** 제작 버튼·작업대에서: 그 방의 제작 칸으로 */
  craft(kind) {
    const have = Object.keys(STATIONS).filter((k) => roomOfKind(k));
    if (!have.length) { UI.toast('작업방이 아직 없다. 모루·연금대·책장·화덕과 식탁을 벽 안에 두면 된다.'); return; }
    this.workSheet('craft', have.includes(kind) ? kind : this.workRoom || have[0]);
  },
  workSheet(tab = this.workTab, room) {
    colony(); this.workTab = tab; if (room) this.workRoom = room;
    const tabs = [['jobs', '👥 일 배정'], ['craft', '⚒ 제작'], ['stock', '📦 목표 재고']].map(([k, t]) => `<button class="wbtn ${k === tab ? 'on' : ''}" data-tab="${k}" style="height:40px">${t}</button>`).join('');
    const body = tab === 'jobs' ? this.jobsHtml() : tab === 'craft' ? this.craftHtml() : this.stockHtml();
    const sh = this.sheet(`<h3>📋 일 <button class="close">닫기</button></h3><div class="wrow" style="grid-template-columns:repeat(3,1fr)">${tabs}</div>${body}`);
    sh.classList.add('tall'); sh.onpointerdown = () => { this.workTouch = performance.now(); };
    sh.querySelector('.close').addEventListener('click', () => { sh.classList.remove('tall'); sh.onpointerdown = null; });
    sh.querySelectorAll('[data-tab]').forEach((b) => { b.onclick = () => this.workSheet(b.dataset.tab); });
    if (tab === 'jobs') this.jobsWire(sh); else if (tab === 'craft') this.craftWire(sh); else this.stockWire(sh);
  },
  /** 열려 있으면 다시 그린다(시간이 흐를 때) */
  workRefresh() {
    const sh = $('#sheet'); if (sh.classList.contains('hidden') || !sh.querySelector('[data-tab]') || sh.querySelector('[data-pick]')) return;
    if (performance.now() - (this.workTouch || 0) < 1500) return; // 누르는 중에는 다시 그리지 않는다
    const wrap = sh.querySelector('.jobwrap'), sx = wrap ? wrap.scrollLeft : 0, sy = sh.scrollTop;
    this.workSheet();
    const w2 = sh.querySelector('.jobwrap'); if (w2) w2.scrollLeft = sx; sh.scrollTop = sy;
  },

  /* ---------- 일 배정 표 ---------- */
  jobsHtml() {
    const head = `<tr><th></th>${WORK_IDS.map((w) => `<th title="${WORKS[w].name}">${WORKS[w].icon}<br><small>${WORKS[w].name}</small></th>`).join('')}</tr>`;
    const rows = META.npcs.map((n) => {
      const auto = !n.work || n.work.auto;
      const cells = WORK_IDS.map((w) => { const p = priOf(n, w); return `<td><button class="pri p${p} ${auto ? 'auto' : ''}" data-n="${n.id}" data-w="${w}">${DOTS[p]}</button></td>`; }).join('');
      return `<tr><td class="who"><b>${JOBS[n.job].icon} ${n.name}</b> ${MOODS[n.mood + 2]}<br><small>${DOING[n.doing] || '💭'} ${n.doing && WORKS[n.doing] ? WORKS[n.doing].name : n.doing === 'sleep' ? '잠' : n.doing === 'faint' ? '배고파 쓰러짐' : '쉼'}${n.hunger ? ` · 굶음 ${n.hunger}` : ''}</small><br><button class="autob ${auto ? 'on' : ''}" data-auto="${n.id}">${auto ? '✓ 알아서' : '직접'}</button></td>${cells}</tr>`;
    }).join('');
    return `<div class="gtxt" style="color:#9aa2bd;margin-top:8px">칸을 누르면 우선순위가 바뀐다(· 안 함 → ●●● 먼저). 알아서 = 직업 특기 일을 먼저.</div>
      <div class="jobwrap" style="overflow-x:auto"><table class="jobs">${head}${rows}</table></div>`;
  },
  jobsWire(sh) {
    sh.querySelectorAll('[data-w]').forEach((b) => { b.onclick = () => {
      const n = META.npcs.find((q) => q.id === b.dataset.n), w = b.dataset.w;
      if (n.work.auto) { n.work.pri = Object.fromEntries(WORK_IDS.map((k) => [k, priOf(n, k)])); n.work.auto = false; }
      n.work.pri[w] = ((n.work.pri[w] ?? 1) + 1) % 4; n.task = null; saveMeta(); this.workSheet('jobs');
    }; });
    sh.querySelectorAll('[data-auto]').forEach((b) => { b.onclick = () => { const n = META.npcs.find((q) => q.id === b.dataset.auto); n.work.auto = !n.work.auto; n.task = null; saveMeta(); this.workSheet('jobs'); }; });
  },

  /* ---------- 제작 ---------- */
  craftHtml() {
    const ks = Object.keys(STATIONS).filter((k) => roomOfKind(k));
    if (!ks.length) return `<div class="gtxt" style="margin-top:10px">작업방이 아직 없다. 🔨 건설에서 모루(대장간)·연금대(연금실)·책장(서재)·화덕과 식탁(식당)을 벽과 문 안에 두자.</div>`;
    const k = ks.includes(this.workRoom) ? this.workRoom : ks[0]; this.workRoom = k;
    const t = tierOf(k), w = stationWorker(k), C = META.colony;
    const rt = ks.map((q) => `<button class="wbtn ${q === k ? 'on' : ''}" data-room="${q}" style="height:44px">${ROOMS[q].icon} ${STATIONS[q]}<small>${tierOf(q)}등급</small></button>`).join('');
    const who = [...META.npcs.map((n) => `<button class="wbtn ${w === n ? 'on' : ''}" data-st="${n.id}" style="height:46px">${JOBS[n.job].icon} ${n.name}<small>${JOBS[n.job].b === k ? '특기' : JOBS[n.job].name}</small></button>`), `<button class="wbtn ${C.stations[k] === 'none' ? 'on' : ''}" data-st="none" style="height:46px">🚫 비움</button>`].join('');
    const queue = C.orders.filter((o) => CRAFT_BY_ID[o.rid].room === k).map((o) => {
      const R = CRAFT_BY_ID[o.rid], why = orderWhy(o), g = o.target && (META.gear.find((q) => q.uid === o.target) || Object.values(META.hero?.eq || {}).find((q) => q && q.uid === o.target) || META.hero?.bag.find((q) => q.uid === o.target));
      const pct = Math.min(100, Math.round((o.prog / R.h) * 100));
      return `<div class="prow"><span>${R.name}${o.crystal ? ` · ${MATS[o.crystal]}` : ''}${g ? ` · <span style="color:${gearCss(g)}">${gearName(g, true)}</span>` : ''} <small>×${o.n}</small><br><small style="color:${why ? '#ff9aa4' : '#8fffb0'}">${why || (o.paid ? `만드는 중 ${pct}%` : w ? '차례를 기다린다' : '작업할 사람이 없다')}</small></span>
        <span style="display:flex;gap:4px"><button data-q="${o.id}" data-d="-1">−</button><button data-q="${o.id}" data-d="1">+</button><button data-del="${o.id}">✕</button></span></div>`;
    }).join('') || '<div class="gtxt" style="color:#9aa2bd">주문이 없다.</div>';
    const list = CRAFT.filter((R) => R.room === k).map((R) => {
      const lock = t < R.tier, cost = { ...R.in };
      return `<div class="prow"><span>${R.name} <small>${R.h}시간${R.tier > 1 ? ` · ${R.tier}등급` : ''}</small><br><small>${matTxt(cost)}${R.crystal ? ` · 원소 결정 ${R.crystal}` : ''}</small></span><button class="mk" data-add="${R.id}" ${lock ? 'disabled' : ''}>${lock ? `${R.tier}등급` : '주문'}</button></div>`;
    }).join('');
    const up = t < 3 ? `<div class="gtxt" style="color:#9aa2bd">${t + 1}등급: 🔨 건설에서 이 방에 ${t + 1}등급 가구를 들인다.</div>` : '';
    return `<div class="wrow" style="grid-template-columns:repeat(${Math.min(4, ks.length)},1fr);margin-top:8px">${rt}</div>
      <div class="sec">작업하는 사람 <small>${w ? `${w.name} · ${w.doing === 'craft' ? '작업 중' : '다른 일'}` : '없음'}</small></div><div class="wrow" style="grid-template-columns:repeat(3,1fr)">${who}</div>
      <div class="sec">주문 <small>위에서부터 차례로</small></div>${queue}
      <div class="sec">제작 목록 <small>${STATIONS[k]} ${t}등급</small></div>${list}${up}`;
  },
  craftWire(sh) {
    const C = META.colony, k = this.workRoom;
    sh.querySelectorAll('[data-room]').forEach((b) => { b.onclick = () => this.workSheet('craft', b.dataset.room); });
    sh.querySelectorAll('[data-st]').forEach((b) => { b.onclick = () => {
      const id = b.dataset.st; for (const [q, v] of Object.entries(C.stations)) if (v === id && q !== k) delete C.stations[q]; // 한 사람은 한 곳에만
      C.stations[k] = id; for (const n of META.npcs) if (n.task?.kind === 'craft') n.task = null; saveMeta(); this.workSheet('craft');
    }; });
    sh.querySelectorAll('[data-q]').forEach((b) => { b.onclick = () => { const o = C.orders.find((q) => q.id === +b.dataset.q); o.n = Math.max(1, Math.min(CRAFT_BY_ID[o.rid].out.buff ? 1 : 20, o.n + +b.dataset.d)); saveMeta(); this.workSheet('craft'); }; });
    sh.querySelectorAll('[data-del]').forEach((b) => { b.onclick = () => {
      const o = C.orders.find((q) => q.id === +b.dataset.del); if (o.paid) for (const [m, q] of Object.entries(orderCost(o))) addStock(m, q); // 치른 재료는 돌려준다
      C.orders = C.orders.filter((q) => q !== o); saveMeta(); this.workSheet('craft');
    }; });
    sh.querySelectorAll('[data-add]').forEach((b) => { b.onclick = () => this.orderPick(b.dataset.add); });
  },
  /** 대상 장비 · 원소 결정 고르기(필요할 때만) */
  orderPick(rid, sel = {}) {
    const R = CRAFT_BY_ID[rid], needGear = R.out.enhance || R.out.quality || R.out.brand || R.out.ego;
    if ((!needGear || sel.target) && (!R.crystal || sel.crystal)) { addOrder(rid, sel); saveMeta(); UI.toast(`주문: ${R.name}`); this.workSheet('craft'); return; }
    let html;
    if (R.crystal && !sel.crystal) {
      html = Object.keys(CRYSTALS).map((c) => `<div class="prow"><span>${MATS[c]} ${c} <small>${stockOf(c)}개 · ${R.crystal}개 쓴다</small></span><button class="mk" data-pick="c" data-v="${c}" ${stockOf(c) >= R.crystal ? '' : 'disabled'}>고르기</button></div>`).join('');
    } else {
      const pool = gearPool(R);
      html = pool.map(([wh, it]) => `<div class="prow"><span style="color:${gearCss(it)}">${gearName(it, true)} <small>${wh}</small></span><button class="mk" data-pick="g" data-v="${it.uid}">고르기</button></div>`).join('') || '<div class="gtxt">고를 장비가 없다.</div>';
    }
    const sh = this.sheet(`<h3>${R.name}: ${R.crystal && !sel.crystal ? '원소 결정' : '장비'} 고르기 <button class="close">닫기</button></h3><div class="gtxt" style="color:#9aa2bd">${matTxt(orderCost({ rid, ...sel, target: sel.target || null }))}</div>${html}<div class="prow"><span></span><button data-back="1">← 돌아가기</button></div>`);
    sh.classList.add('tall');
    sh.querySelector('[data-back]').onclick = () => this.workSheet('craft');
    sh.querySelectorAll('[data-pick]').forEach((b) => { b.onclick = () => this.orderPick(rid, { ...sel, [b.dataset.pick === 'c' ? 'crystal' : 'target']: b.dataset.v }); });
  },

  /* ---------- 목표 재고 ---------- */
  stockHtml() {
    const rows = TGT.map((m) => `<div class="prow"><span>${MATS[m] || ''} ${m} <small>있음 ${have(m)}</small></span><span style="display:flex;gap:4px;align-items:center"><button data-t="${m}" data-d="-5">−</button><b style="min-width:34px">${target(m)}</b><button data-t="${m}" data-d="5">+</button></span></div>`).join('');
    const mats = Object.entries(MATS).filter(([m]) => !TGT.includes(m) && stockOf(m) > 0).map(([m, ic]) => `${ic}${m} ${stockOf(m)}`).join(' · ') || '없음';
    const piles = META.colony.piles.length ? `<div class="gtxt" style="color:#9aa2bd">바닥에 쌓인 더미 ${META.colony.piles.length}곳: 나르기 일을 하는 사람이 창고로 옮긴다.</div>` : '';
    return `<div class="gtxt" style="color:#9aa2bd;margin-top:8px">목표에 모자라면 주민이 알아서 베고 캐고 요리한다. 넘치면 쉬거나 다른 일을 한다.</div>${rows}${piles}<div class="sec">재료 창고</div><div class="gtxt">${mats}</div>`;
  },
  stockWire(sh) {
    sh.querySelectorAll('[data-t]').forEach((b) => { b.onclick = () => { const m = b.dataset.t; META.colony.targets[m] = Math.max(0, Math.min(400, target(m) + +b.dataset.d)); saveMeta(); this.workSheet('stock'); }; });
  },
});
