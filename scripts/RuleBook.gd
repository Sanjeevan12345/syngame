class_name RuleBook
extends CanvasLayer
# The game's rules as a palm-leaf manuscript: long leaves strung on a red cord,
# resting on a carved wooden cover. Leaves turn over their top edge, like a
# calendar, with a perspective shader so the turn reads as 3D. Text is shown
# only while a leaf lies flat, so it never warps.
# The rules live in assets/rulebook/rulebook.json, one entry per leaf.
#
# Usage: add the scene, call open(); it emits closed once put away.
# Flip with the arrow buttons, by clicking the leaf's left or right half, with
# the arrow keys or A / D, or jump to a section with the tabs. Esc closes.

signal closed

const RULES_PATH = "res://assets/rulebook/rulebook.json"
const LEAF_TEXTURE = preload("res://assets/rulebook/leaf.png")
const COVER_TEXTURE = preload("res://assets/rulebook/cover.png")
const TITLE_FONT = preload("res://assets/Fonts/CinzelDecorative-Bold.ttf")
const BODY_FONT = preload("res://assets/Fonts/EBGaramond.ttf")

const GOLD = Color("#D9A21B")
const DARK = Color("#2A0D10")
const CREAM = Color("#F0E3C6")
const INK = Color(0.2, 0.09, 0.04)
const CORD_COLOR = Color(0.58, 0.1, 0.07)

const BOOK_CENTER = Vector2(960, 590)
const LEAF_SIZE = Vector2(1500, 430)
const HOLES = [Vector2(105, 215), Vector2(1395, 215)] # Cord holes, in leaf pixels
const TEXT_MARGIN_X: float = 165.0 # Keeps text clear of the holes
const STACK_LEAVES: int = 4 # Leaf edges showing under the open leaf
const FLIP_TIME: float = 0.5
const OPEN_TIME: float = 0.5
const DIM_ALPHA: float = 0.85

const FLIP_SHADER = """
shader_type canvas_item;
// Turns a leaf over its top edge: tilt about the x-axis, then project with
// perspective, dividing UVs by depth per pixel so the quad stays true.
// Past a quarter turn its back shows, a little darker.
uniform float angle = 0.0;
uniform vec2 size = vec2(1500.0, 430.0);
uniform float view_distance = 1800.0;
varying vec3 persp_uv;
varying vec4 tint;

void vertex() {
	vec2 pivot = vec2(size.x * 0.5, 0.0);
	vec2 p = VERTEX - pivot;
	float z = -p.y * sin(angle); // The lifting edge comes towards the viewer
	float s = view_distance / (view_distance + z);
	VERTEX = pivot + vec2(p.x, p.y * cos(angle)) * s;
	persp_uv = vec3(UV * s, s);
	tint = COLOR;
}

void fragment() {
	vec4 c = texture(TEXTURE, persp_uv.xy / persp_uv.z);
	float light = 0.55 + 0.45 * abs(cos(angle));
	if (cos(angle) < 0.0) {
		light *= 0.8;
	}
	COLOR = vec4(c.rgb * light, c.a) * tint;
}
"""

var leaves: Array = [] # Each {section, title, lines}
var current: int = 0
var busy: bool = false # A flip or the open / close animation is running
var flip_shader: Shader

var dim: ColorRect
var book: Control # Everything that slides in and out
var top_cover: TextureRect
var front: Control # The open leaf
var under: Control # The leaf revealed by a turn
var counter: Label
var tabs: HBoxContainer
var prev_button: Button
var next_button: Button

func _ready():
	layer = 15
	visible = false
	load_leaves()
	flip_shader = Shader.new()
	flip_shader.code = FLIP_SHADER
	build()

func load_leaves():
	var data = JSON.parse_string(FileAccess.get_file_as_string(RULES_PATH))
	if data is Array:
		leaves = data
	else:
		push_warning("RuleBook: could not read " + RULES_PATH)
		leaves = [{"section": "", "title": "Rules", "lines": ["The rule book could not be read."]}]

