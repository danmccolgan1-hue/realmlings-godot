class_name HowToWindow
extends Control
## How to Play: the web game's full guide, from the menu and the in-game menu (data: HOWTO_GUIDE, exported from the
## web game by tools/export_howto.py). web: game_shell.html #stHowBody

var win: Dictionary


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	win = UiKit.window("How to Play", 820, func(): close())
	add_child(win.panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(800, 600)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	win.body.add_child(scroll)
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.fit_content = true
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.custom_minimum_size = Vector2(770, 0)
	t.add_theme_color_override("default_color", UiKit.INK)
	t.add_theme_font_size_override("normal_font_size", 16)
	t.add_theme_font_size_override("bold_font_size", 16)
	var items: Array = GameData.c("HOWTO_GUIDE")
	t.text = "\n\n".join(items.map(func(s): return "• " + str(s).replace("[", "[lb]").replace("[lb]b]", "[b]").replace("[lb]/b]", "[/b]")))
	scroll.add_child(t)
	win.panel.hide()


func open() -> void:
	win.panel.show()
	UiKit.center.call_deferred(win.panel)


func close() -> void:
	win.panel.hide()
