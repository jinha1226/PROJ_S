import { META, resetMeta, saveMeta } from '../core/meta.js';
import { extinguish, perkOf, takeTorch, volunteers } from '../core/succession.js';
import { acceptVisitor, dismissVisitor, requestState } from '../core/visitors.js';
import { ROOMS, SCX, SCY } from '../data/build.js';
import { ENDING, LORE, VOLUNTEER } from '../data/lines.js';
import { BLD, JOBS, TRAITS, adj } from '../data/town.js';
import { LANDS, PERKS } from '../data/visitors.js';
import { W3 } from '../render/common.js';
import { Sfx } from '../render/sfx.js';
import { View } from '../render/view.js';
import { $, UI } from '../ui/ui.js';
import { jo } from '../util/text.js';
import { TownNPC } from './town-npc.js';
import { Town } from './town.js';

/* ================= 방문자 카드 · 등불지기 잇기 · 결말 ================= */
/** "정직한 · 까칠한 대장장이" — 가장 두드러진 성격 둘 */
export function summary(n) {
  const ks = TRAITS.map(([k]) => k).sort((a, b) => Math.abs(n.t[b]) - Math.abs(n.t[a])).slice(0, 2);
  return `${ks.map((k) => adj(n, k)).join(' · ')} ${JOBS[n.job].name}`;
}
const landName = (n) => (LANDS.find((L) => L.id === n.from) || { name: '떠돌이' }).name;

