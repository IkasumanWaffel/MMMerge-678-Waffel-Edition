import re, json, glob
import os, sys
R=(sys.argv[1] if len(sys.argv) > 1 else '../..').rstrip('/') + '/'
WANT='SpcAttack PlayerExtra PartyLight TurnBasedState TurnBasedQueueItem BloodSplat CharacterPortrait CharacterDollType CharacterVoices HouseRules ShopRule WeaponShopRule ArmorShopRule ArcomageRule ShopRep HousesExtra ArmorPicsCoords EquipCoordinates EquipCoordsCloak ReagentSettings MissileDirection'.split()
out={}
for f in sorted(glob.glob(R+'Structs/*.lua')):
    txt=open(f,encoding='utf-8',errors='replace').read()
    for m in re.finditer(r'^function structs\.f\.(\w+)\s*\(define[^)]*\)\n(.*?)^end',txt,flags=re.S|re.M):
        n=m.group(1)
        if n not in WANT or n in out: continue
        rows=[]
        for line in m.group(2).split('\n'):
            code=re.sub(r'--.*','',line)
            if '.Info' in code: code=code[:code.index('.Info')]
            b=re.search(r"\.bit\(\s*'(\w+)'\s*,\s*(0x[0-9A-Fa-f]+|\d+)",code)
            if b: rows.append((b.group(1),'bit '+b.group(2))); continue
            ct=re.search(r"\.CustomType\(\s*'(\w+)'",code)
            if ct: rows.append((ct.group(1),'custom')); continue
            fm=re.search(r"(?:^|\]|\s)\.((?:alt\.)?[\w().,\s+\-*]*?)\s*'(\w+)'",code)
            if fm and not code.strip().startswith('local'):
                t=fm.group(1).replace('alt.','').strip()
                rows.append((fm.group(2),t))
        out[n]={'file':f.replace(R,''),'rows':rows}
json.dump(out,open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'mergestructs.json'),'w'),indent=1)
for k in WANT: print(k, out.get(k,{}).get('file'), out.get(k,{}).get('rows'))
