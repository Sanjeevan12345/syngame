extends AnimatedSprite2D
# Glowing Vaikuntha lotus at the centre of the board, animated from the
# "thamara" (lotus) sprite sheet: a 6x6 grid of frames played in order.

const SHEET = preload("res://assets/thamara.png")
const GRID: int = 6

@export var fps: float = 12.0

func _ready():
	var frame_size = Vector2(SHEET.get_size()) / GRID
	var frames = SpriteFrames.new()
	frames.set_animation_speed("default", fps)
	frames.set_animation_loop("default", true)
	for i in GRID * GRID:
		var atlas = AtlasTexture.new()
		atlas.atlas = SHEET
		atlas.region = Rect2(Vector2(i % GRID, i / GRID) * frame_size, frame_size)
		atlas.filter_clip = true # Frame size isn't a whole pixel; keep neighbours out
		frames.add_frame("default", atlas)
	sprite_frames = frames
	play()
