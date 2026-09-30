// 성장: 등불지기와 주민이 같은 규칙 — 레벨마다 점수 1, 기본 Class 둘까지 (docs/설계_직업.md §3.4)
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { addXp, canSpend, newProg, spend } from '../../js/core/progress.js';
import { G } from '../../js/core/state.js';
import { gainXp } from '../../js/core/stones.js';
import { CLASS_RULE } from '../../js/data/classes.js';
import { arena, events } from './harness.mjs';

test('새 사람은 레벨 1에 점수 1', () => { const p = newProg(); assert.equal(p.level, 1); assert.equal(p.points, 1); });

test('경험이 쌓이면 레벨마다 점수 1, 10에서 멈춘다', () => {
  const p = newProg();
  assert.equal(addXp(p, CLASS_RULE.xp[3]), 3); assert.equal(p.level, 4); assert.equal(p.points, 4);
  addXp(p, 1e9); assert.equal(p.level, 10); assert.equal(p.points, 10); assert.equal(addXp(p, 100), 0);
});

test('점수 찍기: Class 둘까지, 합은 레벨 이하', () => {
  const p = newProg(); addXp(p, CLASS_RULE.xp[2]); // 레벨 3
  assert.ok(spend(p, 'fighter')); assert.ok(spend(p, 'cleric'));
  assert.ok(!canSpend(p.build, 'bard', p.points), '셋째 Class는 안 된다');
  assert.ok(spend(p, 'fighter')); assert.equal(p.points, 0);
  assert.ok(!spend(p, 'fighter'), '점수가 없다');
  assert.deepEqual(p.build.levels, { fighter: 2, cleric: 1 });
});

test('등불지기: 적을 쓰러뜨리면 경험, 레벨업하면 기본 HP +2 · 점수', () => {
  arena([]); const base = G.heroBase;
  gainXp({ max: CLASS_RULE.xp[1], boss: false });
  assert.equal(G.prog.level, 2); assert.equal(G.prog.points, 2); assert.equal(G.heroBase, base + 2);
  assert.ok(events.some((e) => e.type === 'levelUp'));
});

test('주민이 등불을 이으면 그 사람의 성장이 그대로 온다', async () => {
  const M = await import('../../js/core/meta.js');
  M.loadMeta();
  const n = M.makeNpc('hunter'); addXp(n.prog, CLASS_RULE.xp[4]); spend(n.prog, 'ranger');
  const h = M.newHero(n);
  assert.equal(h.prog, n.prog); assert.equal(h.prog.level, 5); assert.equal(h.prog.build.levels.ranger, 1);
});
