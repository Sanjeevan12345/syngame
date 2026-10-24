@tool
class_name ScaledPanel
extends MarginContainer
# Draws one of the Main Screen UI Assets behind its children as a nine-slice.
# The art is drawn scaled down as a whole, so the ornate corners, scroll rollers
# and gems keep their shape at any panel size instead of being squashed.
# The writable margins depend only on art_scale, never on the panel's size:
# sizing them from the size would resize the panel and loop forever.

enum Art { PARCHMENT, ORNATE_FRAME, SCROLL_ORANGE, SCROLL_BLUE }

const ASSET_DIR = "res://assets/Main Screen UI Assets/"

# Per art, in texture pixels: the opaque region of the image, the nine-slice
# margins (left, top, right, bottom), where the writable area starts, and the
# default scale the art is drawn at
const ART_DATA = {
	Art.PARCHMENT: {
		"file": "paper_asset.png",
		"region": Rect2(360, 48, 2032, 1016),
		"slice": [80, 80, 80, 80],
		"content": [90, 70, 90, 70],
		"scale": 0.38,
	},
	Art.ORNATE_FRAME: {
		"file": "paper_asset_2.png",
		"region": Rect2(80, 40, 3968, 948),
		"slice": [330, 190, 330, 190],
		"content": [200, 90, 200, 90],
		"scale": 0.2,
	},
	Art.SCROLL_ORANGE: {
		"file": "scroll_orange.png",
		"region": Rect2(22, 124, 626, 134),
		"slice": [40, 44, 40, 30],
		"content": [46, 22, 46, 31],
		"scale": 1.1,
	},
	Art.SCROLL_BLUE: {
		"file": "scroll_blue.png",
		"region": Rect2(30, 94, 736, 154),
		"slice": [40, 46, 40, 30],
		"content": [50, 22, 50, 33],
		"scale": 1.06,
	},
}

# Smallest height (texture pixels) left for the stretchable middle row
const MIN_MIDDLE = 8.0

@export var art: Art = Art.PARCHMENT:
	set(value):
		art = value
		_apply_art()

# Scale the art is drawn at; 0 uses the art's default from ART_DATA
@export var art_scale: float = 0.0:
	set(value):
		art_scale = value
		_apply_art()

var _box := StyleBoxTexture.new()

func _init():
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready():
	_apply_art()

func _apply_art():
	var data = ART_DATA[art]
	_box.texture = load(ASSET_DIR + data.file)
	_box.region_rect = data.region
	_box.texture_margin_left = data.slice[0]
	_box.texture_margin_top = data.slice[1]
	_box.texture_margin_right = data.slice[2]
	_box.texture_margin_bottom = data.slice[3]

	var layout_scale = get_art_scale()
	var sides = ["margin_left", "margin_top", "margin_right", "margin_bottom"]
	for k in sides.size():
		add_theme_constant_override(sides[k], int(round(data.content[k] * layout_scale)))
	queue_redraw()

func get_art_scale() -> float:
	return art_scale if art_scale > 0.0 else ART_DATA[art].scale

func _draw():
	if _box.texture == null or size.x <= 0 or size.y <= 0:
		return
	# Draw smaller than art_scale only when the panel is too small to fit the
	# nine-slice edges; this affects drawing alone, not layout
	var data = ART_DATA[art]
	var draw_scale = minf(get_art_scale(), minf(
		size.x / (data.slice[0] + data.slice[2] + MIN_MIDDLE),
		size.y / (data.slice[1] + data.slice[3] + MIN_MIDDLE)))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * draw_scale)
	draw_style_box(_box, Rect2(Vector2.ZERO, size / draw_scale))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
