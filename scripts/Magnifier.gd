class_name Magnifier
extends Control
# A round lens that follows the mouse over the board and shows it enlarged, so
# the small writing on the tiles can be read. A SubViewport shares the board's
# 2D world and renders it again, zoomed, around the mouse; it renders from the
# board art itself, so the text stays sharp rather than an upscaled screenshot.
# Only the board's world is drawn in the lens, not the UI panels above it.
# The mouse wheel changes the zoom; clicks pass straight through to the game.

const LENS_SIZE: int = 340
const MIN_ZOOM: float = 1.5
const MAX_ZOOM: float = 4.0
const ZOOM_STEP: float = 0.25
const RIM_COLOR = Color(0.86, 0.64, 0.22)
const RIM_SHADOW = Color(0.15, 0.08, 0.03, 0.8)

const CIRCLE_SHADER = """
shader_type canvas_item;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	c.a *= 1.0 - smoothstep(0.485, 0.5, distance(UV, vec2(0.5)));
	COLOR = c;
}
"""

var active: bool = false
var zoom: float = 2.2
var board_rect: Rect2 # The lens only appears while the mouse is over this area
var viewport: SubViewport
var lens: TextureRect

func _init():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(LENS_SIZE, LENS_SIZE)
	visible = false

	viewport = SubViewport.new()
	viewport.size = Vector2i(LENS_SIZE, LENS_SIZE)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)

	lens = TextureRect.new()
	lens.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lens.size = size
	lens.texture = viewport.get_texture()
	var shader = Shader.new()
	shader.code = CIRCLE_SHADER
	lens.material = ShaderMaterial.new()
	lens.material.shader = shader
	add_child(lens)

	var rim = Control.new()
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rim.size = size
	rim.draw.connect(draw_rim.bind(rim))
	add_child(rim)

# world: the board's World2D, so the lens sees the same pieces
func setup(world: World2D, area: Rect2):
	viewport.world_2d = world
	board_rect = area

func set_active(value: bool):
	active = value
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if not active:
		visible = false

func _process(_delta):
	if not active:
		return
	var mouse = get_global_mouse_position()
	visible = board_rect.has_point(mouse)
	if not visible:
		return
	position = mouse - size / 2
	# Board point under the mouse lands in the lens's centre, enlarged by zoom
	viewport.canvas_transform = Transform2D(0, Vector2(zoom, zoom), 0, size / 2 - mouse * zoom)

func _input(event: InputEvent):
	if not active or not visible:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = minf(zoom + ZOOM_STEP, MAX_ZOOM)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = maxf(zoom - ZOOM_STEP, MIN_ZOOM)
			get_viewport().set_input_as_handled()

# Gold rim around the lens, drawn over the image
func draw_rim(rim: Control):
	var center = size / 2
	var radius = LENS_SIZE / 2.0
	rim.draw_arc(center, radius - 2, 0, TAU, 64, RIM_SHADOW, 9, true)
	rim.draw_arc(center, radius - 3, 0, TAU, 64, RIM_COLOR, 5, true)
