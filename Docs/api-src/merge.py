"""Builds one help file: the MMExtension v2.3 help with the MMMerge / Waffel Edition
API merged into its sections, fixes of the original and the entries it lacks.
Usage: python3 merge.py MMExtension.htm out.htm"""
import sys, os, re, glob, json, importlib, html
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault('MMEXT_HELP', sys.argv[1])
import gen

SRC, OUT = sys.argv[1], sys.argv[2]
REPO = os.environ.get('MMMERGE_REPO', '/home/claude/mmmerge-678-waffel-edition')
s = open(SRC, 'rb').read().decode('cp1251')
s = s.replace('charset=windows-1251', 'charset=utf-8')
s = re.sub(r'<title>.*?</title>', '<title>MMExtension v2.3 Help with MMMerge / Waffel Edition</title>', s)
esc = gen.esc

changes = []   # (kind, html) for the appendix

def badge(t):
    return '<span class="def-ver">[%s]</span><span class="def-nbsp"> </span>' % t

MERGE, WE = badge('MMMerge'), badge('Waffel Edition')

def group_badge(g):
    return WE if 'MMMWE' in g['file'] else MERGE

def must_replace(old, new, count=1, note=None):
    global s
    n = s.count(old)
    if n != count:
        raise SystemExit('expected %d of %r, found %d' % (count, old[:80], n))
    s = s.replace(old, new)
    if note:
        changes.append(('fix', note))

# ---------------------------------------------------------------- fixes of the original
TYPOS = [('achive', 'archive'), ('anmation', 'animation'), ('concious', 'conscious'), ('deafults', 'defaults'),
         ('dirrectory', 'directory'), ('eventhough', 'even though'), ('exect', 'exact'), ('figet', 'fidget'),
         ('fulscreen', 'fullscreen'), ('funciton', 'function'), ('guraded', 'guarded'), ('indeces', 'indices'),
         ('initilized', 'initialized'), ('inteface', 'interface'), ('mutiple', 'multiple'), ('pacth', 'patch'),
         ('ratains', 'retains'), ('sctrucure', 'structure'), ('seemlessly', 'seamlessly'),
         ('signinficant', 'significant'), ('sipmlify', 'simplify'), ('thay', 'they'), ('Additonal', 'Additional')]
fixed = []
for a, b in TYPOS:
    n = len(re.findall(r'\b%s\b' % a, s))
    if n:
        s = re.sub(r'\b%s\b' % a, b, s)
        fixed.append('%s &rarr; %s' % (a, b))
changes.append(('fix', 'Spelling: ' + ', '.join(fixed) + '.'))
must_replace("if the the game wasn't", "if the game wasn't", 2, 'Game.Resume and Game.Resume2: "if the the game" &rarr; "if the game".')
must_replace('<a href="#const.Skill">Skill</a>', '<a href="#const.Skills">Skill</a>', 1,
             '<a href="#structs.ItemsTxtItem.Skill">ItemsTxtItem.Skill</a> linked to the missing const.Skill; now <a href="#const.Skills">const.Skills</a>.')
n = s.count('const.Skill.EarthMagic')
must_replace('const.Skill.EarthMagic', 'const.Skills.EarthMagic', n,
             'The <a href="#events.CalcStatBonusByItems">CalcStatBonusByItems</a> example used <span class="def-code">const.Skill.EarthMagic</span>, which raises an error; now <span class="def-code">const.Skills.EarthMagic</span>.')
n = len(re.findall(r'Game\.StatusText\b', s))
s = re.sub(r'Game\.StatusText\b', 'Game.ShowStatusText', s)
changes.append(('fix', 'The shelf example (Map events) called <span class="def-code">Game.StatusText</span>, which doesn\'t exist; now <a href="#structs.GameStructure.ShowStatusText">Game.ShowStatusText</a> (%d places).' % n))
must_replace('Triggers <a href="#events.UpdateFaces">UpdateFaces</a> event.',
             'Triggers <a href="#events.BeforeUpdateFaces">BeforeUpdateFaces</a> and <a href="#events.AfterUpdateFaces">AfterUpdateFaces</a> events.', 1,
             'Faces.Update linked to a non-existent UpdateFaces event; it raises <a href="#events.BeforeUpdateFaces">BeforeUpdateFaces</a> and <a href="#events.AfterUpdateFaces">AfterUpdateFaces</a>.')
