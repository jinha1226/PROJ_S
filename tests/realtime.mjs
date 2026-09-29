// 실시간 전환(docs/설계_실시간_전환.md)을 헤드리스 크롬에서 검사한다. 시간은 step()으로 돌려 결과가 늘 같다.
// 사용: node tests/realtime.mjs
import { chromium } from 'playwright';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
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
await page.tap('#btn-start'); await page.waitForTimeout(1500);
await page.evaluate(() => { const g = window.__game; document.querySelector('#sheet').classList.add('hidden'); g.META.hero = g.newHero(); g.enterDungeon(1); });
await page.waitForTimeout(1500);

// 아레나: 9×9 방(x, y = 11~19), 주인공 가운데(15, 15). 벽은 나머지 전부
await page.evaluate(async () => {
  const g = window.__game, G = g.G, T = await import('/js/data/terrain.js');
  window.M = { S: await import('/js/core/space.js'), T, C: await import('/js/core/clock.js'), R: await import('/js/data/realtime.js'), TB: (await import('/js/data/torch.js')).TORCH_BURN };
  window.arena = (foes = []) => {
    const cx = 15, cy = 15, p = G.player; document.querySelector('#sheet').classList.add('hidden');
    for (let y = 0; y < G.H; y++) for (let x = 0; x < G.W; x++) { const i = y * G.W + x; G.tile[i] = Math.abs(x - cx) <= 4 && Math.abs(y - cy) <= 4 ? T.T_FLOOR : T.T_WALL; G.surf[i] = 0; G.fire[i] = 0; G.cloud[i] = 0; G.seen[i] = 1; }
    p.x = cx; p.y = cy; p.px = cx; p.py = cy; p.hp = p.max = 40; p.shield = 0; p.alive = true; for (const k in p.st) p.st[k] = 0; G.over = false;
    G.gear.clear(); G.chests.clear(); G.items.clear(); G.stones.clear(); G.mats.clear(); G.block = new Map(); if (G.lamps) G.lamps.clear();
    G.ents = [p, ...foes.map(([x, y, o = {}]) => ({ id: G.nextId++, type: 'goblin', x: cx + x, y: cy + y, hp: 30, max: 30, atk: 0, alive: true, awake: true, face: [0, 1], cd: 0, cast: null, charge: null, aim: false, name: '허수아비', ...o, st: { wet: 0, frozen: 0, burn: 0, poison: 0, stun: 0, fear: 0, haste: 0, immune: 0, bleed: 0, frac: 0, vital: 0 } }))];
    for (const k of Object.keys(G.eq)) G.eq[k] = null; G.eq.weapon = g.makeGear('sword'); g.refreshStats(); G.ps.eva = 0; G.ps.block = 0; G.ps.torchSlow = 0; G.ps.torchCost = 0;
    if (window.M.C) window.M.C.initClock(); g.computeFOV(); return G;
  };
});

// ---------- 과제 1: 공간 ----------
const s1 = await page.evaluate(() => { const G = arena(), p = G.player, r = M.S.sweep(p, 10, 0); return { x: r.x, wall: r.wall }; });
check('공간: 벽 앞에서 멈춘다(벽 안쪽 면 − 반지름)', Math.abs(s1.x - 19.2) < 0.02 && s1.wall, JSON.stringify(s1));

const s2 = await page.evaluate(() => { const G = arena(); G.tile[15 * G.W + 20] = M.T.T_DOOR; const p = G.player; p.px = p.x = 19; let door = null; M.S.sweep(p, 2, 0, { onDoor: (x, y) => { door = [x, y]; } }); return door; });
check('공간: 닫힌 문에 닿으면 onDoor(20, 15)', s2 && s2[0] === 20 && s2[1] === 15, JSON.stringify(s2));

const s3 = await page.evaluate(() => { const G = arena([[2, 0]]), p = G.player, r = M.S.sweep(p, 3, 0); return { x: r.x, body: r.body && r.body.name }; });
check('공간: 몸끼리 겹치지 않는다(0.3 + 0.28)', Math.abs(s3.x - (17 - 0.58)) < 0.02 && s3.body === '허수아비', JSON.stringify(s3));

const s4 = await page.evaluate(() => { const G = arena(); for (let y = 11; y <= 18; y++) G.tile[y * G.W + 17] = M.T.T_WALL; const p = G.player, cm = M.S.costMap(p, 60, { seenOnly: true }), path = M.S.pathPoints(p, cm, 19, 15); return path && { end: path.pts[path.pts.length - 1], n: path.pts.length }; });
check('공간: 벽을 돌아가는 길(끝점 = 목표)', s4 && s4.end[0] === 19 && s4.end[1] === 15 && s4.n >= 3, JSON.stringify(s4));

// ---------- 과제 2: 시계 ----------
const c1 = await page.evaluate(() => { const G = arena(), c0 = G.clock, t0 = G.torch, n0 = G.stats.turns; M.C.setIntent(null, false); const n = M.C.advance(1); return { n, dc: G.clock - c0, dt: G.torch - t0, turns: G.stats.turns - n0 }; });
check('손을 떼면 멈춘다(시계·횃불·턴 그대로)', c1.n === 0 && c1.dc === 0 && c1.dt === 0 && c1.turns === 0, JSON.stringify(c1));

