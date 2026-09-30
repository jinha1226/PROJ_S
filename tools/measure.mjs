// 던전 밸런스 측정: 헤드리스 크롬에서 봇이 1구역(1~4층 + 5층 보스)을 여러 씨앗으로 돌고, docs/밸런스_기준.md §8 목표와 견준다.
// 게임 코드는 건드리지 않는다. 시간은 clock.step()으로 직접 돌린다(화면 루프는 끈다). 씨앗은 ?seed=N 으로 재현된다.
// 사용: node tools/measure.mjs [--seeds 20] [--start 1] [--rush] [--rest 0.6] [--potion 0.3] [--no-dodge] [--out 파일.json] [--quiet]
//   --rush     계단이 보이면 바로 내려간다(기본: 층을 다 탐험한 뒤 계단)
//   --rest     적이 없을 때 이 비율 아래면 쉰다(0이면 쉬지 않음)
//   --potion   이 비율 아래면 회복 물약을 마신다
//   --no-dodge 예고(마법사 표식·돌진 띠, 번개면 이어진 물까지)를 피하지 않는다
//   --choke    익숙한 사람 흉내: 근접 무리가 오면 가까운 좁은 곳(복도·문간)으로 물러나 받아낸다
//   --arena    판 대신 따로 떼어 낸 전투: 11×11 방에서 1구역 무리(층별)와 족장을 --reps번씩(기본 20) 상대한다(횃불 --arena-torch, 기본 100 고정)
//   --torch-lock  진단용: 횃불을 늘 가득 채운다(어둠을 뺀 전투 난이도·보스전 수치를 보려고)
//   --torch-rush N  횃불이 N 아래로 떨어지면 계단을 알 때 바로 내려간다(기본 40, 0이면 끔)
import { chromium } from 'playwright';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const argv = process.argv.slice(2);
const arg = (k, d) => { const i = argv.indexOf('--' + k); return i < 0 ? d : argv[i + 1] === undefined || argv[i + 1].startsWith('--') ? true : argv[i + 1]; };
const OPT = {
  seeds: +arg('seeds', 20), start: +arg('start', 1), rush: !!arg('rush', false), rest: +arg('rest', 0.6), potion: +arg('potion', 0.3),
  dodge: !arg('no-dodge', false), choke: !!arg('choke', false), torchRush: +arg('torch-rush', 40), out: arg('out', null), quiet: !!arg('quiet', false), floorCap: +arg('floor-cap', 600), fightGap: 1.5, arena: !!arg('arena', false), torchLock: !!arg('torch-lock', false), reps: +arg('reps', 20), arenaTorch: +arg('arena-torch', 100),
};

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const server = http.createServer((req, res) => {
  const p = path.join(root, decodeURIComponent(new URL(req.url, 'http://x').pathname));
  if (!p.startsWith(root) || !fs.existsSync(p) || fs.statSync(p).isDirectory()) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'content-type': p.endsWith('.js') ? 'text/javascript' : p.endsWith('.css') ? 'text/css' : p.endsWith('.png') ? 'image/png' : 'text/html; charset=utf-8' }); fs.createReadStream(p).pipe(res);
});
await new Promise((r) => server.listen(0, r));
const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });

