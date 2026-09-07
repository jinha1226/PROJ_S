import {readFileSync,writeFileSync} from 'node:fs';
const data=JSON.parse(readFileSync(process.argv[2], 'utf8'));
const rows=data.rows;
const mean=(a)=>a.reduce((s,v)=>s+v,0)/a.length;
const groups={};
for(const r of rows)(groups[r.scenario+':'+r.policy]??=[]).push(r);
const summary={};
for(const [key,g] of Object.entries(groups)) {
  const wins=g.filter(r=>r.win).length;
  const p=wins/g.length, z=1.96, d=1+z*z/g.length;
  const center=(p+z*z/(2*g.length))/d;
  const half=z*Math.sqrt(p*(1-p)/g.length+z*z/(4*g.length*g.length))/d;
  summary[key]={n:g.length,wins,rate:100*p,ci95:[100*(center-half),100*(center+half)],
    hp:mean(g.map(r=>r.party_hp)),survivors:mean(g.map(r=>r.survivors)),
    time:mean(g.map(r=>r.time)),body:g.reduce((a,r)=>{for(const [k,v] of Object.entries(r.body??{}))a[k]=(a[k]??0)+v;return a;},{}),first_kill:g.reduce((a,r)=>(a[r.first_kill]=(a[r.first_kill]??0)+1,a),{}),
    skill_uses:g.reduce((a,r)=>{for(const [k,v] of Object.entries(r.uses)) a[k]=(a[k]??0)+v;return a;},{})};
}
const pairs={};
for(const scenario of new Set(rows.map(r=>r.scenario))) {
  const reference=groups[scenario+':nearest'];
  for(const policy of ['mage','support','frontline','weakest']) {
    const g=groups[scenario+':'+policy];
    const diffs=g.map((r,i)=>Number(r.win)-Number(reference[i].win));
    const gain=diffs.filter(d=>d===1).length, loss=diffs.filter(d=>d===-1).length;
    pairs[scenario+':'+policy]={gain,loss,delta_pp:100*mean(diffs)};
  }
}
const kitAssociations={};
const base=groups['both:nearest'];
for(const skill of ['FIREBOLT','MEND','BARRIER','STRIKE','SHOVE']) {
  const counts={};
  for(const r of base) {
    const n=r.skills.filter(kit=>kit.includes(skill)).length;
    const g=counts[n]??={n:0,wins:0};g.n++;g.wins+=Number(r.win);
  }
  kitAssociations[skill]=counts;
}
const output=JSON.stringify({battles:rows.length,body_enabled:data.body_enabled??null,replay_ok:data.replay_ok,
  invalid:rows.reduce((s,r)=>s+r.invalid,0),censored:rows.filter(r=>r.outcome==='censored').length,
  summary,pairs,kitAssociations},null,2);
if(process.argv[3]) writeFileSync(process.argv[3],output+'\n');
else console.log(output);