must_replace('<a href="#structs.Item.Bonus2.">Bonus2</a> See', '<a href="#structs.Item.Bonus2">Bonus2</a>. See', 1,
             '<a href="#structs.Player.HasItemBonus">Player.HasItemBonus</a>: broken Bonus2 link and a missing full stop.')
must_replace('<a id="structs.MapMonster.FramesGotHit" class="abs"></a><a href="#Same%20as%20FramesStun">FramesGotHit</a>\n</td><td class="def-right">\n \n',
             '<a id="structs.MapMonster.FramesGotHit" class="abs"></a>FramesGotHit\n</td><td class="def-right">\n Same as <a href="#structs.MapMonster.FramesStun">FramesStun</a>\n', 1)
must_replace('<a id="structs.MapMonster.SoundGotHit" class="abs"></a><a href="#Same%20as%20SoundGetHit">SoundGotHit</a>\n</td><td class="def-right">\n \n',
             '<a id="structs.MapMonster.SoundGotHit" class="abs"></a>SoundGotHit\n</td><td class="def-right">\n Same as <a href="#structs.MapMonster.SoundGetHit">SoundGetHit</a>\n', 1,
             '<a href="#structs.MapMonster.FramesGotHit">MapMonster.FramesGotHit</a> and <a href="#structs.MapMonster.SoundGotHit">SoundGotHit</a>: their "Same as ..." notes had turned into broken links; now they are descriptions.')

# ---------------------------------------------------------------- helpers
def section(name):
    a = s.index('<a id="%s"></a><h2>' % name)
    b = s.find('<br>\n<hr>\n<a id="', a + 10)
    return a, (b if b > 0 else s.index('\t\t</div>\n\t</div>\n</body>'))

def row(left, right):
    return '<tr>\n<td class="def-left">\n%s\n</td><td class="def-right">\n %s\n</td>\n</tr>' % (left, right)

def add_rows(table_id, rows, within=None):
    """append rows at the end of the table that follows <a id=table_id>"""
    global s
    lo, hi = within or (0, len(s))
    a = s.index('<a id="%s"></a>' % table_id, lo)
    assert a < hi, table_id
    e = s.index('</tr></tbody>\n</table>', a)
    s = s[:e + 5] + ''.join(rows) + s[e + 5:]

def caption_table(caption_html, sub, about, rows, anchor):
    return ('<br>\n<a id="%s"></a><table class="def-table">\n<tbody>\n<tr>\n<td colspan="2" class="def-caption">\n%s\n%s&nbsp;<i class="def-ib">%s:</i><br>\n</td>\n</tr>\n%s</tbody>\n</table>\n<br>\n\n'
            % (anchor, caption_html, (about + '<br><br>\n') if about else ' \n', sub, ''.join(rows)))

def file_caption(path):
    path = path.replace('Scripts\\', '', 1)
    d, _, f = path.rpartition('\\')
    return '<h3><span class="def-shadow">%s\\ </span>%s</h3>' % (esc(d), esc(f)) if d else '<h3>%s</h3>' % esc(f)

def local_links(h):
    return h.replace('href="MMExtension.htm#', 'href="#')

def insert_before(marker_pos, text):
    global s
    s = s[:marker_pos] + text + s[marker_pos:]

# ---------------------------------------------------------------- API groups
groups = []
for f in sorted(glob.glob(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'entries_*.py'))):
    groups += importlib.import_module(os.path.basename(f)[:-3]).GROUPS
groups = gen.merge(groups)

def item_row(kind, it, g, mark=False):
    desc = it.get('desc', '')
    if it.get('example'):
        desc += gen.code(it['example'])
    return row(local_links(gen.left(kind, it)), (group_badge(g) if mark else '') + local_links(desc))

