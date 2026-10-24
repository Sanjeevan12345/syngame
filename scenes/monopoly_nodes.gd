extends Node2D

@export var node_scene: PackedScene
@export var board_center: Vector2 = Vector2(560, 536)
@export var board_scale: Vector2 = Vector2(0.6, 0.6)

var board_positions: Array[Vector2] = []

func _ready() -> void:
	# Generate 60 nodes distributed evenly around a rectangle matching the outer track
	# Adjust width and height (e.g., 850x850) to fit your board's outer square border exactly
	board_positions = generate_rectangular_track(60, 840, 840, board_center, board_scale)
	
	if not node_scene:
		printerr("Node scene not assigned!")
		return

	for i in range(board_positions.size()):
		var new_node = node_scene.instantiate() as Node2D
		if new_node:
			new_node.position = board_positions[i]
			new_node.name = "Node_%d" % i
			add_child(new_node)

func generate_rectangular_track(total_nodes: int, board_w: float, board_h: float, center: Vector2, scl: Vector2) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	var nodes_per_side = total_nodes / 4 # 15 nodes per side for 60 total
	
	var half_w = (board_w / 2.0)
	var half_h = (board_h / 2.0)
	
	for i in range(total_nodes):
		var local_pos = Vector2.ZERO
		var side = i / nodes_per_side
		var progress = float(i % nodes_per_side) / float(nodes_per_side)
		
		match side:
			0: # Top side (Left to Right)
				local_pos = Vector2(-half_w + (board_w * progress), -half_h)
			1: # Right side (Top to Bottom)
				local_pos = Vector2(half_w, -half_h + (board_h * progress))
			2: # Bottom side (Right to Left)
				local_pos = Vector2(half_w - (board_w * progress), half_h)
			3: # Left side (Bottom to Top)
				local_pos = Vector2(-half_w, half_h - (board_h * progress))
		
		# Apply board scale and center offset
		var final_x = center.x + (local_pos.x * scl.x)
		var final_y = center.y + (local_pos.y * scl.y)
		
		positions.append(Vector2(final_x, final_y))
		
	return positions
