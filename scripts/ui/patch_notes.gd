class_name PatchNotes
extends Control
## Patch Notes on the start screen: one collapsible section per version, newest first, each with its date.
## The Godot port's own notes first, then the web game's (PATCH_NOTES, data/web/v106.json) that this port follows.
## web: v106.js renderPatchNotes

const PORT_NOTES := [
	{"v": "Godot 0.9", "date": "November 21, 2026", "items": [
		["Swamplings", "Play as the Swamplings: start in a swamp with three Axe Berserkers, fight 20% harder and move 20% faster there, and tax your swamp settlements. Swampwrights, Swampstriders and Warlocks; Ogre Caves (mountain borders), Thug Dens with Thugs who earn gold, Supply Caches and Hot Springs; no Granaries, Storehouses or roads. Mushroom Farming from the start, Spiked Walls, the Fireball."],
		["Swampling war and magic", "Axes, Staghide, Wyvern-Scaled and Dragonbone armor, dual wielding (the off hand hits for half), and Ogres in five breeds. Pyromancy: Fiery Weapons, Scouting Pyres, fire traps, Path of Fire and Sacred Pyres."],
		["Woodlings", "Play as the Woodlings: start in a forest, 20% tougher and 10% quicker there; Scouts slip through borders of trees. Architects, Druids, Groves, Bazaars with Community, Shrines and the Hall of Champions; no shields or roads. Protectors with thrusting swords and a two-handed grip, Champions, Spiritweave, Mithril and Ornate armor."],
		["Woodling magic", "The School of the Elements: Rock Armor, Whispering Rocks, Town Portal and the Forest Spirit."],
		["New Game", "Choose your race; the leaders follow it, with all eight Swampling and eight Woodling leaders and their starts and bonuses. Each opponent can be a Realmling, Swampling, Woodling or a random race, with their own names, designs and schools."],
		["Look", "Swampling mud huts and Woodling tree houses, their buildings, soldiers, workers, townsfolk, icons and leader portraits; the Armory shows your race's gear."]]},
	{"v": "Godot 0.8", "date": "November 21, 2026", "items": [
		["Orders", "Drag a box to select several units, Shift-click to add or remove one. Right-click sends them all, spread out around the spot; hold Shift to queue orders. Ctrl+right-click opens the survey and build menu (or turn on Quick queue in Settings). Drag with the right mouse to move the map."],
		["On the map", "A golden mark where you sent units, numbered markers for queued surveys and moves, the survey's loop and stakes, rally points, and the provinces of your selected units."],
		["Battles and spells", "Battles show the melee, each side's strength, the blows and the fallen. Forts with Arrowslits now shoot invaders. Casting circles, Shockwaves, Earthquakes, forest paths and tunnels are drawn."],
		["Animation", "Units pop in, breathe, hop as they walk and throw sparks as they build; buildings smoke, wave their flags and turn their wheels, and the Mage Tower's crystals circle."],
		["Sound", "Music and every sound effect of the web game, with their switches and volumes; M turns the music on or off."]]},
	{"v": "Godot 0.7", "date": "November 21, 2026", "items": [
		["Armory", "Laid out as the web game’s: your designs with portraits and stats, a spinning preview, stat bars, and the gear as picture buttons under Weapons, Armor and Horses tabs. Equip every Mage with staves, wands and shields, and retrofit your armies from the Armory."],
		["Magic", "Choose your school of magic when your first Mage Tower stands. Abandon Magic School now works: the school and its spells are forgotten and you choose again."],
		["Country Breakdown", "Click your flag and name, top left: your leader, land, where your resources come from and go, your artifacts and your wars."],
		["Diplomacy", "One section per nation you have met, with its leader’s portrait and likes, what you know of it, the agreements between you, the war and its peace terms, and the diplomatic actions as picture buttons. Hover a nation to see its opinion of you."]]},
	{"v": "Godot 0.6", "date": "November 21, 2026", "items": [
		["Start screen", "The web game’s title card: a parade of your folk, Continue, New Game, Tutorial, Multiplayer, Patch Notes, Load a save file, Recorded games, Settings and How to play, over a drifting island."],
		["New Game", "Choose your seed and nation name (with dice), leader from portrait cards, color, flag, start position, the island’s shape with peninsulas, coves and trees, and each of the seven opponent slots. Your choices are remembered."],
		["Saves", "Export a game to a file and load it again, from the menu and the in-game menu."],
		["Renaming", "Rename provinces and your units with the ✎ buttons."],
		["Main screen", "The icon command card, the outliner’s tabs, the province menu with its plots, resource badges and names on the map, the minimap’s toggles, crops on Farms, and the hidden landmarks: Death Mountain, the Oasis, the Heart of the Forest, set pieces, ruins, treasure and travelers."]]},
	{"v": "Godot 0.5", "date": "November 20, 2026", "items": [
		["Flags", "Notification flags hang above the command card: idle research, Army Exhaustion, open plots, upgrades, quakes, truces ending, warscore at 100, white peace coming, spells ready, requests waiting, war news and the province limit. Left-click deals with one, right-click dismisses it."],
		["Tooltips", "Every command, training and building button explains what it does, what it costs and why it can’t be used yet. The resource bar shows what comes in and what upkeep takes."],
		["Settings", "A Settings window: interface size, full screen, Calm map, Record games, and debug switches. Settings are remembered."],
		["Recordings", "Turn on Record games to keep a recording of each full-map game, then watch it back from the start screen: the map as it changed, with every nation’s growth."],
		["Windows", "A Windows build, with its own icon and version number. Saved games carry a version so newer builds still load them."]]},
	{"v": "Godot 0.4", "date": "November 20, 2026", "items": [
		["Diplomacy", "Flirt, gifts, alliances asked and offered, military access, Trade Networks, spies and bribes, each with the reason it isn’t possible yet. Requests from other nations wait in a box with a timer. Gift vaults and war news."]]},
	{"v": "Godot 0.3", "date": "November 20, 2026", "items": [
		["Sieges", "Armies batter walls down; forts and capitals rebuild them."],
		["Magic", "Shockwave and Earthquake, for you and the computer nations."],
		["Bosses", "Boss fights and the nine artifacts, Winged Slippers included. Intact Ruins give a technology."]]},
	{"v": "Godot 0.2", "date": "November 20, 2026", "items": [
		["Full maps", "Full-size worlds with up to six computer nations that build, research, train and go to war."],
		["Wars", "Wars, warscore, peace terms, truces, alliances, opinion and Proclaim Enemy, in a Diplomacy window (Y)."]]},
	{"v": "Godot 0.1", "date": "November 19–20, 2026", "items": [
		["The Practice island", "The web game’s map generator, economy, building, surveying, research, training, the Armory, magic, battles, roads, walls, development, saving and the Basic Tutorial."]]},
]

