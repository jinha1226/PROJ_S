/* ================= 3차: 원정 흐름 · 정착지 ================= */
/** 받침에 맞는 조사: jo('수아', '이가') → '수아가' */
export function jo(w, pair) { const c = String(w).charCodeAt(String(w).length - 1) - 0xAC00, bat = c >= 0 && c < 11172 && c % 28 !== 0; const [a, b] = pair === '이가' ? ['이', '가'] : pair === '을를' ? ['을', '를'] : pair === '은는' ? ['은', '는'] : ['과', '와']; return w + (bat ? a : b); }