func build():
	# Catches every click, so the page behind can't be used while reading
	dim = ColorRect.new()
	dim.color = Color(DARK, 0.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	book = Control.new()
	book.size = Vector2(1920, 1080)
	book.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(book)

	var leaf_origin = BOOK_CENTER - LEAF_SIZE / 2

	var bottom_cover = TextureRect.new()
	bottom_cover.texture = COVER_TEXTURE
	bottom_cover.position = BOOK_CENTER - COVER_TEXTURE.get_size() / 2 + Vector2(0, 30)
	bottom_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	book.add_child(bottom_cover)

	# Edges of the leaves below, each a shade darker
	for i in range(STACK_LEAVES, 0, -1):
		var edge = TextureRect.new()
		edge.texture = LEAF_TEXTURE
		edge.position = leaf_origin + Vector2(0, 6 * i)
		var shade = 0.75 - 0.08 * i
		edge.modulate = Color(shade, shade, shade)
		edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		book.add_child(edge)

	var cords = Control.new()
	cords.position = leaf_origin
	cords.size = LEAF_SIZE
	cords.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cords.draw.connect(draw_cords.bind(cords))
	book.add_child(cords)

	under = make_leaf()
	under.position = leaf_origin
	under.visible = false
	book.add_child(under)

	front = make_leaf()
	front.position = leaf_origin
	front.mouse_filter = Control.MOUSE_FILTER_STOP
	front.gui_input.connect(_on_leaf_input)
	book.add_child(front)

	top_cover = TextureRect.new()
	top_cover.texture = COVER_TEXTURE
	top_cover.position = BOOK_CENTER - COVER_TEXTURE.get_size() / 2
	top_cover.material = flip_material(COVER_TEXTURE.get_size())
	top_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	book.add_child(top_cover)

	tabs = HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 10)
	tabs.position = Vector2(0, BOOK_CENTER.y - LEAF_SIZE.y / 2 - 82)
	tabs.size = Vector2(1920, 48)
	book.add_child(tabs)
	var sections: Array = []
	for leaf in leaves:
		if not sections.has(leaf.section):
			sections.append(leaf.section)
	for section in sections:
		var tab = make_button(section, 20, Vector2(110, 44))
		tab.pressed.connect(go_to_section.bind(section))
		tabs.add_child(tab)

	prev_button = make_button("<", 34, Vector2(64, 96))
	prev_button.position = Vector2(BOOK_CENTER.x - LEAF_SIZE.x / 2 - 90, BOOK_CENTER.y - 48)
	prev_button.tooltip_text = "Previous leaf"
	prev_button.pressed.connect(turn.bind(-1))
	book.add_child(prev_button)

	next_button = make_button(">", 34, Vector2(64, 96))
	next_button.position = Vector2(BOOK_CENTER.x + LEAF_SIZE.x / 2 + 26, BOOK_CENTER.y - 48)
	next_button.tooltip_text = "Next leaf"
	next_button.pressed.connect(turn.bind(1))
	book.add_child(next_button)

	var close_button = make_button("X", 24, Vector2(52, 52))
	close_button.position = Vector2(BOOK_CENTER.x + LEAF_SIZE.x / 2 - 20, BOOK_CENTER.y - LEAF_SIZE.y / 2 - 86)
	close_button.tooltip_text = "Close the book (Esc)"
	close_button.pressed.connect(close)
	book.add_child(close_button)

	counter = Label.new()
	counter.add_theme_font_override("font", TITLE_FONT)
	counter.add_theme_font_size_override("font_size", 20)
	counter.add_theme_color_override("font_color", CREAM)
	counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	counter.position = Vector2(0, BOOK_CENTER.y + LEAF_SIZE.y / 2 + 125) # Below the tassels
	counter.size = Vector2(1920, 30)
	book.add_child(counter)

func flip_material(texture_size: Vector2) -> ShaderMaterial:
	var material = ShaderMaterial.new()
	material.shader = flip_shader
	material.set_shader_parameter("size", texture_size)
	return material

