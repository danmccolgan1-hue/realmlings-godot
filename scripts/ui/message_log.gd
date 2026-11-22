class_name MessageLog
extends PanelContainer
## The messages box, bottom left beside the minimap: every message the game gives you (surveys done, orders taken,
## buildings started and finished, warnings...), newest at the bottom. It keeps the last 48 and shows 8 at a time,
## with a scroll bar. See-through, so the map shows behind it. Views only.

const KEEP := 48
const SHOWN := 8
const INK := Color("#1d1a22")
const WARN := Color("#9a1f1a")

var scroll: ScrollContainer
var list: VBoxContainer
var hint: Label
var _follow := true


func _init() -> void:
	var st := StyleBoxFlat.new()
	st.bg_color = Color("#faf1dc", 0.55)
	st.border_color = Color(INK, 0.45)
	st.set_border_width_all(1)
	st.set_corner_radius_all(4)
	st.set_content_margin_all(6)
	add_theme_stylebox_override("panel", st)
	mouse_filter = Control.MOUSE_FILTER_STOP
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 1)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	hint = Label.new()
	hint.text = "Messages"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(INK, 0.45))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_child(hint)
	# while you read older messages, new ones don't pull the box back to the bottom
	scroll.get_v_scroll_bar().value_changed.connect(func(_v):
		var sb := scroll.get_v_scroll_bar()
		_follow = sb.value >= sb.max_value - sb.page - 4)


## A new message (warn: something went wrong, in red).
func add(text: String, warn := false, clock := "") -> void:
	var l := Label.new()
	l.text = ("%s  %s" % [clock, text]) if clock != "" else text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", WARN if warn else INK)
	l.add_theme_color_override("font_outline_color", Color("#faf1dc", 0.8))
	l.add_theme_constant_override("outline_size", 3)
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	if hint != null:
		hint.queue_free()
		hint = null
	list.add_child(l)
	while list.get_child_count() > KEEP:
		var old := list.get_child(0)
		list.remove_child(old)
		old.queue_free()
	if _follow:
		_to_bottom.call_deferred()


func clear() -> void:
	for c in list.get_children():
		c.queue_free()
	hint = Label.new()
	hint.text = "Messages"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(INK, 0.45))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_child(hint)
	_follow = true


func _to_bottom() -> void:
	await get_tree().process_frame
	var sb := scroll.get_v_scroll_bar()
	scroll.scroll_vertical = int(sb.max_value)


## Lay it out: `at` its top-left, `sz` its size (the minimap's height, twice its width).
func place(at: Vector2, sz: Vector2) -> void:
	position = at
	size = sz
	custom_minimum_size = sz
	scroll.custom_minimum_size = sz - Vector2(12, 12)
