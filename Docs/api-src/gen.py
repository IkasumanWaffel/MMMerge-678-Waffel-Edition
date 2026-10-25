"""Builds the Merge / Waffel Edition API page in the layout of MMExtension.htm.
Entries live in entries_*.py files as GROUPS = [ {file, kind, items:[...]} ].
item: name, args (list of field names for a table argument, or a string for a
plain argument list), desc (HTML), optional links {field: anchor}."""
import importlib, sys, glob, os, html, re

HELP = os.environ.get('MMEXT_HELP') or os.path.join(os.path.dirname(os.path.abspath(__file__)), 'MMExtension.htm')
src = open(HELP, 'rb').read().decode('cp1251')
head = src[:src.index('</head>')]
head = head.replace('charset=windows-1251', 'charset=utf-8')
head = re.sub(r'<title>.*?</title>', '<title>Merge / Waffel Edition API</title>', head)
HELPNAME = 'MMExtension.htm'

def esc(s): return html.escape(s, quote=False)

def code(s):
    # Lua code block in the help's style (plain, comments greened)
    out = []
    for line in s.strip('\n').split('\n'):
        m = re.match(r'^(.*?)(--.*)$', line)
        if m and '"' not in m.group(1):
            out.append(esc(m.group(1)) + '<span class="lua5-comment">' + esc(m.group(2)) + '</span>')
        else:
            out.append(esc(line))
    return '<br><span class="def-vspace">Example:<div class="def-codeblock">' + '<br>'.join(out).replace('\t', '<span class="lua5-tab">\t</span>') + '</div></span>'

def link(target, text=None):
    text = text or target
    # anchors of the base help file point into it
    return '<a href="%s#%s">%s</a>' % (HELPNAME, target, esc(text))

def left(kind, it):
    if kind == 'events':
        anchor, tag, title = 'events.' + it['name'], 'h4', it['name']
    elif kind == 'functions' and it.get('global'):
        anchor, tag, title = it['name'], 'h5', it['name']
    elif kind == 'functions':
        anchor, tag, title = 'Merge.Functions.' + it['name'], 'h5', 'Merge.Functions.' + it['name']
    elif kind == 'structs':
        anchor = it['name'] if it['name'].startswith(('Game.', 'Party.', 'Map.', 'const.')) else 'structs.' + it['name']
        tag, title = 'h4', it['name']
    else:
        anchor, tag, title = 'tables.' + it['name'].replace(' ', '_'), 'h4', it['name']
    ids = [anchor]
    if kind == 'structs' and ', ' in it['name']:
        ids = [n if n.startswith(('Game.', 'Party.', 'Map.', 'const.')) else 'structs.' + n for n in it['name'].split(', ')]
    s = ''.join('<a id="%s" class="abs"></a>' % a for a in ids) + '<%s class="def-%s">%s</%s>' % (tag, tag, esc(title), tag)
    args = it.get('args')
    links = it.get('links', {})
    if isinstance(args, list):
        s += '<b class="def-largs">{</b>'
        for a in args:
            t = esc(a)
            if a in links: t = link(links[a], a)
            s += '<br><span class="def-nbsp">  </span>' + t
        s += '<br><b class="def-rargs">}</b>'
    elif kind in ('events', 'functions'):
        s += '<b class="def-largs">(</b>%s<b class="def-rargs">)</b>' % esc(args or '')
    elif args:
        s += '<br><span class="def-shadow">%s</span>' % esc(args)
    return s

SECTIONS = (('Events', 'events'), ('Merge Functions', 'functions'), ('Structures', 'structs'), ('Data Tables', 'tables'))
KINDNAME = {'events': 'Events', 'functions': 'Functions', 'structs': 'Structures', 'tables': 'Tables'}

def merge(groups):
    out, idx = [], {}
    for g in groups:
        k = (g['file'], g['kind'])
        if k in idx:
            idx[k]['items'] += g['items']
            if g.get('about') and not idx[k].get('about'): idx[k]['about'] = g['about']
        else:
            g = dict(g); g['items'] = list(g['items']); idx[k] = g; out.append(g)
    return out

def build(groups, title, intro):
    groups = merge(groups)
    out = [head, '</head>\n<body>\n<div id="content2">\n<h1>%s</h1>\n%s\n' % (esc(title), intro)]
    def gid(g): return g['kind'] + '-' + re.sub(r'[^A-Za-z0-9_]', '-', g['file'])
    toc = []
    for section, kind in SECTIONS:
        gs = sorted([g for g in groups if g['kind'] == kind], key=lambda g: g['file'].lower())
        n = sum(len(g['items']) for g in gs)
        toc.append('<p><b><a href="#%s">%s</a></b> (%d): %s</p>' % (section.replace(' ', '-'), section, n,
            ', '.join('<a href="#%s">%s</a>' % (gid(g), esc(g['file'].rpartition('\\')[2])) for g in gs)))
    out.append('<h3>Contents</h3>\n' + '\n'.join(toc) + '\n')
    for section, kind in SECTIONS:
        gs = [g for g in groups if g['kind'] == kind]
        if not gs: continue
        out.append('<a id="%s"></a><h2>%s</h2>\n' % (section.replace(' ', '-'), section))
        for g in sorted(gs, key=lambda g: g['file'].lower()):
            d, _, f = g['file'].rpartition('\\')
            out.append('<br>\n<a id="%s"></a><table class="def-table">' % gid(g))
            out.append('<tbody><tr><td colspan="2" class="def-caption">'
                       '<h3><span class="def-shadow">%s\\</span>%s</h3>\n&nbsp;<i class="def-ib">%s:</i><br>%s</td></tr>\n'
                       % (esc(d), esc(f), KINDNAME[kind],
                          ('<br>' + g['about']) if g.get('about') else ''))
            for it in g['items']:
                desc = it.get('desc', '')
                if it.get('example'): desc += code(it['example'])
                out.append('<tr><td class="def-left">%s</td><td class="def-right">%s</td></tr>\n' % (left(kind, it), desc))
            out.append('</tbody></table>\n')
    out.append('</div></body></html>\n')
    return ''.join(out)

if __name__ == '__main__':
    sys.path.insert(0, os.path.dirname(__file__))
    groups = []
    for f in sorted(glob.glob(os.path.join(os.path.dirname(__file__), 'entries_*.py'))):
        m = importlib.import_module(os.path.basename(f)[:-3])
        groups += m.GROUPS
    intro = open(os.path.join(os.path.dirname(__file__), 'intro.html')).read()
    open(sys.argv[1], 'w', encoding='utf-8').write(build(groups, 'Merge / Waffel Edition API', intro))
    print(sum(len(g['items']) for g in groups), 'entries')
