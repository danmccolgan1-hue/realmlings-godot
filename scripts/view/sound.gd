class_name Sound
extends Node
## Music and sound effects. web: sound.js (SFX_FILES, sfx, sndNear, sndBattleLoop, sndWatch, sndSelection, sndMove),
## menu.js (the tavern music: fades, half volume while paused, M to mute), v102.js (a track per race),
## tutorial.js (TUT_AUDIO: a voice line per tutorial step, when one exists).
## The rules only name the sounds (Game.sfx); this node plays them. Switches and volumes live in Settings.

# web: sound.js SFX_FILES (name -> its own volume)
const SFX_FILES := {
	"sel_wayfinder": 0.7, "sel_mason": 0.7, "sel_soldier": 0.7, "sel_mage": 0.7,
	"mv_wayfinder": 0.5, "mv_mason": 0.55, "mv_army": 0.6, "mv_cavalry": 0.6, "mv_mage": 0.5,
	"ui_click": 0.35, "ui_panel": 0.5, "ui_error": 0.45,
	"bld_work": 0.4, "bld_done": 0.7, "bld_outpost": 0.65,
	"bat_loop": 0.75, "bat_blades": 0.3, "bat_fall": 0.4, "bat_win": 0.8, "bat_lose": 0.8,
	"war_declare": 0.9, "war_peace": 0.8, "war_fort_win": 0.8, "war_fort_lose": 0.8,
	"pr_research": 0.55, "pr_research_magic": 0.6, "pr_trained": 0.55, "pr_survey": 0.5,
	"mg_life": 0.65, "mg_death": 0.65, "mg_arcane": 0.65, "mg_rift": 0.7, "mg_risen": 0.55, "mg_school": 0.8,
	"wn_exhaust": 0.85, "wn_unrest": 0.8, "wn_enemy": 0.8, "wn_ally": 0.8,
	"wn_meet": 0.6, "ui_confirm": 0.55, "ui_deny": 0.5}   # (0.19: these three are made by synth(), not files)
# the smallest gap between two plays of the same sound (seconds); web: SFX_GAP
const SFX_GAP := {"ui_click": 0.05, "ui_error": 0.4, "bat_fall": 0.35, "mg_risen": 0.6, "bld_work": 1.5, "wn_enemy": 30.0,
	"sel_wayfinder": 0.25, "sel_mason": 0.25, "sel_soldier": 0.25, "sel_mage": 0.25}
# stingers keep their pitch; everything else varies a little (web: SFX_STEADY)
const SFX_STEADY := ["war_declare", "war_peace", "war_fort_win", "war_fort_lose", "bat_win", "bat_lose", "pr_research", "pr_research_magic",
	"mg_school", "wn_exhaust", "wn_enemy", "wn_ally", "bat_loop"]
# web: v102.js MUSIC_TRACKS (the Realmlings, the menus and the tutorial play the tavern piece)
const MUSIC_TRACKS := {"tavern": "res://assets/audio/music/tavern.mp3", "swamp": "res://assets/audio/music/tavern_percussion.mp3", "wood": "res://assets/audio/music/tavern_harp.mp3"}
const VOICES := 12

static var inst: Sound

var main            # the scene's entry node (its game, camera and HUD)
var buf := {}
var last := {}
var last_big := -9.0
var players := []
var loop: AudioStreamPlayer
var loop_vol := 0.0
var music: AudioStreamPlayer
var music_vol := 0.0      # the music's current level (0..1), faded toward music_target()
var track := ""
var swap_t := -1.0         # fading out to change track
var voice: AudioStreamPlayer
var enemy_seen := {}
var check_t := 0.0
var sel_key := ""
var last_input := -9.0     # a red message soon after your click or key press thunks (web: ui_error on refused commands)


