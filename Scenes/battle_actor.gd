extends StaticBody3D

signal damaged(amount: int, source: Node, remaining_health: int)
signal attacked(target: Node, damage_dealt: int)
signal defeated(source: Node)
signal action_used(action_slot: int, action_name: String, target: Node, damage_dealt: int)

enum ActionSlot {
	ATTACK,
	HEAVY_ATTACK,
	SPECIAL,
	EMPTY,
}

const ACTION_ATTACK := "Attack"
const ACTION_HEAVY_ATTACK := "Heavy Attack"
const ACTION_SPECIAL := "Special"
const ACTION_EMPTY := "Empty"

const ACTION_KIND_ATTACK := "attack"
const ACTION_KIND_EMPTY := "empty"

const DEFAULT_ACTION_SLOTS := [
	{"name": ACTION_ATTACK, "kind": ACTION_KIND_ATTACK, "cost": 100.0, "power_scale": 1.0},
	{"name": ACTION_HEAVY_ATTACK, "kind": ACTION_KIND_ATTACK, "cost": 100.0, "power_scale": 1.6},
	{"name": ACTION_SPECIAL, "kind": ACTION_KIND_ATTACK, "cost": 100.0, "power_scale": 2.0},
	{"name": ACTION_EMPTY, "kind": ACTION_KIND_EMPTY, "cost": 100.0, "power_scale": 0.0},
]

@export var max_health: int = 100
@export var action_threshold: float = 100.0
@export var spark: int = 1
@export var attack_power: int = 20
@export var heavy_attack_multiplier: float = 1.6
@export var special_attack_multiplier: float = 2.0
@export var defense: int = 5
@export var speed: float = 22.0
@export var luck: int = 1
@export var resilience: int = 1
@export var sp: int = 1

var health: int = 1
var action_points: float = 0.0
var action_slots: Array = []

@onready var action_bar: ProgressBar = get_node_or_null("Sprite3D/SubViewport/ActionBar")
@onready var health_bar: ProgressBar = get_node_or_null("Sprite3D/SubViewport/HealthBar")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	health = max_health
	action_points = 0.0
	_ensure_action_slots()
	_sync_health_bar()
	_sync_action_bar()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if not is_alive():
		return

	var gain_amount: float = max(0.0, speed) * delta
	action_points = min(_get_action_point_cap(), action_points + gain_amount)
	_sync_action_bar()


func configure_for_battle(new_max_health: int, new_attack_power: int, new_defense: int) -> void:
	max_health = max(1, new_max_health)
	attack_power = max(1, new_attack_power)
	defense = max(0, new_defense)
	health = max_health
	action_points = 0.0
	_ensure_action_slots()
	_sync_health_bar()
	_sync_action_bar()


func configure_actions(new_action_slots: Array) -> void:
	action_slots = _sanitize_action_slots(new_action_slots)
	_sync_action_bar()


func is_alive() -> bool:
	return health > 0


func attack(target: Node) -> int:
	return perform_action(ActionSlot.ATTACK, target)


func heavy_attack(target: Node) -> int:
	return perform_action(ActionSlot.HEAVY_ATTACK, target)


func special(target: Node) -> int:
	return perform_action(ActionSlot.SPECIAL, target)


func empty_action(_target: Node = null) -> int:
	return perform_action(ActionSlot.EMPTY, _target)


func perform_action(action_slot: int, target: Node = null) -> int:
	if not is_alive():
		return 0

	var action_data: Dictionary = _get_action_data(action_slot)
	if action_data.is_empty() or not can_use_action(action_slot):
		return 0

	var action_name: String = str(action_data.get("name", "Action"))
	var action_kind: String = str(action_data.get("kind", ACTION_KIND_ATTACK)).to_lower()
	var action_cost: float = get_action_cost(action_slot)

	if action_kind == ACTION_KIND_EMPTY:
		_consume_action_points(action_cost)
		emit_signal("action_used", action_slot, action_name, null, 0)
		return 0

	if target == null or not target.has_method("take_damage"):
		return 0

	var power_scale: float = max(0.0, float(action_data.get("power_scale", 1.0)))
	var raw_damage: int = max(1, int(round(attack_power * power_scale)))
	if action_slot == ActionSlot.SPECIAL:
		raw_damage = max(1, int(round(raw_damage * (1.0 + float(max(0, sp)) * 0.1))))

	var dealt_damage: int = _deal_damage_to_target(target, raw_damage, action_cost)
	emit_signal("attacked", target, dealt_damage)
	emit_signal("action_used", action_slot, action_name, target, dealt_damage)
	return dealt_damage