/* ---------------- 페이지 안에서 도는 봇: 한 판(1구역 끝 또는 죽음)까지 ---------------- */
async function botRun(opt) {
  const g = window.__game, G = g.G, U = g.UI, C = g.clock;
  const EL = await import('/js/core/elements.js'), ST = await import('/js/core/state.js'), FOV = await import('/js/core/fov.js'), SP = await import('/js/core/space.js'), AI = await import('/js/core/ai.js'), PORTS = await import('/js/render/ports.js'), TR = await import('/js/data/terrain.js'), RT = (await import('/js/data/realtime.js')).RT;
  // 화면 루프를 끈다: 시간은 봇만 돌린다
  PORTS.ports.Loop = { frame() {} }; window.requestAnimationFrame = () => 0;
  for (const s of ['#screen', '#help', '#sheet', '#hud-overlay']) document.querySelector(s)?.classList.add('hidden');
  // 사건을 모은다(화면 대신)
  const ev = { dealt: 0, heroHits: 0, dodges: 0, blocks: 0 };
  ST.setListener((type, d) => {
    if (type === 'hit') { if (d.id === 0) ev.heroHits++; else ev.dealt += d.amt; }
    else if (type === 'dodge' && d.id === 0) ev.dodges++;
    else if (type === 'block') ev.blocks++;
  });
  const flush = () => { const q = g.TL.q; g.TL.reset(); for (const e of q) e.fn(); const a = g.Anim.q; g.Anim.clear(); for (const e of a) e.fn(); };
  const p = () => G.player, I = ST.I, cheb = (a, b, c, d) => Math.max(Math.abs(a - c), Math.abs(b - d));
  const invN = (k) => (G.inv.find((q) => q.k === k) || { n: 0 }).n;

  const run = { seed: opt.seed, floors: [], fights: [], outcome: null, death: null, boss: null, potions: 0, potionsFound: 0, maxHp0: p().max, weapon: G.eq.weapon && G.eq.weapon.base, dmgBy: {}, hitsBy: {}, heal: { potion: 0, rest: 0, regen: 0 }, clock: 0, level: 1 };
  let fl = null, fight = null, noFoeTicks = 0, exploreDone = false, lastHp = p().hp, drankTick = false, lastLamps = 0, lastHealN = invN('heal'), dodgeT = 0;
  const seenHurt = new WeakSet();
  const startFloor = () => {
    fl = { zf: G.zf, boss: !!G.bossFloor, c0: G.clock, t0: G.stats.turns, torch0: G.torch, lamps: 0, lampsOnFloor: G.lamps ? G.lamps.size : 0, fights: 0, kills0: G.stats.kills, cells: 0, restT: 0, foes: G.ents.filter((e) => e.alive && ST.isFoe(e) && !e.npc).length, hp0: p().hp, max: p().max };
    exploreDone = false; lastLamps = G.lamps ? G.lamps.size : 0; U.stopAuto();
  };
  const endFloor = () => {
    Object.assign(fl, { sec: +(G.clock - fl.c0).toFixed(2), steps: G.stats.turns - fl.t0, torch1: +G.torch.toFixed(1), kills: G.stats.kills - fl.kills0, hp1: p().hp, restT: +fl.restT.toFixed(2) });
    run.floors.push(fl);
  };
  const closeFight = () => {
    if (!fight) return;
    const f = fight; fight = null;
    Object.assign(f, { sec: +(f.last - f.c0).toFixed(2), kills: G.stats.kills - f.k0, hpEnd: p().hp, dealt: ev.dealt - f.dealt0, heroHits: ev.heroHits - f.hits0, dodges: ev.dodges - f.dodge0 });
    f.lossPct = +(100 * (f.hp0 - f.hpMin) / f.max).toFixed(1); // 최저점까지 잃은 HP(최대 HP 대비)
    f.takenPct = +(100 * f.taken / f.max).toFixed(1); // 받은 피해 합(회복 무시)
    f.netPct = +(100 * (f.hp0 - f.hpEnd) / f.max).toFixed(1);
    delete f.dealt0; delete f.hits0; delete f.dodge0; delete f.k0; delete f.last; delete f.choke; delete f.chokeWait;
    run.fights.push(f); fl.fights++;
  };
  startFloor();

  const dangerCells = () => {
    const d = new Set();
    for (const e of G.ents) {
      if (!e.alive || !ST.isFoe(e)) continue;
      if (e.cast) for (const [x, y] of e.cast.tiles) { d.add(I(x, y)); if (e.elem === 'bolt') for (const j of EL.conductSet(x, y).seen) d.add(j); }
      if (e.charge) for (const [x, y] of AI.chargePath(e, e.charge.dx, e.charge.dy)) d.add(I(x, y));
    }
    for (let i = 0; i < G.fire.length; i++) if (G.fire[i]) d.add(i);
    return d;
  };
  const goDir = (tx, ty) => { const [px, py] = SP.posOf(p()); const dx = tx - px, dy = ty - py, L = Math.hypot(dx, dy) || 1; C.setIntent([dx / L, dy / L], false); };
  let chaseT = 0, chaseId = null, noPathT = 0, ignoreUntil = -1;

  const MAX_TICKS = 20 * 60 * 40; // 흐른 시간 40분이면 포기
  let tick = 0;
  while (tick++ < MAX_TICKS) {
    const P = p();
    if (G.over || !P.alive) { run.outcome = 'death'; break; }
    const ignoring = G.clock < ignoreUntil, here = I(P.x, P.y), foes = ignoring ? [] : FOV.visibleFoes().filter((e) => !e.npc);
    drankTick = false;
    // 보스
    const boss = G.bossId >= 0 ? G.ents.find((e) => e.id === G.bossId) : null;
    if (boss && !run.boss && FOV.visibleFoes().includes(boss)) run.boss = { c0: G.clock, hp0: P.hp, max: P.max, hpMin: P.hp, taken: 0, potions: 0, bossHp: boss.max, killed: false };
    if (run.boss && !run.boss.done && boss && !boss.alive) { Object.assign(run.boss, { killed: true, done: true, sec: +(G.clock - run.boss.c0).toFixed(2), hpEnd: P.hp }); run.outcome = 'boss'; break; }
    // 물약
    if (P.hp < P.max * opt.potion && invN('heal') > 0) { g.act(() => g.useItem('heal')); flush(); run.potions++; drankTick = true; if (fight) fight.potions++; if (run.boss && !run.boss.done) run.boss.potions++; }

    if (foes.length) {
      U.explore = false; U.travel = null; if (G.resting) C.setRest(false);
      noFoeTicks = 0;
      if (!fight) fight = { floor: G.zf, boss: !!G.bossFloor, c0: G.clock, hp0: P.hp, max: P.max, hpMin: P.hp, taken: 0, potions: 0, k0: G.stats.kills, dealt0: ev.dealt, hits0: ev.heroHits, dodge0: ev.dodges, foes: [...new Set(foes.map((e) => e.boss || e.type))], n: foes.length, torch: +G.torch.toFixed(0), lv: G.level || 1 };
      else { for (const e of foes) { const k = e.boss || e.type; if (!fight.foes.includes(k)) fight.foes.push(k); } fight.n = Math.max(fight.n, foes.length); }
      fight.last = G.clock;
      const danger = opt.dodge ? dangerCells() : new Set();
      const tgt = foes.slice().sort((a, b) => cheb(a.x, a.y, P.x, P.y) - cheb(b.x, b.y, P.x, P.y))[0];
      if (danger.has(here) || dodgeT > 0) {
        // 예고 안: 위험하지 않은 이웃 칸으로(적 쪽에 가까운 칸을 먼저)
        if (danger.has(here)) dodgeT = 4;
        let best = null, bs = Infinity;
        for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
          if (!dx && !dy) continue; const x = P.x + dx, y = P.y + dy;
          if (!ST.standable(x, y) || ST.entAt(x, y) || danger.has(I(x, y))) continue;
          const s = cheb(x, y, tgt.x, tgt.y) + (dx && dy ? 0.1 : 0);
          if (s < bs) { bs = s; best = [x, y]; }
        }
        if (best && danger.has(here)) { C.setWalk(null); goDir(best[0], best[1]); run.dodgeMoves = (run.dodgeMoves || 0) + 1; }
        else if (!danger.has(here)) { dodgeT--; C.setIntent(null, true); }
        else C.setIntent(null, true);
      } else if (foes.some((e) => g.canHit(e))) {
        C.setWalk(null); C.setIntent(null, true); // 제자리에서 흘린다: 무기 박자마다 저절로 친다
      } else if (opt.choke && foes.filter((e) => e.awake && !['mage', 'archer', 'shaman'].includes(e.type)).length >= 2 && (fight.chokeWait || 0) < 3) {
        // 좁은 곳에서 받아내기: 이웃 8칸 중 설 수 있는 칸이 3개 이하인 가까운 칸
        if (fight.choke == null) {
          const cm = SP.costMap(P, 60, { seenOnly: true, passAllies: true }); let best = -1, bc = Infinity;
          for (let i = 0; i < cm.cost.length; i++) {
            if (!isFinite(cm.cost[i]) || cm.cost[i] > 6 || danger.has(i)) continue; const x = i % G.W, y = (i / G.W) | 0; if (!ST.standable(x, y)) continue;
            let open = 0; for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) if ((dx || dy) && ST.standable(x + dx, y + dy)) open++;
            if (open > 3) continue; const c = cm.cost[i] + open * 0.5; if (c < bc) { bc = c; best = i; }
          }
          fight.choke = best;
        }
        if (fight.choke >= 0 && fight.choke !== here) { if (!G.walk) { const cm = SP.costMap(P, 400, { seenOnly: true, passAllies: true }), pth = SP.pathPoints(P, cm, fight.choke % G.W, (fight.choke / G.W) | 0); C.setIntent(null, false); if (pth) C.setWalk(pth.pts.slice(1)); else { fight.choke = -1; C.setIntent(null, true); } } }
        else { C.setWalk(null); C.setIntent(null, true); fight.chokeWait = (fight.chokeWait || 0) + RT.tick; }
      } else {
        // 쫓기: 가장 가까운 적 칸까지 길
        if (chaseT-- <= 0 || chaseId !== tgt.id || !G.walk) {
          const cm = SP.costMap(P, 400, { seenOnly: true, passAllies: true, allow: I(tgt.x, tgt.y) }), pth = SP.pathPoints(P, cm, tgt.x, tgt.y);
          C.setIntent(null, false);
          if (pth) { C.setWalk(pth.pts.slice(1)); noPathT = 0; } else { C.setIntent(null, true); noPathT += 5; }
          if (noPathT >= 60) { ignoreUntil = G.clock + 5; noPathT = 0; run.ignored = (run.ignored || 0) + 1; } // 닿을 길이 없는 적(물 건너·막힌 복도): 잠시 못 본 척 지나간다
          chaseT = 4; chaseId = tgt.id;
        }
      }
    } else {
      if (fight && ++noFoeTicks > opt.fightGap / RT.tick) closeFight();
      else if (fight) C.setIntent(null, true); // 잠깐 보이지 않는다(모퉁이): 그대로 흘린다
      if (!fight) {
        C.setIntent(null, false);
        const onStairs = G.tile[here] === TR.T_STAIRS;
        if (onStairs && !G.bossFloor) {
          endFloor(); g.descend(); flush(); startFloor(); lastHp = p().hp; continue;
        }
        const stairsKnown = G.stairs != null && G.seen[G.stairs] && G.tile[G.stairs] === TR.T_STAIRS;
        if (G.resting) { /* 쉬는 중: afterTick이 멈춘다 */ }
        else if (U.underAttack()) { // 보이지 않는 곳(어둠·물속)에서 맞는다: 자리를 뜬다
          run.unseenTicks = (run.unseenTicks || 0) + 1;
          if (!G.walk) { if (stairsKnown) U.startTravel(G.stairs % G.W, (G.stairs / G.W) | 0); else { U.explore = true; U.exploreSkip ||= new Set(); U.exploreStep(); } }
          if (!G.walk) C.setIntent(null, true);
        }
        else if (opt.rest > 0 && P.hp < P.max * opt.rest && !U.underAttack() && !P.st.poison && !P.st.burn) { U.startRest(); if (!G.resting) C.setIntent(null, true); }
        else if (!U.explore && !G.walk) {
          const tooLong = G.clock - fl.c0 > opt.floorCap * 0.5, dim = opt.torchRush > 0 && G.torch < opt.torchRush;
          if (stairsKnown && (exploreDone || opt.rush || tooLong || dim)) { if (!U.startTravel(G.stairs % G.W, (G.stairs / G.W) | 0)) C.setIntent(null, true); }
          else if (ignoring) { // 보이는 적을 무시하는 동안: 탐험 대신 '그곳까지 걷기'로
            if (stairsKnown) U.startTravel(G.stairs % G.W, (G.stairs / G.W) | 0);
            else { U.exploreStep(); U.explore = false; if (G.walk) U.travel = { foes: FOV.visibleFoes().length }; }
            if (!G.walk) C.setIntent(null, true);
          }
          else if (!exploreDone) {
            if (P.hp <= P.max * 0.3) { U.startRest(); if (!G.resting) C.setIntent(null, true); } // 빈사라 탐험을 거절당한다: 쉰다
            else { U.startExplore(); if (!U.explore && !G.walk) { exploreDone = true; fl.doneAt = G.clock; } }
          } else { C.setIntent(null, true); if (G.clock - (fl.doneAt || 0) > 3) exploreDone = false; } // 계단을 모른다: 잠시 뒤 다시 탐험
        }
      }
    }
    if (G.resting) fl.restT += RT.tick;
    if (G.clock - fl.c0 > opt.floorCap) { run.outcome = 'stuck'; run.stuckInfo = { pos: [P.x, P.y], explore: U.explore, walk: G.walk && G.walk.length, exploreDone, resting: G.resting, stairsSeen: !!G.seen[G.stairs], stairs: [G.stairs % G.W, (G.stairs / G.W) | 0], intent: G.intent, foes: foes.length, hp: P.hp, awakeFoes: G.ents.filter((e) => e.alive && ST.isFoe(e) && e.awake && !e.npc).map((e) => [e.type, e.x, e.y, !!e.hidden]) }; break; }
    // 한 틱
    if (!C.flowing()) C.setIntent(null, true);
    const px0 = P.x, py0 = P.y;
    C.step(); flush();
    if (opt.torchLock) G.torch = G.torchMax;
    U.afterTick(1); flush();
    if (P.x !== px0 || P.y !== py0) fl.cells++;
    // 기록
    const P2 = p();
    const dh = P2.hp - lastHp;
    if (dh < 0) { if (fight) fight.taken -= dh; if (run.boss && !run.boss.done) run.boss.taken -= dh; }
    else if (dh > 0) { const k = drankTick ? 'potion' : G.resting ? 'rest' : 'regen'; run.heal[k] += dh; }
    if (dh !== 0 || tick % 6 === 0) { (run.trace ||= []).push([+G.clock.toFixed(2), P2.hp, +G.torch.toFixed(0), P2.x, P2.y, G.surf[I(P2.x, P2.y)], G.intent.dir ? 'mv' : G.intent.hold ? 'hold' : G.walk ? 'walk' : G.resting ? 'rest' : '-', FOV.visibleFoes().map((e) => `${e.type}@${e.x},${e.y}${e.cast ? '!cast' : ''}${e.charge ? '!chg' : ''}${e.awake ? '' : 'z'}`).join(' ')]); if (run.trace.length > 80) run.trace.shift(); }
    lastHp = P2.hp;
    if (fight) fight.hpMin = Math.min(fight.hpMin, P2.hp);
    if (run.boss && !run.boss.done) run.boss.hpMin = Math.min(run.boss.hpMin, P2.hp);
    for (const h of G.hurtLog || []) if (!seenHurt.has(h)) { seenHurt.add(h); run.dmgBy[h.who] = (run.dmgBy[h.who] || 0) + h.amt; run.hitsBy[h.who] = (run.hitsBy[h.who] || 0) + 1; }
    const ln = G.lamps ? G.lamps.size : 0; if (ln < lastLamps) fl.lamps += lastLamps - ln; lastLamps = ln;
    const hn = invN('heal'); if (hn > lastHealN) run.potionsFound += hn - lastHealN; lastHealN = hn;
  }
  if (!run.outcome) run.outcome = 'timeout';
  if (run.outcome === 'death') run.death = { floor: G.zf, boss: !!G.bossFloor, by: G.deathBy ? G.deathBy.who : null, kind: G.deathBy ? G.deathBy.kind : null };
  if (fight) { fight.last = G.clock; closeFight(); }
  endFloor();
  if (run.boss && !run.boss.done) Object.assign(run.boss, { sec: +(G.clock - run.boss.c0).toFixed(2), hpEnd: p().hp, done: true });
  if (run.boss) { run.boss.lossPct = +(100 * (run.boss.hp0 - run.boss.hpMin) / run.boss.max).toFixed(1); run.boss.takenPct = +(100 * run.boss.taken / run.boss.max).toFixed(1); }
  Object.assign(run, { clock: +G.clock.toFixed(1), level: G.level, maxHp1: p().max, kills: G.stats.kills, dealt: ev.dealt, heroHits: ev.heroHits, dodges: ev.dodges, potionsLeft: invN('heal') });
  return run;
}


