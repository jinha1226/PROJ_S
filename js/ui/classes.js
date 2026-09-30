import { act } from '../flow.js';
import { los } from '../core/fov.js';
import { META, saveMeta } from '../core/meta.js';
import { refreshStats } from '../core/gear.js';
import { G, I, inb } from '../core/state.js';
import { inCombat } from '../core/stones.js';
import { CSKILLS } from '../data/class-skills.js';
import { BASE, BASE_IDS, BRANCHES, CLASS_RULE, ROLES, TRAITS } from '../data/classes.js';
import { T_WALL } from '../data/terrain.js';
import { Sfx } from '../render/sfx.js';
import { View } from '../render/view.js';
import { classOf, loadoutOf, setClass, skillParams, validLevels } from '../sim/classes.js';
import { enemyOf } from '../sim/effects.js';
import { skillReady, useSkill } from '../sim/skillfx.js';
import { $, UI } from './ui.js';

/* ================= 직업: 스킬 버튼 3칸 · 조준 · 스킬 설명 · Class 정하기(시험용, 훈련소가 생기기 전까지) (docs/설계_직업.md) ================= */
const roleCss = (r) => (r ? ROLES[r].css : '#9aa2bd');
const traitLine = (t) => { const T = TRAITS[t.id]; return `${T.name}: ${T.line(T.v[t.tier])}`; };

