extends RigidBody3D

const FACE_DIRECTIONS = {
	6: Vector3.UP,
	5: Vector3.DOWN,
	4: Vector3.LEFT,
	3: Vector3.RIGHT,
	2: Vector3.FORWARD,
	1: Vector3.BACK
}

var is_rolling: bool = false
var reset_requested: bool = false
var camera: Camera3D = null
var target_camera_pos: Vector3 = Vector3.ZERO
var should_zoom: bool = false

func _ready() -> void:
	reset_requested = true
	is_rolling = true
	camera = get_viewport().get_camera_3d()

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if reset_requested:
		reset_requested = false
		
		# Spawns exactly where you placed it in the editor
		var start_pos = state.transform.origin
		
		# Pre-rotate randomly so it hits the ground at an uneven angle
		var rand_basis = Basis()
		rand_basis = rand_basis.rotated(Vector3.RIGHT, randf_range(0, TAU))
		rand_basis = rand_basis.rotated(Vector3.UP, randf_range(0, TAU))
		rand_basis = rand_basis.rotated(Vector3.FORWARD, randf_range(0, TAU))
		
		state.transform = Transform3D(rand_basis, start_pos)
		
		# CONTROLLED IMPULSE: 
		# We push it downward fast (Y: -4) and minimize horizontal drift (X/Z) so it stays under the camera
		state.linear_velocity = Vector3(randf_range(-0.5, 0.5), -4.0, randf_range(-0.5, 0.5))
		
		# FAST SPIN: High torque forces ensure a quick, violent tumble the moment it hits the floor
		state.angular_velocity = Vector3(randf_range(-20, 20), randf_range(-20, 20), randf_range(-20, 20))

func _physics_process(_delta: float) -> void:
	# FAST DETECT: Increased velocity threshold to 0.05 so the zoom triggers instantly
	# when the heavy tumbling stops, bypassing micro-shakes
	if is_rolling and not reset_requested:
		if linear_velocity.length() < 0.05 and angular_velocity.length() < 0.05:
			is_rolling = false
			calculate_winning_face()

func _process(delta: float) -> void:
	if should_zoom and camera:
		target_camera_pos = global_position + Vector3(0.0, 1.5, 0.3)
		camera.global_position = camera.global_position.lerp(target_camera_pos, 5.0 * delta)
		
		var look_target = camera.global_transform.looking_at(global_position, Vector3.UP)
		camera.global_transform = camera.global_transform.interpolate_with(look_target, 9.0 * delta)

func calculate_winning_face() -> void:
	var highest_dot: float = -1.0
	var landed_number: int = 1
	
	for face_value in FACE_DIRECTIONS:
		var local_dir = FACE_DIRECTIONS[face_value]
		var global_dir = global_transform.basis * local_dir
		var dot = global_dir.dot(Vector3.UP)
		
		if dot > highest_dot:
			highest_dot = dot
			landed_number = face_value
			
	print("Dice landed swiftly on: ", landed_number)
	should_zoom = true
	
	
# Inside your 3D Dice script after the roll finishes and number is determined
func on_roll_complete(rolled_number: int):
	# 1. Update GameManager state
	GameManager.instance.current_dice_roll = rolled_number
	GameManager.instance.is_waiting_for_input = false
	
	# 2. Emit signal or notify main board to move the active player's pawn
	emit_signal("dice_roll_finished", rolled_number)
