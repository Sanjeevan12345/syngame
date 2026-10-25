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

var selected_player_count: int = 0 # Set by the opening page; 0 = use MainBoard's own setting
var pending_load: Dictionary = {} # Saved game the main board restores when it next starts

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

# Forts and Palaces. building_level 0-4 = Forts, 5 = Palace (replaces 4 Forts).
const MAX_FORTS: int = 4
const PALACE_LEVEL: int = 5
const FORT_COST_BY_SET = {
	"Slate": 50, "Pink": 50, "Orange": 100, "Green": 100,
	"Blue": 150, "Crimson": 150, "Black": 200,
}
const RENT_MULTIPLIERS = [1, 4, 10, 20, 30, 40] # Indexed by building_level
const SET_BONUS_MULTIPLIER: int = 2 # Full colour set, no buildings yet
const BUILDING_RESALE_RATE: float = 0.5
const TOTAL_FORTS: int = 32 # Limited Bank supply
const TOTAL_PALACES: int = 12
const REPAIR_TAX_PER_FORT: int = 25
const REPAIR_TAX_PER_PALACE: int = 100

# Scores two Pasa sticks can produce; Shakuni's card lets a player pick one
const PASA_SCORES = [1, 2, 3, 4, 5, 6, 12]

# Card draws, indexed by BoardNode.card_deck (0 = Dharma, 1 = Adharma).
# effect: gold (amount from/to the Bank), collect_each / pay_each (amount from/to
# every opponent), go_to_start (bonus: pays the Start bonus), enter_ludo (through
# the next gate ahead), skip_self, skip_next, extra_turn, shakuni (pick next roll),
# free_fort (amount = Gold instead if nothing can be built), burn_fort, repair_tax
const CARD_DECKS = [
	[
		{"text": "Krishna's counsel guides your treasury.", "effect": "gold", "amount": 200},
		{"text": "Yudhishthira's honesty wins every merchant's trust.", "effect": "gold", "amount": 150},
		{"text": "Vidura's wise policy fills the royal coffers.", "effect": "gold", "amount": 120},
		{"text": "The rishis bless your yajna.", "effect": "gold", "amount": 100},
		{"text": "Vishwakarma raises a free Fort in your realm.", "effect": "free_fort", "amount": 100},
		{"text": "Pilgrims bring offerings to your temples.", "effect": "gold", "amount": 60},
		{"text": "Dharma prevails: the treasury overflows.", "effect": "gold", "amount": 250},
		{"text": "Allied kings send tribute to your court.", "effect": "collect_each", "amount": 50},
		{"text": "Drona's students pay their guru dakshina.", "effect": "collect_each", "amount": 40},
		{"text": "Bhishma's wisdom settles a dispute in your favour.", "effect": "collect_each", "amount": 60},
		{"text": "Advance to Rajasuya Yajna for the great sacrifice.", "effect": "go_to_start", "bonus": true},
		{"text": "Kunti's blessing calls you home to Rajasuya Yajna.", "effect": "go_to_start", "bonus": true},
		{"text": "Krishna's chariot carries your pawn through the next gate.", "effect": "enter_ludo"},
		{"text": "Arjuna clears the way: enter the Ludo board at the next gate.", "effect": "enter_ludo"},
		{"text": "Bhima's strength carries you onward: throw again.", "effect": "extra_turn"},
		{"text": "Hanuman's banner flies on your chariot: throw again.", "effect": "extra_turn"},
		{"text": "Vidura's warning delays your rival: the next player skips their turn.", "effect": "skip_next"},
		{"text": "Arjuna's arrows pin down your rival: the next player skips their turn.", "effect": "skip_next"},
	],
	[
		{"text": "Shakuni's loaded dice: choose your roll on your next turn.", "effect": "shakuni"},
		{"text": "The lac palace burns: rebuild your court.", "effect": "gold", "amount": -200},
		{"text": "Jarasandha's siege drains your treasury.", "effect": "gold", "amount": -175},
		{"text": "Duryodhana's envy burns your granary.", "effect": "gold", "amount": -150},
		{"text": "Bandits raid your caravan.", "effect": "gold", "amount": -120},
		{"text": "Bribes are demanded at the court of Hastinapura.", "effect": "gold", "amount": -110},
		{"text": "Fire sweeps your strongholds: one Fort burns.", "effect": "burn_fort"},
		{"text": "Royal repairs: pay 25 per Fort and 100 per Palace.", "effect": "repair_tax"},
		{"text": "Dushasana's insult: pay each rival to keep the peace.", "effect": "pay_each", "amount": 50},
		{"text": "You lose a wager in the Hall of Dice: pay each rival.", "effect": "pay_each", "amount": 40},
		{"text": "A failed alliance costs you gifts to every rival.", "effect": "pay_each", "amount": 60},
		{"text": "Kichaka's treachery: you are sent back to Rajasuya Yajna.", "effect": "go_to_start", "bonus": false},
		{"text": "Exile! Return to Rajasuya Yajna empty-handed.", "effect": "go_to_start", "bonus": false},
		{"text": "The Chakravyuha pulls you onto the Ludo board at the next gate.", "effect": "enter_ludo"},
		{"text": "Gandhari's curse: skip your next turn.", "effect": "skip_self"},
		{"text": "Drought grips your lands: skip your next turn.", "effect": "skip_self"},
		{"text": "Ashwatthama's night raid: skip your next turn.", "effect": "skip_self"},
		{"text": "Jayadratha blocks your trade routes: skip your next turn.", "effect": "skip_self"},
	],
]