Object.assign(UI, {
  /** 스킬 버튼 k: 자기 대상은 바로, 그 밖은 조준 → 같은 칸 두 번 탭 */
  skillBtn(k) {
    if (G.over || this.overlayOpen()) return;
    const p = G.player, id = p.build && p.build.loadout[k];
    if (!id) { this.openClassPicker(); return; }
    if (this.mode === 'target' && this.pend?.kind === 'skill' && this.pend.slot === k) { this.exitTarget(); return; }
    Sfx.play('ui');
    const S = CSKILLS[id], L = skillParams(p.skillInfo[id], p.build);
    if (p.scd[id] > 0) { this.toast(`${S.name}: ${Math.ceil(p.scd[id])}초 남았다.`); return; }
    if (!skillReady(p, id)) return;
    if (L.tgt === 'self') { act(() => useSkill(p, id)); this.renderSkills(true); return; }
    this.enterTarget({ kind: 'skill', slot: k, id, tgt: L.tgt, range: L.r, name: `${S.icon} ${S.name}`, color: 0x9fd8ff, run: (x, y) => { useSkill(p, id, x, y); this.renderSkills(true); } });
  },
  /** 조준 칸: 적 · 아군 · 칸 · 방향 */
  skillTargets(pend) {
    const p = G.player, set = new Set(), R = Math.ceil(pend.range) + 1;
    for (let dy = -R; dy <= R; dy++) for (let dx = -R; dx <= R; dx++) {
      const x = p.x + dx, y = p.y + dy; if (!inb(x, y)) continue; const i = I(x, y);
      if (!G.vis[i] || G.tile[i] === T_WALL || Math.hypot(dx, dy) > pend.range + 0.6) continue;
      if (pend.tgt === 'foe' && !G.ents.some((e) => e.alive && e.x === x && e.y === y && !e.hidden && !e.npc && enemyOf(p, e))) continue;
      if (pend.tgt === 'ally' && !G.ents.some((e) => e.alive && e.x === x && e.y === y && e.team === p.team && !e.decoy)) continue;
      if (pend.tgt !== 'dir' && !los(p.x, p.y, x, y)) continue;
      if (pend.tgt !== 'ally' && x === p.x && y === p.y) continue; // 내 칸은 아군 대상 스킬만
      set.add(i);
    }
    return set;
  },
  skillPreview(pend) { const S = CSKILLS[pend.id], L = skillParams(G.player.skillInfo[pend.id], G.player.build); return { extra: [], note: S.d(L.p) }; },
  skillInfo(k) {
    const p = G.player, id = p.build && p.build.loadout[k];
    if (!id) { this.openClassPicker(); return; }
    const S = CSKILLS[id], L = skillParams(p.skillInfo[id], p.build);
    this.info(`<h3>${S.icon} ${S.name} <small style="color:#9aa2bd">${L.cast ? `시전 ${L.cast}초 · ` : ''}쿨타임 ${L.cd.toFixed(1)}초${L.r ? ` · ${L.r}칸` : ''}</small></h3><div>${S.d(L.p)}</div>`);
  },
  /** 스킬 칸 그리기(틱마다 불러도 바뀐 것만 고친다) */
  renderSkills(force) {
    const box = $('#souls'); if (!box || !box.classList.contains('skills')) return;
    const p = G.player, list = p && p.build ? loadoutOf(p) : [];
    box.classList.toggle('empty', !list.length);
    [...box.children].forEach((b, k) => {
      const L = list[k], id = L && L.id, cd = id ? p.scd[id] || 0 : 0, key = `${id}|${Math.ceil(cd)}|${id && skillReady(p, id)}`;
      if (!force && b.dataset.key === key) return; b.dataset.key = key;
      const S = id && CSKILLS[id];
      b.classList.toggle('on', !!S); b.style.setProperty('--c', p.klass ? roleCss(p.klass.role) : 'transparent');
      b.querySelector('.si').textContent = S ? S.icon : '＋'; b.querySelector('.sn').textContent = S ? S.name : '직업';
      b.classList.toggle('ready', !!S && cd <= 0); b.classList.toggle('cool', cd > 0); b.querySelector('.scd').textContent = cd > 0 ? Math.ceil(cd) : '';
    });
  },
  /** 상태 창의 직업 칸 */
  classSection() {
    const p = G.player, k = p.klass;
    if (!k || k.kind === 'none') return `<div class="sec">직업</div><div class="gtxt">없음 <button class="mini" data-act="pickclass">직업 정하기</button></div>`;
    const lv = Object.entries(k.levels).filter(([, v]) => v > 0).map(([c, v]) => `${BASE[c].name} ${v}`).join(' / ');
    return `<div class="sec">직업</div><div class="gtxt"><b style="color:${roleCss(k.role)}">${k.title}</b> · ${ROLES[k.role].name}${k.sub ? ` / ${ROLES[k.sub].name}` : ''} <small style="color:#9aa2bd">(${lv})</small></div>
      <div class="gtxt">${k.traits.map(traitLine).join('<br>')}</div><div class="gtxt">장착: ${loadoutOf(p).map((L) => `${CSKILLS[L.id].icon} ${CSKILLS[L.id].name}`).join(' · ')}</div>
      <button class="mini" data-act="pickclass" style="margin-top:4px">직업 바꾸기 (시험용)</button>`;
  },
  /** Class 정하기: 기본 Class 둘까지, 레벨 합 10 이하, 균형형 주 Role, 갈래, 장착 3칸 */
  openClassPicker(draft) {
    const p = G.player, sh = $('#sheet');
    if (G.over || !p) return;
    if (inCombat()) { this.toast('싸우는 중에는 바꿀 수 없다.'); return; }
    const b = draft || structuredClone(p.build || { levels: {} });
    b.levels ||= {}; b.branch ||= {};
    for (const c of BASE_IDS) if ((b.levels[c] || 0) >= CLASS_RULE.branchAt && !b.branch[c]) b.branch[c] = 'A'; // 보이는 대로 저장된다
    const ks = BASE_IDS.filter((c) => b.levels[c] > 0), tot = ks.reduce((a, c) => a + b.levels[c], 0), ok = validLevels(b.levels), k = classOf(b);
    const row = (c) => { const v = b.levels[c] || 0; return `<div class="gtxt" style="display:flex;align-items:center;gap:6px"><b style="width:70px;color:${roleCss(BASE[c].role)}">${BASE[c].name}</b><button class="mini" data-lv="${c}" data-d="-1">−</button><b style="width:22px;text-align:center">${v}</b><button class="mini" data-lv="${c}" data-d="1">＋</button><small style="color:#9aa2bd">${ROLES[BASE[c].role].name} · ${BASE[c].line}</small></div>`; };
    const open = k.skills || [];
    const branches = ks.filter((c) => b.levels[c] >= CLASS_RULE.branchAt).map((c) => `<div class="gtxt">${BASE[c].name} 갈래: ${['A', 'B'].map((x) => `<button class="mini${(b.branch[c] || 'A') === x ? ' on' : ''}" data-br="${c}" data-x="${x}">${BRANCHES[c][x].name}</button>`).join(' ')} <small style="color:#9aa2bd">${BRANCHES[c][b.branch[c] || 'A'].line}</small></div>`).join('');
    const mainPick = k.kind === 'pair' && !k.lean ? `<div class="gtxt">균형형 주 Role: ${[BASE[ks[0]].role, BASE[ks[1]].role].filter((r, i, a) => a.indexOf(r) === i).map((r) => `<button class="mini${k.role === r ? ' on' : ''}" data-main="${r}">${ROLES[r].name}</button>`).join(' ')}</div>` : '';
    const load = (b.loadout || []).filter((id) => open.some((s) => s.id === id));
    const skills = open.map((s) => { const S = CSKILLS[s.id], L = skillParams(s, b), on = load.includes(s.id); return `<button class="gline${on ? ' on' : ''}" data-sk="${s.id}" style="display:block;width:100%;text-align:left;margin:2px 0;${on ? 'border-color:#9fd8ff' : ''}">${on ? '☑' : '☐'} ${S.icon} <b>${S.name}</b>${s.sig ? ' <small style="color:#ffe38a">전용</small>' : ''}${s.upgraded ? ' <small style="color:#9fffb0">강화</small>' : ''} <small style="color:#9aa2bd">${L.cd.toFixed(1)}초 · ${S.d(L.p)}</small></button>`; }).join('');
    sh.innerHTML = `<h3>🎓 직업 (시험용) <button class="close">닫기</button></h3>
      <div class="gtxt" style="color:#9aa2bd">레벨 ${tot}/${CLASS_RULE.cap} · 기본 Class 둘까지. 한 Class 10 = 한 우물, 둘 다 3 이상 = 두 우물</div>
      ${BASE_IDS.map(row).join('')}
      <div class="sec">결과</div><div class="gtxt">${ok && k.kind !== 'none' ? `<b style="color:${roleCss(k.role)}">${k.title}</b> · ${ROLES[k.role].name}${k.sub ? ` / ${ROLES[k.sub].name}` : ''}<br>${k.traits.map(traitLine).join('<br>')}` : ok ? '없음' : '<span style="color:#ff9aa4">규칙에 맞지 않는다</span>'}</div>
      ${mainPick}${branches}
      <div class="sec">장착 ${load.length}/${CLASS_RULE.slots} <small>누르면 넣고 뺀다</small></div>${skills || '<div class="gtxt" style="color:#9aa2bd">열린 스킬이 없다</div>'}
      <button class="bigbtn" data-act="apply" ${ok ? '' : 'disabled'}>정하기</button>`;
    sh.classList.add('tall'); sh.classList.remove('hidden');
    const again = () => this.openClassPicker(b);
    sh.querySelector('.close').onclick = () => { sh.classList.add('hidden'); sh.classList.remove('tall'); };
    sh.querySelectorAll('[data-lv]').forEach((el) => { el.onclick = () => { const c = el.dataset.lv, v = Math.max(0, Math.min(10, (b.levels[c] || 0) + +el.dataset.d)); const nl = { ...b.levels, [c]: v }; if (!v) delete nl[c]; if (Object.keys(nl).filter((q) => nl[q] > 0).length <= 2 && Object.values(nl).reduce((a, q) => a + q, 0) <= CLASS_RULE.cap) b.levels = nl; again(); }; });
    sh.querySelectorAll('[data-br]').forEach((el) => { el.onclick = () => { b.branch[el.dataset.br] = el.dataset.x; again(); }; });
    sh.querySelectorAll('[data-main]').forEach((el) => { el.onclick = () => { b.main = el.dataset.main; again(); }; });
    sh.querySelectorAll('[data-sk]').forEach((el) => { el.onclick = () => { const id = el.dataset.sk; b.loadout = load.includes(id) ? load.filter((q) => q !== id) : load.length < CLASS_RULE.slots ? [...load, id] : load; again(); }; });
    sh.querySelector('[data-act="apply"]').onclick = () => {
      if (!validLevels(b.levels)) return;
      const hp0 = p.hp; setClass(p, b); refreshStats(); p.hp = Math.min(hp0, p.max); // 바꿔서 회복되지는 않는다
      if (META && META.hero) { META.hero.cls = structuredClone(p.build); saveMeta(); }
      sh.classList.add('hidden'); sh.classList.remove('tall');
      this.renderSkills(true); this.syncAll(); View.refreshDecals(); this.toast(`${p.klass.title || '직업 없음'}.`);
    };
  },
});