# A leaf: the palm-leaf texture with its title and lines laid over it
func make_leaf() -> Control:
	var leaf = Control.new()
	leaf.size = LEAF_SIZE
	leaf.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var paper = TextureRect.new()
	paper.name = "Paper"
	paper.texture = LEAF_TEXTURE
	paper.material = flip_material(LEAF_SIZE)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	leaf.add_child(paper)

	var text = VBoxContainer.new()
	text.name = "Text"
	text.position = Vector2(TEXT_MARGIN_X, 34)
	text.size = Vector2(LEAF_SIZE.x - TEXT_MARGIN_X * 2, LEAF_SIZE.y - 68)
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 14)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	leaf.add_child(text)

	var title = Label.new()
	title.name = "Title"
	title.add_theme_font_override("font", TITLE_FONT)
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(0.45, 0.08, 0.05))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.add_child(title)

	var body = Label.new()
	body.name = "Body"
	body.add_theme_font_override("font", BODY_FONT)
	body.add_theme_font_size_override("font_size", 31)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_color_override("font_color", INK)
	body.add_theme_constant_override("line_spacing", 2)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(text.size.x, 0)
	text.add_child(body)
	return leaf

func show_leaf_page(leaf: Control, index: int):
	var page: Dictionary = leaves[index]
	leaf.get_node("Text/Title").text = page.title
	leaf.get_node("Text/Body").text = "\n".join(page.lines)

func set_leaf_angle(leaf: Control, angle: float):
	leaf.get_node("Paper").material.set_shader_parameter("angle", angle)

# The red cord through both holes, hanging below the book with a gold bead and tassel
func draw_cords(canvas: Control):
	var bottom = LEAF_SIZE.y + 60
	for i in HOLES.size():
		var hole: Vector2 = HOLES[i]
		var side = -1.0 if i == 0 else 1.0
		var points = PackedVector2Array()
		for step in 13:
			var t = step / 12.0
			var sway = sin(t * PI) * 28 * side
			points.append(hole.lerp(Vector2(hole.x + 30 * side, bottom), t) + Vector2(sway, 0))
		canvas.draw_polyline(points, CORD_COLOR.darkened(0.35), 7, true)
		canvas.draw_polyline(points, CORD_COLOR, 4, true)
		canvas.draw_circle(hole, 9, GOLD.darkened(0.2))
		canvas.draw_circle(hole, 5, GOLD.lightened(0.2))
		var tassel_top = points[points.size() - 1]
		canvas.draw_circle(tassel_top, 8, GOLD)
		for strand in 7:
			var x = (strand - 3) * 3.0
			canvas.draw_line(tassel_top + Vector2(x * 0.5, 4), tassel_top + Vector2(x, 44), CORD_COLOR, 2.5, true)

func make_button(text: String, font_size: int, min_size: Vector2) -> Button:
	var button = Button.new()
	button.text = text
	button.custom_minimum_size = min_size
	button.size = min_size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", TITLE_FONT)
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", CREAM)
	button.add_theme_color_override("font_hover_color", GOLD.lightened(0.35))
	button.add_theme_color_override("font_pressed_color", DARK)
	button.add_theme_color_override("font_disabled_color", Color(CREAM, 0.3))
	for state in ["normal", "hover", "pressed", "disabled"]:
		var box = StyleBoxFlat.new()
		box.bg_color = {"normal": Color(0.3, 0.15, 0.07), "hover": Color(0.4, 0.2, 0.09),
			"pressed": GOLD, "disabled": Color(0.2, 0.1, 0.05, 0.6)}[state]
		box.border_color = GOLD if state != "disabled" else Color(GOLD, 0.3)
		box.set_border_width_all(2)
		box.set_corner_radius_all(8)
		box.set_content_margin_all(4)
		button.add_theme_stylebox_override(state, box)
	return button

