import re, csv, json
R='/home/claude/mmmerge-678-waffel-edition/'
mon=[r.split('\t') for r in open(R+'Edits of revamp.T.lod/MONSTERS.txt',encoding='latin1',newline='').read().split('\r\n')]
bol={r.split('\t')[0]:r.split('\t') for r in open(R+'Tables/Bolster - monsters.txt',encoding='latin1').read().splitlines()}
EL=['Fire','Air','Water','Earth','Mind','Spirit','Body','Light','Dark','Ener','Phys']
SPELL={'fire bolt':'Fire','fireball':'Fire','incinerate':'Fire','meteor shower':'Fire','dragon breath':'Dark',
 'lightning bolt':'Air','sparks':'Air','ice bolt':'Water','ice blast':'Water','acid burst':'Water','poison spray':'Body',
 'blades':'Earth','rock blast':'Earth','deadly swarm':'Earth','mind blast':'Mind','psychic shock':'Mind','psychic shockt':'Mind',
 'spirit lash':'Spirit','harm':'Body','flying fist':'Body','toxic cloud':'Dark','finger of death':'Dark','light bolt':'Light',
 'paralyze':'Light','mass curse':'Dark','day-o-gods':'Light'}
# name keywords -> element (first match wins)
KW=[(r'droid|robot|blaster|reactor|patrol unit|terminator|seeker|tolberti|emerald dragon|sapphire dragon|ruby dragon|mega-dragon|varn|unit\b','Ener'),
 (r'\bbat\b|bloodsucker|blood sucker','Body'),
 (r'moon|necro|lich|death|doom|dark|skeleton|\bbone|shadow|\bnight|undead|cuisinart|\bblack','Dark'),
 (r'\bfire|flame|inferno|magma|lava|efre|phoenix|\bember|smoke|\bburn|\bhell|salamander|red dragon|(?<!dust )devil|demon|\bimp\b|\bgog\b|magog|gogling','Fire'),
 (r'\bice\b|frost|snow|water|\bsea\b|shark|kraken|wyrm|unicorn|sprite|genie|djinn|triton|naga|mermaid|\beel\b|\btide','Water'),
 (r'\bair\b|storm|lightning|thunder|\bwind|tempest|dust devil|cloud|hawk|\broc\b|thunderbird|titan|ether|crystal walker','Air'),
 (r'earth|stone|\brock|boulder|\bclay|golem|gargoyle|\bsand|crystal|\btree|treant|cactus|troglodyte|dwar|basilisk|gorgon|medusa|behemoth','Earth'),
 (r'ghost|spectre|specter|wraith|banshee|phantom|wight|\bshade|spirit|poltergeist|harpy|angel|\bmonk|ninja|master of','Spirit'),
 (r'\beye\b|beholder|psych|\bmind|\bfear\b|nightmare|agar|terror|vampire|siren','Mind'),
 (r'spider|snake|serpent|cobra|viper|wasp|scorpion|couatl|ooze|slime|jelly|\brat\b|ratman|wererat|toad|mushroom|corpse|zombie|ghoul|ghast|mummy|troll|lizard|swamp|mosquito|leech|\bbaa\b|cannibal|thief|cutpurse|robber|bandit|assassin|wolf|\bbear\b|\bcat\b|\bdog\b|hound|panther|tiger|\blion\b|\bboar\b|griffin|wyvern|hydra|dragonfly|minicore|chicken','Body'),
 (r'\bsun\b|\blight\b|cleric|priest|paladin|crusader|templar|\bglow|dancing light','Light')]
KIND={'Undead':'Spirit','Demon':'Fire','Dragon':'Fire','Construct':'Earth','Troll':'Body','Ogre':'Phys','Minotaur':'Phys','Titan':'Air',
 'Lizardman':'Body','Goblin':'Body','DarkElf':'Dark','Elf':'Phys','Dwarf':'Earth','Human':'Phys','Creature':'Body','Elemental':'Phys','Immobile':'Earth'}
