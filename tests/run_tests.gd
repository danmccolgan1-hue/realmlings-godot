extends SceneTree
## Headless test runner: godot --headless --path . --script res://tests/run_tests.gd
## Each test file in TESTS has a run() -> Array[String] returning failure messages (empty = pass).

const TESTS := ["res://tests/test_world_gen.gd", "res://tests/test_economy.gd", "res://tests/test_play.gd"]

func _initialize() -> void:
	var failures := 0
	for path in TESTS:
		var t = load(path).new()
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
