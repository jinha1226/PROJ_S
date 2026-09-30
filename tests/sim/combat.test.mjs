// 전투 코어: 무기 모양 · 힘 모으기 · 예고 · 상태이상 (docs/설계_전투_코어.md §6) — node --test "tests/sim/*.test.mjs"
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { setPos } from '../../js/core/space.js';
import { G } from '../../js/core/state.js';
import { S_WATER } from '../../js/data/terrain.js';
import { CX, CY, arena, events, foe, run, secs } from './harness.mjs';

const dummy = (o = {}) => ({ hp: 99, max: 99, atk: 0, ...o }); // 치지 않는 허수아비
const still = (e) => { e.cd = 99; e.st.stun = 99; }; // 움직이지도 치지도 않게

test('장검: 앞 1.6칸 안의 한 적만 친다(0.6초마다)', () => {
  arena([[1, 0, 'goblin', dummy()], [-1, 0, 'goblin', dummy()]], { weapon: 'sword' });
  for (const e of G.ents.slice(1)) still(e);
  run(secs(1.25));
  const [a, b] = [foe(1), foe(2)];
  assert.equal(events.filter((e) => e.type === 'swing').length, 3, '0.6초 박자: 0, 0.6, 1.2초');
  assert.ok((a.hp < 99) !== (b.hp < 99), `한 적만 맞는다: ${a.hp} ${b.hp}`);
});

test('장검: 1.6칸 밖은 못 친다', () => {
  arena([[2, 0, 'goblin', dummy()]], { weapon: 'sword' }); still(foe());
  run(secs(1));
  assert.equal(foe().hp, 99);
});

test('도리깨: 앞 넓은 부채꼴의 여럿을 한 번에', () => {
  arena([[1, 0, 'goblin', dummy()], [1, 1, 'goblin', dummy()], [1, -1, 'goblin', dummy()]], { weapon: 'flail' });
  for (const e of G.ents.slice(1)) still(e);
  run(1);
  assert.equal(G.ents.slice(1).filter((e) => e.hp < 99).length, 3);
});

test('대검 반달: 앞 반원은 모두, 뒤는 못 친다', () => {
  arena([[1, 0, 'goblin', dummy()], [0.3, 1, 'goblin', dummy()], [-1.2, 0, 'goblin', dummy({ hp: 50, max: 50 })]], { weapon: 'greatsword' });
  for (const e of G.ents.slice(1)) still(e);
  G.target = foe(1).id;
  run(1);
  assert.ok(foe(1).hp < 99 && foe(2).hp < 99, '앞의 둘');
  assert.equal(foe(3).hp, 50, '뒤');
});

test('창: 줄지은 둘을 꿰뚫는다', () => {
  arena([[1, 0, 'goblin', dummy()], [2, 0, 'goblin', dummy()]], { weapon: 'spear' });
  for (const e of G.ents.slice(1)) still(e);
  run(1);
  assert.ok(foe(1).hp < 99 && foe(2).hp < 99);
});

test('쌍단검: 한 적을 두 번(0.12초 간격)', () => {
  arena([[1, 0, 'goblin', dummy()]], { weapon: 'twin' }); still(foe());
  run(secs(0.2));
  assert.equal(events.filter((e) => e.type === 'hit' && e.id === foe().id).length, 2);
});

test('전투 망치: 치고 1칸 밀친다', () => {
  arena([[1, 0, 'goblin', dummy()]], { weapon: 'hammer' }); still(foe());
  run(1);
  assert.equal(foe().x, CX + 2);
});

test('석궁: 투사체가 날아가 줄지은 적을 꿰뚫는다, 벽 뒤는 못 쏜다', () => {
  arena([[3, 0, 'goblin', dummy()], [4, 0, 'goblin', dummy()]], { weapon: 'crossbow' });
  for (const e of G.ents.slice(1)) still(e);
  run(1);
  assert.equal(foe(1).hp, 99, '날아가는 중');
  run(secs(0.4));
  assert.ok(foe(1).hp < 99 && foe(2).hp < 99, `${foe(1).hp} ${foe(2).hp}`);
});

test('부메랑: 갔다가 돌아오며 두 번 맞힌다', () => {
  arena([[2, 0, 'goblin', dummy()]], { weapon: 'boomerang' }); still(foe());
  run(secs(0.75));
  assert.equal(events.filter((e) => e.type === 'hit' && e.id === foe().id).length, 2);
});

test('적 근접: 힘 모으는 0.35초 사이 빠지면 헛친다', () => {
  arena([[1, 0, 'goblin', { atk: 5, hp: 99, max: 99, cd: 0, cdInit: true }]], { weapon: 'sword' });
  G.eq.weapon = null; // 맞받아치지 않게: 맨손(칼 없는 싸움)도 앞 한 적
  run(1);
  assert.equal(foe().act && foe().act.kind, 'melee', '힘을 모은다');
  run(secs(0.35), [-1, 0]); // 뒤로 1.4칸
  run(secs(0.3));
  assert.equal(G.player.hp, 40, '맞지 않는다');
  assert.ok(events.some((e) => e.type === 'whiff'), '헛침');
});

test('적 근접: 가만히 있으면 맞는다', () => {
  arena([[1, 0, 'goblin', { atk: 5, hp: 99, max: 99, cd: 0, cdInit: true }]]);
  run(secs(0.5));
  assert.ok(G.player.hp < 40);
});

test('기절하면 힘 모으던 행동이 끊긴다', () => {
  arena([[1, 0, 'goblin', { atk: 5, hp: 99, max: 99, cd: 0, cdInit: true }]]);
  G.eq.weapon = null;
  run(2);
  assert.ok(foe().act);
  foe().st.stun = 2; run(1);
  assert.equal(foe().act, null);
  run(secs(0.5));
  assert.equal(G.player.hp, 40);
});

