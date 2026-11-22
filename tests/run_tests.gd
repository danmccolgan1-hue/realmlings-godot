extends SceneTree
## Headless test runner: godot --headless --path . --script res://tests/run_tests.gd
## Each test file in TESTS has a run() -> Array[String] returning failure messages (empty = pass).

const TESTS := ["res://tests/test_world_gen.gd", "res://tests/test_economy.gd", "res://tests/test_play.gd", "res://tests/test_save.gd", "res://tests/test_tutorial.gd", "res://tests/test_decor.gd", "res://tests/test_setup.gd", "res://tests/test_war.gd", "res://tests/test_ai.gd", "res://tests/test_siege.gd", "res://tests/test_dipl.gd", "res://tests/test_ui.gd", "res://tests/test_replay.gd", "res://tests/test_build.gd", "res://tests/test_races.gd", "res://tests/test_determinism.gd"]

func _initialize() -> void:
	var failures := 0
	# a script that doesn't compile fails the run (its tests could otherwise pass vacuously)
	for dir in ["res://scripts/core/", "res://scripts/gen/", "res://scripts/sim/", "res://scripts/view/", "res://scripts/ui/"]:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".gd"):
				var sc: GDScript = load(dir + f)
				if sc == null or not sc.can_instantiate():
					failures += 1
					print("FAIL does not compile: ", dir + f)
	for path in TESTS:
		var ts: GDScript = load(path)
		if ts == null or not ts.can_instantiate():
			failures += 1
			print("FAIL does not compile: ", path)
			continue
		var t = ts.new()
		var errs: Array = t.run()
		if errs.is_empty():
			print("PASS ", path)
		else:
			failures += errs.size()
			print("FAIL ", path)
			for e in errs.slice(0, 20):
				print("    ", e)
	print("%d test file(s), %d failure(s)" % [TESTS.size(), failures])
	quit(1 if failures > 0 else 0)
