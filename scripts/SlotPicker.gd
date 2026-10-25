class_name SlotPicker
extends PanelContainer
# Parchment panel listing the save slots with a Save or Load button on each.
# Used by the main board (save and load) and the opening page (load only).
# Saving over a used slot needs a second click to confirm.

signal slot_chosen(slot: int)

enum Mode { SAVE, LOAD }

var mode: Mode = Mode.LOAD
var title: Label
var rows: VBoxContainer

func _init():
	theme = preload("res://scenes/main_ui_theme.tres")
	visible = false
	custom_minimum_size = Vector2(760, 0)

	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)

	title = Label.new()
	title.theme_type_variation = &"ParchmentLabel"
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	box.add_child(rows)

	var close = Button.new()
	close.text = "Close"
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(hide)
	box.add_child(close)

func open(new_mode: Mode):
	mode = new_mode
	title.text = "Save the Saga" if mode == Mode.SAVE else "Continue a Saga"
	refresh()
	show()

func refresh():
	for child in rows.get_children():
		child.queue_free()
	for slot in range(1, SaveSystem.SLOT_COUNT + 1):
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		rows.add_child(row)

		# Long summaries scroll sideways instead of stretching the panel
		var text_scroll = ScrollContainer.new()
		text_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		text_scroll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(text_scroll)

		var label = Label.new()
		label.theme_type_variation = &"ParchmentLabel"
		label.add_theme_font_size_override("font_size", 15)
		label.text = "Slot %d:  %s" % [slot, SaveSystem.describe(slot)]
		text_scroll.add_child(label)

		var button = Button.new()
		button.custom_minimum_size = Vector2(110, 0)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if mode == Mode.SAVE:
			button.text = "Save"
			button.pressed.connect(_on_save_pressed.bind(slot, button))
		else:
			button.text = "Load"
			button.disabled = not SaveSystem.has_save(slot)
			button.pressed.connect(func(): slot_chosen.emit(slot))
		row.add_child(button)

func _on_save_pressed(slot: int, button: Button):
	if SaveSystem.has_save(slot) and button.text != "Overwrite?":
		button.text = "Overwrite?"
		return
	slot_chosen.emit(slot)
