extends Node2D
class_name Pawn

# Where the pawn is on its journey to Vaikuntha
enum PathState { OUTER, LUDO, HOME_STRETCH, VAIKUNTHA }

# What a pawn does when it is back at its entry tip after a full Ludo lap
enum LapRoute { UNDECIDED, HOME, LOOP_AGAIN, EXIT }

# Tiles in one full lap of the inner Ludo track
const LUDO_CIRCUIT_LENGTH: int = 72

# Pawns shrink on the inner board, where tiles are much closer together
const OUTER_SCALE: float = 0.2
const INNER_SCALE: float = 0.1

@export var owner_id: int = 0
@export var pawn_index: int = 0 # Which of the owner's 3 pawns this is (0-2)
var current_node: BoardNode = null

var path_state: PathState = PathState.OUTER
var entry_node: BoardNode = null # Ludo arm tip this pawn entered on; also its home junction
var entry_gate: BoardNode = null # Outer-ring gate the pawn came in through; its exit back out
var lap_route: LapRoute = LapRoute.UNDECIDED
var ludo_steps: int = 0          # Ludo track tiles moved since entering
var divert_at_gate: bool = false # Next step leaves the outer ring through the current gate

# Small per-pawn shift so pawns sharing a tile don't hide each other
var visual_offset: Vector2 = Vector2.ZERO

signal movement_finished(pawn: Pawn)
signal step_finished(pawn: Pawn, node: BoardNode) # Fired on every tile passed or landed on

# Call this on setup to place the pawn on the starting tile without animating
func set_initial_node(node: BoardNode):
	current_node = node
	scale = get_board_scale()
	global_position = node.global_position + get_board_offset()

func is_on_inner_board() -> bool:
	return path_state != PathState.OUTER

func get_board_scale() -> Vector2:
	return Vector2.ONE * (INNER_SCALE if is_on_inner_board() else OUTER_SCALE)

# Shared-tile offset, scaled down with the pawn on the inner board
func get_board_offset() -> Vector2:
	return visual_offset * (INNER_SCALE / OUTER_SCALE if is_on_inner_board() else 1.0)

# Sends a captured pawn back to Start; it has to re-enter through a gate
func reset_to_start(start_node: BoardNode):
	path_state = PathState.OUTER
	entry_node = null
	entry_gate = null
	ludo_steps = 0
	lap_route = LapRoute.UNDECIDED
	divert_at_gate = false
	set_initial_node(start_node)

# Animated character art: each sheet is a 4x4 grid of 400x400 frames.
# "idle" and "move" come from the moving sheet (rows 1-2 standing, rows 3-4
# walking); "fight" is the sword-swing part of the fighting sheet.
const SHEET_COLUMNS: int = 4
const FRAME_SIZE: int = 400
const FRAME_INSET: int = 6 # Skips the faint grid lines drawn between frames
const CHARACTERS = [
	{
		"moving": preload("res://assets/pawn1_moving.png"),
		"fighting": preload("res://assets/pawn1_fighting.png"),
		"fight_frames": [8, 9, 10, 11, 12, 13, 14, 15],
	},
	{
		"moving": preload("res://assets/pawn2_moving.png"),
		"fighting": preload("res://assets/pawn2_fighting.png"),
		"fight_frames": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
	},
]
const IDLE_FRAMES = [0, 1, 2, 3, 4, 5, 6, 7]
const MOVE_FRAMES = [8, 9, 10, 11, 12, 13, 14, 15]
const SPRITE_SCALE: float = 0.9

# SpriteFrames are built once per character and shared by every pawn using it
static var frames_cache: Dictionary = {}

@export var character: int = 0 # Index into CHARACTERS; set before the pawn enters the tree
var player_color: Color = Color.WHITE # Ring drawn under the pawn's feet

@onready var sprite: AnimatedSprite2D = $Sprite
var pulse_tween: Tween = null

func _ready():
	sprite.sprite_frames = get_character_frames(character)
	sprite.scale = Vector2.ONE * SPRITE_SCALE
	sprite.play("idle")

static func get_character_frames(index: int) -> SpriteFrames:
	if frames_cache.has(index):
		return frames_cache[index]
	var sheets = CHARACTERS[index]
	var frames = SpriteFrames.new()
	frames.remove_animation("default")
	add_sheet_animation(frames, "idle", sheets["moving"], IDLE_FRAMES, 6.0, true)
	add_sheet_animation(frames, "move", sheets["moving"], MOVE_FRAMES, 12.0, true)
	add_sheet_animation(frames, "fight", sheets["fighting"], sheets["fight_frames"], 14.0, false)
	frames_cache[index] = frames
	return frames

