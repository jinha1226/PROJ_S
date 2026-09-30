export const BUILD = {
  floor: { name: '바닥', line: '방의 바닥', wood: 1, stone: 0, color: '#b39a71' },
  wall: { name: '벽', line: '방을 감싼다', wood: 1, stone: 1, color: '#bdac8c' },
  door: { name: '문', line: '드나드는 길', wood: 2, stone: 0, color: '#976648' },
  bed: { name: '침대', line: '하루를 쉰다', wood: 4, stone: 0, room: 'lodging', color: '#d3a48e' },
  anvil: { name: '모루', line: '쇠를 두드린다', wood: 0, stone: 5, room: 'smith', color: '#778da0' },
  stove: { name: '화덕', line: '수프를 끓인다', wood: 2, stone: 3, room: 'dining', color: '#d09059' },
  table: { name: '탁자', line: '마주 앉는다', wood: 3, stone: 0, color: '#a37852' },
  farm: { name: '밭', line: '빛 아래 자란다', wood: 2, stone: 0, color: '#657f48' },
  training: { name: '훈련장', line: '함께 갈 준비', wood: 5, stone: 3, color: '#ad7d55' },
};
export const PRESETS = {
  lodging: { name: '작은 숙소', line: '침대 두 개', furniture: [{ x: 1, y: 1, kind: 'bed' }, { x: 2, y: 1, kind: 'bed' }] },
  smith: { name: '대장간', line: '모루 하나', furniture: [{ x: 1, y: 1, kind: 'anvil' }] },
  dining: { name: '식당', line: '따뜻한 자리', furniture: [{ x: 1, y: 1, kind: 'stove' }, { x: 2, y: 1, kind: 'table' }] },
};
export const ROOM_NAMES = { lodging: '숙소', smith: '대장간', dining: '식당', empty: '빈 방' };
export const BUILD_ERRORS = { darkness: '불빛 밖입니다', occupied: '자리가 찼습니다', cost: '재료가 모자랍니다', bounds: '땅 끝입니다', fire: '불가 자리입니다' };
