// 영혼석 액티브 스킬 확인 목록(docs/설계_영혼석_스킬.md §6)을 헤드리스 크롬에서 검사한다.
// 사용: node tests/stones.mjs
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
const I = (x, y) => y * 40 + x;

// 1. 스킬 5개 버튼이 사라지고 영혼석 칸이 버튼
const s1 = await page.evaluate(() => { const g = window.__game, G = arena([[2, 0]]); drain(); put(0, 'r_fire'); g.UI.renderSlots({ slots: G.slots.map((q) => ({ ...q })), bag: [] }); const n = document.querySelectorAll('#souls .slot').length; document.querySelectorAll('#souls .slot')[0].click(); const mode = g.UI.mode, valid = g.UI.valid.size; g.UI.exitTarget(); return { skills: !!document.querySelector('#skills'), n, mode, valid, ready: document.querySelectorAll('#souls .slot')[0].classList.contains('ready') }; });
check('스킬 5개 버튼 제거, 영혼석 6칸 = 스킬 버튼', !s1.skills && s1.n === 6 && s1.mode === 'target' && s1.valid > 0 && s1.ready, JSON.stringify(s1));

// 2. 빨강: 적중마다 1 더, 한 라운드에 한 번 (연속 베기 2타여도 −1), 방금 쓴 스킬은 제외
const s2 = await page.evaluate(() => { const g = window.__game, G = arena([[1, 0]]); put(0, 'r_arrow', 4); put(1, 'r_extra'); g.act(() => g.useStone(1, 16, 15)); drain(); const a = [G.slots[0].cd, G.slots[1].cd];
  g.act(() => { g.playerMove(1, 0); return true; }); drain(); return { afterExtra: a, afterHit: [G.slots[0].cd, G.slots[1].cd] }; });
check('빨강: 적중 시 1 더 (라운드당 한 번, 방금 쓴 스킬 제외)', s2.afterExtra[0] === 2 && s2.afterExtra[1] === 4 && s2.afterHit[0] === 0 && s2.afterHit[1] === 2, JSON.stringify(s2));

// 3. 보라: 대기하면 1 더 — 전투 밖에서는 이미 0
const s3 = await page.evaluate(() => { const g = window.__game, G = arena([[3, 3]]); put(0, 'p_shield', 5); g.act(() => g.playerWait()); drain(); const inC = G.slots[0].cd;
  arena([]); put(0, 'p_shield', 5); g.act(() => g.playerWait()); drain(); return { inC, outC: G.slots[0].cd }; });
check('보라: 대기 시 1 더, 전투 밖은 0', s3.inC === 3 && s3.outC === 0, JSON.stringify(s3));

// 4. 초록: 여러 적에게 맞아도 라운드에 1만
const s4 = await page.evaluate(() => { const g = window.__game, G = arena([[1, 0], [-1, 0], [0, 1]]); put(0, 'g_fire', 6); const hp = G.player.hp; g.act(() => true); drain(); return { cd: G.slots[0].cd, hits: hp - G.player.hp }; });
check('초록: 여러 번 맞아도 라운드에 1', s4.cd === 4 && s4.hits >= 2, JSON.stringify(s4));

// 5. 전투가 끝나면 모든 쿨타임 0
const s5 = await page.evaluate(() => { const g = window.__game, G = arena([[1, 0, { hp: 1 }]]); put(0, 'r_fire', 5); put(1, 'p_heal', 6); put(2, 'g_heal', 6); g.act(() => { g.playerMove(1, 0); return true; }); drain(); return G.slots.slice(0, 3).map((q) => q.cd); });
check('전투가 끝나면 모든 쿨타임 0', s5.every((v) => v === 0), JSON.stringify(s5));

