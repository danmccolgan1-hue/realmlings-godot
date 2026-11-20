# Rules spec: porting the web game (v106) to Godot

The web game in `reference/web-v106/` is the source of truth. This spec says **what to port, in what order, and where each rule lives**. Numbers live in `data/web/*.json` (every constant, read from a running Realmling game; `data/index.json` says which file holds which name).

## How the web code is layered (read this first)

- `game.js` is the original game. Every later file (`war.js` … `v106.js`) **wraps** earlier functions: `{ const f0 = fn; fn = function (...) { ...f0(...)... } }`. The behavior to port is the **whole chain**, ending at the last wrapper. Before porting a function, search every file for `<name> = ` to find its wrappers, in the order `assemble_game.py` concatenates the files:
  `game.js, war.js, equip.js, tech.js, techicons.js, govtech.js, magic.js, menu.js, sound.js, features.js, flags.js, content.js, ai.js, gpc.js, v78.js, swamp.js, wood.js, v95.js … v106.js, battlesim.js, save.js, tutorial.js` (`gen.js`, `iso.js`, `buildings*.js` are separate modules).
- Game state is one object `S` (see `setupGame()` in `game.js` and each `setupV**` function). Saves serialize all of `S` plus `yields`, `world` seed and a few globals (`save.js`).
- Time: `S.t` in seconds, advancing only while unpaused. **One economic tick (`payday`) every `TICK` = 10 s.**
- World units: the generator works in its own units and `scaleWorld` multiplies every coordinate by `WORLD_K` = 2.

## Milestone 1 scope: the Practice island, Realmlings, the player alone

`RealmGen.generatePractice(seed)` (a 10-province island cut from a full world). Checked in a running game (seed `ember`): 10 provinces (5 grassland, 3 forest, 1 swamp, 1 desert), **no other nations, no Roaming Monsters, no set pieces**. The web game can place Bandit Gangs on it (seed `oak`: two gangs of 2 Footmen); the Godot milestone leaves them out until battles are ported. The player starts with a capital (province 0 on every seed checked), 50 of each resource (`START_STOCK`; Mage leaders get +200), a Wayfinder (`pioneer:B`), a Mason (`mason:A`) and the leader's start (army, building, technologies: `applyLeaderStart`). Reference runs: `tools/gen_econ_fixtures.py`.

**Not needed for milestone 1** (port later): AI nations (`ai.js`, `v103.js`), war and peace (`war.js`), diplomacy (`v105.js`, parts of `v106.js`), Swamplings and Woodlings (`swamp.js`, `wood.js`, `*bld.js`), Bandit Gangs, monsters, set pieces, travelers, ruins (`content.js`, `v78.js`), multiplayer bits. Battles can't happen on the Practice island (no enemies), so combat is ported after milestone 1 unless a test scene needs it.

## Progress

