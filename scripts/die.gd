extends RigidBody3D

var start_pos
var roll_strength = 30

signal roll_finished(value)

func _ready():
	start_pos = global_position

func _input(event):
	if event.is_action_pressed("ui_accept"):
		_roll()
		
func _roll():
	sleeping = false
	freeze = false
	transform.orign = start_pos
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	
	transform.basis = Basis(Vector3.RIGHT, randf_range(0, 2*PI)) * transform.basis
	transform.basis = Basis(Vector3.RIGHT, randf_range(0, 2*PI)) * transform.basis
	transform.basis = Basis(Vector3.FORWARD, randf_range(0, 2*PI)) * transform.basis
	
	var throw_vector = Vector3(randf_range(-1, 1),0, randf_range(-1 ,1)).normalized()
	angular_velocity = throw_vector * roll_length / 2
	apply_central_impulse(throw_vector*roll_strength)
	

"""

@export var maxRandomForce = 50

@onready var faces = $Faces

var isMoving = false

func _physics_process(delta):
	isMoving = linear_velocity.length() > 0.01

func _unhandled_input(event):
	if event.is_pressed() and not isMoving:
		roll_dice()

func roll_dice():
	if isMoving: return
	
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	var randomDirection = [-1, 1]
	var force = Vector3.ZERO
	
	force.x = rng.randi_range(10, maxRandomForce) * randomDirection.pick_random()
	force.z = rng.randi_range(10, maxRandomForce) * randomDirection.pick_random()
	
	apply_torque(force)
	apply_central_impulse(Vector3(0, rng.randf_range(4.0, 7.0), 0))

func get_number():
	var lowest_y
	var number
	
	for node in faces.get_children():
		var y_value = node.global_position.y
		
		if not lowest_y || y_value < lowest_y:
			lowest_y = y_value
			number = node.name
			
	return int(str(number))


"""
