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
    p.hp = p.max = 40; G.hurt = false; G.hurtTurn = -9; // 장비 계산이 최대 HP를 바꾼 뒤에
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
check('걷기 4.0칸/초(20틱 = 1초)', Math.abs(c3 - 4.0) < 0.06, String(c3));

const c4 = await page.evaluate(() => { const G = arena(); G.torch = 80; const n0 = G.stats.turns; M.C.setIntent(null, true); for (let k = 0; k < 20; k++) M.C.step(); return { turns: G.stats.turns - n0, burn: +(80 - G.torch).toFixed(2), tb: M.TB }; });
check('0.3초마다 옛 턴 한 번(1초 = 3턴, 횃불도 3턴어치)', c4.turns === 3 && c4.burn === +(3 * c4.tb).toFixed(2), JSON.stringify(c4));

const c5 = await page.evaluate(() => { const G = arena(); G.tile[15 * G.W + 20] = M.T.T_DOOR; const p = G.player; M.S.setPos(p, 19, 15); M.C.setIntent([1, 0], false); for (let k = 0; k < 6; k++) M.C.step(); return G.tile[15 * G.W + 20] === M.T.T_OPEN; });
check('닫힌 문으로 걸어가면 열린다', c5);

const c6 = await page.evaluate(() => { const G = arena(), n0 = G.inv.reduce((a, b) => a + b.n, 0); G.items.set(15 * G.W + 17, 'heal'); M.C.setIntent([1, 0], false); for (let k = 0; k < 14; k++) M.C.step(); const p = G.player; return { picked: !G.items.has(15 * G.W + 17), inv: G.inv.reduce((a, b) => a + b.n, 0) - n0, cell: [p.x, p.y], vis: G.vis[p.y * G.W + p.x] }; });
check('발밑 칸이 바뀌면 줍기·시야', c6.picked && c6.inv === 1 && c6.vis === 1, JSON.stringify(c6));

const c7 = await page.evaluate(() => { const G = arena([[1, 0]]), e = G.ents[1]; M.C.setIntent(null, true); for (let k = 0; k < 24; k++) M.C.step(); return e.hp; });
check('닿는 적을 무기 박자마다 저절로 친다', c7 < 30, String(c7));

const c8 = await page.evaluate(() => { const G = arena([[4, 0]]), e = G.ents[1], d0 = e.x - 15; M.C.setIntent(null, true); for (let k = 0; k < 6; k++) M.C.step(); return { d0, d1: +(e.px - 15).toFixed(3) }; });
check('적은 칸이 아니라 연속 좌표로 다가온다(0.3초에 약 1칸)', c8.d1 < c8.d0 - 0.5 && c8.d1 !== Math.round(c8.d1), JSON.stringify(c8));

// 검토 초점 1~3
const f1 = await page.evaluate(() => { const G = arena(); M.C.setWalk([[18, 15]]); M.C.setIntent([1, 0], false); window.__game.genFloorForTest(); return { walk: G.walk, dir: G.intent.dir, px: G.player.px === G.player.x }; });
check('층을 옮기면 걷기·의도가 지워진다', f1.walk === null && f1.dir === null && f1.px, JSON.stringify(f1));

const f2 = await page.evaluate(async () => { const G = arena(), p = G.player, Cb = await import('/js/core/combat.js'); Cb.moveEnt(p, 13, 13); M.C.setIntent(null, true); M.C.step(); return [p.px, p.py, p.x, p.y]; });
check('옛 코드가 x, y만 바꿔도 위치가 따라간다', f2[0] === 13 && f2[1] === 13 && f2[2] === 13, JSON.stringify(f2));

const f3 = await page.evaluate(() => { const G = arena(), p = G.player; p.st.stun = 1; M.C.setIntent([1, 0], false); for (let k = 0; k < 19; k++) M.C.step(); const mid = +(p.px - 15).toFixed(2); for (let k = 0; k < 3; k++) M.C.step(); return { stun: p.st.stun, mid }; });
check('기절(1초) 중에는 못 걷지만 시간이 흘러 풀린다', f3.stun === 0 && f3.mid < 0.01, JSON.stringify(f3));

// ---------- 과제 3: 입력 ----------
const i1 = await page.evaluate(() => { const G = arena(), U = window.__game.UI; U.startTravel(18, 17); let n = 0; while (G.walk && n++ < 200) M.C.step(); const p = G.player; return { cell: [p.x, p.y], n }; });
check('탭한 곳까지 자동으로 걷는다', i1.cell[0] === 18 && i1.cell[1] === 17, JSON.stringify(i1));