toc_add = {}   # section id -> list of toc html

def toc_entry(anchor, title_html, subs):
    return '<li><a href="#%s">%s</a>%s</li>' % (anchor, title_html, ('<ul>' + ''.join('<li><a href="#%s">%s</a></li>' % x for x in subs) + '</ul>') if subs else '')

def sub_anchor(kind, it):
    if kind == 'events':
        return ('events.' + it['name'], esc(it['name']))
    if kind == 'functions':
        n = it['name'] if it.get('global') else 'Merge.Functions.' + it['name']
        return (n, esc(n))
    return ('tables.' + it['name'].replace(' ', '_'), esc(it['name']))

def place_groups(kind, sec_name, sub):
    lo, hi = section(sec_name)
    out, tocs = [], []
    for g in sorted([g for g in groups if g['kind'] == kind], key=lambda g: g['file'].lower()):
        cap = file_caption(g['file'])
        # an existing table of the original for the same file?
        lo, hi = section(sec_name)
        k = s.find(cap, lo, hi)
        if k > 0:
            tid = s[s.rfind('<a id="', 0, k) + 7: s.rfind('"></a><table', 0, k)]
            add_rows(tid, [item_row(kind, it, g, True) for it in g['items']], (lo, hi))
            changes.append(('add', '%s: %s added to %s.' % (KIND1[kind], ', '.join('<a href="#%s">%s</a>' % sub_anchor(kind, it) for it in g['items']), esc(g['file'].replace('Scripts\\', '')))))
            continue
        anchor = 'merge-' + kind + '-' + re.sub(r'[^A-Za-z0-9_]', '-', g['file'].replace('Scripts\\', ''))
        about = group_badge(g) + (local_links(g['about']) if g.get('about') else '')
        out.append(caption_table(cap, sub, about, [item_row(kind, it, g) for it in g['items']], anchor))
        tocs.append(toc_entry(anchor, '<span class="def-shadow">%s\\ </span>%s' % tuple(esc(x) for x in g['file'].replace('Scripts\\', '').rpartition('\\')[::2]),
                              [sub_anchor(kind, it) for it in g['items']]))
    lo, hi = section(sec_name)
    insert_before(hi, ''.join(out))
    toc_add[sec_name] = toc_add.get(sec_name, []) + tocs

KIND1 = {'events': 'Events', 'functions': 'Functions', 'tables': 'Tables'}
place_groups('events', 'Events', 'Events')
place_groups('functions', 'General-Functions', 'Functions')

# ---------------------------------------------------------------- base functions missing from the help
P, C = (lambda n: '<b class="def-param">%s</b>' % n), (lambda x: '<span class="def-code">%s</span>' % x)
def frow(name, args, desc, anchor=None):
    return row('<a id="%s" class="abs"></a><h5 class="def-h5">%s</h5><b class="def-largs">(</b>%s<b class="def-rargs">)</b>' % (anchor or name, esc(name), esc(args)), desc)
lo, hi = section('General-Functions')
add_rows('Core-Common.lua', [
    frow('bit.And, bit.Or, bit.Xor, bit.Not', 'a, b', 'Aliases of LuaJIT\'s ' + C('bit.band, bit.bor, bit.bxor, bit.bnot') + '. ' + C('bit[i]') + ' = 2^i for i 0..63.', 'bit.And'),
    frow('bit.AndNot', 'a, b', C('bit.band(a, bit.bnot(b))') + ': clears the bits of ' + P('b') + ' in ' + P('a') + '.'),
    frow('bit.ToTable', 'x, t', 'Bits of ' + P('x') + ' as a table: ' + C('t[i] = true') + ' when bit i-1 is set (fills ' + P('t') + ' if given).'),
    frow('bit.FromTable', 't', 'Reverse of ' + C('bit.ToTable') + ': a signed 32-bit number from ' + C('t[1..32]') + '.'),
    frow('Number methods', 'v', 'Numbers have methods: ' + C('(v):ToHex()') + ' (also ' + C(':tohex') + '), ' + C('(v):Div(d)') + ' (also ' + C(':div') + ', ' + C('floor(v/d)') + '), ' + C(':round(), :floor(), :ceil()') + ' and all ' + C('bit') + ' functions, e.g. ' + C('(x):And(0xFF)') + '.', 'numbers'),
    frow('os.rename', 'old, new', 'Renames or moves a file (WinAPI MoveFile). Returns true or nil and an error message.'),
], (lo, hi))
add_rows('Core-RSFunctions.lua', [
    frow('PrintToFile', 'fname, Windows, preserve', 'Makes ' + P('print') + ' write into file ' + P('fname') + '. ' + P('Windows') + ' = true writes \\r\\n line ends. Returns a function that tells whether something was written and the file name.')], (lo, hi))
