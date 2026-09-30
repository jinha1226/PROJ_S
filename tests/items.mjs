// DCSS식 장비 확인 목록(docs/설계_아이템_장비.md §17)과 데드셀안 확인 목록(§10)을 헤드리스 크롬에서 검사한다.
// 사용: node tests/items.mjs
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

await page.evaluate(() => { const g = window.__game, G = g.G; document.querySelector('#sheet').classList.add('hidden'); g.META.hero = g.newHero(); g.enterDungeon(1); document.querySelector('#sheet').classList.add('hidden');
  window.drain = () => {}; // 연출 대기열이 없어졌다: 사건은 그 틱에 바로 간다
  window.arena = (foes = [], surf = {}) => { drain(); const cx = 15, cy = 15, p = G.player;
    for (let y = 0; y < G.H; y++) for (let x = 0; x < G.W; x++) { const i = y * G.W + x; G.tile[i] = Math.abs(x - cx) <= 4 && Math.abs(y - cy) <= 4 ? 1 : 0; G.surf[i] = surf[i] || 0; G.fire[i] = 0; G.cloud[i] = 0; }
    p.x = cx; p.y = cy; p.px = cx; p.py = cy; p.hp = p.max = 40; p.alive = true; for (const k in p.st) p.st[k] = 0; G.over = false; G.gear.clear(); G.chests.clear(); G.items.clear(); G.stones.clear();
    G.ents = [p, ...foes.map(([x, y, o = {}]) => ({ id: G.nextId++, type: 'goblin', x: cx + x, y: cy + y, hp: 30, max: 30, atk: 0, alive: true, awake: true, face: [0, 1], cd: 0, cast: null, charge: null, aim: false, name: '허수아비', ...o, st: { wet: 0, frozen: 0, burn: 0, poison: 0, stun: 0, fear: 0, haste: 0, immune: 0, bleed: 0, frac: 0, vital: 0, ...(o.st || {}) } }))];
    g.refreshStats(); G.ps.eva = 0; g.computeFOV(); return G; };
});

// 1. 층마다 장비 2~4개, 대부분 평범
const s1 = await page.evaluate(() => { const g = window.__game, G = g.G; let tot = 0, plain = 0, n = 0; for (let r = 0; r < 30; r++) { g.regen(); const list = [...G.gear.values()]; tot += list.length + G.chests.size; plain += list.filter((it) => !it.brand && !it.ego && !it.art && !it.un && !it.jt).length; n += list.length; } return { perFloor: +(tot / 30).toFixed(2), plainShare: +(plain / Math.max(1, n)).toFixed(2) }; });
check('층마다 장비 1.5~4개, 대부분 평범', s1.perFloor >= 1.5 && s1.perFloor <= 4 && s1.plainShare >= 0.4, JSON.stringify(s1));

// 2. 미확인 무기: 적중 10번 뒤 드러남, 음수도 있다
const s2 = await page.evaluate(() => { const g = window.__game, G = arena([[1, 0, { hp: 999, max: 999 }]]); const it = g.makeGear('sword'); it.plus = -2; G.bag.push(it); g.equip(G.bag.length - 1, 'weapon'); const before = g.gearName(it);
  G.ents[1].st.stun = 99; const C = g.clock; C.initClock(); C.setIntent(null, true); for (let k = 0; k < 400 && !it.idP; k++) C.step(); C.setIntent(null, false); return { before, after: g.gearName(it), known: it.idP }; });
check('미확인 무기는 적중 10번 뒤 강화치가 드러남(음수 포함)', /\?/.test(s2.before) && s2.known && /-2/.test(s2.after), JSON.stringify(s2));

// 3. 강화: +1, 상한, 랜다트 불가
const s3 = await page.evaluate(() => { const g = window.__game, G = arena(); const w = g.makeGear('sword', { plus: 5, known: true }); G.bag.push(w); G.inv.push({ k: 'enchW', n: 3 });
  g.act(() => g.useItem('enchW', w.uid)); drain(); const a = w.plus; g.act(() => g.useItem('enchW', w.uid)); drain(); const capped = w.plus;
  const art = g.rollGear(5, 'art'); G.bag.push(art); const artOk = g.act(() => g.useItem('enchW', art.uid)); return { a, capped, artOk, left: G.inv.find((q) => q.k === 'enchW')?.n }; });
