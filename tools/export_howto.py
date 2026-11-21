"""Export the web game's How to Play texts (the title card's short list and the Settings guide) to data/web/howto.json.

Usage: python3 tools/export_howto.py [reference/web-v106/game_shell.html]
Keys (<kbd>T</kbd>) become [T]; bold stays as [b]...[/b] for Godot's rich text.
"""
import html, json, re, sys

src = sys.argv[1] if len(sys.argv) > 1 else 'reference/web-v106/game_shell.html'
t = open(src, encoding='utf-8').read()


def items(block):
    out = []
    for li in re.findall(r'<li>(.*?)</li>', block, re.S):
        s = re.sub(r'<kbd>(.*?)</kbd>', r'[\1]', li)
        s = s.replace('<b>', '[b]').replace('</b>', '[/b]')
        s = re.sub(r'<[^>]+>', '', s)
        out.append(html.unescape(re.sub(r'\s+', ' ', s)).strip())
    return out


short = re.search(r'id="mHowText"[^>]*>(.*?)</ul>', t, re.S).group(1)
guide = re.search(r'id="stHowBody"[^>]*>(.*?)</ul>', t, re.S).group(1)
json.dump({'source': src, 'HOWTO_SHORT': items(short), 'HOWTO_GUIDE': items(guide)}, open('data/web/howto.json', 'w', encoding='utf-8'), indent=1, ensure_ascii=False)
idx = json.load(open('data/index.json', encoding='utf-8'))   # GameData finds each value through the index
for k in ('HOWTO_SHORT', 'HOWTO_GUIDE'):
    idx['constants'][k] = 'data/web/howto.json'
idx['constants'] = dict(sorted(idx['constants'].items()))
json.dump(idx, open('data/index.json', 'w', encoding='utf-8'), indent=1, ensure_ascii=False)
print(len(items(short)), len(items(guide)))
