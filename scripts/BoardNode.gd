extends Marker2D
class_name BoardNode

enum TileType { MONOPOLY, ENTRY_GATE, LUDO, SAFE_HAVEN, THRONE, TAX, CARD }

@export_category("Node Properties")
@export var node_id: int = 0
@export var tile_type: TileType = TileType.MONOPOLY

@export_category("Monopoly Data")
@export var property_name: String = ""
@export var purchase_cost: int = 200
@export var base_rent: int = 50
@export var owner_id: int = -1 # -1 = Unowned
@export var color_set: String = "" # Kingdoms sharing a color band on the board form a set

@export_category("Special Tile Data")
@export var tile_gold: int = 0 # Gold paid when landing on a TAX tile
@export_enum("Dharma", "Adharma") var card_deck: int = 0 # Deck drawn from on a CARD tile

@export_category("Path Connections")
@export var next_node: BoardNode          # Standard clockwise path
@export var branch_ludo_node: BoardNode   # Used on Gates: diverts into the outer Ludo loop
@export var straight_throne_node: BoardNode # Used on Gates: straight bridge to Hastinapur
@export var home_stretch_node: BoardNode  # Used on Ludo arm tips: first tile of that arm's Home Stretch
@export var exit_gate_node: BoardNode     # Used on Ludo arm tips: outer-ring gate a pawn can exit through

@export_category("Combat")
@export var is_safe: bool = false # Safe House: pawns here can't be captured

# Ownership pennant per player (pawnNtag = player N). Each image is mostly
# transparent, so only the pennant's visible region is drawn.
const OWNER_TAGS = [
	{"texture": preload("res://assets/ownership_tags/pawn1tag.png"), "region": Rect2(664, 468, 720, 1132)},
	{"texture": preload("res://assets/ownership_tags/pawn2tag.png"), "region": Rect2(592, 367, 863, 1326)},
	{"texture": preload("res://assets/ownership_tags/pawn3tag.png"), "region": Rect2(613, 399, 824, 1250)},
	{"texture": preload("res://assets/ownership_tags/pawn4tag.png"), "region": Rect2(576, 463, 897, 1121)},
]
const OWNER_TAG_HEIGHT: float = 44.0

func _ready():
	if is_kingdom():
		add_to_group("kingdoms")
	# The tags are drawn far smaller than their source art
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

# Name for messages; unnamed Ludo track tiles fall back to a generic label
func get_display_name() -> String:
	if property_name != "":
		return property_name
	return "the Ludo track"

# Only priced Monopoly tiles are Kingdoms that can be bought
func is_kingdom() -> bool:
	return tile_type == TileType.MONOPOLY and purchase_cost > 0

func set_kingdom_owner(player_id: int):
	owner_id = player_id
	if player_id == -1:
		building_level = 0 # Buildings never survive a return to the Bank
	queue_redraw()

# 0-4 = number of Forts, 5 = Palace
var building_level: int = 0

func set_building_level(level: int):
	building_level = level
	queue_redraw()

# Flies the owner's pennant on owned Kingdoms and shows their Forts / Palace.
# Safe Houses are marked in the board art itself.
func _draw():
	if owner_id >= 0:
		draw_owner_tag()
	draw_buildings()

func draw_owner_tag():
	var tag = OWNER_TAGS[owner_id % OWNER_TAGS.size()]
	var region: Rect2 = tag.region
	var size = Vector2(region.size.x / region.size.y * OWNER_TAG_HEIGHT, OWNER_TAG_HEIGHT)
	draw_texture_rect_region(tag.texture, Rect2(-size / 2, size), region)

func draw_buildings():
	var gold = Color(0.95, 0.75, 0.25)
	var dark = Color(0.25, 0.1, 0.05)
	if building_level == GameManager.PALACE_LEVEL:
		# One larger crimson Palace with a gold dome
		var palace = Rect2(-13, -44, 26, 14)
		draw_rect(palace, Color(0.6, 0.08, 0.08))
		draw_rect(palace, gold, false, 2)
		draw_circle(Vector2(0, -46), 5, gold)
	elif building_level > 0:
		# A row of small gold Forts
		var width = building_level * 10 - 2
		for i in building_level:
			var fort = Rect2(-width / 2.0 + i * 10, -40, 8, 8)
			draw_rect(fort, gold)
			draw_rect(fort, dark, false, 1)