// 6. 옛 스킬 효과를 이어받았다
const s6 = await page.evaluate(() => { const g = window.__game, out = {}, grass = {}, oil = {}, water = {};
  for (let x = 16; x <= 18; x++) grass[x + 15 * 40] = 2; // 풀
  { const G = arena([[3, 3]], grass); put(0, 'r_fire'); g.act(() => g.useStone(0, 16, 15)); drain(); out.grass = G.fire[17 + 15 * 40] > 0 || G.surf[17 + 15 * 40] === 5; }
  for (let x = 16; x <= 18; x++) oil[x + 15 * 40] = 3; // 기름
  { const G = arena([[2, 0], [3, 3]], oil); put(0, 'r_fire'); g.act(() => g.useStone(0, 16, 15)); drain(); out.oil = G.ents[1].hp < 30 && G.surf[17 + 15 * 40] !== 3; }
  for (let x = 17; x <= 19; x++) water[x + 15 * 40] = 1; // 물
  { const G = arena([[2, 0], [4, 0], [3, 3]], water); put(0, 'r_shock'); g.act(() => g.useStone(0, 17, 15)); drain(); out.conduct = G.ents[1].hp < 30 && G.ents[2].hp < 30; }
  { const G = arena([[2, 0], [3, 3]], water); put(0, 'r_freeze'); g.act(() => g.useStone(0, 17, 15)); drain(); out.freezeWater = G.surf[18 + 15 * 40] === 4 && G.ents[1].st.frozen > 0; }
  { const G = arena([[2, 0, { st: { stun: 9 } }], [3, 0, { st: { stun: 9 } }], [3, 3]]); put(0, 'r_poison'); put(1, 'r_fire'); G.ents[2].st.poison = 5; g.act(() => g.useStone(0, 17, 15)); drain(); const psn = G.ents[1].st.poison > 0, ban = []; const on = g.View.on.bind(g.View); g.View.on = (t, d) => { if (t === 'banner') ban.push(d.text); return on(t, d); }; g.act(() => g.useStone(1, 17, 15)); drain(); g.View.on = on; out.venomBlast = psn && ban.some((t) => t.includes('독 폭발')); }
  { const G = arena([[1, 0], [3, 3]]); G.tile[18 + 15 * 40] = 0; put(0, 'r_push'); let stun = 0; const on = g.View.on.bind(g.View); g.View.on = (t, d) => { if (t === 'status' && d.id === G.ents[1].id && d.st.stun > 0) stun++; return on(t, d); }; g.act(() => g.useStone(0, 16, 15)); drain(); g.View.on = on; out.pushWall = stun > 0 && G.ents[1].hp <= 25 && G.ents[1].x === 17; }
  return out; });
for (const [k, v] of Object.entries(s6)) check(`옛 효과: ${{ grass: '불씨 → 풀 번짐', oil: '불씨 → 기름 폭발', conduct: '번개 → 물 전도', freezeWater: '냉기 → 물이 얼음', venomBlast: '독침 → 불씨 독 폭발', pushWall: '밀치기 → 벽 충돌' }[k]}`, v);

// 7. 물벼락(보라) → 번개(빨강) 연쇄
const s7 = await page.evaluate(() => { const g = window.__game, G = arena([[3, 0], [3, 1], [4, -1], [0, 4]]); put(0, 'p_wet'); put(1, 'r_shock'); const st = []; const on = g.View.on.bind(g.View); g.View.on = (t, d) => { if (t === 'chainStage') st.push(d.stage); return on(t, d); };
  g.act(() => g.useStone(0, 18, 15)); drain(); const wet = G.ents.slice(1, 4).every((e) => e.st.wet > 0); g.act(() => g.useStone(1, 18, 15)); drain(); g.View.on = on;
  return { wet, hurt: G.ents.slice(1, 4).filter((e) => e.hp < 30).length, stages: Math.max(0, ...st) }; });
check('물벼락 → 번개: 한 번의 준비로 연쇄', s7.wet && s7.hurt === 3 && s7.stages >= 1, JSON.stringify(s7));

