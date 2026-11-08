"""Collect the translatable texts of the Waffel Edition scripts (Tx"..." and Tn"...") into
the template Data/Text localization/Template/Scripts.txt (see Structs/26_MMMWE_Texts.lua).

    python Tools/script_texts.py            (from the repository folder)
    python Tools/script_texts.py --update Data/Text localization/Russian/Scripts.txt

With --update, an existing translation file is rewritten in the template's order: its
translations are kept, new texts are added untranslated, and texts the scripts no longer
use are kept at the end under "# no longer used".
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIRS = ['Structs', 'General', 'Global']
OUT = os.path.join(ROOT, 'Data', 'Text localization', 'Template', 'Scripts.txt')

CALL = re.compile(r'\b(Tx|Tn)\s*\(?\s*("|\')')
LUA_ESC = {'n': '\n', 't': '\t', 'r': '\r', '\\': '\\', '"': '"', "'": "'", 'a': '\a', 'b': '\b', 'f': '\f', 'v': '\v', '\n': '\n'}


def lua_unescape(s):
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c == '\\' and i + 1 < len(s):
            d = s[i + 1]
            m = re.match(r'\d{1,3}', s[i + 1:])
            if m:
                out.append(chr(int(m.group(0)))); i += 1 + len(m.group(0)); continue
            out.append(LUA_ESC.get(d, d)); i += 2; continue
        out.append(c); i += 1
    return ''.join(out)


def file_escape(s):
    return s.replace('\\', '\\\\').replace('\t', '\\t').replace('\r', '\\r').replace('\n', '\\n')


def file_unescape(s):
    return re.sub(r'\\(.)', lambda m: {'n': '\n', 't': '\t', 'r': '\r', '\\': '\\', '"': '"'}.get(m.group(1), '\\' + m.group(1)), s)


def strip_comments(src):
    """blank out comments (keeping line numbers) so commented-out code isn't collected"""
    out, i, n = [], 0, len(src)
    while i < n:
        if src.startswith('--', i):
            m = re.match(r'--\[(=*)\[', src[i:])
            if m:
                end = src.find(']' + m.group(1) + ']', i); end = n if end < 0 else end + len(m.group(1)) + 2
            else:
                end = src.find('\n', i); end = n if end < 0 else end
            out.append(re.sub(r'[^\n]', ' ', src[i:end])); i = end; continue
        c = src[i]
        if c in '"\'':
            j = i + 1
            while j < n and src[j] != c and src[j] != '\n':
                j += 2 if src[j] == '\\' else 1
            out.append(src[i:j + 1]); i = j + 1; continue
        out.append(c); i += 1
    return ''.join(out)


def collect():
    texts = {}   # text -> [locations]
    for d in DIRS:
        p = os.path.join(ROOT, d)
        for f in sorted(os.listdir(p)):
            if not f.endswith('.lua') or 'MMMWE' not in f:
                continue
            src = strip_comments(open(os.path.join(p, f), encoding='latin-1').read())
            for m in CALL.finditer(src):
                q = m.group(2); i = m.end(); j = i
                while src[j] != q:
                    j += 2 if src[j] == '\\' else 1
                s = lua_unescape(src[i:j])
                line = src.count('\n', 0, m.start()) + 1
                texts.setdefault(s, []).append('%s/%s:%d' % (d, f, line))
    return texts


HEADER = """\
# Waffel Edition script texts. One text per line: English<TAB>translation.
# Escapes: \\n new line, \\t tab, \\\\ backslash. Keep %s, %d, %.1f, %% etc. in the same order.
# Lines starting with # are comments: each text's comment says where the scripts use it.
# An empty translation leaves the English text. Save the file in the game's code page
# (e.g. Windows-1251 for Russian) as Data\\Text localization\\<Language>\\Scripts.txt and put
# the language's name into MMMWE_Language.txt in the game folder.
"""


def write(path, texts, old=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    old = dict(old or {})
    with open(path, 'w', encoding='latin-1', newline='\r\n') as f:
        f.write(HEADER)
        for s, locs in texts.items():
            f.write('\n# ' + ', '.join(locs) + '\n')
            f.write(file_escape(s) + '\t' + file_escape(old.pop(s, '')) + '\n')
        if old:
            f.write('\n# no longer used\n')
            for s, t in old.items():
                f.write(file_escape(s) + '\t' + file_escape(t) + '\n')


def read(path):
    res = {}
    for line in open(path, encoding='latin-1').read().splitlines():
        if line.startswith('#') or '\t' not in line:
            continue
        en, tr = line.split('\t', 1)
        res[file_unescape(en)] = file_unescape(tr)
    return res


if __name__ == '__main__':
    texts = collect()
    if len(sys.argv) > 2 and sys.argv[1] == '--update':
        path = sys.argv[2]
        write(path, texts, read(path) if os.path.exists(path) else None)
    else:
        path = OUT
        write(path, texts)
    print('%d texts -> %s' % (len(texts), path))
