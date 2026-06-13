extends Node3D

# This controller owns battle setup, menu-driven input flow, and action execution.
# In short: it spawns actors from config, lets the player pick actor -> action -> target,
# then delegates damage logic to each actor's script.

# Preload the Battle Actor scene and script for instantiation and validation.
const BATTLE_ACTOR_SCENE: PackedScene = preload("res://Scenes/Battle_Actor.tscn")
const BATTLE_ACTOR_SCRIPT: Script = preload("res://Scenes/battle_actor.gd")

# Paths for actor configuration files.
# DEFAULT_CONFIG_PATH: The bundled default configuration within the project.
# USER_CONFIG_PATH:  The writable user-specific configuration file.
const DEFAULT_CONFIG_PATH := "res://Data/battle_actors.cfg"
const USER_CONFIG_PATH    := "user://battle_actors.cfg"

const DEFAULT_ACTION_SLOT_FALLBACKS := [
	{"name": "Attack", "kind": "attack", "cost": 100.0, "power_scale": 1.0},
	{"name": "Heavy Attack", "kind": "attack", "cost": 100.0, "power_scale": 1.6},
	{"name": "Special", "kind": "attack", "cost": 100.0, "power_scale": 2.0},
	{"name": "Empty", "kind": "empty", "cost": 100.0, "power_scale": 0.0},
]

# Arena Slot Configuration.
# Defines the initial state of each actor in the battle arena.
# - name: The unique Node name assigned to the actor instance.
# - position: The 3D coordinates where the actor spawns.
# - enemy: Boolean flag indicating if this actor is an opponent (true) or ally (false).
# - character: The key used to look up character stats/actions in the config file.
# These slots are the "who/where" layer; stats/actions come from the config roster.
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

# --- State Variables ---

# Cache for quick access to actor nodes, avoiding repeated tree searches.
var actor_nodes_by_name: Dictionary = {}
var actor_is_enemy_by_name: Dictionary = {}
var actor_display_names_by_name: Dictionary = {}

# Cached references to UI buttons for actor, action, and target selection.
# These correspond to the MenuButtons in the CanvasLayer UI.
var actor_select_buttons: Array = []
var action_select_buttons: Array = []
var target_select_buttons: Array = []

# Current selection state for the turn-based flow.
# The UI always advances in this order:
# 1) choose actor, 2) choose action, 3) choose target, 4) execute + reset.
var selected_actor_name: String = ""
var selected_action_slot: int = -1

# Cache the current button labels to track changes without reading UI directly.
var actor_button_actor_names: Array = ["", "", "", ""]
var action_button_slots: Array = [-1, -1, -1, -1]
var action_button_names: Array = ["", "", "", ""]
var target_button_target_names: Array = ["", "", "", ""]

var navigation_cursor: int = 0


# --- Initialization ---

# Called when the node enters the scene tree for the first time.
# Sets up the arena by spawning actors, caching data, and binding UI.
# The order here matters: spawn first so cache/bind logic can find valid nodes.
func _ready() -> void:
	_spawn_arena_actors()       # Create actor instances based on config.
	_cache_arena_actor_nodes()  # Build lookup dictionaries for fast access.
	_bind_selection_buttons()   # Connect UI signals and setup menus.
	_refresh_selection_flow()   # Initialize the UI state to a clean slate.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

# Handles keyboard battle menu navigation.
# Navigation keys: Up/Down and W/S/A/D.
# Confirm keys: Space, Enter, Left Arrow.
# Back key: Right Arrow.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return

	var key_event: InputEventKey = event
	match key_event.keycode:
		KEY_UP, KEY_W, KEY_A:
			_move_navigation_cursor(1)
			get_viewport().set_input_as_handled()
		KEY_DOWN, KEY_S, KEY_D:
			_move_navigation_cursor(-1)
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_LEFT:
			_confirm_navigation_selection()
			get_viewport().set_input_as_handled()
		KEY_RIGHT:
			_back_navigation_stage()
			get_viewport().set_input_as_handled()


