// 주문 장비: 지팡이 · 오브 · 반지·목걸이 옵션 (docs/설계_직업.md §3.4.2)
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { calcStats, makeGear, refreshStats } from '../../js/core/gear.js';
import { G } from '../../js/core/state.js';
import { useSkill } from '../../js/sim/skillfx.js';
import { CX, CY, arena, run } from './harness.mjs';

const stats = (eq) => calcStats({ weapon: null, off: null, head: null, body: null, cloak: null, hands: null, feet: null, neck: null, ring1: null, ring2: null, ...eq }, {});

test('지팡이 주문력 +2(강화 +3마다 +1), 오브 주문력 1 + 강화치', () => {
  assert.equal(stats({ weapon: makeGear('staff', { known: true }) }).spell, 2);
  assert.equal(stats({ weapon: makeGear('staff', { plus: 3, known: true }) }).spell, 3);
  assert.equal(stats({ weapon: makeGear('staff', { known: true }), off: makeGear('orb_red', { plus: 2, known: true }) }).spell, 5);
});

test('반지·목걸이: 비전 · 질주 · 집중 · 치유 · 현자 · 바람 · 명료 · 활력', () => {
  const r = (jt, jv) => { const it = makeGear('ring', { jt }); it.jv = jv; return it; }, n = (jt) => makeGear('neck', { jt });
  const s = stats({ ring1: r('arcana', 2), ring2: r('focus', 10), neck: n('sage') });
  assert.equal(s.spell, 4); assert.equal(s.cdr, 18);
  assert.equal(stats({ ring1: r('swift', 5), neck: n('wind') }).speed, 13);
  assert.equal(stats({ ring1: r('mend', 3) }).healUp, 3);
  assert.equal(stats({ neck: n('vigor') }).maxHp, 8);
  assert.equal(stats({ ring1: r('focus', 12), ring2: r('focus', 12), neck: n('clarity') }).cdr, 39);
});

test('집중: 스킬 쿨타임이 준다', () => {
  arena([], { cls: { levels: { cleric: 1 }, loadout: ['c_heal'] } });
  const it = makeGear('neck', { jt: 'clarity' }); G.eq.neck = it; refreshStats(); run(1);
  useSkill(G.player, 'c_heal', CX, CY);
  assert.ok(G.player.scd.c_heal < 4.6 && G.player.scd.c_heal > 3, String(G.player.scd.c_heal));
});
