extends StaticBody3D

signal damaged(amount: int, source: Node, remaining_health: int)
signal attacked(target: Node, damage_dealt: int)
signal defeated(source: Node)

@export var max_health: int = 100
@export var action_threshold: float = 100.0
@export var spark: int = 1
@export var attack_power: int = 20
@export var defense: int = 5
@export var speed: float = 22.0
@export var luck: int = 1
@export var resilience: int = 1
@export var sp: int = 1

var health: int = 1
var action_points: float = 0.0

@onready var action_bar: ProgressBar = get_node_or_null("Sprite3D/SubViewport/ActionBar")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	health = max_health
	action_points = 0.0
	_sync_action_bar()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if not is_alive():
		return

	var gain_amount: float = max(0.0, speed) * delta
	action_points = min(action_threshold, action_points + gain_amount)
	_sync_action_bar()


func configure_for_battle(new_max_health: int, new_attack_power: int, new_defense: int) -> void:
	max_health = max(1, new_max_health)
	attack_power = max(1, new_attack_power)
	defense = max(0, new_defense)
	health = max_health
	action_points = 0.0
	_sync_action_bar()


func is_alive() -> bool:
	return health > 0


func attack(target: Node) -> int:
	if target == null or not is_alive() or not can_attack() or not target.has_method("take_damage"):
		return 0

	var dealt_damage: int = int(target.call("take_damage", attack_power, self))
	action_points = 0.0
	_sync_action_bar()
	emit_signal("attacked", target, dealt_damage)
	return dealt_damage


func take_damage(raw_damage: int, source: Node = null) -> int:
	if not is_alive() or raw_damage <= 0:
		return 0

	var mitigated_damage: int = max(1, raw_damage - defense)
	health = max(0, health - mitigated_damage)
	emit_signal("damaged", mitigated_damage, source, health)

	if health == 0:
		emit_signal("defeated", source)

	return mitigated_damage


func can_attack() -> bool:
	return is_alive() and action_points >= action_threshold


func get_action_percent() -> float:
	if action_threshold <= 0.0:
		return 0.0
	return (action_points / action_threshold) * 100.0


func _sync_action_bar() -> void:
	if action_bar == null:
		return

	action_bar.max_value = action_threshold
	action_bar.value = action_points