# Shuffled cards still to be drawn from each deck; refilled when empty
var draw_piles: Array = [[], []]

var forts_available: int = TOTAL_FORTS
var palaces_available: int = TOTAL_PALACES

var player_skip_turns: Array = [0, 0, 0, 0] # Turns each player must still skip
var player_shakuni: Array = [false, false, false, false] # Picks their next roll

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
	player_skip_turns.resize(total_players)
	player_skip_turns.fill(0)
	player_shakuni.resize(total_players)
	player_shakuni.fill(false)
	draw_piles = [[], []]
	forts_available = TOTAL_FORTS
	palaces_available = TOTAL_PALACES

# Saved-game data for everything the GameManager tracks except Kingdom lists,
# which MainBoard rebuilds from each Kingdom's owner. Draw piles are stored as
# card indices so a save survives edits to the card text.
func export_state() -> Dictionary:
	var piles = []
	for deck in draw_piles.size():
		piles.append(draw_piles[deck].map(func(card): return CARD_DECKS[deck].find(card)))
	return {
		"active_player": active_player_index,
		"player_suvarnas": player_suvarnas.duplicate(),
		"player_kills": player_kills.duplicate(),
		"player_eliminated": player_eliminated.duplicate(),
		"player_skip_turns": player_skip_turns.duplicate(),
		"player_shakuni": player_shakuni.duplicate(),
		"forts_available": forts_available,
		"palaces_available": palaces_available,
		"draw_piles": piles,
	}

# Restores export_state() data after setup_players(); JSON numbers come back as floats
func import_state(data: Dictionary):
	active_player_index = int(data.active_player)
	player_suvarnas = data.player_suvarnas.map(func(v): return int(v))
	player_kills = data.player_kills.map(func(v): return int(v))
	player_eliminated = data.player_eliminated.map(func(v): return bool(v))
	player_skip_turns = data.player_skip_turns.map(func(v): return int(v))
	player_shakuni = data.player_shakuni.map(func(v): return bool(v))
	forts_available = int(data.forts_available)
	palaces_available = int(data.palaces_available)
	draw_piles = [[], []]
	for deck in draw_piles.size():
		for index in data.draw_piles[deck]:
			if int(index) >= 0 and int(index) < CARD_DECKS[deck].size():
				draw_piles[deck].append(CARD_DECKS[deck][int(index)])

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

# Sells a Kingdom back to the Bank; returns the Gold received. A Kingdom can't be
# sold while any Kingdom in its colour set still has buildings.
func sell_kingdom(player_id: int, node: BoardNode) -> int:
	if node.owner_id != player_id or set_has_buildings(node.color_set):
		return 0
	var value = resale_value(node)
	player_kingdoms[player_id].erase(node)
	node.set_kingdom_owner(-1)
	add_gold(player_id, value)
	return value

# Gold plus what every owned Kingdom and building would sell for: the most a
# player can ever pay
func total_balance(player_id: int) -> int:
	var total: int = player_suvarnas[player_id]
	for node in player_kingdoms[player_id]:
		total += resale_value(node) + building_resale(node)
	return total

# --- Forts & Palaces ---

func get_set_kingdoms(color_set: String) -> Array:
	return get_tree().get_nodes_in_group("kingdoms").filter(func(n): return n.color_set == color_set)

func owns_full_set(player_id: int, color_set: String) -> bool:
	if color_set == "":
		return false
	return get_set_kingdoms(color_set).all(func(n): return n.owner_id == player_id)

func set_has_buildings(color_set: String) -> bool:
	return get_set_kingdoms(color_set).any(func(n): return n.building_level > 0)

func fort_cost(node: BoardNode) -> int:
	return FORT_COST_BY_SET.get(node.color_set, 100)

# What the Bank pays back for all buildings on a Kingdom (a Palace counts as
# 4 Forts plus the Palace upgrade)
func building_resale(node: BoardNode) -> int:
	return int(fort_cost(node) * node.building_level * BUILDING_RESALE_RATE)

func calc_rent(node: BoardNode) -> int:
	if node.building_level > 0:
		return node.base_rent * RENT_MULTIPLIERS[node.building_level]
	if owns_full_set(node.owner_id, node.color_set):
		return node.base_rent * SET_BONUS_MULTIPLIER
	return node.base_rent

