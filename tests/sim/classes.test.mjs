// 직업: 레벨 분배 → Class · 수식어 · Role · 기울기, 스킬 60개가 모두 돈다 (docs/설계_직업.md) — node --test "tests/sim/*.test.mjs"
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { setPos } from '../../js/core/space.js';
import { G } from '../../js/core/state.js';
import { CSKILLS } from '../../js/data/class-skills.js';
import { BASE_IDS, PAIRS } from '../../js/data/classes.js';
import { classOf, setClass, skillParams, validLevels } from '../../js/sim/classes.js';
import { foeTarget } from '../../js/sim/action.js';
import { aiPick, skillReady, useSkill } from '../../js/sim/skillfx.js';
import { CX, CY, arena, events, foe, run, secs } from './harness.mjs';

const L = (o) => ({ levels: o });

test('레벨 분배 규칙: 총 10, Class 둘까지', () => {
  assert.ok(validLevels({ fighter: 7, cleric: 3 }));
  assert.ok(!validLevels({ fighter: 7, cleric: 4 }));
  assert.ok(!validLevels({ fighter: 4, cleric: 3, bard: 3 }));
});

test('기본 · 곁가지 · 한 우물 · 두 우물(기운·균형) 이름과 Role', () => {
  const f3 = classOf(L({ fighter: 3 }));
  assert.equal(f3.name, '파이터'); assert.deepEqual(f3.skills.map((s) => s.id), ['f_block', 'f_taunt']);
  const g = classOf(L({ fighter: 10 }));
  assert.equal(g.name, '가디언'); assert.equal(g.skills.length, 5); assert.ok(g.skills.filter((s) => !s.sig).every((s) => s.upgraded));
  assert.equal(classOf(L({ fighter: 7, cleric: 3 })).title, '방패의 팔라딘');
  assert.equal(classOf(L({ fighter: 7, cleric: 3 })).role, 'tank');
  assert.equal(classOf(L({ fighter: 3, cleric: 7 })).title, '기도의 팔라딘');
  assert.equal(classOf(L({ fighter: 3, cleric: 7 })).role, 'healer');
  const bal = classOf({ levels: { fighter: 5, cleric: 5 }, main: 'healer' });
  assert.equal(bal.title, '팔라딘'); assert.equal(bal.role, 'healer'); assert.equal(bal.sub, 'tank');
  const dip = classOf(L({ fighter: 8, cleric: 2 }));
  assert.equal(dip.kind, 'dip'); assert.ok(dip.skills.some((s) => s.id === 'c_heal') && !dip.skills.some((s) => s.id === 'c_shield'));
});

test('두 우물 15개 × 기울기 셋 모두 이름이 선다', () => {
  for (const key of Object.keys(PAIRS)) {
    const [a, b] = key.split('+');
    for (const [x, y] of [[7, 3], [5, 5], [3, 7]]) { const k = classOf(L({ [a]: x, [b]: y })); assert.equal(k.kind, 'pair'); assert.ok(k.title.endsWith(PAIRS[key].name)); assert.equal(k.skills.length, x === y ? 8 : 7); }
  }
  for (const a of BASE_IDS) assert.equal(classOf(L({ [a]: 10 })).kind, 'mastery');
});

test('기운 쪽에 따라 전용 스킬이 달라진다(팔라딘)', () => {
  const tank = classOf(L({ fighter: 7, cleric: 3 })), heal = classOf(L({ fighter: 3, cleric: 7 }));
  const P = (k, id) => skillParams(k.skills.find((s) => s.id === id), { levels: k.levels }).p;
  assert.equal(P(tank, 'pa_oath').share, 0.7); assert.equal(P(heal, 'pa_oath').share, 0.3); assert.ok(P(heal, 'pa_oath').shield > 0);
  assert.ok(P(tank, 'pa_smite').stun > P(heal, 'pa_smite').stun, '반대쪽(파이터)이 높으면 기절이 길다');
  assert.ok(P(heal, 'pa_smite').heal > P(tank, 'pa_smite').heal, '기대는 쪽(클레릭)이 높으면 치유가 크다');
});

test('스킬 60개가 모두 쓰이고 오류 없이 돈다', () => {
  const ids = Object.keys(CSKILLS);
  assert.equal(ids.length, 60);
  const owner = (id) => { for (const a of BASE_IDS) { if (classOf(L({ [a]: 10 })).skills.some((s) => s.id === id)) return L({ [a]: 10 }); } for (const key of Object.keys(PAIRS)) { const [a, b] = key.split('+'); if (PAIRS[key].skills.includes(id)) return L({ [a]: 5, [b]: 5 }); } return null; };
  for (const id of ids) {
    const b = owner(id); assert.ok(b, id);
    arena([[2, 0, 'goblin', { hp: 99, max: 99, atk: 1 }], [2, 1, 'goblin', { hp: 99, max: 99, atk: 1 }]], { cls: { ...b, loadout: [id] } });
    const p = G.player; p.hp = 20;
    const S = CSKILLS[id], t = S.tgt === 'ally' ? [p.x, p.y] : S.tgt === 'self' ? [null, null] : [CX + 2, CY];
    run(1);
    foe(1).act = { kind: 'melee', t: 0, wind: 9, recover: 0, done: false, target: 0 }; // 힘 모으는 적(끊기 스킬용)
    assert.ok(skillReady(p, id), id);
    assert.ok(useSkill(p, id, ...t), `${id} 대상 못 잡음`);
    run(secs(1.5));
    assert.ok(p.scd[id] > 0 || events.some((e) => e.type === 'skillName'), id);
  }
});

