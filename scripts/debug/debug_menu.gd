class_name DebugMenu
extends CanvasLayer
## Developer tools, only present in debug builds (removed from release exports).
## F1 toggles the panel; F2 spawns an enemy at a random walkable point.
## "God mode" makes the player take no damage (HealthComponent.god_mode).
## The player's final core stats (CharacterStats) are listed at the top.
## "Fog of war" turns the level's FogOfWar on and off.
## The panel also edits the player's appearance and weapon live (not saved),
## opens the Outfits panel (OutfitMenu) to dress the player,
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
## The player's weapon, swapped by the weapon option.
@export var player_weapon: WeaponComponent
## Weapons offered in the weapon option.
@export var player_weapons: Array[WeaponDefinition] = []
## Has generate_level(seed) (the Main scene).
@export var main: Node

@onready var _panel: Control = %Panel
@onready var _scroll: ScrollContainer = $Panel/Scroll
@onready var _count_label: Label = %EnemyCount
@onready var _stats_label: Label = %PlayerStats
@onready var _outfit_menu: OutfitMenu = $OutfitMenu


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
	_outfit_menu.appearance_component = player_appearance
	%OutfitsButton.pressed.connect(_toggle_outfits)
	_setup_weapon_control()
	_setup_level_controls()
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
			_outfit_menu.close()
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
	return "HP %d   Stamina %d (+%d/s)
Damage x%.2f   Speed x%.2f
Armor %d (-%d%% damage)" % [
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


## Opens / closes the Outfits panel, just left of this panel (which grows
## with its contents).
func _toggle_outfits() -> void:
	_outfit_menu.toggle()
	if _outfit_menu.visible:
		_outfit_menu.reset_size()
		_outfit_menu.global_position = Vector2(
			_panel.global_position.x - _outfit_menu.size.x - 12.0, _panel.global_position.y)


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


## Equips `player_weapons[index]` on the player.
func equip_player_weapon(index: int) -> void:
	if player_weapon and index >= 0 and index < player_weapons.size():
		player_weapon.equip(player_weapons[index])


func _setup_weapon_control() -> void:
	var option: OptionButton = %WeaponOption
	option.clear()
	for w in player_weapons:
		option.add_item(w.display_name)
	if player_weapon:
		option.select(maxi(player_weapons.find(player_weapon.current), 0))
	option.item_selected.connect(equip_player_weapon)


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
	if _outfit_menu.visible:
		_outfit_menu.sync()  # A body change swaps the outfit's cut.


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