# --- Data Caching & UI Binding ---

# Populates the lookup dictionaries with current actor nodes and their properties.
# This avoids repeatedly searching the scene tree during gameplay and keeps
# team/display lookups deterministic for button generation.
func _cache_arena_actor_nodes() -> void:
	actor_nodes_by_name.clear()
	actor_is_enemy_by_name.clear()
	actor_display_names_by_name.clear()
	for slot in ARENA_SLOTS:
		var actor_name: String = str(slot.get("name", ""))
		if actor_name.is_empty():
			continue
		var actor_node: Node = get_node_or_null(actor_name)
		if actor_node == null:
			continue
		actor_nodes_by_name[actor_name] = actor_node
		actor_is_enemy_by_name[actor_name] = bool(slot.get("enemy", false))
		actor_display_names_by_name[actor_name] = _resolve_actor_display_name(actor_name, actor_node)

# Connects UI MenuButtons to their respective selection handlers.
# Clears previous entries in popups and binds the button index to the handler.
# Each visible row of UI is represented by 3 MenuButtons:
# ActorNSelect, ActionNSelect, TargetNSelect.
func _bind_selection_buttons() -> void:
	#Clear the cached arrays for all button types to ensure a fresh state.
	actor_select_buttons.clear()
	action_select_buttons.clear()
	target_select_buttons.clear()

	#Iterate through the four available actor slots to bind their respective buttons.
	for button_index in range(4):
		#Retrieve the three MenuButton nodes for actor, action, and target selection by name.
		var actor_button: MenuButton = get_node_or_null("Camera3D/CanvasLayer/Actor%dSelect" % button_index)
		var action_button: MenuButton = get_node_or_null("Camera3D/CanvasLayer/Action%dSelect" % button_index)
		var target_button: MenuButton = get_node_or_null("Camera3D/CanvasLayer/Target%dSelect" % button_index)

		#Append the retrieved buttons to their corresponding arrays for later reference.
		actor_select_buttons.append(actor_button)
		action_select_buttons.append(action_button)
		target_select_buttons.append(target_button)

		#If the actor selection button exists, configure its popup menu and signal connections.
		if actor_button != null:
			#Get the PopupMenu attached to this MenuButton to clear previous entries.
			var actor_popup: PopupMenu = actor_button.get_popup()
			actor_popup.clear()
			#Connect the button's pressed signal to the handler, binding the current loop index.
			if not actor_button.pressed.is_connected(Callable(self, "_on_actor_button_pressed").bind(button_index)):
				actor_button.pressed.connect(Callable(self, "_on_actor_button_pressed").bind(button_index))

		#If the action selection button exists, configure its popup menu and signal connections.
		if action_button != null:
			#Get the PopupMenu attached to this MenuButton to clear previous entries.
			var action_popup: PopupMenu = action_button.get_popup()
			action_popup.clear()
			#Connect the button's pressed signal to the handler, binding the current loop index.
			if not action_button.pressed.is_connected(Callable(self, "_on_action_button_pressed").bind(button_index)):
				action_button.pressed.connect(Callable(self, "_on_action_button_pressed").bind(button_index))

		#If the target selection button exists, configure its popup menu and signal connections.
		if target_button != null:
			#Get the PopupMenu attached to this MenuButton to clear previous entries.
			var target_popup: PopupMenu = target_button.get_popup()
			target_popup.clear()
			#Connect the button's pressed signal to the handler, binding the current loop index.
			if not target_button.pressed.is_connected(Callable(self, "_on_target_button_pressed").bind(button_index)):
				target_button.pressed.connect(Callable(self, "_on_target_button_pressed").bind(button_index))


# --- UI Refresh Logic ---

# Resets the selection state and updates button visibilities.
# Called after any major UI state change to ensure consistency.
# This is the canonical "return to idle" state after an action resolves.
func _refresh_selection_flow() -> void:
	selected_actor_name = ""
	selected_action_slot = -1
	navigation_cursor = 0
	_refresh_actor_buttons()
	_hide_action_buttons()
	_hide_target_buttons()
	_apply_navigation_visuals()