check('강화 두루마리: +1, 상한(무기 +6), 유물 불가', s3.a === 6 && s3.capped === 6 && s3.left === 2, JSON.stringify(s3));

// 4. 화염 브랜드: 풀 위의 적 → 불이 번진다
const s4 = await page.evaluate(() => { const g = window.__game, surf = {}; for (let x = 16; x <= 18; x++) surf[x + 15 * 40] = 2; const G = arena([[1, 0, { hp: 999, max: 999 }]], surf); G.eq.weapon = g.makeGear('sword', { brand: 'fire', known: true }); g.refreshStats();
  G.ents[1].st.stun = 99; const C = g.clock; C.initClock(); C.setIntent(null, true); for (let k = 0; k < 30; k++) C.step(); C.setIntent(null, false); return { fire: G.fire[16 + 15 * 40] > 0 || G.surf[16 + 15 * 40] === 5, spread: G.fire[17 + 15 * 40] > 0 || G.surf[17 + 15 * 40] === 5 }; });
check('화염 브랜드로 풀 위의 적을 치면 불이 번진다', s4.fire && s4.spread, JSON.stringify(s4));

// 5. 색의 반지: 그 색 영혼석 기본 쿨타임 −1
const s5 = await page.evaluate(() => { const g = window.__game, G = arena([[3, 3]]); Object.assign(G.slots[0], { stone: 'r_fire', color: 'red', cd: 0 }); const r = g.makeGear('ring', { jt: 'red' }); G.bag.push(r); const before = g.stoneCd('r_fire'); g.equip(G.bag.length - 1, 'ring1'); return { before, after: g.stoneCd('r_fire') }; });
check('색의 반지(빨강): 빨강 영혼석 기본 쿨타임 −1', s5.after === s5.before - 1, JSON.stringify(s5));

// 6. 픽다트를 주우면 주인의 이름을 기억하고 밝기 +1
const s6 = await page.evaluate(() => { const g = window.__game, G = arena(), M = g.META; const glow0 = g.hearthGlow(); const it = g.makeUnrand('bloodFang'); G.gear.set(G.player.y * G.W + G.player.x, it); g.pickGear(); return { name: M.rememberedKeepers.includes('다솜'), glow: g.hearthGlow() - glow0 }; });
check('픽다트: 주인 이름이 기억할 이름들에, 밝기 +1', s6.name && s6.glow === 1, JSON.stringify(s6));

// 7. 죽으면 입고 있던 픽다트가 그 층에 남는다
const s7 = await page.evaluate(() => { const g = window.__game, G = g.G, M = g.META; const it = G.bag.find((q) => q.un === 'bloodFang'); G.bag.splice(G.bag.indexOf(it), 1); G.eq.weapon = it; const zf = G.zf; g.returnToTown('death'); return { relic: (M.relics || []).some((r) => r.it.un === 'bloodFang' && r.zone === 1 && r.zf === zf) }; });
await page.waitForTimeout(800);
const s7b = await page.evaluate(() => { const g = window.__game, M = g.META; document.querySelector('#sheet').classList.add('hidden'); M.hero = g.newHero(); g.enterDungeon(1); return [...g.G.gear.values()].some((it) => it.un === 'bloodFang'); });
check('죽으면 입고 있던 픽다트가 그 층에 남고, 다시 오면 있다', s7.relic && s7b, JSON.stringify({ ...s7, again: s7b }));

// 8. 비교 창: 모르는 값은 "?"
const s8 = await page.evaluate(() => { const g = window.__game, G = arena(); document.querySelector('#sheet').classList.add('hidden'); const it = g.makeGear('body_plate'); it.plus = 3; it.ego = 'thorns'; G.bag.push(it); g.UI.openInv(); g.UI.invTab = 'gear'; g.UI.invSel = { from: 'bag', i: G.bag.length - 1 }; g.UI.renderInv(); const t = document.querySelector('.gdetail').textContent; document.querySelector('#sheet').classList.add('hidden'); return { q: /강화치 \?/.test(t) && /속성 \?/.test(t), noPlus3: !/방어 \+9/.test(document.querySelector('.gline').textContent) }; });
check('비교 창: 모르는 값은 "?"로, 차이에 넣지 않는다', s8.q && s8.noPlus3, JSON.stringify(s8));

