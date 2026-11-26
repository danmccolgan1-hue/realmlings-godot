# Quests, digging, Reliquaries, Dungeons and armaments: the plan

The design is in the attachment "Quests, Digging, Reliquarys, Dungeons, Araments" (2026-11-25). This page is that
design with the answers to the open questions folded in, and the order it is built in, one chunk per session.
Godot-only content: nothing here exists in the web game, so none of it is in `data/web/` or `reference/`.

## Decisions (answers of 2026-11-25)

- **Cycle** = the 10 s payday. Dig rolls, event chances and the Detained count run on it.
- **Quests chosen per map** (full maps only; not the Practice island or the tutorial): one Rebuilding the Library, one
  Forgotten War, one Mage's Request, one Reclaiming Battlegear, and two of the seven Spell Books and Lost Armaments.
  Only the chosen quests' items get dig sites.
- **Locked gear and spells are hidden completely** until their quest unlocks them.
- **Items go straight into a Reliquary** with room, from anywhere. A scouting unit keeps an item only when no Reliquary
  has room (it carries **one**; more is dropped as a chest). Carried items move into a Reliquary as soon as one has room.
- **Several Reliquaries** may be built (one per province, 9 slots each).
- **Completing a quest destroys every item of that quest**, used or extra.
- A scouting unit that dies with items **drops them as a chest** where it fell. A Reliquary torn down, dismantled,
  shaken down by an Earthquake or lost with its province drops its items as a chest there too.
- **Dig sites** are hidden until surveyed. Once someone uncovers one, every player who can see the province sees it.
  Fallen Star sites are seen by anyone who has ever explored the province.
- **Fallen Stars**: the first falls 30 minutes in, each next one 15 to 25 minutes after the last, until the game
  ends. Never on Death Mountain, the Oasis, the Heart of the Forest or their boss provinces.
- **Armor prices drop 10% across the board.** The special armors cost what Tier 4 of the same armor type costs.
- **Freak Man's Bone Regalia** "steals mage buffs": in battle it removes the enemy's Cursed Weapons or Hardened Skin and
  gives it to the wearer's side.
- **Wall of Flame and Time Warp** can be cast by any Mage, Warlock or Druid of a human nation that completed the quest.
- **Primal beasts** patrol their own province like monsters and bandits.
- **Dungeons** are hidden entirely in single player. Battles no longer give prisoners: prisoners come only from
  Dungeon quests. Several Dungeons may be built; Jailbreak needs 3 (8 convicts).
- **Convicts captured by someone else** can be traded for, or freed in a peace deal.
- **War, new peace options at 50% warscore:** *Raid Reliquary* (they have one with at least one item: you get 1 to 4
  of their items) and *Free Prisoners* (they have a Dungeon with prisoners: they become yours, except an envoy,
  general, noble, lady, apprentice or merchant, who goes home).
- **Ransom answers**: Player Y has 40 s; no answer means war. In a ransom war the only peace is reaching 50% warscore:
  Player Y frees the prisoner; Player X, at 50% the other way, can *Demand Concession*, which ends it in X's favor.
- **"−10 Military Research for 10 cycles"** cuts the research rate by 10 for 10 cycles, never below 0.
- **Diplomacy gets a Trade action**: items and prisoners for items or resources.
- **The Quest Log shows every text of a quest**, and each collectible's count (have / need) so the player knows what
  is left.
- Text fixes: "Weapon: Triune Staff unlocked", Shield of Sham part 2 says "shield", the Envoy prompt says "his",
  the herb quests' names match, "Apprentice" is one of the Envoy variants, "Jailbreak".

- **Research rewards** ("+6 Government Research") are a permanent +6 research points every cycle. Dungeon-quest
  rewards ("+300 Government Research") are one-time.
- **The Mason's card has two pages** (all races): the outpost and the buildings that need no research (the Reliquary
  among them) first, with **Advanced Buildings** on cell 12 (bottom left, hotkey U); that page holds every building
  research unlocks, with **Back** on the same cell. Road, Cancel build and Dismiss stay where they were.

## Sessions