# "" if the player may raise this Kingdom one level now, otherwise why not.
# ignore_cost is used by the free Fort card.
func build_block_reason(player_id: int, node: BoardNode, ignore_cost: bool = false) -> String:
	if node.owner_id != player_id or not owns_full_set(player_id, node.color_set):
		return "needs full set"
	if node.building_level >= PALACE_LEVEL:
		return "Palace built"
	var lowest = get_set_kingdoms(node.color_set).map(func(n): return n.building_level).min()
	if node.building_level > lowest:
		return "build evenly"
	if node.building_level < MAX_FORTS and forts_available <= 0:
		return "no Forts left"
	if node.building_level == MAX_FORTS and palaces_available <= 0:
		return "no Palaces left"
	if not ignore_cost and not can_afford(player_id, fort_cost(node)):
		return "not enough Gold"
	return ""

func can_build(player_id: int, node: BoardNode) -> bool:
	return build_block_reason(player_id, node) == ""

# Adds a Fort, or swaps 4 Forts for a Palace. free skips the cost (card effect).
func build_on(player_id: int, node: BoardNode, free: bool = false) -> bool:
	if build_block_reason(player_id, node, free) != "":
		return false
	if not free:
		add_gold(player_id, -fort_cost(node))
	if node.building_level < MAX_FORTS:
		forts_available -= 1
		node.set_building_level(node.building_level + 1)
	else:
		palaces_available -= 1
		forts_available += MAX_FORTS
		node.set_building_level(PALACE_LEVEL)
	return true

# Selling goes evenly too: only a Kingdom at its set's highest level can be lowered
func can_sell_building(player_id: int, node: BoardNode) -> bool:
	if node.owner_id != player_id or node.building_level == 0:
		return false
	var highest = get_set_kingdoms(node.color_set).map(func(n): return n.building_level).max()
	return node.building_level == highest

# Lowers a Kingdom one step and returns the pieces to the Bank; returns how many
# levels were removed. A Palace drops back to 4 Forts, or to as many as the Bank has.
func remove_building_level(node: BoardNode) -> int:
	if node.building_level == PALACE_LEVEL:
		palaces_available += 1
		var forts = mini(MAX_FORTS, forts_available)
		forts_available -= forts
		node.set_building_level(forts)
		return PALACE_LEVEL - forts
	if node.building_level > 0:
		forts_available += 1
		node.set_building_level(node.building_level - 1)
		return 1
	return 0

# Sells one building step back to the Bank at half its build price
func sell_building(player_id: int, node: BoardNode) -> int:
	if not can_sell_building(player_id, node):
		return 0
	var levels = remove_building_level(node)
	var value = int(fort_cost(node) * levels * BUILDING_RESALE_RATE)
	add_gold(player_id, value)
	return value

# Returns {"forts": n, "palaces": n} across all of a player's Kingdoms
func count_buildings(player_id: int) -> Dictionary:
	var counts = {"forts": 0, "palaces": 0}
	for node in player_kingdoms[player_id]:
		if node.building_level == PALACE_LEVEL:
			counts["palaces"] += 1
		else:
			counts["forts"] += node.building_level
	return counts

# Kingdom the free Fort card builds on: the lowest one that may be raised, or null
func find_free_fort_target(player_id: int) -> BoardNode:
	var best: BoardNode = null
	for node in player_kingdoms[player_id]:
		if build_block_reason(player_id, node, true) == "" \
				and (best == null or node.building_level < best.building_level):
			best = node
	return best

# Removes a bankrupt player: their buildings and Kingdoms are sold to the Bank
# and all their Gold is taken. Returns everything they were worth.
func eliminate_player(player_id: int) -> int:
	for node in player_kingdoms[player_id]:
		add_gold(player_id, building_resale(node))
		if node.building_level == PALACE_LEVEL:
			palaces_available += 1
		else:
			forts_available += node.building_level
		node.set_building_level(0)
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

# Every card in a deck comes up once before the deck is reshuffled
func draw_card(deck: int) -> Dictionary:
	if draw_piles[deck].is_empty():
		draw_piles[deck] = CARD_DECKS[deck].duplicate()
		draw_piles[deck].shuffle()
	return draw_piles[deck].pop_back()

# Next player after this one in turn order who is still in the game
func next_active_opponent(player_id: int) -> int:
	var next = (player_id + 1) % total_players
	while player_eliminated[next]:
		next = (next + 1) % total_players
	return next

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

# Call this after a pawn finishes moving. Returns every opponent pawn sharing the
# landing tile that would be captured (empty if there is no Vadh). The caller
# captures them with execute_vadh_capture, after the fight animation.
func find_vadh_victims(moving_pawn: Pawn, all_pawns: Array, start_node: BoardNode) -> Array:
	var victims: Array = []
	var node = moving_pawn.current_node

	if is_safe_tile(node, start_node):
		return victims

	for other_pawn in all_pawns:
		if other_pawn.current_node == node and other_pawn.owner_id != moving_pawn.owner_id:
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
