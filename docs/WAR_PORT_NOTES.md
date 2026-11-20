# Porting wars and the computer nations: working notes

The plan after milestone 1. Each step is tested against the web game, then committed.

## Steps

1. **Full-size world** — done: `RealmGen.generate_world(seed, opts, true)` places Death Mountain, the Desert Oasis and
   the Heart of the Forest (`place_uniques`); `tests/fixtures/world/*.json` (6 seeds, `node tools/gen_fixtures.js`).
2. **Normal game setup** — done (`Game.new_world`, `tests/test_setup.gd`, fixtures from
   `tools/gen_world_setup_fixtures.py`). Notes: `pickAICapital` is the v103 version (wood around); computer nations get
   leaders (`assign_ai_leaders`) and their leader starts; monster names start with the province's name.
   Web order: `menu.js startGame`:
   `regenerate(seed, 'normal')` → `applyRace` → `setupGame` (capital: `menuOpts.start` center / edge / random,
   `uniqueBan`) → `spawnAINations(slots, races)` (ai.js + v96.js wrapper: Moderate / Difficult pick a school with
   `Math.random`) → `setupContent` (set pieces, Bandit Gangs) → `setupV78` (monsters, ruins, travelers, `spawnBosses`
   on normal maps) → `setupV96(false)`.
   v95: `rollYields` wrapper (Oasis 10/10/10, Heart 6/20/6, Death Mountain neighbors +5 gold), `provName` for the
   three, `canEnter` `bossBlock`, bosses (`BOSSES`, `BOSS_SITES`), artifacts (`ARTIFACTS`, `grantArtifact`).
   Computer nations are Realmlings only for now (`races[i] = 'realm'`).
3. **Wars** (war.js + wrappers in v95, v96, v99, v100, v102, v104, v105, v106): `S.wars`, `declareWhy` / `declareWar`,
   warscore (`occScore`, `addScore`, wipes), `stepWar` (occupation progress, the time tick, stalls), peace
   (`peaceCheck`, `makePeace`, terms), truces, alliances (`stepAlliances`), AI demands (`checkAIDemands`), AI-vs-AI
   peace (`aiPeace`), `hostile`.
4. **The computer players** (ai.js + v100, v102, v103, v104, v105 wrappers): `stepAI`, `aiPlan`, `aiMasons`,
   `aiWayfinders`, `aiTrain`, `aiFortUp`, `aiArmyOrders`, `aiConsiderWar`, `aiPayday`, `aiRedesign`. Fixtures with
   `Math.random` pinned (as for battles).
5. **Diplomacy UI**: met nations, declare war, alliance offers, peace terms, the war chip.

## Things to remember

- **Always grep for wrappers** (`name = function`) before porting a function: later web files replace many of them.
- **Key order matters**: the game iterates over tables (leaders, schools, monsters). `data/web/*.json` keeps the web's
  order now (`tools/split_data.py`; the first export had sorted keys).
- **Chromium's sort**: `arr.sort(() => r() - 0.5)` is a plain binary insertion sort up to 15 items and TimSort's
  run + insertion from 16 to 63 (`JS.sort_random`); node's V8 differs for short arrays.
- `Game.test_random` pins the web's `Math.random` draws (`js_rand`) in tests.

- Owners: player `ME = 1`, raiders `3`, computer nations `4`–`10` (`AI_IDS`). `NATIONS[id]` holds each AI's state.
- Many shared functions become owner-aware: outpost / building completion, `cancelBuild` refunds, arrowslits and
  moats (`techOf(owner, id)`), Wayfinder deaths, bandit bounties, battle colors, the minimap borders.
- The web game keeps going after an error; Godot doesn't: test long AI runs headless.
