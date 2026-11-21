class_name CountryWindow
extends Control
## The Country Breakdown: click your flag and name, top left. Your leader, your land, where your resources come from
## and go, your artifacts and every war you have fought. web: v78.js renderCountry / upkeepSplit, v95.js (artifacts),
## v105.js (the leader's portrait and name). Views only.

const MUTED := Color("#6b6257")
const LINE := Color("#cdbf9e")
const RACE_WORD := {"realm": "Realmling", "swamp": "Swampling", "wood": "Woodling"}   # web: v105.js raceWord

var game: Game
var hud
var win: Dictionary
var flag: TextureRect
var key := ""


func setup(g: Game, h) -> void:
	game = g
	hud = h
	key = ""
	if not win.is_empty():
		hide()
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	win = UiKit.window("", 780, func(): hide())
	add_child(win.panel)
	var head: HBoxContainer = win.title.get_parent()
	flag = TextureRect.new()
	flag.custom_minimum_size = Vector2(44, 30)
	flag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	flag.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(flag)
	head.move_child(flag, 0)
	head.add_theme_constant_override("separation", 10)
	win.title.size_flags_horizontal = 0
	var sub := UiKit.ink(15)
	sub.text = "Country Breakdown"
	sub.add_theme_color_override("font_color", MUTED)
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sub)
	head.move_child(sub, 2)
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


static func clock(s: float) -> String:   # web: v78.js fmtClock
	var n := maxi(0, floori(s))
	var h := n / 3600
	var m := (n / 60) % 60
	return ("%d:%02d:%02d" % [h, m, n % 60]) if h else ("%d:%02d" % [m, n % 60])


func _refresh() -> void:
	var provs := game.provs_of()
	var sp := game.upkeep_split()
	var gross: Dictionary = game.income_parts.get("gross", {"gold": 0, "wood": 0, "food": 0})
	var k := "%s|%s|%s|%s|%s|%s|%s|%d|%s" % [provs, sp, gross, game.income, game.war_log.map(func(w): return [w.id, w.end, w.result]),
		game.player_info(Game.ME).name, game.artifacts.get(Game.ME, []), floori(game.t), game.leader]
	if k == key:
		return
	key = k
	flag.texture = Art.nation_flag(game, Game.ME)
	win.title.text = game.player_info(Game.ME).name
	UiKit.clear(win.body)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	win.body.add_child(top)
	top.add_child(_leader())
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	top.add_child(right)
	# stats
	var caps := provs.filter(func(p): return game.buildings[p].stage == 2).size()
	var forts := provs.filter(func(p): return game.buildings[p].stage == 1).size()
	var st := HBoxContainer.new()
	st.add_theme_constant_override("separation", 8)
	for s in [["Provinces", str(provs.size())], ["Capital · Forts · Outposts", "%d · %d · %d" % [caps, forts, provs.size() - caps - forts]], ["Game time", clock(game.t)]]:
		st.add_child(_stat(s[0], s[1]))
	right.add_child(st)
	# land
	right.add_child(_sec("Land"))
	var terr := {"grassland": 0, "forest": 0, "desert": 0, "swamp": 0}
	for p in provs:
		terr[game.G.provs[p].terrain] = terr.get(game.G.provs[p].terrain, 0) + 1
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 14)
	for t in terr:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 5)
		var sw := ColorRect.new()
		sw.color = Color(MapLayers.TER[t][0])
		sw.custom_minimum_size = Vector2(14, 14)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(sw)
		var l := UiKit.rich(15)
		l.fit_content = true
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.text = "%s [b]%d[/b]" % [t.capitalize(), terr[t]]
		h.add_child(l)
		tr.add_child(h)
	right.add_child(tr)
	# resources
	right.add_child(_sec("Resources every 10 s"))
	var gd := GridContainer.new()
	gd.columns = 4
	gd.add_theme_constant_override("h_separation", 22)
	gd.add_theme_constant_override("v_separation", 3)
	gd.add_child(Control.new())
	for r in Game.RES:
		var l := UiKit.ink(13)
		l.text = GameData.c("RES_LABEL")[r].to_upper()
		l.add_theme_color_override("font_color", MUTED)
		gd.add_child(l)
	var neg := func(o):
		var x := {}
		for r in Game.RES:
			x[r] = -o.get(r, 0)
		return x
	for row in [["Gross income", gross, true], ["Upkeep: buildings", neg.call(sp.blds), false], ["Upkeep: units", neg.call(sp.units), false], ["Net income", game.income, true]]:
		var l := UiKit.ink(15)
		l.text = row[0]
		if row[0] == "Net income":
			l.add_theme_color_override("font_color", UiKit.INK)
			l.add_theme_font_size_override("font_size", 16)
		gd.add_child(l)
		for r in Game.RES:
			var v := int(roundf(float(row[1].get(r, 0))))
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 3)
			var ic := TextureRect.new()
			ic.texture = CostRow.icon(r)
			ic.custom_minimum_size = Vector2(18, 18)
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			h.add_child(ic)
			var n := UiKit.ink(15)
			n.text = ("+%d" % v) if row[2] and v > 0 else str(v)
			if row[0] == "Net income":
				n.add_theme_color_override("font_color", Color("#2c6e36") if v >= 0 else UiKit.BAD)
			h.add_child(n)
			gd.add_child(h)
	right.add_child(gd)
	# artifacts (web: v95.js)
	right.add_child(_sec("Artifacts"))
	var mine: Array = game.artifacts.get(Game.ME, [])
	if mine.is_empty():
		right.add_child(_none("None yet. Bosses guard Death Mountain, the Desert Oasis and the Heart of the Forest: beat one to claim its artifact."))
	for id in mine:
		var A: Dictionary = GameData.c("ARTIFACTS")[id]
		var h := HBoxContainer.new()
		var ic := TextureRect.new()
		ic.texture = Hud.icon("icons/common/art_%s.png" % id)
		ic.custom_minimum_size = Vector2(34, 34)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		h.add_child(ic)
		var l := UiKit.rich(14, 440)
		var d: String = A.desc
		l.text = "[b]%s[/b]\n%s" % [A.name, d.left(1).to_upper() + d.substr(1)]
		h.add_child(l)
		right.add_child(h)
	# wars
	win.body.add_child(_sec("Wars"))
	if game.war_log.is_empty():
		win.body.add_child(_none("No wars yet."))
		return
	var wg := GridContainer.new()
	wg.columns = 4
	wg.add_theme_constant_override("h_separation", 26)
	for hd in ["Against", "Started", "Ended", "Result"]:
		var l := UiKit.ink(13)
		l.text = hd.to_upper()
		l.add_theme_color_override("font_color", MUTED)
		wg.add_child(l)
	var wl := game.war_log.duplicate()
	wl.reverse()
	for w in wl:
		var h := HBoxContainer.new()
		var dot := ColorRect.new()
		dot.color = Color(str(game.player_info(w.foe).get("color", "#999999")))
		dot.custom_minimum_size = Vector2(12, 12)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(dot)
		var nl := UiKit.ink(15)
		nl.text = str(w.foeName) + ("  (ally's war)" if w.get("joined", false) else "")
		h.add_child(nl)
		wg.add_child(h)
		for txt in [clock(w.start), "ongoing" if w.end == null else clock(w.end)]:
			var l := UiKit.ink(15)
			l.text = txt
			wg.add_child(l)
		var res := UiKit.ink(15)
		var rs := str(w.result) if w.result != null else "—"
		res.text = rs
		if rs.begins_with("Victory"):
			res.add_theme_color_override("font_color", Color("#2c6e36"))
		elif rs.begins_with("Defeat"):
			res.add_theme_color_override("font_color", UiKit.BAD)
		wg.add_child(res)
	win.body.add_child(wg)


