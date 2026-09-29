/* ---------- 원형 턴제(자유 위치) 수치 — docs/prompts/추가_원형턴제_전투.txt ---------- */
export const FREE = {
  move: { hero: 5, goblin: 4, archer: 4, mage: 3, charger: 3, npc: 5 },
  bossMove: { chief: 4, lich: 3, boarking: 3, abyss: 3 },
  radius: { hero: 0.3, goblin: 0.28, archer: 0.28, mage: 0.3, charger: 0.38, npc: 0.28 },
  reach: 1.5, // 근접 사거리(중심 거리)
  spearReach: 2.5,
  archerRange: 6,
  speed: 3.6, // 탐험 걸음 m/s
  waterCost: 1.5,
  chargeMax: 8,
  pushStep: 0.1,
  circle: { square: 1.5, plus: 1.2 }, // 3×3 → 반지름 1.5, 십자 → 1.2
  envEvery: 1.4, // 탐험 중 환경(불 번짐·상태)이 한 번 흐르는 시간(초)
  joinRange: 12, // 전투 시작 시 이만큼 안의 깨어 있는 적이 들어온다
};
