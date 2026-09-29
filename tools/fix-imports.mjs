// js/ 모듈의 빠진 import를 채우고, 쓰지 않는 import를 지우고, 의존 규칙(docs/코드정리_가이드.md §4) 위반을 알린다.
// 사용: node tools/fix-imports.mjs [--check]   (--check: 고치지 않고 문제만 보고, 있으면 exit 1)
import * as acorn from 'acorn';
import * as walk from 'acorn-walk';
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..', 'js');
const CHECK = process.argv.includes('--check');
const files = [];
(function scan(d) { for (const f of fs.readdirSync(d)) { const p = path.join(d, f); if (fs.statSync(p).isDirectory()) scan(p); else if (f.endsWith('.js')) files.push(p); } })(ROOT);
const parse = (s) => acorn.parse(s, { ecmaVersion: 'latest', sourceType: 'module', allowAwaitOutsideFunction: true });
const rel = (from, to) => { let r = path.relative(path.dirname(from), to).replace(/\\/g, '/'); return r.startsWith('.') ? r : './' + r; };
const layer = (f) => path.relative(ROOT, f).split(path.sep)[0].replace('.js', '');

const exportsOf = {}; // name → file
const info = {};
for (const f of files) {
  const src = fs.readFileSync(f, 'utf8'), ast = parse(src), exp = [], imports = [], top = new Set();
  for (const st of ast.body) {
    if (st.type === 'ImportDeclaration') { imports.push(st); for (const s of st.specifiers) top.add(s.local.name); continue; }
    const d = st.type === 'ExportNamedDeclaration' ? st.declaration : st;
    if (st.type === 'ExportNamedDeclaration' && !st.declaration && !st.source) for (const s of st.specifiers) exp.push(s.exported.name);
    if (!d) continue;
    const names = d.type === 'VariableDeclaration' ? d.declarations.map((x) => x.id.name).filter(Boolean) : d.id ? [d.id.name] : [];
    for (const n of names) { top.add(n); if (st.type === 'ExportNamedDeclaration') exp.push(n); }
  }
  for (const n of exp) if (!exportsOf[n] && !f.endsWith('render/diorama.js')) exportsOf[n] = f;
  info[f] = { src, ast, imports, top };
}
let problems = 0;
for (const f of files) {
  const { src, ast, imports, top } = info[f];
  const used = new Set(), locals = new Set();
  const pat = (n) => { if (!n) return; if (n.type === 'Identifier') locals.add(n.name); else if (n.type === 'ObjectPattern') n.properties.forEach((p) => pat(p.value || p.argument)); else if (n.type === 'ArrayPattern') n.elements.forEach(pat); else if (n.type === 'AssignmentPattern') pat(n.left); else if (n.type === 'RestElement') pat(n.argument); };
  walk.full(ast, (n) => { if (n.type === 'VariableDeclarator') pat(n.id); if (/Function/.test(n.type)) n.params.forEach(pat); if (n.type === 'CatchClause') pat(n.param); });
  walk.fullAncestor(ast, (node, _s, anc) => {
    if (node.type !== 'Identifier') return;
    const p = anc[anc.length - 2];
    if (p && p.type === 'MemberExpression' && p.property === node && !p.computed) return;
    if (p && (p.type === 'Property' || p.type === 'MethodDefinition') && p.key === node && !p.computed && !p.shorthand) return;
    if (p && (p.type === 'ImportSpecifier' || p.type === 'ImportNamespaceSpecifier' || p.type === 'ExportSpecifier')) return;
    used.add(node.name);
  });
  const importedFrom = {};
  for (const im of imports) for (const s of im.specifiers) importedFrom[s.local.name] = im.source.value;
  const missing = {};
  for (const n of used) {
    if (top.has(n) || importedFrom[n]) continue;
    const src2 = exportsOf[n]; if (!src2 || src2 === f) continue;
    if (locals.has(n)) continue;
    (missing[src2] ||= []).push(n);
  }
  // 없는 이름을 import (export가 사라졌는데 import가 남은 경우)
  for (const im of imports) {
    if (!im.source.value.startsWith('.')) continue;
    const tgt = path.resolve(path.dirname(f), im.source.value), T = info[tgt];
    if (!T) { problems++; console.log(`${path.relative(ROOT, f)}: 없는 파일 ${im.source.value}`); continue; }
    const exp = new Set(Object.entries(exportsOf).filter(([, v]) => v === tgt).map(([k]) => k));
    for (const s of im.specifiers) if (s.type === 'ImportSpecifier' && !exp.has(s.imported.name) && !tgt.endsWith('render/diorama.js')) { problems++; console.log(`${path.relative(ROOT, f)}: ${path.relative(ROOT, tgt)}에 ${s.imported.name} 없음`); }
  }
  // 쓰지 않는 import
  const unused = [];
  for (const im of imports) for (const s of im.specifiers) if (s.type === 'ImportSpecifier' && !used.has(s.local.name) && !src.includes(`export { ${s.local.name}`)) unused.push(s.local.name);
  // 규칙
  const L = layer(f);
  for (const im of imports) {
    const tgt = im.source.value.startsWith('.') ? path.resolve(path.dirname(f), im.source.value) : null; if (!tgt) continue;
    const T = layer(tgt);
    const bad = (L === 'core' && ['render', 'ui', 'town', 'flow'].includes(T)) || (L === 'data' && T !== 'data') || (L === 'util' && T !== 'util') || (L === 'render' && ['ui', 'town', 'flow'].includes(T));
    if (bad) { problems++; console.log(`규칙 위반: ${path.relative(ROOT, f)} → ${path.relative(ROOT, tgt)}`); }
  }
  if (!Object.keys(missing).length && !unused.length) continue;
  problems += Object.values(missing).flat().length + unused.length;
  console.log(`${path.relative(ROOT, f)}: 빠짐 ${JSON.stringify(Object.fromEntries(Object.entries(missing).map(([k, v]) => [path.relative(ROOT, k), v])))}${unused.length ? ' · 안 씀 ' + unused.join(',') : ''}`);
  if (CHECK) continue;
  // 고치기: import 줄 다시 쓰기
  const want = {}, bare = [];
  for (const im of imports) {
    const key = im.source.value;
    if (!im.specifiers.length) { bare.push(src.slice(im.start, im.end)); continue; } // 부수 효과 import는 원래 순서대로 맨 뒤에
    if (im.specifiers.some((s) => s.type !== 'ImportSpecifier')) { (want[key] ||= { raw: src.slice(im.start, im.end) }); continue; }
    for (const s of im.specifiers) if (!unused.includes(s.local.name)) ((want[key] ||= { names: new Set() }).names ||= new Set()).add(s.local.name);
  }
  for (const [file, ns] of Object.entries(missing)) { const key = rel(f, file); for (const n of ns) ((want[key] ||= { names: new Set() }).names ||= new Set()).add(n); }
  const lines = Object.entries(want).sort(([a], [b]) => (a.startsWith('.') - b.startsWith('.')) || a.localeCompare(b)).map(([k, v]) => v.raw || (v.names.size ? `import { ${[...v.names].sort().join(', ')} } from '${k}';` : '')).filter(Boolean).concat(bare);
  const first = imports.length ? imports[0].start : 0, last = imports.length ? imports[imports.length - 1].end : 0;
  const out = src.slice(0, first) + lines.join('\n') + (imports.length ? '' : '\n\n') + src.slice(last);
  fs.writeFileSync(f, out);
}
console.log(problems ? `문제 ${problems}건${CHECK ? '' : ' (고침)'}` : '문제 없음');
process.exit(CHECK && problems ? 1 : 0);
