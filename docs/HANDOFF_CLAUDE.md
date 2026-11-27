# Handoff for a new Claude conversation (2026-11-27, version 0.19.5)

Paste this whole file at the start of a new conversation, or tell Claude: "Read docs/HANDOFF_CLAUDE.md in the
realmlings-godot repo (branch `server`) and continue from there." Also read the repo's `CLAUDE.md`.

## Where things are

- **Repo:** https://github.com/danmccolgan1-hue/realmlings-godot. Work branch: **`server`** (built on `quests`).
  Not merged into `main` yet.
- **My PC (Windows):** `C:\Users\Woods\Documents\Realmlings\Realmlings-godot\realmlings-godot`. I use PowerShell.
  Git is installed (winget). Claude can reach this folder through the desktop app's device bridge.
- **Godot:** 4.7.2, GDScript only. In Claude's Linux workspace the binary is
  `/home/claude/godot/Godot_v4.7.2-stable_linux.x86_64` (not on PATH).
- **Rules reference:** `reference/web-v106/` (the web game). `docs/RULES_SPEC.md` maps systems to files.

## The server (DigitalOcean)

- Droplet: Ubuntu 24.04, 1 GiB, NYC, public IP **157.245.250.30**. SSH as `root` with my key.
- Firewall: TCP 22, UDP 24565 (widen to 24565-24569 to run several games).
- Service `realmlings` (systemd, `tools/server/realmlings.service`), runs
  `/home/realmlings/server/Realmlings.x86_64` in server mode, saves in `/home/realmlings/saves`.
  Exit 0 = game ended, stays stopped; exit 75 (or a crash) = systemd restarts it to a fresh lobby.
- Extra games: template `realmlings@.service` → `systemctl enable --now realmlings@24566` (port 24566, saves in
  `saves-24566`). Players join `157.245.250.30:24566`. ~200-250 MB each.
- Logs: `ssh root@157.245.250.30 "journalctl -u realmlings -n 50"`.
- Full guide: `docs/SERVER.md` (also the project doc `claude/server-setup.md`).

### Updating the server after a change

1. `git pull` on the PC. If it refuses because of local changes: `git checkout -- project.godot export_presets.cfg`
   and `Remove-Item` any listed `.uid` file, then pull again.
2. In Godot: Project → Export → export **Windows Desktop** (for players) and **Linux Server**
   (`build/server/Realmlings.x86_64`). Untick "Export With Debug".
3. `powershell -ExecutionPolicy Bypass -File tools\server\update_server.ps1 -Ip 157.245.250.30`
   (uploads, restarts every realmlings unit).
4. Send friends the new Windows build: the versions must match.

## How the server works (decisions I made)

- One server process = one game. The first player to join leads the lobby: map settings, optional password,
  kicking players, "Allows Debug", loading a save. Each new lobby gets a fresh random island seed.
