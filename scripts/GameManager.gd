extends Node
#class_name GameManager

static var instance: GameManager

# Player Data Arrays
var active_player_index: int = 0
var total_players: int = 4
var player_suvarnas: Array = [1000, 1000, 1000, 1000] # Gold Coins
var player_kills: Array = [0, 0, 0, 0]
var player_kingdoms: Array = [[], [], [], []] # Holds the BoardNodes owned by each player
var player_eliminated: Array = [false, false, false, false] # True once a player goes bankrupt

var current_dice_roll: int = 0
var is_waiting_for_input: bool = true

signal turn_changed(player_id: int)
signal dice_rolled(roll_value: int)
signal gold_changed(player_id: int, new_amount: int)
signal kills_changed(player_id: int, new_kills: int)

const PAWNS_PER_PLAYER: int = 3
const PLAYER_COLORS = [Color.RED, Color.DODGER_BLUE, Color.LIME_GREEN, Color.GOLD]

const STARTING_GOLD: int = 1000
const START_BONUS: int = 200 # Paid for passing or landing on Rajasuva Yajna
const UNQUALIFIED_LAP_BONUS: int = 200 # Paid for a Ludo lap finished without Home Stretch entry
const HOME_STRETCH_SETS_REQUIRED: int = 1
const HOME_STRETCH_KILLS_REQUIRED: int = 3
const RESALE_RATE: float = 0.75 # Share of the purchase price the Bank pays back for a Kingdom

# Card draws, indexed by BoardNode.card_deck (0 = Dharma, 1 = Adharma)
const CARD_DECKS = [
	[
		{"text": "A grateful king sends tribute.", "gold": 150},
		{"text": "The rishis bless your yajna.", "gold": 100},
		{"text": "Merchants pay for safe passage.", "gold": 75},
		{"text": "You win a wager in the Hall of Dice.", "gold": 50},
	],
	[
		{"text": "Bandits raid your caravan.", "gold": -150},
		{"text": "You lose a wager at dice.", "gold": -100},
		{"text": "A failed alliance costs you gifts.", "gold": -75},
		{"text": "Pay penance at the temple.", "gold": -50},
	],
]

func _enter_tree():
	instance = self

# Resets turn order and per-player stats for a 2-4 player game
func setup_players(count: int):
	total_players = clampi(count, 2, 4)
	active_player_index = 0
	is_waiting_for_input = true
	player_suvarnas.resize(total_players)
	player_suvarnas.fill(STARTING_GOLD)
	player_kills.resize(total_players)
	player_kills.fill(0)
	player_kingdoms.clear()
	for i in total_players:
		player_kingdoms.append([])
	player_eliminated.resize(total_players)
	player_eliminated.fill(false)

func add_gold(player_id: int, amount: int):
	player_suvarnas[player_id] += amount
	gold_changed.emit(player_id, player_suvarnas[player_id])

func can_afford(player_id: int, amount: int) -> bool:
	return player_suvarnas[player_id] >= amount

func buy_kingdom(player_id: int, node: BoardNode) -> bool:
	if not node.is_kingdom() or node.owner_id != -1 or not can_afford(player_id, node.purchase_cost):
		return false
	add_gold(player_id, -node.purchase_cost)
	node.set_kingdom_owner(player_id)
	player_kingdoms[player_id].append(node)
	return true

# What the Bank pays for a Kingdom (75% of its purchase price, rounded down)
func resale_value(node: BoardNode) -> int:
	return int(node.purchase_cost * RESALE_RATE)

# Sells a Kingdom back to the Bank; returns the Gold received
func sell_kingdom(player_id: int, node: BoardNode) -> int:
	if node.owner_id != player_id:
		return 0
	var value = resale_value(node)
	player_kingdoms[player_id].erase(node)
	node.set_kingdom_owner(-1)
	add_gold(player_id, value)
	return value

# Gold plus what every owned Kingdom would sell for: the most a player can ever pay
func total_balance(player_id: int) -> int:
	var total: int = player_suvarnas[player_id]
	for node in player_kingdoms[player_id]:
		total += resale_value(node)
	return total

# Removes a bankrupt player: their Kingdoms are sold to the Bank and all their
# Gold is taken. Returns everything they were worth.
func eliminate_player(player_id: int) -> int:
	for node in player_kingdoms[player_id].duplicate():
		sell_kingdom(player_id, node)
	var worth: int = player_suvarnas[player_id]
	add_gold(player_id, -worth)
	player_eliminated[player_id] = true
	return worth

func get_remaining_players() -> Array:
	var remaining: Array = []
	for player_id in total_players:
		if not player_eliminated[player_id]:
			remaining.append(player_id)
	return remaining

func draw_card(deck: int) -> Dictionary:
	return CARD_DECKS[deck].pick_random()

func roll_dice() -> int:
	if not is_waiting_for_input:
		return 0

	current_dice_roll = randi_range(1, 6)
	is_waiting_for_input = false
	emit_signal("dice_rolled", current_dice_roll)
	return current_dice_roll

# Number of color sets in which this player owns every Kingdom
func count_color_sets(player_id: int) -> int:
	var sets: Dictionary = {} # color_set -> true while every Kingdom in it is this player's
	for node in get_tree().get_nodes_in_group("kingdoms"):
		if node.color_set != "":
			sets[node.color_set] = sets.get(node.color_set, true) and node.owner_id == player_id
	return sets.values().count(true)

# Home Stretch entry needs at least 1 full color set AND enough Vadh kills
func can_enter_home_stretch(player_id: int) -> bool:
	return count_color_sets(player_id) >= HOME_STRETCH_SETS_REQUIRED \
		and player_kills[player_id] >= HOME_STRETCH_KILLS_REQUIRED

func end_turn():
	# Skip players who have gone bankrupt
	active_player_index = (active_player_index + 1) % total_players
	while player_eliminated[active_player_index]:
		active_player_index = (active_player_index + 1) % total_players
	is_waiting_for_input = true
	emit_signal("turn_changed", active_player_index)

# Start, Safe Houses and tiles marked SAFE_HAVEN or THRONE can never host a capture
func is_safe_tile(node: BoardNode, start_node: BoardNode) -> bool:
	return node == start_node or node.is_safe \
		or node.tile_type == BoardNode.TileType.SAFE_HAVEN \
		or node.tile_type == BoardNode.TileType.THRONE

# Call this after a pawn finishes moving. Captures every opponent pawn sharing
# the landing tile and returns them (empty if there was no Vadh).
func resolve_vadh(moving_pawn: Pawn, all_pawns: Array, start_node: BoardNode) -> Array:
	var victims: Array = []
	var node = moving_pawn.current_node

	if is_safe_tile(node, start_node):
		return victims

	for other_pawn in all_pawns:
		if other_pawn.current_node == node and other_pawn.owner_id != moving_pawn.owner_id:
			execute_vadh_capture(moving_pawn, other_pawn, start_node)
			victims.append(other_pawn)

	return victims

func execute_vadh_capture(attacker: Pawn, victim: Pawn, start_node: BoardNode):
	print("VADH! Player ", attacker.owner_id + 1, " captured Player ", victim.owner_id + 1, "'s pawn!")

	# Increment Kill Count
	player_kills[attacker.owner_id] += 1
	kills_changed.emit(attacker.owner_id, player_kills[attacker.owner_id])

	# Send victim back to Start (Rajasuva Yajna) without paying the Start bonus.
	# A pawn caught on the Ludo track loses its progress and must re-enter through a gate.
	victim.reset_to_start(start_node)