const c2 = await page.evaluate(() => { const G = arena(), c0 = G.clock; M.C.setIntent(null, true); const n = M.C.advance(1); return { n, dc: +(G.clock - c0).toFixed(3) }; });
check('한 프레임에 최대 3틱(0.15초)', c2.n === 3 && c2.dc === 0.15, JSON.stringify(c2));

const c3 = await page.evaluate(() => { const G = arena(), p = G.player; M.C.setIntent([1, 0], false); for (let k = 0; k < 20; k++) M.C.step(); return +(p.px - 15).toFixed(2); });
check('걷기 3.3칸/초(20틱 = 1초)', Math.abs(c3 - 3.3) < 0.06, String(c3));

const c4 = await page.evaluate(() => { const G = arena(); G.torch = 80; const n0 = G.stats.turns; M.C.setIntent(null, true); for (let k = 0; k < 20; k++) M.C.step(); return { turns: G.stats.turns - n0, burn: +(80 - G.torch).toFixed(2), tb: M.TB }; });
check('0.3초마다 옛 턴 한 번(1초 = 3턴, 횃불도 3턴어치)', c4.turns === 3 && c4.burn === +(3 * c4.tb).toFixed(2), JSON.stringify(c4));

const c5 = await page.evaluate(() => { const G = arena(); G.tile[15 * G.W + 20] = M.T.T_DOOR; const p = G.player; M.S.setPos(p, 19, 15); M.C.setIntent([1, 0], false); for (let k = 0; k < 6; k++) M.C.step(); return G.tile[15 * G.W + 20] === M.T.T_OPEN; });
check('닫힌 문으로 걸어가면 열린다', c5);

const c6 = await page.evaluate(() => { const G = arena(), n0 = G.inv.reduce((a, b) => a + b.n, 0); G.items.set(15 * G.W + 17, 'heal'); M.C.setIntent([1, 0], false); for (let k = 0; k < 14; k++) M.C.step(); const p = G.player; return { picked: !G.items.has(15 * G.W + 17), inv: G.inv.reduce((a, b) => a + b.n, 0) - n0, cell: [p.x, p.y], vis: G.vis[p.y * G.W + p.x] }; });
check('발밑 칸이 바뀌면 줍기·시야', c6.picked && c6.inv === 1 && c6.vis === 1, JSON.stringify(c6));

const c7 = await page.evaluate(() => { const G = arena([[1, 0]]), e = G.ents[1]; M.C.setIntent(null, true); for (let k = 0; k < 24; k++) M.C.step(); return e.hp; });
check('닿는 적을 저절로 친다(1단계 다리, 0.6초마다)', c7 < 30, String(c7));

const c8 = await page.evaluate(() => { const G = arena([[4, 0]]), e = G.ents[1], d0 = e.x - 15; M.C.setIntent(null, true); for (let k = 0; k < 6; k++) M.C.step(); return { d0, d1: e.x - 15 }; });
check('적은 걸음 박자(0.3초)마다 한 칸', c8.d1 === c8.d0 - 1, JSON.stringify(c8));

// 검토 초점 1~3
const f1 = await page.evaluate(() => { const G = arena(); M.C.setWalk([[18, 15]]); M.C.setIntent([1, 0], false); window.__game.genFloorForTest(); return { walk: G.walk, dir: G.intent.dir, px: G.player.px === G.player.x }; });
check('층을 옮기면 걷기·의도가 지워진다', f1.walk === null && f1.dir === null && f1.px, JSON.stringify(f1));

const f2 = await page.evaluate(async () => { const G = arena(), p = G.player, Cb = await import('/js/core/combat.js'); Cb.moveEnt(p, 13, 13); M.C.setIntent(null, true); M.C.step(); return [p.px, p.py, p.x, p.y]; });
check('옛 코드가 x, y만 바꿔도 위치가 따라간다', f2[0] === 13 && f2[1] === 13 && f2[2] === 13, JSON.stringify(f2));

const f3 = await page.evaluate(() => { const G = arena(), p = G.player; p.st.stun = 1; M.C.setIntent([1, 0], false); for (let k = 0; k < 6; k++) M.C.step(); return { stun: p.st.stun, moved: +(p.px - 15).toFixed(2) }; });
check('기절 중에는 못 걷지만 시간이 흘러 풀린다', f3.stun === 0 && f3.moved < 0.2, JSON.stringify(f3));

// (과제 2~5의 검사가 여기 이어진다)

check('페이지 오류 없음', errors.length === 0, errors.slice(0, 3).join(' | '));
await browser.close(); server.close();
const bad = results.filter((r) => !r).length;
console.log(bad ? `\n${bad}개 실패` : `\n모두 통과 (${results.length})`);
process.exit(bad ? 1 : 0);
