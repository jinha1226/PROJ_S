import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { parse } from 'acorn';
const errors=[],graph=new Map();
async function walk(dir){const entries=await readdir(dir,{withFileTypes:true});const result=[];for(const e of entries){const p=path.join(dir,e.name);if(e.isDirectory())result.push(...await walk(p));else if(/\.(js|mjs)$/.test(p))result.push(p);}return result;}
const allowed={util:[],data:['util','data'],sim:['util','data','sim'],town:['util','data','town'],render:['util','data','render'],ui:['util','data','sim','town','render','ui']};
for(const file of [...await walk('js'),...await walk('tools'),...await walk('tests')]){
  const source=await readFile(file,'utf8');
  if(source.split('\n').length>400)errors.push(`${file}: exceeds 400 lines`);
  let ast;try{ast=parse(source,{ecmaVersion:'latest',sourceType:'module'});}catch(e){errors.push(`${file}: ${e.message}`);continue;}
  const layer=file.split('/')[1],deps=[];
  for(const node of ast.body){
    if(!['ImportDeclaration','ExportNamedDeclaration','ExportAllDeclaration'].includes(node.type)||!node.source)continue;
    const spec=node.source.value;
    if(!spec.startsWith('.')){if(file.startsWith('js/') && layer!=='render' && layer!=='ui')errors.push(`${file}: external import ${spec}`);continue;}
    const target=path.normalize(path.join(path.dirname(file),spec));deps.push(target);
    try{await readFile(target);}catch{errors.push(`${file}: missing ${spec}`);}
    if(file.startsWith('js/') && allowed[layer] && !allowed[layer].includes(target.split('/')[1]))errors.push(`${file}: forbidden dependency ${target}`);
  }
  graph.set(file,deps);
  if(['sim','town'].includes(layer) && file.startsWith('js/')){
    if(/\b(window|document|THREE|setTimeout|requestAnimationFrame)\b|Date\.now|Math\.random/.test(source))errors.push(`${file}: browser or nondeterministic rule`);
    if(/[가-힣]/.test(source.replace(/heroName:\s*'[^']*'/g,'')))errors.push(`${file}: Korean rule text`);
  }
}
const done=new Set(),stack=new Set();
function check(file){if(stack.has(file)){errors.push(`Import cycle at ${file}`);return;}if(done.has(file))return;stack.add(file);for(const next of graph.get(file)||[])check(next);stack.delete(file);done.add(file);}
for(const file of graph.keys())check(file);
if(errors.length){console.error(errors.join('\n'));process.exitCode=1;}else console.log(`Checked ${graph.size} modules: syntax, imports, cycles, rule purity, 400-line limit.`);
