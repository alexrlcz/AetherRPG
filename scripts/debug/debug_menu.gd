class_name DebugMenu
extends CanvasLayer
## Developer tools, only present in debug builds (removed from release exports).
## F1 toggles the panel; F2 spawns an enemy at a random walkable point.
## The panel also edits the player's appearance and weapon live (not saved)
## and generates levels from a seed (Main.generate_level()).

@export var spawner: EnemySpawner
@export var player_health: HealthComponent
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
@onready var _count_label: Label = %EnemyCount


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	_panel.hide()
	%SpawnButton.pressed.connect(spawn_enemy)
	%HealButton.pressed.connect(heal_player)
	%KillButton.pressed.connect(kill_all_enemies)
	_setup_appearance_controls()
	_setup_weapon_control()
	_setup_level_controls()
	# Mouse-only: a focused button would swallow Space (jump) as ui_accept.
	for button in _panel.find_children("*", "BaseButton", true, false):
		(button as BaseButton).focus_mode = Control.FOCUS_NONE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_menu"):
		_panel.visible = not _panel.visible
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_spawn_enemy"):
		spawn_enemy()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _panel.visible:
		_count_label.text = "Enemies alive: %d" % _alive_enemies().size()


func spawn_enemy() -> Node3D:
	return spawner.spawn_random()


func heal_player() -> void:
	player_health.heal(player_health.max_health)


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