const i2 = await page.evaluate(() => { const G = arena([[3, 3, { awake: true }]]), U = window.__game.UI; U.explore = true; M.C.setWalk([[11, 11]]); G.hurt = false; U.afterTick(1); return { explore: U.explore, walk: G.walk }; });
check('탐험은 적이 보이면 멈춘다', !i2.explore && i2.walk === null, JSON.stringify(i2));

const i3 = await page.evaluate(() => { const G = arena(), U = window.__game.UI, p = G.player; p.hp = 38; M.C.setIntent(null, false); U.startRest(); let n = 0; while (G.resting && n++ < 400) { M.C.advance(0.15); U.afterTick(1); } return { hp: p.hp, resting: G.resting, n }; });
check('쉬기: 손을 안 대도 흐르다가 다 나으면 멈춘다', i3.hp === 40 && !i3.resting, JSON.stringify(i3));

await page.evaluate(() => { arena(); window.__game.UI.syncAll(); });
// 조이스틱 칸(화면 아래 42%) 안에서 HUD가 아닌 캔버스가 받는 점
const jy = await page.evaluate(() => { for (let y = Math.round(innerHeight * 0.6); y < innerHeight; y += 8) if (document.elementFromPoint(195, y)?.tagName === 'CANVAS') return y; return null; });
await page.mouse.click(195, jy); await page.waitForTimeout(200);
const j1 = await page.evaluate(() => ({ block: window.__game.UI.joyTapBlock, ring: getComputedStyle(document.querySelector('#joy')).display }));
await page.evaluate(() => window.__game.UI.stopAuto()); // 짧은 탭은 그 칸으로 걷기일 수 있다
const jc0 = await page.evaluate(() => window.__game.G.clock);
await page.mouse.move(195, jy); await page.mouse.down(); await page.waitForTimeout(800);
const held = await page.evaluate(() => ({ clock: window.__game.G.clock, frozen: document.body.classList.contains('frozen') }));
await page.mouse.up(); await page.waitForTimeout(300);
const after = await page.evaluate(() => document.body.classList.contains('frozen'));
check('조이스틱: 짧은 탭은 탭으로 넘기고, 누르고 있으면 흐르고, 떼면 멈춘다', jy != null && !j1.block && j1.ring === 'none' && held.clock > jc0 && !held.frozen && after, JSON.stringify({ jy, j1, jc0, held, after }));

await page.evaluate(() => arena());
const k0 = await page.evaluate(() => [window.__game.G.player.px, window.__game.G.player.py]);
await page.keyboard.down('d'); await page.waitForFunction((x0) => window.__game.G.player.px - x0 > 0.3, k0[0], { timeout: 5000 }).catch(() => {}); await page.keyboard.up('d'); await page.waitForTimeout(150); // 헤드리스는 프레임 빠르기가 들쭉날쭉하다: 움직일 때까지 기다린다
const k1 = await page.evaluate(() => [window.__game.G.player.px, window.__game.G.player.py]);
check('이동 키를 누르는 동안 걷는다', Math.hypot(k1[0] - k0[0], k1[1] - k0[1]) > 0.3, JSON.stringify({ k0, k1 }));

// 검토 초점 4~5
const f4 = await page.evaluate(() => { arena(); const U = window.__game.UI; document.querySelector('#sheet').classList.remove('hidden'); U.joyKeys.add('d'); U.feedIntent(); const on = M.C.flowing(); U.joyKeys.clear(); document.querySelector('#sheet').classList.add('hidden'); U.feedIntent(); return on; });
check('창을 연 채 키를 누르고 있으면 흐르지 않는다', f4 === false);

const f5 = await page.evaluate(() => { arena(); const U = window.__game.UI; U.joyKeys.add('d'); dispatchEvent(new Event('blur')); U.feedIntent(); return { keys: U.joyKeys.size, flowing: M.C.flowing() }; });
check('포커스가 빠지면 눌린 키를 비운다', f5.keys === 0 && !f5.flowing, JSON.stringify(f5));

