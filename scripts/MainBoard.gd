extends Node2D

@onready var pawn_p1: Pawn = $Pawns/Pawn_P1 as Pawn
@onready var pawn_p2: Pawn = $Pawns/Pawn_P2 as Pawn

# Reference to your 3D Dice Scene
@onready var roll_button: Button = $UI_Layer/RollButton
@onready var dice = $SubViewportContainer/SubViewport/dice_main/Dice

var active_pawn: Pawn

func _ready():
	# 1. Place both pawns at Start (Node_0) on load
	var start_node = $BoardNodes/MonopolyNodes/Node_0
	pawn_p1.set_initial_node(start_node)
	pawn_p2.set_initial_node(start_node)
	
	active_pawn = pawn_p1
	
	roll_button.pressed.connect(_on_roll_button_pressed)
	
	# 2. Connect your 3D dice signal
	# Replace 'roll_completed' with the exact signal name your 3D dice script emits
	
	if dice != null and dice.has_signal("dice_roll_finished"):
		dice.dice_roll_finished.connect(_on_dice_rolled)
		
	print("Checking Dice Node: ", dice)
	
	if dice != null:
		print("Dice node found! Connecting signal...")
		dice.dice_roll_finished.connect(_on_dice_rolled)
	else:
		print("ERROR: Dice node is NULL! Check your SubViewport scene path.")

func _on_roll_button_pressed():
	# Disable the button while the dice is in motion to prevent double-clicking
	roll_button.disabled = true
	
	if dice != null and dice.has_method("trigger_roll"):
		dice.trigger_roll()
	else:
		print("ERROR: Dice node missing trigger_roll method!")
		roll_button.disabled = false # Re-enable if call fails

func _on_dice_rolled(rolled_number: int):
	# Move current pawn forward
	active_pawn.move_steps(rolled_number)
	await active_pawn.movement_finished
	
	print("Pawn landed on: ", active_pawn.current_node.property_name)
	
	# Switch turns and re-enable the button for the next player
	switch_turn()
	roll_button.disabled = false
	
	"""
	print("!!! SIGNAL RECEIVED !!! Dice rolled a: ", rolled_number)
	print("Dice result: ", rolled_number, " | Moving Pawn...")
	
	# Move current pawn forward by the rolled number
	active_pawn.move_steps(rolled_number)
	await active_pawn.movement_finished
	
	
	print("Pawn landed on: ", active_pawn.current_node.property_name)
	
	# Pass turn to the other player for testing
	switch_turn()
	"""
	print("!!! SIGNAL RECEIVED !!! Dice rolled a: ", rolled_number)
	
	
	

func switch_turn():
	if active_pawn == pawn_p1:
		active_pawn = pawn_p2
	else:
		active_pawn = pawn_p1
	print("Switched turn to: ", active_pawn.name)
