// 전투 코어: 시간·이동·박자 (docs/설계_전투_코어.md §6) — node --test tests/sim
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { advance, setIntent } from '../../js/core/clock.js';
import { G } from '../../js/core/state.js';
import { CX, arena, foe, run, secs } from './harness.mjs';

const snap = () => JSON.stringify(G.ents.map((e) => [e.id, e.px, e.py, e.hp, e.act && e.act.t, e.cd])) + G.clock;

test('흐르지 않으면 100프레임을 돌려도 아무것도 변하지 않는다', () => {
  arena([[3, 0], [-3, 2, 'archer'], [0, -3, 'mage']]);
  setIntent(null, false);
  const before = snap();
  for (let k = 0; k < 100; k++) advance(0.05);
  assert.equal(snap(), before);
});

test('등불지기는 1초(20틱)에 4.0칸 걷는다', () => {
  arena([], { size: 8 });
  run(20, [1, 0]);
  assert.ok(Math.abs(G.player.px - CX - 4.0) < 0.06, `${G.player.px - CX}`);
});

test('고블린은 칸이 아니라 연속 좌표로 다가온다', () => {
  arena([[4, 1]]);
  const e = foe(), xs = [];
  for (let k = 0; k < 8; k++) { run(1); xs.push(e.px); }
  assert.ok(xs.some((x) => Math.abs(x - Math.round(x)) > 0.05), `소수 위치가 없다: ${xs}`);
  assert.ok(xs[7] < xs[0], '다가오지 않는다');
});

test('적 여럿은 같은 박자에 한꺼번에 치지 않는다', () => {
  arena([[1, 0, 'goblin', { atk: 0 }], [-1, 0, 'goblin', { atk: 0 }], [0, 1, 'goblin', { atk: 0 }]]);
  const starts = {};
  for (let k = 0; k < secs(1.5); k++) { run(1); for (const e of G.ents.slice(1)) if (e.act && e.act.kind === 'melee' && starts[e.id] == null) starts[e.id] = G.clock; }
  const ts = Object.values(starts);
  assert.equal(ts.length, 3, '셋 모두 힘을 모은다');
  assert.ok(new Set(ts.map((t) => t.toFixed(2))).size >= 2, `모두 같은 때: ${ts}`);
});

test('같은 씨앗·같은 입력이면 결과가 같다', () => {
  const go = () => { arena([[3, 0], [-3, 2, 'archer'], [2, -3, 'mage'], [-2, -2, 'rat']], { seed: 11 }); run(secs(4), [0.3, 0.2]); run(secs(2)); return snap(); };
  assert.equal(go(), go());
});

test('멈춘 동안에는 날아가던 화살도 그 자리에 떠 있다', () => {
  arena([[4, 0, 'archer', { cd: 0, cdInit: true, hp: 99, max: 99 }]]);
  G.eq.weapon = null;
  run(secs(0.85));
  const pr = G.projs[0];
  assert.ok(pr, '화살이 떴다');
  const x = pr.x;
  setIntent(null, false);
  for (let k = 0; k < 40; k++) advance(0.05);
  assert.equal(G.projs[0].x, x);
});
