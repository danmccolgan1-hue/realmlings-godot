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
3. **Wars** — done (`tests/test_war.gd`, in the suite; fixtures from `tools/gen_war_fixtures.py`, which freeze the
   AI brain: `g.ai_frozen`). Both fixtures match the web game to the end.
   Ported: declaring (fee, allies joining, the 2-enemy cap, truces, surrender lock), warscore (occupations, wipes by
   army size, the occupation tick once a war is serious), occupation progress (moats, frozen during battles, kept when
   the capturer wins), stalls, the 20-minute timer, peace terms (white, gold, provinces / annexation, surrender),
   Conquered Capitals (v102), evicting armies, killing a nation, AI demands to the player and AI-vs-AI peace,
   alliances with the v105/v106 rules (opinion, rivals, proclaimed enemies), meeting nations, Proxy War exhaustion.
   Web: war.js + wrappers in v95, v96, v99, v100, v102, v104, v105, v106): `S.wars`, `declareWhy` / `declareWar`,
   warscore (`occScore`, `addScore`, wipes), `stepWar` (occupation progress, the time tick, stalls), peace
   (`peaceCheck`, `makePeace`, terms), truces, alliances (`stepAlliances`), AI demands (`checkAIDemands`), AI-vs-AI
   peace (`aiPeace`), `hostile`.
4. **The computer players** — done (`scripts/sim/ai.gd`, class `Ai`: static functions taking the Game and the
   nation). `tests/test_ai.gd` plays three fixture games from `tools/gen_ai_fixtures.py` (`Math.random` pinned to
   0.5, the player idle): ember (3 nations, 40 min), river (2 nations, 40 min), crowd (6 nations, 60 min, bandit
   waves, a war against the player and one between two nations). Every nation's stock, income, research, buildings,
   units and queues match the web game at every 10 s snapshot, to the end.
   Ported with it, because the computer nations use them: crops (staple / cash / fiber), `stepScouts` (Wayfinders and
   Masons running from soldiers), `outpostClaimed`, `evictStrays`, fort gates for every nation, bandit waves (v96),
   Proclaim Enemy and the v106 opinion parts, owner-aware mana, leader soldier bonuses, plots, development and builds.
   Not yet: gift vaults, Swampling and Woodling nations.
6. **Batch A: sieges, quakes, artifacts** — done (`tests/test_siege.gd`, fixtures from `tools/gen_siege_fixtures.py`:
   a siege, a Shockwave then an Earthquake, a boss fight; all match the web game to the end).
   - Sieges (gpc.js + v102.js): `pathNbr` with `siege`, `findPath` falling back to a route through hostile walls,
     `siegeHold` in the movement loop (the army walks up to the wall and stands there), `stepSiege` (10+ soldiers take
     1 wall health a second; palisade 40, stone 120), `breakWall` (the border opens; the wall is remembered),
     rebuilding broken walls from a fort or capital at peace (50 wood a wall, 15 s), wall health bars and cracks.
     Computer armies count a hostile wall as passable at 3 extra hops (v104 `aiReach`).
   - Earthquake and Shockwave (gpc.js Z11/Z12 + v98 times 30 s / 15 s and mana 200 / 50): for you (Mage card;
     Shockwave aims at a neighboring province) and the computer nations (`aiQuake`).
   - Bosses and artifacts (v95 + v105): boss fights decided by power (`BOSS_K`, the boss's fortune), the artifact to
     whoever beat it, +25 opinion with every nation; all nine artifacts' effects (speed, health, attack, maces,
     income, storage, upkeep, the Lidless Eye, Winged Slippers with their 60 s cooldown).
   - Intact Ruins: a random Tier I Government technology (Math.random), or 3 minutes of research when none is left.
   - Fixed on the way: battle sides are taken in owner order like the web game (`Object.keys` sorts number keys),
     and a battle between sides at peace ends.