// ---------- 과제 4: 화면 ----------
await page.evaluate(() => arena());
await page.keyboard.down('d'); await page.waitForTimeout(1000);
const v1 = await page.evaluate(() => { const g = window.__game, ev = g.View.evs.get(0), p = g.G.player; return { gap: Math.hypot(ev.cur.x - p.px, ev.cur.z - p.py), turns: document.querySelector('#turns').textContent }; });
await page.keyboard.up('d'); await page.waitForTimeout(300);
const v2 = await page.evaluate(() => document.querySelector('#turns').textContent);
check('인형이 걷는 위치를 따라간다', v1.gap < 0.35, JSON.stringify(v1));
check('시계는 초로, 멈추면 "멈춤"', /초/.test(v1.turns) && !/멈춤/.test(v1.turns) && /멈춤/.test(v2), JSON.stringify({ v1: v1.turns, v2 }));
const v3 = await page.evaluate(() => { arena([[1, 0]]); window.__game.View.refreshDecals(); return window.__game.View.grid.lastDecals.filter((d) => d.kind === 1).length; });
check('칸 이동 표시(주변 8칸 테)가 없다', v3 === 0, String(v3));

// 걸음: 두 틱 사이를 보간하고(뒤쫓지 않는다), 통통 튀며 걷고, 멈추면 바닥에 선다. 발밑 고리는 인형 발밑 바닥에
const w0 = await page.evaluate(() => { const g = window.__game, G = arena(), p = G.player, ev = g.View.evs.get(0); ev.cur.set(15, 0, 15); ev.t = 1; p.ppx = 15; p.ppy = 15; p.px = 15.165; p.py = 15; G.alpha = 0.5; g.View.placeUnits(0.016); const x = +ev.cur.x.toFixed(4); p.px = 15; return x; });
check('인형은 두 틱 사이를 보간한다(뒤쫓지 않는다)', w0 === 15.0825, String(w0));
await page.evaluate(() => arena());
await page.keyboard.down('d');
const w1 = await page.evaluate(() => new Promise((done) => { const ev = window.__game.View.evs.get(0); let maxY = 0, n = 0; const f = () => { maxY = Math.max(maxY, ev.d.root.position.y); if (++n < 40) requestAnimationFrame(f); else done({ maxY, ring: !!ev.foot, gap: ev.foot ? Math.hypot(ev.foot.position.x - ev.cur.x, ev.foot.position.z - ev.cur.z) : -1, y: ev.foot ? ev.foot.position.y : -1 }); }; requestAnimationFrame(f); }));
await page.keyboard.up('d'); await page.waitForTimeout(800);
const w2 = await page.evaluate(() => { const g = window.__game, ev = g.View.evs.get(0); g.View.refreshDecals(); return { y: +ev.d.root.position.y.toFixed(3), decal: g.View.grid.lastDecals.some((d) => d.color === 0xffc070) }; });
check('걸을 때 통통 튄다', w1.maxY > 0.05, JSON.stringify(w1));
check('발밑 고리는 인형 발밑 바닥에 붙는다(칸 표식이 아니다)', w1.ring && w1.gap < 0.02 && w1.y < 0.1 && !w2.decal, JSON.stringify({ w1, w2 }));
check('멈추면 바닥에 선다', w2.y < 0.02, JSON.stringify(w2));

await page.evaluate(() => arena());
await page.keyboard.down('d');
const cam = await page.evaluate(() => new Promise((done) => { const g = window.__game, ev = g.View.evs.get(0), rig = g.View.dio.rig; let lag = 0, n = 0; const f = () => { if (n > 10) lag = Math.max(lag, Math.hypot(rig.focus.x - ev.cur.x, rig.focus.z - ev.cur.z)); if (++n < 30) requestAnimationFrame(f); else done(+lag.toFixed(3)); }; requestAnimationFrame(f); }));
await page.keyboard.up('d'); await page.waitForTimeout(300);
check('카메라가 걷는 등불지기를 바짝 따라간다(반 칸씩 처지지 않는다)', cam < 0.3, String(cam));

// ---------- 과제 5: 영혼석 꺼짐 ----------
const z1 = await page.evaluate(async () => { const G = arena([[1, 0]]), S = await import('/js/core/stones.js'); for (let k = 0; k < 20; k++) S.dropStone(G.ents[1], true); return { stones: G.stones.size, souls: getComputedStyle(document.querySelector('#souls')).display }; });
check('영혼석 꺼짐: 떨어지지 않고 칸도 안 보인다', z1.stones === 0 && z1.souls === 'none', JSON.stringify(z1));


