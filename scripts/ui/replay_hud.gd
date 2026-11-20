class_name ReplayHud
extends CanvasLayer
## Watching a recording: play / pause, speed, a timeline to scrub, every nation's numbers at the playhead, a chart of
## their land over the game, and what happened lately. Views only: it moves the Replay's playhead.

const SPEEDS := [1, 4, 16, 64]

var replay: Replay
var main
var playing := true
var speed := 16
var title: Label
var clock: Label
var play_btn: Button
var speed_btns := []
var slider: HSlider
var nat_box: VBoxContainer
var chart: Control
var feed: RichTextLabel
var minimap: Minimap
var key := ""
var _sliding := false


func _ready() -> void:
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.add_theme_stylebox_override("panel", UiKit.box(Color(UiKit.DARK, 0.92), 0))
	add_child(top)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)
	top.add_child(bar)
	title = UiKit.label(22, UiKit.GOLD)
	bar.add_child(title)
	clock = UiKit.label(22)
	clock.custom_minimum_size = Vector2(170, 0)
	bar.add_child(clock)
	bar.add_child(_btn("⏮", "Back to the start", func():
		replay.seek(replay.t0)))
	play_btn = _btn("⏸ Pause", "Play or pause [Space]", func(): toggle_play())
	bar.add_child(play_btn)
	for s in SPEEDS:
		var b := _btn("%d×" % s, "Play at %d times the game's speed" % s, func(): set_speed(s))
		b.toggle_mode = true
		speed_btns.append(b)
		bar.add_child(b)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	bar.add_child(_btn("Exit replay [Esc]", "Back to the start screen", func(): main.exit_replay()))
	# the timeline
	var bottom := PanelContainer.new()
	bottom.add_theme_stylebox_override("panel", UiKit.box(Color(UiKit.DARK, 0.92), 10))
	add_child(bottom)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE, 20)
	bottom.offset_right = -560
	slider = HSlider.new()
	slider.custom_minimum_size = Vector2(0, 28)
	slider.step = 1.0
	slider.tooltip_text = "Drag to jump to any moment of the game"
	slider.drag_started.connect(func(): _sliding = true)
	slider.drag_ended.connect(func(_c): _sliding = false)
	slider.value_changed.connect(func(v):
		if _sliding or absf(v - replay.t) > 1.5:
			replay.seek(v))
	bottom.add_child(slider)
	# the nations, their land over time, and the news
	var side := PanelContainer.new()
	side.add_theme_stylebox_override("panel", UiKit.box(Color(UiKit.PAPER, 0.96), 12, 3))
	add_child(side)
	side.anchor_left = 1.0
	side.anchor_right = 1.0
	side.anchor_top = 0.0
	side.anchor_bottom = 1.0
	side.offset_left = -540
	side.offset_right = -20
	side.offset_top = 70
	side.offset_bottom = -20
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	side.add_child(col)
	var h1 := UiKit.ink(22)
	h1.text = "Nations"
	col.add_child(h1)
	nat_box = VBoxContainer.new()
	col.add_child(nat_box)
	var h2 := UiKit.ink(20)
	h2.text = "Provinces held"
	col.add_child(h2)
	chart = Control.new()
	chart.custom_minimum_size = Vector2(480, 170)
	chart.draw.connect(_draw_chart)
	chart.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			replay.seek(lerpf(replay.t0, replay.t1, clampf(ev.position.x / chart.size.x, 0, 1))))
	chart.tooltip_text = "Click to jump to that moment"
	col.add_child(chart)
	var h3 := UiKit.ink(20)
	h3.text = "Lately"
	col.add_child(h3)
	feed = UiKit.rich(16, 480)
	col.add_child(feed)
	minimap = Minimap.new()
	add_child(minimap)
	minimap.position = Vector2(20, 70)
	hide()


func _btn(text: String, tip: String, f: Callable) -> Button:
	var b := UiKit.button(text, 18, f)
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	return b


func setup(r: Replay, m, map: MapView, cam: Camera2D) -> void:
	replay = r
	main = m
	playing = true
	set_speed(16)
	var h: Dictionary = r.rec.header
	title.text = "Replay · %s · %d nations · %s" % [h.seed, h.nations.size(), str(r.rec.get("made", "")).replace("T", " ").left(16)]
	slider.min_value = r.t0
	slider.max_value = r.t1
	minimap.setup(r.g, map, cam)
	key = ""
	show()


