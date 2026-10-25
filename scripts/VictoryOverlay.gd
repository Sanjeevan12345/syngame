class_name VictoryOverlay
extends CanvasLayer
# Victory celebration shown over the board, with no scene change: the board is
# dimmed behind it and all board input (clicks, dice throws) is blocked while it
# is up. Two swords fly in and clash in an X with sparks, a flash and a screen
# shake; then the ribbon drops in with the winner's name, and the winner's piece
# bobs between the sword tips. Play Again and Quit appear after about 3 seconds.
#
# Usage: add the scene, call play(winner_name, winner_texture), and listen for
# finished (animation done, buttons shown), play_again_pressed and quit_pressed.

signal finished
signal play_again_pressed
signal quit_pressed

const SWORD = preload("res://assets/winner/trimmed/sword.png")
const SPARK = preload("res://assets/winner/trimmed/spark.png")
const RIBBON = preload("res://assets/winner/trimmed/ribbon_banner.png")
const FONT = preload("res://assets/Fonts/CinzelDecorative-Black.ttf")

const GOLD = Color("#D9A21B")
const DARK = Color("#2A0D10")
const CREAM = Color("#F0E3C6")

const CENTER = Vector2(960, 440) # Where the swords cross, behind the ribbon's middle
const DIM_ALPHA: float = 0.62

# Sword art is 290 x 1295, tip up. The swords cross on their blades, about 40%
# down from the tip, so that point is placed on the sprite's origin.
const SWORD_SCALE: float = 0.62
const SWORD_CROSS_OFFSET = Vector2(0, 130)
const SWORD_ANGLE: float = deg_to_rad(36)
const SWORD_START_X: float = 560.0 # How far off each side the swords start

# The ribbon art (rotated to a banner) is 1164 x 672. Its wide, flat middle
# runs from about x 250 to 900, centred near (575, 140), rising to the right
# at about 7 degrees; the name goes there.
const RIBBON_SCALE: float = 0.95
const RIBBON_BAND_CENTER = Vector2(575, 140)
const RIBBON_BAND_SIZE = Vector2(560, 100)
const RIBBON_BAND_ANGLE: float = deg_to_rad(-7.3)
const RIBBON_REST_Y: float = 610.0 # Screen y of the ribbon's middle once landed

const PIECE_POSITION = Vector2(960, 190) # In the V between the sword tips
const PIECE_SCALE: float = 0.85
const BOB_HEIGHT: float = 12.0

# Timeline, in seconds
const SWORD_FLIGHT: float = 0.55
const CLASH_AT: float = 0.75
const RIBBON_AT: float = 1.25
const RIBBON_DROP: float = 0.6
const NAME_AT: float = 1.85
const BUTTONS_AT: float = 2.6

var dim: ColorRect
var flash: ColorRect
var stage: Node2D # Everything that moves; shaken on the clash
var swords: Array = []
var spark: Sprite2D
var small_sparks: Array = []
var embers: CPUParticles2D
var gold_dust: CPUParticles2D
var ribbon: Sprite2D
var name_label: Label
var piece: Sprite2D
var buttons: HBoxContainer
var bob: Tween
var rng := RandomNumberGenerator.new()

func _ready():
	layer = 20 # Over the board, its panels, the top bar and the magnifier
	visible = false
	build()

