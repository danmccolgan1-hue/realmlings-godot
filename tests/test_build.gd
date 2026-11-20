extends RefCounted
## Shipping: saves carry their version and the build that wrote them; an older save still loads, a newer one is
## refused with a reason; the Windows export preset points at files that exist.

func run() -> Array:
	var errs := []
	var g := Game.new_practice("moss", "cormac")
	var d: Dictionary = SaveCodec.from_text(g.save_text())
	if int(d.version) != Game.SAVE_VERSION or str(d.get("build", "")) != str(ProjectSettings.get_setting("application/config/version")):
		errs.append("save: version %s, build %s" % [d.version, d.get("build")])
	# a version-1 save, from before the fields this build added
	var old := d.duplicate(true)
	old.version = 1
	old.erase("build")
	for f in ["debug_cap", "debug_tech", "reveal_all", "rec", "gift_vault", "quakes"]:
		old.erase(f)
	var g1 := Game.from_save(old)
	if g1 == null:
		errs.append("save: a version-1 save doesn't load")
	elif g1.debug_cap != 0 or not g1.rec.is_empty() or g1.capital != g.capital:
		errs.append("save: a version-1 save loads wrong (debug_cap %s, rec %s, capital %d vs %d)" % [g1.debug_cap, g1.rec, g1.capital, g.capital])
	# a save from a newer build
	var newer := d.duplicate(true)
	newer.version = Game.SAVE_VERSION + 1
	newer.build = "9.9.9"
	var why := Game.save_why(SaveCodec.to_text(newer))
	if not why.contains("newer version") or not why.contains("9.9.9"):
		errs.append("save: a newer save's reason: '%s'" % why)
	if Game.from_save(newer) != null:
		errs.append("save: a newer save loads")
	# the export preset
	var cfg := ConfigFile.new()
	if cfg.load("res://export_presets.cfg") != OK:
		errs.append("export: no export_presets.cfg")
	else:
		var icon := str(cfg.get_value("preset.0.options", "application/icon", ""))
		if icon == "" or not FileAccess.file_exists(icon):
			errs.append("export: the Windows icon '%s' is missing" % icon)
		var ver := str(cfg.get_value("preset.0.options", "application/product_version", ""))
		if not ver.begins_with(str(ProjectSettings.get_setting("application/config/version"))):
			errs.append("export: product version %s doesn't match the game's %s" % [ver, ProjectSettings.get_setting("application/config/version")])
		for x in ["tests/*", "tools/*", "reference/*"]:
			if not str(cfg.get_value("preset.0", "exclude_filter", "")).contains(x):
				errs.append("export: %s isn't left out of the build" % x)
	return errs
