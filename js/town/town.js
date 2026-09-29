import * as THREE from 'three';
import { META, processReturn, rel, saveMeta } from '../core/meta.js';
import { Game } from '../core/state.js';
import { weaponId } from '../data/gear.js';
import { S_GRASS, S_NONE, S_WATER } from '../data/terrain.js';
import { WORKTALK } from '../data/lines.js';
import { BLD, JOBS, TH, TOWN_PAL, TW } from '../data/town.js';
import { W3, _tv, _w } from '../render/common.js';
import * as K from '../render/diorama.js';
import { buildingModel, dollSpec, matProp, weaponDoll } from '../render/dolls.js';
import { Sfx } from '../render/sfx.js';
import { View } from '../render/view.js';
import { UI } from '../ui/ui.js';
import { pick } from '../util/rng.js';
import { TownNPC, talkLine } from './town-npc.js';

export const Town = {
  grid: null,
  npcs: [],
  blds: {},
  hero: null,
  center: new THREE.Vector3(5, 0, 7.4),
  objs: [],
  tags: [],
  rising: [],
  shower: [],
  busy: false,
  workSpot(n) { const b = BLD[JOBS[n.job].b]; return [b.x + (b.x < 5 ? 1.25 : -1.25), b.y + 0.6]; },
  enter(r = {}) {
    Game.mode = 'town';
    const res = processReturn(r); saveMeta();
    UI.toTown(); View.clear();
    // 조각을 넣기 전의 원경, 아직 오지 않은 방문자로 짓고 연출로 바꾼다
    if (res.shard) META.lit[res.shard - 1] = false;
    this.build(res.visitors);
    if (res.shard) META.lit[res.shard - 1] = true;
    this.busy = true;
    if (res.dark) { setTimeout(() => { this.busy = false; this.afterReport = () => this.endingDark(); this.report(r, res); }, 700); this.renderHud(); return; }
    const hasLoot = r.loot && Object.keys(r.loot).length, steps = [];
    if (hasLoot) steps.push((next) => { this.lootShower(r.loot); setTimeout(next, 2600); });
    if (res.shard) steps.push((next) => this.shardScene(res.shard, next));
    steps.push((next) => { const newB = Object.keys(META.buildings).filter((b) => !META.buildings[b].shown); newB.forEach((b, k) => setTimeout(() => this.rise(b), k * 900)); setTimeout(next, newB.length * 900 + (newB.length ? 700 : 0)); });
    for (const v of res.visitors) steps.push((next) => this.visitorArrive(v, () => setTimeout(next, 300)));
    steps.push(() => {
      this.busy = false;
      this.afterReport = () => { if (res.ending) this.endingDawn(); else if (META.needSuccessor) this.successionSheet(); };
      this.report(r, res);
    });
    const run = (k) => steps[k] && steps[k](() => run(k + 1));
    setTimeout(() => run(0), 500);
    this.renderHud();
  },
  clear() {
    const D = View.dio;
    if (this.grid) { this.grid.dispose(); this.grid = null; }
    for (const o of this.objs) D.scene.remove(o); this.objs = [];
    for (const n of this.npcs) D.scene.remove(n.d.root); this.npcs = [];
    for (const t of this.tags) t.remove(); this.tags = [];
    for (const s of this.shower) D.scene.remove(s.o); this.shower = [];
    this.blds = {}; this.hero = null; this.rising = []; this.lands = []; this.graves = []; this.visitorDolls = []; this.orbs = [];
  },
  build(skipVisitors = []) {
    const D = View.dio; this.clear();
    D.setPreset('settlement');
    const N = TW * TH, kind = (i) => { const x = i % TW, y = (i / TW) | 0; return x === 0 || y === 0 || x === TW - 1 || y === TH - 1 ? 'wall' : 'floor'; };
    this.grid = new K.GridView(D.scene, { w: TW, h: TH, kind, palette: TOWN_PAL, wallH: 0.55 }); D.grid = this.grid;
    const surf = new Uint8Array(N), fire = new Uint8Array(N);
    const foot = new Set();
    for (const [id, b] of Object.entries(BLD)) if (id !== 'plaza') for (let y = Math.round(b.y) - 1; y <= Math.round(b.y); y++) for (let x = Math.round(b.x) - 1; x <= Math.round(b.x) + 1; x++) foot.add(y * TW + x);
    for (let y = 1; y < TH - 1; y++) for (let x = 1; x < TW - 1; x++) {
      const i = y * TW + x, path = x === 5 || y === 7 || (Math.abs(x - 5) <= 1 && Math.abs(y - 7) <= 1);
      surf[i] = (x >= 8 && y <= 2) ? S_WATER : path ? S_NONE : foot.has(i) ? S_NONE : S_GRASS;
    }
    fire[7 * TW + 5] = 3;
    this.grid.setTerrain({ surf, fire, cloud: new Uint8Array(N), cloudT: new Uint8Array(N) });
    this.grid.setVisibility(new Uint8Array(N).fill(2)); this.grid.setDecals([]);
    for (const id of Object.keys(META.buildings)) this.placeBuilding(id, META.buildings[id].shown);
    // 울타리 밖 나무
    const trees = new THREE.Group();
    for (let k = 0; k < 26; k++) {
      const side = k % 4, t = Math.random(), x = side === 0 ? -1.3 : side === 1 ? TW + 0.3 : t * (TW + 1) - 0.5, z = side === 2 ? -1.3 : side === 3 ? TH + 0.3 : t * (TH + 1) - 0.5;
      const s = 0.8 + Math.random() * 0.6, d = K.doll([{ s: 'cyl', p: [0, 0.35, 0], k: [0.12, 0.7, 0.12], c: 0x6a4526 }, { s: 'ico', detail: 1, p: [0, 1.05, 0], k: [0.55, 0.6, 0.55], c: 0x4f9a3f }, { s: 'ico', detail: 1, p: [0.15, 1.45, 0.05], k: [0.38, 0.4, 0.38], c: 0x62b24f }], { gloss: 0.3, scale: s });
      d.root.position.set(x, 0, z); d.root.rotation.y = Math.random() * 6; trees.add(d.root);
    }
    D.scene.add(trees); this.objs.push(trees);
    for (const n of META.npcs) this.npcs.push(new TownNPC(n));
    if (META.hero) {
      const sp = dollSpec({ type: 'hero', face: [0, 1], eq: META.hero.eq }), d = K.doll(sp.parts, { scale: 1.3, gloss: sp.gloss }); const ex = sp.extra(d); if (META.hero.eq.weapon) ex.wh.add(weaponDoll(weaponId(META.hero.eq.weapon), META.hero.eq.weapon).root);
      d.root.position.set(4.1, 0, 8.1); d.root.rotation.y = 0.6; d.mesh.userData.pick = { hero: true }; D.scene.add(d.root); this.objs.push(d.root); this.hero = d;
    }
    this.buildHearth(skipVisitors);
    D.lightTarget = this.center; D.rig.focusT.copy(this.center); D.rig.snap();
  },
  /** 장비를 바꾸면 광장의 모험가 인형도 다시 입힌다 */
  redressHero() {
    if (!this.hero || !META.hero) return;
    const D = View.dio, old = this.hero, sp = dollSpec({ type: 'hero', face: [0, 1], eq: META.hero.eq }), d = K.doll(sp.parts, { scale: 1.3, gloss: sp.gloss }), ex = sp.extra(d);
    if (META.hero.eq.weapon) ex.wh.add(weaponDoll(weaponId(META.hero.eq.weapon), META.hero.eq.weapon).root);
    d.root.position.copy(old.root.position); d.root.rotation.y = old.root.rotation.y; d.mesh.userData.pick = { hero: true };
    D.scene.remove(old.root); this.objs.splice(this.objs.indexOf(old.root), 1, d.root); D.scene.add(d.root); this.hero = d;
    D.sparks.emit({ pos: _w.set(d.root.position.x, 0.6, d.root.position.z), n: 20, color: 0xffffff, color2: 0xffd84a, speed: 1.6, up: 1.4, grav: 0, life: 0.6, size: 0.12, spread: 0.4 });
  },
  placeBuilding(id, shown) {
    const D = View.dio, b = BLD[id], m = buildingModel(id);
    m.g.position.set(b.x, shown ? 0 : -3, b.y); m.g.traverse((o) => { if (o.isMesh) o.userData.pick = { bld: id }; });
    D.scene.add(m.g); this.objs.push(m.g); this.blds[id] = m;
    const tag = document.createElement('div'); tag.className = 'btag'; tag.innerHTML = `${b.icon} ${b.name}`; tag.style.display = shown ? '' : 'none';
    View.labelRoot.appendChild(tag); this.tags.push(tag); m.tag = tag;
  },
  rise(id) {
    const m = this.blds[id]; if (!m) return; META.buildings[id].shown = true; saveMeta();
    const D = View.dio, b = BLD[id];
    this.rising.push({ m, t: 0 });
    D.rig.shake(0.35); Sfx.play('blunt');
    D.puffs.emit({ pos: W3(b.x, b.y, 0.2), n: 26, color: 0xc8b890, color2: 0x9a8a6a, speed: 2.5, grav: 0, life: 1, size: 0.5, grow: 1, flat: true, spread: 0.8 });
    UI.banner(`${b.icon} ${b.name} 완성!`, 'info');
  },
  lootShower(loot) {
    const D = View.dio, list = [];
    for (const [m, n] of Object.entries(loot)) for (let k = 0; k < Math.min(n, 6); k++) list.push(m);
    list.slice(0, 26).forEach((m, k) => {
      const o = matProp(m); o.scale.setScalar(1.4);
      const a = Math.random() * 6.28, r = 0.4 + Math.random() * 1.1;
      o.position.set(this.center.x + Math.cos(a) * 0.3, 5 + k * 0.15, this.center.z - 0.4 + Math.sin(a) * 0.3);
      D.scene.add(o);
      this.shower.push({ o, v: new THREE.Vector3(Math.cos(a) * r * 1.2, 0, Math.sin(a) * r * 1.2), delay: k * 0.07, life: 9 });
    });
    for (const t of this.npcs) { const a = Math.random() * 6.28; t.goto(this.center.x + Math.cos(a) * 2.2, this.center.z + Math.sin(a) * 2.0, 'gather', 3.5, [this.center.x, this.center.z]); }
    Sfx.play('gem');
  },
  decide(t) {
    const n = t.n, others = this.npcs.filter((o) => o !== t), r = Math.random();
    const bad = others.filter((o) => (n.rel[o.n.id] || 0) <= -20);
    const ok = (x, z) => bad.every((o) => o.pos.distanceTo(W3(x, z)) > 3 && (!o.target || o.target.distanceTo(W3(x, z)) > 3));
    if (t.partner) { t.partner.partner = null; t.partner = null; }
    const w = this.workSpot(n);
    if (n.t.C <= -1 && r < 0.3) { t.goto(w[0], w[1], 'nap', 5); return; }
    const friends = others.filter((o) => (n.rel[o.n.id] || 0) >= 20 && !o.partner && o.state !== 'walk' && o.state !== 'gather');
    if (friends.length && r < 0.35 + n.t.X * 0.12) {
      const f = friends[Math.floor(Math.random() * friends.length)];
      for (let k = 0; k < 8; k++) {
        const a = Math.random() * 6.28, x = this.center.x + Math.cos(a) * 1.9, z = this.center.z + Math.sin(a) * 1.7, x2 = this.center.x + Math.cos(a + 0.5) * 1.9, z2 = this.center.z + Math.sin(a + 0.5) * 1.7;
        if (!ok(x, z)) continue;
        t.partner = f; f.partner = t; rel(n, f.n, 2); // 수다를 떨면 조금씩 가까워진다
        t.goto(x, z, 'chat', 6, [x2, z2]); f.goto(x2, z2, 'chat', 6, [x, z]); return;
      }
    }
    if (r < 0.6 + n.t.O * 0.1) {
      for (let k = 0; k < 10; k++) { const x = 1.5 + Math.random() * 8, z = 1.8 + Math.random() * 11; if (ok(x, z)) { t.goto(x, z, 'idle', 2 + Math.random() * 2); return; } }
    }
    const b = BLD[JOBS[n.job].b];
    if (!META.buildings[JOBS[n.job].b]) { t.goto(this.center.x + 1.5, this.center.z + 1.5, 'idle', 3); return; }
    t.goto(w[0] + (Math.random() - 0.5) * 0.4, w[1] + (Math.random() - 0.5) * 0.4, 'work', Math.max(2.5, 6 + n.t.C * 1.6), [b.x, b.y]);
  },
  bubble(t) {
    const n = t.n; let text;
    if (t.state === 'chat') text = pick(['💬', '😄', '💬 그러니까…', '하하!']);
    else if (t.state === 'nap') text = '💤';
    else if (t.state === 'work') text = n.mood <= -1 ? '😤 …' : pick(WORKTALK[JOBS[n.job].work]);
    else if (t.state === 'gather') text = n.t.X >= 1 ? '우와! 이게 다 뭐야!' : n.t.H <= -1 ? '하나쯤 없어져도…' : '수고했어요!';
    else text = talkLine(n);
    View.dio.labels.pop(W3(t.pos.x, t.pos.z, 1.75), '', { html: `<span class="bub">${text}</span>`, cls: 'gem', vx: 0, rise: 14, dur: 2.6 });
  },
  frame(sdt) {
    const D = View.dio, time = K.SHARED.uTime.value;
    for (const t of this.npcs) t.update(sdt, time);
    this.hearthFrame(sdt, time);
    if (Math.random() < sdt * (4 + (this.glow ?? 30) * 0.2)) D.sparks.emit({ pos: _w.set(BLD.plaza.x, 0.5, BLD.plaza.y), n: 1, color: 0xff8a2a, color2: 0xffe36a, speed: 0.4, up: 1 + (this.glow ?? 30) / 50, grav: 0.4, life: 0.9, size: 0.1, spread: 0.25 }); // 불이 밝을수록 불티가 많다
    for (const [id, m] of Object.entries(this.blds)) {
      const a = m.anim;
      if (a.disc) a.disc.material.opacity = 0.6 + Math.sin(time * 3) * 0.15;
      if (a.gems) a.gems.forEach((g) => { const k = g.userData.k, an = time * 1.2 + k * 2.09; g.position.set(Math.cos(an) * 0.35, 1.45 + Math.sin(time * 2 + k) * 0.08, Math.sin(an) * 0.35); g.rotation.y = time * 2; });
      if (a.ember) a.ember.scale.y = 0.8 + Math.sin(time * 9) * 0.2;
      if (a.smoke && Math.random() < sdt * 3) { const b = BLD[id]; D.puffs.emit({ pos: _w.set(b.x + a.smoke[0], a.smoke[1], b.y + a.smoke[2]), n: 1, color: 0xe8e4dc, color2: 0xbab4aa, speed: 0.2, up: 0.9, grav: 0, life: 2.2, size: 0.45, grow: 0.8, drag: 0.6 }); }
    }
    for (let i = this.rising.length - 1; i >= 0; i--) {
      const q = this.rising[i]; q.t = Math.min(1, q.t + sdt / 1.1); const k = q.t, e = 1 + 2.7 * Math.pow(k - 1, 3) + 1.7 * Math.pow(k - 1, 2);
      q.m.g.position.y = -3 * (1 - e); q.m.g.rotation.y = Math.sin(k * 20) * 0.03 * (1 - k); q.m.tag.style.display = '';
      if (Math.random() < 0.5) D.puffs.emit({ pos: _w.set(q.m.g.position.x + (Math.random() - 0.5) * 1.6, 0.1, q.m.g.position.z + (Math.random() - 0.5) * 1.4), n: 1, color: 0xc8b890, speed: 0.8, grav: 0, life: 0.8, size: 0.4, flat: true });
      if (k >= 1) this.rising.splice(i, 1);
    }
    for (let i = this.shower.length - 1; i >= 0; i--) {
      const s = this.shower[i]; if (s.delay > 0) { s.delay -= sdt; continue; }
      s.life -= sdt; const o = s.o; s.v.y -= 16 * sdt; o.position.addScaledVector(s.v, sdt); o.rotation.x += sdt * 5; o.rotation.z += sdt * 4;
      if (o.position.y < 0.02) { o.position.y = 0.02; if (Math.abs(s.v.y) > 1.5) { D.sparks.emit({ pos: o.position, n: 3, color: 0xfff2b0, speed: 1.5, life: 0.4, size: 0.1 }); if (Math.random() < 0.4) Sfx.play('pickgem'); } s.v.y *= -0.4; s.v.x *= 0.6; s.v.z *= 0.6; o.rotation.x *= 0.5; o.rotation.z *= 0.5; }
      if (s.life < 1) o.scale.setScalar(Math.max(0.01, s.life * 1.4));
      if (s.life <= 0) { D.scene.remove(o); this.shower.splice(i, 1); }
    }
    const s = {};
    for (const [id, m] of Object.entries(this.blds)) {
      if (m.tag.style.display === 'none') continue;
      D.labels.toScreen(_tv.set(m.g.position.x, m.g.position.y + (id === 'library' || id === 'gate' ? 2.6 : 1.8), m.g.position.z), s);
      m.tag.style.transform = `translate(${s.x.toFixed(1)}px,${s.y.toFixed(1)}px) translate(-50%,-100%)`;
      m.tag.classList.toggle('closed', !!META.closed[id]);
    }
  },
  tap(sx, sy) {
    if (this.busy) return;
    const ray = View.dio.ray(sx, sy), list = [];
    for (const o of this.objs) list.push(o); for (const t of this.npcs) list.push(t.d.root);
    const hits = ray.intersectObjects(list, true);
    for (const h of hits) {
      const p = h.object.userData.pick; if (!p) continue;
      if (p.npc) { const n = META.npcs.find((q) => q.id === p.npc); if (n) { this.npcCard(n); const t = this.npcs.find((q) => q.n === n); if (t) this.bubble(t); } return; }
      if (p.hero) { this.heroCard(); return; }
      if (p.visitor) { this.visitorCard(p.visitor); return; }
      if (p.grave) { this.graveInfo(p.grave); return; }
      if (p.bld) { this.open(p.bld); return; }
    }
  },
  open(id) {
    Sfx.play('ui');
    if (id === 'gate') this.gate(); else if (id === 'altar') this.altar(); else if (id === 'storage') this.storage(); else if (id === 'plaza') this.rest(); else this.craft(id);
  },
};
