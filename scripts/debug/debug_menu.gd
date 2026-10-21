class_name DebugMenu
extends CanvasLayer
## Developer tools, only present in debug builds (removed from release exports).
## F1 toggles the panel; F2 spawns an enemy at a random walkable point.
## "God mode" makes the player take no damage (HealthComponent.god_mode).
## The player's final core stats (CharacterStats) are listed at the top.
## "Fog of war" turns the level's FogOfWar on and off.
## The panel also edits the player's appearance live (not saved), opens the
## Equipment panel (EquipmentMenu) to equip any item in any slot,
## generates levels from a seed (Main.generate_level()) and plays the
## hand-made maps in LevelPool.MAPS_DIR (Main.play_map()).

@export var spawner: EnemySpawner
@export var player_health: HealthComponent
## Shown in the stats readout (optional).
@export var player_stats: CharacterStats
## Toggled by the "Fog of war" checkbox (optional).
@export var fog: FogOfWar
## Node whose children are the enemies (counted / killed by the buttons).
@export var enemies: Node
## Edited by the appearance controls; works on a copy of its resource.
@export var player_appearance: AppearanceComponent
## Edited by the Equipment panel.
@export var player_equipment: Equipment
## Scaled by the UI size sliders (optional).
@export var hud: HUD
@export var inventory_screen: InventoryScreen
## Has generate_level(seed) (the Main scene).
@export var main: Node

@onready var _panel: Control = %Panel
@onready var _scroll: ScrollContainer = $Panel/Scroll
@onready var _count_label: Label = %EnemyCount
@onready var _stats_label: Label = %PlayerStats
@onready var _equipment_menu: EquipmentMenu = $EquipmentMenu


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	_panel.hide()
	%SpawnButton.pressed.connect(spawn_enemy)
	%HealButton.pressed.connect(heal_player)
	%GodModeCheck.set_pressed_no_signal(player_health.god_mode)
	%GodModeCheck.toggled.connect(set_god_mode)
	%KillButton.pressed.connect(kill_all_enemies)
	%FogCheck.disabled = fog == null
	%FogCheck.set_pressed_no_signal(fog != null and fog.enabled)
	%FogCheck.toggled.connect(set_fog)
	_setup_appearance_controls()
	_equipment_menu.equipment = player_equipment
	%EquipmentButton.pressed.connect(_toggle_equipment)
	_setup_level_controls()
	_setup_ui_scale_controls()
	_setup_map_controls()
	# Taller than the window (small windows): scroll instead of running off it.
	get_viewport().size_changed.connect(fit_to_screen)
	fit_to_screen()
	# Mouse-only: a focused button would swallow Space (jump) as ui_accept.
	for button in _panel.find_children("*", "BaseButton", true, false):
		(button as BaseButton).focus_mode = Control.FOCUS_NONE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_menu"):
		_panel.visible = not _panel.visible
		fit_to_screen()
		if not _panel.visible:
			_equipment_menu.close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_spawn_enemy"):
		spawn_enemy()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _panel.visible:
		_count_label.text = "Enemies alive: %d" % _alive_enemies().size()
		_stats_label.text = stats_text(player_stats)


## Readout of a character's final core stats.
static func stats_text(stats: CharacterStats) -> String:
	if stats == null:
		return "Player stats: -"
	var armor := stats.get_value(CharacterStats.Stat.ARMOR)
	return "HP %d   Stamina %d (+%d/s)\nDamage x%.2f   Speed x%.2f\nArmor %d (-%d%% damage)" % [
		roundi(stats.get_value(CharacterStats.Stat.MAX_HEALTH)),
		roundi(stats.get_value(CharacterStats.Stat.MAX_STAMINA)),
		roundi(stats.get_value(CharacterStats.Stat.STAMINA_REGEN)),
		stats.get_value(CharacterStats.Stat.DAMAGE),
		stats.get_value(CharacterStats.Stat.MOVE_SPEED),
		roundi(armor), roundi(CharacterStats.armor_reduction(armor) * 100.0)]


## Caps the panel's height to the window (its rows scroll past that).
func fit_to_screen() -> void:
	var content := _scroll.get_child(0) as Control
	var margins := _panel.get_theme_stylebox(&"panel").get_minimum_size().y
	var room := get_viewport().get_visible_rect().size.y - _panel.offset_top - margins - 16.0
	_scroll.custom_minimum_size = Vector2(0.0, minf(content.get_combined_minimum_size().y, room))
	_panel.reset_size()