ARCHERS={'Human','Elf','DarkElf','Dwarf','Goblin','Lizardman'}
PAIR={'Fire':'Air','Air':'Fire','Water':'Earth','Earth':'Water','Body':'Mind','Mind':'Spirit','Spirit':'Body','Light':'Spirit','Dark':'Body','Ener':'Fire','Phys':'Mind'}
HUMANOID={'Human','Elf','DarkElf','Dwarf','Goblin','Minotaur','Ogre','Troll','Lizardman','Titan','Undead','Demon'}
ROGUE=re.compile(r'thief|cutpurse|robber|bandit|assassin|rogue|brigand|burglar|smuggler|cutthroat|ninja|spy')
THUG=re.compile(r'thug|ruffian|buccaneer|pirate|corsair|head hunter|cannibal|brigand|bandit')
ROCK=re.compile(r'troll|cyclop|titan|giant $|troglodyte|gorgon|behemoth|golem')
def dice(s):
    m=re.match(r'\s*(\d+)\s*[dD]\s*(\d+)\s*(?:\+\s*(\d+))?',s or '')
    return (int(m[1]),int(m[2]),int(m[3] or 0)) if m else None
def avg(d): return d[0]*(d[1]+1)/2+d[2]
def scale(d,k):
    n,s,b=d; t=avg(d)*k; b2=round(b*k); n2=max(1,round((t-b2)/((s+1)/2)))
    return f'{n2}D{s}'+(f'+{b2}' if b2 else '')
def spells(r):
    out=[]
    for c in (r[25],r[27]):
        m=re.match(r'"?\s*([A-Za-z\- ]+?)\s*,',c or '')
        if m and m[1].lower() in SPELL: out.append(SPELL[m[1].lower()])
    return out