5. **Diplomacy UI** — done (`scripts/ui/diplomacy_window.gd`, Y): your wars with warscore and the peace terms you can
   offer (white, gold, provinces / annexation, surrender, each with the reason it is unavailable), every met nation
   with leader, difficulty, size, army power, opinion (tooltip: its parts) and relation, Declare War, Proclaim /
   Renounce Enemy. The top-bar button turns into a war chip. AI demands and alliance offers use the dialog box.
   Start menu: Practice island or a full map with 1–6 opponents (Easy / Moderate / Difficult / Mixed) and a start
   position. Map: other nations' settlements only where explored, their units in their color (red when hostile).
   The v105 actions are in now (Batch B, below).
6. **Batch B: diplomacy actions, gift vaults, requests, news** — done (v105 dx* functions, matched on 2 fixtures in
   `tests/test_dipl.gd`):
   - Actions, each with its web reason when unavailable: Flirt, Gift (1000 gold), Propose / Ask for an alliance,
     offer and ask for military access, Trade Network, Send spies (200 gold, intel on success), Bribe a third
     nation (2000 gold; the fixtures never have a valid target, so only the reasons are tested).
   - Requests go through one queue (`dip_request`): timer, yes / no / Later / Show me, "N requests waiting"
     (`scripts/ui/request_box.gd`). Alliance offers from computer nations use it.
   - Pacts end with their reason (war, opinion, timeout); Trade Networks add gold to the capital's Trade Routes.
   - Gift vaults (v105) on the map and their payout; a news list (wars, peace, pacts) in the Diplomacy window.
   - Not ported: Swampling / Woodling-only pacts (growl, crime). The web AI doesn't flirt or gift to you either.
7. **Batch C: flags, tooltips, settings, patch notes** — done (`tests/test_ui.gd`):
   - Notification flags (`scripts/ui/flag_bar.gd`): flags.js plus the v96, v98, v102, v105 and v106 wrappers, in the
     web order: idle research, Army Exhaustion, open plots and upgrades (several places: clicks step through them),
     quakes, truces ending, warscore ±100, white peace in 30 s, Grave Robbing / Trading ready, requests waiting (these
     replace the "N requests waiting" button), war news, over the province limit. Right-click hides a flag until its
     reason goes away and comes back (v102 flagAck). Fix over the web game: right-clicking the province-limit flag
     does hide it (in v106 the v102 handler cancels the dismissal). Swampling-only flags (Thug Den room, Sacred Pyre)
     and the dead ones (alliance ended, ally fort) are left out. Flag art: `tools/export_flags.py` renders FLAG_IMG to PNG.
   - Tooltips: the command card shows the web cmdInfo box (name, description, cost, why / Ready) for building,
     surveying, roads, spells, Shockwave / Earthquake, flying, retreat, split, combine, rest, retrofit, inspect,
     cancel and dismiss; the province panel's train, develop, rebuild walls, tear down and Forge / Mage Tower buttons
     explain themselves; the resource bar, clock and roster too. The look is `assets/ui/theme.tres`
     (`tools/make_theme.gd` from `UiKit.tooltip_theme`).
   - Settings (`scripts/core/settings.gd`, `scripts/ui/settings_window.gd`, remembered in `user://settings.json`):
     interface size, full screen, Calm map (trees stand still; the port has no villagers to hide), Record games, the
     map seed, and the debug switches (reveal, +2000 resources, every technology; swamp.js). Not ported: Quick queue
     (the port has no Ctrl+right-click build menu yet), music and sound volumes (no audio yet).
   - Patch Notes on the start screen: the port's own versions, then the web game's v106 notes (PATCH_NOTES).
