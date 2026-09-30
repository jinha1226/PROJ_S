export const SLOTS = { weapon: '무기', shield: '방패', head: '머리', body: '몸통', cloak: '망토', hands: '장갑', feet: '신발', neck: '목걸이', ring1: '반지', ring2: '반지' };
export const ARMOR = {
  cloth: { name: '천옷', line: '가벼운 천', slot: 'body', armor: 1, weight: 0 },
  leather: { name: '가죽 갑옷', line: '질긴 가죽', slot: 'body', armor: 3, weight: 1 },
  chain: { name: '사슬 갑옷', line: '엮은 쇠', slot: 'body', armor: 5, weight: 2 },
  plate: { name: '판금 갑옷', line: '두꺼운 쇠', slot: 'body', armor: 8, weight: 3 },
  shield: { name: '둥근 방패', line: '앞을 막는다', slot: 'shield', armor: 2, weight: 1 },
  helm: { name: '철 투구', line: '머리를 감싼다', slot: 'head', armor: 2, weight: 0 },
  cloak: { name: '여행 망토', line: '어둠을 두른다', slot: 'cloak', armor: 1, weight: 0 },
  gloves: { name: '가죽 장갑', line: '손을 지킨다', slot: 'hands', armor: 1, weight: 0 },
  boots: { name: '장화', line: '돌길을 딛는다', slot: 'feet', armor: 1, weight: 0 },
  ring: { name: '루비 반지', line: '붉은 돌', slot: 'ring1', armor: 0, weight: 0 },
  amulet: { name: '은 목걸이', line: '가슴의 은빛', slot: 'neck', armor: 0, weight: 0 },
};
export const BRANDS = { fire: '화염', ice: '냉기', lightning: '번개', poison: '독', blood: '피', crush: '파쇄', pierce: '꿰뚫기', drain: '흡혈' };
export const EGOS = { fire: '내화', ice: '내한', lightning: '절연', poison: '해독', thorns: '가시', guard: '보호', insight: '통찰', waterwalk: '물걸음' };
export const RELICS = [ { name: '소라의 마지막 칼', owner: '소라', line: '불빛 곁에서 누군가 웃었다' }, { name: '하람의 잿빛 망토', owner: '하람', line: '끝내 돌아오지 못한 길' } ];
