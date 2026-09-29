// 던전 확장 1단계(소모 · 첫 새 적)와 5단계(연출) 확인 목록(docs/설계_던전_확장.md §10)을 헤드리스 크롬에서 검사한다.
// 사용: node tests/dungeon.mjs
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
await page.tap('#btn-start'); await page.waitForTimeout(1500);
await page.evaluate(() => { const g = window.__game; document.querySelector('#sheet').classList.add('hidden'); g.META.hero = g.newHero(); g.enterDungeon(1); });
await page.waitForTimeout(1500);

// 아레나: 9×9 방, 주인공 가운데. 적을 원하는 대로 놓는다.

await page.evaluate(() => { const g = window.__game, G = g.G;
  window.drain = () => { let n = 0; while (g.Anim.active && n++ < 800) g.Anim.step(1000); };
  window.arena = (foes = [], surf = {}) => { const cx = 15, cy = 15, p = G.player; document.querySelector('#sheet').classList.add('hidden');
    for (let y = 0; y < G.H; y++) for (let x = 0; x < G.W; x++) { const i = y * G.W + x; G.tile[i] = Math.abs(x - cx) <= 4 && Math.abs(y - cy) <= 4 ? 1 : 0; G.surf[i] = surf[i] || 0; G.fire[i] = 0; G.cloud[i] = 0; }
    p.x = cx; p.y = cy; p.hp = p.max = 40; p.shield = 0; p.alive = true; for (const k in p.st) p.st[k] = 0; G.over = false; G.gear.clear(); G.chests.clear(); G.items.clear(); G.stones.clear(); G.block = new Map(); G.auras = {}; G.round = 0; G.combatDmg = 0;
    G.ents = [p, ...foes.map(([x, y, o = {}]) => ({ id: G.nextId++, type: 'goblin', x: cx + x, y: cy + y, hp: 30, max: 30, atk: 2, alive: true, awake: true, face: [0, 1], cd: 0, cast: null, charge: null, aim: false, name: '허수아비', ...o, st: { wet: 0, frozen: 0, burn: 0, poison: 0, stun: 0, fear: 0, haste: 0, immune: 0, bleed: 0, frac: 0, vital: 0, ...(o.st || {}) } }))];
    G.slots.forEach((q) => { q.stone = null; q.color = null; q.cd = 0; q.usedRound = q.redRound = -1; });
    for (const k of Object.keys(G.eq)) G.eq[k] = null; G.eq.weapon = g.makeGear('sword'); g.refreshStats(); G.ps.eva = 0; G.ps.block = 0; g.computeFOV(); return G; };
  window.put = (k, id, cd = 0) => Object.assign(G.slots[k], { stone: id, color: g.STONE[id].color, cd, usedRound: -1, redRound: -1 });
});
const tick = () => page.evaluate(() => { const g = window.__game; g.act(() => g.playerWait()); drain(); });

// §10-1 전투가 끝나도 쿨타임은 그대로, 전투 밖에서도 턴마다 1씩
const d1 = await page.evaluate(() => { const g = window.__game, G = arena(); put(0, 'r_fire', 4); g.act(() => g.playerWait()); drain(); const a = G.slots[0].cd; g.act(() => g.playerWait()); drain(); return { a, b: G.slots[0].cd }; });
check('§10-1 쿨타임은 초기화 없이 턴마다 1씩', d1.a === 3 && d1.b === 2, JSON.stringify(d1));

// §10-2 휴식: 횃불 턴마다 1, 3턴마다 HP 1 (자동 회복은 그대로 둔다)
const d2 = await page.evaluate(() => { const g = window.__game, G = arena(), p = G.player; p.hp = 20; G.torch = 80; G.restN = 0; G.stats.turns = 1; // 6턴 자동 회복과 겹치지 않게
  for (let k = 0; k < 3; k++) { g.act(() => { G.resting = true; return g.playerWait(); }); drain(); }
  return { torch: +(80 - G.torch).toFixed(2), hp: p.hp - 20 }; });
check('§10-2 휴식: 횃불 턴마다 1, 3턴마다 HP 1', d2.torch === 3 && d2.hp === 1, JSON.stringify(d2));