/* ---------------- 따로 떼어 낸 전투(아레나): 층별 표준 무리 · 보스 ---------------- */
async function arenaRun(opt) {
  const g = window.__game, G = g.G, C = g.clock;
  const ST = await import('/js/core/state.js'), FOV = await import('/js/core/fov.js'), SP = await import('/js/core/space.js'), AI = await import('/js/core/ai.js'), EL = await import('/js/core/elements.js'), MG = await import('/js/core/mapgen.js'), PORTS = await import('/js/render/ports.js'), TR = await import('/js/data/terrain.js'), RT = (await import('/js/data/realtime.js')).RT, RNG = await import('/js/util/rng.js');
  PORTS.ports.Loop = { frame() {} }; window.requestAnimationFrame = () => 0;
  let dealt = 0; ST.setListener((type, d) => { if (type === 'hit' && d.id !== 0) dealt += d.amt; });
  const flush = () => { const q = g.TL.q; g.TL.reset(); for (const e of q) e.fn(); const a = g.Anim.q; g.Anim.clear(); for (const e of a) e.fn(); };
  const I = ST.I, cheb = (a, b, c, d) => Math.max(Math.abs(a - c), Math.abs(b - d));
  const F0 = TR.FLOORS[0];
  // 1구역 표준: 층마다 무리 6종(테마 0) + 5층 족장. 주인공은 §7.3 기준안(1구역 레벨 1~3, HP 30~34)
  const cases = [];
  for (const [type, cnt, extra] of F0.packs) cases.push({ name: `${type}×${cnt}${extra ? '+' + extra : ''}`, floor: 2, pack: [[type, cnt], ...(extra ? [[extra, 1]] : [])], hp: 32 });
  cases.push({ name: '족장(5층, HP 34, 물약 2)', floor: 5, boss: true, pack: [], hp: 34, potions: 2 });
  cases.push({ name: '족장(5층, HP 34, 물약 0)', floor: 5, boss: true, pack: [], hp: 34, potions: 0 });
  const weapons = ['sword', 'axe', 'mace', 'spear'], out = [];
  for (const cs of cases) for (let rep = 0; rep < opt.reps; rep++) {
    RNG.setR(RNG.mulberry32(1000 * (cases.indexOf(cs) + 1) + rep));
    const cx = 20, cy = 20, R = 5, p = G.player;
    G.zone = 1; G.zf = cs.floor; G.floor = cs.floor; G.theme = F0; G.bossFloor = !!cs.boss;
    for (let y = 0; y < G.H; y++) for (let x = 0; x < G.W; x++) { const i = I(x, y); G.tile[i] = Math.abs(x - cx) <= R && Math.abs(y - cy) <= R ? TR.T_FLOOR : TR.T_WALL; G.surf[i] = 0; G.fire[i] = 0; G.cloud[i] = 0; G.seen[i] = 1; }
    G.rooms = [{ x: cx - R, y: cy - R, w: 2 * R + 1, h: 2 * R + 1, cx, cy }];
    G.gear.clear(); G.chests.clear(); G.items.clear(); G.stones.clear(); G.mats.clear(); G.block = new Map(); if (G.lamps) G.lamps.clear();
    for (const k of Object.keys(G.eq)) G.eq[k] = null; G.eq.weapon = g.makeGear(weapons[rep % 4], { known: true }); G.eq.body = g.makeGear('body_cloth', { known: true });
    G.heroBase = cs.hp; G.level = 99; G.xp = 0; G.inv = cs.potions ? [{ k: 'heal', n: cs.potions }] : [];
    p.alive = true; for (const k in p.st) p.st[k] = 0; p.shield = 0; G.over = false; G.hurtLog = []; G.torch = opt.arenaTorch;
    G.ents = [p]; SP.setPos(p, cx - 3, cy); g.refreshStats(); p.hp = p.max;
    const free = () => { for (let t = 0; t < 200; t++) { const x = cx + 1 + Math.floor(RNG.rand() * R), y = cy - R + Math.floor(RNG.rand() * (2 * R + 1)); if (!ST.entAt(x, y)) return [x, y]; } return [cx + 3, cy]; };
    if (cs.boss) { const [x, y] = [cx + 4, cy]; const b = MG.mkBoss('chief', x, y); b.awake = true; G.ents.push(b); G.bossId = b.id; } else G.bossId = -1;
    for (const [type, n] of cs.pack) for (let k = 0; k < n; k++) { const [x, y] = free(); const e = MG.mkEnemy(type, x, y, F0); e.awake = true; e.hidden = false; G.ents.push(e); }
    C.initClock(); g.computeFOV(); dealt = 0;
    const hp0 = p.hp; let hpMin = p.hp, taken = 0, last = p.hp, pots = 0, tick = 0;
    while (tick++ < 20 * 90) {
      if (!p.alive || G.over) break;
      const foes = G.ents.filter((e) => e.alive && ST.isFoe(e));
      if (!foes.length) break;
      if (cs.boss && !G.ents.find((e) => e.id === G.bossId).alive) break; // 족장이 쓰러지면 끝(남은 부하는 세지 않는다)
      if (p.hp < p.max * opt.potion && G.inv.length && G.inv[0].n > 0) { g.act(() => g.useItem('heal')); flush(); pots++; }
      const here = I(p.x, p.y), danger = new Set();
      if (opt.dodge) for (const e of foes) { if (e.cast) for (const [x, y] of e.cast.tiles) { danger.add(I(x, y)); if (e.elem === 'bolt') for (const j of EL.conductSet(x, y).seen) danger.add(j); } if (e.charge) for (const [x, y] of AI.chargePath(e, e.charge.dx, e.charge.dy)) danger.add(I(x, y)); }
      const tgt = foes.slice().sort((a, b) => cheb(a.x, a.y, p.x, p.y) - cheb(b.x, b.y, p.x, p.y))[0];
      if (danger.has(here)) {
        let best = null, bs = Infinity;
        for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) { if (!dx && !dy) continue; const x = p.x + dx, y = p.y + dy; if (!ST.standable(x, y) || ST.entAt(x, y) || danger.has(I(x, y))) continue; const sc = cheb(x, y, tgt.x, tgt.y); if (sc < bs) { bs = sc; best = [x, y]; } }
        if (best) { C.setWalk(null); const [px, py] = SP.posOf(p), dx = best[0] - px, dy = best[1] - py, L = Math.hypot(dx, dy) || 1; C.setIntent([dx / L, dy / L], false); } else C.setIntent(null, true);
      } else if (foes.some((e) => g.canHit(e))) { C.setWalk(null); C.setIntent(null, true); }
      else if (tick % 5 === 1 || !G.walk) { const cm = SP.costMap(p, 400, { seenOnly: true, passAllies: true, allow: I(tgt.x, tgt.y) }), pth = SP.pathPoints(p, cm, tgt.x, tgt.y); C.setIntent(null, false); if (pth) C.setWalk(pth.pts.slice(1)); else C.setIntent(null, true); }
      if (!C.flowing()) C.setIntent(null, true);
      C.step(); flush(); G.torch = opt.arenaTorch;
      if (p.hp < last) taken += last - p.hp; last = p.hp; hpMin = Math.min(hpMin, p.hp);
    }
    out.push({ case: cs.name, boss: !!cs.boss, weapon: weapons[rep % 4], sec: +(tick * RT.tick).toFixed(2), lossPct: +(100 * (hp0 - hpMin) / p.max).toFixed(1), takenPct: +(100 * taken / p.max).toFixed(1), dead: !p.alive, potions: pots, dps: +(dealt / Math.max(0.05, tick * RT.tick)).toFixed(2), dtps: +(taken / Math.max(0.05, tick * RT.tick)).toFixed(2) });
  }
  return out;
}

