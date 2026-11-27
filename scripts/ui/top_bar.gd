class_name TopBar
extends Control
## The top of the screen as the web game lays it out (game.js setupBar / updateBar, v96 forts and provinces, v98
## mana): a centered strip with gold, wood, food (stock, storage, income), mana regeneration, forts, provinces and
## the payday ring; the research strip under it (a circle per tree, the points each earns); the clock and map
## buttons top right; the menu gear, your nation and the Armory and Diplomacy buttons top left.
## Views only: buttons go through the HUD and main.

const PAPER := Color("#f4ead2")
const INK := Color("#1d1a22")
const GREEN := Color("#2f7d32")
const RED := Color("#b3261e")
const TREES := ["gov", "mil", "mag"]
const TREE_NAME := {"gov": "Government", "mil": "Military", "mag": "Magic"}

var hud
var game: Game
var res := {}          # k -> {amt, cap, inc, row}
var mana_l: Label
var forts_l: Label
var provs_l: Label
var exh_l: Label
var ring: Glyph
var tree_g := {}
var tree_pts := {}
var tree_ban := {}
var research_btn: Button
var clock_l: Label
var play_g: Glyph
var nation_l: Label
var nation_sw: TextureRect
var dip_btn: Button
var quest_btn: Button   # the Quest Log, under Diplomacy (games with quests only)
var war_g: Glyph
var key := ""
## 0.19.3: an observer's bar: only the menu, the clock and the map buttons (no resources, research, nation, Armory,
## Diplomacy or Quest Log; nothing to pause or go home to).
var observer := false
var _player_only := []   # what an observer doesn't get


static func paper(radius := 3, border := 2) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = PAPER
	b.border_color = INK
	b.set_border_width_all(border)
	b.set_corner_radius_all(radius)
	b.content_margin_left = 12
	b.content_margin_right = 12
	b.content_margin_top = 5
	b.content_margin_bottom = 5
	return b


