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
await page.waitForTimeout(1500);

// 아레나: 9×9 방, 주인공 가운데. 적을 원하는 대로 놓는다.
const setup = `(() => { const g = window.__game, G = g.G; window.drain = () => { let n = 0; while (g.Anim.active && n++ < 800) g.Anim.step(1000); };
  window.arena = (foes = [], surf = {}) => { const cx = 15, cy = 15, p = G.player;
    for (let y = 0; y < G.H; y++) for (let x = 0; x < G.W; x++) { const i = y * G.W + x; G.tile[i] = Math.abs(x - cx) <= 4 && Math.abs(y - cy) <= 4 ? 1 : 0; G.surf[i] = surf[i] || 0; G.fire[i] = 0; G.cloud[i] = 0; }
    p.x = cx; p.y = cy; p.hp = p.max; p.shield = 0; p.alive = true; G.over = false; G.gear.clear(); G.chests.clear(); G.items.clear();
    G.ents = [p, ...foes.map(([x, y, o = {}]) => ({ id: G.nextId++, type: 'goblin', x: cx + x, y: cy + y, hp: 30, max: 30, atk: 2, st: { wet: 0, frozen: 0, burn: 0, poison: 0, stun: 0, fear: 0, haste: 0, immune: 0, bleed: 0, frac: 0, vital: 0, ...(o.st || {}) }, alive: true, awake: true, face: [0, 1], cd: 0, cast: null, charge: null, aim: false, name: '허수아비', ...o }))];
    G.slots.forEach((q) => { q.stone = null; q.color = null; q.cd = 0; }); window.cast = (id, x, y) => { const q = G.slots[5]; q.stone = id; q.color = g.STONE[id].color; q.cd = 0; return g.useStone(5, x, y); };
    for (const k of Object.keys(G.eq)) G.eq[k] = null; G.eq.weapon = g.makeGear('sword'); G.bag.length = 0; g.refreshStats(); g.computeFOV(); return G; };
  window.wear = (base, slot, legend) => { const it = g.makeGear(base, legend ? 'legend' : 'common', 1, legend || null); it.known = true; it.affixes.forEach((a) => { a.known = true; }); G.bag.push(it); g.equip(G.bag.length - 1, slot); drain(); return it; };
})()`;
await page.evaluate(setup);

// 1. 첫 3층에서 마법 이상 장비 수 (층 무기 + 상자 + 적 처치 기대값)
const magic = await page.evaluate(() => {
  const g = window.__game, G = g.G; let tot = 0; const N = 40;
  for (let r = 0; r < N; r++) for (let d = 1; d <= 3; d++) {
    G.floor = d; G.legendsDropped = new Set();
    const rolls = 1 + 2 + 1; // 상자 1~2 + 층 무기 + 처치 드롭(9마리 × 12% ≈ 1)
    for (let k = 0; k < rolls; k++) if (g.rollGear(d).rarity !== 'common') tot++;
  }
  return tot / N;
});
check('첫 3층 마법 이상 장비 ≥ 2 (평균)', magic >= 2, magic.toFixed(2));

// 5. 상한
const caps = await page.evaluate(() => { const g = window.__game; const eq = {}; for (const [k, b] of [['body', 'body_plate'], ['head', 'head_plate'], ['hands', 'hands_plate'], ['feet', 'feet_cloth'], ['off', 'shield'], ['ring1', 'ring'], ['ring2', 'ring']]) { const it = g.makeGear(b); it.affixes = [{ id: k === 'feet' || k.startsWith('ring') ? 'eva' : 'def', v: 9, known: true }]; eq[k] = it; } const s = g.calcStats(eq); return { def: s.def, eva: s.eva, capped: s.capped }; });
check('상한: 방어 ≤ 6, 회피 ≤ 40%', caps.def <= 6 && caps.eva <= 40 && caps.capped.def, JSON.stringify(caps));