# the leader: portrait, full name, race and sex, bonus (web: v105.js)
func _leader() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(180, 0)
	v.add_theme_constant_override("separation", 4)
	var L = game.leader_of(Game.ME)
	var fr := PanelContainer.new()
	var bx := UiKit.box(Color("#3a3340"), 0, 2, UiKit.INK)
	bx.set_content_margin_all(0)
	fr.add_theme_stylebox_override("panel", bx)
	fr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var pt := TextureRect.new()
	pt.custom_minimum_size = Vector2(150, 175)
	pt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pt.texture = Hud.icon("icons/realm/leader_%s.png" % L.id) if L != null else null
	fr.add_child(pt)
	v.add_child(fr)
	if L == null:
		var l := UiKit.ink(16)
		l.text = "Leader"
		v.add_child(l)
		return v
	fr.tooltip_text = L.full
	var n := UiKit.ink(18)
	n.text = L.full
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(n)
	var r := UiKit.ink(14)
	r.text = "%s · %s" % [RACE_WORD.get(L.race, "Realmling"), "Woman" if L.get("sex") == "f" else "Man"]
	r.add_theme_color_override("font_color", MUTED)
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(r)
	var b := UiKit.ink(14)
	b.text = L.bonus
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(180, 0)
	b.add_theme_color_override("font_color", Color("#2c6e36"))
	v.add_child(b)
	return v


func _stat(label: String, val: String) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bx := UiKit.box(Color("#fbf6e8"), 4, 1, LINE)
	bx.set_content_margin_all(6)
	pc.add_theme_stylebox_override("panel", bx)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	pc.add_child(v)
	var l := UiKit.ink(12)
	l.text = label.to_upper()
	l.add_theme_color_override("font_color", MUTED)
	v.add_child(l)
	var b := UiKit.ink(20)
	b.text = val
	v.add_child(b)
	return pc


func _sec(t: String) -> Label:
	var l := UiKit.ink(14)
	l.text = t.to_upper()
	l.add_theme_color_override("font_color", MUTED)
	return l


func _none(t: String) -> Label:
	var l := UiKit.ink(14)
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(500, 0)
	l.add_theme_color_override("font_color", MUTED)
	return l


func _process(_dt: float) -> void:
	if game != null and visible:
		_refresh()
