class_name QuestLogWindow
extends Control
## The Quest Log (Godot only, docs/QUESTS_PLAN.md): every quest your nation has found, each with all its texts and
## how many of each relic you have. Open quests in gray, finished ones in green ("Complete"), lost ones in red
## ("Failed"). Click a quest to fold its texts away or open them. The button under Diplomacy, or L. Views only.

const MUTED := Color("#6b6257")
const ACTIVE := Color("#6b6b70")
const DONE := Color("#2f8a3a")
const FAILED := Color("#b3261e")
const ORDER := {"active": 0, "done": 1, "failed": 2}

var game: Game
var hud
var win: Dictionary
var key := ""
var folded := {}   # quest id -> true when its texts are folded away


func setup(g: Game, h) -> void:
	game = g
	hud = h
	key = ""
	if not win.is_empty():
		hide()
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	win = UiKit.window("Quest Log", 640, func(): hide())
	add_child(win.panel)
	hide()


func toggle() -> void:
	if visible:
		hide()
	else:
		open()


func open() -> void:
	show()
	key = ""
	_refresh()
	UiKit.center.call_deferred(win.panel)


func _process(_dt: float) -> void:
	if visible and game != null:
		_refresh()


## The quests in the order the log shows them: open ones first, then finished, then failed; oldest first in each.
static func entries(g: Game) -> Array:
	var L: Dictionary = g.quest_log
	var ids: Array = L.keys()
	ids.sort_custom(func(a, b):
		var sa: int = ORDER.get(L[a].state, 3)
		var sb: int = ORDER.get(L[b].state, 3)
		return sa < sb if sa != sb else float(L[a].t0) < float(L[b].t0))
	return ids


## Everything the log says about one quest (its texts in your race's words, and the relic counts).
static func body_text(g: Game, qid: String) -> String:
	var q: Dictionary = Quests.quest(qid)
	var st: Dictionary = g.quest_log[qid]
	var o: int = g.ME
	var parts := [str(q.text)]
	if q.has("part2") and int(st.get("part", 1)) == 2:
		var site := int(st.get("site", -1))
		parts.append(str(q.part2.text) + (("\nThe dig site is in %s." % g.prov_name(site)) if site >= 0 and st.state == "active" else ""))
	if st.state == "active":
		parts.append(Quests.goal_text(g, o, qid))
	elif st.state == "done":
		parts.append(str(q.done_text))
		parts.append(str(q.reward_text))
	else:
		parts.append("The %s finished it first." % g.player_info(int(st.get("by", 0))).name if st.get("by") != null else "Failed.")
	return Quests.words(g, o, "\n\n".join(parts))


func _refresh() -> void:
	var ids := entries(game)
	var k := str(ids) + str(folded) + str(ids.map(func(id): return [game.quest_log[id], Quests.progress(game, game.ME, id)]))
	if k == key:
		return
	key = k
	UiKit.clear(win.body)
	if ids.is_empty():
		var l := UiKit.rich(16, 600)
		l.text = Quests.words(game, game.ME, "No quests yet. Your Wayfinders find relics by surveying and digging; a relic in one of your Reliquaries starts its quest.")
		win.body.add_child(l)
		return
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, mini(560, 60 + ids.size() * 150))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	win.body.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	scroll.add_child(col)
	for qid in ids:
		var st: Dictionary = game.quest_log[qid]
		var q: Dictionary = Quests.quest(qid)
		var head := Button.new()
		head.flat = true
		head.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var mark := str(Quests.LOG_TEXT.get(st.state, ""))
		head.text = ("▸ " if folded.get(qid, false) else "▾ ") + Quests.words(game, game.ME, str(q.title)) + (("   " + mark) if mark != "" else "")
		head.add_theme_font_size_override("font_size", 18)
		var colr: Color = DONE if st.state == "done" else FAILED if st.state == "failed" else ACTIVE
		for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			head.add_theme_color_override(s, colr)
		var id: String = qid
		head.pressed.connect(func():
			folded[id] = not folded.get(id, false)
			key = "")
		col.add_child(head)
		if folded.get(qid, false):
			continue
		var body := UiKit.rich(15, 580)
		body.text = body_text(game, qid)
		body.add_theme_color_override("default_color", UiKit.INK if st.state == "active" else colr.darkened(0.2))
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_left", 22)
		m.add_child(body)
		col.add_child(m)
