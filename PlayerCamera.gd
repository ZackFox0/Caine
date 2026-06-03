extends Camera3D

var playerControlled : bool = true
var playerPosition : Vector3
var resetRotation : Vector3 = Vector3(-40,-45,0)
var resetPositionOffsetBase : Vector2 = Vector2(-4,4)
var lastLockedPosition : Vector3
var locked : bool = true

var mouseVelocity
signal giveCameraRotation(rotation: Vector3)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	giveCameraRotation.emit(rotation)
	if Input.is_action_pressed("Camera_Pan"):
		locked = false
		var direction = mouseVelocity.rotated(deg_to_rad(45))
		if direction:
			position.x += direction.x * delta * 0.01
			position.z += direction.y * delta * 0.01
		

	if locked or Input.is_action_just_pressed("Reset_Camera"):
		locked = true
		position.x = playerPosition.x + resetPositionOffsetBase.x
		position.z = playerPosition.z + resetPositionOffsetBase.y

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouseVelocity = event.screen_velocity
	
func on_giveCameraPosition(position: Vector3) -> void:
	playerPosition = position