func toggle_play() -> void:
	if replay.t >= replay.t1:
		replay.seek(replay.t0)
	playing = not playing


func set_speed(s: int) -> void:
	speed = s
	for i in SPEEDS.size():
		speed_btns[i].button_pressed = SPEEDS[i] == s


func step(dt: float) -> void:
	if replay == null:
		return
	if playing and not _sliding:
		replay.seek(replay.t + dt * speed)
		if replay.t >= replay.t1:
			playing = false
	play_btn.text = "⏸ Pause" if playing else "▶ Play"
	clock.text = "%s / %s" % [Game.fmt_time(replay.t), Game.fmt_time(replay.t1)]
	if not _sliding:
		slider.set_value_no_signal(replay.t)
	var k := str(int(replay.t / 5))
	if k == key:
		return
	key = k
	_fill_nations()
	_fill_feed()
	chart.queue_redraw()
	minimap.queue_redraw()


func _fill_nations() -> void:
	UiKit.clear(nat_box)
	var st := replay.stats_at()
	for n in replay.rec.header.nations:
		var s = st.get(int(n.id))
		var row := HBoxContainer.new()
		var sw := ColorRect.new()
		sw.color = Color(n.color)
		sw.custom_minimum_size = Vector2(18, 18)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(sw)
		var l := UiKit.rich(16, 460)
		var name := "%s — %s" % [n.name, "you" if str(n.diff) == "player" else str(n.diff).capitalize()]
		if s == null:
			l.text = "[b]%s[/b]" % name
		else:
			l.text = "[b]%s[/b]\n%d provinces (%d forts) · power %d · %d soldiers · +%d/+%d/+%d · %d techs%s" % [name, s.provs, s.forts, s.power, s.soldiers,
				s.inc.g, s.inc.w, s.inc.f, int(s.techs.gov + s.techs.mil + s.techs.mag), (" · at war" if int(s.get("wars", 0)) else "")]
			if int(s.provs) == 0:
				l.text = "[b][s]%s[/s][/b] — fallen" % name
		row.add_child(l)
		nat_box.add_child(row)


func _fill_feed() -> void:
	var lines := []
	for e in replay.events_until(9):
		lines.append("[color=#6b5a44]%s[/color]  %s" % [Game.fmt_time(float(e.t)), replay.event_text(e)])
	lines.reverse()
	feed.text = "\n".join(lines) if not lines.is_empty() else "[i]Nothing yet.[/i]"


func _draw_chart() -> void:
	if replay == null:
		return
	var sz := chart.size
	chart.draw_rect(Rect2(Vector2.ZERO, sz), Color("#fffaf0"))
	chart.draw_rect(Rect2(Vector2.ZERO, sz), UiKit.INK, false, 2.0)
	var span := maxf(1.0, replay.t1 - replay.t0)
	var top := 1
	var lines := {}
	for s in replay.rec.snap:
		top = maxi(top, int(s.provs))
		var o := int(s.o)
		if not lines.has(o):
			lines[o] = PackedVector2Array()
		lines[o].append(Vector2(float(s.t), float(s.provs)))
	var to_px := func(v: Vector2) -> Vector2:
		return Vector2((v.x - replay.t0) / span * (sz.x - 8) + 4, sz.y - 6 - v.y / top * (sz.y - 14))
	for n in replay.rec.header.nations:
		var o := int(n.id)
		if not lines.has(o) or lines[o].size() < 2:
			continue
		var pts := PackedVector2Array()
		for v in lines[o]:
			pts.append(to_px.call(v))
		chart.draw_polyline(pts, Color(n.color), 3.0 if o == Game.ME else 2.0, true)
	var x: float = (replay.t - replay.t0) / span * (sz.x - 8) + 4
	chart.draw_line(Vector2(x, 2), Vector2(x, sz.y - 2), Color(UiKit.INK, 0.7), 2.0)
	chart.draw_string(ThemeDB.fallback_font, Vector2(6, 16), str(top), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(UiKit.INK, 0.6))
