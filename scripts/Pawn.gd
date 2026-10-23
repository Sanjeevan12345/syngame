extends Node2D
class_name Pawn

var owner_id: int = 0
var current_node: BoardNode = null

# Track Journey State
var is_inside_ludo: bool = false
var gate_entered_id: int = -1
var ludo_steps_taken: int = 0

# Signal emitted when pawn finishes moving all dice steps
signal movement_finished(pawn: Pawn)

# Call this to set initial starting position without animation
func set_initial_node(node: BoardNode):
	current_node = node
	global_position = node.global_position

# Steps the pawn forward one node at a time
func move_steps(steps: int):
	for i in range(steps):
		var target_node = get_next_target_node()
		if target_node == null:
			break
			
		current_node = target_node
		if is_inside_ludo:
			ludo_steps_taken += 1

		# Smooth movement animation over 0.2 seconds
		var tween = create_tween()
		tween.tween_property(self, "global_position", current_node.global_position, 0.2)
		await tween.finished
		await get_tree().create_timer(0.05).timeout # Brief pause between steps

	emit_signal("movement_finished", self)

# Determines path direction
func get_next_target_node() -> BoardNode:
	if current_node == null:
		return null

	# Special Logic: Arriving at an Entry Gate from Ludo
	if is_inside_ludo and current_node.tile_type == BoardNode.TileType.ENTRY_GATE:
		if current_node.node_id == gate_entered_id and ludo_steps_taken >= 24:
			# Check win condition readiness in GameManager before taking straight path
			if GameManager.instance.can_player_enter_hastinapur(owner_id):
				return current_node.straight_throne_node

	# Default path forward
	return current_node.next_node
	
func enter_ludo_branch():
	if current_node.tile_type == BoardNode.TileType.ENTRY_GATE and current_node.branch_ludo_node != null:
		is_inside_ludo = true
		gate_entered_id = current_node.node_id
		ludo_steps_taken = 0
		current_node = current_node.branch_ludo_node
		global_position = current_node.global_position
		
