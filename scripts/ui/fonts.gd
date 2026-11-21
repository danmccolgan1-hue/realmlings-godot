class_name Fonts
extends RefCounted
## The game's typefaces (web: game_shell.html --font-display, --font-ui, the outliner's names). Bundled with their
## licenses in assets/fonts so every PC shows the same type:
##   display: Cinzel Decorative (titles, window heads)
##   ui:      Alegreya (everything else; the web game's Cinzel isn't bundled)
##   names:   Alegreya SemiBold (the outliner's unit and province names, in place of the web game's Grenze Gotisch)
## DejaVu Sans stands behind each for the symbols they lack (✓ ✗ ⚔ …).

static var ui: Font
static var bold: Font
static var italic: Font
static var names: Font
static var display: Font
static var display_bold: Font


static func load_all() -> void:
	if ui != null:
		return
	var sym = load("res://assets/fonts/DejaVuSans.ttf")
	var mk := func(path: String) -> Font:
		var f = load(path)
		if f == null:
			return ThemeDB.fallback_font
		if sym != null:
			f.fallbacks = [sym]
		return f
	ui = mk.call("res://assets/fonts/Alegreya-Regular.ttf")
	bold = mk.call("res://assets/fonts/Alegreya-Bold.ttf")
	italic = mk.call("res://assets/fonts/Alegreya-Italic.ttf")
	names = mk.call("res://assets/fonts/Alegreya-SemiBold.ttf")
	display = mk.call("res://assets/fonts/CinzelDecorative-Regular.ttf")
	display_bold = mk.call("res://assets/fonts/CinzelDecorative-Bold.ttf")


## Make Alegreya the default everywhere (controls, rich text and anything drawn with the fallback font).
static func apply() -> void:
	load_all()
	ThemeDB.fallback_font = ui
	var th: Theme = ThemeDB.get_project_theme()
	if th != null:
		th.default_font = ui
		th.set_font("bold_font", "RichTextLabel", bold)
		th.set_font("italics_font", "RichTextLabel", italic)
		th.set_font("bold_italics_font", "RichTextLabel", bold)


## A title in Cinzel Decorative.
static func title(c: Control, heavy := true) -> void:
	load_all()
	c.add_theme_font_override("font", display_bold if heavy else display)
