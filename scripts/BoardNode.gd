extends Marker2D
class_name BoardNode

enum TileType { MONOPOLY, ENTRY_GATE, LUDO, SAFE_HAVEN, THRONE }

@export_category("Node Properties")
@export var node_id: int = 0
@export var tile_type: TileType = TileType.MONOPOLY

@export_category("Monopoly Data")
@export var property_name: String = ""
@export var purchase_cost: int = 200
@export var base_rent: int = 50
@export var owner_id: int = -1 # -1 = Unowned

@export_category("Path Connections")
@export var next_node: BoardNode          # Standard clockwise path
@export var branch_ludo_node: BoardNode   # Used on Gates: diverts into the outer Ludo loop
@export var straight_throne_node: BoardNode # Used on Gates: straight bridge to Hastinapur
