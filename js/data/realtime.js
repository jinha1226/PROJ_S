/* ================= 실시간: 움직일 때만 시간이 흐른다 (docs/설계_실시간_전환.md §1~§3) ================= */
export const RT = {
  tick: 0.05, // 고정 틱(초)
  maxTicks: 3, // 한 프레임에 돌리는 최대 틱(느린 기기에서 판정이 건너뛰지 않게)
  turn: 0.3, // 걸음 기준: 옛 1턴 = 한 칸 걷는 시간(횃불·회복·떠도는 무리·적 박자)
  heroSpeed: 4.0, // 칸/초
  radius: { hero: 0.3, goblin: 0.28, rat: 0.22, leech: 0.26, shaman: 0.28, archer: 0.28, mage: 0.3, charger: 0.38, npc: 0.28 },
  bossRadius: 0.5,
  waterCost: 1.5, // 길찾기: 물은 1.5배 먼 길
  stuck: 0.4, // 자동 걷기가 이만큼(초) 못 움직이면 멈춘다
  joyZone: 0.42, // 화면 아래 이 비율 안에서 누르면 조이스틱
  joyDead: 10, // px: 이만큼 밀어야 방향이 생긴다
  joyMax: 60, // px: 끝까지 민 거리
  joyHoldMs: 140, // 이만큼 누르고 있으면 조이스틱이 켜진다(짧은 탭은 시간을 흘리지 않는다)
  restTap: 250, // 대기 버튼을 이보다 짧게 누르면 쉬기
  restMax: 40, // 쉬기는 옛 40턴까지
};
/* ================= 전투 코어 (docs/설계_전투_코어.md §3) ================= */
export const COMBAT = {
  env: 1, // 상태이상·환경 박자(초): 출혈·중독·화상 1초마다, 지속도 초
  foeSpeed: { goblin: 3.3, rat: 5.3, leech: 1.65, shaman: 3.0, archer: 3.0, mage: 2.8, charger: 3.3, npc: 3.8 }, // 칸/초
  bossSpeed: 2.5,
  reach: 1.2, // 적 근접: 닿는 거리(중심 사이)
  whiff: 0.3, // 힘 모으는 동안 닿는 거리 + 이만큼 밖으로 빠지면 헛친다
  windup: 0.35, // 적 근접 힘 모으기(초)
  bossWindup: 0.6, // 보스의 무거운 한 방
  recover: 0.25, // 친 뒤 멈춰 있는 시간(초)
  beat: { rat: 0.8, chief: 1.6 }, // 적 공격 간격(초), 없으면 1. 보스는 이름으로
  tele: { cast: 1.2, aim: 0.8, charge: 1.0, slam: 1.2, horn: 1.2, heal: 0.5 }, // 예고(초)
  recast: 2.4, // 마법사 다시 외우기까지(초)
  healEvery: 2.5, hornEvery: 15, summonEvery: 10, blinkEvery: 4, // 주술사 치유 · 족장 뿔나팔 · 파수꾼 소환 · 대마법사 순간이동(초)
  chargeCd: 3, bossChargeCd: 1.5, // 돌진 뒤 다시 노리기까지(초)
  dashSpeed: 12, dashMax: 8, // 돌진: 칸/초, 최대 칸
  arrow: { speed: 14, range: 8 }, // 해골 궁수 화살
  keepAway: [3, 5], // 원거리·시전하는 적이 두려는 거리(칸)
  castRange: 6, aimRange: 7, // 주문·조준을 시작하는 거리(칸)
  wake: 4, // 깨어난 적이 깨우는 거리(칸)
  maxAdds: 2, // 족장·파수꾼이 불러 둔 부하가 이만큼이면 더 부르지 않는다
};
/** 등불지기 무기 모양 (docs/설계_실시간_전환.md §4): half = 부채꼴 반각(도), reach = 닿는 거리(칸), beat = 박자(초) */
export const WSHAPE = {
  front: { kind: 'arc', half: 35, reach: 1.6, beat: 0.6, one: true },
  fan: { kind: 'arc', half: 60, reach: 1.6, beat: 0.7 },
  twin: { kind: 'arc', half: 35, reach: 1.6, beat: 0.5, one: true, twice: 0.12 },
  sweep: { kind: 'arc', half: 90, reach: 1.6, beat: 0.9 },
  smash: { kind: 'arc', half: 35, reach: 1.6, beat: 0.9, one: true, knock: 1 },
  line2: { kind: 'line', reach: 2.6, width: 0.5, beat: 0.7 },
  bolt: { kind: 'proj', range: 7, beat: 1.2, pierce: true, speed: 16, look: 'quarrel' },
  shot: { kind: 'proj', range: 4, beat: 0.8, knock: 1, speed: 12, look: 'pebble' },
  boomerang: { kind: 'proj', range: 4, beat: 0.8, pierce: true, back: true, speed: 10, look: 'boomerang' },
};
/** 레이피어는 더 빠르다 */
export const RAPIER_BEAT = 0.5;
/** 영혼석: 직업·역할 시스템이 들어올 때까지 꺼 둔다(설계 §6) */
export const STONES_ON = false;