# Updates the actor selection buttons to reflect current alive allies.
# If no allies are alive, it falls back to showing all allies from config.
# Fallback-to-allies is useful for debugging because UI still renders even in
# fully defeated states.
func _refresh_actor_buttons() -> void:
	var controllable_actor_names: Array = _get_alive_actor_names(false)
	if controllable_actor_names.is_empty():
		controllable_actor_names = _get_actor_names_by_team(false)

	for button_index in range(4):
		var button: MenuButton = actor_select_buttons[button_index]
		if button == null:
			continue

		var actor_name: String = ""
		if button_index < controllable_actor_names.size():
			actor_name = str(controllable_actor_names[button_index])

		actor_button_actor_names[button_index] = actor_name
		button.visible = not actor_name.is_empty()
		if button.visible:
			button.text = _get_actor_display_name(actor_name)

	_apply_navigation_visuals()

# Displays action buttons for a selected actor, populated from the actor's config.
# Slots marked kind=empty are hidden so they cannot be selected from UI.
# Button index and action slot index intentionally stay aligned.
func _show_action_buttons_for_actor(actor_name: String) -> void:
	selected_action_slot = -1
	var actor_node: Node = _get_actor_by_name(actor_name)

	var slot_data_list: Array = []
	if actor_node != null and actor_node.has_method("get_action_data_list"):
		slot_data_list = Array(actor_node.call("get_action_data_list"))
	else:
		slot_data_list = [
			{"name": "Attack",       "kind": "attack"},
			{"name": "Heavy Attack", "kind": "attack"},
			{"name": "Special",      "kind": "attack"},
			{"name": "Empty",        "kind": "empty"},
		]

	for button_index in range(4):
		var button: MenuButton = action_select_buttons[button_index]
		if button == null:
			continue

		action_button_slots[button_index] = -1
		action_button_names[button_index] = ""
		button.visible = false

		if button_index >= slot_data_list.size():
			continue

		var slot_data: Dictionary = slot_data_list[button_index]
		var action_kind: String = str(slot_data.get("kind", "attack")).strip_edges().to_lower()
		if action_kind == "empty":
			continue

		var action_name: String = str(slot_data.get("name", "")).strip_edges()
		if action_name.is_empty():
			continue

		action_button_slots[button_index] = button_index
		action_button_names[button_index] = action_name
		button.text = action_name
		button.visible = true

	navigation_cursor = 0
	_apply_navigation_visuals()

# Displays target buttons for a selected actor, populated from opponent actors.
# Prioritizes alive opponents; falls back to team list when everyone is defeated.
func _show_target_buttons_for_actor(actor_name: String) -> void:
	var opponent_names: Array = _get_opponent_targets_for_actor(actor_name)
	for button_index in range(4):
		var button: MenuButton = target_select_buttons[button_index]
		if button == null:
			continue

		var target_name: String = ""
		if button_index < opponent_names.size():
			target_name = str(opponent_names[button_index])

		target_button_target_names[button_index] = target_name
		button.visible = not target_name.is_empty()
		if button.visible:
			button.text = _get_actor_display_name(target_name)

	navigation_cursor = 0
	_apply_navigation_visuals()

# Hides all action selection buttons.
func _hide_action_buttons() -> void:
	for button_index in range(4):
		action_button_slots[button_index] = -1
		action_button_names[button_index] = ""
		var button: MenuButton = action_select_buttons[button_index]
		if button != null:
			button.visible = false

# Hides all target selection buttons.
func _hide_target_buttons() -> void:
	for button_index in range(4):
		target_button_target_names[button_index] = ""
		var button: MenuButton = target_select_buttons[button_index]
		if button != null:
			button.visible = false


# --- UI Signal Handlers ---

