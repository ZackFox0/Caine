extends Node3D

const BATTLE_ACTOR_SCENE: PackedScene = preload("res://Scenes/Battle_Actor.tscn")
const BATTLE_ACTOR_SCRIPT: Script = preload("res://Scenes/battle_actor.gd")

const ARENA_ACTOR_CONFIGS := [
	{
		"name": "Actor_Friend1",
		"position": Vector3(2.5, 1.0, 2.5),
		"animation": "Canin",
		"label": "Caine",
		"max_hp": 120,
		"attack": 25,
		"defense": 4,
		"speed": 22.0,
		"enemy": false,
	},
	{
		"name": "Actor_Friend2",
		"position": Vector3(2.5, 1.0, 7.0),
		"animation": "Alyssa",
		"label": "Alyssa",
		"max_hp": 100,
		"attack": 16,
		"defense": 3,
		"speed": 18.0,
		"enemy": false,
	},
	{
		"name": "Actor_Friend3",
		"position": Vector3(7.0, 1.0, 2.5),
		"animation": "Zeke",
		"label": "Zeke",
		"max_hp": 100,
		"attack": 17,
		"defense": 3,
		"speed": 20.0,
		"enemy": false,
	},
	{
		"name": "Actor_Friend4",
		"position": Vector3(7.0, 1.0, 7.0),
		"animation": "Ster",
		"label": "Ster",
		"max_hp": 115,
		"attack": 19,
		"defense": 4,
		"speed": 17.0,
		"enemy": false,
	},
	{
		"name": "Actor_Enemy1",
		"position": Vector3(-7.0, 1.0, 7.0),
		"animation": "Lyre",
		"label": "Lyre",
		"max_hp": 100,
		"attack": 16,
		"defense": 3,
		"speed": 20.0,
		"enemy": true,
	},
	{
		"name": "Actor_Enemy2",
		"position": Vector3(-7.0, 1.0, 2.5),
		"animation": "Albert",
		"label": "Albert",
		"max_hp": 100,
		"attack": 16,
		"defense": 3,
		"speed": 18.0,
		"enemy": true,
	},
	{
		"name": "Actor_Enemy3",
		"position": Vector3(-2.5, 1.0, 2.5),
		"animation": "Jack",
		"label": "Jack",
		"max_hp": 105,
		"attack": 17,
		"defense": 3,
		"speed": 19.0,
		"enemy": true,
	},
	{
		"name": "Actor_Enemy4",
		"position": Vector3(-2.5, 1.0, 7.0),
		"animation": "Logos",
		"label": "Logos",
		"max_hp": 110,
		"attack": 18,
		"defense": 4,
		"speed": 16.0,
		"enemy": true,
	},
]

var actor_friend1: Node = null
var actor_enemy1: Node = null


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_spawn_arena_actors()
	actor_friend1 = get_node_or_null("Actor_Friend1")
	actor_enemy1 = get_node_or_null("Actor_Enemy1")


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_actor_friend1_attacks_enemy1()


func _spawn_arena_actors() -> void:
	for config in ARENA_ACTOR_CONFIGS:
		_spawn_actor_from_template(config)


func _spawn_actor_from_template(config: Dictionary) -> void:
	var actor_name: String = str(config.get("name", ""))
	if actor_name.is_empty():
		return

	var existing: Node = get_node_or_null(actor_name)
	if existing != null:
		existing.get_parent().remove_child(existing)
		existing.free()

	var actor_instance: Node = BATTLE_ACTOR_SCENE.instantiate()
	if not (actor_instance is Node3D):
		return

	var actor_node: Node3D = actor_instance as Node3D
	actor_node.name = actor_name
	actor_node.position = config.get("position", Vector3.ZERO)
	add_child(actor_node)

	_configure_actor_visuals(actor_node, config)
	_prepare_actor(
		actor_node,
		int(config.get("max_hp", 100)),
		int(config.get("attack", 10)),
		int(config.get("defense", 0)),
		float(config.get("speed", 10.0))
	)


func _configure_actor_visuals(actor_node: Node3D, config: Dictionary) -> void:
	var animation_name: StringName = StringName(str(config.get("animation", "Canin")))
	var is_enemy: bool = bool(config.get("enemy", false))

	var sprite: AnimatedSprite3D = actor_node.get_node_or_null("AnimatedSprite3D")
	if sprite != null:
		if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(animation_name):
			sprite.play(animation_name)

		var x_scale: float = abs(sprite.scale.x)
		var z_scale: float = abs(sprite.scale.z)
		if is_enemy:
			sprite.scale.x = x_scale
			sprite.scale.z = z_scale
		else:
			sprite.scale.x = -x_scale
			sprite.scale.z = -z_scale

	var label: Label3D = actor_node.get_node_or_null("Label3D")
	if label != null:
		label.text = str(config.get("label", actor_node.name))


func _prepare_actor(actor: Node, max_hp: int, actor_attack: int, actor_defense: int, actor_speed: float) -> void:
	if actor == null:
		return

	if actor.get_script() != BATTLE_ACTOR_SCRIPT:
		actor.set_script(BATTLE_ACTOR_SCRIPT)

	if actor.has_method("configure_for_battle"):
		actor.call("configure_for_battle", max_hp, actor_attack, actor_defense)

	if actor.has_method("set"):
		actor.set("speed", max(0.0, actor_speed))


func _actor_friend1_attacks_enemy1() -> void:
	if actor_friend1 == null or actor_enemy1 == null:
		return

	if not actor_enemy1.has_method("is_alive") or not actor_enemy1.call("is_alive"):
		print("Actor_Enemy1 is already defeated.")
		return

	if not actor_friend1.has_method("attack"):
		return

	if actor_friend1.has_method("can_attack") and not actor_friend1.call("can_attack"):
		var action_percent: float = 0.0
		if actor_friend1.has_method("get_action_percent"):
			action_percent = float(actor_friend1.call("get_action_percent"))
		print("Actor_Friend1 action is %.1f%%. Reach 100%% to attack." % action_percent)
		return

	var damage: int = int(actor_friend1.call("attack", actor_enemy1))
	var enemy_health: int = int(actor_enemy1.get("health"))
	var enemy_max_health: int = int(actor_enemy1.get("max_health"))
	print("Actor_Friend1 hits Actor_Enemy1 for %d damage. HP %d/%d" % [damage, enemy_health, enemy_max_health])
