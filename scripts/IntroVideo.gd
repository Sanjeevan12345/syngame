extends Control
# Plays the intro video before the opening page. A click or a touch skips it.
# The background music waits until the intro is over, since the video has its own sound.
# The video and its sound fade out to black just before the end (faster when
# skipped); the opening page then fades in from black as the music swells.

const OPENING_PAGE_SCENE = "res://scenes/opening_page.tscn"
const FADE_OUT: float = 0.8 # Natural ending
const SKIP_FADE_OUT: float = 0.4 # Skipping should still feel responsive
const SKIP_HINT_DELAY: float = 1.0
const SKIP_HINT_ALPHA: float = 0.55

@onready var video: VideoStreamPlayer = $Video
@onready var fade: ColorRect = $Fade
@onready var skip_hint: Label = $SkipHint

var leaving: bool = false

func _ready():
	Music.player.stop()
	video.finished.connect(leave.bind(0.0)) # Fallback if the early fade was missed
	video.play()
	create_tween().tween_property(skip_hint, "modulate:a", SKIP_HINT_ALPHA, 0.6).set_delay(SKIP_HINT_DELAY)

# Starts the fade while the video is still moving, so it never freezes on its last frame
func _process(_delta):
	var length = video.get_stream_length()
	if length > 0.0 and length - video.stream_position <= FADE_OUT:
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
	if fade_time > 0.0:
		var tween = create_tween().set_parallel()
		tween.tween_property(fade, "color:a", 1.0, fade_time)
		tween.tween_property(video, "volume_db", -40.0, fade_time)
		tween.tween_property(skip_hint, "modulate:a", 0.0, fade_time)
		await tween.finished
	video.stop()
	Music.start(true)
	get_tree().change_scene_to_file(OPENING_PAGE_SCENE)