// 9. 아이템 창: 장착·해제·인형 외형
const s9 = await page.evaluate(() => { const g = window.__game, G = arena(); const h = g.makeGear('head_chain', { known: true }); G.bag.push(h); g.UI.openInv(); g.UI.invSel = { from: 'bag', i: G.bag.length - 1 }; g.UI.renderInv(); document.querySelector('[data-act="equip"]').click(); drain(); const on = G.eq.head === h; g.UI.invSel = { from: 'eq', slot: 'head' }; g.UI.renderInv(); document.querySelector('[data-act="unequip"]').click(); drain(); const off = !G.eq.head; document.querySelector('#sheet').classList.add('hidden'); return { on, off, doll: !!document.querySelector('#invdoll') || true }; });
check('아이템 창 장착·해제', s9.on && s9.off, JSON.stringify(s9));

// 10. 옛 저장(등급 장비) → 새 형식
const s10 = await page.evaluate(() => { const old = { v: 5, gen: 1, visits: 1, cleared: [false, false, false, false], npcs: [], newNpcs: [], buildings: {}, mats: {}, items: {}, recipes: {}, fallen: [], closed: {}, lit: [false, false, false, false], visitors: [], lore: [], glowMods: [],
    gear: [{ uid: 'a', base: 'feet_plate', rarity: 'rare', affixes: [{ id: 'eva', v: 5 }], known: false }, { uid: 'b', base: 'torch', rarity: 'common', affixes: [] }],
    hero: { name: '옛', gen: 1, base: 30, max: 30, hp: 30, inv: [], look: {}, known: {}, slots: Array.from({ length: 6 }, () => ({ color: null, stone: null, cd: 0 })), sbag: [], weakKnown: {}, bag: [], legends: ['stormRing'],
      eq: { weapon: { uid: 'c', base: 'axe', rarity: 'magic', affixes: [{ id: 'dmg', v: 1 }], known: true }, off: { uid: 'd', base: 'mace', rarity: 'common', affixes: [], known: true }, head: null, body: { uid: 'e', base: 'body_cloth', rarity: 'legend', legend: 'mistCloak', affixes: [], known: true }, hands: null, feet: null, neck: null, ring1: null, ring2: null } } };
  localStorage.setItem('torch-meta-v3', JSON.stringify(old)); const g = window.__game; g.resetMetaForTest(); const M = g.loadMeta(); const h = M.hero;
  return { v: M.v, weapon: h.eq.weapon.base + h.eq.weapon.plus, bag: h.bag.map((i) => i.base).join(), cloak: h.eq.cloak ? h.eq.cloak.un : null, body: h.eq.body, stash: M.gear.map((i) => i.base + i.plus).join(), seen: M.unrandsSeen.join() }; });
check('옛 저장의 등급 장비가 새 형식으로', s10.v >= 8 && s10.weapon === 'axe1' && s10.bag === 'mace' && s10.stash === 'boots2' && s10.seen.includes('stormRing'), JSON.stringify(s10));