static func ink_label(sz: int, col := INK) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## A paper button (the web game's .btn): an icon, a word, or both.
static func paper_button(text: String, glyph: String, tip: String, f: Callable, px := 46.0) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(px, px)
	for st in ["normal", "hover", "pressed", "focus"]:
		var s := paper()
		if st == "hover":
			s.bg_color = Color("#fff6df")
		elif st == "pressed":
			s.bg_color = Color("#e6d9b8")
		b.add_theme_stylebox_override(st, s)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_font_size_override("font_size", 18)
	if glyph != "":
		# an icon-only button's glyph fills it, centered, at any size (11 px of margin at the usual 46)
		var gm := 11.0 if px >= 46.0 else maxf(5.0, px * 0.18)
		var g := Glyph.make(glyph, 24.0 if text != "" else px - 2 * gm)
		b.add_child(g)
		if text == "":
			g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_KEEP_SIZE, int(gm))
		else:
			g.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE, Control.PRESET_MODE_KEEP_SIZE, 10)
			g.offset_right = g.offset_left + 24
		if text != "":
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.add_theme_constant_override("h_separation", 0)
			b.text = "      " + text
	b.pressed.connect(f)
	return b


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# the centered strip
	var strip := PanelContainer.new()
	strip.add_theme_stylebox_override("panel", paper())
	add_child(strip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	strip.add_child(row)
	for k in Game.RES:
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 3)
		r.mouse_filter = Control.MOUSE_FILTER_STOP
		var icon := TextureRect.new()
		var sp = Art.get_sprite("icons", "common", "res_%s.png" % k)
		if sp:
			icon.texture = sp.tex
		icon.custom_minimum_size = Vector2(30, 30)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.add_child(icon)
		var amt := ink_label(22)
		var cap := ink_label(13, Color("#6b5a44"))
		var inc := ink_label(14, GREEN)
		for l in [amt, cap, inc]:
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			r.add_child(l)
		row.add_child(r)
		res[k] = {"amt": amt, "cap": cap, "inc": inc, "row": r}
	mana_l = _counter(row, "mana", "")
	forts_l = _counter(row, "fort", "")
	provs_l = _counter(row, "prov", "")
	exh_l = ink_label(16, RED)
	exh_l.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(exh_l)
	ring = Glyph.make("ring", 26.0)
	ring.mouse_filter = Control.MOUSE_FILTER_STOP
	ring.tooltip_text = "Payday: every 10 s your provinces and buildings pay out and upkeep is paid. The circle fills until the next one."
	row.add_child(ring)
	# the research strip
	research_btn = Button.new()
	research_btn.focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed", "focus"]:
		var s := paper(3, 2)
		s.content_margin_top = 3
		s.content_margin_bottom = 3
		if st == "hover":
			s.bg_color = Color("#fff6df")
		research_btn.add_theme_stylebox_override(st, s)
	research_btn.tooltip_text = "Research [T]: a circle per tree fills as it researches (empty: nothing picked); the numbers are the points each tree earns every 10 s"
	research_btn.pressed.connect(func(): hud.toggle_research())
	add_child(research_btn)
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 6)
	rrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	research_btn.add_child(rrow)
	var rl := ink_label(16)
	rl.text = "Research"
	rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rrow.add_child(rl)
	for tr in TREES:
		var g := Glyph.make("tree_" + tr, 20.0)
		rrow.add_child(g)
		tree_g[tr] = g
	var sep := ink_label(16, Color("#6b5a44"))
	sep.text = " |"
	rrow.add_child(sep)
	for tr in TREES:   # web: tech.js renderTechBtn: each tree's banner, then its points every 10 s
		var ban := Glyph.make("rp_" + tr, 22.0)
		rrow.add_child(ban)
		tree_ban[tr] = ban
		var l := ink_label(16, Glyph.TREE_COL["tree_" + tr])
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rrow.add_child(l)
		tree_pts[tr] = l
	# top right: the clock and the map buttons
	var right := HBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	add_child(right)
	var clock_box := PanelContainer.new()
	clock_box.add_theme_stylebox_override("panel", paper())
	clock_box.custom_minimum_size = Vector2(80, 46)
	clock_l = ink_label(20, Color("#6b5a44"))
	clock_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock_l.mouse_filter = Control.MOUSE_FILTER_STOP
	clock_l.tooltip_text = "Game time"
	clock_box.add_child(clock_l)
	right.add_child(clock_box)
	var play := paper_button("", "", "Pause or play [Space]", func(): hud.game.do("set_paused", [not hud.game.paused]))
	_player_only.append(play)
	play_g = Glyph.make("play", 24.0)
	play.add_child(play_g)
	play_g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_KEEP_SIZE, 11)
	right.add_child(play)
	right.add_child(paper_button("", "full", "Full screen [F11]", func(): hud.toggle_fullscreen()))
	right.add_child(paper_button("", "plus", "Zoom in", func(): hud.main.zoom_by(1.25)))
	right.add_child(paper_button("", "minus", "Zoom out", func(): hud.main.zoom_by(0.8)))
	var home := paper_button("", "home", "Back to your capital [Home]", func(): hud.main.go_home())
	right.add_child(home)
	_player_only.append(home)
	right.add_child(paper_button("", "bug", "Report a bug: what happened, with a screenshot", func(): hud.bug.toggle()))
	# top left: the menu, your nation, Armory and Diplomacy
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	add_child(left)
	left.position = Vector2(12, 12)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	left.add_child(top_row)
	top_row.add_child(paper_button("", "gear", "Menu and settings [Esc]", func(): hud.toggle_menu()))
	var nb := paper_button("", "", "Your nation", func(): hud.country.toggle())
	nb.custom_minimum_size = Vector2(0, 46)
	var nrow := HBoxContainer.new()
	nrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nrow.add_theme_constant_override("separation", 8)
	nation_sw = TextureRect.new()
	nation_sw.custom_minimum_size = Vector2(40, 28)
	nation_sw.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	nation_sw.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	nation_sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nation_sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nrow.add_child(nation_sw)
	nation_l = ink_label(20)
	nation_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nrow.add_child(nation_l)
	nb.add_child(nrow)
	nrow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	nb.resized.connect(func(): nb.custom_minimum_size.x = nrow.get_combined_minimum_size().x + 22)
	nrow.resized.connect(func(): nb.custom_minimum_size.x = nrow.get_combined_minimum_size().x + 22)
	top_row.add_child(nb)
	_player_only.append(nb)
	# Armory and Diplomacy: picture buttons, as the web game's left column (web: #armBtn, #dip)
	var arm := paper_button("", "", "Armory (G): design your soldiers' gear and set the Army Training Order", func(): hud.armory.toggle(), 54.0)
	_icon_on(arm, "icons/common/ui_armory.png")
	left.add_child(arm)
	dip_btn = paper_button("", "", "Diplomacy (Y): wars, peace, alliances and every other nation", func(): hud.diplomacy.toggle(), 54.0)
	_icon_on(dip_btn, "icons/common/ui_dove.png")
	war_g = Glyph.make("war", 22.0, RED)
	war_g.hide()
	dip_btn.add_child(war_g)
	war_g.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE, Control.PRESET_MODE_KEEP_SIZE, 8)
	war_g.offset_left = war_g.offset_right - 24
	left.add_child(dip_btn)
	quest_btn = paper_button("", "", "Quest Log (L): your quests, their texts and the relics you still need", func(): hud.quests.toggle(), 54.0)
	_icon_on(quest_btn, "icons/common/ui_quests.png")
	left.add_child(quest_btn)
	for b in [arm, dip_btn, quest_btn]:
		b.custom_minimum_size = Vector2(140, 54)
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_player_only.append_array([strip, research_btn, arm, dip_btn, quest_btn])