func update_controls():
	counter.text = "Leaf %d of %d" % [current + 1, leaves.size()]
	prev_button.disabled = current == 0
	next_button.disabled = current == leaves.size() - 1
	var section = leaves[current].section
	for tab in tabs.get_children():
		# The open section's tab is lit in gold
		var lit = tab.text == section
		tab.add_theme_color_override("font_color", DARK if lit else CREAM)
		var box: StyleBoxFlat = tab.get_theme_stylebox("normal").duplicate()
		box.bg_color = GOLD if lit else Color(0.3, 0.15, 0.07)
		tab.add_theme_stylebox_override("normal", box)

func open():
	if visible:
		return
	visible = true
	busy = true
	current = 0
	show_leaf_page(front, current)
	set_leaf_angle(front, 0.0)
	front.get_node("Text").visible = true
	under.visible = false
	update_controls()

	top_cover.modulate.a = 1.0
	top_cover.material.set_shader_parameter("angle", 0.0)
	book.position.y = 900
	var t = create_tween()
	t.tween_property(dim, "color:a", DIM_ALPHA, 0.3)
	t.parallel().tween_property(book, "position:y", 0.0, OPEN_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# The top cover swings open over its top edge
	t.tween_method(func(a: float): top_cover.material.set_shader_parameter("angle", a), 0.0, PI, 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.parallel().tween_property(top_cover, "modulate:a", 0.0, 0.25).set_delay(0.4)
	await t.finished
	busy = false

func close():
	if not visible or busy:
		return
	busy = true
	var t = create_tween()
	t.tween_property(top_cover, "modulate:a", 1.0, 0.15)
	t.parallel().tween_method(func(a: float): top_cover.material.set_shader_parameter("angle", a), PI, 0.0, 0.45) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(book, "position:y", 900.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(dim, "color:a", 0.0, 0.4)
	await t.finished
	visible = false
	busy = false
	closed.emit()

# Turns one leaf forward (+1) or back (-1)
func turn(direction: int):
	go_to(current + direction)

func go_to_section(section: String):
	for i in leaves.size():
		if leaves[i].section == section:
			go_to(i)
			return

# Turning forward lifts the open leaf away to reveal the target beneath it;
# turning back brings the target leaf down over the open one.
func go_to(index: int):
	if busy or index == current or index < 0 or index >= leaves.size():
		return
	busy = true
	var forward = index > current
	var t = create_tween()
	if forward:
		show_leaf_page(under, index)
		under.get_node("Text").visible = true
		under.visible = true
		front.get_node("Text").visible = false
		t.tween_method(func(a: float): set_leaf_angle(front, a), 0.0, PI, FLIP_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		t.parallel().tween_property(front, "modulate:a", 0.0, FLIP_TIME * 0.3).set_delay(FLIP_TIME * 0.7)
	else:
		show_leaf_page(under, current)
		under.get_node("Text").visible = true
		under.visible = true
		show_leaf_page(front, index)
		front.get_node("Text").visible = false
		front.modulate.a = 0.0
		set_leaf_angle(front, PI)
		t.tween_method(func(a: float): set_leaf_angle(front, a), PI, 0.0, FLIP_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		t.parallel().tween_property(front, "modulate:a", 1.0, FLIP_TIME * 0.3)
	await t.finished

	# The open leaf now shows the target page, flat
	current = index
	show_leaf_page(front, current)
	set_leaf_angle(front, 0.0)
	front.modulate.a = 1.0
	front.get_node("Text").visible = true
	under.visible = false
	update_controls()
	busy = false

# Clicking the right half of the leaf turns forward, the left half back
func _on_leaf_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		turn(1 if event.position.x > LEAF_SIZE.x / 2 else -1)

func _input(event: InputEvent):
	if not visible or not (event is InputEventKey and event.pressed):
		return
	match event.keycode:
		KEY_RIGHT, KEY_D:
			turn(1)
		KEY_LEFT, KEY_A:
			turn(-1)
		KEY_ESCAPE:
			close()
		_:
			return
	get_viewport().set_input_as_handled()