// ---------- 최종 검토에서 찾은 것 ----------
// 실제 탭은 늘 pointerdown으로 시작해 조이스틱 탭 막기를 푼다
const tap = (x, y) => page.evaluate(([x, y]) => { const g = window.__game, pt = g.View.pickTile; g.View.pickTile = () => ({ x, y }); g.UI.joyTapBlock = false; g.UI.onTap(0, 0); g.View.pickTile = pt; }, [x, y]);
await page.evaluate(() => { const G = arena([[2, 0]]); G.inv = [{ k: 'oil', n: 2 }]; window.__game.UI.useFromBag('oil'); });
await tap(17, 15); await tap(17, 15);
const r1 = await page.evaluate(() => { const G = window.__game.G; return { oil: G.inv.find((q) => q.k === 'oil')?.n || 0, walk: G.walk, mode: window.__game.UI.mode }; });
check('던지기: 조준 모드에서 탭은 대상 칸(걷지 않는다)', r1.oil === 1 && r1.walk === null && r1.mode === 'normal', JSON.stringify(r1));

const r2 = await page.evaluate(() => { const G = arena([[1, 1, { type: 'rat', name: '쥐', atk: 3, hp: 99, max: 99 }]]), p = G.player, e = G.ents[1]; M.C.setIntent([Math.SQRT1_2, Math.SQRT1_2], false); for (let k = 0; k < 60; k++) M.C.step(); M.C.setIntent(null, false); return { hero: [p.x, p.y], foe: [e.x, e.y], foeHp: e.hp, heroHp: p.hp, max: p.max }; });
check('대각선으로 다가가도 적 칸에 들어가지 않고 서로 친다', (r2.hero[0] !== r2.foe[0] || r2.hero[1] !== r2.foe[1]) && r2.foeHp < 99 && r2.heroHp < r2.max, JSON.stringify(r2));

const r3 = await page.evaluate(() => { arena(); const U = window.__game.UI; U.startTravel(18, 18); document.querySelector('#sheet').classList.remove('hidden'); U.feedIntent(); const open = M.C.flowing(); document.querySelector('#sheet').classList.add('hidden'); U.feedIntent(); const closed = M.C.flowing(); U.stopAuto(); return { open, closed }; });
check('창을 열면 자동 걷기 중에도 시간이 멈춘다', r3.open === false && r3.closed === true, JSON.stringify(r3));

await page.evaluate(() => { arena(); window.__game.UI.joyTapBlock = true; });
await page.mouse.move(195, 200); await page.mouse.down();
const r4 = await page.evaluate(() => window.__game.UI.joyTapBlock);
await page.mouse.up(); await page.evaluate(() => { window.__game.UI.stopAuto(); window.__game.UI.hideInfo(); });
check('조이스틱을 쓴 뒤 다음 탭이 먹히지 않는다', r4 === false, String(r4));

await page.evaluate(() => { const G = arena([[2, 0]]); window.__game.UI.hideInfo(); M.C.setTarget(null); });
await tap(17, 15); const r5a = await page.evaluate(() => document.querySelector('#info').classList.contains('hidden'));
await tap(17, 15); const r5b = await page.evaluate(() => !document.querySelector('#info').classList.contains('hidden'));
await page.evaluate(() => window.__game.UI.hideInfo());
check('노린 적을 한 번 더 탭하면 정보 카드(조이스틱 칸에서도 살펴볼 수 있다)', r5a && r5b, JSON.stringify({ r5a, r5b }));

const r7 = await page.evaluate(() => { const g = window.__game, G = arena(); G.tile[15 * G.W + 15] = M.T.T_STAIRS; G.bossFloor = false; G.projs.push({ x: 15, y: 15, ang: 0, speed: 1, left: 5, range: 5, hit: new Set(), team: 'foe', onHit() {} }); g.descend(); return { projs: G.projs.length, zf: G.zf }; });
check('계단을 내려가면 날던 투사체를 버린다', r7.projs === 0, JSON.stringify(r7));

const r8 = await page.evaluate(() => { const g = window.__game, G = arena(); G.tile[15 * G.W + 16] = M.T.T_DOOR; g.computeFOV(); const seen = []; const on = g.View.on; g.View.on = function (t, d) { seen.push(t); return on.apply(this, arguments); }; g.act(() => g.playerMove(1, 0)); g.View.on = on; return { hud: seen.includes('hud'), vis: seen.includes('vis'), ctx: document.querySelector('#btn-ctx').textContent }; });
check('행동 뒤 화면이 새로 맞춰진다(문을 열면 "문 열기"가 사라진다)', r8.hud && r8.vis && !/문 열기/.test(r8.ctx), JSON.stringify(r8));

