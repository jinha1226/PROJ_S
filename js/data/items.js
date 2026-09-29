export const MATS = { 가죽: '🟫', 뼈: '🦴', 심장: '🫀', 약초: '🌿', 광석: '🪨', 기름: '🛢', 얼음: '🧊', 마석: '🔮' };

export const ITEMS = {
  heal: { cat: 'potion', name: '회복 물약', desc: 'HP 15 회복, 화상 해제.' },
  cure: { cat: 'potion', name: '해독 물약', desc: '중독·화상·젖음을 없애고 12턴간 중독되지 않는다.' },
  haste: { cat: 'potion', name: '가속 물약', desc: '8턴 동안 적이 한 번 움직일 때 두 번 행동한다.' },
  ember_jar: { cat: 'potion', name: '모닥불 불씨 단지', desc: '모닥불의 불씨로 횃불을 60 채운다.' },
  tele: { cat: 'scroll', name: '순간이동 두루마리', desc: '이 층의 먼 곳으로 순간이동한다.' },
  fear: { cat: 'scroll', name: '공포 두루마리', desc: '보이는 적 모두 6턴간 도망치고, 준비 중인 공격이 취소된다.' },
  blaze: { cat: 'scroll', name: '불꽃 두루마리', desc: '주변 8칸에 불길이 솟는다(4 화염). 풀·기름 위라면 조심.' },
  ident: { cat: 'scroll', name: '확인 두루마리', desc: '장비 하나의 정체를 드러낸다 — 장비 창에서 [확인].', target: true },
  enchW: { cat: 'scroll', name: '무기 강화 두루마리', desc: '무기 하나를 +1 (상한 +6) — 장비 창에서 [강화].', target: true },
  enchA: { cat: 'scroll', name: '방어구 강화 두루마리', desc: '방어구 하나를 +1 (몸통 +4, 그 밖 +2까지) — 장비 창에서 [강화].', target: true },
  recall: { cat: 'scroll', name: '귀환 두루마리', desc: '한 턴 동안 빛이 모인 뒤 정착지로 돌아간다(그 사이 맞으면 피해는 받는다). 전리품은 챙기지만 이 구역은 처음부터 다시. 보스 층에서는 쓸 수 없다.' },
  oil: { cat: 'throw', name: '기름병', desc: '십자 5칸에 기름을 쏟는다. 불이 닿으면 연쇄 폭발.' },
  water: { cat: 'throw', name: '물병', desc: '십자 5칸에 물웅덩이. 닿은 적은 젖는다 → 번개가 번지고, 얼면 오래 간다.' },
  smoke: { cat: 'throw', name: '연막탄', desc: '3×3 연기(6턴). 연기 너머로는 보이지 않아 궁수·마법사가 조준하지 못한다.' },
};

export const ITEM_W = [['heal', 16], ['cure', 9], ['haste', 8], ['tele', 8], ['fear', 9], ['blaze', 10], ['oil', 14], ['water', 14], ['smoke', 12]];
/** 처음부터 이름이 보이는 소모품(대상 장비를 골라 쓰는 두루마리·귀환) */
export const ALWAYS_KNOWN = ['recall', 'ident', 'enchW', 'enchA'];

export const ITEM_COL = { oil: 0x3a3440, water: 0x4d97ff, smoke: 0x9aa0aa };

export const APPEAR = {
  potion: [['붉은 물약', 0xff4a5a], ['탁한 초록 물약', 0x6fae4a], ['금빛 물약', 0xffc84a], ['푸른 거품 물약', 0x4aa8ff], ['보랏빛 물약', 0xb45aff], ['불씨 단지', 0xffc45c]],
  scroll: [['두루마리 「ZAR VOK」', 0xe8d6a8], ['두루마리 「MIRU TEL」', 0xe8c890], ['두루마리 「OSS KANDA」', 0xf0dcb8], ['두루마리 「PHEN NOR」', 0xdcc8a0], ['두루마리 「VEL ORIM」', 0xe0d0b0], ['두루마리 「KAS DUN」', 0xd8c0a0], ['두루마리 「ELU MAR」', 0xe4d4b4], ['두루마리 「TOR VEX」', 0xd4c4a0]],
  throw: [['금이 간 병', 0xb89a70], ['묵직한 병', 0x7a8090], ['흔들리는 유리구슬', 0x88c8d0], ['밀랍 봉한 항아리', 0xb07050]],
};

export const CAT_ICON = { potion: '🧪', scroll: '📜', throw: '🫙' };
