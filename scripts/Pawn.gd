extends Node2D
class_name Pawn

@export var owner_id: int = 0
var current_node: BoardNode = null

signal movement_finished(pawn: Pawn)

# Call this on setup to place the pawn on the starting tile without animating
func set_initial_node(node: BoardNode):
	current_node = node
	global_position = node.global_position

# Moves the pawn step-by-step along the Monopoly perimeter loop
func move_steps(steps: int):
	for i in range(steps):
		if current_node == null or current_node.next_node == null:
			print("Error: Unlinked node encountered!")
			break
			
		# Advance to next Monopoly node
		current_node = current_node.next_node
		
		# Smooth sliding animation over 0.25 seconds per space
		var tween = create_tween()
		tween.tween_property(self, "global_position", current_node.global_position, 0.25)
		await tween.finished
		await get_tree().create_timer(0.05).timeout # Brief pause between steps

	emit_signal("movement_finished", self)
