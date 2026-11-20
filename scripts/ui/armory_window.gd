class_name ArmoryWindow
extends Control
## The Armory (G): design soldiers from the gear you have researched, and place Army Training Orders: many soldiers
## at once, trained by every Barracks, gathered into one army. web: equip.js Armory panel, v106.js Training Orders tab.
## Views only: every change goes through the game's own functions.

var game: Game
var hud
var win: Dictionary
var tabs: TabContainer
var list: VBoxContainer
var draft := {}
var editor: VBoxContainer
var preview: RichTextLabel
var order_box: VBoxContainer
var order_draft := {}
var order_rally := -1
var order_info: RichTextLabel
var order_btn: Button
var orders_list: RichTextLabel
var key := ""

const GEAR := {"weapon": "WEAPONS", "shield": "SHIELD_DEFS", "armor": "ARMORS", "horse": "HORSES"}


func setup(g: Game, h) -> void:
	game = g
	hud = h
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	win = UiKit.window("Armory", 860, func(): close())
	add_child(win.panel)
	win.panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	tabs = TabContainer.new()
	tabs.add_theme_font_size_override("font_size", 18)
	tabs.custom_minimum_size = Vector2(820, 520)
	tabs.add_theme_stylebox_override("panel", UiKit.box(UiKit.PAPER.darkened(0.06), 8))
	win.body.add_child(tabs)
	# designs
	var row := HBoxContainer.new()
	row.name = "Designs"
	row.add_theme_constant_override("separation", 16)
	tabs.add_child(row)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(250, 0)
	row.add_child(left)
	list = VBoxContainer.new()
	left.add_child(list)
	left.add_child(UiKit.button("+ New design", 18, func(): edit({"id": null, "name": "New Footman", "type": "inf", "weapon": "shortsword", "shield": null, "armor": "leather1", "horse": null})))
	editor = VBoxContainer.new()
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(editor)
	# training orders
	var ob := VBoxContainer.new()
	ob.name = "Army Training Order"
	tabs.add_child(ob)
	order_box = VBoxContainer.new()
	ob.add_child(order_box)
	order_info = UiKit.rich(18, 760)
	ob.add_child(order_info)
	order_btn = UiKit.button("Place the order", 20, func(): _place())
	ob.add_child(order_btn)
	orders_list = UiKit.rich(17, 760)
	ob.add_child(orders_list)
	hide()


func open(tab := 0) -> void:
	show()
	tabs.current_tab = tab
	key = ""
	if draft.is_empty():
		edit(game.designs[0])
	order_rally = hud.prov if hud.prov >= 0 and game.owned(hud.prov) else game.capital
	_refresh()
	UiKit.center.call_deferred(win.panel)


func close() -> void:
	hide()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func edit(d: Dictionary) -> void:
	draft = d.duplicate()
	key = ""
	_build_editor()
	_refresh()


func _build_editor() -> void:
	UiKit.clear(editor)
	var name_row := HBoxContainer.new()
	var nl := UiKit.ink(18)
	nl.text = "Name"
	name_row.add_child(nl)
	var ne := LineEdit.new()
	ne.text = draft.name
	ne.max_length = 24
	ne.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ne.add_theme_font_size_override("font_size", 18)
	ne.text_changed.connect(func(t): draft.name = t)
	name_row.add_child(ne)
	editor.add_child(name_row)
	var type_row := HBoxContainer.new()
	for ty in [["inf", "Infantry"], ["cav", "Cavalry"]]:
		var b := UiKit.button(ty[1], 18, func():
			draft.type = ty[0]
			draft.horse = "riding" if ty[0] == "cav" else null
			_build_editor()
			_refresh())
		b.toggle_mode = true
		b.button_pressed = draft.type == ty[0]
		type_row.add_child(b)
	editor.add_child(type_row)
	for kind in ["weapon", "shield", "armor", "horse"]:
		if kind == "horse" and draft.type != "cav":
			continue
		if kind == "shield" and GameData.c("WEAPONS")[draft.weapon].twoH:
			var l := UiKit.ink(16)
			l.text = "Shield: none (two-handed weapon)"
			editor.add_child(l)
			continue
		var r := HBoxContainer.new()
		var l := UiKit.ink(18)
		l.text = kind.capitalize()
		l.custom_minimum_size = Vector2(90, 0)
		r.add_child(l)
		var opt := OptionButton.new()
		opt.add_theme_font_size_override("font_size", 17)
		opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var keys := []
		if kind == "shield":
			keys.append(null)
			opt.add_item("No shield")
		var table: Dictionary = GameData.c(GEAR[kind])
		for k in table:
			var rc = table[k].get("race")
			if rc != null and rc != "realm":
				continue
			var why = game.gear_why(kind, k)
			keys.append(k)
			opt.add_item("%s%s" % [table[k].name, "" if why == null else "  (%s)" % why])
			opt.set_item_disabled(opt.item_count - 1, why != null)
		opt.select(maxi(0, keys.find(draft.get(kind))))
		opt.item_selected.connect(func(i):
			draft[kind] = keys[i]
			_build_editor()
			_refresh())
		r.add_child(opt)
		editor.add_child(r)
	preview = UiKit.rich(18)
	editor.add_child(preview)
	var btns := HBoxContainer.new()
	btns.add_child(UiKit.button("Save design", 18, func():
		var d := game.save_design(draft)
		edit(d)))
	var del := UiKit.button("Delete", 18, func():
		if draft.get("id") != null and game.delete_design(draft.id):
			edit(game.designs[0]))
	del.disabled = draft.get("id") == null or game.design_by_id(draft.id) == null or game.design_by_id(draft.id).builtin
	btns.add_child(del)
	editor.add_child(btns)


