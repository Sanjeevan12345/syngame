extends Node3D

signal dice_roll_finished(rolled_number: int)

# Both sticks showing the blank face counts as 12
const DOUBLE_ZERO_SCORE = 12

# Sticks are carried just above the dice container's rim (3.26) while dragged,
# and kept over its inside (inner walls at +/-4.9; a stick is 3 long)
const HOLD_HEIGHT = 4.0
const HOLD_LIMIT = 3.0
const DIE_OFFSETS = [Vector3(-0.7, 0, 0), Vector3(0.7, 0, 0)]

# After a roll the camera eases to this view over the centre of the container
# (about 12 x 12 including its walls), framing the whole thing
const OVERVIEW_CAMERA_POS = Vector3(0.0, 10.5, 3.0)
const OVERVIEW_LOOK_AT = Vector3.ZERO
const CAMERA_SPEED_SCALE = 0.75 # 1.0 = original camera animation speed

# Throw speed comes from the last 0.1 s of mouse movement before release
const THROW_SAMPLE_WINDOW = 0.1
const MAX_THROW_SPEED = 10.0

@onready var dice: Array = [$PasaDie1, $PasaDie2]
@onready var camera: Camera3D = $Camera3D

var is_holding: bool = false
var is_rolling: bool = false
# The camera starts at its editor position; after the first roll it moves to the
# overview and stays there for the rest of the game
var should_zoom: bool = false
var hold_samples: Array = [] # [time_seconds, world_position] pairs

# Picks up both sticks under the cursor. screen_pos is in this viewport's pixels.
func begin_hold(screen_pos: Vector2) -> bool:
	if is_rolling or is_holding:
		return false

	is_holding = true
	hold_samples.clear()
	for die in dice:
		die.pick_up()
	hold_to(screen_pos)
	return true

func hold_to(screen_pos: Vector2) -> void:
	if not is_holding:
		return

	var hit = Plane(Vector3.UP, HOLD_HEIGHT).intersects_ray(
		camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos))
	if hit == null:
		return

	var pos: Vector3 = hit
	pos.x = clampf(pos.x, -HOLD_LIMIT, HOLD_LIMIT)
	pos.z = clampf(pos.z, -HOLD_LIMIT, HOLD_LIMIT)

	for i in dice.size():
		dice[i].hold_at(pos + DIE_OFFSETS[i])

	hold_samples.append([Time.get_ticks_msec() / 1000.0, pos])

func release_hold() -> void:
	if not is_holding:
		return
	is_holding = false

	# Only movement just before release counts, so pausing then letting go drops the sticks
	var now = Time.get_ticks_msec() / 1000.0
	var recent = hold_samples.filter(func(s): return now - s[0] <= THROW_SAMPLE_WINDOW)

	var velocity = Vector3.ZERO
	if recent.size() >= 2:
		var dt = maxf(recent[-1][0] - recent[0][0], 0.01)
		velocity = (recent[-1][1] - recent[0][1]) / dt
	velocity = velocity.limit_length(MAX_THROW_SPEED)
	velocity.y = -2.0

	is_rolling = true
	for die in dice:
		die.release(velocity)

func _physics_process(_delta: float) -> void:
	# Wait until BOTH sticks are still, so one knocking the other can't change a result
	if not is_rolling:
		return
	for die in dice:
		if not die.is_settled():
			return

	is_rolling = false
	calculate_score()

func calculate_score() -> void:
	var faces: Array = []
	var total: int = 0
	for die in dice:
		var face = die.get_up_face()
		faces.append(face)
		total += face

	if total == 0:
		total = DOUBLE_ZERO_SCORE

	print("Pasa landed on: ", faces, " | Score: ", total)
	should_zoom = true
	on_roll_complete(total)

func _process(delta: float) -> void:
	if should_zoom and camera:
		# Settle into an overview centred on the container, showing all of it
		camera.global_position = camera.global_position.lerp(OVERVIEW_CAMERA_POS, 5.0 * CAMERA_SPEED_SCALE * delta)

		var look_target = camera.global_transform.looking_at(OVERVIEW_LOOK_AT, Vector3.UP)
		camera.global_transform = camera.global_transform.interpolate_with(look_target, 9.0 * CAMERA_SPEED_SCALE * delta)

func on_roll_complete(rolled_number: int) -> void:
	# 1. Update GameManager state
	GameManager.instance.current_dice_roll = rolled_number
	GameManager.instance.is_waiting_for_input = false

	# 2. Notify the main board to move the active player's pawn
	emit_signal("dice_roll_finished", rolled_number)