func _ready() -> void:
	inst = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	for k in SFX_FILES:
		var path := "res://assets/audio/sfx/%s.mp3" % k
		if ResourceLoader.exists(path):
			buf[k] = load(path)
	# 0.19: a fanfare for meeting a nation, a confirming knock for orders that start a building or an upgrade, and
	# a low buzz for a refused road; made here (no files to import)
	buf["wn_meet"] = synth([[523.25, 0.0, 0.32], [659.25, 0.16, 0.32], [783.99, 0.32, 0.6], [1046.5, 0.32, 0.6]], 0.42)
	buf["ui_confirm"] = synth([[392.0, 0.0, 0.09], [587.33, 0.07, 0.16]], 0.5, 4)
	buf["ui_deny"] = synth([[196.0, 0.0, 0.14], [155.56, 0.12, 0.24]], 0.45, 6)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	loop = AudioStreamPlayer.new()
	add_child(loop)
	music = AudioStreamPlayer.new()
	add_child(music)
	voice = AudioStreamPlayer.new()
	add_child(voice)
	# every button gives the paper tick (web: the document click listener)
	get_tree().node_added.connect(_on_node)
	_hook(get_tree().root)


## A short sound made of notes [frequency, start s, length s]: a plucked tone with a few overtones, falling away.
## harm: how many overtones (more is brassier).
static func synth(notes: Array, vol := 0.5, harm := 3) -> AudioStreamWAV:
	var rate := 22050
	var end := 0.0
	for n in notes:
		end = maxf(end, float(n[1]) + float(n[2]))
	var count := int((end + 0.05) * rate)
	var mix := PackedFloat32Array()
	mix.resize(count)
	for n in notes:
		var f: float = n[0]
		var at := int(float(n[1]) * rate)
		var n_len := int(float(n[2]) * rate)
		for i in n_len:
			var tt := float(i) / rate
			var env := minf(1.0, tt / 0.008) * exp(-tt * 5.0 / float(n[2]))
			var v := 0.0
			for h in harm:
				v += sin(TAU * f * (h + 1) * tt) / pow(float(h + 1), 1.6)
			if at + i < count:
				mix[at + i] += v * env
	var peak := 0.001
	for x in mix:
		peak = maxf(peak, absf(x))
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		data.encode_s16(i * 2, int(clampf(mix[i] / peak * vol, -1.0, 1.0) * 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


func _hook(n: Node) -> void:
	_on_node(n)
	for c in n.get_children():
		_hook(c)


func _on_node(n: Node) -> void:
	if n is BaseButton and not n.has_meta("no_click"):
		var b: BaseButton = n
		if not b.pressed.is_connected(_click):
			b.pressed.connect(_click)


func _click() -> void:
	sfx("ui_click")


func now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Play a sound effect. prov: where it comes from (quieter the further it is from the screen; -1 everywhere).
## web: sound.js sfx
static func play(name: String, prov := -1, vol := 1.0) -> void:
	if inst:
		inst.sfx(name, prov, vol)


func sfx(name: String, prov := -1, vol := 1.0) -> void:
	if not Settings.sfx_on or not SFX_FILES.has(name) or not buf.has(name):
		return
	var t := now()
	if last.has(name) and t - last[name] < SFX_GAP.get(name, 0.08):
		return
	var near := near_of(prov) if prov >= 0 else 1.0
	if near <= 0.02:
		return
	if name == "ui_error" and t - last_big < 0.8:   # error thunks stay quiet right after a big sound (web: sndQuietFor)
		return
	last[name] = t
	if not (name.begins_with("ui_") or name.begins_with("sel_") or name.begins_with("mv_")) or name == "ui_deny":
		last_big = t   # (ui_deny: a refusal that already sounded, so the error thunk after it stays quiet)
	var p: AudioStreamPlayer = null
	for q in players:
		if not q.playing:
			p = q
			break
	if p == null:
		p = players[0]
		for q in players:
			if q.get_playback_position() > p.get_playback_position():
				p = q
	p.stream = buf[name]
	p.pitch_scale = 1.0 if SFX_STEADY.has(name) else randf_range(0.95, 1.05)
	p.volume_db = linear_to_db(maxf(0.0001, SFX_FILES[name] * near * vol * Settings.sfx_vol))
	p.play()


## How loud something in province p should be, from where the camera looks: 1 on screen, fading to 0 two screens
## away. web: sound.js sndNear
func near_of(p: int) -> float:
	if main == null or main.game == null or main.cam == null or p < 0 or p >= main.game.G.provs.size():
		return 1.0
	var ic: Array = main.game.G.provs[p].ic
	var vs: Vector2 = main.get_viewport().get_visible_rect().size
	var s: Vector2 = (Vector2(ic[0], ic[1]) - main.cam.position) * main.cam.zoom.x + vs / 2
	var dx := maxf(0, absf(s.x - vs.x / 2) - vs.x / 2)
	var dy := maxf(0, absf(s.y - vs.y / 2) - vs.y / 2)
	var off := Vector2(dx, dy).length() / maxf(vs.x, vs.y)
	return maxf(0, 1 - off / 1.2)


## The footsteps or voice that fit a unit. web: sound.js sndKind
static func kind_of(u) -> String:
	if u == null:
		return ""
	if inst and inst.main and inst.main.game and u.kind == inst.main.game.WAYFINDER:
		return "wayfinder"
	if u.kind == Game.MASON:
		return "mason"
	if u.kind == "mage:A":
		return "mage"
	if u.kind == "army" and inst and inst.main and inst.main.game:
		var cav := 0
		var n := 0
		for k in u.troops:
			n += u.troops[k]
			if inst.main.game.DSTATS.get(k, {}).get("cav", false):
				cav += u.troops[k]
		return "cavalry" if cav * 2 > n else "soldier"
	return ""


## Units set off: their footsteps. web: sound.js sndMove
static func move(units: Array) -> void:
	if units.is_empty():
		return
	var k := kind_of(units[0])
	if k != "":
		play("mv_" + ("army" if k == "soldier" else k))


## A warning shown soon after a click or key press: the error thunk (web: ui_error on a refused order).
func on_toast(warn: bool) -> void:
	if warn and now() - last_input < 0.35:
		sfx("ui_error")


func _input(ev: InputEvent) -> void:
	if (ev is InputEventMouseButton or ev is InputEventKey) and ev.pressed:
		last_input = now()
	# M turns the music on or off (web: menu.js), unless you are typing
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_M and not ev.ctrl_pressed and not ev.alt_pressed \
			and not (get_viewport().gui_get_focus_owner() is LineEdit) and not (get_viewport().gui_get_focus_owner() is TextEdit):
		Settings.music_on = not Settings.music_on
		Settings.save_all()


func _process(dt: float) -> void:
	_music(dt)
	var g = main.game if main else null
	if g == null:
		if loop.playing:
			loop.stop()
		return
	_selection()
	if now() >= check_t:
		check_t = now() + 1.0
		_battle_loop(g)
		_watch(g)
	# the clash of blades fades in and out
	var want := loop_vol if Settings.sfx_on and not g.paused else 0.0
	if loop.playing:
		var cur := db_to_linear(loop.volume_db)
		cur = move_toward(cur, want * Settings.sfx_vol, dt / 0.6)
		loop.volume_db = linear_to_db(maxf(0.0001, cur))
		if want <= 0.0 and cur <= 0.001:
			loop.stop()


# web: sound.js sndBattleLoop: the clash of blades loops while one of your battles is on screen
func _battle_loop(g) -> void:
	var near := 0.0
	for b in g.battles:
		if b.start.has(Game.LOCAL):
			near = maxf(near, near_of(b.prov))
	loop_vol = SFX_FILES.bat_blades * near if near > 0.02 else 0.0
	if loop_vol > 0 and not loop.playing and Settings.sfx_on and not g.paused and buf.has("bat_blades"):
		var s: AudioStream = buf.bat_blades.duplicate()
		if s is AudioStreamMP3:
			s.loop = true
		loop.stream = s
		loop.volume_db = linear_to_db(0.0001)
		loop.play()


# web: sound.js sndWatch: a hostile army stepping into your land
func _watch(g) -> void:
	var now_seen := {}
	for v in g.units:
		if v.kind == "army" and v.owner != Game.LOCAL and g.hostile(v.owner, Game.LOCAL) and g.owned(v.prov):
			now_seen["%d:%d" % [v.id, v.prov]] = true
	for k in now_seen:
		if not enemy_seen.has(k):
			sfx("wn_enemy")
			break
	enemy_seen = now_seen


# web: sound.js sndSelection: a voice for what you just selected (adding to a selection stays quiet)
func _selection() -> void:
	var hud = main.hud if main else null
	if hud == null:
		return
	var key := ",".join(hud.selection.map(func(u): return str(u.id)))
	if key == sel_key:
		return
	var was := sel_key
	sel_key = key
	if key == "" or hud.selection.is_empty() or hud.selection[0].owner != Game.LOCAL:
		return
	if was != "" and key.begins_with(was) and key.length() > was.length():
		return
	var k := kind_of(hud.selection[0])
	if k != "":
		sfx("sel_" + ("soldier" if k == "cavalry" else k))


# --- music (web: menu.js musicStart / musicFadeTo / musicTarget, v102.js musicCheckTrack) ---

func _music_want() -> String:
	var g = main.game if main else null
	if g == null or g.tutorial != null:
		return "tavern"
	var r: String = str(g.race_of.get(Game.LOCAL, "realm"))
	return "swamp" if r == "swamp" else "wood" if r == "wood" else "tavern"


func _music(dt: float) -> void:
	var g = main.game if main else null
	var target: float = Settings.music_vol * (0.5 if g != null and g.paused else 1.0) if Settings.music_on else 0.0
	var want := _music_want()
	if track == "":
		track = want
		_load_track(want)
	if want != track and swap_t < 0:
		swap_t = 1.2   # fade out, switch, fade back in
	if swap_t >= 0:
		swap_t -= dt
		music_vol = move_toward(music_vol, 0.0, dt / 1.2)
		if swap_t < 0 or music_vol <= 0.0:
			swap_t = -1.0
			track = want
			_load_track(want)
	else:
		# 3 s to come in the first time, 0.6 s for other changes (web: musicFadeTo)
		var rate := (maxf(target, 0.05) / 3.0) if music_vol < target else (1.0 / 0.6)
		music_vol = move_toward(music_vol, target, dt * rate)
	if music_vol > 0.0005 and not music.playing and music.stream != null:
		music.play()
	elif music_vol <= 0.0005 and music.playing and not Settings.music_on:
		music.stop()
	music.volume_db = linear_to_db(maxf(0.0001, music_vol))


func _load_track(k: String) -> void:
	var path: String = MUSIC_TRACKS[k]
	if not ResourceLoader.exists(path):
		return
	var s: AudioStream = load(path)
	if s is AudioStreamMP3:
		s.loop = true
	music.stream = s
	if music_vol > 0.0005 or Settings.music_on:
		music.play()


## A tutorial step's voice line, when there is one: res://assets/audio/tutorial/t<id>.mp3 (web: tutorial.js
## TUT_AUDIO; the web game has none yet, so the folder is empty until they are recorded).
static func tutorial_voice(id) -> void:
	if inst == null:
		return
	inst.voice.stop()
	var path := "res://assets/audio/tutorial/t%s.mp3" % str(id)
	if not ResourceLoader.exists(path):
		return
	inst.voice.stream = load(path)
	inst.voice.volume_db = linear_to_db(maxf(0.0001, (Settings.sfx_vol if Settings.sfx_on else 0.0)))
	inst.voice.play()
