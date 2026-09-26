#!/usr/bin/env python3
"""Draft setup/payoff metadata for existing status keywords; never change mechanics."""
import argparse
import json
from pathlib import Path
STATUS_WORDS = {'bleed':'출혈','fracture':'골절','stun':'기절','freeze':'빙결','exposed':'급소 노출','burn':'화상','poison':'중독','bind':'속박','weak':'약화','marked':'표식','confuse':'혼란'}
# Bespoke handlers whose rules do not describe their status application.
CODE_SETUP = {'wraith_kill':['confuse'],'SHIELD_HEART':['fracture'],'FROST_CLAW':['freeze'],'UNRAND_SHIELD':['fracture'],'UNRAND_PLAGUE':['poison']}
def draft(effect):
    setup, payoff = set(), set()
    for rule in effect.get('rules',[]):
        for action in rule.get('do',[]):
            for key in ('apply_status','spread_status'):
                status=action.get(key)
                if status in STATUS_WORDS: setup.add(STATUS_WORDS[status])
                elif status == 'harmful': setup.add('해로운 상태')
        for clause in rule.get('if',[]):
            for key in ('target_has','victim_had','status_is'):
                if clause.get(key) in STATUS_WORDS: payoff.add(STATUS_WORDS[clause[key]])
            for status in clause.get('target_has_any',[]):
                if status in STATUS_WORDS: payoff.add(STATUS_WORDS[status])
            if 'target_harmful_at_least' in clause or clause.get('harmful'): payoff.add('해로운 상태')
        for key in rule.get('mod',{}):
            if key.startswith('wound_chance.'):
                word={'SLASH':'출혈','IMPACT':'골절','PIERCE':'급소 노출'}.get(key.split('.')[-1])
                if word: setup.add(word)
            if key == 'bleed_pierce_chance': setup.add('출혈')
            if key == 'bleed_tick': payoff.add('출혈')
            if key == 'poison_tick': payoff.add('중독')
            if key.startswith('status_ticks.') and key.split('.')[-1] in STATUS_WORDS:
                setup.add(STATUS_WORDS[key.split('.')[-1]])
        handler=str(rule.get('args',{}).get('effect',rule.get('code','')))
        setup.update(STATUS_WORDS[s] for s in CODE_SETUP.get(handler,[]))
    return {word:('both' if word in setup and word in payoff else 'setup' if word in setup else 'payoff') for word in effect.get('keywords',[]) if word in setup or word in payoff}
if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('path',type=Path)
    parser.add_argument('--check',action='store_true',help='Show drafts without writing')
    args=parser.parse_args()
    data=json.loads(args.path.read_text())
    for ident,effect in data['effects'].items():
        if 'roles' in effect: continue
        result=draft(effect)
        if result:
            effect['roles']=result
            print(ident,json.dumps(result,ensure_ascii=False))
    if not args.check: args.path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