/* ---------------- 판 돌리기 ---------------- */
if (OPT.arena) {
  const page = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 1, hasTouch: true });
  await page.addInitScript(() => { try { localStorage.clear(); } catch (_) { /* 없음 */ } });
  await page.goto(`http://127.0.0.1:${server.address().port}/index.html?seed=1`);
  await page.waitForFunction(() => !!window.__game, null, { timeout: 30000 });
  await page.tap('#btn-start'); await page.waitForFunction(() => window.__game.Game.mode === 'town', null, { timeout: 30000 }); await page.waitForTimeout(300);
  await page.evaluate(() => { const g = window.__game; document.querySelector('#sheet').classList.add('hidden'); g.META.hero = g.newHero(); g.enterDungeon(1); });
  const res = await page.evaluate(arenaRun, OPT);
  await browser.close(); server.close();
  const md = (a) => { const b = a.slice().sort((x, y) => x - y), m = b.length >> 1; return +(b.length % 2 ? b[m] : (b[m - 1] + b[m]) / 2).toFixed(1); };
  const q = (a, k) => a.slice().sort((x, y) => x - y)[Math.min(a.length - 1, Math.floor(k * a.length))];
  console.log(`## 아레나(11×11 방, 횃불 ${OPT.arenaTorch} 고정, 무기 장검·손도끼·철퇴·창 돌림, 물약 < ${OPT.potion * 100}%, 예고 피하기 ${OPT.dodge ? '켬' : '끔'}) · 경우마다 ${OPT.reps}번\n`);
  console.log('| 상대 | 흐른 시간 중앙(초) | 최저점 손실 중앙 % | 10–90% | 받은 피해 합 중앙 % | 사망 | 내 DPS | 받는 DPS | 목표 |\n| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | --- |');
  for (const name of [...new Set(res.map((r) => r.case))]) { const a = res.filter((r) => r.case === name), L = a.map((r) => r.lossPct); console.log(`| ${name} | ${md(a.map((r) => r.sec))} | ${md(L)} | ${q(L, 0.1)}–${q(L, 0.9)} | ${md(a.map((r) => r.takenPct))} | ${a.filter((r) => r.dead).length}/${a.length} | ${md(a.map((r) => r.dps))} | ${md(a.map((r) => r.dtps))} | ${a[0].boss ? '30~60초, 50~90%' : '5~15초, 15~35%'} |`); }
  const wp = {}; for (const r of res.filter((r) => !r.boss)) (wp[r.weapon] ||= []).push(r.lossPct); console.log(`\n- 무기별 일반 무리 최저점 손실 중앙 %: ${Object.entries(wp).map(([k, v]) => `${k} ${md(v)}`).join(' · ')}`);
  if (OPT.out) fs.writeFileSync(path.resolve(OPT.out), JSON.stringify({ opt: OPT, arena: res }, null, 1));
  process.exit(0);
}

