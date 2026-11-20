extends RefCounted
## Saving and loading: a game saved halfway through a scripted fixture game, loaded and played on, must stay
## identical to the game that was never saved (every snapshot), and match the web game too.

const DIR := "res://tests/fixtures/play/"
const SCENARIOS := ["orders", "train", "roads", "life", "arcane", "death", "armory"]
const CUT := {"armory": 400}   # mid-retrofit, with the Training Order still in the queue


func run() -> Array:
	var errs := []
	for sc in SCENARIOS:
		var fx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "oak_%s.json" % sc))
		var map := RealmGen.scale_world(RealmGen.generate_practice(fx.seed))
		# play the fixture with a save + load in the middle: TestPlay.play takes a hook called after each frame
		var cut: int = CUT.get(sc, int(fx.frames) / 2)
		var e := TestPlay.play(fx, map.duplicate(true), func(g: Game, i: int) -> Game:
			if i != cut:
				return g
			var text := g.save_text()
			var g2 := Game.load_text(text, map.duplicate(true))
			if g2 == null:
				return g
			# the copy must save to the very same text
			if g2.save_text() != text:
				errs.append("%s: a loaded game saves differently" % sc)
			return g2)
		for m in e.slice(0, 4):
			errs.append("%s (saved at frame %d): %s" % [sc, cut, m])
	return errs
