import { distance, labStepToward, sweep } from './space.js';

const ALLIES = [
  { id: 'guard', name: '수호자', role: 'guard', hp: 52, max: 52, x: 4, y: 7, color: '#66aaff' },
  { id: 'sword', name: '검사', role: 'sword', hp: 38, max: 38, x: 4, y: 9, color: '#f27a71' },
  { id: 'archer', name: '궁수', role: 'archer', hp: 29, max: 29, x: 2, y: 6, color: '#9bd96d' },
  { id: 'healer', name: '치유사', role: 'healer', hp: 30, max: 30, x: 2, y: 10, color: '#e3d8bd' },
];
const HERO = { id: 'hero', name: '등불지기', role: 'hero', hp: 40, max: 40, x: 3, y: 8, color: '#ffd478' };
const BOSS = { id: 'boss', name: '잊힌 파수병', role: 'boss', hp: 120, max: 120, x: 11, y: 8, color: '#e78a54', boss: true };
const DATA = { bolt: { name: '번개', cd: 4 }, water: { name: '물벼락', cd: 4 }, counter: { name: '반격 자세', cd: 5 } };
export const MODES = { A: '턴제', B: '격자 실시간', C: '완전 실시간' };
const now = () => performance.now();
/** C: 걷는 속도(칸/초)와 한 번 행동하는 간격(초). 걷기는 매 프레임, 판단·공격만 간격마다 */
const SPEED = { boss: 1.5, add: 1.9, hero: 3.8 };
const PERIOD = { boss: 1.2, add: 0.75 };
const period = (u) => PERIOD[u.role] || 0.6;
/** 턴제에서 한 방이 보이고 나서 다음 유닛이 움직이기까지(ms). 근접은 휘두름, 원거리는 날아가는 시간까지 */
const PACE = { slash: 300, blunt: 320, arrow: 380, orb: 360, water: 420, bolt: 460, counter: 420, cleave: 650, scatter: 650 };

