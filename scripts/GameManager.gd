extends Node
#class_name GameManager

static var instance: GameManager

# Player Data Arrays
var active_player_index: int = 0
var total_players: int = 4
var player_suvarnas: Array = [500, 500, 500, 500]
var player_kills: Array = [0, 0, 0, 0]
var player_kingdoms: Array = [[], [], [], []] # Holds node IDs owned by each player

var current_dice_roll: int = 0
var is_waiting_for_input: bool = true

signal turn_changed(player_id: int)
signal dice_rolled(roll_value: int)



func _enter_tree():
	instance = self

func roll_dice() -> int:
	if not is_waiting_for_input:
		return 0

	current_dice_roll = randi_range(1, 6)
	is_waiting_for_input = false
	emit_signal("dice_rolled", current_dice_roll)
	return current_dice_roll

func can_player_enter_hastinapur(player_id: int) -> bool:
	var owned_count = player_kingdoms[player_id].size()
	var kills = player_kills[player_id]
	return (owned_count >= 3 and kills >= 3)

func end_turn():
	active_player_index = (active_player_index + 1) % total_players
	is_waiting_for_input = true
	emit_signal("turn_changed", active_player_index)

# Call this after a pawn finishes moving
func resolve_tile_landing(moving_pawn: Pawn, all_pawns: Array):
	var node = moving_pawn.current_node

	# Skip captures if landing on a Safe Haven or the Start/Throne space
	if node.tile_type == BoardNode.TileType.SAFE_HAVEN or node.tile_type == BoardNode.TileType.THRONE:
		return

	# Check if another player's pawn is already on this node
	for other_pawn in all_pawns:
		if other_pawn != moving_pawn and other_pawn.current_node == node:
			if other_pawn.owner_id != moving_pawn.owner_id:
				execute_vadh_capture(moving_pawn, other_pawn)
				break

func execute_vadh_capture(attacker: Pawn, victim: Pawn):
	print("VADH! Player ", attacker.owner_id, " captured Player ", victim.owner_id, "'s pawn!")
	
	# Increment Kill Count
	player_kills[attacker.owner_id] += 1
	
	# Reset victim pawn back to their Home Base node
	victim.is_inside_ludo = false
	victim.gate_entered_id = -1
	victim.ludo_steps_taken = 0
	
	# Send victim back to Start Node (Node_0)
	var start_node = get_tree().root.get_node("MainBoard/BoardNodes/MonopolyNodes/Node_0")
	victim.set_initial_node(start_node)