// 8. 한 손 조작: 칸 → 범위 미리보기 → 대상 탭 두 번 / 자기 대상은 칸 두 번
const s8 = await page.evaluate(() => { const g = window.__game, G = arena([[2, 0], [3, 3]]); put(0, 'r_fire'); put(1, 'p_shield'); const U = g.UI;
  U.stoneBtn(0); U.tapTarget(17, 15); const note = document.querySelector('#targettext').textContent, prev = U.prev && U.prev.extra.length; U.tapTarget(17, 15); drain(); const hit = G.ents[1].hp < 30;
  U.stoneBtn(1); const selfNote = document.querySelector('#targettext').textContent; U.stoneBtn(1); drain();
  return { note: note.slice(0, 30), prev, hit, selfNote: selfNote.slice(0, 20), shield: G.player.shield, cd: [G.slots[0].cd, G.slots[1].cd] }; });
check('칸 → 미리보기 → 대상 탭으로 발동, 자기 대상은 두 번', s8.prev > 0 && s8.hit && s8.shield > 0 && s8.cd[0] > 0 && s8.cd[1] > 0 && /화염|화상/.test(s8.note), JSON.stringify(s8));

// 지속 효과: 번개 갑주가 때린 적에게 되갚고, 남은 라운드가 칸에 뜬다
const s9 = await page.evaluate(() => { const g = window.__game, G = arena([[1, 0]]); put(0, 'g_shock'); g.act(() => g.useStone(0)); drain(); const r = document.querySelectorAll('#souls .slot')[0].querySelector('.aur').textContent; return { hp: G.ents[1].hp, aura: G.auras.storm, r }; });
check('번개 갑주: 때린 적에게 번개, 남은 라운드 표시', s9.hp < 30 && s9.aura > 0 && /R/.test(s9.r), JSON.stringify(s9));
// 어둠: 횃불이 약할수록 적 공격 +, 영혼석이 더 잘 남는다 / 넓어진 층 / 지도에서 누른 곳으로
const s11 = await page.evaluate(async () => { const g = window.__game, C = await import('/js/core/combat.js'), St = await import('/js/core/stones.js'), G = arena([[1, 0, { hp: 999, max: 999 }]]), p = G.player, foe = G.ents[1];
  G.ps.def = 0; G.ps.eva = 0; G.ps.block = 0; G.darkAmbushUsed = true; const hit = (torch) => { G.torch = torch; p.hp = 40; p.shield = 0; return C.damage(p, 2, 'hit', { src: foe }); };
  const bright = hit(100), low = hit(10), out = hit(0);
  const rate = (torch, f) => { G.torch = torch; let n = 0; for (let k = 0; k < 400; k++) { G.stones.clear(); St.dropStone({ ...foe, x: 15, y: 15, boss: null }, f); n += G.stones.size; } return n / 400; };
  const r = { weapon: rate(100, 'slash'), other: rate(100, null), dark: rate(0, 'slash') }; G.torch = 100;
  return { bright, low, out, ...Object.fromEntries(Object.entries(r).map(([k, v]) => [k, +v.toFixed(2)])), W: G.W }; });
check('어둠: 적 공격 +1·+2, 영혼석 45%/15% → 어두우면 ×2', s11.bright === 2 && s11.low === 3 && s11.out === 4 && s11.weapon > 0.35 && s11.weapon < 0.55 && s11.other < 0.24 && s11.dark > 0.8, JSON.stringify(s11));
const s12 = await page.evaluate(async () => { const g = window.__game; g.regen(); const G = g.G; drain(); const foes = G.ents.filter((e) => e.alive && !e.ally && e !== G.player).length;
  const i = G.seen.findIndex((v, k) => v && G.tile[k] !== 0 && (k % G.W !== G.player.x || ((k / G.W) | 0) !== G.player.y));
  g.UI.openMap(); const cv = document.querySelector('#fullmap'), r = cv.getBoundingClientRect(), x = i % G.W, y = (i / G.W) | 0;
  cv.onclick({ clientX: r.left + ((x + 0.5) / G.W) * r.width, clientY: r.top + ((y + 0.5) / G.H) * r.height });
  const moving = !!g.UI.travel; g.UI.travel = null; drain(); return { W: G.W, rooms: G.rooms.length, foes, lamps: G.lamps.size, closed: document.querySelector('#hud-overlay').classList.contains('hidden'), moving }; });