| Step | State | Tested against the web game |
|---|---|---|
| 1. Map generator | Done (`scripts/gen/realm_gen.gd`) | 16 seeds, every province, border and vertex (`tests/test_world_gen.gd`) |
| 2. World setup | Done for Realmlings on the Practice island (`scripts/sim/game.gd`, `world_prep.gd`): capital choice, yields, starting units, all 8 Realmling leader starts | 4 seeds × 8 leaders (`tests/test_economy.gd`) |
| 3. Economy | Done for what exists at the start: income, upkeep (leader cuts, free buildings, province limit), storage, payday every 10 s, Army Exhaustion and desertion | same, 200 s of play each |
| 4. Settlements and buildings | Done: outposts (survey first, border your land, outpost limit), buildings on plots (`buildCheck`, `bslotOf`), Fort upgrades. Building levels (Forge, Mage Tower), demolish and v106 development still to come | 4 seeds, scripted game (`tests/test_play.gd`) |
| 5. Workers, movement, fog | Done: orders and paths (`findPath`, `walkHops`, `navRoute`), exploring (8 s a province), surveys (the lap walk), auto-scouting, Far Sight, fog (explored / visible), Intact Ruins placement, Forgotten Treasure. Roads and walls still to come | 4 seeds × 2 scripted games, a snapshot every second, positions to the last digit |
| 6. Training | Done: capital, Barracks (Armory designs; cavalry with a Stable; the Crossbowman with a Forge), Mage Tower; unit limits, queues, joining the army in the province, rally points (no UI yet). Army Training Orders (v106), retrofits, split / combine still to come | 4 seeds, scripted game |
| 7. Research | Done: the three trees, tiers, rates, costs, picking and switching, the bank, the random offer (`drawOptions` / `topUpOptions`), auto-research, Forge / Mage Tower levels, the leader's school lock. Each technology's effect arrives with its system | 4 seeds × 2 scripted games (the web game's random offer is replaced by recorded picks) |
| 4–5. Roads, walls, development | Done: roads (speed by tier), walls and gates (pathfinding through your own gates, marching units re-routed), forts and capitals walling their open borders with Wooden Walls, owned provinces revealing their resources, split / combine / dismiss, tear down, v106 development (levels, lucky finds, Deep Gold Deposits, the province limit). Wall rebuilding, sieges and broken walls come with war | 4 seeds × 2 more scripted games |
| 3. Economy, later | Crops and Harvest, Trade Routes, Sawyer Guilds, artifacts, research points and mana at payday, deep gold mines | arrive with the systems that switch them on |

Left out of milestone 1 for now: Bandit Gangs, travelers (`v78.js` placeTravelers), the technology the Intact Ruins grant is picked at random in the web game (tests remove the ruins and check their placement).

Port from the **assembled** game, not the separate files alone: `assemble_game.py` rewrites parts of `page.html` (for example the province inset distances 6 / 50 / 18 used for `ic`).

## Port order

Each step ends with a headless test and something visible in the placeholder view.

### 1. Map generator — `gen.js` (port whole)
- `generateWorld(seed, opts)` then `generatePractice(seed)`. Pure functions of the seed; must reproduce the web output exactly (tests compare against `tests/fixtures/*.json` written by the web generator).
- Random numbers: `seedRng` / `rngFrom` (string hash + PRNG with 32-bit integer math). Port bit-exact: GDScript ints are 64-bit, so mask with `& 0xFFFFFFFF` and emulate `Math.imul` and `>>>`.
- Output: `provinces` (site, verts, terrain, nbr, edges, coast), `vertices`, `edges` (a, b, v, open, style: `mountains` | `trees` | `river` | `palms` | null), `junctions`, `lakes`, `center`, `W`, `H`.
- After generation the web game runs `scaleWorld` (×2) and `prep(w)` in `page.html` (province polygons, inner polygons, `ic` = the province's drawing center, neighbor lists, `G.bounds`).

### 2. World setup and resources — `game.js`
- `rollYields()`: per-province gold / wood / food from terrain plus rolls, and the hidden gold deposit (25% desert, 5% elsewhere). Uses `rngFrom(world.seed + ':resources')`.
- `treeBorder`, `buildCap(p, type)` (4 farms, one Lumber Mill per tree border, one of anything else).
- `setupGame()`: initial `S`, start position, starting units and stock (`START_STOCK`), the capital. Leader starts: `applyLeaderStart` (`v105.js`, wrapped in `v106.js`).
- `CAPITAL_BONUS`, province names (`war.js` province naming).

### 3. Economy — `game.js`, `govtech.js`, `v104.js`, `v106.js`
- `computeIncome()`, `upkeep()` (+ wrappers), `extrasBonus(p)`, `payday(t)` every 10 s, `storageCap(k)` / `clampStock()` (base 2000, Granary / Storehouse / Bank raise it), Army Exhaustion when food runs out (`gpc.js`).
- Province limit: `provLimit`, `outpostLimit`, `perFort`, `fortsHeldBy`, `devLimitBonus` (`govtech.js`, `v106.js`).

### 4. Settlements and buildings — `game.js`, `gpc.js`, `v96.js`, `v104.js`, `v106.js`
- Outposts: `OUTPOST_COST`, `outpostWhy()`, build by a Mason (`orderBuild`, `startBuild`, build completion in `update()`), `outpostClaimed`.
- Upgrades outpost → fort: `upgradeWhy`, `startUpgrade`, `stepUpgrades`.
- Plots: `plotCap(p)`, `freePlot(p)` (`flags.js`), `usedSlots`, `buildCheck(p, type)`, `beginExtra`, `BUILD_DEFS` (costs, upkeep, gives, levels), building upgrades (Forge / Mage Tower levels), demolish (`v104.js`).
- Development (`v106.js`: `DEV`, `startDevelop`, `finishDevelop`, `stepDevelop`).
- Houses and villagers are decoration (`content.js` `syncTowns`): port with the view, not the rules.

### 5. Workers and movement — `game.js` `update()`, `features.js`, `govtech.js`
- Unit movement: `order(u, target)`, `findPath(u, target)`, waypoint following in `update()`, speeds (`SPEED`, `UNIT_SPEED`, `unitSpeed`), roads (`onRoad`, `roadSpeed`), province slots (`freeSlot`, `slotPos`).
- Wayfinder: exploring (entering unexplored land: `EXPLORE_TIME`, `S.explored`, `S.wf`), surveying (`startSurvey`, survey walk, reveals yields and deposits), auto-survey and the survey queue.
- Fog: `computeFog()` (`page.html` / `game.js`): explored vs visible provinces. (v106 lake / ocean reveal is a view rule.)
- Mason: outposts, buildings, roads and walls (`startLink`, `finishLink`, `linkWhy`, `raiseWall`, `ROAD_COST`, `WALL_COST`, road tiers), gates and fort walls (`gpc.js`), tear down / rebuild (`features.js`, `v106.js`).

### 6. Training and armies — `game.js`, `v96.js`, `v97.js`, `v104.js`, `v106.js`
- `trainable(kind, prov)`, `train(kind)`, `stepTraining(t)` (queues per building: `S.queues['barracks:<p>']`), `newArmy`, rally points (`rallyOf`, `rallyGo`, `rallyArrivals`), Army Training Orders (`v106.js`).
- Unit stats: `UNIT_DEFS`, `DSTATS`, `UNIT_BASE`; the Armory designs (`equip.js`: `WEAPONS`, `ARMORS`, `HORSES`, `designStats`); army merge / split, unit limits (`UNIT_LIMIT`).

### 7. Technology and government — `tech.js`, `govtech.js`
- `TECHS`, `TECH_COST`, `techCost`, `pickTech`, research progress, `hasTech`, `TECH_GIVES`, repeatable techs (`content.js`), government techs and their effects (`govtech.js`).

### 8. Magic — `magic.js`, `v95.js`, `v96.js`
- Schools (`SCHOOLS`), mana, spells (`SPELL2`, `castSpell`, `stepMagic`), mages and their gear. Only spells that work without enemies matter for milestone 1.

### 9. Saving and loading — `save.js`
- New format (the web saves won't load in Godot): serialize the Godot state to JSON with a version number. Keep the web's rule that a save stores the seed and regenerates the map.

### 10. Tutorial — `tutorial.js`
- The Basic Tutorial's steps (`TUT_TRIGGERS`, `TUT_EXPLAIN`, `TUT_FINAL`) and its own setup. Check which map it uses before porting.

## Interface (needed to play-test each step; full UI is Phase 5)

A plain placeholder interface is enough to test the rules: resource bar, select a unit, right-click to move, command buttons for the selected unit or settlement, a province panel with yields and plots, a research list. Keys and command names follow the web game (`CMD`, `GRID_KEYS`).
