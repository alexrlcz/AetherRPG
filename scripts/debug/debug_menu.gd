class_name DebugMenu
extends CanvasLayer
## Developer tools, only present in debug builds (removed from release exports).
## F1 toggles the panel; F2 spawns an enemy at a random walkable point.

@export var spawner: EnemySpawner
@export var player_health: HealthComponent
## Node whose children are the enemies (counted / killed by the buttons).
@export var enemies: Node

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