check('넓어진 층(40칸·방 10개 이상·적 늘어남) · 지도에서 누른 곳으로 간다', s12.W === 40 && s12.rooms >= 10 && s12.foes >= 12 && s12.lamps >= 2 && s12.closed && s12.moving, JSON.stringify(s12));

// 자동 탐험·이동은 맞거나 피하면 멈추고, 방금 공격받았으면 다시 시작하지 않는다
const s13 = await page.evaluate(async () => { const g = window.__game, C = await import('/js/core/combat.js'), G = arena([[3, 3, { hp: 999, max: 999, awake: false }]]), p = G.player, foe = G.ents[1], U = g.UI;
  G.ps.eva = 100; G.ps.block = 0; p.shield = 0; let dodged = false; for (let k = 0; k < 60 && !dodged; k++) { G.hurt = false; const hp = p.hp; if (C.damage(p, 3, 'hit', { src: foe }) === 0 && p.hp === hp) dodged = G.hurt; else p.hp = hp; }
  U.travel = { path: [[p.x + 1, p.y], [p.x + 2, p.y]], first: false }; U.explore = true; U.travelStep(); const stopped = !U.travel && !U.explore && /공격받았다/.test(document.querySelector('#toast').textContent);
  foe.alive = false; U.startExplore(); const refused = !U.explore && /공격받고 있어서/.test(document.querySelector('#toast').textContent);
  // 감전으로 기절: 기절 턴이 지나가도 탐험을 이어 가지 않는다
  G.hurt = true; p.st.stun = 1; U.explore = true; U.travel = { path: [[p.x + 1, p.y]], first: false }; U.afterTurn(); const stun = !U.explore && !U.travel; await new Promise((r) => setTimeout(r, 500)); drain(); p.st.stun = 0;
  G.ps.eva = 0; G.hurt = false; G.hurtTurn = -9; return { dodged, stopped, refused, stun }; });
check('자동 탐험: 맞거나 피하면(감전 기절 포함) 멈추고, 공격받는 중에는 다시 시작하지 않는다', s13.dodged && s13.stopped && s13.refused && s13.stun, JSON.stringify(s13));

// 발밑 영혼석: 두고 가기 / 고르지 않고 움직이면 바로 흩어진다
const s10 = await page.evaluate(() => { const g = window.__game, G = arena(), i = (x, y) => y * G.W + x;
  G.stones.set(i(16, 15), 'r_fire'); g.act(() => g.playerMove(1, 0)); drain(); const offered = G.stoneOffer === i(16, 15) && !document.querySelector('#sheet').classList.contains('hidden');
  document.querySelector('#sheet [data-a="leave"]').click(); drain(); const left = !G.stones.has(i(16, 15)) && G.stoneOffer == null;
  G.stones.set(i(17, 15), 'p_wet'); g.act(() => g.playerMove(1, 0)); drain(); document.querySelector('#sheet').classList.add('hidden'); g.act(() => g.playerMove(-1, 0)); drain();
  return { offered, left, walked: !G.stones.has(i(17, 15)) && G.stoneOffer == null }; });
check('발밑 영혼석: 흡수·가방에 넣지 않으면 바로 흩어진다', s10.offered && s10.left && s10.walked, JSON.stringify(s10));
await page.screenshot({ path: path.join(outDir, 'stones.png') });

check('페이지 오류 없음', errors.length === 0, errors.slice(0, 3).join(' | '));
await browser.close(); server.close();
const bad = results.filter((r) => !r).length;
console.log(bad ? `\n${bad}개 실패` : `\n모두 통과 (${results.length})`);
process.exit(bad ? 1 : 0);
