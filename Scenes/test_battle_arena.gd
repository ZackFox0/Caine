extends Node3D

const BATTLE_ACTOR_SCENE: PackedScene = preload("res://Scenes/Battle_Actor.tscn")
const BATTLE_ACTOR_SCRIPT: Script = preload("res://Scenes/battle_actor.gd")

const DEFAULT_CONFIG_PATH := "res://Data/battle_actors.cfg"
const USER_CONFIG_PATH    := "user://battle_actors.cfg"

# Arena Config
const ARENA_SLOTS := [
	{ "name": "Actor_Friend1", "position": Vector3( 2.5, 1.0, 2.5), "enemy": false, "character": "Caine"  },
	{ "name": "Actor_Friend2", "position": Vector3( 2.5, 1.0, 7.0), "enemy": false, "character": "Alyssa" },
	{ "name": "Actor_Friend3", "position": Vector3( 7.0, 1.0, 2.5), "enemy": false, "character": "Zeke"   },
	{ "name": "Actor_Friend4", "position": Vector3( 7.0, 1.0, 7.0), "enemy": false, "character": "Ster"   },
	{ "name": "Actor_Enemy1",  "position": Vector3(-7.0, 1.0, 7.0), "enemy": true,  "character": "Lyre"   },
	{ "name": "Actor_Enemy2",  "position": Vector3(-7.0, 1.0, 2.5), "enemy": true,  "character": "Albert" },
	{ "name": "Actor_Enemy3",  "position": Vector3(-2.5, 1.0, 2.5), "enemy": true,  "character": "Jack"   },
	{ "name": "Actor_Enemy4",  "position": Vector3(-2.5, 1.0, 7.0), "enemy": true,  "character": "Logos"  },
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


func _load_cfg() -> ConfigFile:
	# On first run copy the bundled default to user:// so it stays editable.
	if not FileAccess.file_exists(USER_CONFIG_PATH):
		var src := FileAccess.open(DEFAULT_CONFIG_PATH, FileAccess.READ)
		if src != null:
			var content := src.get_as_text()
			src.close()
			var dst := FileAccess.open(USER_CONFIG_PATH, FileAccess.WRITE)
			if dst != null:
				dst.store_string(content)
				dst.close()

	var load_path := USER_CONFIG_PATH if FileAccess.file_exists(USER_CONFIG_PATH) else DEFAULT_CONFIG_PATH
	var cfg := ConfigFile.new()
	var err := cfg.load(load_path)
	if err != OK:
		push_error("battle_arena: failed to load config from %s (error %d)" % [load_path, err])
		return null
	return cfg


func _load_actor_configs() -> Array:
	var roster := _load_roster()
	var configs: Array = []
	for slot in ARENA_SLOTS:
		var char_key: String = str(slot.get("character", ""))
		var char_data: Dictionary = roster.get(char_key, {})
		if char_data.is_empty():
			push_warning("battle_arena: slot '%s' references unknown character '%s'" % [slot["name"], char_key])
		configs.append({
			"name":      slot["name"],
			"position":  slot["position"],
			"enemy":     slot["enemy"],
			"animation": char_data.get("animation", "Canin"),
			"label":     char_data.get("label", char_key),
			"max_hp":    char_data.get("max_hp", 100),
			"attack":    char_data.get("attack", 10),
			"defense":   char_data.get("defense", 0),
			"speed":     char_data.get("speed", 10.0),
		})
	return configs


func _load_roster() -> Dictionary:
	var cfg := _load_cfg()
	if cfg == null:
		return {}
	var roster: Dictionary = {}
	for section in cfg.get_sections():
		if not section.begins_with("character."):
			continue
		var char_name: String = section.substr(len("character."))
		roster[char_name] = {
			"animation": str(cfg.get_value(section, "animation", "Canin")),
			"label":     str(cfg.get_value(section, "label", char_name)),
			"max_hp":    int(cfg.get_value(section, "max_hp", 100)),
			"attack":    int(cfg.get_value(section, "attack", 10)),
			"defense":   int(cfg.get_value(section, "defense", 0)),
			"speed":     float(cfg.get_value(section, "speed", 10.0)),
		}
	return roster


func _spawn_arena_actors() -> void:
	for config in _load_actor_configs():
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
