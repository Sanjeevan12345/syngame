extends Control
# Title screen: pick 2-4 players, then start the game on the main board.

const MAIN_BOARD_SCENE = "res://scenes/main_board.tscn"

@onready var player_buttons: Array = [
	$Scroll/Content/PlayerChoices/Players2,
	$Scroll/Content/PlayerChoices/Players3,
	$Scroll/Content/PlayerChoices/Players4,
]
@onready var start_button: Button = $Scroll/Content/StartButton
@onready var quit_button: Button = $Scroll/Content/QuitButton

var player_count: int = 2

func _ready():
	# Only one player count can be chosen at a time
	var group = ButtonGroup.new()
	for i in player_buttons.size():
		var button: Button = player_buttons[i]
		button.toggle_mode = true
		button.button_group = group
		button.pressed.connect(func(): player_count = i + 2)
	player_buttons[0].button_pressed = true

	start_button.pressed.connect(_on_start_pressed)
	quit_button.pressed.connect(func(): get_tree().quit())

func _on_start_pressed():
	GameManager.instance.selected_player_count = player_count
	get_tree().change_scene_to_file(MAIN_BOARD_SCENE)