const runs = [];
const t0 = performance.now();
for (let s = OPT.start; s < OPT.start + OPT.seeds; s++) {
  const page = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 1, hasTouch: true });
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.addInitScript(() => { try { localStorage.clear(); } catch (_) { /* 없음 */ } });
  await page.goto(`http://127.0.0.1:${server.address().port}/index.html?seed=${s}`);
  await page.waitForFunction(() => !!window.__game, null, { timeout: 30000 });
  await page.tap('#btn-start'); await page.waitForFunction(() => window.__game.Game.mode === 'town', null, { timeout: 30000 }); await page.waitForTimeout(300);
  await page.evaluate(() => { const g = window.__game; document.querySelector('#sheet').classList.add('hidden'); g.META.hero = g.newHero(); g.enterDungeon(1); });
  let run;
  try { run = await page.evaluate(botRun, { ...OPT, seed: s }); } catch (e) { run = { seed: s, outcome: 'error', error: String(e).slice(0, 300), floors: [], fights: [] }; }
  run.errors = errors.slice(0, 3);
  runs.push(run);
  await page.close();
  if (!OPT.quiet) {
    const b = run.boss;
    console.log(`seed ${s}: ${run.outcome}${run.death ? ` (${run.death.floor}층 ${run.death.by})` : ''} · 층 ${run.floors.length} · 흐른 ${run.clock}s · 전투 ${run.fights.length} · 물약 ${run.potions}/${run.potionsFound} · Lv${run.level} · ${run.weapon}${b ? ` · 보스 ${b.sec}s ${b.lossPct}%${b.killed ? ' 처치' : ''}` : ''}${run.error ? ' · ' + run.error : ''}${run.errors.length ? ' · 오류 ' + run.errors[0] : ''}  [${((performance.now() - t0) / 1000).toFixed(0)}s]`);
  }
}
await browser.close(); server.close();

