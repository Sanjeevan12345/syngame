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

func _ready():
	if is_kingdom():
		add_to_group("kingdoms")

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
	queue_redraw()

# Rings owned Kingdoms in the owner's color, and marks Safe Houses on the Ludo track
func _draw():
	if is_safe and tile_type == TileType.LUDO:
		draw_arc(Vector2.ZERO, 11, 0, TAU, 24, Color.WHITE, 2)
	if owner_id >= 0:
		draw_arc(Vector2.ZERO, 24, 0, TAU, 32, GameManager.PLAYER_COLORS[owner_id], 4)
