extends Node
# Background music for the whole game. Runs as an autoload, so the track keeps
# playing without restarting when the opening page changes to the board.
# Mute and volume are saved to user://settings.cfg and restored on the next launch.

const BGM = preload("res://assets/BGM 4.mp3")
const SETTINGS_PATH = "user://settings.cfg"
const DEFAULT_VOLUME: float = 0.5 # 0.0 - 1.0

var player: AudioStreamPlayer
var volume: float = DEFAULT_VOLUME
var muted: bool = false

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS # Keep playing even if the game is paused
	var stream: AudioStreamMP3 = BGM.duplicate()
	stream.loop = true
	player = AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	load_settings()
	start()

const FADE_IN_TIME: float = 1.5
const SILENT_DB: float = -40.0

# Starts the track from the beginning, keeping the mute setting.
# The intro video stops the music and calls this when it ends, fading it in.
func start(fade_in: bool = false):
	player.play()
	apply_settings()
	if fade_in:
		var target_db = player.volume_db
		player.volume_db = SILENT_DB
		create_tween().tween_property(player, "volume_db", target_db, FADE_IN_TIME)

func set_volume(value: float):
	volume = clampf(value, 0.0, 1.0)
	apply_settings()
	save_settings()

func set_muted(value: bool):
	muted = value
	apply_settings()
	save_settings()

func apply_settings():
	player.volume_db = linear_to_db(volume) if volume > 0.0 else -80.0
	player.stream_paused = muted

func load_settings():
	var config = ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		volume = config.get_value("music", "volume", DEFAULT_VOLUME)
		muted = config.get_value("music", "muted", false)

func save_settings():
	var config = ConfigFile.new()
	config.set_value("music", "volume", volume)
	config.set_value("music", "muted", muted)
	config.save(SETTINGS_PATH)
