extends Button

func _ready():
	pressed.connect(_on_pressed)
	GameManager.instance.turn_changed.connect(_on_turn_changed)

func _on_pressed():
	if GameManager.instance.is_waiting_for_input:
		var roll = GameManager.instance.roll_dice()
		text = "Rolled: " + str(roll)
		
		# Move Player 0's pawn for testing
		var test_pawn = get_tree().root.get_node("MainBoard/Pawns/Pawn_P1")
		test_pawn.move_steps(roll)

func _on_turn_changed(player_id: int):
	text = "Player " + str(player_id + 1) + "'s Turn (Roll)"