| # | Session | State |
|---|---|---|
| 1 | **Foundations**: quest and item catalog (`data/quests.json`, `scripts/sim/quests.gd`), the quests chosen when the map is made, hidden dig sites, each human nation's quest record, saves (version 3) | Done |
| 2 | **Reliquary and carrying items**: the Reliquary for all three races (art, build menus), its 9 slots on the building's card, scouts carrying one, auto-deposit, chests on the map, chests dropped by dying scouts and lost Reliquaries, picking chests up | Done |
| 3 | **Digging and Fallen Stars**: surveys uncover dig sites (red X), Dig on the scouting unit's card and its animation, the rarity roll every cycle, the site gone once dug, Fallen Stars (timer, shooting star, silver X) | Done |
| 4 | **Quest engine and Quest Log**: triggers, progress, completion and failing everyone else, item removal, popups, the Quest Log window and hotkey (all texts, counts), race words, the nine research quests (and the engine for every quest: Battlegear, Spell Books and the Lost Armaments' part 2 already finish and record their unlocks) | Done |
| 5 | **Battlegear and armor**: the three Battlegear quests, the three armors (hidden until unlocked), armor prices −10%, Siegebreaker's siege speed, the Bone Regalia's buff theft | |
| 6 | **Primal beasts**: four monsters in Meadow, Fae Forest, Drylands and Bog with their counts and drops | |
| 7 | **Lost Armaments**: the four map quests and their part-2 dig spot, Cutlass, Axe, Maul, Shield of Sham (first blow negated), Triune Staff | |
| 8 | **Spells**: the two Spell Book quests, Wall of Flame, Time Warp | |
| 9 | **Dungeon**: the building (multiplayer only, three looks), prisoner slots and silhouettes, Detained, Prisoner Escape | |
| 10 | **Ransom quests and their war**: the Captured Royal Lady, Captured Envoy and its four variants, the two-player dialogs, the 40 s answer, the ransom war (50% frees, Demand Concession), research penalties | |
| 11 | **Jailbreak**: Convict Gangs, recovering convicts, execute or pardon | |
| 12 | **Trade and raids**: Diplomacy's Trade (items, prisoners, resources), Raid Reliquary and Free Prisoners at 50% warscore | |
| 13 | **Computer nations and finishing**: AI Reliquaries, digging and chests (no quests), patch notes, How to Play, a balance pass | |

## What sessions 1 to 4 built

- `data/quests.json`: every quest (texts, triggers, goals, rewards, the Lost Armaments' part 2) and relic (rarity,
  dig-site count, icon look), the Reliquary's building entry, the carry limit, slot count and Fallen Star timings.
  Written by hand (Godot only), so `tools/export_data.py` doesn't touch it. Texts use the Realmlings' words
  ("Mage", "Wayfinder", "Mage Tower"); `Races.words` turns them into the player's race's.
- `scripts/sim/quests.gd` (`Quests`): reads the catalog; `pick(seed)` chooses the six quests; `place_digs` buries the
  chosen quests' relics (stream `<seed>:digs`, one relic to a province, never on capitals, the Intact Ruins, the
  unique provinces or the bosses' provinces and their neighbors); `setup` runs both at the end of `Game.new_world`
  and rolls the first Fallen Star's time (stream `<seed>:stars`). Then the Reliquary rules: `reliquaries`, `room`,
  `deposit`, `take`, `count`, `give` (Reliquary, else the scout's bag, else a chest), `drop`, `step` (scouts open
  chests where they stand), `payday` (bags empty into Reliquaries with room), `unit_lost`, `extras_lost`.
  `Quests.added()` is the hook the quest engine fills in session 4.
- `Game`: new saved fields `quests_on`, `quest_pick`, `digs`, `chests`, `star_next` and each human nation's
  `quest_log` (a seat field); a unit's `bag`; a Reliquary's `items` on its building record (so a captured Reliquary
  keeps its relics for the captor). Save version 3; older saves load with quests off. `Game.QUESTS` (static, on)
  turns the system off for the tests that compare against the web game (`tests/run_tests.gd`).
- Hooks: relics drop as a chest when a scouting unit dies, is dismissed or its nation falls, and when a Reliquary is
  torn down, dismantled with its fort, shaken down by an Earthquake, or cut when a captured province has fewer plots.
- Building: the Reliquary (100 gold, 100 wood, no upkeep, one per province, any province you own) is on the plot
  menu, the Ctrl+right-click build menu and the first page of the Mason's card, for every race.
- Interface: the Reliquary's card shows its 9 slots (top-left 3×3, dark gray outlines, the relic's icon and name on
  hover); a scouting unit's card shows what it carries in the bottom row; chests with a gold lock are drawn on the map
  where you have vision.
- Art (placeholders, `tools/make_quest_art.py`): the ornate vault, the spiky bunker and the treehouse with their
  rising frames, their build icons, and an icon for each of the 34 relics.
- Tests: `tests/test_quests.gd` (catalog, picks, dig sites, building, carrying, chests, losses, save and load,
  quests off).

### Sessions 3 and 4

- Digging: a survey uncovers the province's dig site (`Quests.uncover`, called from the survey's end); **Dig** sits on
  cell 5 of the scouting unit's card (and Digging… stop while it digs); each cycle the digger rolls its relic's
  rarity on its own stream (`<seed>:dig:<province>:<unit>:<n>`), so a loaded or multiplayer game rolls the same.
  A digging unit counts as busy (auto-survey leaves it alone), shows "digging", bobs and throws clods; moving it
  stops the digging.
- Fallen Stars (`Quests.step_stars`): at `star_next`, a star falls on a province that isn't Death Mountain, the
  Oasis, the Heart of the Forest, a boss's province or a dig site (stream `<seed>:star:<n>`); the next is 15–25
  minutes later. A silver X for anyone who has explored the province, a shooting star (`Game.star_fx`, not saved).
- The quest engine (`Quests.check / acquire / advance / complete`): runs when a relic reaches a Reliquary and every
  cycle (for the quests waiting on a Mage Tower). Rewards: `quest_rate` (research every cycle, added in
  `Game.tech_rate`) and `quest_unlocks` ("armor:bone_regalia", "spell:flamewall", "weapon:cutlass"...; sessions 5–8
  make them do something). A Lost Armament's part 2 places its prize's dig site in the nation's own land, seen and
  dug only by that nation (`only` on the dig site).
- The Quest Log (`scripts/ui/quest_log.gd`, `QuestLogWindow`): the button under Diplomacy (games with quests only) or **L**. Open
  quests first, then finished (green, "Complete"), then failed (red, "Failed"); click a title to fold its texts.
  Each shows every text so far and each relic's count.
- Pop-ups now wait their turn: a new one no longer replaces an open one (a quest pop-up could otherwise have wiped
  out a choice such as the lost travelers').
- Pictures for checking the view: `godot --path . -- --world=moderate,easy --seed=ember --shot=a.png
  --quests=log|reliq|mason|masonadv|scout`.
- Also fixed on the way (0.19): a nation handed to the computer registers its designs as loading a save does, so
  `tests/test_seats.gd` passes again.