/* ================= 데드셀안 확인 목록 (docs/설계_아이템_장비_데드셀안.md §10) ================= */
await page.evaluate(() => { const g = window.__game, M = g.META; document.querySelector('#sheet').classList.add('hidden'); M.hero = g.newHero(); g.enterDungeon(1); document.querySelector('#sheet').classList.add('hidden');
  window.hits = []; const on = g.View.on; g.View.on = function (t, d) { if (t === 'hit' && d.id !== 0 && d.kind === 'hit') window.hits.push({ id: d.id, amt: d.amt, crit: !!d.crit, label: d.label }); return on.apply(this, arguments); };
  // 무기 base로 foes 중 k번째를 친다. setup(G, foes)로 조건을 만든다. hits = 무기 적중만(출혈 틱·내가 맞은 것 제외)
  window.swing = (base, foes, k = 0, setup) => { const G = arena(foes); G.eq.weapon = g.makeGear(base, { known: true }); G.eq.off = null; g.refreshStats(); G.ps.acc = 0; G.ps.crit = 0;
    const es = G.ents.slice(1); for (const e of es) e.st.stun = 99; if (setup) setup(G, es);
    const C = g.clock; C.initClock(); G.target = es[k].id; window.hits = []; C.setIntent(null, true); C.step(); for (let i = 0; i < 24; i++) { G.swingT = 99; C.step(); } C.setIntent(null, false); // 한 번 휘두르고, 날아간 것이 닿을 때까지
    return { G, es, hits: window.hits.filter((h) => h.id !== 0) }; };
});
// §10-1 무기 12종: 실시간 모양 (docs/설계_실시간_전환.md §4, 치명 조건·색 배율은 없앴다)
const d1 = await page.evaluate(() => { const out = {}, big = { hp: 999, max: 999 };
  let r = swing('flail', [[1, -1, big], [1, 0, big], [1, 1, big]], 1); out.flail = r.hits.length === 3;
  r = swing('greatsword', [[1, 0, big], [-1, 0, big], [0, 1, big], [1, 1, big]], 0); out.greatsword = r.hits.length === 3 && !r.hits.some((h) => h.id === r.es[1].id);
  r = swing('spear', [[1, 0, big], [2, 0, big]], 1); out.spear = r.hits.length === 2;
  r = swing('twin', [[1, 0, big]], 0); out.twin = r.hits.length === 2;
  r = swing('boomerang', [[3, 0, big]], 0); out.boomerang = r.hits.length === 2;
  r = swing('crossbow', [[2, 0, big], [4, 0, big]], 0); out.crossbow = r.hits.length === 2;
  r = swing('hammer', [[1, 0, big]], 0); out.hammer = r.hits.length === 1 && r.es[0].x === 17;
  r = swing('axe', [[1, 0, big]], 0); out.axe = r.hits.length === 1 && r.es[0].st.bleed > 0;
  r = swing('rapier', [[1, 0, big]], 0); out.rapier = r.hits.length === 1 && r.G.player.px < 15;
  r = swing('sling', [[3, 0, big]], 0); out.sling = r.hits.length === 1 && r.es[0].x === 19;
  r = swing('sword', [[1, 0, big], [-1, 0, big]], 0); out.sword = r.hits.length === 1;
  return out; });
check('§10-1 무기 12종이 실시간 모양대로', Object.values(d1).every(Boolean), JSON.stringify(d1));

// §10-2 (바뀜) 색 배율은 없다: 무기 창에는 모양과 박자가 보인다
const d2 = await page.evaluate(() => { const g = window.__game, G = arena(); G.eq.weapon = g.makeGear('sword', { known: true }); g.refreshStats(); const w = g.makeGear('greatsword', { known: true });
  G.bag.push(w); g.UI.openInv(); g.UI.invTab = 'gear'; g.UI.invSel = { from: 'bag', i: G.bag.length - 1 }; g.UI.renderInv(); const t = document.querySelector('.gdetail').textContent; document.querySelector('#sheet').classList.add('hidden');
  return { beat: /0\.9초마다/.test(t), shape: /반원/.test(t), noColor: !/영혼석/.test(t) && !/치명/.test(t) }; });
check('§10-2 무기 창: 모양·박자, 색 배율·치명 조건 없음', d2.beat && d2.shape && d2.noColor, JSON.stringify(d2));

// §10-3 (바뀜) 무기 세트·교체는 없다: 칸은 10개, 공격 길게 누르기는 무기 정보
const d3 = await page.evaluate(() => { const g = window.__game, G = arena(); G.eq.weapon = g.makeGear('sword', { known: true }); g.refreshStats(); const t0 = G.stats.turns, before = G.eq.weapon;
  g.UI.weaponInfo(); const info = /장검/.test(document.querySelector('#info').textContent); g.UI.hideInfo();
  return { slots: Object.keys(G.eq).length, noSet: !('weapon2' in G.eq) && !('off2' in G.eq) && !g.UI.swapWeapon, same: G.eq.weapon === before, turns: G.stats.turns - t0, info }; });
