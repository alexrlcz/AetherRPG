class_name HUD
extends CanvasLayer
## Player-facing interface. Only listens to gameplay signals; never drives gameplay.

@export var player_health: HealthComponent
@export var player_stamina: StaminaComponent

@onready var _health_bar: ProgressBar = %HealthBar
@onready var _health_label: Label = %HealthLabel
@onready var _stamina_bar: ProgressBar = %StaminaBar
@onready var _defeated_label: Label = %DefeatedLabel
@onready var _restart_hint: Label = %RestartHint
@onready var _level_label: Label = %LevelLabel
@onready var _boss_panel: Control = %BossPanel
@onready var _boss_name: Label = %BossName
@onready var _boss_bar: ProgressBar = %BossBar

## The boss whose bar is shown (or waiting to be shown).
var _boss: EnemyController


func _ready() -> void:
	_defeated_label.hide()
	_restart_hint.hide()
	_boss_panel.hide()
	if player_health:
		bind_player_health(player_health)
	if player_stamina:
		bind_player_stamina(player_stamina)
	GameRun.current().level_changed.connect(_on_level_changed)
	_on_level_changed(GameRun.current().level)


func bind_player_health(health: HealthComponent) -> void:
	player_health = health
	health.health_changed.connect(_on_player_health_changed)
	health.died.connect(_on_player_died)
	_on_player_health_changed(health.current_health, health.max_health)


func bind_player_stamina(stamina: StaminaComponent) -> void:
	player_stamina = stamina
	stamina.stamina_changed.connect(_on_player_stamina_changed)
	stamina.exhausted.connect(_refresh_stamina_tint)
	stamina.recovered.connect(_refresh_stamina_tint)
	_on_player_stamina_changed(stamina.current_stamina, stamina.max_stamina)
	_refresh_stamina_tint()


func _on_player_stamina_changed(current: float, maximum: float) -> void:
	_stamina_bar.max_value = maximum
	_stamina_bar.value = current


## Dimmed while exhausted: no attacks, dodges or sprint until it brightens.
func _refresh_stamina_tint() -> void:
	_stamina_bar.modulate = Color(0.55, 0.5, 0.45) if player_stamina.is_exhausted else Color.WHITE


func _on_player_health_changed(current: int, maximum: int) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current
	_health_label.text = "HP %d / %d" % [current, maximum]
	_defeated_label.visible = current <= 0
	_restart_hint.visible = current <= 0


func _on_level_changed(level: int) -> void:
	_level_label.text = GameRun.level_title(level)


## Shows `boss`'s health bar titled `title` once it starts fighting (an
## intro beat: the bar fades in when the boss first notices the player).
func show_boss(boss: EnemyController, title: String) -> void:
	_boss = boss
	_boss_panel.hide()
	_boss_name.text = title
	_on_boss_health_changed(boss.health.current_health, boss.health.max_health)
	boss.health.health_changed.connect(_on_boss_health_changed)
	boss.health.died.connect(_on_boss_died.bind(boss, title))
	boss.state_changed.connect(_on_boss_state_changed.bind(boss))
	boss.tree_exiting.connect(func() -> void:
		if _boss == boss:
			_boss = null
			_boss_panel.hide())


func is_boss_bar_shown() -> bool:
	return _boss_panel.visible


func _on_boss_state_changed(state: EnemyController.State, boss: EnemyController) -> void:
	if boss != _boss or _boss_panel.visible or state == EnemyController.State.IDLE:
		return
	_boss_panel.modulate.a = 0.0
	_boss_panel.show()
	create_tween().tween_property(_boss_panel, "modulate:a", 1.0, 0.6)


func _on_boss_health_changed(current: int, maximum: int) -> void:
	_boss_bar.max_value = maximum
	_boss_bar.value = current


func _on_boss_died(boss: EnemyController, title: String) -> void:
	if boss != _boss:
		return
	_boss_panel.show()
	_boss_panel.modulate.a = 1.0
	_boss_name.text = "%s falls — the gate opens" % title
	var tween := create_tween()
	tween.tween_interval(2.5)
	tween.tween_property(_boss_panel, "modulate:a", 0.0, 1.0)
	tween.tween_callback(func() -> void:
		if _boss == boss:
			_boss_panel.hide())


func _on_player_died() -> void:
	_defeated_label.show()
	_restart_hint.show()
