extends Node3D

signal dice_roll_finished(rolled_number: int)

# Both sticks showing the blank face counts as 12
const DOUBLE_ZERO_SCORE = 12

# Sticks are carried just above the dice box's rim (2.6) while dragged,
# and kept over its inside (inner walls at +/-4.9; a stick is 3 long)
const HOLD_HEIGHT = 4.0
const HOLD_LIMIT = 3.0
const DIE_OFFSETS = [Vector3(-0.7, 0, 0), Vector3(0.7, 0, 0)]

# Fixed camera for the whole game: over the centre of the container
# (about 12.6 x 12.6 including its walls), framing the whole thing
const OVERVIEW_CAMERA_POS = Vector3(0.0, 11.5, 3.3)
const OVERVIEW_LOOK_AT = Vector3.ZERO

# Throw speed comes from the last 0.1 s of mouse movement before release
const THROW_SAMPLE_WINDOW = 0.1
const MAX_THROW_SPEED = 10.0

@onready var dice: Array = [$PasaDie1, $PasaDie2]
@onready var camera: Camera3D = $Camera3D

var is_holding: bool = false
var is_rolling: bool = false
var hold_samples: Array = [] # [time_seconds, world_position] pairs

# Dice-roll sound effects; one random clip plays when the sticks land in the container
const LANDING_SOUNDS = [
	preload("res://assets/SFXs/dice roll1.mp3"),
	preload("res://assets/SFXs/dice roll2.mp3"),
	preload("res://assets/SFXs/dice roll3.mp3"),
	preload("res://assets/SFXs/dice roll4.mp3"),
	preload("res://assets/SFXs/dice roll5.mp3"),
	preload("res://assets/SFXs/dice roll6.mp3"),
	preload("res://assets/SFXs/dice roll7.mp3"),
	preload("res://assets/SFXs/dice roll8.mp3"),
	preload("res://assets/SFXs/dice roll9.mp3"),
]
# Each clip opens with silence before its first hit (measured, in seconds). Playback
# starts LANDING_PREROLL before that hit so the sound lands with the impact.
const LANDING_SOUND_ONSETS = [0.27, 0.50, 0.46, 0.55, 0.34, 0.44, 0.25, 0.27, 0.42]
const LANDING_PREROLL = 0.02
var landing_player: AudioStreamPlayer
var landing_sound_played: bool = false # Once per throw
var last_landing_sound: int = -1

func _ready() -> void:
	# The camera never moves: it starts and stays on the container overview
	camera.global_transform = Transform3D(Basis(), OVERVIEW_CAMERA_POS).looking_at(OVERVIEW_LOOK_AT, Vector3.UP)

	landing_player = AudioStreamPlayer.new()
	add_child(landing_player)
	for die in dice:
		die.body_entered.connect(_on_die_body_entered)

# Plays one random dice-roll clip the instant a thrown stick first hits the
# container, skipping the clip's silent lead-in so the hit is heard right away.
func _on_die_body_entered(body: Node) -> void:
	if not is_rolling or landing_sound_played or not body is StaticBody3D:
		return
	landing_sound_played = true

	# Never the same clip twice in a row
	var choices = range(LANDING_SOUNDS.size()).filter(func(i): return i != last_landing_sound)
	last_landing_sound = choices.pick_random()
	landing_player.stream = LANDING_SOUNDS[last_landing_sound]
	landing_player.pitch_scale = randf_range(0.95, 1.05)
	landing_player.play(maxf(LANDING_SOUND_ONSETS[last_landing_sound] - LANDING_PREROLL, 0.0))

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
	landing_sound_played = false
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
	on_roll_complete(total)

func on_roll_complete(rolled_number: int) -> void:
	# 1. Update GameManager state
	GameManager.instance.current_dice_roll = rolled_number
	GameManager.instance.is_waiting_for_input = false

	# 2. Notify the main board to move the active player's pawn
	emit_signal("dice_roll_finished", rolled_number)
