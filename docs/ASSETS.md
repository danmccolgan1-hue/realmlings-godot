# Asset list (milestone 1: Realmlings, Practice island)

Exported from the web game v106 by `tools/export_art.py`. Every folder has a `manifest.json` with each image's anchor (`ax`, `ay`) and scale (image pixels per world unit; the web game zooms to at most 3 screen pixels per world unit).

## Exported

| Folder | Images | What |
| --- | --- | --- |
| `buildings/realm` | 64 | Every Realmling province building, each upgrade level, plus 25/50/75% construction stages |
| `houses/realm` | 12 | Village houses, plain and with the owner-colored roof |
| `icons/common` | 14 | Resource icons and command icons |
| `icons/realm` | 112 | Technology icons and building thumbnails |
| `settlements/realm` | 120 | Outpost, fort, capital × 4 terrains × 10 looks (the web picks look = (province × 7 + 3) mod 10) |
| `units/common` | 26 | Spell creatures and bosses (Ent, Zombie, Jackal-man, dragons and others), facing left (d2) and right (d6) |
| `units/realm` | 72 | Wayfinder, Mason, Mage, Swordsman, Spearman, Clubman, Rider, Crossbowman, Bandit, each in 8 facings (d0 = facing the camera, then clockwise) |
| `flags/common` | 10 | Notification flag pictures (SVG) |

## Animation

Realmling soldiers and workers have no leg animation in the web game: walking is a bounce (`hop = -|sin(t × 9)| × 3` world units while moving, `-|sin(t × 8)| × 2` while working) and the facing snaps to 8 directions. The Godot view reproduces that in code, so one image per facing is enough. Horses sway their tails; that is left out for now.

## Not exported yet

| Missing | Why | When |
| --- | --- | --- |
| Map art: terrain, coasts, lakes, forests and mountains along borders, rivers, walls, gates, roads | The web game draws these procedurally along each map's own borders; Godot redraws them the same way | Phase 4 (visuals) |
| Armory custom designs | Soldiers are drawn from their gear; any mix is possible. Milestone 1 uses the built-in designs above; a gear-layer composer comes with the Armory | Phase 5 |
| Effects: spells, battles, construction dust | Drawn by code each frame | Phase 4 |
| Leader portraits | `.jpg` files in the web project's `portraits/` folder | With the interface |
| Music | 38 MB; kept out of the repository until needed | Phase 5 |
| Swampling and Woodling art | Not in milestone 1 | Later milestones |