## An observer's bar (see `observer`), or a player's again.
func set_observer(on: bool) -> void:
	observer = on
	for c in _player_only:
		c.visible = not on
	if not on and game != null:
		setup(game)


func _counter(row: HBoxContainer, glyph: String, tip: String) -> Label:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 3)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	r.tooltip_text = tip
	r.add_child(Glyph.make(glyph, 24.0))
	var l := ink_label(20)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(l)
	row.add_child(r)
	return l


func setup(g: Game) -> void:
	game = g
	key = ""
	var P := g.player_info(Game.LOCAL)
	nation_sw.texture = Art.nation_flag(g, Game.LOCAL)
	nation_l.text = "Basic Tutorial" if g.tutorial != null else str(P.name)
	var L = g.leader_of(Game.LOCAL)
	nation_l.get_parent().get_parent().tooltip_text = "%s%s" % [P.name, (", led by %s" % L.full) if L != null else ""]
	dip_btn.visible = not g.nations.is_empty() and not observer
	quest_btn.visible = g.quests_on and not observer


func _process(_dt: float) -> void:
	if game == null or not is_visible_in_tree():
		return
	var g := game
	# placed by hand each frame: centered strip, research strip under it, map buttons top right
	var strip: Control = get_child(0)
	strip.size = strip.get_combined_minimum_size()
	strip.position = Vector2((size.x - strip.size.x) / 2, 12)
	var right: Control = get_child(2)
	right.size = right.get_combined_minimum_size()
	right.position = Vector2(size.x - right.size.x - 12, 12)
	var rrow0: Control = research_btn.get_child(0)
	var rm: Vector2 = rrow0.get_combined_minimum_size()
	var rs: Vector2 = rm + Vector2(24, 8)
	research_btn.size = rs
	research_btn.position = Vector2(round((size.x - rs.x) / 2), strip.position.y + strip.size.y + 6)
	rrow0.size = rm   # (sized and centered by hand, so it stays centered as its numbers change)
	rrow0.position = ((rs - rm) / 2).round()
	ring.set_value(clampf(1.0 - (g.next_tick - g.t) / g.TICK, 0, 1) if g.next_tick > 0 else 0.0)
	clock_l.text = Game.fmt_time(g.t)
	if observer:
		return
	play_g.kind = "play" if g.paused else "pause"
	play_g.queue_redraw()
	for tr in TREES:
		var st: Dictionary = g.tech[tr]
		var gl: Glyph = tree_g[tr]
		gl.active = st.cur != null
		# (0.19: against the real cost, which doubles for Government and Military and grows with your land; it used
		# the bare cost, so the circles overflowed and stopped drawing)
		var gx = g.TECH_BY_ID.get(st.cur) if st.cur != null else null
		gl.set_value(clampf(float(st.prog) / maxf(1.0, float(g.tech_cost(gx))), 0.0, 1.0) if gx != null else 0.0)
		gl.queue_redraw()
	var k := "%s|%s|%s|%d|%d|%d|%d|%d|%d|%d" % [g.stock, g.income, [g.storage_cap("gold"), g.storage_cap("wood"), g.storage_cap("food")],
		g.mana_regen(Game.LOCAL), g.fort_count(), g.fort_limit(), g.provs_of(Game.LOCAL).size(), g.prov_limit(), g.exhaust, g.wars_of(Game.LOCAL).size()]
	k += str(TREES.map(func(t): return g.tech_rate(t)))
	if k == key:
		return
	key = k
	for r in Game.RES:
		var cap := g.storage_cap(r)
		var inc: int = g.income[r]
		res[r].amt.text = str(int(g.stock[r]))
		res[r].amt.add_theme_color_override("font_color", RED if g.stock[r] >= cap else INK)
		res[r].cap.text = "/%d" % cap
		res[r].inc.text = "(%s%d)" % ["+" if inc >= 0 else "−", absi(inc)]
		res[r].inc.add_theme_color_override("font_color", RED if inc < 0 else GREEN)
		res[r].row.tooltip_text = hud._res_tip(r)
	var mr := g.mana_regen(Game.LOCAL)
	mana_l.text = "+%d" % mr
	mana_l.get_parent().tooltip_text = "Mana: every Magic User regains %d mana every 10 s (1 for each Tier I Magic Barracks, 2 for each Tier II, 3 for each Tier III), up to %d. A Magic User regains nothing while he is casting." % [mr, g.mana_cap()]
	var fc := g.fort_count()
	var fl := g.fort_limit()
	forts_l.text = "%d/%d" % [fc, fl]
	forts_l.add_theme_color_override("font_color", RED if fc >= fl else INK)
	forts_l.get_parent().tooltip_text = "Forts you hold out of your fort limit (a fort counts once its upgrade has finished)"
	var pc := g.provs_of(Game.LOCAL).size()
	var pl := g.prov_limit()
	provs_l.text = "%d/%d" % [pc, pl]
	provs_l.add_theme_color_override("font_color", RED if pc >= pl else INK)
	provs_l.get_parent().tooltip_text = "Provinces you hold (%d) out of the %d your forts allow: each fort (and the capital) allows itself plus a few outposts." % [pc, pl]
	exh_l.visible = g.exhaust > 0
	exh_l.text = "Exhaustion %d/%d" % [g.exhaust, GameData.c("EXHAUST_MAX")]
	exh_l.tooltip_text = "Army Exhaustion: rises every payday you can’t feed your army. At %d the whole army deserts." % GameData.c("EXHAUST_MAX")
	for tr in TREES:
		tree_pts[tr].text = str(g.tech_rate(tr)) if g.tech[tr].tier else "–"
		var bk: String = "rp_%s%s" % [tr, "" if g.tech[tr].tier else "_off"]
		if tree_ban[tr].kind != bk:
			tree_ban[tr].kind = bk
			tree_ban[tr].queue_redraw()
	var n := g.wars_of(Game.LOCAL).size()
	war_g.visible = n > 0
	dip_btn.tooltip_text = ("At war with %d nation%s. " % [n, "s" if n > 1 else ""] if n else "") + "Diplomacy [Y]: wars, peace, alliances and every other nation"


static func _icon_on(b: Button, path: String) -> void:
	var r := TextureRect.new()
	r.texture = load("res://assets/art/" + path) if ResourceLoader.exists("res://assets/art/" + path) else null
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(r)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 7)


## Where things below the bar can start (the flags hang from here).
func bottom() -> float:
	return research_btn.position.y + research_btn.size.y
