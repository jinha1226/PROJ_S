// 정착지 2단계: 시간과 일 · 제작 (docs/설계_정착지_2단계.md §12)
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { colony, have, hourTick, markCut, passHours } from '../../js/core/colony.js';
import { addOrder, rollQuality, stationWorker, tierOf } from '../../js/core/crafting.js';
import { META, loadMeta, resetMeta } from '../../js/core/meta.js';
import { inLight, invalidate, placeBps, stockOf } from '../../js/core/settlement.js';
import { SCX, SCY, TR } from '../../js/data/build.js';
import { mulberry32, setR } from '../../js/util/rng.js';
import './harness.mjs';

function fresh() { resetMeta(); setR(mulberry32(3)); loadMeta(); invalidate(); colony(); META.time = { day: 1, hour: 7, min: 0 }; return META; }
const hours = (n) => { for (let k = 0; k < n; k++) hourTick(); };

test('새 땅: 근처에 나무 20 · 바위 10 · 광맥 3 이상', () => {
  const M = fresh(), s = M.settle; let t = 0, r = 0, o = 0;
  for (let i = 0; i < s.terr.length; i++) { const x = i % s.W, y = (i / s.W) | 0; if ((x - SCX) ** 2 + (y - SCY) ** 2 > 13 * 13) continue; if (s.terr[i] === TR.tree) t++; if (s.terr[i] === TR.rock) r++; if (s.terr[i] === TR.ore) o++; }
  assert.ok(t >= 20 && r >= 10 && o >= 3, `${t} ${r} ${o}`);
});

test('채집: 목표 재고보다 적으면 베고, 더미를 창고로 나른다', () => {
  const M = fresh(); M.colony.targets.나무 = 80; const w0 = stockOf('나무');
  hours(10);
  assert.ok(stockOf('나무') > w0, `${w0} → ${stockOf('나무')}`);
});

test('목표 재고를 넘으면 채집을 멈춘다', () => {
  const M = fresh(); M.colony.targets = { 나무: 0, 돌: 0, 광석: 0 }; M.settle.stock.식사 = 99; M.settle.stock.식량 = 99;
  const before = have('나무') + have('돌'); hours(8);
  assert.equal(have('나무') + have('돌'), before);
});

test('베기 표시한 곳은 목표 재고와 상관없이 먼저 벤다', () => {
  const M = fresh(), s = M.settle; M.colony.targets = { 나무: 0, 돌: 0, 광석: 0 };
  const i = s.terr.findIndex((t, k) => t === TR.tree && inLight(k % s.W, (k / s.W) | 0)); assert.ok(i >= 0);
  markCut(i % s.W, (i / s.W) | 0, i % s.W, (i / s.W) | 0); hours(4);
  assert.notEqual(s.terr[i], TR.tree);
});

test('짓기: 청사진은 주민이 시간을 들여 짓는다', () => {
  const M = fresh(), s = M.settle;
  let at = null; for (let d = 2; d < 6 && !at; d++) for (const [x, y] of [[SCX + d, SCY + d], [SCX - d, SCY + d], [SCX + d, SCY - d]]) if (!at && placeBps([{ L: 'floor', k: 'wood', x, y }]).ok.length) at = [x, y];
  assert.ok(at, '빈 칸'); const i = at[1] * s.W + at[0];
  assert.equal(s.floor[i], 0, '아직');
  hours(3);
  assert.ok(s.floor[i] > 0, '지었다');
});

test('식사: 아침·저녁에 먹고, 먹을 게 없으면 배고프다', () => {
  const M = fresh(); M.settle.stock.식량 = 1; M.settle.stock.식사 = 0; M.time.hour = 6;
  hours(1); // 7시 아침
  assert.equal(M.settle.stock.식량, 0);
  assert.ok(M.npcs.some((n) => n.hunger > 0));
});

test('제작: 대장간에 대장장이가 서서 한손 무기를 만든다', () => {
  const M = fresh(); M.mats.마석 = 10; M.mats.광석 = 3; M.mats.가죽 = 2; const g0 = (M.gear || []).length;
  assert.ok(tierOf('forge') >= 1, '대장간이 있다');
  assert.equal(stationWorker('forge').job, 'blacksmith');
  addOrder('wpn1');
  hours(8);
  assert.equal((M.gear || []).length, g0 + 1); assert.equal(M.mats.마석, 7);
});

test('품질: 1등급 작업방이면 기본 낡은(1), 특기면 오를 수 있다', () => {
  const smith = { job: 'blacksmith', t: { O: 0, C: 0 }, mood: 0 }, other = { job: 'cook', t: { O: 0, C: 0 }, mood: 0 };
  setR(mulberry32(1)); const qs = Array.from({ length: 200 }, () => rollQuality(smith, 1)), qo = Array.from({ length: 200 }, () => rollQuality(other, 1));
  assert.ok(qs.filter((q) => q === 2).length > 60 && qo.every((q) => q === 1));
});

test('원정 뒤: 지난 시간만큼 돌리고 요약한다(최대 3일)', () => {
  fresh(); META.colony.targets.나무 = 99;
  const sum = passHours(5 * 12);
  assert.equal(sum.hours, 60); assert.ok((sum.got.나무 || 0) > 0 && sum.meals > 0, JSON.stringify(sum));
  assert.equal(passHours(500).hours, 72);
});

test('전리품: 모든 적이 마석, 마법사는 자기 원소 결정, 보스는 마석 10 · 심장', async () => {
  const { lootOf } = await import('../../js/core/combat.js');
  setR(mulberry32(5));
  const mage = Array.from({ length: 50 }, () => lootOf({ type: 'mage', elem: 'bolt' })).flat();
  assert.ok(mage.filter((m) => m === '마석').length >= 90 && mage.includes('번개 결정') && !mage.includes('불 결정'));
  const boss = lootOf({ type: 'goblin', boss: 'chief' });
  assert.equal(boss.filter((m) => m === '마석').length, 10); assert.ok(boss.includes('심장'));
});