add_rows('Core-npc.lua-', [frow('RefillNPCTopics', '', 'Rebuilds the topics of the current NPC dialog.')], (lo, hi))
add_rows('Core-evt.lua-', [frow('UpdateEventJustHint', '', '[MM7+] Marks facets and sprites whose events only show a hint (houses named in ' + C('evt.house') + '), as on map load.')], (lo, hi))
changes.append(('add', 'Undocumented base functions: <a href="#bit.And">bit.And/Or/Xor/Not</a>, <a href="#bit.AndNot">bit.AndNot</a>, <a href="#bit.ToTable">bit.ToTable</a>, <a href="#bit.FromTable">bit.FromTable</a>, <a href="#numbers">number methods</a>, <a href="#os.rename">os.rename</a>, <a href="#PrintToFile">PrintToFile</a>, <a href="#RefillNPCTopics">RefillNPCTopics</a>, <a href="#UpdateEventJustHint">UpdateEventJustHint</a>.'))

# ---------------------------------------------------------------- structures
ST = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'mergestructs.json')))

def type_left(name, t, sname):
    t = t.replace('27 + MC.PlayerBuffs2Count - 1', '33').replace('MC.PlayerDebuffsCount', '33')
    arr = ''
    for d in re.findall(r'array\(([^)]*)\)', t):
        p = [x.strip() for x in d.split(',')]
        num = [x if re.fullmatch(r'-?\d+', x) else '' for x in p]
        if len(p) == 2:
            arr += '[%s..%s]' % tuple(num)
        else:
            arr += '[%s]' % ('' if num[0] in ('', '0') else num[0])
    sm = re.search(r'struct\(structs\.(\w+)\)', t)
    a = '<a id="structs.%s.%s" class="abs"></a>' % (sname, name)
    nm = ('<a href="#structs.%s">%s</a>' % (sm.group(1), name)) if sm else name
    return a + nm + arr

TYPEDESC = {'u1': '', 'u2': '', 'u4': '', 'i2': '', 'i4': '', 'i8': '', 'r4': 'float', 'b1': 'boolean', 'EditPChar': 'bitmap name (string)'}
FIELDDOC = {
 ('SpcAttack', 'NextTime'): 'Game.Time when the attack can be used again',
 ('SpcAttack', 'Bits'): 'All the flags above',
 ('PlayerExtra', 'SpcAttack'): '[0] melee, [1] ranged; also as SpcAttackMelee and SpcAttackRanged',
 ('PlayerExtra', 'SpellBuffs2'): 'Extra character buffs 27..33',
 ('PlayerExtra', 'Debuffs'): 'Conditions 0-12, 15, 17-19 shown as debuffs and the drains 20-32',
 ('TurnBasedQueueItem', 'Kind'): 'Kind of the EntityRef (<a href="#const.ObjectRefKind">const.ObjectRefKind</a>)',
 ('TurnBasedQueueItem', 'Index'): 'Index part of the EntityRef',
 ('CharacterVoices', 'Sounds'): '[voice][sound type] sound id', ('CharacterVoices', 'Avail'): '[voice][type] availability',
 ('MissileDirection', 'Direction'): '0..2047', ('MissileDirection', 'LookAngle'): 'Vertical angle',
 ('HouseRules', 'ArcomageTexts'): 'Text ids',
}
NEWSTRUCT_ABOUT = {
 'MissileDirection': 'Direction of a projectile: the vector to the target and its distance. Used by <a href="#events.MonsterCastSpell">MonsterCastSpell</a>.',
}

