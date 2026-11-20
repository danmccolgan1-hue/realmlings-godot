# Folder layout and naming rules

Everything a later art pass (for example pixel art) might replace is reached through **data and file paths**, never through drawing code inside the game rules. Keep it that way.

## Folders

| Folder | Holds |
| --- | --- |
| `scenes/` | Godot scenes (`.tscn`). `main.tscn` is the entry point. |
| `scripts/core/` | Pure helpers with no game state: random numbers, geometry, JSON loading. |
| `scripts/gen/` | The map generator (port of the web game's `gen.js`). |
| `scripts/sim/` | Game rules and state. **No drawing, no nodes, no input here.** Plain `RefCounted` classes that can run headless. |
| `scripts/view/` | Everything that draws the world: map, units, buildings, fog, camera. Reads `sim` state, never changes it. |
| `scripts/ui/` | Menus, panels, tooltips, hotkeys. Calls into `sim` through its public functions. |
| `data/` | Game data exported from the web game (JSON). The rules read these instead of hard-coding numbers. |
| `assets/art/` | Images. See the art naming rules below. |
| `assets/audio/` | `music/` and `sfx/`. File names match the web game's sound ids (`bld_done.mp3` is `sfx("bld_done")`). |
| `docs/` | The rules spec, the asset list and these rules. |
| `tests/` | Headless test scripts: `godot --headless --path . --script res://tests/run_tests.gd`. |
| `tools/` | Scripts that regenerate `data/` and `assets/art/` from the web game. |
| `reference/web-v106/` | The web game's source, v106. The source of truth for every rule being ported. Not exported with the game. |

## Code

- GDScript, typed where practical. Files `snake_case.gd`, classes `PascalCase` (`class_name`), constants `UPPER_CASE`.
- Rules code names things the way the web game does (`BUILD_DEFS`, `provLimit` → `prov_limit`), so a rule can be found in `reference/` by name.
- Every ported function says where it came from: `# web: game.js computeIncome()`.

## Art

`assets/art/<category>/<race>/<id>[_<variant>][_<direction>][_<frame>].png`

| Part | Values |
| --- | --- |
| `category` | `settlements`, `buildings`, `units`, `houses`, `icons`, `flags`, `ui` |
| `race` | `realm`, `swamp`, `wood`, or `common` for shared art |
| `id` | The web game's id: `capital`, `barracks`, `d-sword` becomes `d_sword` |
| `variant` | `v0`, `v1`… (building looks), `lv1`, `lv2`… (upgrade levels), `grassland`… (settlement terrain) |
| `direction` | `d0`…`d7`: 8 facings, `d0` = facing the camera, then clockwise in 45° steps |
| `frame` | `f0`, `f1`… animation frames |

Each art folder has a `manifest.json` listing every image with its **anchor**: the pixel in the image that sits on the object's ground point (the province center for settlements, the plot for buildings, the feet for units), and the **scale**: image pixels per world unit. Placement code reads the anchor and scale and never guesses offsets, so any art set with a correct manifest can replace another.