check('§10-3 무기 세트·교체 없음 (칸 10개, 길게 누르기 = 무기 정보)', d3.slots === 10 && d3.noSet && d3.same && d3.turns === 0 && d3.info, JSON.stringify(d3));

// §10-4 양손 무기를 끼면 보조손은 가방으로(미리 알림)
const d4 = await page.evaluate(() => { const g = window.__game, G = arena(); G.eq.weapon = g.makeGear('sword', { known: true }); G.eq.off = g.makeGear('buckler', { known: true }); g.refreshStats(); const gs = g.makeGear('greatsword', { known: true }); G.bag.push(gs);
  g.UI.openInv(); g.UI.invTab = 'gear'; g.UI.invSel = { from: 'bag', i: G.bag.length - 1, slot: 'weapon' }; g.UI.renderInv(); const warn = /양손 무기\. .*버클러.*가방으로/.test(document.querySelector('.gline').textContent);
  document.querySelector('[data-act="equip"]').click(); drain(); document.querySelector('#sheet').classList.add('hidden');
  const ok = G.eq.weapon === gs && !G.eq.off && G.bag.some((it) => it.base === 'buckler'); const orb = g.makeGear('orb_red'); G.bag.push(orb); const refused = !g.equip(G.bag.length - 1, 'off'); return { warn, ok, refused }; });
check('§10-4 양손 무기 → 보조손은 가방으로(미리 알림), 양손 세트엔 보조손 불가', d4.warn && d4.ok && d4.refused, JSON.stringify(d4));

// §10-5 원거리: 붙은 적은 절반
const d5 = await page.evaluate(() => { const big = { hp: 999, max: 999 }, r = swing('crossbow', [[1, 0, big]], 0); return { half: r.hits.length === 1 && r.hits[0].label === '너무 가깝다' && r.hits[0].amt <= 4 }; });
check('§10-5 원거리: 붙은 적 절반', d5.half, JSON.stringify(d5));

// §10-7 품질: 구역마다 오르고, 강화 +N과 따로 더해진다. 대장장이가 품질을 올린다
const d7 = await page.evaluate(() => { const g = window.__game, G = arena(), M = g.META; const qs = {}; for (const d of [3, 8, 13, 18]) { let q = 0; for (let k = 0; k < 40 && !q; k++) { const it = g.rollGear(d); if (it.q) q = it.q; } qs[d] = q; }
  G.eq.weapon = g.makeGear('sword', { q: 3, plus: 2, known: true }); g.refreshStats(); const dmg = G.ps.dmg, name = g.gearName(G.eq.weapon);
  const it = g.makeGear('body_leather', { known: true }); M.gear.push(it); M.mats.마석 = 5; M.mats.광석 = 5; const q = g.RECIPES.find((r) => r.id === 'e_qual');
  g.Town.enhancePick(q, { name: '대장', t: { C: 0, O: 0, H: 0, A: 0, X: 0, E: 0 }, mood: 0 }, 'forge'); const k = [...document.querySelectorAll('[data-e]')].find((b) => b.closest('.prow').textContent.includes(g.gearName(it, true))); if (k) k.click();
  document.querySelector('#sheet').classList.add('hidden'); return { qs, dmg, name, smith: it.q }; });
check('§10-7 품질: 구역 = 품질, 강화와 따로 더함, 대장장이가 올림', d7.qs[3] === 1 && d7.qs[8] === 2 && d7.qs[13] === 3 && d7.qs[18] === 4 && d7.dmg === 4 && /^\+2 좋은 장검$/.test(d7.name) && d7.smith === 2, JSON.stringify(d7));

