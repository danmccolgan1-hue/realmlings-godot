# Tools: regenerate data and art from the web game

Both exports read a running copy of the web game (v106), so they always match what the web game actually uses.

1. Assemble a web build with the dump snippet: copy the web project, save `web_dump_snippet.js` there as `v999.js`, and add `open('v999.js').read()` right after `open('v106.js').read()` in its `assemble_game.py`. Run `python3 assemble_game.py`.
2. Serve that folder: `python3 -m http.server 8777`.
3. Data: `python3 tools/export_data_browser.py` writes `/tmp/all_data.json` (every UPPER_CASE constant of a started Realmling game); the repository's `data/web/*.json` are that file split by the source file that declares each constant.
4. Art: `python3 tools/export_art.py assets/art` renders every image listed in `export_art.js` and writes a `manifest.json` per folder.

Needs Python 3 with Playwright and Chromium (`pip install playwright && playwright install chromium`).
