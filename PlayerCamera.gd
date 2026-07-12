extends Camera3D

var playerControlled : bool = true
var playerPosition : Vector3
var resetRotation : Vector3 = Vector3(-40,-45,0)
var resetPositionOffsetBase : Vector2 = Vector2(-4,4)
var lastLockedPosition : Vector3
var locked : bool = true
var orbit_angle : float = 0.0
var orbit_radius : float = 0.0
var orbit_height : float = 0.0
var orbit_sensitivity : float = 0.01
var orbit_vertical_sensitivity : float = 0.02
var orbit_min_height : float = 2.0
var orbit_max_height : float = 12.0
var default_orbit_angle : float = 0.0
var default_orbit_height : float = 0.0
var ctrl_was_pressed : bool = false

var mouseVelocity : Vector2 = Vector2.ZERO
signal giveCameraRotation(rotation: Vector3)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	orbit_radius = resetPositionOffsetBase.length()
	orbit_height = position.y
	orbit_angle = atan2(resetPositionOffsetBase.x, resetPositionOffsetBase.y)
	default_orbit_angle = orbit_angle
	default_orbit_height = orbit_height

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	var ctrl_pressed := Input.is_key_pressed(KEY_CTRL)
	var shift_pressed := Input.is_key_pressed(KEY_SHIFT)
	if ctrl_pressed and not ctrl_was_pressed:
		if shift_pressed:
			_capture_orbit_from_current_position()
			locked = true
		else:
			_reset_camera_position()
	ctrl_was_pressed = ctrl_pressed

	if Input.is_key_pressed(KEY_ALT):
		locked = false

	if Input.is_action_pressed("Camera_Pan"):
		locked = false
		var direction = mouseVelocity.rotated(deg_to_rad(45))
		if direction:
			position.x += direction.x * delta * 0.01
			position.z += direction.y * delta * 0.01
		

	if Input.is_action_just_pressed("Reset_Camera"):
		_reset_camera_position()

	if locked:
		_update_orbit_from_state()
	else:
		look_at(playerPosition, Vector3.UP)

	giveCameraRotation.emit(rotation)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouseVelocity = event.screen_velocity
		if Input.is_key_pressed(KEY_ALT):
			orbit_angle -= event.relative.x * orbit_sensitivity
			orbit_height = clamp(orbit_height - event.relative.y * orbit_vertical_sensitivity, orbit_min_height, orbit_max_height)
			_update_orbit_from_state()
	
func on_giveCameraPosition(player_pos: Vector3) -> void:
	playerPosition = player_pos

func _reset_camera_position() -> void:
	orbit_angle = default_orbit_angle
	orbit_height = default_orbit_height
	_update_orbit_position(resetPositionOffsetBase.x, resetPositionOffsetBase.y)

func _capture_orbit_from_current_position() -> void:
	var offset := position - playerPosition
	orbit_height = clamp(offset.y, orbit_min_height, orbit_max_height)
	orbit_angle = atan2(offset.x, offset.z)

func _update_orbit_from_state() -> void:
	var orbit_x := sin(orbit_angle) * orbit_radius
	var orbit_z := cos(orbit_angle) * orbit_radius
	_update_orbit_position(orbit_x, orbit_z)

func _update_orbit_position(offset_x: float, offset_z: float) -> void:
	position.x = playerPosition.x + offset_x
	position.y = playerPosition.y + orbit_height
	position.z = playerPosition.z + offset_z
	look_at(playerPosition, Vector3.UP)
