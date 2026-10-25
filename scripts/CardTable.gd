class_name CardTable
extends Node2D
# The Dharma and Adharma decks lying on the board, and the card-draw animation:
# the top card lifts off its deck, flips over in 3D while flying to the board's
# centre, and lands face up; then the card's text fades in. A click (or a wait)
# puts the card away, and only then does its effect happen.
# Cards are portrait (like the deck backs); the face is drawn landscape by
# landing the card a quarter turn round. The 3D turn is a perspective-correct
# vertex shader, so the 2D board needs no 3D scene.

const BACKS = [preload("res://assets/cards/dharma_back.png"), preload("res://assets/cards/adharma_back.png")]
const FACE = preload("res://assets/cards/card_face.png")
const DECK_NAMES = ["Dharma", "Adharma"]
const TITLE_COLORS = [Color(0.1, 0.18, 0.45), Color(0.45, 0.06, 0.05)]

# Where each deck lies on the board (as in the board mock-up) and its turn
const DECK_POSITIONS = [Vector2(357, 304), Vector2(772, 725)]
const DECK_ANGLES = [0.69, 0.62]
const DECK_SCALE: float = 0.32 # 400 x 600 card art -> about 128 x 192 on the board
const STACK_LAYERS: int = 7
const LAYER_STEP = Vector2(-1.1, 1.7) # Each card below sits a little down-left

const LANDING_POSITION = Vector2(560, 536) # Centre of the board
const LANDING_SCALE: float = 0.78 # About 470 x 310 once landed
const FLIGHT_TIME: float = 1.1
const LIFT: float = 0.3 # How much bigger the card looks at the top of its arc
const SHADOW_DROP: float = 46.0 # Shadow offset at the top of the arc
const TEXT_FADE: float = 0.35
const MIN_READ_TIME: float = 3.0
const READ_TIME_PER_CHAR: float = 0.04
const PUT_AWAY_TIME: float = 0.3

const CARD_SHADER = """
shader_type canvas_item;
// Turns the card in 3D: flip about its long axis, spin in the board's plane,
// tilt towards the viewer, then project with perspective. UVs are divided by
// depth per pixel so the quad's two triangles stay true.
uniform sampler2D face_tex : filter_linear_mipmap;
uniform float flip = 0.0;   // Radians about the card's long axis; past PI/2 the face shows
uniform float spin = 0.0;   // Radians in the board's plane
uniform float tilt = 0.0;   // Radians, top edge away from the viewer
uniform float view_distance = 1500.0;
uniform bool shadow = false;
uniform float shadow_alpha = 0.35;
varying vec3 persp_uv;
varying vec4 tint; // The sprite's modulate; COLOR in fragment() already holds the texture

void vertex() {
	vec3 p = vec3(VERTEX, 0.0);
	p = vec3(p.x * cos(flip), p.y, p.x * sin(flip));
	p = vec3(p.x * cos(spin) - p.y * sin(spin), p.x * sin(spin) + p.y * cos(spin), p.z);
	p = vec3(p.x, p.y * cos(tilt) - p.z * sin(tilt), p.y * sin(tilt) + p.z * cos(tilt));
	float s = view_distance / (view_distance + p.z);
	VERTEX = p.xy * s;
	persp_uv = vec3(UV * s, s);
	tint = COLOR;
}

void fragment() {
	vec2 uv = persp_uv.xy / persp_uv.z;
	vec4 c;
	if (cos(flip) < 0.0) {
		// The face is landscape: after the flip and the quarter turn, the
		// card's (u, v) shows the face's (1 - v, 1 - u)
		c = texture(face_tex, vec2(1.0 - uv.y, 1.0 - uv.x));
	} else {
		c = texture(TEXTURE, uv);
	}
	COLOR = shadow ? vec4(0.0, 0.0, 0.0, c.a * shadow_alpha * tint.a) : c * tint;
}
"""

signal dismissed

var flying: Sprite2D
var flying_shadow: Sprite2D
var text_box: Control
var title_label: Label
var text_label: Label
var waiting_for_click: bool = false

func _ready():
	z_index = 5 # Above the board art, below the flying card

	var shader = Shader.new()
	shader.code = CARD_SHADER
	flying_shadow = make_card_sprite(shader, true)
	flying = make_card_sprite(shader, false)

	# Text sits flat over the landed card
	text_box = VBoxContainer.new()
	text_box.theme = preload("res://scenes/main_ui_theme.tres")
	text_box.alignment = BoxContainer.ALIGNMENT_CENTER
	text_box.add_theme_constant_override("separation", 10)
	text_box.size = Vector2(330, 200)
	text_box.position = LANDING_POSITION - text_box.size / 2
	text_box.z_index = 41
	text_box.z_as_relative = false
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.visible = false
	add_child(text_box)

	title_label = Label.new()
	title_label.theme_type_variation = &"ParchmentLabel"
	title_label.add_theme_font_size_override("font_size", 26)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_box.add_child(title_label)

	text_label = Label.new()
	text_label.theme_type_variation = &"ParchmentLabel"
	text_label.add_theme_font_size_override("font_size", 19)
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.custom_minimum_size = Vector2(330, 0)
	text_box.add_child(text_label)

