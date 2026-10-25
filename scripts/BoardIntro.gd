class_name BoardIntro
extends CanvasLayer
# Plays the board animation (the game box opening, diving into the lotus) over
# the board when a game starts. As it ends, the video fades out while the board
# pulls back from its own lotus to its normal size, so the camera seems to come
# out of the flower. A click or touch skips it. The background music pauses
# meanwhile, since the video has its own sound. Emits finished, then frees itself.

signal finished

const VIDEO = preload("res://assets/board animation.ogv")
const FADE_OUT: float = 0.9 # Natural ending: overlaps the video's final hold on the lotus
const SKIP_FADE_OUT: float = 0.45
const LOTUS = Vector2(560, 536) # The board's lotus, where the video's camera ends up
const PULL_BACK_FROM: float = 1.8 # Board zoom at the start of the pull-back

var screen: Control # Fades as a whole
var video: VideoStreamPlayer
var skip_hint: Label
var leaving: bool = false

func _ready():
	layer = 30 # Over everything on the board

	screen = Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_STOP # The board can't be used underneath
	add_child(screen)

	var black = ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(black)

	video = VideoStreamPlayer.new()
	video.stream = VIDEO
	video.expand = true
	video.set_anchors_preset(Control.PRESET_FULL_RECT)
	video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	video.finished.connect(leave.bind(0.0)) # Fallback if the early fade was missed
	screen.add_child(video)

	skip_hint = Label.new()
	skip_hint.text = "Click to skip"
	skip_hint.add_theme_font_size_override("font_size", 22)
	skip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	skip_hint.position = Vector2(1660, 1010)
	skip_hint.size = Vector2(220, 34)
	skip_hint.modulate.a = 0.0
	screen.add_child(skip_hint)

func play():
	Music.player.stream_paused = true
	video.play()
	create_tween().tween_property(skip_hint, "modulate:a", 0.55, 0.6).set_delay(1.0)

# Starts the fade during the video's last moments, so it never sits on a frozen frame
func _process(_delta):
	var length = video.get_stream_length()
	if video.is_playing() and length > 0.0 and length - video.stream_position <= FADE_OUT:
		leave(FADE_OUT)

func _input(event: InputEvent):
	var mouse_click = event is InputEventMouseButton and event.pressed
	var touch = event is InputEventScreenTouch and event.pressed
	if mouse_click or touch:
		get_viewport().set_input_as_handled()
		leave(SKIP_FADE_OUT)

func leave(fade_time: float):
	if leaving:
		return
	leaving = true
	var viewport = get_viewport()
	var board_view = viewport.canvas_transform
	if fade_time > 0.0:
		var t = create_tween().set_parallel()
		t.tween_property(screen, "modulate:a", 0.0, fade_time)
		t.tween_property(video, "volume_db", -40.0, fade_time)
		# The board eases out from its lotus to its normal size
		t.tween_method(func(zoom: float):
			viewport.canvas_transform = board_view * Transform2D(0, Vector2(zoom, zoom), 0, LOTUS - LOTUS * zoom),
			PULL_BACK_FROM, 1.0, fade_time * 1.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		await t.finished
	viewport.canvas_transform = board_view
	video.stop()
	Music.apply_settings() # Resumes the music, unless it's muted
	finished.emit()
	queue_free()
