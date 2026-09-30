// 장비 시스템 확인 목록(docs/설계_아이템_장비.md §15)을 헤드리스 크롬에서 검사한다.
// 사용: node tests/gear.mjs
import { chromium } from 'playwright';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const outDir = path.join(root, 'test-results'); fs.mkdirSync(outDir, { recursive: true });
const server = http.createServer((req, res) => {
  const p = path.join(root, decodeURIComponent(new URL(req.url, 'http://x').pathname));
  if (!p.startsWith(root) || !fs.existsSync(p) || fs.statSync(p).isDirectory()) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'content-type': p.endsWith('.js') ? 'text/javascript' : p.endsWith('.css') ? 'text/css' : 'text/html; charset=utf-8' }); fs.createReadStream(p).pipe(res);
});
await new Promise((r) => server.listen(0, r));
const results = [];
const check = (name, ok, info = '') => { results.push(!!ok); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${info ? '  — ' + info : ''}`); };
const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const page = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 1, hasTouch: true });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message)); page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
await page.addInitScript(() => { try { localStorage.clear(); } catch (_) { /* 없음 */ } });
await page.goto(`http://127.0.0.1:${server.address().port}/index.html`);
await page.waitForFunction(() => !!window.__game, null, { timeout: 30000 });
await page.tap('#btn-start'); await page.waitForTimeout(1800);
const hide = () => page.evaluate(() => { document.querySelector('#sheet').classList.add('hidden'); document.querySelector('#screen').classList.add('hidden'); });
const npc = (job, t = {}) => ({ id: 'n' + Math.random().toString(36).slice(2), name: '테스트' + Math.floor(Math.random() * 1e5), job, t: { H: 0, E: 0, X: 0, A: 0, C: 0, O: 0, ...t }, mood: 0, rel: {}, look: { skin: 0xd9a47a, hair: 0x3a2618, cloth: 0x4e443a } });
await page.evaluate(`window.mk = ${npc.toString()}`);

// 1. 새 게임: 원경은 어둡고 밝기 12~20, 방문 확률은 밝기를 따른다
const s1 = await page.evaluate(() => { const g = window.__game, T = g.Town; return { glow: g.hearthGlow(), dark: T.lands.every((L) => L.k === 0), recall: g.META.items.recall || 0, v: g.META.v }; });
check('새 게임: 원경 어둠 · 밝기 12~20 · 귀환 두루마리 0', s1.dark && s1.glow >= 12 && s1.glow <= 20 && s1.recall === 0 && s1.v >= 5, JSON.stringify(s1));
const vc = await page.evaluate(() => { const g = window.__game, M = g.META; const keep = M.npcs.slice(), lit = M.lit.slice(); M.lit = [true, true, false, false]; M.glowMods = []; const rate = (n) => { M.npcs = keep.slice(); for (let k = 0; k < n; k++) M.npcs.push(mk('cook')); let c = 0; for (let r = 0; r < 400; r++) { M.visitors = []; c += g.rollVisitors().length; } return c / 400; }; const lo = rate(0), hi = rate(3); M.npcs = keep; M.visitors = []; M.lit = lit; return { lo: +lo.toFixed(2), hi: +hi.toFixed(2), none: (() => { M.npcs = []; M.visitors = []; let n = 0; for (let r = 0; r < 50; r++) n += g.rollVisitors().length; M.npcs = keep; return n; })() }; });
check('방문 확률은 밝기를 따르고, 밝기 20 이하면 아무도 안 온다', vc.hi > vc.lo && vc.none === 0, JSON.stringify(vc));

// 2. 1구역 조각 → 호숫가 원경 · 호숫가 출신 방문자
await page.evaluate(() => { const g = window.__game; g.META.hero = g.newHero(); g.META.cleared[0] = true; g.Town.enter({ reason: 'boss', zone: 1, zf: 3, loot: {}, npcs: [], first: true, kills: 3 }); });
const done = () => page.waitForFunction(() => !window.__game.Town.busy && !document.querySelector('#sheet').classList.contains('hidden'), null, { timeout: 90000 });
await done(); await hide();
const s2 = await page.evaluate(() => { const g = window.__game, M = g.META; M.glowMods = []; M.npcs.forEach((n) => { n.mood = 0; }); M.npcs.push(mk('cook', { A: 1 })); const glow = g.hearthGlow(); const jobs = new Set(); for (let r = 0; r < 300; r++) { M.visitors = []; for (const v of g.rollVisitors()) jobs.add(v.npc.job + ':' + v.npc.from); } M.visitors = []; M.npcs.pop(); return { lit: M.lit[0], land: g.Town.lands[0].k, glow, jobs: [...jobs], recall: M.items.recall }; });
check('1구역 조각: 호숫가가 밝아지고 호숫가 사람들이 온다 · 보스 첫 처치 두루마리', s2.lit && s2.land > 0.9 && s2.jobs.length && s2.jobs.every((j) => /^(fisher|boatman|cook):lake$/.test(j)) && s2.recall === 1, JSON.stringify(s2));

// 3. 요청은 성격을 따르고, 채워야 받아들일 수 있다
const s3 = await page.evaluate(() => { const g = window.__game, M = g.META, keep = M.npcs.slice(), out = {};
  const v = (t) => ({ npc: mk('fisher', t), waits: 0, req: null });
  const hon = v({ H: 2 }); hon.req = 'H+'; M.npcs = keep.map((n) => ({ ...n, t: { ...n.t, H: -1 } })); out.honNo = g.requestState(hon).ok; M.npcs[0].t.H = 2; out.honYes = g.requestState(hon).ok;
  const soc = v({ X: 2 }); soc.req = 'X+'; M.npcs = keep.slice(0, 2); out.socNo = g.requestState(soc).ok; M.npcs = [...keep, mk('cook'), mk('cook')]; out.socYes = g.requestState(soc).ok;
  const greedy = v({ H: -2 }); greedy.req = 'H-'; M.mats = { 약초: 1 }; out.greedNo = g.requestState(greedy).ok; M.mats = { 약초: 2, 광석: 2 }; out.greedYes = g.requestState(greedy).ok;
  M.visitors.push(greedy); const r = g.acceptVisitor(greedy); out.paid = (M.mats.약초 || 0) + (M.mats.광석 || 0); out.joined = M.npcs.includes(greedy.npc) && !!r;
  M.npcs = keep; return out; });
check('요청: 정직·외향·욕심 — 채우면 받아들이고 값을 치른다', !s3.honNo && s3.honYes && !s3.socNo && s3.socYes && !s3.greedNo && s3.greedYes && s3.paid === 1 && s3.joined, JSON.stringify(s3));

// 4. 까칠한 방문자 · 두 번 기다리면 세 번째 귀환에 떠난다
const s4 = await page.evaluate(() => { const g = window.__game, M = g.META, keep = M.npcs.slice();
  const foe = mk('cook', { A: -2, C: -2 }), vis = { npc: mk('miner', { A: -2, C: 2 }), waits: 0, req: 'A-' };
  M.npcs = [...keep, foe]; const no = g.requestState(vis).ok; M.npcs = keep.map((n) => ({ ...n, t: { ...n.t, A: 2, C: 2 } })); const yes = g.requestState(vis).ok; M.npcs = keep;
  M.visitors = [vis]; const seen = []; for (let k = 0; k < 3; k++) { g.processReturn({ reason: 'recall', zone: 1, zf: 1, loot: {} }); seen.push(M.visitors.includes(vis)); }
  M.visitors = []; return { no, yes, seen }; });
check('원만성 낮은 방문자: 궁합 나쁜 주민이 있으면 거절 · 세 번째 귀환에 떠남', !s4.no && s4.yes && s4.seen.join() === 'true,true,false', JSON.stringify(s4));

// 5. 주민 상한이면 방문자가 오지 않는다
const s5 = await page.evaluate(() => { const g = window.__game, M = g.META, keep = M.npcs.slice(); const cap = 4 + M.lit.filter(Boolean).length * 2; M.npcs = keep.slice(); while (M.npcs.length < cap) M.npcs.push(mk('cook', { A: 2 })); let n = 0; for (let r = 0; r < 100; r++) { M.visitors = []; n += g.rollVisitors().length; } M.npcs = keep; M.visitors = []; return { cap, n }; });
check('주민 상한(4 + 조각×2)이면 방문자 없음', s5.n === 0 && s5.cap === 6, JSON.stringify(s5));

// 6. 숨은 방: 맞는 스킬로만 열린다
await page.evaluate(() => { const g = window.__game; document.querySelector('#sheet').classList.add('hidden'); g.enterDungeon(1); });
await page.waitForTimeout(800);
const s6 = await page.evaluate(() => { const g = window.__game, G = g.G; let tries = 0;
  while ((!G.block || !G.block.size) && tries++ < 60) { G.zf = 1; g.regen(); }
  const [i, kind] = [...G.block.entries()][0], x = i % G.W, y = (i / G.W) | 0, want = { thorn: 'fire', water: 'frost', gate: 'bolt', rubble: 'push' }[kind], wrong = want === 'fire' ? 'bolt' : 'fire';
  const bad = g.openHidden(x, y, wrong);
  // 입구 앞 방 바닥에 서서 스킬로 조준 → 발동
  const p = G.player, nb = [[1, 0], [-1, 0], [0, 1], [0, -1]].map(([dx, dy]) => [x + dx, y + dy]).find(([a, b]) => G.tile[b * G.W + a] === 1 && G.room[b * G.W + a] >= 0);
  G.ents = [p]; p.x = nb[0]; p.y = nb[1]; const sid = { fire: 'r_fire', frost: 'r_freeze', bolt: 'r_shock', push: 'r_push' }[want]; Object.assign(G.slots[0], { stone: sid, color: g.STONE[sid].color, cd: 0 }); g.computeFOV(); g.View.buildFloor();
  g.UI.stoneBtn(0); const valid = g.UI.valid.has(i); g.UI.tapTarget(x, y); g.UI.tapTarget(x, y);
  const ok = G.tile[i] !== 0;
  return { tries, kind, bad, valid, ok, left: G.block.size }; });
check('숨은 방: 틀린 스킬로는 안 열리고 맞는 스킬로 조준해 연다', !s6.bad && s6.valid && s6.ok && s6.left === 0, JSON.stringify(s6));

// 10. 귀환 두루마리: 보스 층 금지 · 한 턴 뒤 귀환
const s10 = await page.evaluate(() => { const g = window.__game, G = g.G; const drain = () => { };
  G.inv.push({ k: 'recall', n: 1 }); G.bossFloor = true; const boss = g.useItem('recall'); G.bossFloor = false;
  g.act(() => g.useItem('recall')); drain(); const armed = G.pendingReturn || G.over ? 'early' : 'wait';
  const C = g.clock; C.setIntent(null, true); for (let k = 0; k < 6; k++) C.step(); C.setIntent(null, false); drain(); // 실시간: 한 턴(0.3초)이 흘러야 빛이 모인다
  return { boss, armed, pending: G.pendingReturn || (G.over ? 'gone' : null) }; });
await page.waitForFunction(() => window.__game.Game.mode === 'town', null, { timeout: 30000 }).catch(() => {});
const s10b = await page.evaluate(() => ({ mode: window.__game.Game.mode }));
await done();
check('귀환 두루마리: 보스 층 불가 · 빛이 모인 한 턴 뒤 정착지로', s10.boss === false && s10b.mode === 'town', JSON.stringify({ ...s10, ...s10b }));
await hide();

// 7. 쓰러지면 자원자 창 → 고른 주민의 일터가 빈다
await page.evaluate(() => { const g = window.__game, M = g.META; M.npcs = [mk('blacksmith', { E: -2 }), mk('herbalist', { H: 2 }), mk('scholar', { A: 1 })]; M.npcs.forEach((n) => { for (const m of M.npcs) if (m !== n) n.rel[m.id] = 30; }); M.hero = g.newHero(); g.enterDungeon(1); g.returnToTown('death'); });
await done();
await page.evaluate(() => document.querySelector('#sheet .close')?.click());
await page.waitForTimeout(500);
const s7a = await page.evaluate(() => ({ vols: document.querySelectorAll('#sheet [data-v]').length, need: window.__game.META.needSuccessor }));
await page.evaluate(() => document.querySelector('#sheet [data-v="0"]').click());
await page.waitForFunction(() => !window.__game.Town.busy && window.__game.META.hero, null, { timeout: 60000 });
const s7 = await page.evaluate(() => { const M = window.__game.META; return { hero: M.hero && M.hero.name, job: M.hero && M.hero.job, perk: M.hero && M.hero.perk, smith: M.npcs.some((n) => n.job === 'blacksmith'), n: M.npcs.length, moods: M.npcs.map((n) => n.mood) }; });
check('자원자 창 → 고른 주민이 등불지기, 일터가 빈다', s7a.vols === 2 && s7a.need && s7.job === 'blacksmith' && !s7.smith && s7.n === 2 && s7.perk === 'E-' && s7.moods.every((m) => m < 0), JSON.stringify({ ...s7a, ...s7 }));
await hide();

// 9. 4구역 조각 → 새벽
await page.evaluate(() => { const g = window.__game, M = g.META; M.lit = [true, true, true, false]; M.cleared = [true, true, true, true]; g.Town.enter({ reason: 'boss', zone: 4, zf: 3, loot: {}, npcs: [], first: true, kills: 1 }); });
await done();
await page.evaluate(() => document.querySelector('#sheet .close')?.click());
await page.waitForTimeout(600);
const s9 = await page.evaluate(() => ({ ending: window.__game.META.ending, screen: !document.querySelector('#screen').classList.contains('hidden') && !!document.querySelector('.ending.dawn') }));
check('4구역 조각 → 새벽 결말', s9.ending === 'dawn' && s9.screen, JSON.stringify(s9));
await page.screenshot({ path: path.join(outDir, 'story-dawn.png') });
await hide();

// 8. 주민 0명일 때 쓰러지면 꺼진 불 · 저장이 지워진다
await page.evaluate(() => { const g = window.__game, M = g.META; M.npcs = []; M.newNpcs = []; M.hero = g.newHero(); g.enterDungeon(1); g.returnToTown('death'); });
await done();
await page.evaluate(() => document.querySelector('#sheet .close')?.click());
await page.waitForTimeout(600);
const s8 = await page.evaluate(() => ({ dark: !!document.querySelector('.ending.dark'), saved: localStorage.getItem('torch-meta-v3') }));
check('주민 0명 사망 → 꺼진 불 · 저장 삭제', s8.dark && s8.saved === null, JSON.stringify(s8));
await page.screenshot({ path: path.join(outDir, 'story-dark.png') });

check('페이지 오류 없음', errors.length === 0, errors.slice(0, 3).join(' | '));
await browser.close(); server.close();
const bad = results.filter((r) => !r).length;
console.log(bad ? `\n${bad}개 실패` : `\n모두 통과 (${results.length})`);
process.exit(bad ? 1 : 0);