test('방패 세우기: 앞에서 오는 공격은 막고, 뒤에서 오면 맞는다', () => {
  arena([[1, 0, 'goblin', { atk: 5, hp: 99, max: 99, cd: 0, cdInit: true }]], { cls: L({ fighter: 1 }) });
  G.eq.weapon = null; G.player.ang = 0;
  useSkill(G.player, 'f_block'); run(secs(0.8));
  assert.equal(G.player.hp, 40);
  arena([[1, 0, 'goblin', { atk: 0, hp: 99, max: 99 }], [-1, 0, 'goblin', { atk: 5, hp: 99, max: 99, cd: 0, cdInit: true }]], { cls: L({ fighter: 1 }) });
  foe(1).st.stun = 99; G.target = foe(1).id; G.eq.weapon = null; useSkill(G.player, 'f_block'); run(secs(0.8)); // 앞의 적을 치느라 등을 보인다
  assert.ok(G.player.hp < 40);
});

test('도발: 도발당한 적은 가까운 적 대신 나를 노린다(미끼)', () => {
  arena([[3, 0, 'goblin', { atk: 3, hp: 99, max: 99 }]], { cls: { levels: { rogue: 5, bard: 5 }, loadout: ['tr_decoy'] } });
  G.eq.weapon = null;
  useSkill(G.player, 'tr_decoy', CX + 1, CY + 2); run(secs(0.5));
  assert.equal(foeTarget(foe()), G.ents.find((e) => e.decoy), '적이 미끼를 노린다');
  assert.equal(G.player.hp, 40);
});

test('묶기: 올가미 덫을 밟은 적은 3초 못 움직인다', () => {
  arena([[4, 0, 'goblin', { atk: 0, hp: 99, max: 99 }]], { cls: L({ ranger: 3 }) });
  G.eq.weapon = null;
  useSkill(G.player, 'ra_trap', CX + 2, CY); run(secs(1.2));
  const x = foe().px; run(secs(1));
  assert.ok(Math.abs(foe().px - x) < 0.01 && foe().fx.root);
});

test('죽음 유예: 쓰러질 피해를 받아도 HP 1', async () => {
  const { damage } = await import('../../js/core/combat.js');
  arena([], { cls: L({ cleric: 5 }) });
  useSkill(G.player, 'c_ward', CX, CY); run(secs(0.4));
  damage(G.player, 99, 'hit', { src: null });
  assert.equal(G.player.hp, 1); assert.ok(G.player.alive);
});

test('수호의 맹세: 아군이 받는 피해를 대신 받는다', async () => {
  const { damage } = await import('../../js/core/combat.js');
  arena([[3, 0, 'goblin', { atk: 0, hp: 99, max: 99 }]], { cls: { levels: { fighter: 7, cleric: 3 }, loadout: ['pa_oath'] } });
  const ally = { id: 900, type: 'goblin', name: '동료', team: 'party', ally: true, x: CX, y: CY + 1, hp: 30, max: 30, st: { ...foe().st }, alive: true, face: [0, 1], atk: 0 };
  G.ents.push(ally); setPos(ally, CX, CY + 1); ally.cdInit = true; ally.cd = 99;
  useSkill(G.player, 'pa_oath', CX, CY + 1); run(secs(0.3));
  damage(ally, 10, 'hit', { src: foe() });
  assert.equal(ally.hp, 27, '방패의 팔라딘: 70%를 대신 받는다'); assert.ok(G.player.hp <= 34 && G.player.hp >= 33);
});

test('예지(바드 특성): 주변 적의 힘 모으기가 느리다', () => {
  arena([[1, 0, 'goblin', { atk: 0, hp: 99, max: 99, cd: 0, cdInit: true }]], { cls: L({ bard: 5 }) });
  G.eq.weapon = null; run(2);
  const a = foe().act; assert.ok(a); const t0 = a.t; run(4);
  assert.ok(a.t - t0 < 0.2 - 1e-6, `${a.t - t0}`);
});

test('AI: 힘 모으는 적이 있으면 끊는 스킬부터', () => {
  arena([[3, 0, 'goblin', { atk: 0, hp: 99, max: 99 }]], { cls: { levels: { bard: 5 }, loadout: ['b_song', 'b_disc', 'b_fog'] } });
  run(1); foe().act = { kind: 'melee', t: 0, wind: 9, recover: 0, done: false, target: 0 };
  const pick = aiPick(G.player);
  assert.ok(pick && (pick.id === 'b_disc' || pick.id === 'b_song'), JSON.stringify(pick));
});

test('등불지기 Class HP: 파이터 10은 HP +10', () => {
  arena([], { cls: L({ fighter: 10 }) });
  setClass(G.player, L({ fighter: 10 }));
  assert.equal(G.player.classHp, 10);
});
