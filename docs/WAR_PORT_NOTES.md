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
3. **Wars** — ported, being verified (`tests/test_war.gd`, fixtures from `tools/gen_war_fixtures.py`; not in
   `run_tests.gd` yet). It matches the web game up to the first payday; the computer nations' payday (`aiPayday`:
   income, storage, exhaustion, research, money spells) comes with step 4. The fixture freezes the AI brain
   (`stepAI`, `aiEnemyThink`) and pre-meets every nation (meeting one pauses the web game).
   Ported: declaring (fee, allies joining, the 2-enemy cap, truces, surrender lock), warscore (occupations, wipes by
   army size, the occupation tick once a war is serious), occupation progress (moats, frozen during battles, kept when
   the capturer wins), stalls, the 20-minute timer, peace terms (white, gold, provinces / annexation, surrender),
   Conquered Capitals (v102), evicting armies, killing a nation, AI demands to the player and AI-vs-AI peace,
   alliances with the v105/v106 rules (opinion, rivals, proclaimed enemies), meeting nations, Proxy War exhaustion.
   Web: war.js + wrappers in v95, v96, v99, v100, v102, v104, v105, v106): `S.wars`, `declareWhy` / `declareWar`,
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

## Step 4 map: ai.js functions and the files that wrap them (port the last wrapper's behaviour)

- spawnAINations: v96 · pickAICapital: v103 (done)
- Economy: aiGives (swamp, v105), aiProvIncome (v106, swamp), aiUpkeep (v106 upkeepAdjust), aiIncome (v104, v95,
  swamp, v105), aiStorage (swamp), aiSpells (v105, v98), aiProvResearch (v105)
- Research: aiTechsLeft (v103), aiDrawOptions (v103, v105), aiTechWeight (v103, v104), aiPick, aiFinishTech,
  aiTechPayday; aiRedesign (wood, swamp: other races only)
- Brain: aiPlan (v104, v103), stepAI (v100, v102, v104, v103), aiQueueStep (v101, v102), aiTrain (v103),
  aiReach (v104), aiBuildWhy (swamp), aiNextBuilding (v104, v103), aiMasons (v103), aiFortUp (v103),
  aiArmyOrders (v101), aiWarGoal (v100, v101, v103), aiConsiderWar (v103, v104)
- Also v106 `aiEnemyThink` (Proclaim Enemy, from `stepEnemies`), v100 `aiNoteDefeat` (from warWipe / retreat),
  v100 counter designs (`aiCounterDesigns`).
- `aiPayday` runs from `payday` even when the brain is frozen.