## UI size sliders (under the fog checkbox): the HUD's health / stamina
## panel, this menu (and its Equipment panel), the inventory window.
func _setup_ui_scale_controls() -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	var vbox := %FogCheck.get_parent() as Control
	vbox.add_child(grid)
	vbox.move_child(grid, %FogCheck.get_index() + 1)
	for row: Array in [["Health/stamina size", func(v: float) -> void: if hud: hud.set_player_panel_scale(v)],
			["Debug menu size", _set_menu_scale],
			["Inventory size", func(v: float) -> void: if inventory_screen: inventory_screen.set_ui_scale(v)]]:
		var label := Label.new()
		label.text = row[0]
		grid.add_child(label)
		var slider := HSlider.new()
		slider.min_value = 0.5
		slider.max_value = 2.0
		slider.step = 0.05
		slider.value = 1.0
		slider.custom_minimum_size = Vector2(110, 0)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.focus_mode = Control.FOCUS_NONE
		if row[1] == _set_menu_scale:
			# This menu moves under the cursor while it scales: apply only
			# when the drag ends (clicks on the track still apply at once).
			slider.drag_ended.connect(func(_changed: bool) -> void: _set_menu_scale(slider.value))
			slider.value_changed.connect(func(v: float) -> void:
				if not slider.has_meta(&"dragging"):
					_set_menu_scale(v))
			slider.drag_started.connect(func() -> void: slider.set_meta(&"dragging", true))
			slider.drag_ended.connect(func(_changed: bool) -> void: slider.remove_meta(&"dragging"))
		else:
			slider.value_changed.connect(row[1])
		grid.add_child(slider)


## Scales this panel from its top-right corner, and the Equipment panel.
func _set_menu_scale(value: float) -> void:
	_panel.pivot_offset = Vector2(_panel.size.x, 0.0)
	_panel.scale = Vector2.ONE * value
	_equipment_menu.scale = Vector2.ONE * value
	if _equipment_menu.visible:
		_toggle_equipment()
		_toggle_equipment()


## Opens / closes the Equipment panel, just left of this panel (which grows
## with its contents).
func _toggle_equipment() -> void:
	_equipment_menu.toggle()
	if _equipment_menu.visible:
		_equipment_menu.reset_size()
		_equipment_menu.global_position = Vector2(
			_panel.global_position.x - _equipment_menu.size.x * _equipment_menu.scale.x - 12.0,
			_panel.global_position.y)


func spawn_enemy() -> Node3D:
	return spawner.spawn_random()


func heal_player() -> void:
	player_health.heal(player_health.max_health)


## Player takes no damage while `on`.
func set_god_mode(on: bool) -> void:
	player_health.god_mode = on
	%GodModeCheck.set_pressed_no_signal(on)


func set_fog(on: bool) -> void:
	if fog:
		fog.enabled = on
	%FogCheck.set_pressed_no_signal(on)


func kill_all_enemies() -> void:
	for health in _alive_enemies():
		health.take_damage(health.current_health)


func _alive_enemies() -> Array[HealthComponent]:
	var result: Array[HealthComponent] = []
	for enemy in enemies.get_children():
		var health := enemy.get_node_or_null("HealthComponent") as HealthComponent
		if health and not health.is_dead:
			result.append(health)
	return result


## Replaces the level with the one generated from `level_seed`, populated
## for the level in the level box.
func generate_level(level_seed: int) -> void:
	if main and main.has_method(&"generate_level"):
		(%SeedSpin as SpinBox).set_value_no_signal(level_seed)
		var level := int((%LevelSpin as SpinBox).value)
		GameRun.current().jump_to(level)  # HUD and the gate follow the jump.
		main.generate_level(level_seed, level)


func _setup_level_controls() -> void:
	var spin: SpinBox = %SeedSpin
	var line := spin.get_line_edit()
	var level_line := (%LevelSpin as SpinBox).get_line_edit()
	# Typing a number must not keep WASD / Space from reaching the game.
	for edit in [line, level_line]:
		edit.text_submitted.connect(func(_text: String) -> void: edit.release_focus())
	%GenerateButton.pressed.connect(func() -> void:
		line.release_focus()
		level_line.release_focus()
		generate_level(int(spin.value)))
	%RandomLevelButton.pressed.connect(func() -> void:
		line.release_focus()
		level_line.release_focus()
		generate_level(randi_range(1, 999999)))