const r10 = await page.evaluate(() => { arena(); const U = window.__game.UI, G = window.__game.G; U.explore = true; U.exploreSkip = new Set(); U.exploreGoal = 15 * G.W + 18; G.walk = null; G.stuckAbort = true; G.hurt = false; U.afterTick(0); const r = U.exploreSkip.has(15 * G.W + 18); U.stopAuto(); return r; });
check('탐험이 막힌 곳에 걸리면 그 목표를 건너뛴다', r10 === true, String(r10));

const r11 = await page.evaluate(() => { arena(); const U = window.__game.UI; U.joy = { id: 1, ox: 100, oy: 700, dx: 40, dy: 0, t0: 0, on: true }; dispatchEvent(new Event('blur')); U.feedIntent(); return { joy: U.joy, flowing: M.C.flowing() }; });
check('포커스가 빠지면 누르던 조이스틱도 놓는다', r11.joy === null && !r11.flowing, JSON.stringify(r11));

const r6 = await page.evaluate(async () => { const g = window.__game; document.body.classList.add('frozen'); g.returnToTown('recall'); await new Promise((r) => setTimeout(r, 2500)); return { mode: g.Game.mode, frozen: document.body.classList.contains('frozen') }; });
check('정착지로 돌아가면 멈춤 표시(채도 빠짐)가 풀린다', r6.mode === 'town' && !r6.frozen, JSON.stringify(r6));

// ---------- 직업: Class 정하기 · 스킬 3칸 (docs/설계_직업.md) ----------
const cj1 = await page.evaluate(() => {
  const g = window.__game; if (g.Game.mode !== 'dungeon') { g.META.hero = g.META.hero || g.newHero(); g.enterDungeon(1); } // 앞의 검사가 정착지로 돌아갔다
  const G = arena([[3, 0, { hp: 99, max: 99, atk: 0 }]]), U = g.UI; G.ents[1].awake = false; document.querySelector('#screen').classList.add('hidden'); // 싸우는 중이 아니다
  const before = getComputedStyle(document.querySelector('#souls')).display;
  U.openClassPicker();
  const click = (sel) => document.querySelector(sel).click();
  for (let k = 0; k < 7; k++) click('[data-lv="fighter"][data-d="1"]');
  for (let k = 0; k < 3; k++) click('[data-lv="cleric"][data-d="1"]');
  click('[data-act="apply"]');
  const btns = [...document.querySelectorAll('#souls .slot')].map((b) => b.querySelector('.sn').textContent);
  return { before, title: G.player.klass.title, shown: getComputedStyle(document.querySelector('#souls')).display, btns, saved: g.META.hero && g.META.hero.cls && g.META.hero.cls.levels.fighter };
});
check('직업 정하기: 파이터 7 / 클레릭 3 = 방패의 팔라딘, 스킬 3칸이 뜬다', cj1.before === 'none' && cj1.title === '방패의 팔라딘' && cj1.shown !== 'none' && cj1.btns.length === 3 && cj1.btns[0] === '수호의 맹세', JSON.stringify(cj1));
const cj2 = await page.evaluate(() => {
  const g = window.__game, G = g.G, U = g.UI, p = G.player;
  U.skillBtn(1); // 신성한 일격(자기): 바로 시전, 시전하는 동안 시간이 흐른다
  const flowing = M.C.flowing(); for (let k = 0; k < 3; k++) M.C.step();
  const next = !!(p.fx && p.fx.next), cd = p.scd.pa_smite > 0;
  U.skillBtn(0); const tgt = U.mode === 'target' && U.valid.has(p.y * G.W + p.x); U.exitTarget(); // 수호의 맹세(아군): 조준, 내 칸도 대상
  return { flowing, next, cd, tgt };
});
check('스킬 버튼: 자기 대상은 바로 시전(그동안 시간이 흐른다), 아군 대상은 조준', cj2.flowing && cj2.next && cj2.cd && cj2.tgt, JSON.stringify(cj2));

check('페이지 오류 없음', errors.length === 0, errors.slice(0, 3).join(' | '));
await browser.close(); server.close();
const bad = results.filter((r) => !r).length;
console.log(bad ? `\n${bad}개 실패` : `\n모두 통과 (${results.length})`);
process.exit(bad ? 1 : 0);
