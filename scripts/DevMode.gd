extends CanvasLayer
# Developer-only test tools. The "Dev Mode" toggle in the top-left corner shows
# a panel that lets you skip the throw and pick the roll yourself.

signal forced_roll_requested(value: int)

var enabled: bool = false

var toggle_button: CheckButton
var dev_panel: HBoxContainer
var roll_spinbox: SpinBox

func _ready():
	layer = 10 # Above the game UI

	var bar = HBoxContainer.new()
	bar.position = Vector2(10, 10)
	add_child(bar)

	toggle_button = CheckButton.new()
	toggle_button.text = "Dev Mode"
	toggle_button.toggled.connect(set_enabled)
	bar.add_child(toggle_button)

	dev_panel = HBoxContainer.new()
	dev_panel.visible = false
	bar.add_child(dev_panel)

	var label = Label.new()
	label.text = "Roll:"
	label.modulate = Color.ORANGE
	dev_panel.add_child(label)

	# Any value, so long jumps (e.g. a full 72-tile Ludo lap) can be tested quickly
	roll_spinbox = SpinBox.new()
	roll_spinbox.min_value = 1
	roll_spinbox.max_value = 100
	roll_spinbox.value = 6
	dev_panel.add_child(roll_spinbox)

	var roll_button = Button.new()
	roll_button.text = "Use this roll"
	roll_button.pressed.connect(func(): forced_roll_requested.emit(int(roll_spinbox.value)))
	dev_panel.add_child(roll_button)

func set_enabled(value: bool):
	enabled = value
	dev_panel.visible = value
	print("Developer mode ", "ON" if value else "OFF")