func build():
	# Catches every click, so nothing on the board can be used underneath
	dim = ColorRect.new()
	dim.color = Color(DARK, 0.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	stage = Node2D.new()
	add_child(stage)

	var add_blend = CanvasItemMaterial.new()
	add_blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	for side in [-1, 1]:
		var sword = Sprite2D.new()
		sword.texture = SWORD
		sword.offset = SWORD_CROSS_OFFSET
		sword.flip_h = side == 1
		sword.scale = Vector2.ONE * SWORD_SCALE
		stage.add_child(sword)
		swords.append(sword)

	gold_dust = CPUParticles2D.new()
	gold_dust.texture = SPARK
	gold_dust.material = add_blend
	gold_dust.emitting = false
	gold_dust.amount = 40
	gold_dust.lifetime = 4.0
	gold_dust.position = Vector2(960, -20)
	gold_dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	gold_dust.emission_rect_extents = Vector2(900, 10)
	gold_dust.direction = Vector2.DOWN
	gold_dust.spread = 15.0
	gold_dust.initial_velocity_min = 60.0
	gold_dust.initial_velocity_max = 140.0
	gold_dust.gravity = Vector2(0, 30)
	gold_dust.angular_velocity_min = -90.0
	gold_dust.angular_velocity_max = 90.0
	gold_dust.scale_amount_min = 0.03
	gold_dust.scale_amount_max = 0.07
	gold_dust.color_ramp = fade_ramp(Color(GOLD, 0.0), Color(GOLD.lightened(0.3), 0.8))
	stage.add_child(gold_dust)

	ribbon = Sprite2D.new()
	ribbon.texture = RIBBON
	ribbon.scale = Vector2.ONE * RIBBON_SCALE
	stage.add_child(ribbon)

	# The name lies along the ribbon's flat middle, tilted with it
	var band = Control.new()
	band.size = RIBBON_BAND_SIZE
	band.pivot_offset = RIBBON_BAND_SIZE / 2
	band.position = RIBBON_BAND_CENTER - RIBBON.get_size() / 2 - RIBBON_BAND_SIZE / 2
	band.rotation = RIBBON_BAND_ANGLE
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ribbon.add_child(band)

	name_label = Label.new()
	name_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.pivot_offset = RIBBON_BAND_SIZE / 2
	name_label.add_theme_font_override("font", FONT)
	name_label.add_theme_color_override("font_color", CREAM)
	name_label.add_theme_color_override("font_outline_color", DARK)
	name_label.add_theme_constant_override("outline_size", 14)
	name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	name_label.add_theme_constant_override("shadow_offset_y", 4)
	band.add_child(name_label)

	piece = Sprite2D.new()
	piece.scale = Vector2.ONE * PIECE_SCALE
	stage.add_child(piece)

	spark = Sprite2D.new()
	spark.texture = SPARK
	spark.material = add_blend
	stage.add_child(spark)
	for i in 7:
		var small = Sprite2D.new()
		small.texture = SPARK
		small.material = add_blend
		stage.add_child(small)
		small_sparks.append(small)

	embers = CPUParticles2D.new()
	embers.texture = SPARK
	embers.material = add_blend
	embers.emitting = false
	embers.one_shot = true
	embers.explosiveness = 1.0
	embers.amount = 70
	embers.lifetime = 1.1
	embers.position = CENTER
	embers.spread = 180.0
	embers.initial_velocity_min = 250.0
	embers.initial_velocity_max = 700.0
	embers.gravity = Vector2(0, 700)
	embers.damping_min = 60.0
	embers.damping_max = 120.0
	embers.scale_amount_min = 0.04
	embers.scale_amount_max = 0.1
	embers.color_ramp = fade_ramp(Color(1.0, 0.95, 0.75, 1.0), Color(GOLD, 0.0), true)
	stage.add_child(embers)

	flash = ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)

	buttons = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 40)
	buttons.position = Vector2(0, 990)
	buttons.size = Vector2(1920, 70)
	add_child(buttons)
	buttons.add_child(make_button("Play Again", play_again_pressed))
	buttons.add_child(make_button("Quit", quit_pressed))

# A colour ramp for particles. burst: straight from -> to over their life.
# Otherwise: fade in from `from` to `to`, then fade out.
func fade_ramp(from: Color, to: Color, burst: bool = false) -> Gradient:
	var ramp = Gradient.new()
	if burst:
		ramp.set_color(0, from)
		ramp.set_color(1, to)
	else:
		ramp.set_color(0, from)
		ramp.set_color(1, Color(to, 0.0))
		ramp.add_point(0.2, to)
	return ramp

func make_button(text: String, pressed_signal: Signal) -> Button:
	var button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(240, 64)
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 26)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, CREAM if state != "font_hover_color" else GOLD.lightened(0.35))
	for state in ["normal", "hover", "pressed", "focus"]:
		var box = StyleBoxFlat.new()
		box.bg_color = DARK.lightened(0.12) if state == "hover" else DARK
		box.border_color = GOLD
		box.set_border_width_all(3)
		box.set_corner_radius_all(10)
		box.shadow_color = Color(0, 0, 0, 0.45)
		box.shadow_size = 8
		if state == "focus":
			box.draw_center = false
		button.add_theme_stylebox_override(state, box)
	button.pressed.connect(func(): pressed_signal.emit())
	return button

