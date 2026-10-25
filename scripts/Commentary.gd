class_name Commentary
extends Node
# Decides when Shakuni and Narada speak. Lines come from the dialogue JSON and
# are matched to game events by their "when" text, so lines can be reworded or
# added there without code changes. Paced so the banter never floods the game.

const LINES_PATH = "res://assets/charac_talks/shakuni_narada_dialogues_simple.json"

# "when" texts used in the JSON
const GAME_STARTS = "When the game starts"
const COLLECTS_START = "When the player passes Rajasuya Yajna (Start) and collects coins"
const BUYS_KINGDOM = "When the player buys a kingdom"
const RIVAL_BUYS_KINGDOM = "When a rival buys a kingdom"
const HALL_OF_DICE = "When the player lands on Hall of Dice"
const PAYS_RENT = "When the player pays rent"
const BUILDS_FORT = "When the player builds a fort"
const KAMYAKA_FOREST = "When the player lands on Kamyaka Forest (exile)"
const LOW_ON_COINS = "When the player is running low on coins"
const DWARKA_HAVEN = "When the player lands on Dwarka Haven"
const DRAWS_CARD = "When the player draws a card"
const IN_THE_LEAD = "When the player is in the lead"
const MAGADHA = "When the player lands on Magadha"
const GANDHARA = "When the player lands on Gandhara"
const LOT_OF_COINS = "When the player has a lot of coins"
const GOES_BANKRUPT = "When the player goes bankrupt"
const GAME_ENDS = "When the game ends"
const TRASH_TALK = "Randomly, at any time during the game (trash talk)"

# Pacing, in seconds
const EVENT_GAP: float = 25.0 # Since the last line, before an ordinary event may speak
const TRIGGER_COOLDOWN: float = 90.0 # Before the same event may speak again
const RANDOM_INTERVAL_MIN: float = 60.0
const RANDOM_INTERVAL_MAX: float = 120.0
const RANDOM_QUIET: float = 30.0 # Since the last line, before trash talk may speak

# Gold thresholds; each fires once and re-arms only after recovering past the second value
const LOW_GOLD: int = 300
const LOW_GOLD_RESET: int = 500
const RICH_GOLD: int = 2000
const RICH_GOLD_RESET: int = 1500
const LEAD_MARGIN: int = 300

var popup: CharacterPopup
var lines_by_when: Dictionary = {} # when -> Array of {name, text}
var queue: Array = []
var last_shown_at: float = -INF
var last_trigger_at: Dictionary = {}
var trash_talk_bag: Array = [] # Shuffled; refilled once every line has been heard
var random_timer: Timer
var low_warned: Dictionary = {}
var rich_noted: Dictionary = {}
var leader: int = -1

func _ready():
	load_lines()
	random_timer = Timer.new()
	random_timer.one_shot = true
	random_timer.timeout.connect(_on_random_timer)
	add_child(random_timer)
	_restart_random_timer()

func setup(character_popup: CharacterPopup):
	popup = character_popup
	popup.finished.connect(_show_next)

func load_lines():
	var data = JSON.parse_string(FileAccess.get_file_as_string(LINES_PATH))
	if not data is Array:
		push_warning("Commentary: could not read " + LINES_PATH)
		return
	for entry in data:
		if entry is Dictionary and entry.has("when") and entry.has("text"):
			if not lines_by_when.has(entry.when):
				lines_by_when[entry.when] = []
			lines_by_when[entry.when].append({"name": entry.get("name", ""), "text": entry.text})

# Speaks a line for this event. Ordinary events are skipped if someone spoke
# recently; must_show events (game start, bankruptcy, game end) wait their turn
# and play every line they have, in order.
func trigger(when: String, must_show: bool = false):
	if when == GAME_ENDS:
		random_timer.stop() # No trash talk over the victory
	var lines: Array = lines_by_when.get(when, [])
	if lines.is_empty() or popup == null:
		return
	var now = _now()
	if not must_show:
		if popup.showing or not queue.is_empty() or now - last_shown_at < EVENT_GAP \
				or now - last_trigger_at.get(when, -INF) < TRIGGER_COOLDOWN:
			return
		queue.append(lines.pick_random())
	else:
		queue.append_array(lines)
	last_trigger_at[when] = now
	if not popup.showing:
		_show_next()

# After each move: low funds, great wealth and a new clear leader
func check_fortunes():
	var gm = GameManager.instance
	var ranking: Array = []
	for player_id in gm.total_players:
		if gm.player_eliminated[player_id]:
			continue
		var gold = gm.player_suvarnas[player_id]
		if gold < LOW_GOLD and not low_warned.get(player_id, false):
			low_warned[player_id] = true
			trigger(LOW_ON_COINS)
		elif gold > LOW_GOLD_RESET:
			low_warned[player_id] = false
		if gold > RICH_GOLD and not rich_noted.get(player_id, false):
			rich_noted[player_id] = true
			trigger(LOT_OF_COINS)
		elif gold < RICH_GOLD_RESET:
			rich_noted[player_id] = false
		ranking.append([gm.total_balance(player_id), player_id])

	if ranking.size() >= 2:
		ranking.sort_custom(func(a, b): return a[0] > b[0])
		var best = ranking[0][1]
		if best != leader and ranking[0][0] - ranking[1][0] >= LEAD_MARGIN:
			leader = best
			trigger(IN_THE_LEAD)

func _show_next():
	if queue.is_empty() or popup.showing:
		return
	var line = queue.pop_front()
	last_shown_at = _now()
	popup.say(line.name, line.text)

func _on_random_timer():
	if not popup.showing and queue.is_empty() and _now() - last_shown_at >= RANDOM_QUIET:
		if trash_talk_bag.is_empty():
			trash_talk_bag = lines_by_when.get(TRASH_TALK, []).duplicate()
			trash_talk_bag.shuffle()
		if not trash_talk_bag.is_empty():
			queue.append(trash_talk_bag.pop_back())
			_show_next()
	_restart_random_timer()

func _restart_random_timer():
	random_timer.start(randf_range(RANDOM_INTERVAL_MIN, RANDOM_INTERVAL_MAX))

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