/* ---------------- 모으기 ---------------- */
const med = (a) => { if (!a.length) return NaN; const b = a.slice().sort((x, y) => x - y), m = b.length >> 1; return b.length % 2 ? b[m] : (b[m - 1] + b[m]) / 2; };
const mean = (a) => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : NaN);
const pct = (a, q) => { if (!a.length) return NaN; const b = a.slice().sort((x, y) => x - y); return b[Math.min(b.length - 1, Math.floor(q * b.length))]; };
const f1 = (v) => (Number.isFinite(v) ? (+v.toFixed(1)).toString() : '-');
const row = (name, a, target = '') => console.log(`| ${name} | ${a.length} | ${f1(med(a))} | ${f1(mean(a))} | ${f1(pct(a, 0.1))}–${f1(pct(a, 0.9))} | ${target} |`);

const ok = runs.filter((r) => r.outcome !== 'error');
const allNormFloors = ok.flatMap((r) => r.floors.filter((f, k) => !f.boss && k < r.floors.length - 1)); // 끝까지 간 일반 층
const fights = ok.flatMap((r) => r.fights.filter((f) => !f.boss));
const realFights = fights.filter((f) => f.taken > 0 || f.kills > 0);
const bosses = ok.map((r) => r.boss).filter(Boolean);
const deaths = ok.filter((r) => r.outcome === 'death');

