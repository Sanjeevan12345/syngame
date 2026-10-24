extends RigidBody3D

# Pip count on each long face, keyed by that face's local outward normal.
# The stick's long axis is local Z, so the end caps are never read.
const FACE_DIRECTIONS = {
	0: Vector3.UP,
	1: Vector3.RIGHT,
	2: Vector3.DOWN,
	3: Vector3.LEFT
}

var release_requested: bool = false
var throw_velocity: Vector3 = Vector3.ZERO

# Straightens the stick along Z with a random roll so held sticks never overlap
func pick_up() -> void:
	freeze = true
	global_transform.basis = Basis(Vector3.BACK, randf_range(0, TAU))

# Pins the stick in place while the player is dragging it
func hold_at(pos: Vector3) -> void:
	freeze = true
	global_position = pos

# Lets go of the stick with the velocity of the player's throw
func release(velocity: Vector3) -> void:
	freeze = false
	sleeping = false
	throw_velocity = velocity
	release_requested = true

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if release_requested:
		release_requested = false
		state.linear_velocity = throw_velocity

		# Spin mostly around the long axis so the stick tumbles across its four faces.
		# The spin is always random, so how hard you throw never picks the result.
		var spin_dir = 1.0 if randf() < 0.5 else -1.0
		var spin_speed = clampf(15.0 + throw_velocity.length() * 1.5, 15.0, 30.0)
		state.angular_velocity = state.transform.basis.z * spin_speed * randf_range(0.8, 1.2) * spin_dir \
			+ Vector3(randf_range(-3, 3), randf_range(-3, 3), randf_range(-3, 3))

func is_settled() -> bool:
	return not release_requested and not freeze \
		and linear_velocity.length() < 0.05 and angular_velocity.length() < 0.05

func get_up_face() -> int:
	var highest_dot: float = -1.0
	var landed_face: int = 0

	for face_value in FACE_DIRECTIONS:
		var global_dir = global_transform.basis * FACE_DIRECTIONS[face_value]
		var dot = global_dir.dot(Vector3.UP)

		if dot > highest_dot:
			highest_dot = dot
			landed_face = face_value

	return landed_face
