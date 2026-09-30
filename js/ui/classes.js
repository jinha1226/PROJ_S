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
import { Game } from '../core/state.js';
import { canSpend, nextXp, progOf } from '../core/progress.js';

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
    const p = G.player, k = p.klass, pr = G.prog || { level: 1, xp: 0, points: 0 }, nx = nextXp(pr);
    const head = `<div class="sec">직업 · 성장</div><div class="gtxt">레벨 ${pr.level}${nx != null ? ` · 경험 ${pr.xp}/${nx}` : ''}${pr.points ? ` · <b style="color:#ffe38a">찍을 점수 ${pr.points}</b>` : ''}</div>`;
    if (!k || k.kind === 'none') return `${head}<div class="gtxt">직업 없음 <button class="mini" data-act="pickclass">직업 정하기</button></div>`;
    const lv = Object.entries(k.levels).filter(([, v]) => v > 0).map(([c, v]) => `${BASE[c].name} ${v}`).join(' / ');
    return `${head}<div class="gtxt"><b style="color:${roleCss(k.role)}">${k.title}</b> · ${ROLES[k.role].name}${k.sub ? ` / ${ROLES[k.sub].name}` : ''} <small style="color:#9aa2bd">(${lv})</small></div>
      <div class="gtxt">${k.traits.map(traitLine).join('<br>')}</div><div class="gtxt">장착: ${loadoutOf(p).map((L) => `${CSKILLS[L.id].icon} ${CSKILLS[L.id].name}`).join(' · ')}</div>
      <button class="mini" data-act="pickclass" style="margin-top:4px">${pr.points ? '점수 찍기 · 스킬' : '갈래 · 스킬'}</button>`;
  },
  /**
   * 직업 · 성장 창: 찍을 점수만큼 기본 Class에 1씩(둘까지, 합은 레벨 이하). 이번에 찍은 것만 되돌릴 수 있다(다시 나누기는 훈련소).
   * rec = 등불지기 기록(META.hero) 또는 주민 기록. 던전 안의 등불지기는 G.player에도 바로 입힌다
   */
  openClassPicker(rec, draft) {
    const hero = !rec || rec === META.hero, R = rec || META.hero, prog = hero && Game.mode === 'dungeon' ? G.prog : progOf(R), sh = $('#sheet');
    if (!prog) return;
    if (hero && Game.mode === 'dungeon' && inCombat()) { this.toast('싸우는 중에는 바꿀 수 없다.'); return; }
    const d = draft || { b: structuredClone(prog.build || { levels: {} }), add: {} };
    const b = d.b; b.levels ||= {}; b.branch ||= {};
    for (const c of BASE_IDS) if ((b.levels[c] || 0) >= CLASS_RULE.branchAt && !b.branch[c]) b.branch[c] = 'A'; // 보이는 대로 저장된다
    const added = Object.values(d.add).reduce((a, v) => a + v, 0), free = prog.points - added, ks = BASE_IDS.filter((c) => b.levels[c] > 0), k = classOf(b);
    const row = (c) => { const v = b.levels[c] || 0, can = canSpend(b, c, free), back = d.add[c] > 0; return `<div class="gtxt" style="display:flex;align-items:center;gap:6px"><b style="width:70px;color:${roleCss(BASE[c].role)}">${BASE[c].name}</b><button class="mini" data-lv="${c}" data-d="-1" ${back ? '' : 'disabled'}>−</button><b style="width:22px;text-align:center">${v}</b><button class="mini" data-lv="${c}" data-d="1" ${can ? '' : 'disabled'}>＋</button><small style="color:#9aa2bd">${ROLES[BASE[c].role].name} · ${BASE[c].line}</small></div>`; };
    const open = k.skills || [];
    const branches = ks.filter((c) => b.levels[c] >= CLASS_RULE.branchAt).map((c) => `<div class="gtxt">${BASE[c].name} 갈래: ${['A', 'B'].map((x) => `<button class="mini${b.branch[c] === x ? ' on' : ''}" data-br="${c}" data-x="${x}">${BRANCHES[c][x].name}</button>`).join(' ')} <small style="color:#9aa2bd">${BRANCHES[c][b.branch[c]].line}</small></div>`).join('');
    const mainPick = k.kind === 'pair' && !k.lean ? `<div class="gtxt">균형형 주 Role: ${[BASE[ks[0]].role, BASE[ks[1]].role].filter((r, i, a) => a.indexOf(r) === i).map((r) => `<button class="mini${k.role === r ? ' on' : ''}" data-main="${r}">${ROLES[r].name}</button>`).join(' ')}</div>` : '';
    const load = (b.loadout || []).filter((id) => open.some((q) => q.id === id));
    const skills = open.map((q) => { const S = CSKILLS[q.id], L = skillParams(q, b), on = load.includes(q.id); return `<button class="gline${on ? ' on' : ''}" data-sk="${q.id}" style="display:block;width:100%;text-align:left;margin:2px 0;${on ? 'border-color:#9fd8ff' : ''}">${on ? '☑' : '☐'} ${S.icon} <b>${S.name}</b>${q.sig ? ' <small style="color:#ffe38a">전용</small>' : ''}${q.upgraded ? ' <small style="color:#9fffb0">강화</small>' : ''} <small style="color:#9aa2bd">${L.cd.toFixed(1)}초 · ${S.d(L.p)}</small></button>`; }).join('');
    sh.innerHTML = `<h3>🎓 ${R.name || '등불지기'} · 직업 <button class="close">닫기</button></h3>
      <div class="gtxt">레벨 ${prog.level} · 찍을 점수 <b style="color:${free ? '#ffe38a' : '#9aa2bd'}">${free}</b> <small style="color:#9aa2bd">· 기본 Class 둘까지. 한 Class 10 = 한 우물, 둘 다 3 이상 = 두 우물</small></div>
      ${BASE_IDS.map(row).join('')}
      <div class="sec">결과</div><div class="gtxt">${k.kind !== 'none' ? `<b style="color:${roleCss(k.role)}">${k.title}</b> · ${ROLES[k.role].name}${k.sub ? ` / ${ROLES[k.sub].name}` : ''}<br>${k.traits.map(traitLine).join('<br>')}` : '직업 없음'}</div>
      ${mainPick}${branches}
      <div class="sec">장착 ${load.length}/${CLASS_RULE.slots} <small>누르면 넣고 뺀다</small></div>${skills || '<div class="gtxt" style="color:#9aa2bd">열린 스킬이 없다</div>'}
      <button class="bigbtn" data-act="apply">정하기</button>`;
    sh.classList.add('tall'); sh.classList.remove('hidden');
    const again = () => this.openClassPicker(rec, d);
    sh.querySelector('.close').onclick = () => { sh.classList.add('hidden'); sh.classList.remove('tall'); };
    sh.querySelectorAll('[data-lv]').forEach((el) => { el.onclick = () => { const c = el.dataset.lv; if (+el.dataset.d > 0) { if (!canSpend(b, c, free)) return; b.levels = { ...b.levels, [c]: (b.levels[c] || 0) + 1 }; d.add[c] = (d.add[c] || 0) + 1; } else if (d.add[c] > 0) { d.add[c]--; b.levels = { ...b.levels, [c]: b.levels[c] - 1 }; if (!b.levels[c]) delete b.levels[c]; } again(); }; });
    sh.querySelectorAll('[data-br]').forEach((el) => { el.onclick = () => { b.branch[el.dataset.br] = el.dataset.x; again(); }; });
    sh.querySelectorAll('[data-main]').forEach((el) => { el.onclick = () => { b.main = el.dataset.main; again(); }; });
    sh.querySelectorAll('[data-sk]').forEach((el) => { el.onclick = () => { const id = el.dataset.sk; b.loadout = load.includes(id) ? load.filter((q) => q !== id) : load.length < CLASS_RULE.slots ? [...load, id] : load; again(); }; });
    sh.querySelector('[data-act="apply"]').onclick = () => {
      if (!validLevels(b.levels)) return;
      prog.points -= added; prog.build = b;
      if (hero && Game.mode === 'dungeon') { const p = G.player, hp0 = p.hp; setClass(p, b); refreshStats(); p.hp = Math.min(hp0, p.max); prog.build = p.build; this.renderSkills(true); this.syncAll(); View.refreshDecals(); }
      saveMeta();
      sh.classList.add('hidden'); sh.classList.remove('tall');
      const t = classOf(b); this.toast(`${R.name || '등불지기'}: ${t.kind === 'none' ? '직업 없음' : t.title}.`);
    };
  },
});
