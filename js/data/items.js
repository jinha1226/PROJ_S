export const MATS = { 가죽: '🟫', 뼈: '🦴', 심장: '🫀', 약초: '🌿', 광석: '🪨', 기름: '🛢', 얼음: '🧊', 마석: '🔮' };

export const ITEMS = {
  heal: { cat: 'potion', name: '회복 물약', desc: 'HP 15를 회복하고 화상을 끈다.' },
  cure: { cat: 'potion', name: '해독 물약', desc: '중독·화상·젖음을 없애고 12초 동안 중독되지 않는다.' },
  haste: { cat: 'potion', name: '가속 물약', desc: '8초 동안 1.5배 빨리 걷는다.' },
  ember_jar: { cat: 'potion', name: '모닥불 불씨 단지', desc: '모닥불의 불씨로 횃불을 60 채운다.' },
  tele: { cat: 'scroll', name: '순간이동 두루마리', desc: '이 층의 먼 곳으로 순간이동한다.' },
  fear: { cat: 'scroll', name: '공포 두루마리', desc: '보이는 적이 모두 6초 동안 도망친다. 준비하던 공격도 멈춘다.' },
  blaze: { cat: 'scroll', name: '불꽃 두루마리', desc: '주변 8칸에 불길이 솟아 불 4. 풀과 기름을 타고 번진다.' },
  ident: { cat: 'scroll', name: '확인 두루마리', desc: '장비 하나의 정체를 드러낸다.', target: true },
  enchW: { cat: 'scroll', name: '무기 강화 두루마리', desc: '무기 하나를 강화한다.', target: true },
  enchA: { cat: 'scroll', name: '방어구 강화 두루마리', desc: '방어구 하나를 강화한다.', target: true },
  recall: { cat: 'scroll', name: '귀환 두루마리', desc: '빛이 모인 뒤 정착지로 돌아간다.' },
  oil: { cat: 'throw', name: '기름병', desc: '십자 모양으로 기름을 쏟는다. 불이 닿으면 잇따라 터진다.' },
  water: { cat: 'throw', name: '물병', desc: '십자 모양으로 물을 쏟는다. 닿은 적은 젖는다.' },
  smoke: { cat: 'throw', name: '연막탄', desc: '떨어진 곳 둘레에 6초 동안 연기가 낀다. 연기 너머로는 궁수와 마법사가 겨누지 못한다.' },
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
