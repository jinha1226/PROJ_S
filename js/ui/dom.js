export const $ = id => document.getElementById(id);
export const escape = text => String(text).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function button(label,action,options={}) {
  const b=document.createElement('button');b.textContent=label;b.addEventListener('click',action);Object.assign(b,options);return b;
}
export function openPanel(title) { $('panel-title').textContent=title;$('panel-body').replaceChildren();if(!$('panel').open)$('panel').showModal();return $('panel-body'); }
export function closePanel() {$('panel').close();}
export function notice(text) {const node=$('notice');node.textContent=text;node.hidden=false;clearTimeout(node.timer);node.timer=setTimeout(()=>node.hidden=true,2200);}
export function html(parent,markup) {const el=document.createElement('div');el.innerHTML=markup;parent.append(el);return el;}
