// 원형 턴제(자유 위치) 모드를 헤드리스 크롬에서 검사한다. 격자 모드와 토글로 오간다.
// 사용: node tests/free.mjs
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
  res.writeHead(200, { 'content-type': p.endsWith('.js') ? 'text/javascript' : 'text/html; charset=utf-8' }); fs.createReadStream(p).pipe(res);
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
await page.waitForTimeout(800);
await page.waitForTimeout(1500);

// 아레나: 9×9 방, 주인공 가운데. 적을 원하는 대로 놓는다.

// 1. 토글 버튼
await page.tap('#btn-mode'); await page.waitForTimeout(600);
const tog = await page.evaluate(() => { const G = window.__game.G; return { free: G.free, px: typeof G.player.px, mode: localStorage.getItem('torch-mode'), label: document.querySelector('#btn-mode').textContent, bar: document.querySelector('#freebar').style.display }; });
check('토글 → 원형 턴제 (저장·위치·표시줄)', tog.free && tog.px === 'number' && tog.mode === 'free' && tog.label.includes('원형') && tog.bar !== 'none', JSON.stringify(tog));

// 아레나: 11×11 방, 주인공 가운데
await page.evaluate(() => { const g = window.__game, G = g.G; window.drain = () => { let n = 0; while (g.Anim.active && n++ < 2000) g.Anim.step(1000); };
  window.foe = (x, y, o = {}) => ({ id: G.nextId++, type: 'goblin', x, y, hp: 30, max: 30, atk: 3, st: { wet: 0, frozen: 0, burn: 0, poison: 0, stun: 0, fear: 0, haste: 0, immune: 0, bleed: 0, frac: 0, vital: 0 }, alive: true, awake: true, face: [0, 1], cd: 0, cast: null, charge: null, aim: false, name: '허수아비', ...o });
  window.arena = (foes = []) => { const cx = 15, cy = 15, p = G.player; document.querySelector('#sheet').classList.add('hidden');
    for (let y = 0; y < G.H; y++) for (let x = 0; x < G.W; x++) { const i = y * G.W + x; G.tile[i] = Math.abs(x - cx) <= 5 && Math.abs(y - cy) <= 5 ? 1 : 0; G.surf[i] = 0; G.fire[i] = 0; G.cloud[i] = 0; }
    p.x = cx; p.y = cy; p.px = cx; p.py = cy; p.hp = p.max; p.shield = 0; p.alive = true; p.st = { wet: 0, frozen: 0, burn: 0, poison: 0, stun: 0, fear: 0, haste: 0, immune: 0, bleed: 0, frac: 0, vital: 0 }; G.over = false; G.gear.clear(); G.chests.clear(); G.items.clear();
    G.ents = [p, ...foes.map(([x, y, o]) => foe(cx + x, cy + y, o))];
    G.slots.forEach((q) => { q.stone = null; q.color = null; q.cd = 0; }); g.refreshStats(); G.ps.eva = 0; G.ps.block = 0;
    g.initFree(); g.computeFOV(); g.View.buildFloor(); g.UI.syncAll(); g.UI.freeReset(); return G; };
});

// 2. 탐험: 키보드로 연속 이동 (칸 단위가 아님)
const walk = await page.evaluate(() => { const g = window.__game, G = arena(); const x0 = G.player.px; window.dispatchEvent(new KeyboardEvent('keydown', { key: 'd' })); for (let k = 0; k < 5; k++) g.UI.freeFrame(0.05); window.dispatchEvent(new KeyboardEvent('keyup', { key: 'd' })); return { dx: G.player.px - x0, frac: G.player.px % 1 !== 0, fc: G.fc }; });
check('탐험: 연속 위치로 걷는다', Math.abs(walk.dx - 0.9) < 0.05 && walk.fc === null, JSON.stringify(walk));

// 3. 발견 → 전투, 적 턴 → 내 턴(이동 5m · 행동 1)
const fight = await page.evaluate(() => { const g = window.__game, G = arena([[4, 0]]); g.freeRun(() => { const k = g.detect(); if (k) g.startCombat(k); }); drain(); return { fc: !!G.fc, side: G.fc && G.fc.side, move: G.fc && G.fc.move, act: G.fc && G.fc.actions, d: g.dist(G.player, G.ents[1]) }; });
check('발견 → 전투 → 내 턴 (5m · 행동 1)', fight.fc && fight.side === 'player' && fight.move === 5 && fight.act === 1, JSON.stringify(fight));