# Called when an actor selection button is pressed.
# Selects the actor and shows their available actions.
func _on_actor_button_pressed(button_index: int) -> void:
	if button_index < 0 or button_index >= actor_button_actor_names.size():
		return
	var actor_name: String = str(actor_button_actor_names[button_index])
	if actor_name.is_empty():
		return
	selected_actor_name = actor_name
	_hide_target_buttons()
	_show_action_buttons_for_actor(actor_name)
	navigation_cursor = 0
	_apply_navigation_visuals()

# Called when an action selection button is pressed.
# Selects the action and shows available targets.
func _on_action_button_pressed(button_index: int) -> void:
	if selected_actor_name.is_empty() or button_index < 0 or button_index >= action_button_slots.size():
		return
	var action_slot: int = int(action_button_slots[button_index])
	if action_slot < 0:
		return
	selected_action_slot = action_slot
	_show_target_buttons_for_actor(selected_actor_name)
	navigation_cursor = 0
	_apply_navigation_visuals()

# Called when a target selection button is pressed.
# Executes the selected action on the target and resets the flow.
func _on_target_button_pressed(button_index: int) -> void:
	if selected_actor_name.is_empty() or selected_action_slot < 0:
		return
	if button_index < 0 or button_index >= target_button_target_names.size():
		return
	var target_name: String = str(target_button_target_names[button_index])
	if target_name.is_empty():
		return

	_execute_action(selected_actor_name, selected_action_slot, target_name)
	_refresh_selection_flow()


func _move_navigation_cursor(direction: int) -> void:
	if direction == 0:
		return

	var option_indices: Array = _get_current_navigation_option_indices()
	if option_indices.is_empty():
		navigation_cursor = 0
		_apply_navigation_visuals()
		return

	navigation_cursor = wrapi(navigation_cursor + direction, 0, option_indices.size())
	_apply_navigation_visuals()


func _confirm_navigation_selection() -> void:
	var option_indices: Array = _get_current_navigation_option_indices()
	if option_indices.is_empty():
		return

	navigation_cursor = clampi(navigation_cursor, 0, option_indices.size() - 1)
	var button_index: int = int(option_indices[navigation_cursor])

	match _get_navigation_stage():
		0:
			_on_actor_button_pressed(button_index)
		1:
			_on_action_button_pressed(button_index)
		2:
			_on_target_button_pressed(button_index)


func _back_navigation_stage() -> void:
	var stage: int = _get_navigation_stage()
	if stage == 2:
		selected_action_slot = -1
		_hide_target_buttons()
		navigation_cursor = 0
		_apply_navigation_visuals()
		return

	if stage == 1:
		selected_actor_name = ""
		selected_action_slot = -1
		_hide_action_buttons()
		_hide_target_buttons()
		navigation_cursor = 0
		_apply_navigation_visuals()


func _get_navigation_stage() -> int:
	if selected_actor_name.is_empty():
		return 0
	if selected_action_slot < 0:
		return 1
	return 2


func _get_current_navigation_option_indices() -> Array:
	var indices: Array = []
	match _get_navigation_stage():
		0:
			for button_index in range(4):
				if str(actor_button_actor_names[button_index]).is_empty():
					continue
				var actor_button: MenuButton = actor_select_buttons[button_index]
				if actor_button != null and actor_button.visible:
					indices.append(button_index)
		1:
			for button_index in range(4):
				if int(action_button_slots[button_index]) < 0:
					continue
				var action_button: MenuButton = action_select_buttons[button_index]
				if action_button != null and action_button.visible:
					indices.append(button_index)
		2:
			for button_index in range(4):
				if str(target_button_target_names[button_index]).is_empty():
					continue
				var target_button: MenuButton = target_select_buttons[button_index]
				if target_button != null and target_button.visible:
					indices.append(button_index)
	return indices


