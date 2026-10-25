class_name CharacterPopup
extends Control
# Shakuni or Narada sliding in at the bottom-left with a parchment speech bubble.
# say() shows one line; it slides out after a reading time or when clicked,
# then emits finished.

signal finished

const PORTRAITS = {
	"Shakuni": preload("res://assets/charac_talks/shakuni_no_watermark-Photoroom (1).png"),
	"Narada": preload("res://assets/charac_talks/naradar.png"),
}
const REST_POSITION = Vector2(6, 760)
const HIDDEN_OFFSET: float = -720.0 # Off the left edge of the screen
const BASE_SECONDS: float = 4.0
const SECONDS_PER_CHAR: float = 0.045

var showing: bool = false
var portrait: TextureRect
var bubble: ScaledPanel
var name_label: Label
var text_label: Label
var text_scroll: ScrollContainer
var hold_timer: Timer
var tween: Tween

func _init():
	theme = preload("res://scenes/main_ui_theme.tres")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = REST_POSITION + Vector2(HIDDEN_OFFSET, 0)
	size = Vector2(700, 316)
	visible = false

	portrait = TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.position = Vector2.ZERO
	portrait.size = Vector2(236, 316)
	add_child(portrait)

	# Speech bubble to the right of the speaker, level with their face
	bubble = ScaledPanel.new()
	bubble.art = ScaledPanel.Art.PARCHMENT
	bubble.art_scale = 0.3
	bubble.mouse_filter = Control.MOUSE_FILTER_STOP
	bubble.position = Vector2(222, 24)
	bubble.size = Vector2(470, 196)
	add_child(bubble)

	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	bubble.add_child(box)

	name_label = Label.new()
	name_label.theme_type_variation = &"ParchmentLabel"
	name_label.add_theme_color_override("font_color", Color(0.5, 0.08, 0.05))
	name_label.add_theme_font_size_override("font_size", 22)
	box.add_child(name_label)

	# Long lines scroll inside the bubble instead of overflowing it
	text_scroll = ScrollContainer.new()
	text_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	text_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(text_scroll)

	text_label = Label.new()
	text_label.theme_type_variation = &"ParchmentLabel"
	text_label.add_theme_font_size_override("font_size", 15)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_scroll.add_child(text_label)

	hold_timer = Timer.new()
	hold_timer.one_shot = true
	hold_timer.timeout.connect(dismiss)
	add_child(hold_timer)

func say(speaker: String, text: String):
	portrait.texture = PORTRAITS.get(speaker)
	name_label.text = speaker
	text_label.text = text
	text_scroll.scroll_vertical = 0
	showing = true
	visible = true
	_slide(REST_POSITION, 1.0)
	hold_timer.start(BASE_SECONDS + SECONDS_PER_CHAR * text.length())

func dismiss():
	if not showing:
		return
	showing = false
	hold_timer.stop()
	_slide(REST_POSITION + Vector2(HIDDEN_OFFSET, 0), 0.0)
	await tween.finished
	if not showing: # A new line may have started during the slide-out
		visible = false
		finished.emit()

func _slide(target: Vector2, alpha: float):
	if tween:
		tween.kill()
	tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position", target, 0.4)
	tween.tween_property(self, "modulate:a", alpha, 0.4)

# Clicking the speaker or the bubble sends them away early. Checked in _input so
# the bubble's text or the UI beneath can't swallow the click first.
func _input(event: InputEvent):
	if not showing or not (event is InputEventMouseButton and event.pressed 			and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var mouse = get_global_mouse_position()
	if portrait.get_global_rect().has_point(mouse) or bubble.get_global_rect().has_point(mouse):
		dismiss()
		get_viewport().set_input_as_handled()