console.log(`\n## 결과: ${ok.length}판 (씨앗 ${OPT.start}~${OPT.start + OPT.seeds - 1}, ${OPT.rush ? '계단 서두름' : '층 전체 탐험'}, 쉬기 < ${OPT.rest * 100}%, 물약 < ${OPT.potion * 100}%, 예고 피하기 ${OPT.dodge ? '켬' : '끔'}, 좁은 곳 ${OPT.choke ? '켬' : '끔'}, 횃불 < ${OPT.torchRush}이면 계단${OPT.torchLock ? ', 횃불 고정(진단)' : ''}) · ${((performance.now() - t0) / 1000).toFixed(0)}초\n`);
console.log('| 지표 | n | 중앙값 | 평균 | 10–90% | 목표(§8) |\n| --- | ---: | ---: | ---: | --- | --- |');
row('도달 층', ok.map((r) => r.floors.length));
row('일반 층 흐른 시간(초)', allNormFloors.map((f) => f.sec), '30~45초');
row('일반 층 걸음(0.3초)', allNormFloors.map((f) => f.steps), '100~150걸음');
row('일반 층 쉬기 시간(초)', allNormFloors.map((f) => f.restT));
row('일반 층 전투 수', allNormFloors.map((f) => f.fights));
row('층 끝 횃불', allNormFloors.map((f) => f.torch1));
row('층당 등잔 사용', allNormFloors.map((f) => f.lamps), '층마다 1번쯤');
row('전투 흐른 시간(초)', realFights.map((f) => f.sec), '5~15초');
row('전투 최저점 손실 %', realFights.map((f) => f.lossPct), '15~35%');
row('전투 받은 피해 합 %', realFights.map((f) => f.takenPct));
row('전투 순손실 %(끝-시작)', realFights.map((f) => f.netPct));
row('전투당 처치', realFights.map((f) => f.kills));
row('보스전 시간(초)', bosses.map((b) => b.sec), '30~60초');
row('보스전 최저점 손실 %', bosses.map((b) => b.lossPct), '50~90%');
row('보스전 받은 피해 합 %', bosses.map((b) => b.takenPct));
row('보스전 물약', bosses.map((b) => b.potions), '1~2개');
row('판당 물약 사용', ok.map((r) => r.potions));
row('판당 물약 주움', ok.map((r) => r.potionsFound));
row('최종 레벨', ok.map((r) => r.level));
row('판 흐른 시간(초)', ok.map((r) => r.clock), '150~225초(5층)');
const inRange = (a, lo, hi) => (a.length ? `${Math.round((100 * a.filter((v) => v >= lo && v <= hi).length) / a.length)}%` : '-');
console.log(`\n- 전투 최저점 손실이 15~35% 안: ${inRange(realFights.map((f) => f.lossPct), 15, 35)}, 15% 미만: ${inRange(realFights.map((f) => f.lossPct), -1, 14.99)}, 35% 초과: ${inRange(realFights.map((f) => f.lossPct), 35.01, 999)} (전투 ${realFights.length}개, 피해 0 전투 ${realFights.filter((f) => f.taken === 0).length}개)`);
console.log(`- 사망률(1구역): ${deaths.length}/${ok.length} = ${ok.length ? Math.round((100 * deaths.length) / ok.length) : '-'}% (목표: 처음 30~50%, 익숙 ≤10%) · 보스 처치 ${bosses.filter((b) => b.killed).length}/${ok.length} · 막힘 ${ok.filter((r) => r.outcome === 'stuck').length} · 시간초과 ${ok.filter((r) => r.outcome === 'timeout').length}`);
if (deaths.length) console.log(`- 죽은 곳: ${deaths.map((r) => `${r.death.floor}층${r.death.boss ? '(보스)' : ''} ${r.death.by}`).join(', ')}`);
const heal = { potion: 0, rest: 0, regen: 0 }; for (const r of ok) for (const k in heal) heal[k] += r.heal ? r.heal[k] : 0;
const taken = ok.reduce((a, r) => a + Object.values(r.dmgBy || {}).reduce((x, y) => x + y, 0), 0);
console.log(`- 회복 합(판 평균): 자동 회복 ${f1(heal.regen / ok.length)} · 쉬기 ${f1(heal.rest / ok.length)} · 물약 ${f1(heal.potion / ok.length)} / 받은 피해 ${f1(taken / ok.length)} (레벨업 회복은 자동 회복에 섞임)`);
const by = {}; const hb = {}; for (const r of ok) { for (const [k, v] of Object.entries(r.dmgBy || {})) by[k] = (by[k] || 0) + v; for (const [k, v] of Object.entries(r.hitsBy || {})) hb[k] = (hb[k] || 0) + v; }
console.log(`- 피해 준 것(판 평균, 피해/맞은 횟수): ${Object.entries(by).sort((a, b) => b[1] - a[1]).map(([k, v]) => `${k} ${f1(v / ok.length)}/${f1(hb[k] / ok.length)}`).join(' · ')}`);
const ft = realFights.reduce((a, f) => a + f.sec, 0), dealt = realFights.reduce((a, f) => a + f.dealt, 0), tk = realFights.reduce((a, f) => a + f.taken, 0);
console.log(`- 일반 전투 전체: 내가 준 피해 ${f1(dealt / ft)}/초 · 받은 피해 ${f1(tk / ft)}/초 · 회피 ${realFights.reduce((a, f) => a + f.dodges, 0)}번 · 예고 피하기 이동 틱 ${ok.reduce((a, r) => a + (r.dodgeMoves || 0), 0)}`);
const byType = {}; for (const f of realFights) { const k = f.foes.slice().sort().join('+'); (byType[k] ||= []).push(f); }
console.log('\n| 전투 구성(보인 적 종류) | 수 | 시간 중앙(초) | 최저점 손실 중앙 % | 최대 % |\n| --- | ---: | ---: | ---: | ---: |');
for (const [k, a] of Object.entries(byType).sort((x, y) => y[1].length - x[1].length).slice(0, 12)) console.log(`| ${k} | ${a.length} | ${f1(med(a.map((f) => f.sec)))} | ${f1(med(a.map((f) => f.lossPct)))} | ${f1(Math.max(...a.map((f) => f.lossPct)))} |`);
if (OPT.out) { fs.writeFileSync(path.resolve(OPT.out), JSON.stringify({ opt: OPT, runs }, null, 1)); console.log(`\n저장: ${OPT.out}`); }
