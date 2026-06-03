extends CharacterBody3D

const SPEED : float = 5.0
const FASTSPEED : float = 10.0
const JUMP_VELOCITY : float = 4.5
var releasedJump : bool = false
var cameraRotation : Vector3

signal giveCameraPosition(position: Vector3)

func _physics_process(delta: float) -> void:
	MovementProcess(delta)
	giveCameraPosition.emit(position)
	move_and_slide()
	
func MovementProcess(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		releasedJump = false
	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	if Input.is_action_just_released("ui_accept") and not is_on_floor() and !releasedJump:
		velocity.y = 0
		releasedJump = true

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	# TODO: Make player movement relative to camera position
	# TODO: Make camera rotatable
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y))
	direction.rotated(Vector3.UP, cameraRotation.y).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)


func on_giveCameraRotation(camRotation: Vector3) -> void:
	cameraRotation = camRotation
	pass # Replace with function body.
