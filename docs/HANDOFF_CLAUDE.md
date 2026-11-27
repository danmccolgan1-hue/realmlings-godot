# Handoff for a new Claude conversation (2026-11-27, version 0.19.2)

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
- Autosave; after a restart the lobby offers to carry the saved game on. If everyone leaves a running game, the
  server waits 3 min, autosaves and restarts to a fresh lobby. The menu's "End the game for everyone" stops it.
- Debug (only when the lobby allows it): reveal and +2000 resources go to all humans; "Every technology" asks
  for the Magic school.
- "Host on this computer" in the menu = a PC hosts, not the Droplet. For the Droplet use "Join by address".
- The Dungeon only appears with 2+ human players (my rule), for every race.

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

## What 0.19.2 changed (last session)

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