func play(winner_name: String, winner_texture: Texture2D):
	name_label.text = winner_name
	fit_name()
	piece.texture = winner_texture
	reset()
	visible = true

	var t = create_tween()
	t.tween_property(dim, "color:a", DIM_ALPHA, 0.35)

	# Swords slam in from both sides and meet at the centre
	for i in 2:
		var side = -1 if i == 0 else 1
		var sword: Sprite2D = swords[i]
		var tween = create_tween().set_parallel()
		tween.tween_property(sword, "position", CENTER, SWORD_FLIGHT) \
			.set_delay(CLASH_AT - SWORD_FLIGHT).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		tween.tween_property(sword, "rotation", -side * SWORD_ANGLE, SWORD_FLIGHT) \
			.set_delay(CLASH_AT - SWORD_FLIGHT).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		# Recoil from the hit, then settle crossed
		tween.chain().tween_property(sword, "rotation", -side * (SWORD_ANGLE + 0.09), 0.08)
		tween.chain().tween_property(sword, "rotation", -side * SWORD_ANGLE, 0.35) \
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	get_tree().create_timer(CLASH_AT).timeout.connect(clash)

	# The ribbon drops in over the swords with a small bounce
	var drop = create_tween()
	drop.tween_interval(RIBBON_AT)
	drop.tween_callback(func(): ribbon.visible = true)
	drop.tween_property(ribbon, "position:y", RIBBON_REST_Y, RIBBON_DROP) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	drop.parallel().tween_property(ribbon, "modulate:a", 1.0, 0.2)
	drop.tween_callback(func(): gold_dust.emitting = true)

	# Winner's name stamps onto the ribbon, then the piece rises in and bobs
	var reveal = create_tween()
	reveal.tween_interval(NAME_AT)
	reveal.tween_property(name_label, "modulate:a", 1.0, 0.25)
	reveal.parallel().tween_property(name_label, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	reveal.parallel().tween_property(piece, "modulate:a", 1.0, 0.4)
	reveal.parallel().tween_property(piece, "position:y", PIECE_POSITION.y, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	reveal.tween_callback(start_bob)

	var finish = create_tween()
	finish.tween_interval(BUTTONS_AT)
	finish.tween_callback(func(): buttons.visible = true)
	finish.tween_property(buttons, "modulate:a", 1.0, 0.35)
	finish.tween_callback(func(): finished.emit())

# Everything back to its starting pose, so play() can run more than once
func reset():
	for i in 2:
		var side = -1 if i == 0 else 1
		swords[i].position = CENTER + Vector2(side * (960 + SWORD_START_X), 260)
		swords[i].rotation = -side * deg_to_rad(80)
	spark.visible = false
	for small in small_sparks:
		small.visible = false
	ribbon.visible = false
	ribbon.modulate.a = 0.0
	ribbon.position = Vector2(960, -420)
	name_label.modulate.a = 0.0
	name_label.scale = Vector2.ONE * 1.6
	piece.position = PIECE_POSITION + Vector2(0, 60)
	piece.modulate.a = 0.0
	buttons.visible = false
	buttons.modulate.a = 0.0
	gold_dust.emitting = false
	stage.position = Vector2.ZERO
	if bob:
		bob.kill()

# Shrinks long names so they stay on the ribbon's flat middle
func fit_name():
	var size = 64
	while size > 24 and FONT.get_string_size(name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > RIBBON_BAND_SIZE.x - 40:
		size -= 2
	name_label.add_theme_font_size_override("font_size", size)

# The swords meet: big spark, scattered small ones, embers, a white flash and a shake
func clash():
	spark.position = CENTER
	spark.visible = true
	spark.scale = Vector2.ONE * 0.2
	spark.modulate = Color(1.6, 1.4, 1.0, 1.0) # Brighter than the art, since it's added
	var t = create_tween().set_parallel()
	t.tween_property(spark, "scale", Vector2.ONE * 1.7, 0.45).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(spark, "rotation", rng.randf_range(-0.4, 0.4), 0.6)
	t.tween_property(spark, "modulate:a", 0.0, 0.5).set_delay(0.2)

	for small in small_sparks:
		var angle = rng.randf() * TAU
		small.position = CENTER + Vector2.from_angle(angle) * rng.randf_range(60, 260)
		small.scale = Vector2.ZERO
		small.rotation = rng.randf() * TAU
		small.modulate = Color(1.5, 1.3, 1.0, 1.0)
		small.visible = true
		var delay = rng.randf_range(0.0, 0.18)
		var size = rng.randf_range(0.25, 0.55)
		t.tween_property(small, "scale", Vector2.ONE * size, 0.25).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(small, "position", small.position + Vector2.from_angle(angle) * 70, 0.6).set_delay(delay)
		t.tween_property(small, "modulate:a", 0.0, 0.35).set_delay(delay + 0.25)

	embers.restart()
	embers.emitting = true

	flash.color.a = 0.75
	t.tween_property(flash, "color:a", 0.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	shake(0.35, 18.0)

# Shakes the swords, sparks and ribbon and the board behind them (not the dim,
# whose edges would show), easing off over the duration
func shake(duration: float, strength: float):
	var viewport = get_viewport()
	var board_transform = viewport.canvas_transform
	var t = create_tween()
	t.tween_method(func(amount: float):
		var jolt = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * strength * amount
		stage.position = jolt
		viewport.canvas_transform = board_transform.translated(jolt), 1.0, 0.0, duration)
	t.tween_callback(func():
		stage.position = Vector2.ZERO
		viewport.canvas_transform = board_transform)

func start_bob():
	bob = create_tween().set_loops()
	bob.tween_property(piece, "position:y", PIECE_POSITION.y - BOB_HEIGHT, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(piece, "position:y", PIECE_POSITION.y, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