test('마법사 원: 1.2초 동안 차오른 뒤 터지고, 밖에 있으면 피해 0', () => {
  arena([[4, 0, 'mage', { elem: 'fire', cd: 0, cdInit: true, hp: 99, max: 99 }]]);
  G.eq.weapon = null;
  run(1);
  const a = foe().act;
  assert.equal(a && a.kind, 'cast');
  assert.ok(a.cells.some(([x, y]) => x === CX && y === CY), '발밑이 예고 안');
  run(secs(0.5));
  assert.equal(G.player.hp, 40, '아직 안 터짐');
  run(secs(0.6), [0, 1]); // 옆으로 2칸 넘게 비켜난다
  run(secs(0.4));
  assert.equal(G.player.hp, 40, '비켰으니 0');
});

test('마법사 번개: 물 위의 젖은 무리에게 번진다', () => {
  arena([[-4, 0, 'mage', { elem: 'bolt', cd: 0, cdInit: true }], [1, 0, 'goblin', dummy()], [2, 0, 'goblin', dummy()]]);
  G.eq.weapon = null;
  for (let x = CX - 1; x <= CX + 3; x++) G.surf[CY * G.W + x] = S_WATER;
  for (const e of G.ents) e.st.wet = 3;
  still(foe(2)); still(foe(3));
  run(secs(1.3));
  assert.ok(G.player.hp < 40 && foe(2).hp < 99 && foe(3).hp < 99, `${G.player.hp} ${foe(2).hp} ${foe(3).hp}`);
});

test('궁수: 0.8초 조준 뒤 쏘고, 비키면 빗나간다', () => {
  arena([[4, 0, 'archer', { cd: 0, cdInit: true, hp: 99, max: 99 }]]);
  G.eq.weapon = null;
  run(1);
  assert.equal(foe().act && foe().act.kind, 'aim');
  run(secs(0.6), [0, 1]);
  run(secs(1));
  assert.equal(G.player.hp, 40);
  arena([[4, 0, 'archer', { cd: 0, cdInit: true, hp: 99, max: 99 }]]);
  G.eq.weapon = null;
  run(secs(1.4));
  assert.ok(G.player.hp < 40, '가만히 있으면 맞는다');
});

test('돌진: 1초 띠 예고 뒤 달린다, 비키면 벽에 박혀 기절', () => {
  arena([[-3, 0, 'charger', { cd: 0, cdInit: true, hp: 99, max: 99 }]]);
  G.eq.weapon = null;
  run(1);
  assert.equal(foe().act && foe().act.kind, 'charge');
  run(secs(0.5), [0, 1]); run(secs(0.5), [0, 1]); // 띠에서 비켜난다
  run(secs(1.5));
  assert.equal(G.player.hp, 40);
  assert.ok(foe().st.stun > 0 || events.some((e) => e.type === 'bump' && e.id === foe().id), '벽에 박힘');
});

test('주술사: 다친 동료를 치유한다', () => {
  arena([[3, 0, 'shaman', { cd: 0, cdInit: true }], [3, 2, 'goblin', { hp: 3, max: 12, atk: 0 }]]);
  G.eq.weapon = null; still(foe(2));
  run(secs(1));
  assert.equal(foe(2).hp, 7);
});

test('족장: 뿔나팔로 고블린 둘을 부른다', () => {
  arena([[3, 0, 'goblin', { boss: 'chief', name: '고블린 족장', hp: 110, max: 110, atk: 0, hornT: 0 }]]);
  G.eq.weapon = null;
  const n0 = G.ents.length;
  run(secs(1.5));
  assert.equal(G.ents.length, n0 + 2);
});

test('출혈 3: 1초마다 1씩 3초', () => {
  arena([[3, 0, 'goblin', dummy()]]); still(foe());
  G.eq.weapon = null; G.envAcc = 0;
  foe().st.bleed = 3;
  run(secs(1.02)); assert.equal(foe().hp, 98);
  run(secs(2)); assert.equal(foe().hp, 96);
  run(secs(2)); assert.equal(foe().hp, 96);
});

test('빙결 2초: 그동안 움직이지도 치지도 않는다', () => {
  arena([[3, 0, 'goblin', { atk: 5, hp: 99, max: 99 }]]);
  G.eq.weapon = null; G.envAcc = 0;
  foe().st.frozen = 2; const x0 = foe().x;
  run(secs(1.9));
  assert.equal(foe().px, x0);
  run(secs(1));
  assert.ok(foe().px < x0, '풀리면 다가온다');
});

test('전투 중에는 자동 회복이 없고, 전투 뒤에는 회복한다', () => {
  arena([[3, 0, 'goblin', dummy()]]); still(foe());
  G.eq.weapon = null; G.player.hp = 20;
  run(secs(4)); assert.equal(G.player.hp, 20, '깨어 보이는 적');
  foe().alive = false;
  run(secs(4)); assert.ok(G.player.hp > 20);
});

test('기다림 망토: 제자리에서 1초 흘릴 때마다 보호막', () => {
  arena([]);
  G.ps.patience = 2; G.player.shield = 0;
  run(secs(1.05));
  assert.equal(G.player.shield, 2);
});

test('같은 칸의 둘 모두 불에 탄다(entsAt)', async () => {
  const { fireAt } = await import('../../js/core/elements.js');
  arena([[2, 0, 'goblin', dummy()], [2, 0, 'goblin', dummy()]]);
  setPos(foe(2), CX + 2.3, CY); setPos(foe(1), CX + 1.8, CY);
  fireAt(CX + 2, CY, 3);
  assert.ok(foe(1).hp < 99 && foe(2).hp < 99);
});