func _apply_navigation_visuals() -> void:
	for button_index in range(4):
		var actor_button: MenuButton = actor_select_buttons[button_index]
		if actor_button != null and actor_button.visible:
			actor_button.text = _get_actor_display_name(str(actor_button_actor_names[button_index]))

		var action_button: MenuButton = action_select_buttons[button_index]
		if action_button != null and action_button.visible:
			action_button.text = str(action_button_names[button_index])

		var target_button: MenuButton = target_select_buttons[button_index]
		if target_button != null and target_button.visible:
			target_button.text = _get_actor_display_name(str(target_button_target_names[button_index]))

	var option_indices: Array = _get_current_navigation_option_indices()
	if option_indices.is_empty():
		navigation_cursor = 0
		return

	navigation_cursor = clampi(navigation_cursor, 0, option_indices.size() - 1)
	var selected_button_index: int = int(option_indices[navigation_cursor])
	var selected_label: String = ""

	match _get_navigation_stage():
		0:
			selected_label = _get_actor_display_name(str(actor_button_actor_names[selected_button_index]))
			var actor_button: MenuButton = actor_select_buttons[selected_button_index]
			if actor_button != null and actor_button.visible:
				actor_button.text = "> " + selected_label
		1:
			selected_label = str(action_button_names[selected_button_index])
			var action_button: MenuButton = action_select_buttons[selected_button_index]
			if action_button != null and action_button.visible:
				action_button.text = "> " + selected_label
		2:
			selected_label = _get_actor_display_name(str(target_button_target_names[selected_button_index]))
			var target_button: MenuButton = target_select_buttons[selected_button_index]
			if target_button != null and target_button.visible:
				target_button.text = "> " + selected_label


# --- Core Battle Logic ---

# Executes the selected action on the target.
# Validates actor and target states, retrieves action details, and calls the actor's method.
# This function is intentionally strict about validation so UI bugs do not
# silently apply invalid actions.
func _execute_action(actor_name: String, action_slot: int, target_name: String) -> void:
	var actor_node: Node = _get_actor_by_name(actor_name)
	var actor_label: String = _get_actor_display_name(actor_name)
	if actor_node == null:
		print("No actor selected.")
		return

	if not actor_node.has_method("is_alive") or not actor_node.call("is_alive"):
		print("%s is defeated and cannot act." % actor_label)
		return

	if not actor_node.has_method("perform_action"):
		return

	if actor_node.has_method("can_use_action") and not actor_node.call("can_use_action", action_slot):
		var action_percent: float = 0.0
		if actor_node.has_method("get_action_percent"):
			action_percent = float(actor_node.call("get_action_percent"))
		var action_cost: float = 100.0
		if actor_node.has_method("get_action_cost"):
			action_cost = float(actor_node.call("get_action_cost", action_slot))
		print("%s action is %.1f%%. Need %.1f to use this action." % [actor_label, action_percent, action_cost])
		return

	var action_name: String = "Action"
	if actor_node.has_method("get_action_names"):
		var action_names: PackedStringArray = actor_node.call("get_action_names")
		if action_slot >= 0 and action_slot < action_names.size():
			action_name = action_names[action_slot]

	var target_node: Node = _get_actor_by_name(target_name)
	var target_label: String = _get_actor_display_name(target_name)
	if target_node != null and target_node.has_method("is_alive") and not target_node.call("is_alive"):
		print("%s is already defeated." % target_label)
		return

	var damage: int = int(actor_node.call("perform_action", action_slot, target_node))
	if target_node == null:
		print("%s uses %s." % [actor_label, action_name])
		return

	var target_health: int = int(target_node.get("health"))
	var target_max_health: int = int(target_node.get("max_health"))
	print("%s uses %s on %s for %d damage. HP %d/%d" % [actor_label, action_name, target_label, damage, target_health, target_max_health])


# --- Helper Functions ---

# Gets all actor names for a specific team (ally or enemy).
func _get_actor_names_by_team(is_enemy: bool) -> Array:
	var actor_names: Array = []
	for slot in ARENA_SLOTS:
		if bool(slot.get("enemy", false)) != is_enemy:
			continue
		var actor_name: String = str(slot.get("name", ""))
		if not actor_name.is_empty() and actor_nodes_by_name.has(actor_name):
			actor_names.append(actor_name)
	return actor_names

