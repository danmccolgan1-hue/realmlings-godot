class_name LoadingScreen
extends Control
## The screen while a game is being built (0.19.3): every other menu goes away, and a line tells what the world is
## up to (shaping, sculpting mountains, growing trees, adding secrets, populating with enemies, one for each fifth),
## with the percentage under it. The rules report how far they are (Game.build_pct, from the building thread); the
## number creeps on between those reports so it never sits still, and never runs past the next one. Views only.

const LINES := ["...shaping your world...", "...sculpting mountains...", "...growing trees...", "...adding secrets...", "...populating with enemies..."]
const BG := Color("#2f3b55")   # (the boot splash's color)
const GOLD := Color("#f2b632")

var line: Label
var pct_l: Label
var bar: ProgressBar
var shown := 0.0     # the percentage on the screen (0-100)
var _at := 0         # (the clock when it last moved: real time, even when frames are slow while building)
const CREEP := 15.0  # percent a second between the rules' reports


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # (nothing under it can be clicked)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	v.custom_minimum_size = Vector2(720, 0)
	c.add_child(v)
	line = Label.new()
	line.text = LINES[0]
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_theme_font_size_override("font_size", 44)
	line.add_theme_color_override("font_color", GOLD)
	line.add_theme_color_override("font_outline_color", Color("#7a4a12"))
	line.add_theme_constant_override("outline_size", 8)
	Fonts.title(line)
	v.add_child(line)
	bar = ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(520, 18)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = Color(0, 0, 0, 0.35)
	bg_sb.set_corner_radius_all(9)
	bg_sb.set_border_width_all(2)
	bg_sb.border_color = Color("#1d1a22")
	bar.add_theme_stylebox_override("background", bg_sb)
	var fill := StyleBoxFlat.new()
	fill.bg_color = GOLD
	fill.set_corner_radius_all(9)
	bar.add_theme_stylebox_override("fill", fill)
	v.add_child(bar)
	pct_l = Label.new()
	pct_l.text = "0%"
	pct_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pct_l.add_theme_font_size_override("font_size", 28)
	pct_l.add_theme_color_override("font_color", Color("#faf1dc"))
	v.add_child(pct_l)
	hide()


## Show it from 0%.
func open() -> void:
	Game.build_pct = 0.0
	shown = 0.0
	_at = Time.get_ticks_msec()
	_show_pct()
	show()
	move_to_front()


func close() -> void:
	hide()


## The line for a percentage: a new one every 20%.
static func line_for(pct: float) -> String:
	return LINES[clampi(int(pct / 20.0), 0, LINES.size() - 1)]


func _process(_dt: float) -> void:
	if not visible:
		return
	var now := Time.get_ticks_msec()
	var dt := minf((now - _at) / 1000.0, 1.0)
	_at = now
	var reached := clampf(Game.build_pct * 100.0, 0.0, 100.0)
	var next := 100.0
	for stop in Game.BUILD_STOPS:
		if stop * 100.0 > reached + 0.01:
			next = stop * 100.0
			break
	if shown < reached:
		shown = reached
	# creep on toward the next report (15% a second), never quite reaching it before the rules do
	shown = minf(shown + CREEP * dt, maxf(shown, next - 1.0))
	_show_pct()


func _show_pct() -> void:
	var p := floorf(shown)
	pct_l.text = "%d%%" % int(p)
	bar.value = p
	line.text = line_for(p)
