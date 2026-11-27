class_name DialogBox
extends Control
## A pop-up with a title, text and choice buttons (set pieces found, lost travelers, retrofit picks, inspecting an
## army). A choice that can't be taken is shown greyed, with its reason. web: the #spPop / #travPop / #findPop pop-ups.

var win: Dictionary
var text: RichTextLabel
var row: VBoxContainer
var pics: HBoxContainer
var on_pick: Callable


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	win = UiKit.window("", 640, func(): pick("close"))
	add_child(win.panel)
	win.panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	pics = HBoxContainer.new()
	pics.alignment = BoxContainer.ALIGNMENT_CENTER
	pics.add_theme_constant_override("separation", 16)
	win.body.add_child(pics)
	text = UiKit.rich(19, 600)
	win.body.add_child(text)
	row = VBoxContainer.new()   # the choices, one above the other, centered
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	win.body.add_child(row)
	hide()


## choices: [{id, label, why}]; `f(id)` is called with the pick ("close" when closed without one). A label's
## bracketed end ("Rob them (+120 gold)") goes on its own line, without the brackets. images: shown above the text.
func ask(title: String, body: String, choices: Array, f: Callable, images := []) -> void:
	win.title.text = title
	text.text = body
	on_pick = f
	UiKit.clear(pics)
	for tex in images:
		if tex is Texture2D:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.custom_minimum_size = Vector2(80, 80) if tex.has_meta("square") else Vector2(66, 44) if pics.get_child_count() == 0 else Vector2(104, 104)   # (0.19: the flag at half size; 0.19.3: a relic's icon)
			tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			pics.add_child(tr)
	pics.visible = pics.get_child_count() > 0
	UiKit.clear(row)
	var rx := RegEx.create_from_string("^(.*?)\\s*\\((.*)\\)\\s*$")
	for c in choices:
		var label := str(c.label)
		var m := rx.search(label)
		if m != null and m.get_string(1) != "":
			label = "%s\n%s" % [m.get_string(1), m.get_string(2)]
		var b := UiKit.button(label, 18, pick.bind(c.id))
		b.custom_minimum_size = Vector2(340, 0)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.disabled = c.get("why") != null
		if c.get("why") != null:
			b.tooltip_text = str(c.why)
			b.text += "\n%s" % c.why
		row.add_child(b)
	show()
	UiKit.center.call_deferred(win.panel)


func pick(id: String) -> void:
	hide()
	var f := on_pick
	on_pick = Callable()
	if f.is_valid():
		f.call("leave" if id == "close" else id)