Object.assign(Town, {
  visitorCard(v) {
    Sfx.play('ui');
    const n = v.npc, st = requestState(v), left = 2 - v.waits;
    const sh = this.sheet(`<h3>방문자 <button class="close">닫기</button></h3>
      <div class="vcard"><div class="vname">${n.name}</div><div class="vsub">${summary(n)} · ${landName(n)}에서 왔다</div>
      <div class="vline">“${st.line}”</div>
      <div class="vreq ${st.ok ? 'ok' : 'no'}">${st.ok ? '✓' : '✗'} ${st.need}${st.note ? `<br><small>${st.note}</small>` : ''}</div></div>
      <div class="wrow" style="grid-template-columns:1fr 1fr 1fr;margin-top:8px">
        <button class="wbtn" data-a="accept" ${st.ok ? '' : 'disabled style="opacity:.4"'}>받아들이기</button>
        <button class="wbtn" data-a="wait">기다려 달라<small>${left > 0 ? `귀환 ${left}번 더` : '다음 귀환에 떠난다'}</small></button>
        <button class="wbtn" data-a="dismiss">돌려보내기</button></div>`);
    sh.querySelector('[data-a="accept"]').onclick = () => { if (st.ok) this.acceptScene(v); };
    sh.querySelector('[data-a="wait"]').onclick = () => { sh.classList.add('hidden'); UI.toast(`${jo(n.name, '이가')} 불가에서 조금 더 기다리기로 했다`); };
    sh.querySelector('[data-a="dismiss"]').onclick = () => { dismissVisitor(v); saveMeta(); sh.classList.add('hidden'); const q = this.removeVisitor(v); if (q) View.dio.puffs.emit({ pos: q.d.root.position, n: 10, color: 0x8a8490, speed: 1, grav: 0, life: 0.7, size: 0.3 }); UI.toast(`${jo(n.name, '은는')} 어둠 속으로 돌아갔다`); this.renderHud(); };
  },
  acceptScene(v) {
    const r = acceptVisitor(v); if (!r) return;
    saveMeta(); $('#sheet').classList.add('hidden');
    const q = this.removeVisitor(v), pos = q ? [q.d.root.position.x, q.d.root.position.z] : [SCX, SCY + 1.5];
    const t = new TownNPC(v.npc, [pos[0], 0, pos[1]]); this.npcs.push(t); this.bubble(t);
    View.dio.sparks.emit({ pos: W3(pos[0], pos[1], 0.8), n: 26, color: 0xffc070, color2: 0xffffff, speed: 2, up: 1.5, grav: 0, life: 0.8, size: 0.12 }); Sfx.chime(4);
    UI.banner(`${jo(v.npc.name, '이가')} 주민이 되었다`, 'info');
    if (r.want) setTimeout(() => UI.toast(`${jo(v.npc.name, '이가')} 일할 ${jo(ROOMS[r.want].name, '이가')} 아직 없다.`), 900);
    this.applyGlow(); this.renderHud();
  },
  /* ---- 등불지기 잇기 ---- */
  successionSheet() {
    if (!META.needSuccessor || META.hero) return;
    if (META.npcs.length === 1) { const n = META.npcs[0]; this.torchScene(n, `${jo(n.name, '이가')} 말없이 횃불을 들었다. 남은 사람은 ${n.name}뿐이었다.`); return; }
    const vs = volunteers();
    const cards = vs.map((n, k) => { const pk = perkOf(n), line = n.t.E <= -1 ? VOLUNTEER.lowE : n.t.H >= 1 ? VOLUNTEER.highH : n.t.A >= 1 ? VOLUNTEER.highA : VOLUNTEER.other;
      return `<button class="vol" data-v="${k}"><b>${n.name}</b><small>${summary(n)} · ${jo(BLD[JOBS[n.job].b].name, '이가')} 빈다</small><span class="vline">“${line}”</span><span class="perk">${pk ? `✦ ${PERKS[pk].name}: ${PERKS[pk].desc}` : '✦ 특별한 시작 특성 없음'}</span></button>`; }).join('');
    const sh = this.sheet(`<h3>누가 횃불을 들까</h3><div class="gtxt">등불지기가 쓰러졌다. 누군가 다시 내려가야 한다.<br><small>고른 사람은 정착지를 떠나 등불지기가 된다. 그 사람의 일터는 비고, 가까웠던 이웃들은 슬퍼한다.</small></div><div class="vols">${cards}</div>`);
    sh.querySelectorAll('[data-v]').forEach((b) => { b.onclick = () => this.torchScene(vs[+b.dataset.v]); });
  },
  torchScene(n, note) {
    $('#sheet').classList.add('hidden'); this.busy = true;
    const t = this.npcs.find((q) => q.n === n), c = { x: SCX, y: SCY };
    if (t) t.goto(c.x - 0.8, c.y + 0.4, 'idle', 5, [c.x, c.y]);
    setTimeout(() => {
      const D = View.dio; D.pool.flash(W3(c.x, c.y), 0xffa040, 90, 1, 8); D.sparks.emit({ pos: W3(c.x - 0.6, c.y + 0.4, 1.0), n: 40, color: 0xff9a3a, color2: 0xffe36a, speed: 2.5, up: 2, grav: 0.3, life: 1, size: 0.14 }); Sfx.play('fire');
      takeTorch(n); UI.banner(`${META.hero.gen}대 등불지기 ${n.name}`, 'fire');
      setTimeout(() => { this.build(); this.renderHud(); this.busy = false; if (note) UI.toast(note); }, 900);
    }, t ? 1600 : 200);
  },
  /* ---- 결말 ---- */
  endingDawn() {
    const names = [...META.npcs.map((n) => n.name), ...META.fallen.map((f) => f.name)];
    const loreAll = LORE.every((_, k) => META.lore.includes(k + 1));
    UI.screen(`<div class="ending dawn"><h1>새벽</h1>${ENDING.dawn.map((t, k) => `<p class="fade" style="animation-delay:${k * 1.4}s">${t}</p>`).join('')}
      <div class="names">${names.map((nm, k) => `<span class="fade" style="animation-delay:${4.5 + k * 0.45}s">${nm}</span>`).join('')}</div>
      ${loreAll ? `<p class="fade" style="animation-delay:${5 + names.length * 0.45}s">${LORE[3]}</p><div class="wrow fade" style="animation-delay:${5.5 + names.length * 0.45}s"><button class="wbtn" data-w="1">그의 이름을 새긴다</button><button class="wbtn" data-w="0">비워 둔다</button></div><p id="watcher"></p>` : ''}
      <button class="bigbtn fade" id="btn-dawn" style="animation-delay:${6 + names.length * 0.45}s">정착지로</button></div>`);
    document.querySelectorAll('[data-w]').forEach((b) => { b.onclick = () => { META.watcher = b.dataset.w === '1'; saveMeta(); $('#watcher').textContent = META.watcher ? ENDING.watcherYes : ENDING.watcherNo; document.querySelectorAll('[data-w]').forEach((q) => { q.disabled = true; }); }; });
    $('#btn-dawn').onclick = () => { $('#screen').classList.add('hidden'); };
  },
  endingDark() {
    const names = META.fallen.map((f) => f.name);
    extinguish();
    UI.screen(`<div class="ending dark"><h1>꺼진 불</h1>${ENDING.dark.map((t, k) => `<p class="fade" style="animation-delay:${k * 1.4}s">${t}</p>`).join('')}
      <div class="names out">${names.map((nm, k) => `<span class="fade" style="animation-delay:${4 + k * 0.35}s">${nm}</span>`).join('')}</div>
      <p class="fade" style="animation-delay:${5 + names.length * 0.35}s;color:#8a8a9a">세상은 완전히 잊혔다. 기록이 지워졌다.</p>
      <button class="bigbtn fade" id="btn-dark" style="animation-delay:${6 + names.length * 0.35}s">처음부터</button></div>`);
    View.dio.lights.setGlow?.(0);
    $('#btn-dark').onclick = () => { resetMeta(); UI.title(); };
  },
  graveInfo(f) { UI.info(`<h3>🕯 ${f.name}</h3><div class="gtxt">${f.gen}대 등불지기 · 구역 ${f.zone}-${f.zf}에서 ${f.by ? f.by + '에게 ' : ''}쓰러졌다 · ${f.kills}마리를 쓰러뜨렸다</div><div class="gtxt" style="color:#9aa2bd">누군가 비석 앞에 마른 꽃을 두고 갔다.</div>`); },
  loreInfo(zone) { UI.info(`<h3>옛 등불지기의 기록</h3><div class="gtxt">${LORE[zone - 1]}</div><div class="gtxt" style="color:#9aa2bd">기록 ${META.lore.length}/4</div>`); },
});
