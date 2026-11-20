"""Split the web game's data dump (window.__dumpAll(), saved by tools/export_data_browser.py to /tmp/all_data.json)
into data/web/<file>.json as listed in data/index.json. Key order is kept exactly as in the web game: the game
iterates over some tables (leaders, schools, monsters) and its choices depend on that order. Text read with the
wrong encoding is repaired (see tools/fix_text_encoding.py)."""
import json, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))

MARKS = ('â€', 'Ã', 'Â')
def fix(s):
    if not any(m in s for m in MARKS): return s
    try: return s.encode('cp1252').decode('utf-8')
    except (UnicodeEncodeError, UnicodeDecodeError): return s
def walk(v):
    if isinstance(v, str): return fix(v)
    if isinstance(v, list): return [walk(x) for x in v]
    if isinstance(v, dict): return {fix(k): walk(x) for k, x in v.items()}
    return v

root = Path(__file__).resolve().parent.parent
dump = json.loads(Path(sys.argv[1] if len(sys.argv) > 1 else '/tmp/all_data.json').read_text(encoding='utf-8'))
index = json.loads((root / 'data' / 'index.json').read_text())
consts = index.get('constants', index)
files = {}
for name, f in consts.items():
    files.setdefault(f, {})[name] = walk(dump[name])
for f, d in files.items():
    (root / f).write_text(json.dumps(d, indent=1, ensure_ascii=False) + '\n', encoding='utf-8')
print(len(files), 'files,', sum(len(d) for d in files.values()), 'values')