# Gets all alive actor names for a specific team.
func _get_alive_actor_names(is_enemy: bool) -> Array:
	var actor_names: Array = []
	for actor_name in _get_actor_names_by_team(is_enemy):
		var actor_node: Node = _get_actor_by_name(actor_name)
		if actor_node != null and actor_node.has_method("is_alive") and actor_node.call("is_alive"):
			actor_names.append(actor_name)
	return actor_names

# Gets opponent actor names for a given actor.
func _get_opponent_targets_for_actor(actor_name: String) -> Array:
	if actor_name.is_empty() or not actor_is_enemy_by_name.has(actor_name):
		return []
	var is_enemy: bool = bool(actor_is_enemy_by_name[actor_name])
	var opponent_names: Array = _get_alive_actor_names(not is_enemy)
	if not opponent_names.is_empty():
		return opponent_names
	return _get_actor_names_by_team(not is_enemy)

# Gets an actor node by name from the cache.
func _get_actor_by_name(actor_name: String) -> Node:
	if actor_name.is_empty() or not actor_nodes_by_name.has(actor_name):
		return null
	return actor_nodes_by_name[actor_name]

# Gets the display name for an actor, falling back to the node name.
func _get_actor_display_name(actor_name: String) -> String:
	if actor_name.is_empty():
		return ""
	if actor_display_names_by_name.has(actor_name):
		return str(actor_display_names_by_name[actor_name])
	return actor_name

# Resolves the display name from the actor's Label3D node, if available.
func _resolve_actor_display_name(actor_name: String, actor_node: Node) -> String:
	if actor_node != null:
		var label_node: Label3D = actor_node.get_node_or_null("Label3D")
		if label_node != null:
			var label_text: String = label_node.text.strip_edges()
			if not label_text.is_empty():
				return label_text
	return actor_name


# --- Configuration Loading ---

# Loads the actor configuration file, copying default to user path if necessary.
# Config precedence:
# 1) user://battle_actors.cfg (persistent editable copy)
# 2) res://Data/battle_actors.cfg (bundled default)
#
# After loading, missing keys are merged from default config so schema additions
# do not break older user files.
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

	var default_cfg := ConfigFile.new()
	if default_cfg.load(DEFAULT_CONFIG_PATH) == OK:
		if _merge_missing_default_config_values(cfg, default_cfg):
			var save_err := cfg.save(USER_CONFIG_PATH)
			if save_err != OK:
				push_warning("battle_arena: failed to save merged defaults to %s (error %d)" % [USER_CONFIG_PATH, save_err])
	return cfg


# Merges missing section/key pairs from bundled defaults into user config.
# Existing user values are never overwritten.
func _merge_missing_default_config_values(user_cfg: ConfigFile, default_cfg: ConfigFile) -> bool:
	var changed := false
	for section in default_cfg.get_sections():
		var existing_keys := {}
		for key in user_cfg.get_section_keys(section):
			existing_keys[str(key)] = true

		for key in default_cfg.get_section_keys(section):
			var key_str: String = str(key)
			if existing_keys.has(key_str):
				continue
			user_cfg.set_value(section, key_str, default_cfg.get_value(section, key_str))
			changed = true
	return changed

# Loads configuration for all actors in the arena.
# This combines static slot placement (ARENA_SLOTS) with per-character roster data.
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
			"actions":   char_data.get("actions", []),
		})
	return configs

# Loads the roster from the configuration file.
# Expected section shape:
# [character.Name] for base stats +
# [character.Name.action_slot.N] for per-slot action overrides.
func _load_roster() -> Dictionary:
	var cfg := _load_cfg()
	if cfg == null:
		return {}
	var shared_action_slots: Array = _load_shared_action_slots(cfg)
	var roster: Dictionary = {}
	for section in cfg.get_sections():
		if not section.begins_with("character."):
			continue
		if section.contains(".action_slot."):
			continue
		var char_name: String = section.substr(len("character."))
		roster[char_name] = {
			"animation": str(cfg.get_value(section, "animation", "Canin")),
			"label":     str(cfg.get_value(section, "label", char_name)),
			"max_hp":    int(cfg.get_value(section, "max_hp", 100)),
			"attack":    int(cfg.get_value(section, "attack", 10)),
			"defense":   int(cfg.get_value(section, "defense", 0)),
			"speed":     float(cfg.get_value(section, "speed", 10.0)),
			"actions":   _load_action_slots_for_character(cfg, char_name, shared_action_slots),
		}
	return roster