def struct_table(name, about, badge_html):
    rows = []
    for f, t in ST[name]['rows']:
        if f.startswith('unk'):
            continue
        d = FIELDDOC.get((name, f), '')
        if t.startswith('bit '):
            d = d or 'Bit %s of Bits' % t[4:]
        elif not d:
            d = TYPEDESC.get(t, '')
        rows.append(row(type_left(f, t, name), d))
    cap = '<h3>structs.%s</h3>\n%s' % (name, badge_html)
    return '<br><a id="structs.%s"></a>\n<table class="def-table">\n<tbody>\n<tr>\n<td colspan="2" class="def-caption">\n%s\n%s<br><br>\n&nbsp;<i class="def-ib">Fields:</i><br>\n</td>\n</tr>\n%s</tbody>\n</table>\n<br>\n\n' % (
        name, cap, about, ''.join(rows))

def insert_struct(name, html_text):
    lo, hi = section('Structures')
    pos = None
    for m in re.finditer(r'<br><a id="structs\.(\w+)"></a>\n<table', s[lo:hi]):
        n = m.group(1)
        if n in ('GameStructure', 'GameParty', 'GameMap', 'GameMouse', 'GameScreen'):
            continue
        if n.lower() > name.lower():
            pos = lo + m.start(); break
    insert_before(pos or hi, html_text)
    toc_struct.append(name)

toc_struct = []
FLINK = {'Game.CharacterPortraits': 'CharacterPortrait', 'Game.CharacterDollTypes': 'CharacterDollType', 'Game.CharacterVoices': 'CharacterVoices',
         'Game.HouseRules': 'HouseRules', 'Game.HousesExtra': 'HousesExtra', 'Game.ArmorPicsCoords': 'ArmorPicsCoords',
         'Game.ReagentSettings': 'ReagentSettings', 'Game.PartyLight': 'PartyLight', 'Game.TurnBasedState': 'TurnBasedState',
         'Game.TurnBasedQueue': 'TurnBasedQueueItem', 'Game.PlayersExtra': 'PlayerExtra', 'Map.BloodSplats': 'BloodSplat'}
sgroups = [g for g in groups if g['kind'] == 'structs']
TARGET = {'Game': 'GameStructure', 'Party': 'GameParty', 'Map': 'GameMap', 'Item': 'Item'}
struct_about = {}
added_fields = []
for g in sgroups:
    for it in g['items']:
        names = it['name'].split(', ')
        desc = local_links(it.get('desc', ''))
        b = group_badge(g)
        if names[0] in ('PlayerExtra', 'SpcAttack'):
            struct_about[names[0]] = b + desc
            continue
        if names[0] == 'const.ShopTopics':
            continue   # documented with the constants
        new_rows, notes = [], []
        target = TARGET[names[0].split('.')[0]]
        lo, hi = section('Structures')
        newn = []
        for n in names:
            f = n.split('.', 1)[1]
            aid = 'structs.%s.%s' % (target, f)
            if ('<a id="%s"' % aid) in s:
                # append a note to the existing row
                k = s.index('<a id="%s"' % aid)
                e = s.index('</td>\n</tr>', s.index('<td class="def-right">', k))
                s = s[:e] + '<br>' + b + desc + '\n' + s[e:]
                s = s.replace('<a id="%s" class="abs"></a>' % aid, '<a id="%s" class="abs"></a><a id="%s" class="abs"></a>' % (aid, n), 1)
                added_fields.append('<a href="#%s">%s</a> (note)' % (aid, esc(n)))
            else:
                newn.append((f, aid, n))
        if newn:
            left = '<br>'.join('<a id="%s" class="abs"></a><a id="%s" class="abs"></a>%s' % (aid, n, ('<a href="#structs.%s">%s</a>' % (FLINK[n], esc(f))) if n in FLINK else esc(f)) for f, aid, n in newn)
            add_rows('structs.' + target, [row(left, b + desc)])
            added_fields += ['<a href="#%s">%s</a>' % (aid, esc(n)) for f, aid, n in newn]