8. **Batch D: recordings and replays, Windows build, saves, speed** — done (`tests/test_replay.gd`, `tests/test_build.gd`):
   - Recording (`scripts/sim/recorder.gd`; Settings → Record games, off by default; full maps only): the web game's
     v102 log (events by diffing every second: buildings built / upgraded / lost, settlements gained / lost,
     research, milestones, wars, peace with its terms; a line per nation every 30 s) plus a map frame every 5 s
     (province owners and stages, buildings, roads and walls as changes; every nation's armies with ids). Left out of
     the web log: the player's picked research, training and spell counts, design changes, gear mix. It lives in the
     save (`rec`) and is written to `user://recordings/` on every autosave, on leaving, on falling and on quitting.
     Recording reads the game only (the test checks a recorded game plays exactly like the same game unrecorded).
   - Replays (`scripts/view/replay.gd`, `scripts/ui/replay_hud.gd`, `scripts/ui/recordings_window.gd`): Recorded games
     on the start screen; the map is raised again from the seed and a stand-in Game is set to each moment (armies glide
     between frames); play / pause, 1× to 64×, a timeline to scrub, every nation's numbers, a chart of provinces held,
     and the latest events. No fog in replays (or with Debug → Reveal).
   - Windows: `export_presets.cfg` (icon `assets/icon/realmlings.ico` from `tools/make_icon.gd` + `.py`, version 0.5.0,
     company and copyright, build folders left out); `docs/BUILDING.md` has the steps to export on your PC.
   - Saves carry `version` 2 and the `build` that wrote them; version-1 saves load (missing fields keep a new game's
     defaults), a newer save is refused with the reason (`Game.migrate_save`, `Game.save_why`).
   - Speed, same answers (all fixtures still match): `Game.enter_cache` (the unit checks of `can_enter` worked out once
     per AI walk), `Game.armies_by_prov` (scouts and patrols), Wayfinder bandit check, road midpoints cached. Six
     computer nations, 40 minutes: about 3–6 ms of rules per frame, the worst AI frame 15–20 ms (was 37).
     Rendering can't be timed here (software GL); the map's own drawing code is about 3 ms a frame on the full map.
   - Fixed: the map and minimap took nation colors from the static PLAYERS table (ids 1–6), so games with 4+ opponents
     failed to draw borders and other nations' colors could differ from their own; they use `player_info` now.
9. **Batch E: what the playtest found broken or invisible** — done (`tests/test_ui.gd` gate roads and fort commands):
   - Screen: a new top bar (`scripts/ui/top_bar.gd`, icons drawn in `scripts/ui/glyph.gd`): resources with caps and
     income, mana and its regeneration, forts, provinces, the payday ring, the research strip with each tree's circle
     and points; clock, play/pause, full screen (F11), zoom and home buttons; menu, flag and name, Armory, Diplomacy.
     Minimap bottom left, toasts as paper notes bottom center, the Paused plaque under the flags.
   - Fixed: a new game added a second outliner list and Armory window over the first ("text overwriting").
   - Symbols: DejaVu Sans is a fallback font so ⚔ ✗ and the like show on Windows; the replay buttons are words.
   - Notification flags are swaying banners with a glow and a count badge, centered under the research strip. Every
     nation flag (72) is exported (`tools/export_flags.py`); armies carry theirs.
   - Research window: progress bars, a collapsible Researched list, option cards with icons, the Auto toggle, and it
     closes once every tree is researching (web v101).
   - Map: armies drawn as up to 10 figures with their flag, a health bar and their power (web drawArmy);
     palisades, stone walls with towers, gates in the holder's color, roads that grow while built (govtech.js).
     The Mason no longer vanishes while building a road (road plots have no slot). The Road button finds a wall
     between two of your provinces when no open border is near (`Game.mason_road_border`, v106).
   - Landmarks (`scripts/view/map_landmarks.gd`, through `scripts/view/pen.gd`, a small canvas-path stand-in):
     Death Mountain, the Desert Oasis and the Heart of the Forest (v95.js), set pieces and their "+N" tags (gpc.js,
     content.js), ruins and treasure (v78.js), lost travelers with their cart and campfire, and the pulsing red outline
     of provinces where bandits or monsters were seen (v78.js drawLairGlow).
   - Camera: the game opens framing your capital (web `home()`, also the Home button), zoom up to 6×, so the drifting
     clouds only show zoomed out, as in the web game (the fade rule was already the same).
   - Buildings can be selected (click the settlement or a building, or its button in the province panel); the command
     card is always shown and holds the building's actions: training and the queue (capital, Barracks, Mage Tower),
     Upgrade to Fort and cancelling it, Rebuild walls, Develop, Dismantle fort (v96), Forge and Mage Tower upgrades,
     tearing down. The province panel keeps the information and Develop only. Not yet: icons on the card, the
     Stable and Thieves' Den cards.

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