// 4. 이동 예산: 3m 걸으면 2m 남는다
const budget = await page.evaluate(() => { const g = window.__game, G = arena([[5, 5]]); g.freeRun(() => g.startCombat('ambush')); drain(); const p = G.player, cm = g.costMap(p, G.fc.move), path = g.pathPoints(p, cm, 15, 12); g.freeRun(() => g.playerWalk(path.pts, path.cost)); drain(); return { left: G.fc.move, cost: path.cost, py: p.py, over: g.playerWalk([[p.px, p.py], [p.px, p.py + 4]], 4) }; });
check('이동 예산: 3m 걷기 → 2m 남음, 초과 이동 거부', Math.abs(budget.left - 2) < 0.05 && Math.abs(budget.py - 12) < 0.1 && budget.over === false, JSON.stringify(budget));

// 5. 걸어가서 공격 + 기습 +50%
const atk = await page.evaluate(() => { const g = window.__game, G = arena([[3, 1]]); const t = G.ents[1]; g.freeRun(() => g.startCombat('ambush')); drain(); const plan = g.attackPlan(t); g.act(() => g.walkAttack(t)); drain(); return { plan: !!plan, hp: t.hp, d: +g.dist(G.player, t).toFixed(2), side: G.fc && G.fc.side, amb: G.fc ? G.fc.ambush : null }; });
check('걸어가서 공격 (사거리 1.5m 안에서 친다)', atk.plan && atk.d <= 1.55 && atk.hp < 30, JSON.stringify(atk));

// 6. 기회 공격: 붙은 적에게서 걸어 나가면 맞는다
const opp = await page.evaluate(() => { const g = window.__game, G = arena([[1, 0]]); g.freeRun(() => g.startCombat('ambush')); drain(); const p = G.player, hp0 = p.hp, cm = g.costMap(p, G.fc.move), path = g.pathPoints(p, cm, 11, 15); g.freeRun(() => g.playerWalk(path.pts, path.cost)); drain(); return { hp0, hp: p.hp, px: p.px }; });
check('기회 공격: 근접 적에게서 벗어나면 한 대 맞는다', opp.hp < opp.hp0, JSON.stringify(opp));

// 7. 마법사 원형 예고 → 벗어나면 피한다
const mage = await page.evaluate(() => { const g = window.__game, G = arena([[4, 0, { type: 'mage', elem: 'fire', hp: 12, max: 12, atk: 2, name: '화염 마법사' }]]); const m = G.ents[1]; g.freeRun(() => g.startCombat('caught')); drain();
  const cast = m.cast ? { r: m.cast.r, n: m.cast.tiles.length } : null, dec = g.View.intents.decals.some((d) => d.kind === 8);
  const p = G.player, cm = g.costMap(p, G.fc.move), path = g.pathPoints(p, cm, 12, 12); g.freeRun(() => g.playerWalk(path.pts, path.cost)); drain();
  const hp1 = p.hp; g.freeRun(() => g.endPlayerTurn()); drain(); return { cast, dec, hp1, hp2: p.hp, burn: p.st.burn }; });
check('마법사: 원 예고(장판 8) → 벗어나면 안 맞는다', mage.cast && mage.dec && mage.hp2 === mage.hp1 && !mage.burn, JSON.stringify(mage));

// 8. UI: 바닥 탭 → 분신 → [이동] 버튼
const ui = await page.evaluate(async () => { const g = window.__game, G = arena([[5, 5]]); g.freeRun(() => g.startCombat('ambush')); drain();
  const v = g.View, cam = v.dio.camera, THREE = null; const w = { x: 15, y: 13 };
  // 월드 → 화면
  const vec = cam.position.clone(); vec.set(w.x, 0, w.y).project(cam); const sx = (vec.x * 0.5 + 0.5) * innerWidth, sy = (-vec.y * 0.5 + 0.5) * innerHeight;
  g.UI.onTap(sx, sy); await new Promise((r) => setTimeout(r, 50));
  const ghost = !!(v.ghost && v.ghost.root.visible), btn = document.querySelector('#btn-ctx').dataset.act;
  document.querySelector('#btn-ctx').click(); drain();
  return { ghost, btn, py: +G.player.py.toFixed(2), move: +G.fc.move.toFixed(2) };
});
check('분신 미리보기 → [이동] 확정', ui.ghost && ui.btn === 'fmove' && ui.py < 14.2 && ui.move < 5, JSON.stringify(ui));
await page.screenshot({ path: path.join(outDir, 'free-combat.png') });