// 3. 전투 중 장착은 한 턴
const turn = await page.evaluate(() => { const g = window.__game, G = arena([[1, 0]]); const it = g.makeGear('head_chain'); G.bag.push(it); const t0 = G.stats.turns; g.UI.openInv(); g.UI.invSel = { from: 'bag', i: 0 }; g.UI.renderInv(); document.querySelector('[data-act="equip"]').click(); drain(); return { turns: G.stats.turns - t0, head: !!G.eq.head, label: document.querySelector('.gdetail') ? 1 : 0 }; });
check('전투 중 장착 → 적이 한 번 움직인다', turn.turns === 1 && turn.head, JSON.stringify(turn));
await page.evaluate(() => document.querySelector('#sheet').classList.add('hidden'));

// 2. 비교 창: 차이값 색, 반지 두 칸
const cmp = await page.evaluate(() => { const g = window.__game, G = arena([]); const r1 = g.makeGear('ring'), r2 = g.makeGear('ring'), r3 = g.makeGear('ring'); r1.affixes = [{ id: 'eva', v: 3, known: true }]; r2.affixes = [{ id: 'hp', v: 5, known: true }]; r3.affixes = [{ id: 'eva', v: 8, known: true }];
  G.eq.ring1 = r1; G.eq.ring2 = r2; G.bag.push(r3); const a = g.makeGear('body_plate'); G.bag.push(a); g.refreshStats();
  g.UI.openInv(); g.UI.invSel = { from: 'bag', i: 0 }; g.UI.renderInv(); const tabs = document.querySelectorAll('[data-tab]').length, up1 = document.querySelector('.gline .up')?.textContent || '';
  g.UI.invSel = { from: 'bag', i: 0, slot: 'ring2' }; g.UI.renderInv(); const txt2 = document.querySelector('.gline').textContent, lost = document.querySelectorAll('.gcard [style*="line-through"]').length;
  g.UI.invSel = { from: 'bag', i: 1 }; g.UI.renderInv(); const dn = document.querySelector('.gline .dn')?.textContent || '', up = document.querySelector('.gline .up')?.textContent || '';
  return { tabs, up1, txt2, lost, dn, up }; });
check('비교 창: 반지 탭 2개 · 오름 초록 · 내림 빨강 · 사라지는 옵션 줄긋기', cmp.tabs === 2 && /회피 \+5%/.test(cmp.up1) && /최대 HP -5/.test(cmp.txt2) && cmp.lost >= 1 && /회피/.test(cmp.dn) && /방어/.test(cmp.up), JSON.stringify(cmp));
await page.screenshot({ path: path.join(outDir, 'gear-compare.png') });
await page.evaluate(() => document.querySelector('#sheet').classList.add('hidden'));

// 4. 외형: 장착하면 인형이 바뀌고, 해제하면 돌아온다
const look = await page.evaluate(() => { const g = window.__game, G = arena([]); g.View.buildFloor(); const ev = () => g.View.evs.get(0); const sig = () => { const a = ev().d.geo.getAttribute('color'); let s = 0; for (let i = 0; i < a.count * 3; i += 7) s += a.array[i]; return a.count + ':' + s.toFixed(2); };
  const s0 = sig(); const it = g.makeGear('body_plate'); G.bag.push(it); g.UI.instant(() => g.equip(0, 'body')); const s1 = sig(); g.UI.instant(() => g.unequip('body')); const s2 = sig();
  const h = g.makeGear('head_plate'); G.bag.push(h); g.UI.instant(() => g.equip(G.bag.length - 1, 'head')); const s3 = sig(); return { s0, s1, s2, s3 }; });
check('외형: 몸통·머리 장착 시 바뀌고 해제하면 원래대로', look.s0 !== look.s1 && look.s0 === look.s2 && look.s3 !== look.s0, JSON.stringify(look));
await page.screenshot({ path: path.join(outDir, 'gear-look.png') });