export class Battle {
  constructor(mode, changed = () => {}) {
    this.mode = mode; this.changed = changed;
    this.units = [structuredClone(HERO), ...structuredClone(ALLIES), structuredClone(BOSS)];
    this.hero = this.units[0]; this.boss = this.units[5];
    this.command = 'focus'; this.target = 'boss'; this.skill = null;
    this.round = 0; this.elapsed = 0; this.speed = 1; this.paused = mode !== 'A'; this.autoPause = true;
    this.tele = null; this.bossActs = 0; this.summoned = false; this.wet = new Set(); this.guard = 0;
    this.cooldowns = { bolt: 0, water: 0, counter: 0 }; this.timers = Object.fromEntries(this.units.map((u) => [u.id, mode === 'C' ? Math.random() * period(u) : 0])); // C는 모두 한 박자에 치지 않게 흩어 둔다
    this.events = ['잊힌 파수병이 길을 막았다.']; this.finished = null; this.busy = false; this.cancelled = false;
    this.metrics = { inputs: 0, pauses: 0, pausedSeconds: 0, waitingSeconds: 0, dodged: 0, hit: 0, fallen: 0, started: now() };
    this._lastDanger = false; this.onFx = null; this.pace = 0;
  }
  /** 화면 연출에 알린다(전투 규칙은 바꾸지 않는다). pace는 턴제에서 다음 유닛까지 기다릴 시간(ms) */
  fx(type, o = {}, pace = 0) { this.pace = Math.max(this.pace, pace); if (!this.cancelled) this.onFx?.(type, o); }
  takePace() { const ms = Math.max(180, this.pace); this.pace = 0; return ms; }
  get living() { return this.units.filter((u) => u.hp > 0); }
  get party() { return this.units.slice(0, 5); }
  get foes() { return this.units.filter((u) => u.role === 'boss' || u.role === 'add').filter((u) => u.hp > 0); }
  get phase() { return this.boss.hp > 72 ? 1 : this.boss.hp > 36 ? 2 : 3; }
  log(line) { this.events.unshift(line); this.events.length = Math.min(4, this.events.length); this.changed(); }
  input() { this.metrics.inputs++; }
  setCommand(key) {
    if (key === 'auto' && this.command === 'auto') key = 'focus';
    this.command = key; this.input();
    this.log(({ focus: '한곳을 노린다.', scatter: '흩어진다.', gather: '등불지기 곁으로 모인다.', retreat: '뒤로 물러난다.', auto: '등불지기도 자동으로 싸운다.' })[key]);
    if (this.mode === 'A' && key === 'auto' && !this.finished && !this.busy) this.heroTurn({ type: 'auto' });
  }
  setPause(value, automatic = false) {
    if (this.mode === 'A' || this.finished || this.paused === value) return;
    this.paused = value;
    if (value) this.metrics.pauses++;
    this.log(value ? (automatic ? '파수병이 움직인다. 시간이 멈췄다.' : '시간이 멈췄다.') : '시간이 흐른다.');
  }
  selectSkill(key) {
    if (this.cooldowns[key] || this.finished) return false;
    this.skill = this.skill === key ? null : key; this.input(); this.changed(); return true;
  }
  direct(point) {
    if (this.finished) return;
    this.input();
    const foe = this.foes.find((u) => distance(u, point) < (u.boss ? 0.9 : 0.6));
    if (foe) this.target = foe.id;
    if (this.mode === 'A') {
      if (this.busy) return;
      this.heroTurn(this.skill ? { type: 'skill', key: this.skill, point } : foe ? { type: 'attack', target: foe.id } : { type: 'move', point });
    } else {
      this.order = this.skill ? { type: 'skill', key: this.skill, point } : foe ? { type: 'attack', target: foe.id } : { type: 'move', point };
      this.skill = null; this.changed();
    }
  }
  heroTurn(action) {
    if (this.finished || this.busy || this.cancelled) return;
    this.busy = true; this.round++;
    for (const k of Object.keys(this.cooldowns)) this.cooldowns[k] = Math.max(0, this.cooldowns[k] - 1);
    this.heroAct(action);
    this.skill = null; this.checkEnd();
    if (this.finished) { this.busy = false; return; }
    const queue = [...this.party.slice(1), this.boss, ...this.units.filter((u) => u.role === 'add')];
    let i = 0;
    const next = () => {
      if (this.cancelled) return;
      if (this.finished || i >= queue.length) { this.busy = false; this.checkEnd(); this.changed(); if (this.command === 'auto' && !this.finished) setTimeout(() => this.heroTurn({ type: 'auto' }), 220); return; }
      const unit = queue[i++];
      if (unit.hp > 0) unit.boss ? this.bossAct() : unit.role === 'add' ? this.addAct(unit) : this.allyAct(unit);
      this.checkEnd(); this.changed();
      if (!this.finished) setTimeout(next, this.takePace()); else this.busy = false;
    };
    setTimeout(next, this.takePace()); this.changed();
  }
  heroAct(action = { type: 'auto' }) {
    const h = this.hero; if (h.hp <= 0) return;
    if (action.type === 'wait') { this.log('등불지기가 숨을 고른다.'); return; }
    if (action.type === 'auto') action = { type: 'attack', target: this.target, auto: true };
    if (action.type === 'skill') {
      const target = this.foes.find((u) => distance(u, action.point) < 1.1) || this.boss;
      if (this.cooldowns[action.key]) return;
      if (action.key === 'water') { this.wet.add(target.id); this.damage(target, 5, '물벼락', { from: h, kind: 'water' }); }
      else if (action.key === 'bolt') { const bonus = this.wet.has(target.id) ? 8 : 0; this.wet.delete(target.id); this.damage(target, 9 + bonus, bonus ? '젖은 몸에 번개' : '번개', { from: h, kind: 'bolt', crit: !!bonus }); }
      else { this.guard = 2; this.fx('guard', { unit: h }, 300); this.log('등불지기가 반격 자세를 잡았다.'); }
      this.cooldowns[action.key] = DATA[action.key].cd; return;
    }
    if (action.type === 'move') { this.moveTo(h, action.point); return; }
    const target = this.foes.find((u) => u.id === action.target) || this.boss;
    if (distance(h, target) <= 1.6) this.damage(target, 5, '장검', { from: h, kind: 'slash' });
    else if (this.mode !== 'C' || !action.auto || this.command === 'auto') this.moveTo(h, target, false, 1.3); // C는 적을 탭했거나 자동일 때만 쫓아간다(피한 뒤 저절로 돌아가지 않게)
  }
  /** A·B는 한 칸 옮기고, C는 목표만 정해 두고 tick이 매 프레임 걸어간다. stop: 목표에서 멈출 거리 */
  moveTo(unit, point, away = false, stop = point.hp !== undefined ? 1.3 : 0.1) {
    if (this.mode === 'C') { unit.goal = { to: point, away, stop, left: away ? 0.7 : 4 }; return; }
    labStepToward(unit, point, this.living, false, away);
    this.changed();
  }
  damage(unit, n, source, how = {}) {
    if (unit.hp <= 0) return;
    const amount = Math.max(1, Math.round(n)), phase = this.phase;
    unit.hp = Math.max(0, unit.hp - amount);
    this.fx('hit', { unit, amount, source, from: how.from, kind: how.kind, crit: how.crit, killed: unit.hp === 0 }, PACE[how.kind] || 260);
    if (unit === this.boss && unit.hp > 0 && this.phase !== phase) this.fx('phase', { phase: this.phase }, 500);
    this.log(`${source} · ${unit.name} −${amount}`);
    if (unit.hp === 0 && unit.role !== 'boss' && unit.role !== 'add' && unit.role !== 'hero') this.metrics.fallen++;
    if (unit === this.boss && unit.hp > 0 && unit.hp <= 72 && !this.summoned) this.summon();
    this.checkEnd();
  }
  summon() {
    this.summoned = true;
    for (const [i, x] of [1, 14].entries()) {
      const u = { id: `add${i}`, name: '해골 궁수', role: 'add', hp: 14, max: 14, x, y: 8, color: '#b5b9c6' };
      this.units.push(u); this.timers[u.id] = this.mode === 'C' ? Math.random() * period(u) : 0;
    }
    this.fx('summon', { units: this.units.filter((u) => u.role === 'add') }, 500);
    this.log('벽 틈에서 해골 궁수 둘이 나온다.');
  }
  allyAct(u) {
    if (u.hp <= 0) return;
    const boss = this.boss;
    if (this.command === 'scatter' && this.tele?.type === 'scatter') {
      const near = this.party.filter((p) => p !== u && p.hp > 0).sort((a, b) => distance(a, u) - distance(b, u))[0];
      if (near && distance(near, u) < 2.2) { this.moveTo(u, near, true); return; }
    }
    if (this.command === 'gather' && distance(u, this.hero) > 2.3) { this.moveTo(u, this.hero, false, 2); return; }
    if (this.command === 'retreat' && u.x > 3) { this.moveTo(u, { x: 2, y: u.y }); return; }
    if (u.role === 'healer') {
      const patient = this.party.filter((p) => p.hp > 0).sort((a, b) => a.hp / a.max - b.hp / b.max)[0];
      if (patient && patient.hp < patient.max * 0.78) { const was = patient.hp; patient.hp = Math.min(patient.max, patient.hp + 8); this.fx('heal', { from: u, unit: patient, amount: patient.hp - was }, 300); this.log(`치유사가 ${patient.name}을 돌봤다.`); return; }
    }
    if (u.role === 'guard' && this.bossActs % 4 === 0) { this.taunt = 2; this.fx('taunt', { from: u }, 260); this.log('수호자가 파수병을 끌어당겼다.'); }
    const target = this.foes.find((e) => e.id === this.target) || this.foes.find((e) => e.role === 'add') || boss;
    const range = u.role === 'archer' || u.role === 'healer' ? 6.5 : 1.7;
    if (distance(u, target) <= range) {
      const amount = u.role === 'sword' ? 5 : u.role === 'archer' ? 4 : u.role === 'guard' ? 3 : 2;
      this.damage(target, amount, u.name, { from: u, kind: ({ sword: 'slash', archer: 'arrow', guard: 'blunt', healer: 'orb' })[u.role] });
    } else this.moveTo(u, target, false, range - 0.3);
  }
  addAct(u) {
    const targets = this.party.filter((p) => p.hp > 0);
    if (!targets.length) return;
    const t = targets.sort((a, b) => distance(a, u) - distance(b, u))[0];
    if (distance(u, t) <= 7) this.damage(t, 3, '해골 궁수', { from: u, kind: 'arrow' }); else this.moveTo(u, t, false, 6.5);
  }
  bossAct() {
    if (this.boss.hp <= 0) return;
    this.bossActs++;
    if (this.tele) { this.resolveTele(); return; }
    const live = this.party.filter((u) => u.hp > 0);
    if (!live.length) return;
    const target = this.taunt > 0 && this.party[1].hp > 0 ? this.party[1] : live.sort((a, b) => distance(a, this.boss) - distance(b, this.boss))[0];
    this.taunt = Math.max(0, (this.taunt || 0) - 1);
    if (distance(this.boss, target) > 3.2) { this.moveTo(this.boss, target, false, 2.9); return; }
    this.boss.goal = null; // 기믹을 예고하면 제자리에서 힘을 모은다
    const type = this.bossActs % 3 === 0 ? 'scatter' : 'cleave';
    this.tele = { type, target: target.id, aim: { x: target.x, y: target.y }, at: this.party.filter((u) => u.hp > 0).map((u) => ({ id: u.id, x: u.x, y: u.y })), remaining: type === 'scatter' ? 2 : 1.5 };
    this.fx('tele', { type, target }, 360);
    this.log(type === 'scatter' ? '흩어져라! 발밑에 원이 번진다.' : `파수병이 ${target.name}을 노린다.`);
    if (this.mode === 'B' && this.autoPause) this.setPause(true, true);
  }
  inDanger(unit, tele = this.tele) {
    if (!tele) return false;
    if (tele.type === 'scatter') return tele.at.some((p) => distance(p, unit) < 1.15);
    const vx = tele.aim.x - this.boss.x, vy = tele.aim.y - this.boss.y, len = Math.hypot(vx, vy) || 1;
    const dx = unit.x - this.boss.x, dy = unit.y - this.boss.y, d = Math.hypot(dx, dy);
    return d <= 3.25 && (dx * vx + dy * vy) / (d * len || 1) > 0.58;
  }
  resolveTele() {
    const tele = this.tele; if (!tele) return;
    const hit = this.party.filter((u) => u.hp > 0 && this.inDanger(u, tele));
    const dodge = this.party.filter((u) => u.hp > 0 && !this.inDanger(u, tele)).length;
    this.metrics.dodged += dodge; this.metrics.hit += hit.length;
    this.fx('slam', { type: tele.type, aim: tele.aim, at: tele.at, hit, dodge: this.party.filter((u) => u.hp > 0 && !hit.includes(u)) }, 650);
    for (const u of hit) {
      const overlap = tele.type === 'scatter' && this.party.some((v) => v !== u && v.hp > 0 && distance(u, v) < 1.5);
      let dmg = tele.type === 'cleave' ? 12 : overlap ? 12 : 6;
      if (u.role === 'guard') dmg = Math.ceil(dmg * 0.55);
      if (u === this.hero && this.guard) { dmg = Math.ceil(dmg * 0.4); this.damage(this.boss, 7, '반격', { from: u, kind: 'counter' }); this.guard = 0; }
      this.damage(u, dmg, tele.type === 'cleave' ? '내려치기' : '흩어져라', { from: this.boss, kind: tele.type });
    }
    this.log(hit.length ? `${hit.length}명 피격 · ${dodge}명 회피` : '모두 피했다.');
    this.tele = null;
  }
  tick(dt) {
    if (this.finished) return;
    if (this.mode === 'A') { if (this.busy) this.metrics.waitingSeconds += dt; return; }
    if (this.paused) { this.metrics.pausedSeconds += dt; return; }
    const delta = Math.min(dt, 0.06) * this.speed;
    this.elapsed += delta;
    if (this.elapsed >= 90) { this.end('격노'); return; }
    for (const k of Object.keys(this.cooldowns)) this.cooldowns[k] = Math.max(0, this.cooldowns[k] - delta);
    if (this.tele) { this.tele.remaining -= delta; if (this.tele.remaining <= 0) this.resolveTele(); }
    if (this.mode === 'C') this.walk(delta);
    for (const u of this.units) {
      if (u.hp <= 0 || this.finished) continue;
      const p = period(u);
      this.timers[u.id] += delta;
      if (this.timers[u.id] < p) continue;
      this.timers[u.id] -= this.mode === 'C' ? p * (0.85 + Math.random() * 0.3) : p;
      if (u.role === 'hero') {
        if (this.order?.type === 'move') this.moveTo(u, this.order.point);
        else if (this.order?.type === 'skill') { this.heroAct(this.order); this.order = null; }
        else this.heroAct(this.order || { type: 'auto' });
      } else if (u.role === 'boss') { if (!this.tele) this.bossAct(); }
      else if (u.role === 'add') this.addAct(u);
      else this.allyAct(u);
    }
    this.checkEnd();
  }
  /** C: 목표가 있는 유닛은 매 프레임 조금씩 걷는다(벽·몸은 sweep이 막는다) */
  walk(dt) {
    for (const u of this.living) {
      const g = u.goal; if (!g) continue;
      g.left -= dt;
      const d = distance(u, g.to);
      if (g.left <= 0 || (g.to.hp !== undefined && g.to.hp <= 0) || (!g.away && d <= g.stop)) { u.goal = null; continue; }
      const step = Math.min((SPEED[u.role] || 2.6) * dt, g.away ? Infinity : d - g.stop), k = (g.away ? -step : step) / (d || 1);
      Object.assign(u, sweep(u, (g.to.x - u.x) * k, (g.to.y - u.y) * k, this.living));
    }
  }
  continuousMove(dx, dy, dt) {
    if (this.mode !== 'C' || this.paused || this.finished || this.hero.hp <= 0) return;
    this.hero.goal = null; if (this.order?.type === 'move') this.order = null; // 조이스틱이 탭 이동보다 먼저
    Object.assign(this.hero, sweep(this.hero, dx * dt * 3.8, dy * dt * 3.8, this.living));
  }
  checkEnd() {
    if (this.finished) return;
    if (this.boss.hp <= 0) this.end('승리');
    else if (this.party.every((u) => u.hp <= 0)) this.end('전멸');
    else if (this.mode === 'A' && this.round >= 30 && !this.busy) this.end('격노');
  }
  end(result) {
    if (this.finished) return;
    this.finished = result;
    this.log(`레이드 ${result}.`);
    this.changed();
  }
  record() {
    return { mode: this.mode, result: this.finished, seconds: Math.round((now() - this.metrics.started) / 1000), ...this.metrics, fallen: this.metrics.fallen, round: this.round, date: new Date().toISOString() };
  }
}