rows=[]
for r in mon[4:]:
    if len(r)<39 or not r[0].strip().isdigit(): continue
    i=r[0].strip(); b=bol.get(i)
    if not b: continue
    name=r[1].strip(); low=name.lower()+' '; kind=b[2].strip() or '-'; xk=b[3]; style=b[6].strip() or 'Wimpy'
    peasant='Peasant' in xk
    a1=(r[17].strip(),r[18].strip(),r[19].strip()); a2=(r[21].strip(),r[22].strip(),r[23].strip(),r[20].strip())
    a1ranged=a1[2] not in ('0','')
    aff=[]; src=[]
    for pat,el in KW:
        if re.search(pat,low): aff.append(el); src.append('name'); break
    if a1[0] not in ('Phys','0','') : aff.append(a1[0]); src.append('attack 1')
    for e in spells(r): aff.append(e); src.append('spell')
    if KIND.get(kind): aff.append(KIND[kind]); src.append('kind')
    seen=[];
    for e in aff:
        if e not in seen: seen.append(e)
    aff=seen or ['Phys']; prim=aff[0]; sec=aff[1] if len(aff)>1 else prim
    d=dice(a1[1]) or (1,4,0)
    hum=kind in HUMANOID
    if a1[2]=='Ener' and kind=='Human' and re.search(r'blaster|tolberti|robert the wise',low):
        p=None; why='blaster: shoots in melee and at range alike, no second attack'
    elif peasant or name.lower() in ('cat','chicken','dog','rat','fish','peasant'):
        p=None; why='peasant / pet: no second attack'
    elif style=='Strength':
        if a1ranged: p=('Phys',scale(d,1.0),'0',25); why='ranged attacker: a melee blow up close'
        elif prim!='Phys': p=(prim,scale(d,1.0),'0',15); why=f'{prim} strike in melee'
        else: p=('Phys',scale(d,1.5),'0',15); why='heavy blow'
    elif style=='Endurance':
        el=prim if prim!='Phys' else 'Body'
        p=(el,scale(d,1.0),'0',20); why=f'{el} melee (draining, crushing)'
    elif style=='Speed':
        weak = src and src[0]=='kind'
        if a1ranged:
            el='Phys' if (weak or prim=='Phys') else prim; p=(el,scale(d,0.75),'0',20); why='quick melee strike'
        elif prim not in ('Phys','Body') and not weak:
            p=(prim,scale(d,0.75),prim,25); why=f'{prim} missile'
        elif kind in ARCHERS or ROCK.search(low):
            if ROCK.search(low): p=('Phys',scale(d,0.75),'Rock',25); why='thrown rock'
            else: p=('Phys',scale(d,0.75),'Arrow',25); why='arrows / thrown weapons'
        else: p=('Body',scale(d,0.75),'0',20); why='quick rending / venomous strike'
    elif style=='Magic':
        if a1ranged and a1[0]==prim:
            if kind in ('Elemental','Construct'): el=prim; p=(el,scale(d,1.0),'0',25); why=f'{el} touch up close'
            else:
                el = sec if sec not in (prim,'Phys') else PAIR.get(prim,'Mind')
                p=(el,scale(d,1.0),el,30); why=f'{el} bolt (second school)'
        else:
            el=prim if prim!='Phys' else 'Mind'; p=(el,scale(d,1.0),el,30); why=f'{el} bolt'
    else:  # Wimpy, not peasant
        el=prim if prim!='Phys' else 'Phys'
        p=(el,scale(d,0.75),'0',10); why='weak melee'
    if p is not None:
        if ROGUE.search(low) and not a1ranged:
            el='Body' if prim in ('Body','Phys') else prim
            p=(el,scale(d,0.75),'Arrow',20); why='thrown knives / poisoned darts'
        elif kind=='Elemental' and not a1ranged and prim!='Phys':
            p=(prim,scale(d,0.75),prim,25); why=f'{prim} missile from afar'
        if re.search(r'wight|wraith',low) and not a1ranged:   # melee-only undead: a draining touch
            el=PAIR.get(a1[0],'Body') if a1[0]!='Phys' else 'Body'
            p=(el,scale(d,0.75),'0',20); why=f'{el} draining touch (melee only)'
        # a second attack that only repeats the first
        trained = (kind in ('Human','Dwarf','-','0','') and not (THUG.search(low) or ROGUE.search(low) or ROCK.search(low) or 'cyclop' in low)) or (kind=='Ogre' and 'mage' not in low)
        if why=='heavy blow' and trained: why='hard hit (club or falchion)' if kind=='Ogre' else 'hard hit (a trained fighter)'
        elif p[0]==a1[0] and ((p[2]=='0')==(not a1ranged)) and not why.startswith('current'):
            if not a1ranged and p[0] not in ('Phys',):
                p=(p[0],scale(d,0.75),p[0],25); why=f'{p[0]} missile (the melee one is Attack 1)'
            elif a1ranged:
                p=(p[0],scale(d,1.0),'0',20); why=f'{p[0]} touch up close (the missile is Attack 1)'
            elif ROCK.search(low):
                p=('Phys',scale(d,0.75),'Rock',15); why='thrown rock or boulder'
            else:
                p=('Phys',scale(d,0.75),'Arrow',15); why='thrown spear, axe or javelin'
    cur = '' if a2[0] in ('0','') else f'{a2[0]} {a2[1]} {"melee" if a2[2] in ("0","") else a2[2]} {a2[3]}%'
    if p is None: act='none' if not cur else 'remove?'
    else:
        same = cur and a2[0]==p[0] and ((a2[2] in ('0',''))==(p[2]=='0'))
        a2ranged = a2[2] not in ('0','')
        hardhit = cur and a2[0]=='Phys' and not a2ranged and a1[0]=='Phys' and not a1ranged and kind in ('Human','Dwarf','-','0','') and not THUG.search(low) and not ROGUE.search(low)
        complements = cur and (a2ranged!=a1ranged or a2[0]!=a1[0] or hardhit)
        if same or complements:
            act='keep current'; p=(a2[0],a2[1],a2[2],int(a2[3] or 0)); why=('current hard hit kept (a trained fighter)' if hardhit else 'current second attack already complements the first')
            if a2[2]=='ArrowF' and a2[0]!='Fire': act='replace'; p=('Fire',)+p[1:]; why='flaming bolts: ArrowF is Fire'
        else: act='new' if not cur else 'replace'
    rows.append(dict(Id=int(i),Name=name,Kind=kind,Style=style,Level=r[3].strip(),
        Attack1=f'{a1[0]} {a1[1]} {"melee" if not a1ranged else a1[2]}',Current2=cur,
        Affinity='/'.join(aff[:2]),Source=src[0] if src else '',
        Type=p[0] if p else '',Damage=p[1] if p else '',Missile=('melee' if p and p[2]=='0' else (p[2] if p else '')),Chance=p[3] if p else '',
        Action=act,Why=why))
json.dump(rows,open('/home/claude/atk/rows.json','w'))
from collections import Counter
print(len(rows),Counter(x['Action'] for x in rows),Counter(x['Type'] for x in rows))
for x in rows[::23]: print(x['Id'],x['Name'],x['Style'],x['Attack1'],'|',x['Current2'],'->',x['Type'],x['Damage'],x['Missile'],x['Chance'],x['Action'],'|',x['Affinity'])