- A player may start alone. Players joining a loaded game pick a nation from the save.
- Autosave; after a crash/restart the lobby offers to carry the saved game on. 0.19.3: no "End the game" button. A
  game with no player left (observers don't count) for 30 s is over: a last save is kept, the autosave deleted, and
  the server exits 75 so systemd starts a fresh empty lobby. Every finished game exits 75 now (always a lobby ready).
- 0.19.3 observers: **Watch** joins with `NetSession.watch` (players[id].watch). Never lead, always ready, no nation
  (`MpSetup.playing` filters them). Lockstep seat 0 = observer: `Game.spectator`, view_seat HOST, `Game.LOCAL = 0`;
  between steps `Game.spy_view()` swaps `cur` for a whole-map copy (spy_end before steps; to_save always saves the
  real seat). Hud/TopBar `observer` mode + `ObserverPanel`. Observer orders are dropped (Game.do, Lockstep._order).
- 0.19.3 Host online: `OnlinePorts` probes 157.245.250.30:24565-24569 ({"t":"probe"} → "probe_ok"), picks a random
  empty lobby of the same version and joins it with `fresh` (refused with NetSession.TAKEN if someone got there
  first → next port). None free: "No ports available. Try hosting locally."
- 0.19.3 loading screen (`LoadingScreen`): Game.build_pct reported from new_world/from_save; "building" message.
- Debug (only when the lobby allows it): reveal and +2000 resources go to all humans; "Every technology" asks
  for the Magic school.
- "Host locally" in the menu = a PC hosts, not the Droplet. "Host online" = an empty lobby on the Droplet.
- The Dungeon appears in any multiplayer game (`Game.mp_game`, saved), even with one player (0.19.3).
- Quests (0.19.3): picking up a relic (Reliquary or a scout's bag) starts its quest; no Mage Tower requirement
  (quests.json's trigger.tower is ignored). The pop-up shows the relic's icon (Game.dialog_items); the Quest Log
  shows `Quests.icon_slots` with checks (in a Reliquary) or a bag badge (carried).

## Architecture rules Claude must keep

- Lockstep: STEP 0.05 s, DELAY 3 steps, checksum every 100 steps, a mismatch resyncs by sending the save.
  Every rule must be deterministic: use `DMath` (fdlibm port, `scripts/core/dmath.gd`) for sin/cos/atan2/exp/pow,
  never the built-ins, inside `scripts/sim/`. Inside DMath call `DMath.atan` explicitly.
- Rules never branch on whether `on_dialog` is connected (the server has no UI). Pending questions to a player
  are saved (e.g. `trav_asking`).
- Commands go through `do()` → `apply()`; host-only commands are in `Lockstep.HOST_ONLY`.
- Each `new_world` randomises the rng, so compare two runs only from the same save.
- Per CLAUDE.md: sim never draws, views never change state, comment ports with `# web: <file> <function>`,
  `data/*.json` only via `tools/export_data.py`.
- Bump the version in `project.godot`, `export_presets.cfg` (file/product version) and add patch notes in
  `scripts/ui/patch_notes.gd` for each release; `tests/test_build.gd` checks they match.

## Tests

`godot --headless --path . --script res://tests/run_tests.gd` (about 17 minutes; run in the background).
Single file: `--script res://tests/<file>.gd`. Important ones: test_server, test_dmath, test_mp_events,
test_quests, test_build.

## What 0.19.3 and 0.19.4 changed (last session; 0.19.4: the Map Settings ranges, lakes and tree lines)

- Loading screen; Host locally / Host online; observers (Watch); Join/Watch/Set are buttons; Dungeon in any
  multiplayer game; empty games end and the server reopens a lobby; quests start on pickup with item icons.
- Starting positions (`Game.spawn_first/spawn_block/spawn_pick`, `SPAWN19`; tests that compare with the web game
  turn it off): first capital a random suitable province on/next to the coast; each capital blocks SPAWN_GAP (40)
  provinces (itself + 39 nearest, ties random); next nations random outside the blocks (players first, then
  computers). Spawn near players (3+ computers): each player takes the nearest allowed province to the first
  player's capital, and computers avoid shortest routes between players. Start position option removed.
- Automatic Wayfinders (0.19.5): `u.amode` "explore"/"survey"/"dig" (one, off by default; order `set_auto_mode`;
  any other player order naming the Wayfinder switches it off in `Game.apply`). `Game._auto_ring`: rings outward
  through enterable provinces, random pick in the first ring with a hit; idle → look again after AUTO_IDLE (10 s).
- Server (0.19.5): a player's `leave()` sends "bye"; if the last player left that way the game ends at once;
  `MpServer.fresh_lobby()` reopens the lobby in-process (no exit). Lobby shows the server address with Copy.
- Map Settings ranges: `<key>_min/_max` for pens, coves, trees, lakes; `Game.roll_map` draws the value from the
  seed in new_world; lakes 0-5 (`RealmGen` opts.lakes, -1 = the web game's random 1-3; saved in the map mode).
- Random race on the Nation page (`opts.random_race`, `StartScreen.resolved_nation()`): race, leader, name, emblem.
- Picture modes: `-- --mpwatch --shot=x.png`, `-- --loading --at=2 --shot=x.png`, `-- --mpmenu --menu --shot=x.png`,
  `-- --world=easy,easy --quests=log|newquest --shot=x.png` (render with xvfb-run and `--rendering-driver opengl3`).

## What 0.19.2 changed

- Late-game stall fixed: automatic scouting was pathing to every explored province (2.5 s per call with all tech
  + reveal); now a bounded nearest search with the identical result (64 ms worst step).
- Server: idle reset to a fresh lobby after 3 min, rejoin shows "End the game", template for several games.
- Lobby: fresh random island per lobby, start alone, "Host on this computer" rename.
- Earlier in 0.19.x: DMath determinism, travelers desync, Woodling tree houses with nation-coloured leaves,
  dig-site banners (click to centre), computer nations build a Reliquary and dig.

## Open items / ideas

- Playtest 0.19.2 with friends on the Droplet; watch `journalctl` for "out of step".
- "Orders react late": input delay is DELAY 3 steps (150 ms) plus ping. Could lower DELAY or show the order at
  once locally (prediction) — not started.
- Late-game performance: profile other per-step costs with many fully built provinces.
- Pixel art swap via `assets/art/**/manifest.json`; balance passes (project docs `claude/ai-*`).
- Merge `server` → `main` when happy.
