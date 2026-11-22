class_name RequestBox
extends PanelContainer
## A computer nation's request (an alliance offer, a gift, an access request…) waiting for your answer: 30 s, then
## declined. "Later" tucks it away into a flag (FlagBar). web: v105.js renderRequest.
## Views only: answers go through Game.answer_request.

var game: Game
var hud
var col: VBoxContainer
var title: RichTextLabel
var text: RichTextLabel
var timer: ProgressBar
var btns: HBoxContainer
var shown_id := -1


func setup(g: Game, h) -> void:
	game = g
	hud = h
	if col != null:
		return
	add_theme_stylebox_override("panel", UiKit.box(UiKit.PAPER, 12, 3))
	custom_minimum_size = Vector2(520, 0)
	col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	title = UiKit.rich(20, 500)
	col.add_child(title)
	text = UiKit.rich(18, 500)
	col.add_child(text)
	timer = ProgressBar.new()
	timer.show_percentage = false
	timer.custom_minimum_size = Vector2(500, 10)
	col.add_child(timer)
	btns = HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	col.add_child(btns)
	hide()


func _current():
	if game == null or game.dipl.is_empty():
		return null
	for r in game.dipl_state().reqs:
		if not r.min:
			return r
	return null


func _process(_dt: float) -> void:
	if game == null:
		return
	var r = _current()
	if r == null:
		hide()
		shown_id = -1
		return
	show()
	var left := maxf(0.0, r.until - game.t)
	timer.max_value = Game.DIPL.reqTime
	timer.value = left
	if r.id == shown_id:
		return
	shown_id = r.id
	var o: int = r.from
	var L = game.leader_of(o)
	var tx: Array = game.req_text(r)
	title.text = "[b]%s[/b] — %s%s" % [game.player_info(o).name, (L.full + " · ") if L != null else "", Game.REQ_NAME[r.kind]]
	text.text = "%s\n[i]Declined if you don’t answer within %d seconds.[/i]" % [tx[0], int(Game.DIPL.reqTime)]
	UiKit.clear(btns)
	btns.add_child(UiKit.button(tx[1], 18, func(): game.do("answer_request", [r, true])))
	btns.add_child(UiKit.button(tx[2], 18, func(): game.do("answer_request", [r, false])))
	btns.add_child(UiKit.button("Later", 18, func():
		game.do("show_request", [r.id, false])
		shown_id = -1))
	if hud and hud.has_method("focus_nation"):
		btns.add_child(UiKit.button("Show me", 18, func(): hud.focus_nation(o)))
