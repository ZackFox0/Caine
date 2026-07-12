extends Node3D

const BATTLE_SCENE_PATH := "res://Scenes/Test_BattleArena.tscn"
const BATTLE_LAYOUT_META_KEY := "battle_layout_id"
const BATTLE_RETURN_SCENE_META_KEY := "battle_return_scene_path"
const DEFAULT_RETURN_SCENE_PATH := "res://Test.tscn"

const PILLAR_LAYOUT_BY_NAME := {
	"Battle1": "battle1",
	"Battle2": "battle2",
	"Battle3": "battle3",
	"Battle4": "battle4",
	"Battle5": "battle5",
}

const TRIGGER_RADIUS: float = 0.85
const TRIGGER_HEIGHT: float = 2.4
const TRIGGER_Y_OFFSET: float = 1.0

var transition_in_progress: bool = false


func _ready() -> void:
	_setup_battle_pillar_triggers()


func _setup_battle_pillar_triggers() -> void:
	for pillar_name in PILLAR_LAYOUT_BY_NAME.keys():
		var pillar_node: Node3D = _find_pillar_node(pillar_name)
		if pillar_node == null:
			push_warning("play_ground: missing pillar node '%s'" % pillar_name)
			continue

		if pillar_node.get_node_or_null("BattleTrigger") != null:
			continue

		var trigger_area := Area3D.new()
		trigger_area.name = "BattleTrigger"
		trigger_area.monitoring = true
		trigger_area.monitorable = false
		trigger_area.position = Vector3(0.0, TRIGGER_Y_OFFSET, 0.0)

		var trigger_shape := CollisionShape3D.new()
		var cylinder_shape := CylinderShape3D.new()
		cylinder_shape.radius = TRIGGER_RADIUS
		cylinder_shape.height = TRIGGER_HEIGHT
		trigger_shape.shape = cylinder_shape

		trigger_area.add_child(trigger_shape)
		pillar_node.add_child(trigger_area)

		var layout_id: String = str(PILLAR_LAYOUT_BY_NAME[pillar_name]).strip_edges().to_lower()
		trigger_area.body_entered.connect(_on_battle_trigger_body_entered.bind(layout_id, pillar_name))


func _on_battle_trigger_body_entered(body: Node, layout_id: String, pillar_name: String) -> void:
	if transition_in_progress:
		return
	if not _is_player_body(body):
		return

	if layout_id.is_empty():
		push_warning("play_ground: missing layout id for pillar '%s'" % pillar_name)
		return

	transition_in_progress = true
	get_tree().set_meta(BATTLE_LAYOUT_META_KEY, layout_id)
	var return_scene_path: String = _resolve_current_scene_path()
	get_tree().set_meta(BATTLE_RETURN_SCENE_META_KEY, return_scene_path)

	var err: Error = get_tree().change_scene_to_file(BATTLE_SCENE_PATH)
	if err != OK:
		transition_in_progress = false
		push_error("play_ground: failed to load battle scene '%s' from pillar '%s' (error %d)" % [BATTLE_SCENE_PATH, pillar_name, err])


func _is_player_body(body: Node) -> bool:
	if not (body is CharacterBody3D):
		return false

	var body_script: Script = body.get_script() as Script
	if body_script != null and body_script.resource_path == "res://Player.gd":
		return true

	# Fallback for player controllers that wrap the movement script.
	return body.name == "CharacterBody3D" or body.has_signal("giveCameraPosition")


func _find_pillar_node(pillar_name: String) -> Node3D:
	var scene_level_path := NodePath("%s" % pillar_name)
	var terrain_path := NodePath("Terain/%s" % pillar_name)

	var scene_level_pillar: Node3D = get_node_or_null(scene_level_path) as Node3D
	if scene_level_pillar != null:
		return scene_level_pillar

	return get_node_or_null(terrain_path) as Node3D


func _resolve_current_scene_path() -> String:
	var current_scene: Node = get_tree().current_scene
	if current_scene != null:
		var scene_path: String = str(current_scene.scene_file_path).strip_edges()
		if not scene_path.is_empty():
			return scene_path
	return DEFAULT_RETURN_SCENE_PATH
