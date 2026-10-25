extends Control
# Title screen: pick 2-4 players, then start the game on the main board.

const MAIN_BOARD_SCENE = "res://scenes/main_board.tscn"

@onready var player_buttons: Array = [
	$Scroll/Content/PlayerChoices/Players2,
	$Scroll/Content/PlayerChoices/Players3,
	$Scroll/Content/PlayerChoices/Players4,
]
@onready var start_button: Button = $Scroll/Content/StartButton
@onready var continue_button: Button = $Scroll/Content/ContinueButton
@onready var quit_button: Button = $Scroll/Content/QuitButton
# Invisible button over the gear painted in the background art
@onready var settings_button: Button = $SettingsButton
@onready var settings_panel: PanelContainer = $SettingsPanel
@onready var mute_toggle: CheckButton = $SettingsPanel/Settings/MuteToggle
@onready var volume_slider: HSlider = $SettingsPanel/Settings/VolumeRow/VolumeSlider

var player_count: int = 2
var slot_picker: SlotPicker

const FADE_IN_TIME: float = 0.8
const RULE_BOOK_SCENE = preload("res://scenes/rule_book.tscn")
const ICON_GOLD = Color(0.9, 0.72, 0.36)

var rule_book: RuleBook

func _ready():
	# Fades in from black, picking up where the intro video's fade-out left off
	modulate = Color.BLACK
	create_tween().tween_property(self, "modulate", Color.WHITE, FADE_IN_TIME)

	# Only one player count can be chosen at a time
	var group = ButtonGroup.new()
	for i in player_buttons.size():
		var button: Button = player_buttons[i]
		button.toggle_mode = true
		button.button_group = group
		button.pressed.connect(func(): player_count = i + 2)
	player_buttons[0].button_pressed = true

	start_button.pressed.connect(_on_start_pressed)

	# Continue opens the save slots; it's off until a game has been saved
	continue_button.disabled = not SaveSystem.has_any_save()
	slot_picker = SlotPicker.new()
	slot_picker.slot_chosen.connect(_on_slot_chosen)
	add_child(slot_picker)
	continue_button.pressed.connect(func():
		slot_picker.open(SlotPicker.Mode.LOAD)
		slot_picker.reset_size()
		slot_picker.position = (size - slot_picker.size) / 2)
	quit_button.pressed.connect(func(): get_tree().quit())

	# Music settings reflect (and update) the Music autoload, which saves them
	mute_toggle.button_pressed = Music.muted
	volume_slider.value = Music.volume
	mute_toggle.toggled.connect(Music.set_muted)
	volume_slider.value_changed.connect(Music.set_volume)
	settings_button.pressed.connect(func(): settings_panel.visible = not settings_panel.visible)
	build_rules_button()

# "How to play": a palm-leaf book icon beside the gear, opening the rule book
func build_rules_button():
	rule_book = RULE_BOOK_SCENE.instantiate()
	add_child(rule_book)

	var button = Button.new()
	button.flat = true
	button.position = Vector2(84, 26)
	button.size = Vector2(56, 50)
	button.tooltip_text = "How to play"
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.draw.connect(draw_rules_icon.bind(button))
	button.mouse_entered.connect(button.queue_redraw)
	button.mouse_exited.connect(button.queue_redraw)
	button.pressed.connect(rule_book.open)
	add_child(button)

# Two stacked palm leaves with a cord through them; brighter on hover
func draw_rules_icon(button: Button):
	var color = ICON_GOLD.lightened(0.3) if button.is_hovered() else ICON_GOLD
	var leaf = StyleBoxFlat.new()
	leaf.bg_color = Color(color, 0.25)
	leaf.border_color = color
	leaf.set_border_width_all(2)
	leaf.set_corner_radius_all(6)
	for i in 3:
		button.draw_style_box(leaf, Rect2(Vector2(6, 12 + i * 9), Vector2(44, 12)))
	button.draw_line(Vector2(13, 8), Vector2(13, 46), color, 2.0, true)
	button.draw_line(Vector2(43, 8), Vector2(43, 46), color, 2.0, true)

func _on_slot_chosen(slot: int):
	var data = SaveSystem.read(slot)
	if data.is_empty():
		return
	GameManager.instance.pending_load = data
	GameManager.instance.play_board_intro = true
	get_tree().change_scene_to_file(MAIN_BOARD_SCENE)

func _on_start_pressed():
	GameManager.instance.selected_player_count = player_count
	GameManager.instance.play_board_intro = true
	get_tree().change_scene_to_file(MAIN_BOARD_SCENE)