// §10-3 방랑하는 적: 먼 방에 깨어 있는 무리가 생긴다
const d3 = await page.evaluate(async () => { const g = window.__game; g.regen(); drain(); const G = g.G, R = await import('/js/core/run.js'); const n0 = G.ents.length; let ok = false; for (let k = 0; k < 5 && !ok; k++) ok = R.wanderers(); const nw = G.ents.slice(n0); return { ok, n: nw.length, awake: nw.every((e) => e.awake), far: nw.every((e) => Math.max(Math.abs(e.x - G.player.x), Math.abs(e.y - G.player.y)) >= 5) }; });
check('§10-3 방랑하는 적: 먼 방에 깨어 있는 무리', d3.ok && d3.n >= 1 && d3.awake && d3.far, JSON.stringify(d3));

// §10-4 레벨업: 잃은 HP의 절반
const d4 = await page.evaluate(async () => { const g = window.__game, G = arena(), S = await import('/js/core/stones.js'), p = G.player; G.level = 1; G.xp = 0; p.hp = 10; const max0 = p.max; S.gainXp({ max: 15 }); drain(); return { level: G.level, hp: p.hp, max: p.max, max0 }; });
check('§10-4 레벨업: 잃은 HP의 절반이 찬다', d4.level === 2 && d4.hp === 14 + Math.ceil((d4.max - 14) / 2), JSON.stringify(d4));

// §10-5 속도: 빠른 쥐는 한 턴 두 칸, 느린 거머리(땅 위)는 두 턴에 한 칸. 머리 위 » «
const d5 = await page.evaluate(async () => { const g = window.__game, G = arena([[-4, 0, { type: 'rat', name: '굶주린 쥐', speed: 'fast', hp: 99, max: 99 }], [4, 4, { type: 'leech', name: '거머리', speed: 'slow', hp: 99, max: 99, atk: 0 }]]); const rat = G.ents[1], lee = G.ents[2], d = (e) => Math.max(Math.abs(e.x - G.player.x), Math.abs(e.y - G.player.y));
  g.View.buildFloor(); g.UI.syncAll(); const r0 = d(rat), l0 = d(lee); g.act(() => g.playerWait()); drain(); const r1 = d(rat), l1 = d(lee); g.act(() => g.playerWait()); drain(); const l2 = d(lee);
  let tags = ''; for (let k = 0; k < 20 && !(/»/.test(tags) && /«/.test(tags)); k++) { await new Promise((r) => setTimeout(r, 100)); tags = [...document.querySelectorAll('.spd')].map((b) => b.textContent).join(''); } // 그려질 때까지
  return { rat: r0 - r1, leech1: l0 - l1, leech2: l0 - l2, tags }; });
check('§10-5 빠름 두 칸 · 느림 두 턴에 한 칸 · 머리 위 » «', d5.rat === 2 && d5.leech2 === 1 && d5.leech1 <= 1 && /»/.test(d5.tags) && /«/.test(d5.tags), JSON.stringify(d5));

// §10-6 1구역 새 적: 쥐 떼·거머리·주술사가 나온다. 거머리는 물속에서 안 보이고, 맞으면 드러난다. 주술사는 동료를 치유한다
const d6 = await page.evaluate(async () => { const g = window.__game, types = new Set(); for (let k = 0; k < 4; k++) { g.regen(); drain(); for (const e of g.G.ents) types.add(e.type); }
  const water = {}; for (let x = 11; x <= 19; x++) for (let y = 11; y <= 19; y++) water[y * 40 + x] = 1;
  const G = arena([[2, 0, { type: 'leech', name: '거머리', speed: 'slow', hidden: true, hp: 99, max: 99 }]], water), lee = G.ents[1], C = await import('/js/core/combat.js'), F = await import('/js/core/fov.js');
  g.computeFOV(); const hid = !F.visibleFoes().includes(lee) && !!G.vis[lee.y * 40 + lee.x]; C.damage(lee, 1, 'shock', { src: G.player }); const shown = !lee.hidden && F.visibleFoes().includes(lee);
  const G2 = arena([[3, 0, { hp: 2, max: 6 }], [3, 1, { type: 'shaman', name: '고블린 주술사', hp: 7, max: 7, atk: 0, healCd: 0 }]]); G2.ents[1].atk = 0; g.act(() => g.playerWait()); drain();
  return { types: [...types].filter((t) => ['rat', 'leech', 'shaman'].includes(t)).sort().join(), hid, shown, healed: G2.ents[1].hp - 2 }; });
check('§10-6 1구역 새 적 3종 · 거머리 숨음/드러남 · 주술사 치유', d6.types === 'leech,rat,shaman' && d6.hid && d6.shown && d6.healed >= 4, JSON.stringify(d6));

