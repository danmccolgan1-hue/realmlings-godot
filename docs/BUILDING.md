# Building Realmlings for Windows

The project is ready to export: `export_presets.cfg` has a **Windows Desktop** preset with the game's icon
(`assets/icon/realmlings.ico`), name, version and the folders a player doesn't need left out (`reference/`,
`tools/`, `tests/`, `docs/`). Exporting needs Godot's export templates, which are installed once per Godot version.

## Once: install Godot 4.7.2 and its export templates

1. Download **Godot 4.7.2 (Standard, not .NET)** for Windows from godotengine.org and unzip it anywhere.
2. Open Godot, then **Editor → Manage Export Templates…**, choose **Download and Install** (about 1 GB). Wait for it to
   finish.

## Every build

1. Get the latest code: `git pull` in your `realmlings-godot` folder (or download the repository as a zip).
2. In Godot's Project Manager, **Import** the folder's `project.godot` and open it. The first open imports every
   image; give it a minute.
3. **Project → Export…**, pick **Windows Desktop**, then **Export Project…**. Keep the file name
   `build/Realmlings.exe` (make the `build` folder if Godot asks). Untick **Export With Debug** for a build to share.
4. You get `Realmlings.exe` (the game, with everything packed inside) and, with debug on, `Realmlings.console.exe`
   (the same game with a console window that shows errors — handy when something goes wrong).

Double-click `Realmlings.exe` to play. Nothing else needs installing.

## Where the game keeps its files on Windows

`%APPDATA%\Godot\app_userdata\Realmlings\`

- `autosave.json`, `quicksave.json`: saved games. Saves carry a version, so a newer build loads older saves; a save
  from a newer build is refused with a message instead of breaking.
- `settings.json`: the Settings window's choices.
- `recordings\`: recorded games (Settings → Record games), listed on the start screen under **Recorded games**.

## When something goes wrong

- *"No export template found"*: step 2 of "Once" didn't finish. Open Manage Export Templates again.
- The exe shows Godot's icon instead of the crown: in **Editor Settings → Export → Windows**, make sure nothing points
  at an old `rcedit`; Godot 4.7 sets the icon by itself.
- To see errors, run `Realmlings.console.exe` (a debug export) and send what the console says.

## Checking a build here (for Claude)

`godot --headless --path . --script res://tests/run_tests.gd` runs every test, `test_build.gd` included (the save
versions and the export preset). Export templates aren't installed in Claude's workspace, so the `.exe` itself is
built on your PC.
