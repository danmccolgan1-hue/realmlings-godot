class_name MpPanel
extends PanelContainer
## Multiplayer, in the game: who is playing (flag, name, nation, connection speed; away or played by the computer)
## and what the game is waiting for. No chat: players talk through Diplomacy. Views only.

const INK := Color("#1d1a22")
const MUTED := Color("#5a6475")

var lock: Lockstep
var rows: VBoxContainer
var wait_label: Label
var _sig := ""
var heads := []
var _t := 0.0


func _init() -> void:
	add_theme_stylebox_override("panel", TopBar.paper(2, 8))
	custom_minimum_size = Vector2(300, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	add_child(v)
	var head := Label.new()
	head.text = "Players"
	head.add_theme_font_size_override("font_size", 17)
	head.add_theme_color_override("font_color", INK)
	v.add_child(head)
	UiKit.draggable(self, head, "players")   # 0.19: drag it by its title
	heads = [head]
	rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	v.add_child(rows)
	wait_label = Label.new()
	wait_label.add_theme_font_size_override("font_size", 14)
	wait_label.add_theme_color_override("font_color", Color("#a0461e"))
	wait_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wait_label.custom_minimum_size = Vector2(280, 0)
	wait_label.visible = false
	v.add_child(wait_label)
	# (no chat in the game: players talk through Diplomacy's messages and proclamations)


func setup(lk: Lockstep) -> void:
	lock = lk
	lk.waiting.connect(func(t2):
		if is_instance_valid(wait_label):
			wait_label.text = t2
			wait_label.visible = t2 != "")
	_sig = ""
	show()


func _process(dt: float) -> void:
	if lock == null or lock.game == null:
		return
	# beside the outliner, under the clock (until the player drags it elsewhere)
	if not UiKit.is_placed("players"):
		position = Vector2(get_viewport_rect().size.x - 300 - size.x, 76)
	# 0.19: Settings can hide it; what the game is waiting for still shows
	var on: bool = Settings.view.get("players", true)
	rows.visible = on
	for h in heads:
		h.visible = on
	visible = on or wait_label.visible
	if not visible:
		return
	_t -= dt
	if _t > 0:
		return
	_t = 0.5
	var g := lock.game
	var list := []
	for o in g.seat_names:
		var state := "computer" if g.nations.has(o) else "away" if lock.gone.has(o) else ""
		var ping := ""
		for pid in lock.net.players:
			if str(lock.net.players[pid].name) == str(g.seat_names[o]) and pid != 1:
				ping = "%d ms" % int(lock.net.players[pid].get("ping", 0))
		if not g.nations.has(o) and not g.seats.has(o):
			state = "fallen"
		elif g.seats.has(o) and g.seats[o].fallen:
			state = "fallen"
		list.append([o, str(g.seat_names[o]), g.player_info(o).name, state, ping])
	var sig := str(list)
	if sig == _sig:
		return
	_sig = sig
	for c in rows.get_children():
		c.queue_free()
	for r in list:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		var tex = Art.nation_flag(g, r[0])
		if tex is Texture2D:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.custom_minimum_size = Vector2(28, 20)
			h.add_child(tr)
		var l := Label.new()
		l.text = "%s%s · %s" % [r[1], " (you)" if r[0] == lock.me else "", r[2]]
		l.add_theme_font_size_override("font_size", 14)
		l.add_theme_color_override("font_color", INK)
		h.add_child(l)
		var s := Label.new()
		s.text = r[3] if r[3] != "" else r[4]
		s.add_theme_font_size_override("font_size", 13)
		s.add_theme_color_override("font_color", Color("#a0461e") if r[3] != "" else MUTED)
		h.add_child(s)
		rows.add_child(h)
