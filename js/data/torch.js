export const TORCH_MAX = 100;
export const TORCH_BONUS = 20;
export const TORCH_BURN = 0.5;
export const LAMP_REFILL = 40;
export const JAR_REFILL = 60;
/** 모닥불에서 불씨 단지 하나 = 나무 */
export const JAR_WOOD = 5;
export const OLD_KEEPERS = ['이솔', '하람', '연우', '서하', '가온', '다인', '유담', '시온', '루아', '태린', '해민', '나린', '도하', '소이', '윤슬', '라온', '은재', '미루', '지안', '새별'];
/** 어둠: 횃불이 약할수록 적은 사나워지고(공격 +) 남기는 것은 많아진다(영혼석·장비 드롭 ×) */
export const DARK = { high: { atk: 0, drop: 1 }, mid: { atk: 0, drop: 1.25 }, low: { atk: 1, drop: 1.6 }, out: { atk: 2, drop: 2 } };
/** 영혼석 드롭: 무기로 쓰러뜨리면 45%, 그 밖 15% (어둠 배율을 곱한다) */
export const STONE_DROP = { weapon: 0.45, other: 0.15 };
export const torchTier = (v) => v <= 0 ? 'out' : v < 25 ? 'low' : v < 50 ? 'mid' : 'high';
export const torchSight = (v, base = 7) => v <= 0 ? 1 : v < 25 ? Math.max(1, base - 4) : v < 50 ? Math.max(1, base - 2) : base;