## Plays the map `path` with the seed and level in the boxes.
func play_map(path: String) -> void:
	if main and main.has_method(&"play_map"):
		var level := int((%LevelSpin as SpinBox).value)
		GameRun.current().jump_to(level)
		main.play_map(path, int((%SeedSpin as SpinBox).value), level)


func _setup_map_controls() -> void:
	var option: OptionButton = %MapOption
	option.clear()
	for path in LevelPool.map_paths():
		option.add_item(path.get_file().get_basename())
		option.set_item_metadata(option.item_count - 1, path)
	%PlayMapButton.disabled = option.item_count == 0
	%PlayMapButton.pressed.connect(func() -> void:
		if option.selected >= 0:
			play_map(option.get_item_metadata(option.selected)))


# --- Appearance -------------------------------------------------------------

func _setup_appearance_controls() -> void:
	# Edit a copy so the shared .tres on disk is never modified.
	player_appearance.appearance = player_appearance.appearance.duplicate()
	_fill(%BodyOption, CharacterAppearance.Body.keys())
	_fill(%SkinOption, CharacterAppearance.SkinTexture.keys())
	_fill(%HairOption, CharacterAppearance.HAIR_STYLES)
	_fill(%BrowOption, CharacterAppearance.EYEBROW_STYLES)
	_sync_controls()
	%BodyOption.item_selected.connect(func(i: int) -> void: _edit(func(a: CharacterAppearance) -> void: a.body = i as CharacterAppearance.Body))
	%SkinOption.item_selected.connect(func(i: int) -> void: _edit(func(a: CharacterAppearance) -> void: a.skin_texture = i as CharacterAppearance.SkinTexture))
	%SkinTint.color_changed.connect(func(c: Color) -> void: _edit(func(a: CharacterAppearance) -> void: a.skin_tint = c))
	%HairOption.item_selected.connect(func(i: int) -> void: _edit(func(a: CharacterAppearance) -> void: a.hair_style = CharacterAppearance.HAIR_STYLES[i]))
	%HairColor.color_changed.connect(func(c: Color) -> void: _edit(func(a: CharacterAppearance) -> void: a.hair_color = c))
	%BrowOption.item_selected.connect(func(i: int) -> void: _edit(func(a: CharacterAppearance) -> void: a.eyebrows = CharacterAppearance.EYEBROW_STYLES[i]))
	%BeardCheck.toggled.connect(func(on: bool) -> void: _edit(func(a: CharacterAppearance) -> void: a.beard = on))
	%RandomizeButton.pressed.connect(randomize_appearance)


## Applies a random look to the player.
func randomize_appearance() -> void:
	var a := player_appearance.appearance
	a.body = (randi() % CharacterAppearance.Body.size()) as CharacterAppearance.Body
	a.skin_texture = (randi() % CharacterAppearance.SkinTexture.size()) as CharacterAppearance.SkinTexture
	a.skin_tint = Color.from_hsv(randf_range(0.0, 0.1), randf_range(0.0, 0.25), randf_range(0.8, 1.0))
	a.hair_style = CharacterAppearance.HAIR_STYLES[randi() % CharacterAppearance.HAIR_STYLES.size()]
	a.hair_color = Color.from_hsv(randf_range(0.0, 0.12), randf_range(0.3, 0.9), randf_range(0.1, 0.9))
	a.eyebrows = CharacterAppearance.EYEBROW_STYLES[1 + randi() % (CharacterAppearance.EYEBROW_STYLES.size() - 1)]
	a.beard = a.body == CharacterAppearance.Body.MALE and randf() < 0.5
	player_appearance.apply(a)
	_sync_controls()


func _edit(change: Callable) -> void:
	change.call(player_appearance.appearance)
	player_appearance.apply(player_appearance.appearance)


func _sync_controls() -> void:
	var a := player_appearance.appearance
	%BodyOption.select(a.body)
	%SkinOption.select(a.skin_texture)
	%SkinTint.color = a.skin_tint
	%HairOption.select(maxi(CharacterAppearance.HAIR_STYLES.find(a.hair_style), 0))
	%HairColor.color = a.hair_color
	%BrowOption.select(maxi(CharacterAppearance.EYEBROW_STYLES.find(a.eyebrows), 0))
	%BeardCheck.set_pressed_no_signal(a.beard)


static func _fill(option: OptionButton, labels: Array) -> void:
	option.clear()
	for label in labels:
		option.add_item(str(label).capitalize())
