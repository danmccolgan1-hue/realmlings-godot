class_name PatchNotes
extends Control
## Patch Notes on the start screen: one collapsible section per version, newest first, each with its date.
## The Godot port's own notes first, then the web game's (PATCH_NOTES, data/web/v106.json) that this port follows.
## web: v106.js renderPatchNotes

const PORT_NOTES := [
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