// 6. 전설 6종
const L = await page.evaluate(() => {
  const g = window.__game, out = {}, I = (x, y) => y * g.G.W + x;
  // 물안개 망토: 대기하면 주변이 젖는다
  { const G = arena([[1, 0]]); wear('body_cloth', 'body', 'mistCloak'); g.act(() => g.playerWait()); drain(); out.mist = G.surf[I(16, 15)] === 1 && G.ents[1].st.wet > 0; }
  // 피의 송곳니: 출혈 중인 적이 죽으면 옆 적에게 출혈 2
  { const G = arena([[1, 0, { hp: 1, st: { bleed: 3 } }], [2, 0, { type: 'goblin' }]]); wear('dagger', 'weapon', 'bloodFang'); G.ents[2].st.bleed = 0; g.act(() => { g.playerMove(1, 0); return true; }); drain(); out.fang = !G.ents[1].alive && G.ents[2].st.bleed >= 1 && G.ents[2].hp < 30; } // 출혈 2가 들어가고 같은 턴에 1 흐른다
  // 가시 판금: 맞으면 초록 쿨타임이 2씩(턴 끝 1 + 초록 2 = 3)
  { const G = arena([[1, 0, { atk: 5 }]]); g.addStone('g_shield'); G.slots[0].cd = 5; wear('body_plate', 'body', 'thornPlate'); G.ps.eva = 0; G.ps.block = 0; G.ps.def = 0; G.slots[0].cd = 5; g.act(() => true); drain(); out.thorn = G.slots[0].cd === 2; }
  // 번개 감긴 반지: 번질 때 1칸 더
  { const surf = {}; for (let x = 16; x <= 17; x++) surf[I(x, 15)] = 1; const G = arena([[1, 0], [3, 0]], surf); const a = g.G.ents[2]; const before = (() => { let r; cast('r_shock', 16, 15); drain(); r = a.hp; return r; })();
    const G2 = arena([[1, 0], [3, 0]], surf); wear('ring', 'ring1', 'stormRing'); cast('r_shock', 16, 15); drain(); out.storm = before === 30 && G2.ents[2].hp < 30; }
  // 거인의 철퇴: 밀치기 1칸 더 + 벽 충돌 시 주변 흔들림
  { const G = arena([[1, 0]]); wear('mace', 'weapon', 'giantMace'); cast('r_push', 16, 15); drain(); out.giant = G.ents[1].x === 19; }
  // 연금술사의 장갑: 던지면 둘로
  { const G = arena([]); wear('hands_leather', 'hands', 'alchGlove'); g.G.inv.push({ k: 'water', n: 1 }); g.G.known.water = true; g.useItem('water', 15, 12); drain(); let n = 0; for (let i = 0; i < G.W * G.H; i++) if (G.surf[i] === 1) n++; out.alch = n >= 9; }
  return out;
});
for (const [k, v] of Object.entries(L)) check(`전설: ${{ mist: '물안개 망토', fang: '피의 송곳니', thorn: '가시 판금', storm: '번개 감긴 반지', giant: '거인의 철퇴', alch: '연금술사의 장갑' }[k]}`, v);

// 7. 미확인: 입으면 하나 드러나고, 층을 내려가면 전부
const unk = await page.evaluate(() => { const g = window.__game, G = arena([]); const it = g.makeGear('ring', 'rare'); G.bag.push(it); const hidden = it.affixes.filter((a) => !a.known).length; g.equip(0, 'ring1'); const after = it.affixes.filter((a) => !a.known).length; return { hidden, after, n: it.affixes.length }; });
check('미확인 희귀: 장착 시 옵션 하나 공개', unk.hidden === unk.n && unk.after === unk.n - 1, JSON.stringify(unk));

check('페이지 오류 없음', errors.length === 0, errors.slice(0, 3).join(' | '));
await browser.close(); server.close();
const fail = results.filter((r) => !r).length;
console.log(`\n${results.length - fail}/${results.length} 통과`);
process.exit(fail ? 1 : 0);