// 9. 턴 끝 버튼 → 적 턴 → 다시 내 턴
const end = await page.evaluate(() => { const g = window.__game, G = window.__game.G; const r0 = G.fc.round; document.querySelector('#btn-ctx').click(); drain(); return { r0, r: G.fc && G.fc.round, side: G.fc && G.fc.side }; });
check('[턴 끝] → 다음 라운드', end.r === end.r0 + 1 && end.side === 'player', JSON.stringify(end));

// 10. 스킬 조준: 사거리 원(미터) 안의 적만
const sk = await page.evaluate(() => { const g = window.__game, G = arena([[2, 0], [0, 4]]); g.freeRun(() => g.startCombat('ambush')); drain(); g.UI.skillBtn('fire'); const n = g.UI.valid.size, mode = g.UI.mode; const e = G.ents[1]; g.UI.tapTarget(e.x, e.y); g.UI.tapTarget(e.x, e.y); drain(); return { n, mode, hp: e.hp, cd: G.cd.fire, acts: G.fc && G.fc.actions }; });
check('스킬: 조준 → 발동 → 행동 소모', sk.mode === 'target' && sk.n > 0 && sk.cd > 0, JSON.stringify(sk));

// 11. 격자로 되돌리기: 칸 중심, 겹침 없음
const back = await page.evaluate(() => { const g = window.__game, G = g.G; G.fc = null; document.querySelector('#btn-mode').click(); const pos = G.ents.filter((e) => e.alive).map((e) => [e.x, e.y, e.px]); const keys = new Set(pos.map(([x, y]) => x + ',' + y)); return { free: G.free, ints: pos.every(([x, y, px]) => Number.isInteger(x) && px === x), unique: keys.size === pos.length, bar: document.querySelector('#freebar').style.display }; });
check('격자로 복귀: 칸 중심 · 겹침 없음', !back.free && back.ints && back.unique && back.bar === 'none', JSON.stringify(back));

// 12. 원형 모드로 한 층 자동 진행(무작위 입력) — 오류 없음
await page.evaluate(() => document.querySelector('#btn-mode').click());
const fuzz = await page.evaluate(() => { const g = window.__game; g.META.hero = g.newHero(); g.enterDungeon(1); document.querySelector('#sheet').classList.add('hidden'); const G = g.G; let fights = 0;
  let was = false;
  for (let k = 0; k < 250 && !G.over; k++) {
    if (G.fc && !was) fights++; was = !!G.fc;
    if (!G.fc) { const k2 = g.detect(); if (k2) { g.freeRun(() => g.startCombat(k2)); drain(); fights++; continue; } g.freeRun(() => { const p = G.player, cm = g.costMap(p, 6, { passAllies: true }); const c = []; for (let i = 0; i < cm.cost.length; i++) if (isFinite(cm.cost[i]) && cm.cost[i] > 2) c.push(i); if (!c.length) return; const i = c[(Math.random() * c.length) | 0], pp = g.pathPoints(p, cm, i % G.W, (i / G.W) | 0); if (pp) g.playerWalk(pp.pts, pp.cost); }); drain(); continue; }
    if (G.fc.side !== 'player') { drain(); continue; }
    const foes = G.ents.filter((e) => e.alive && e !== G.player && !e.ally && G.vis[e.y * G.W + e.x]);
    const t = foes.sort((a, b) => g.dist(a, G.player) - g.dist(b, G.player))[0];
    if (t && G.fc.actions > 0 && g.attackPlan(t)) { g.act(() => g.walkAttack(t)); drain(); } else { g.freeRun(() => g.endPlayerTurn()); drain(); }
    if (G.player.hp < 8) G.player.hp = G.player.max;
  }
  return { fights, over: G.over, turns: G.stats.turns, kills: G.stats.kills, free: G.free, anim: g.Anim.active, pos: [G.player.px, G.player.py], foes: G.ents.length };
});
check('원형 모드 무작위 진행 250걸음 — 오류 없음', fuzz.fights > 0 && errors.length === 0, JSON.stringify(fuzz) + (errors.length ? ' ' + errors.slice(0, 3).join(' | ') : ''));

await browser.close(); server.close();
const bad = results.filter((r) => !r).length;
console.log(bad ? `\n${bad}개 실패` : `\n모두 통과 (${results.length})`);
if (errors.length) console.log('페이지 오류:', errors.slice(0, 5));
process.exit(bad ? 1 : 0);