changes.append(('add', 'Fields and notes of the merge on Game, Party, Map and Item: ' + ', '.join(added_fields) + '.'))

# base fields missing from the help
add_rows('structs.GameStructure', [row('<a id="structs.GameStructure.DelayedFaceAnimation" class="abs"></a>DelayedFaceAnimation',
         'A face animation waiting to be played: ' + C('Delay') + ' (i8), ' + C('Animation') + ' (<a href="#const.FaceAnimation">const.FaceAnimation</a>), ' + C('PlayerIndex') + '.')])
add_rows('structs.TravelInfo', [row('<a id="structs.TravelInfo.OldMapIndex" class="abs"></a>OldMapIndex',
         MERGE + 'The byte at offset 0 where the original games keep the map index. The merge reads the map from ' + C('MapIndex') + ' (2 bytes at 0xA) so more maps fit.')])
changes.append(('add', 'Undocumented fields: <a href="#structs.GameStructure.DelayedFaceAnimation">Game.DelayedFaceAnimation</a>, <a href="#structs.TravelInfo.OldMapIndex">TravelInfo.OldMapIndex</a> (merge layout), <a href="#structs.Item.Material">Item.Material</a> (merge).'))

for name in sorted(ST):
    if name == 'MissileDirection':
        insert_struct(name, struct_table(name, NEWSTRUCT_ABOUT[name], ''))
        continue
    about = struct_about.get(name, '')
    insert_struct(name, struct_table(name, about, MERGE if not about else ''))
changes.append(('add', 'Missing structure <a href="#structs.MissileDirection">structs.MissileDirection</a> (MonsterCastSpell linked to it). Merge structures: ' + ', '.join('<a href="#structs.%s">%s</a>' % (n, n) for n in sorted(ST) if n != 'MissileDirection') + '.'))

# ---------------------------------------------------------------- data tables section
lo, hi = section('Structures')
dt = ['<br>\n<hr>\n<a id="Data-Tables"></a><h2>Data Tables</h2>\n\n<p>Text tables in <span class="def-code">Data\\Tables</span> that the MMMerge and Waffel Edition scripts read, grouped by the script that reads them.</p>\n']
toc_dt = []
for g in sorted([g for g in groups if g['kind'] == 'tables'], key=lambda g: g['file'].lower()):
    anchor = 'merge-tables-' + re.sub(r'[^A-Za-z0-9_]', '-', g['file'])
    about = (group_badge(g) + local_links(g['about'])) if g.get('about') else group_badge(g)
    if g['file'].startswith('Data'):
        about = local_links(g['about'])
    dt.append(caption_table(file_caption(g['file']), 'Tables', about, [item_row('tables', it, g) for it in g['items']], anchor))
    toc_dt.append(toc_entry(anchor, '<span class="def-shadow">%s\\ </span>%s' % tuple(esc(x) for x in g['file'].replace('Scripts\\', '').rpartition('\\')[::2]),
                            [sub_anchor('tables', it) for it in g['items']]))
insert_before(hi, ''.join(dt))

# ---------------------------------------------------------------- constants
def lua_table(path, name):
    t = open(os.path.join(REPO, path), encoding='utf-8', errors='replace').read()
    m = re.search(r'^const\.%s\s*=\s*\{(.*?)^\}' % name, t, flags=re.S | re.M)
    body = re.sub(r'--[^\n]*', '', m.group(1))
    return [(k, v) for k, v in re.findall(r'(\w+)\s*=\s*(0x[0-9A-Fa-f]+|-?\d+)', body)]