func get_action_names() -> PackedStringArray:
	_ensure_action_slots()
	var names := PackedStringArray()
	for action_data in action_slots:
		names.append(str(action_data.get("name", "Action")))
	return names


func get_action_data_list() -> Array:
	_ensure_action_slots()
	return action_slots.duplicate()


func take_damage(raw_damage: int, source: Node = null) -> int:
	if not is_alive() or raw_damage <= 0:
		return 0

	var mitigated_damage: int = max(1, raw_damage - defense)
	health = max(0, health - mitigated_damage)
	_sync_health_bar()
	emit_signal("damaged", mitigated_damage, source, health)

	if health == 0:
		emit_signal("defeated", source)

	return mitigated_damage


func can_attack() -> bool:
	return can_use_action(ActionSlot.ATTACK)


func can_use_action(action_slot: int) -> bool:
	if not is_alive():
		return false
	return action_points >= get_action_cost(action_slot)


func get_action_cost(action_slot: int) -> float:
	var action_data: Dictionary = _get_action_data(action_slot)
	if action_data.is_empty():
		return max(0.0, action_threshold)
	return max(0.0, float(action_data.get("cost", action_threshold)))


func get_action_percent() -> float:
	var point_cap: float = _get_action_point_cap()
	if point_cap <= 0.0:
		return 0.0
	return (action_points / point_cap) * 100.0


func _deal_damage_to_target(target: Node, raw_damage: int, action_cost: float = 0.0) -> int:
	var dealt_damage: int = int(target.call("take_damage", max(1, raw_damage), self))
	_consume_action_points(action_cost)
	return dealt_damage


func _consume_action_points(amount: float) -> void:
	action_points = max(0.0, action_points - max(0.0, amount))
	_sync_action_bar()


func _get_action_data(action_slot: int) -> Dictionary:
	_ensure_action_slots()
	if action_slot < 0 or action_slot >= action_slots.size():
		return {}
	return action_slots[action_slot]


func _ensure_action_slots() -> void:
	if action_slots.size() != DEFAULT_ACTION_SLOTS.size():
		action_slots = _sanitize_action_slots([])


func _sanitize_action_slots(new_action_slots: Array) -> Array:
	var sanitized: Array = []
	for slot_index in range(DEFAULT_ACTION_SLOTS.size()):
		var fallback: Dictionary = DEFAULT_ACTION_SLOTS[slot_index]
		var merged: Dictionary = fallback.duplicate()
		if slot_index < new_action_slots.size() and new_action_slots[slot_index] is Dictionary:
			merged.merge(new_action_slots[slot_index], true)

		sanitized.append({
			"name": str(merged.get("name", fallback.get("name", "Action"))),
			"kind": str(merged.get("kind", fallback.get("kind", ACTION_KIND_ATTACK))).to_lower(),
			"cost": max(0.0, float(merged.get("cost", fallback.get("cost", action_threshold)))),
			"power_scale": max(0.0, float(merged.get("power_scale", fallback.get("power_scale", 1.0)))),
		})
	return sanitized


func _sync_action_bar() -> void:
	if action_bar == null:
		return

	action_bar.max_value = _get_action_point_cap()
	action_bar.value = action_points


func _get_action_point_cap() -> float:
	var point_cap: float = max(0.0, action_threshold)
	for action_data in action_slots:
		if action_data is Dictionary:
			point_cap = max(point_cap, max(0.0, float(action_data.get("cost", point_cap))))
	return point_cap


func _sync_health_bar() -> void:
	if health_bar == null:
		return

	health_bar.max_value = max_health
	health_bar.value = health