// §10-7 처음 보는 적: 한 번 알리고 기억한다. 정보 카드에 속도·위험
const d7 = await page.evaluate(async () => { const g = window.__game, M = g.META; M.seenFoes = (M.seenFoes || []).filter((k) => k !== 'rat'); const G = arena([[2, 0, { type: 'rat', name: '굶주린 쥐', speed: 'fast', hp: 99, max: 99, atk: 0 }]]); g.act(() => g.playerWait()); drain();
  const log = [...document.querySelectorAll('#log div')].map((d) => d.textContent).join('|'); g.UI.showEnemy(G.ents[1]); const card = document.querySelector('#info').textContent; g.UI.hideInfo();
  return { remembered: M.seenFoes.includes('rat'), log: /처음 보는 적: 굶주린 쥐/.test(log), card: /빠르다/.test(card) && /⚠/.test(card) }; });
check('§10-7 처음 보는 적 알림 · 정보 카드 속도·위험', d7.remembered && d7.log && d7.card, JSON.stringify(d7));

// 5단계: 큰 피해 멈칫·붉은 테, 빈사 화면·탐험 막기, 사망 요약
const d8 = await page.evaluate(async () => { const g = window.__game, G = arena([[1, 0, { hp: 99, max: 99, name: '고블린' }]]), p = G.player, C = await import('/js/core/combat.js'), D = g.View.dio; p.hp = p.max = 30; G.ps.def = 0;
  window.hurts = []; const h0 = g.UI.hurt.bind(g.UI); g.UI.hurt = (b) => { window.hurts.push(b); h0(b); }; window.hits2 = []; const on = g.View.on; g.View.on = function (t, d) { if (t === 'hit') window.hits2.push([d.id, d.amt, d.kind]); return on.apply(this, arguments); };
  g.act(() => { C.damage(p, 8, 'hit', { src: G.ents[1] }); return true; }); drain(); g.View.on = on; g.UI.hurt = h0; const stop = D._stop > 0, big = window.hurts[0] === true; // 첫 피격(8 = 최대 HP의 20% 이상)이 큰 피해로
  p.hp = 6; g.UI.hp(6, 30); const low = +document.querySelector('#lowhp').style.opacity; G.hurtTurn = -9; G.ents[1].alive = false; g.UI.startExplore(); const refused = !g.UI.explore && /너무 다쳐서/.test(document.querySelector('#toast').textContent);
  G.ents[1].alive = true; g.act(() => { C.damage(p, 99, 'hit', { src: G.ents[1] }); return true; }); drain(); await new Promise((r) => setTimeout(r, 1500)); drain(); await new Promise((r) => setTimeout(r, 1200));
  const scr = document.querySelector('#screen').textContent; return { stop, big, low, refused, summary: /고블린에게/.test(scr) && /쓰러지다/.test(scr) && /턴/.test(scr) }; });
check('5단계: 큰 피해 멈칫·붉은 테 · 빈사 화면·탐험 막기 · 사망 요약', d8.stop && d8.big && d8.low > 0.4 && d8.refused && d8.summary, JSON.stringify(d8));

// 자동 탐험 오판 없음: 물속에 깨어 있는 거머리가 가까이 있어도(맞지 않았으면) 탐험이 시작된다. 지속 피해는 '공격받는 중'이 아니다
const d9 = await page.evaluate(async () => { const g = window.__game, water = {}; for (let x = 16; x <= 19; x++) for (let y = 11; y <= 19; y++) water[y * 40 + x] = 1;
  const G = arena([[3, 0, { type: 'leech', name: '거머리', speed: 'slow', hidden: true, hp: 99, max: 99 }]], water), C = await import('/js/core/combat.js'); G.hurtTurn = -9; G.stats.turns = 50;
  C.damage(G.player, 1, 'poison'); const dot = (G.hurtTurn ?? -9) < 0; G.hurt = false;
  g.UI.startExplore(); const started = g.UI.explore || !/공격받고 있어서/.test(document.querySelector('#toast').textContent); g.UI.explore = false; g.UI.travel = null; drain();
  return { dot, started }; });
check('자동 탐험 오판 없음: 숨은 적·지속 피해는 공격받는 중이 아니다', d9.dot && d9.started, JSON.stringify(d9));

check('페이지 오류 없음', errors.length === 0, errors.slice(0, 3).join(' | '));
await browser.close(); server.close();
const bad = results.filter((r) => !r).length;
console.log(bad ? `\n${bad}개 실패` : `\n모두 통과 (${results.length})`);
process.exit(bad ? 1 : 0);
