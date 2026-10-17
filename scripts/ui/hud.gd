class_name HUD
extends CanvasLayer
## Player-facing interface. Only listens to gameplay signals; never drives gameplay.

@export var player_health: HealthComponent

@onready var _health_bar: ProgressBar = %HealthBar
@onready var _health_label: Label = %HealthLabel
@onready var _defeated_label: Label = %DefeatedLabel
@onready var _restart_hint: Label = %RestartHint
@onready var _level_label: Label = %LevelLabel


func _ready() -> void:
	_defeated_label.hide()
	_restart_hint.hide()
	if player_health:
		bind_player_health(player_health)
	GameRun.current().level_changed.connect(_on_level_changed)
	_on_level_changed(GameRun.current().level)


func bind_player_health(health: HealthComponent) -> void:
	player_health = health
	health.health_changed.connect(_on_player_health_changed)
	health.died.connect(_on_player_died)
	_on_player_health_changed(health.current_health, health.max_health)


func _on_player_health_changed(current: int, maximum: int) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current
	_health_label.text = "HP %d / %d" % [current, maximum]
	_defeated_label.visible = current <= 0
	_restart_hint.visible = current <= 0


func _on_level_changed(level: int) -> void:
	_level_label.text = "Level %d" % level


func _on_player_died() -> void:
	_defeated_label.show()
	_restart_hint.show()