func make_card_sprite(shader: Shader, is_shadow: bool) -> Sprite2D:
	var sprite = Sprite2D.new()
	sprite.material = ShaderMaterial.new()
	sprite.material.shader = shader
	sprite.material.set_shader_parameter("face_tex", FACE)
	sprite.material.set_shader_parameter("shadow", is_shadow)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.z_index = 39 if is_shadow else 40
	sprite.z_as_relative = false
	sprite.visible = false
	add_child(sprite)
	return sprite

# The two decks: a soft shadow, darkened cards for the stack's edges, the top card
func _draw():
	for deck in 2:
		var back: Texture2D = BACKS[deck]
		var rect = Rect2(-back.get_size() / 2, back.get_size())
		var base = DECK_POSITIONS[deck]
		var bottom = LAYER_STEP * STACK_LAYERS
		draw_set_transform(base + bottom + Vector2(-8, 12), DECK_ANGLES[deck], Vector2.ONE * DECK_SCALE * 1.03)
		draw_texture_rect(back, rect, false, Color(0, 0, 0, 0.28))
		for layer in range(STACK_LAYERS, 0, -1):
			var shade = lerpf(0.32, 0.55, 1.0 - float(layer) / STACK_LAYERS)
			draw_set_transform(base + LAYER_STEP * layer, DECK_ANGLES[deck], Vector2.ONE * DECK_SCALE)
			draw_texture_rect(back, rect, false, Color(shade, shade, shade))
		draw_set_transform(base, DECK_ANGLES[deck], Vector2.ONE * DECK_SCALE)
		draw_texture_rect(back, rect, false)
	draw_set_transform_matrix(Transform2D.IDENTITY)

# Draws a card from a deck (0 = Dharma, 1 = Adharma) and shows its text.
# Returns once the player has read it and it has been put away.
func show_card(deck: int, text: String):
	title_label.text = DECK_NAMES[deck]
	title_label.add_theme_color_override("font_color", TITLE_COLORS[deck])
	text_label.text = text
	text_box.modulate.a = 0.0
	text_box.visible = true

	for sprite in [flying, flying_shadow]:
		sprite.texture = BACKS[deck]
		sprite.modulate.a = 1.0
		sprite.visible = true
	var tween = create_tween()
	tween.tween_method(fly.bind(deck), 0.0, 1.0, FLIGHT_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished

	tween = create_tween()
	tween.tween_property(text_box, "modulate:a", 1.0, TEXT_FADE)
	await tween.finished

	# Stays until clicked, or long enough to read
	waiting_for_click = true
	var read_timer = get_tree().create_timer(maxf(MIN_READ_TIME, READ_TIME_PER_CHAR * text.length()))
	read_timer.timeout.connect(func():
		if waiting_for_click:
			dismissed.emit())
	await dismissed
	waiting_for_click = false

	tween = create_tween().set_parallel()
	for node in [flying, flying_shadow, text_box]:
		tween.tween_property(node, "modulate:a", 0.0, PUT_AWAY_TIME)
	tween.tween_property(flying, "scale", flying.scale * 1.06, PUT_AWAY_TIME)
	await tween.finished
	flying.visible = false
	flying_shadow.visible = false
	text_box.visible = false

# One frame of the flight, t from 0 (on the deck) to 1 (landed)
func fly(t: float, deck: int):
	var height = sin(t * PI) # 0 on the deck and on landing, 1 at the top of the arc
	var position_now = DECK_POSITIONS[deck].lerp(LANDING_POSITION, t)
	var scale_now = lerpf(DECK_SCALE, LANDING_SCALE, t) * (1.0 + LIFT * height)
	var flip = PI * smoothstep(0.15, 0.85, t)
	var spin = lerp_angle(DECK_ANGLES[deck], PI / 2, t)
	var tilt = 0.45 * height

	flying.position = position_now - Vector2(0, 30 * height)
	flying_shadow.position = position_now + Vector2(-0.4, 1) * SHADOW_DROP * height
	for sprite in [flying, flying_shadow]:
		sprite.scale = Vector2.ONE * scale_now
		sprite.material.set_shader_parameter("flip", flip)
		sprite.material.set_shader_parameter("spin", spin)
		sprite.material.set_shader_parameter("tilt", tilt)
	flying_shadow.material.set_shader_parameter("shadow_alpha", lerpf(0.35, 0.2, height))

func _input(event: InputEvent):
	if waiting_for_click and event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		dismissed.emit()
