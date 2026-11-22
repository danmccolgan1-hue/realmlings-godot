class_name RenameBox
extends PanelContainer
## Rename a province or one of your units (the ✎ buttons). Names are cleaned and kept to 28 letters; a province
## can go back to its original name. web: v78.js openRename, doRename, cleanName

var game: Game
var target := ""   # "prov:<p>" or "unit:<id>"
var edit: LineEdit
var reset_btn: Button
var title: Label


func _init() -> void:
	add_theme_stylebox_override("panel", TopBar.paper(4, 2))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	title = TopBar.ink_label(18)
	v.add_child(title)
	edit = LineEdit.new()
	edit.max_length = 28
	edit.custom_minimum_size = Vector2(300, 0)
	edit.text_submitted.connect(func(_t): _done(false))
	v.add_child(edit)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_END
	h.add_theme_constant_override("separation", 6)
	reset_btn = UiKit.button("Original", 16, func(): _done(true))
	reset_btn.tooltip_text = "Go back to the original name"
	h.add_child(reset_btn)
	h.add_child(UiKit.button("Cancel", 16, func(): hide()))
	h.add_child(UiKit.button("Rename", 16, func(): _done(false)))
	v.add_child(h)
	hide()


static func clean(s: String) -> String:
	var out := s.replace("<", "").replace(">", "").replace("&", "").replace("\"", "")
	while out.contains("  "):
		out = out.replace("  ", " ")
	return out.strip_edges().left(28)


func open(g: Game, what: String) -> void:
	game = g
	target = what
	var kind := what.split(":")[0]
	var id := int(what.split(":")[1])
	var cur := ""
	if kind == "prov":
		cur = g.prov_name(id)
	else:
		var u = _unit(id)
		if u == null:
			return
		cur = u.name
	title.text = "Rename " + ("province" if kind == "prov" else "unit")
	reset_btn.visible = kind == "prov"
	edit.text = cur
	show()
	reset_size()
	var vs := get_viewport_rect().size
	position = ((vs - size) / 2).floor()
	edit.grab_focus()
	edit.select_all()


func _unit(id: int):
	for u in game.units:
		if u.id == id and u.owner == Game.LOCAL:
			return u
	return null


func _done(reset: bool) -> void:
	var kind := target.split(":")[0]
	var id := int(target.split(":")[1])
	var v := clean(edit.text)
	if kind == "prov":
		if reset or v == "":
			game.prov_rename.erase(id)
		else:
			game.do("rename_prov", [id, v])
	else:
		var u = _unit(id)
		if u != null and v != "":
			u.name = v
	hide()


func _input(ev: InputEvent) -> void:
	if visible and ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		hide()
		get_viewport().set_input_as_handled()
