# Realmlings (Godot)

The Godot 4.7.2 port of Realmlings, a browser grand strategy game. GDScript only. Target: Windows.

- **Source of truth for rules:** `reference/web-v106/` (the web game, v106). Its `HANDOFF.md` explains every system; `docs/RULES_SPEC.md` maps each system to the files and functions to port.
- **First milestone:** Realmlings only, on the 10-province Practice island (`RealmGen.generatePractice`), the player alone. Computer nations, war and diplomacy come later.
- **Layout and naming:** `docs/NAMING.md`. Rules in `scripts/sim/` never draw; views in `scripts/view/` never change state. Art is reached through `assets/art/**/manifest.json` so it can be swapped (pixel art later).
- **Data:** `data/*.json` is exported from the web game by `tools/export_data.py`; don't hand-edit it, re-export.
- **Art:** `assets/art/` is rendered from the web game's drawing code by `tools/export_art.py`.
- **Tests:** `godot --headless --path . --script res://tests/run_tests.gd`. The map generator test compares islands against the web generator's output for the same seeds (`tests/fixtures/`).
- Comment each ported function with its origin: `# web: <file> <function>`.