def const_table(name, pairs, about, anchor_prefix=None):
    ap = anchor_prefix or 'const.' + name
    rows = [row('<a id="%s.%s" class="abs"></a>%s <i class="def-const">= %s</i>' % (ap, k, k, (str(int(v, 16)) if v.startswith('0x') else v)), '') for k, v in pairs]
    title = 'const.%s' % name + (' (MMMerge)' if anchor_prefix else '')
    return '<br><a id="%s"></a>\n<table class="def-table">\n<tbody>\n<tr>\n<td colspan="2" class="def-caption">\n<h3>%s</h3>\n%s<br><br>\n&nbsp;<i class="def-ib">Values:</i><br>\n</td>\n</tr>\n%s</tbody>\n</table>\n<br>\n\n' % (ap, title, about, ''.join(rows))

toc_const = []
def insert_const(name, html_text, anchor):
    lo, hi = section('Constants')
    pos = None
    for m in re.finditer(r'<br><a id="const\.(\w+)"></a>\n<table', s[lo:hi]):
        if m.group(1).lower() > name.lower():
            pos = lo + m.start(); break
    insert_before(pos or hi, html_text)
    toc_const.append((anchor, 'const.' + name + (' (MMMerge)' if anchor.startswith('merge.') else '')))

MC = 'Structs/20_MergeConsts.lua'
NEWC = [
 ('Alignment', MC, 'Party alignment values.'),
 ('ClassKind', MC, 'Class families (' + C('Kind') + ' of <a href="#tables.Class_Extra.txt">Class Extra.txt</a>).'),
 ('RaceFamily', MC, 'Race families (<a href="#tables.Races.txt">Races.txt</a>).'),
 ('RaceKind', MC, 'Race kinds (<a href="#tables.Races.txt">Races.txt</a>).'),
 ('RaceMaturity', MC, ''),
 ('PromoAwards', MC, 'Award numbers of the promotions.'),
 ('ShopTopics', 'Structs/RemoveHouseRulesLimits.lua', 'Topic numbers of the shop dialogs.'),
 ('LearnTopics', 'Structs/RemoveHouseRulesLimits.lua', 'Learn-skill topics: 0x24 + <a href="#const.Skills">const.Skills</a>.'),
]
for name, path, about in NEWC:
    insert_const(name, const_table(name, lua_table(path, name), MERGE + about), 'const.' + name)
for name in ('Class', 'Race'):
    anchor = 'merge.const.' + name
    insert_const(name + '!', const_table(name, lua_table(MC, name), MERGE + 'The merge replaces the table above with this one for all three games.', anchor), anchor)
    toc_const[-1] = (anchor, 'const.%s (MMMerge)' % name)
    # note in the original caption
    k = s.index('<br><a id="const.%s"></a>' % name)
    e = s.index('&nbsp;<i class="def-ib">Values:</i>', k)
    s = s[:e] + MERGE + 'In MMMerge this table is replaced, see <a href="#%s">const.%s (MMMerge)</a>.<br><br>\n' % (anchor, name) + s[e:]
add_rows('const', [row('<a id="const.Second" class="abs"></a>Second <i class="def-const">= 256/60</i>', 'One in-game second in <a href="#structs.GameStructure.Time">Game.Time</a> units (const.Minute/60).'),
                   row('<a id="const.HouseTypeInv" class="abs"></a>HouseTypeInv', 'Reverse of <a href="#const.HouseType">const.HouseType</a>: house type number &rarr; name. ' + MERGE + 'Adds 16 "Mirrored Guild", 33 "El2 Guild", 34 "Se2 Guild", 36 "Mi2 Guild".')])
extra = []
for cname, items in [('Stats', [('LightResistance', 50), ('DarkResistance', 51), ('PhysicalResistance', 52), ('EnergyResistance', 53)]),
                     ('PlayerBuff', [('HPPotion', 27), ('SPPotion', 28)]),
                     ('HouseType', [('Mirrored Guild', 16), ('El2 Guild', 33), ('Se2 Guild', 34), ('Mi2 Guild', 36)])]:
    rows = []
    for k, v in items:
        aid = 'const.%s.%s' % (cname, k.replace(' ', '_'))
        if ('id="%s"' % aid) in s or ('id="const.%s.%s"' % (cname, k)) in s:
            continue
        rows.append(row('<a id="%s" class="abs"></a>%s <i class="def-const">= %d</i>' % (aid, esc(k) if ' ' not in k else '["%s"]' % esc(k), v), MERGE))
        extra.append('<a href="#%s">const.%s.%s</a>' % (aid, cname, esc(k)))
    if rows:
        add_rows('const.' + cname, rows)