static func add_sheet_animation(frames: SpriteFrames, anim: String, sheet: Texture2D, indices: Array, fps: float, loop: bool):
	frames.add_animation(anim)
	frames.set_animation_speed(anim, fps)
	frames.set_animation_loop(anim, loop)
	for i in indices:
		var atlas = AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(
			(i % SHEET_COLUMNS) * FRAME_SIZE + FRAME_INSET,
			(i / SHEET_COLUMNS) * FRAME_SIZE + FRAME_INSET,
			FRAME_SIZE - FRAME_INSET * 2, FRAME_SIZE - FRAME_INSET * 2)
		frames.add_frame(anim, atlas)

# Colored ring under the feet shows which player owns the pawn
func _draw():
	draw_set_transform(Vector2(0, FRAME_SIZE * SPRITE_SCALE * 0.45), 0, Vector2(1, 0.35))
	draw_arc(Vector2.ZERO, 110, 0, TAU, 40, player_color, 28)

# Swings the weapon once (used when capturing), then returns to standing
func play_fight():
	sprite.play("fight")
	await sprite.animation_finished
	sprite.play("idle")

# Pulses the pawn while it can be clicked to move
func set_selectable(selectable: bool):
	if pulse_tween:
		pulse_tween.kill()
		pulse_tween = null
	sprite.scale = Vector2.ONE * SPRITE_SCALE

	if selectable:
		pulse_tween = create_tween().set_loops()
		pulse_tween.tween_property(sprite, "scale", Vector2.ONE * SPRITE_SCALE * 1.15, 0.4)
		pulse_tween.tween_property(sprite, "scale", Vector2.ONE * SPRITE_SCALE, 0.4)

# True if a global (board) position falls on this pawn's character. The figure
# fills roughly the middle half of each frame's width.
func contains_point(global_point: Vector2) -> bool:
	var size = Vector2(FRAME_SIZE, FRAME_SIZE) * Vector2(0.5, 0.95)
	return Rect2(-size / 2, size).has_point(sprite.to_local(global_point))

func is_on_gate() -> bool:
	return path_state == PathState.OUTER \
		and current_node.tile_type == BoardNode.TileType.ENTRY_GATE \
		and current_node.branch_ludo_node != null

# Picks the tile this pawn moves to next, following its path state
func get_next_node() -> BoardNode:
	match path_state:
		PathState.OUTER:
			if divert_at_gate:
				return current_node.branch_ludo_node
		PathState.LUDO:
			# At the junction after a full lap: turn home or leave through the entry gate
			if is_at_lap_junction():
				match lap_route:
					LapRoute.HOME:
						return entry_node.home_stretch_node
					LapRoute.EXIT:
						return entry_gate
		PathState.VAIKUNTHA:
			return null
	return current_node.next_node

# True when the pawn is back on its entry tip having completed a full lap
func is_at_lap_junction() -> bool:
	return path_state == PathState.LUDO and current_node == entry_node \
		and ludo_steps >= LUDO_CIRCUIT_LENGTH

# True when the pawn stopped on an arm tip it may leave through. A pawn can't exit
# through the gate it just came in by until it has moved; lap completions at the
# entry tip are handled by the lap prompt instead.
func can_exit_here() -> bool:
	if path_state != PathState.LUDO or current_node.exit_gate_node == null:
		return false
	if current_node == entry_node and ludo_steps == 0:
		return false
	return not is_at_lap_junction()

# First Entry Gate ahead of this pawn on the outer ring
func find_next_gate() -> BoardNode:
	var node = current_node.next_node
	while node != null and node != current_node:
		if node.tile_type == BoardNode.TileType.ENTRY_GATE and node.branch_ludo_node != null:
			return node
		node = node.next_node
	return null

# Card effect: jump to a gate and enter the Ludo board there, as a normal entry would
func enter_ludo_through(gate: BoardNode):
	set_initial_node(gate)
	divert_at_gate = true
	await step_to(gate.branch_ludo_node)
	sprite.play("idle")

# Tiles from a node to Vaikuntha along a Home Stretch, counting the Vaikuntha tile itself
func count_steps_to_vaikuntha(from: BoardNode) -> int:
	var steps = 0
	var node = from
	while node != null and node.tile_type != BoardNode.TileType.THRONE:
		node = node.next_node
		steps += 1
	return steps

