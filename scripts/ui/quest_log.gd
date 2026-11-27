class_name QuestLogWindow
extends Control
## The Quest Log (Godot only, docs/QUESTS_PLAN.md): every quest your nation has found, each with all its texts and
## how many of each relic you have. Open quests in gray, finished ones in green ("Complete"), lost ones in red
## ("Failed"). Click a quest to fold its texts away or open them. Under each quest, an icon for every relic it needs
## (0.19.3): dim until found, a green check once it is in a Reliquary, a bag once a scouting unit carries it. The
## button under Diplomacy, or L. Views only.

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


## A relic's icon (null when it has none, as for Jailbreak's convicts). Marked "square" for the pop-ups' layout.
static func item_tex(id: String) -> Texture2D:
	var path := "res://assets/art/icons/common/item_%s.png" % id
	if not ResourceLoader.exists(path):
		return null
	var t: Texture2D = load(path)
	if t != null and not t.has_meta("square"):
		t.set_meta("square", true)
	return t


## A row of the quest's relic icons with their marks (see the class note).
func _icon_row(qid: String) -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	for slot in Quests.icon_slots(game, game.ME, qid):
		var tex := item_tex(str(slot.item))
		var cell := Control.new()
		cell.custom_minimum_size = Vector2(44, 44)
		var nm := Quests.words(game, game.ME, Quests.item_name(str(slot.item))) if str(slot.item) != "_convict" else "A Convict"
		cell.tooltip_text = "%s: %s" % [nm, "in your Reliquary" if slot.got else "carried by one of your scouts, on its way to a Reliquary" if slot.carried else "not found yet"]
		cell.mouse_filter = Control.MOUSE_FILTER_PASS
		var got: bool = slot.got
		var carried: bool = slot.carried
		cell.draw.connect(func():
			var r := Rect2(Vector2.ZERO, cell.size)
			cell.draw_rect(r, Color("#efe3c4"))
			if tex != null:
				cell.draw_texture_rect(tex, r.grow(-3), false, Color.WHITE if got or carried else Color(1, 1, 1, 0.3))
			else:
				cell.draw_string(ThemeDB.fallback_font, Vector2(6, 30), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(UiKit.INK, 0.5 if not got else 1.0))
			cell.draw_rect(r, Color(UiKit.INK, 0.6), false, 1.5)
			if got:   # a green check over the icon
				var pts := PackedVector2Array([Vector2(10, 23), Vector2(19, 32), Vector2(35, 12)])
				cell.draw_polyline(pts, Color.WHITE, 7.0, true)
				cell.draw_polyline(pts, Color("#2f8a3a"), 4.0, true)
			elif carried:   # a little bag in the corner
				cell.draw_circle(Vector2(34, 34), 7.0, Color("#b07a2a"))
				cell.draw_arc(Vector2(34, 34), 7.0, 0, TAU, 16, UiKit.INK, 1.2, true)
				cell.draw_line(Vector2(31, 27), Vector2(37, 27), UiKit.INK, 1.5))
		row.add_child(cell)
	return row


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
	var k := str(ids) + str(folded) + str(ids.map(func(id): return [game.quest_log[id], Quests.icon_slots(game, game.ME, id)]))
	if k == key:
		return
	key = k
	UiKit.clear(win.body)
	if ids.is_empty():
		var l := UiKit.rich(16, 600)
		l.text = Quests.words(game, game.ME, "No quests yet. Your Wayfinders find relics by surveying and digging; picking one up starts its quest.")
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
		var mv := VBoxContainer.new()
		mv.add_theme_constant_override("separation", 6)
		mv.add_child(_icon_row(qid))   # (0.19.3: every relic it needs, checked once found)
		mv.add_child(body)
		m.add_child(mv)
		col.add_child(m)