func _refresh() -> void:
	if not visible:
		return
	UiKit.clear(list)
	for d in game.designs:
		var b := UiKit.button(d.name, 17, edit.bind(d))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_pressed = d.id == draft.get("id")
		list.add_child(b)
	var st := game.design_stats(draft)
	var locked := []
	for kind in ["weapon", "shield", "armor", "horse"]:
		if draft.get(kind) != null and (kind != "horse" or draft.type == "cav"):
			var why = game.gear_why(kind, draft[kind])
			if why != null:
				locked.append(why)
	var W: Dictionary = GameData.c("WEAPONS")[draft.weapon]
	preview.text = "[b]Attack[/b] %s   [b]Health[/b] %d   [b]Armor[/b] %d (blocks %d%%)   [b]Speed[/b] %s\n[b]Cost[/b] %s   [b]Upkeep[/b] %s food\n%s%s" % [
		st.atk, st.hp, st.armor, roundi(st.red * 100), st.speed, UiKit.cost_line(st.cost), st.upkeep.food, GameData.c("FAMILY")[W.fam].note,
		"" if locked.is_empty() else "\n[color=#b3261e]Locked: %s[/color]" % "; ".join(locked)]
	_refresh_orders()


func _refresh_orders() -> void:
	var kinds := game.to_kinds()
	var k := "%s|%s|%d" % [kinds, order_draft, order_rally]
	if k != key:
		key = k
		UiKit.clear(order_box)
		if kinds.is_empty():
			var l := UiKit.ink(18)
			l.text = "Build a Barracks to train soldiers."
			order_box.add_child(l)
		for kind in kinds:
			var r := HBoxContainer.new()
			var l := UiKit.ink(18)
			l.text = "%s (%s)" % [game.unit_defs[kind].name, UiKit.cost_line(game.unit_defs[kind].cost)]
			l.custom_minimum_size = Vector2(420, 0)
			r.add_child(l)
			for step in [-5, -1, 1, 5]:
				r.add_child(UiKit.button(("%+d" % step), 17, func():
					order_draft[kind] = maxi(0, order_draft.get(kind, 0) + step)
					_refresh_orders()))
			var n := UiKit.ink(20)
			n.text = "  × %d" % order_draft.get(kind, 0)
			r.add_child(n)
			order_box.add_child(r)
	var why = game.to_why(order_draft, order_rally)
	order_info.text = "Gather in [b]%s[/b] (click one of your provinces on the map to change it).\nCost: %s%s" % [
		game.prov_name(order_rally) if order_rally >= 0 else "?", UiKit.cost_line(game.to_cost(order_draft)), "" if why == null else "\n[color=#b3261e]%s[/color]" % why]
	order_btn.disabled = why != null
	var lines := []
	for O in game.train_orders:
		var pr := game.order_progress(O)
		lines.append("Order %d → %s: %s" % [O.id, game.prov_name(O.rally.prov), "complete" if O.done else "%d of %d trained, %d gathered" % [pr.made, O.total, pr.there]])
	orders_list.text = "\n".join(lines)


func _place() -> void:
	if game.purchase_order(order_draft, order_rally) >= 0:
		order_draft = {}
		key = ""
	_refresh_orders()


func _ready() -> void:
	if game == null:
		hide()


func _process(_dt: float) -> void:
	if game == null:
		return
	if visible and tabs.current_tab == 1:
		if hud.prov >= 0 and game.owned(hud.prov):
			order_rally = hud.prov
		_refresh_orders()
