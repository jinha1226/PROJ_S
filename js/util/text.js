export function jo(word, pair = '은/는') {
  const code = word.charCodeAt(word.length - 1) - 44032;
  const final = code >= 0 && code <= 11171 && code % 28 !== 0;
  return word + pair.split('/')[final ? 0 : 1];
}