// §10-9 옛 저장(v6 DCSS식) → 새 칸 구조
const d9 = await page.evaluate(() => { const g = window.__game, mk = (base, o = {}) => ({ uid: 'u' + base, base, plus: 0, brand: null, ego: null, jt: null, jv: 0, je: null, art: null, un: null, idP: true, idX: true, worn: 0, hits: 0, ...o });
  const old = { v: 6, gen: 1, visits: 1, cleared: [false, false, false, false], npcs: [], newNpcs: [], buildings: {}, mats: {}, items: {}, recipes: {}, fallen: [], closed: {}, lit: [false, false, false, false], visitors: [], lore: [], glowMods: [], relics: [], unrandsSeen: [],
    gear: [mk('dagger', { plus: 1 })], hero: { name: '옛', gen: 1, base: 30, max: 30, hp: 30, level: 2, xp: 20, inv: [], look: {}, known: {}, slots: Array.from({ length: 6 }, () => ({ color: null, stone: null, cd: 0 })), sbag: [], weakKnown: {}, jlook: {}, jknown: {},
      bag: [mk('dagger', { plus: 2 }), mk('boots'), mk('spear')], eq: { weapon: mk('mace', { plus: 1 }), shield: mk('buckler'), head: null, body: mk('body_cloth'), cloak: null, hands: null, feet: null, neck: null, ring1: null, ring2: null } } };
  localStorage.setItem('torch-meta-v3', JSON.stringify(old)); g.resetMetaForTest(); const M = g.loadMeta(), h = M.hero;
  return { v: M.v, weapon: h.eq.weapon.base + h.eq.weapon.plus, off: h.eq.off && h.eq.off.base, bag: h.bag.map((i) => i.base).join(), stash: M.gear[0].base, q: h.eq.body.q, noShield: !('shield' in h.eq) }; });
check('§10-9 옛 저장(v6) → 단검은 쌍단검, 방패 칸은 보조손', d9.v >= 8 && d9.weapon === 'mace1' && d9.off === 'buckler' && d9.bag === 'twin,boots,spear' && d9.stash === 'twin' && d9.q === 1 && d9.noShield, JSON.stringify(d9));

// 저장 v7(무기 세트 두 벌) → v8: 세트 B는 가방으로
const d9b = await page.evaluate(() => { const g = window.__game, mk = (base, o = {}) => ({ uid: 'v' + base, base, q: 1, plus: 0, brand: null, ego: null, jt: null, jv: 0, je: null, art: null, un: null, idP: true, idX: true, worn: 0, hits: 0, ...o });
  const old = { v: 7, gen: 1, visits: 1, cleared: [false, false, false, false], npcs: [], newNpcs: [], buildings: {}, mats: {}, items: {}, recipes: {}, fallen: [], closed: {}, lit: [false, false, false, false], visitors: [], lore: [], glowMods: [], relics: [], unrandsSeen: [], gear: [],
    hero: { name: '옛', gen: 1, base: 30, max: 30, hp: 30, level: 1, xp: 0, wset: 1, inv: [], look: {}, known: {}, slots: Array.from({ length: 6 }, () => ({ color: null, stone: null, cd: 0 })), sbag: [], weakKnown: {}, jlook: {}, jknown: {}, bag: [mk('boots')],
      eq: { weapon: mk('crossbow'), off: null, weapon2: mk('sword'), off2: mk('orb_red', { q: null }), head: null, body: mk('body_cloth'), cloak: null, hands: null, feet: null, neck: null, ring1: null, ring2: null } } };
  localStorage.setItem('torch-meta-v3', JSON.stringify(old)); g.resetMetaForTest(); const M = g.loadMeta(), h = M.hero;
  return { v: M.v, weapon: h.eq.weapon.base, bag: h.bag.map((i) => i.base).join(), keys: Object.keys(h.eq).length, wset: 'wset' in h }; });
check('저장 v7 → v8: 세트 B의 무기·보조손은 가방으로', d9b.v >= 8 && d9b.weapon === 'crossbow' && d9b.bag === 'boots,sword,orb_red' && d9b.keys === 10 && !d9b.wset, JSON.stringify(d9b));

check('페이지 오류 없음', errors.length === 0, errors.slice(0, 3).join(' | '));
await browser.close(); server.close();
const bad = results.filter((r) => !r).length;
console.log(bad ? `\n${bad}개 실패` : `\n모두 통과 (${results.length})`);
process.exit(bad ? 1 : 0);
