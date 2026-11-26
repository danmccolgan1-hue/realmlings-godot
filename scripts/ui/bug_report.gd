class_name BugReport
extends Control
## 0.19: the bug report box (the bug button, top right in a game). A text box with a blue border and two buttons:
## Submit takes a screenshot and sends it with the text to GitHub (Settings.bug_repo, the bug_reports folder) so it
## can be read and dealt with later; Cancel clears the text and folds the box away. Without a GitHub token in
## Settings, or if GitHub can't be reached, the report is kept on this computer (user://bug_reports) instead.
## Views only: nothing here changes the game.

const BLUE := Color("#3f72d9")
const API := "https://api.github.com/repos/%s/contents/%s"

var hud
var panel: PanelContainer
var text: TextEdit
var submit_btn: Button
var note: Label
var http: HTTPRequest
var _queue := []      # [path, base64 content, message] still to send
var _stamp := ""
var _sent := []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", TopBar.paper(3, 2))
	panel.custom_minimum_size = Vector2(440, 0)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var head := Label.new()
	head.text = "Report a bug"
	head.add_theme_font_size_override("font_size", 20)
	head.add_theme_color_override("font_color", UiKit.INK)
	v.add_child(head)
	text = TextEdit.new()
	text.placeholder_text = "What happened, and what did you expect? (A screenshot of the game is added when you submit.)"
	text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text.custom_minimum_size = Vector2(420, 150)
	text.add_theme_font_size_override("font_size", 15)
	text.add_theme_color_override("font_color", UiKit.INK)
	text.add_theme_color_override("font_placeholder_color", Color(UiKit.INK, 0.45))
	for st in ["normal", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#fffdf6")
		sb.border_color = BLUE
		sb.set_border_width_all(3 if st == "focus" else 2)
		sb.set_corner_radius_all(6)
		sb.set_content_margin_all(8)
		text.add_theme_stylebox_override(st, sb)
	v.add_child(text)
	note = Label.new()
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color("#5a6475"))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(420, 0)
	v.add_child(note)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	submit_btn = UiKit.button("Submit", 18, func(): submit())
	submit_btn.custom_minimum_size = Vector2(120, 0)
	row.add_child(submit_btn)
	var cancel := UiKit.button("Cancel", 18, func(): cancel_report())
	cancel.custom_minimum_size = Vector2(120, 0)
	row.add_child(cancel)
	http = HTTPRequest.new()
	http.timeout = 30.0
	add_child(http)
	http.request_completed.connect(_on_done)
	panel.hide()


func toggle() -> void:
	if panel.visible:
		panel.hide()
	else:
		open()


func open() -> void:
	note.text = ("Sends to GitHub (%s)." % Settings.bug_repo) if Settings.bug_token != "" else "No GitHub token in Settings: the report is saved on this computer (%s)." % ProjectSettings.globalize_path("user://bug_reports")
	submit_btn.disabled = false
	panel.show()
	panel.reset_size()
	# just under the top right corner, below the map buttons
	var vs := get_viewport_rect().size
	panel.position = Vector2(vs.x - panel.size.x - 12, 70)
	text.grab_focus()


## Cancel: the text is cleared and the box folds away (the bug button stays, to open it again).
func cancel_report() -> void:
	text.text = ""
	panel.hide()


func submit() -> void:
	var body := text.text.strip_edges()
	if body == "":
		hud.add_toast("Write what went wrong first.", true)
		return
	submit_btn.disabled = true
	panel.hide()   # (the screenshot shows the game, not this box)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null and img.get_width() > 1600:
		img.resize(1600, int(img.get_height() * 1600.0 / img.get_width()), Image.INTERPOLATE_BILINEAR)
	var shot: PackedByteArray = img.save_jpg_to_buffer(0.85) if img != null else PackedByteArray()
	_stamp = Time.get_datetime_string_from_system(true).replace(":", "-").replace("T", "_")
	var md := _report(body, "%s.jpg" % _stamp)
	_save_local(md, shot)
	if Settings.bug_token == "":
		_finish("Bug report saved on this computer: %s" % ProjectSettings.globalize_path("user://bug_reports"))
		return
	_sent = []
	_queue = [["bug_reports/%s.jpg" % _stamp, Marshalls.raw_to_base64(shot), "Bug report %s: screenshot" % _stamp],
		["bug_reports/%s.md" % _stamp, Marshalls.utf8_to_base64(md), "Bug report %s" % _stamp]]
	_next()


# the report's text: what the player wrote, and the game it happened in
func _report(body: String, shot: String) -> String:
	var g: Game = hud.game if hud != null else null
	var lines := ["# Bug report %s" % _stamp, "", body, "", "## The game", ""]
	lines.append("- Version: %s" % str(ProjectSettings.get_setting("application/config/version", "")))
	lines.append("- System: %s" % OS.get_name())
	if g != null:
		lines.append("- Seed: %s" % str(g.world.seed))
		lines.append("- Game time: %s" % Game.fmt_time(g.t))
		lines.append("- Nation: %s (%s, %s)" % [g.player_info(Game.LOCAL).name, Races.NAME.get(g.race(), ""), g.leader])
		lines.append("- Players: %d%s" % [g.seats.size(), " (multiplayer)" if g.seats.size() > 1 else ""])
		lines.append("- Provinces: %d" % g.provs_of(Game.LOCAL).size())
	lines.append("")
	lines.append("![screenshot](%s)" % shot)
	return "\n".join(lines) + "\n"


func _save_local(md: String, shot: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute("user://bug_reports")
	var f := FileAccess.open("user://bug_reports/%s.md" % _stamp, FileAccess.WRITE)
	if f != null:
		f.store_string(md)
		f.close()
	var f2 := FileAccess.open("user://bug_reports/%s.jpg" % _stamp, FileAccess.WRITE)
	if f2 != null:
		f2.store_buffer(shot)
		f2.close()


func _next() -> void:
	if _queue.is_empty():
		_finish("Bug report sent. Thank you!")
		return
	var it: Array = _queue[0]
	var url := API % [Settings.bug_repo, it[0]]
	var headers := ["Authorization: Bearer " + Settings.bug_token, "Accept: application/vnd.github+json", "User-Agent: Realmlings", "Content-Type: application/json"]
	var err := http.request(url, headers, HTTPClient.METHOD_PUT, JSON.stringify({"message": it[2], "content": it[1]}))
	if err != OK:
		_finish("Couldn't reach GitHub; the report is saved on this computer: %s" % ProjectSettings.globalize_path("user://bug_reports"), true)


func _on_done(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		var why := "GitHub said %d%s" % [code, " (check the token in Settings)" if code == 401 or code == 403 or code == 404 else ""] if result == HTTPRequest.RESULT_SUCCESS else "no connection"
		_finish("The bug report couldn't be sent (%s); it is saved on this computer: %s" % [why, ProjectSettings.globalize_path("user://bug_reports")], true)
		return
	_sent.append(_queue.pop_front()[0])
	_next()


func _finish(msg: String, warn := false) -> void:
	_queue = []
	submit_btn.disabled = false
	if not warn:
		text.text = ""
	if hud != null:
		hud.add_toast(msg, warn)