# Loads action slots for a specific character, using shared defaults if not defined.
# Fallback order per slot:
# character override -> shared action_slot.N -> hardcoded slot fallback.
func _load_action_slots_for_character(cfg: ConfigFile, char_name: String, shared_action_slots: Array) -> Array:
	var slots: Array = []
	for slot_index in range(4):
		var section := "character.%s.action_slot.%d" % [char_name, slot_index]
		var fallback: Dictionary = {}
		if slot_index < shared_action_slots.size() and shared_action_slots[slot_index] is Dictionary:
			fallback = shared_action_slots[slot_index]

		var default_name: String = str(fallback.get("name", "Action"))
		var default_kind: String = str(fallback.get("kind", "attack"))
		var default_cost: float = float(fallback.get("cost", 100.0))
		var default_power_scale: float = float(fallback.get("power_scale", 1.0))

		slots.append({
			"name": str(cfg.get_value(section, "name", default_name)),
			"kind": str(cfg.get_value(section, "kind", default_kind)),
			"cost": float(cfg.get_value(section, "cost", default_cost)),
			"power_scale": float(cfg.get_value(section, "power_scale", default_power_scale)),
		})
	return slots

# Loads shared action slots from the configuration file.
# Shared slots provide baseline names/types/costs that each character can reuse.
func _load_shared_action_slots(cfg: ConfigFile) -> Array:
	var slots: Array = []
	for slot_index in range(4):
		var section := "action_slot.%d" % slot_index
		var fallback: Dictionary = DEFAULT_ACTION_SLOT_FALLBACKS[slot_index]
		slots.append({
			"name": str(cfg.get_value(section, "name", fallback.get("name", "Action"))),
			"kind": str(cfg.get_value(section, "kind", fallback.get("kind", "attack"))),
			"cost": float(cfg.get_value(section, "cost", fallback.get("cost", 100.0))),
			"power_scale": float(cfg.get_value(section, "power_scale", fallback.get("power_scale", 1.0))),
		})
	return slots


# --- Actor Spawning & Setup ---

# Spawns all actors in the arena based on the configuration.
# Uses loaded templates so changes in config reflect immediately on next run.
func _spawn_arena_actors() -> void:
	for config in _load_actor_configs():
		_spawn_actor_from_template(config)

# Spawns a single actor from a configuration template.
# Any previous node with the same slot name is replaced to keep the tree clean.
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
		float(config.get("speed", 10.0)),
		config.get("actions", [])
	)

# Configures the visual aspects of an actor (animation and label).
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

# Prepares an actor for battle by configuring its stats and actions.
# Behavior is delegated to battle_actor.gd methods when available.
func _prepare_actor(actor: Node, max_hp: int, actor_attack: int, actor_defense: int, actor_speed: float, actor_actions: Array) -> void:
	if actor == null:
		return

	if actor.get_script() != BATTLE_ACTOR_SCRIPT:
		actor.set_script(BATTLE_ACTOR_SCRIPT)

	if actor.has_method("configure_for_battle"):
		actor.call("configure_for_battle", max_hp, actor_attack, actor_defense)

	if actor.has_method("configure_actions"):
		actor.call("configure_actions", actor_actions)

	if actor.has_method("set"):
		actor.set("speed", max(0.0, actor_speed))


# --- Quick Test Function ---

# Executes an action for Actor_Friend1 on Actor_Enemy1.
# Intended for testing purposes only.
func _actor_friend1_uses_action_on_enemy1(action_slot: int) -> void:
	_execute_action("Actor_Friend1", action_slot, "Actor_Enemy1")
	_refresh_selection_flow()