var win: Dictionary
var box: VBoxContainer
var open_v := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	win = UiKit.window("Patch Notes", 760, func(): close())
	add_child(win.panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(740, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	win.body.add_child(scroll)
	box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	open_v[PORT_NOTES[0].v] = true
	win.panel.hide()


func all_notes() -> Array:
	var out := PORT_NOTES.duplicate()
	for P in GameData.c("PATCH_NOTES"):
		out.append({"v": "Web game " + str(P.v), "date": P.date, "items": P.items})
	return out


func open() -> void:
	_fill()
	win.panel.show()
	UiKit.center.call_deferred(win.panel)


func close() -> void:
	win.panel.hide()


func _fill() -> void:
	UiKit.clear(box)
	for P in all_notes():
		var on: bool = open_v.has(P.v)
		var head := UiKit.button("%s %s   ·   %s" % ["▾" if on else "▸", P.v, P.date], 19)
		head.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var v: String = P.v
		head.pressed.connect(func():
			if open_v.has(v):
				open_v.erase(v)
			else:
				open_v[v] = true
			_fill())
		box.add_child(head)
		if on:
			var r := UiKit.rich(17, 700)
			r.text = "\n".join(P.items.map(func(it): return "• [b]%s.[/b] %s" % [it[0], it[1]]))
			box.add_child(r)