changes.append(('add', 'Constants: <a href="#const.Second">const.Second</a> and <a href="#const.HouseTypeInv">const.HouseTypeInv</a> were undocumented. Merge constants: ' +
                ', '.join('<a href="#%s">%s</a>' % x for x in toc_const) + ('; ' + ', '.join(extra) if extra else '') + '.'))

# ---------------------------------------------------------------- top note and appendix
intro = ('<p>This file is the MMExtension v2.3 help with the MMMerge and Waffel Edition additions merged in. '
         'Added entries are marked <span class="def-ver">[MMMerge]</span> or <span class="def-ver">[Waffel Edition]</span>; '
         'whole new groups sit at the end of each section. The new <a href="#Data-Tables">Data Tables</a> section describes the text tables of the mod. '
         '<a href="#Merge-Changes">Changes to the original help</a> lists the corrections and the entries that were missing. '
         'In the scripts <i>Merge.Functions</i> is usually aliased as <span class="def-code">local MF = Merge.Functions</span>.</p>\n')
k = s.index('<a id="General-Information"></a>')
k = s.index('</h2>', k) + 5
insert_before(k, '\n' + intro)
app = ['<br>\n<hr>\n<a id="Merge-Changes"></a><h2>Changes to the original help</h2>\n<h3>Corrections</h3>\n<ul>']
app += ['<li>%s</li>' % h for kind, h in changes if kind == 'fix']
app += ['</ul>\n<h3>Added entries</h3>\n<ul>']
app += ['<li>%s</li>' % h for kind, h in changes if kind == 'add']
app += ['<li>The MMMerge and Waffel Edition events, Merge.Functions, structures and data tables (%d entries).</li>' % sum(len(g['items']) for g in groups)]
app += ['</ul>\n']
e = s.index('\t\t</div>\n\t</div>\n</body>')
insert_before(e, '\n'.join(app))

# ---------------------------------------------------------------- table of contents
def toc_insert(sec, items_html):
    global s
    t0 = s.index('<div id="toc">')
    k = s.index('<a href="#%s">' % sec, t0)
    ul = s.index('<ul>', k)
    depth, i = 0, ul
    while True:
        a, b = s.find('<ul>', i), s.find('</ul>', i)
        if a != -1 and a < b:
            depth += 1; i = a + 4
        else:
            depth -= 1; i = b + 5
            if depth == 0:
                break
    s = s[:i - 5] + ''.join(items_html) + s[i - 5:]

toc_insert('Events', toc_add['Events'])
toc_insert('General-Functions', toc_add['General-Functions'])
toc_insert('Structures', ['<li><a href="#structs.%s">structs.%s</a></li>' % (n, n) for n in toc_struct])
toc_insert('Constants', ['<li><a href="#%s">%s</a></li>' % x for x in toc_const])
t0 = s.index('<div id="toc">')
k = s.index('<li><a href="#Constants">', t0)
s = s[:k] + '<li><a href="#Data-Tables">Data Tables</a><ul>' + ''.join(toc_dt) + '</ul></li>' + s[k:]
k = s.index('</ul>\n\t\t\t</div>', t0) if '</ul>\n\t\t\t</div>' in s[t0:] else None
lastul = s.rindex('</ul>', t0, s.index('</div>', t0))
s = s[:lastul] + '<li><a href="#Merge-Changes">Changes to the original help</a></li>' + s[lastul:]
s = s.replace('<h1>MMExtension v2.3 Help</h1>', '<h1>MMExtension v2.3 Help<br><span class="def-shadow">with MMMerge / Waffel Edition</span></h1>', 1)

open(OUT, 'w', encoding='utf-8').write(s)
print('written', OUT, len(s))