# Exact steps this pawn needs to land on Vaikuntha, or -1 if it isn't heading
# there (outer ring, exiting, or a lap that won't qualify for the Home Stretch).
# qualified: whether the owner currently meets the Home Stretch requirements.
func distance_to_vaikuntha(qualified: bool) -> int:
	match path_state:
		PathState.VAIKUNTHA:
			return 0
		PathState.HOME_STRETCH:
			return count_steps_to_vaikuntha(current_node)
		PathState.LUDO:
			var home_length = 1 + count_steps_to_vaikuntha(entry_node.home_stretch_node)
			if is_at_lap_junction():
				return home_length if lap_route == LapRoute.HOME else -1
			if qualified:
				return (LUDO_CIRCUIT_LENGTH - ludo_steps) + home_length
	return -1

# A pawn can't move once in Vaikuntha, and must roll exactly what's needed to reach it
func can_move(steps: int, qualified: bool) -> bool:
	if path_state == PathState.VAIKUNTHA:
		return false
	var distance = distance_to_vaikuntha(qualified)
	return distance < 0 or steps <= distance

# Moves one tile and updates the path state for the tile entered
func step_to(node: BoardNode):
	match path_state:
		PathState.OUTER:
			if divert_at_gate:
				divert_at_gate = false
				path_state = PathState.LUDO
				entry_gate = current_node
				entry_node = node
				ludo_steps = 0
				lap_route = LapRoute.UNDECIDED
		PathState.LUDO:
			if node.tile_type == BoardNode.TileType.LUDO:
				ludo_steps += 1
			elif node.tile_type == BoardNode.TileType.ENTRY_GATE:
				# Leaving the Ludo board back onto the outer ring
				path_state = PathState.OUTER
				entry_node = null
				entry_gate = null
				ludo_steps = 0
				lap_route = LapRoute.UNDECIDED
			else:
				path_state = PathState.HOME_STRETCH
	if node.tile_type == BoardNode.TileType.THRONE:
		path_state = PathState.VAIKUNTHA

	# Walk toward the new tile, facing the direction of travel
	var dx = node.global_position.x - current_node.global_position.x
	if absf(dx) > 1.0:
		sprite.flip_h = dx < 0
	if sprite.animation != "move":
		sprite.play("move")

	current_node = node

	# Smooth sliding animation over 0.25 seconds per space
	var tween = create_tween()
	tween.tween_property(self, "global_position", current_node.global_position + get_board_offset(), 0.25)
	tween.parallel().tween_property(self, "scale", get_board_scale(), 0.25)
	await tween.finished
	emit_signal("step_finished", self, current_node)
	await get_tree().create_timer(0.05).timeout # Brief pause between steps

# Moves the pawn step-by-step along its path. If the move ends exactly on an
# Entry Gate, it asks gate_chooser (a coroutine taking (pawn, gate) -> bool)
# whether to divert. Passing over a gate never offers entry.
# If it ends exactly on a Ludo arm tip, it asks exit_chooser (same signature)
# whether to leave through that arm's gate.
# On completing a Ludo lap it asks lap_handler (a coroutine taking (pawn) -> LapRoute)
# whether to turn home, loop again or exit.
func move_steps(steps: int, gate_chooser: Callable, lap_handler: Callable, exit_chooser: Callable):
	for i in range(steps):
		var next = get_next_node()
		if next == null:
			print("Error: Unlinked node encountered!")
			break

		await step_to(next)

		# Reaching Vaikuntha ends the move (MainBoard only allows exact rolls to get here)
		if path_state == PathState.VAIKUNTHA:
			break

		# Decided once per lap, whether the pawn passes the junction or stops on it
		if is_at_lap_junction() and lap_route == LapRoute.UNDECIDED:
			lap_route = await lap_handler.call(self)
			if lap_route == LapRoute.LOOP_AGAIN:
				ludo_steps = 0
				lap_route = LapRoute.UNDECIDED

	# Entering moves the pawn onto the arm's first tile right away
	if is_on_gate():
		divert_at_gate = await gate_chooser.call(self, current_node)
		if divert_at_gate:
			await step_to(current_node.branch_ludo_node)
	# Exiting moves the pawn out onto the gate right away
	elif can_exit_here():
		var gate = current_node.exit_gate_node
		if await exit_chooser.call(self, gate):
			await step_to(gate)

	sprite.play("idle")
	emit_signal("movement_finished", self)
