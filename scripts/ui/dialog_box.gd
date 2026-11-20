class_name DialogBox
extends Control
## A pop-up with a title, text and choice buttons (set pieces found, lost travelers, retrofit picks, inspecting an
## army). A choice that can't be taken is shown greyed, with its reason. web: the #spPop / #travPop / #findPop pop-ups.

var win: Dictionary
var text: RichTextLabel
var row: HFlowContainer
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
	text = UiKit.rich(19, 600)
	win.body.add_child(text)
	row = HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	win.body.add_child(row)
	hide()


## choices: [{id, label, why}]; `f(id)` is called with the pick ("close" when closed without one).
func ask(title: String, body: String, choices: Array, f: Callable) -> void:
	win.title.text = title
	text.text = body
	on_pick = f
	UiKit.clear(row)
	for c in choices:
		var b := UiKit.button(c.label, 18, pick.bind(c.id))
		b.disabled = c.get("why") != null
		if c.get("why") != null:
			b.tooltip_text = str(c.why)
			b.text += "\n(%s)" % c.why
		row.add_child(b)
	show()
	UiKit.center.call_deferred(win.panel)


func pick(id: String) -> void:
	hide()
	var f := on_pick
	on_pick = Callable()
	if f.is_valid():
		f.call("leave" if id == "close" else id)
