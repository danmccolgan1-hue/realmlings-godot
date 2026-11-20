"""Repair text in data/web/*.json that was read with the wrong encoding.

python3 -m http.server sends realmlings_play.html without a charset, so the browser decoded the page's UTF-8 as
Windows-1252 and strings came out as "players‚Äô" / "â€™" instead of "players’". This turns such strings back
(encode as cp1252, decode as UTF-8) and leaves every other string alone. Exports made with the page served as UTF-8
(see tools/README.md) don't need it."""
import json, glob, sys
from pathlib import Path

MARKS = ('â€', 'Ã', 'Â')

def fix(s):
    if not any(m in s for m in MARKS):
        return s
    try:
        return s.encode('cp1252').decode('utf-8')
    except (UnicodeEncodeError, UnicodeDecodeError):
        return s

def walk(v):
    if isinstance(v, str): return fix(v)
    if isinstance(v, list): return [walk(x) for x in v]
    if isinstance(v, dict): return {fix(k): walk(x) for k, x in v.items()}
    return v

root = Path(__file__).resolve().parent.parent
for f in sorted(glob.glob(str(root / 'data' / 'web' / '*.json'))):
    txt = Path(f).read_text(encoding='utf-8')
    if not any(m in txt for m in MARKS): continue
    data = json.loads(txt)
    Path(f).write_text(json.dumps(walk(data), indent=1, ensure_ascii=False, sort_keys=True) + '\n', encoding='utf-8')
    print('fixed', Path(f).name)
